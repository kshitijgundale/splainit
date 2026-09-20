#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Security/Security.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <limits.h>
#include <stdatomic.h>
#import "resolver.h"
#import "visual.h"

// This bridge keeps AppKit and Core Foundation ownership on the Objective-C side.
// The caller owns each returned UTF-8 buffer and must free it with splainit_free.
static char *encode(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return strdup("{}");
    char *result = malloc(data.length + 1);
    if (!result) return NULL;
    memcpy(result, data.bytes, data.length);
    result[data.length] = 0;
    return result;
}

static NSDictionary *reply(NSString *status, NSString *detail, NSString *text) {
    NSMutableDictionary *result = [@{ @"status": status ?: @"failed", @"detail": detail ?: @"", @"text": text ?: @"",
        @"verification": @"none", @"confidence": NSNull.null } mutableCopy];
    if ([status isEqualToString:@"permission_required"])
        result[@"permission"] = @{ @"kind": @"accessibility", @"state": @"not_granted" };
    return result;
}

char *splainit_frontmost(void) {
    @autoreleasepool {
        NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (!app) return encode(@{ @"pid": @0, @"source_app": @"", @"bundle_id": @"" });
        return encode(@{
            @"pid": @(app.processIdentifier),
            @"source_app": app.localizedName ?: @"",
            @"bundle_id": app.bundleIdentifier ?: @""
        });
    }
}

bool splainit_accessibility_granted(void) {
    return AXIsProcessTrusted();
}

bool splainit_request_screen_recording(void) {
    return CGRequestScreenCaptureAccess();
}

bool splainit_request_accessibility(void) {
    @autoreleasepool {
        NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
        return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
}

static _Atomic(uint64_t) captureInvocation = 0;
@class SplainitAXProvider;
static NSLock *visualLock;
static SplainitAXProvider *visualSource;
static void initializeVisualLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ visualLock = [NSLock new]; });
}
void splainit_set_invocation(uint64_t invocation) {
    atomic_store(&captureInvocation, invocation);
    initializeVisualLock();
    [visualLock lock]; visualSource = nil; [visualLock unlock];
}

@interface SplainitAXProvider : NSObject <SplainitSemanticProvider> {
    AXUIElementRef app;
    AXUIElementRef element;
    AXUIElementRef window;
    pid_t pid;
    uint64_t invocation;
    NSTimeInterval deadline;
    NSDictionary *initialFailure;
    CGRect frozenWindow;
    NSDictionary *frozenRange;
    CGWindowID sourceWindowID;
}
- (instancetype)initWithPid:(pid_t)source invocation:(uint64_t)generation;
- (NSDictionary *)geometry:(NSDictionary *)range;
- (NSDictionary *)ocr:(NSArray<NSValue *> *)regions method:(NSString *)method;
- (NSDictionary *)drag;
- (NSDictionary *)cancelled;
- (BOOL)canOfferDrag;
@end

@implementation SplainitAXProvider
- (NSDictionary *)budget {
    if (atomic_load(&captureInvocation) != invocation)
        return reply(@"cancelled", @"Capture was superseded", nil);
    if (NSProcessInfo.processInfo.systemUptime >= deadline)
        return reply(@"timed_out", @"Semantic capture exceeded two seconds", nil);
    return nil;
}
- (AXError)attribute:(CFStringRef)name of:(AXUIElementRef)target value:(CFTypeRef *)value {
    if ([self budget]) return kAXErrorCannotComplete;
    AXUIElementSetMessagingTimeout(target, fmax(0.001, fmin(0.5, deadline - NSProcessInfo.processInfo.systemUptime)));
    return AXUIElementCopyAttributeValue(target, name, value);
}
- (NSDictionary *)failureForError:(AXError)error detail:(NSString *)detail {
    NSDictionary *budget = [self budget];
    if (budget) return budget;
    return reply(error == kAXErrorCannotComplete ? @"timed_out" : @"blocked", detail, nil);
}
- (instancetype)initWithPid:(pid_t)source invocation:(uint64_t)generation {
    if (!(self = [super init])) return nil;
    pid = source;
    invocation = generation;
    deadline = NSProcessInfo.processInfo.systemUptime + 2.0;
    if (pid <= 0) { initialFailure = reply(@"blocked", @"Source process is unidentified", nil); return self; }
    if (!AXIsProcessTrusted()) { initialFailure = reply(@"permission_required", @"Accessibility access is disabled", nil); return self; }
    NSRunningApplication *running = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSArray *excluded = [NSUserDefaults.standardUserDefaults arrayForKey:@"ExcludedApps"] ?: @[];
    if (!running.bundleIdentifier.length || [excluded containsObject:running.bundleIdentifier] ||
        [running.bundleIdentifier isEqualToString:@"app.splainit.desktop"]) {
        initialFailure = reply(@"blocked", @"Source application is excluded or unidentified", nil); return self;
    }
    if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != pid) {
        initialFailure = reply(@"failed", @"Source app lost focus before capture", nil); return self;
    }
    app = AXUIElementCreateApplication(pid);
    CFTypeRef value = NULL;
    AXError error = [self attribute:kAXFocusedUIElementAttribute of:app value:&value];
    if (error != kAXErrorSuccess || !value || CFGetTypeID(value) != AXUIElementGetTypeID()) {
        if (value) CFRelease(value);
        initialFailure = [self failureForError:error detail:@"Cannot establish the focused source element"]; return self;
    }
    element = (AXUIElementRef)value;
    value = NULL;
    error = [self attribute:kAXFocusedWindowAttribute of:app value:&value];
    if (error != kAXErrorSuccess || !value || CFGetTypeID(value) != AXUIElementGetTypeID()) {
        if (value) CFRelease(value);
        initialFailure = [self failureForError:error detail:@"Cannot establish the focused source window"]; return self;
    }
    window = (AXUIElementRef)value;
    value = NULL;
    error = [self attribute:kAXWindowAttribute of:element value:&value];
    BOOL sameWindow = error == kAXErrorSuccess && value && CFEqual(window, value);
    if (value) CFRelease(value);
    if (!sameWindow && !CFEqual(element, window)) {
        initialFailure = [self failureForError:error detail:@"Focused element does not belong to the active window"]; return self;
    }
    initialFailure = [self checkSafety];
    return self;
}
- (NSDictionary *)checkSafety {
    NSDictionary *failure = nil;
    CFTypeRef value = NULL;
    AXError error;
    // Check ancestry without reading values/text. Missing safety evidence fails closed.
    AXUIElementRef current = (AXUIElementRef)CFRetain(element);
    BOOL established = NO;
    for (int depth = 0; depth < 32; depth++) {
        CFTypeRef role = NULL, subrole = NULL, protected = NULL;
        error = [self attribute:kAXRoleAttribute of:current value:&role];
        if (error != kAXErrorSuccess || !role || CFGetTypeID(role) != CFStringGetTypeID()) {
            if (role) CFRelease(role);
            failure = [self failureForError:error detail:@"Cannot establish secure-field safety"]; break;
        }
        AXError subError = [self attribute:kAXSubroleAttribute of:current value:&subrole];
        AXError protectedError = [self attribute:CFSTR("AXProtectedContent") of:current value:&protected];
        BOOL secure = [(__bridge id)role isEqual:@"AXSecureTextField"] ||
            (subrole && CFGetTypeID(subrole) == CFStringGetTypeID() && [(__bridge id)subrole isEqual:@"AXSecureTextField"]) ||
            (protected && CFGetTypeID(protected) == CFBooleanGetTypeID() && CFBooleanGetValue(protected));
        BOOL root = [(__bridge id)role isEqual:@"AXWindow"] || [(__bridge id)role isEqual:@"AXApplication"];
        CFRelease(role);
        if (subrole) CFRelease(subrole);
        if (protected) CFRelease(protected);
        if (secure) { failure = reply(@"blocked", @"Secure text field", nil); break; }
        if (subError == kAXErrorCannotComplete || protectedError == kAXErrorCannotComplete) {
            failure = [self failureForError:kAXErrorCannotComplete detail:@"Secure-field check timed out"]; break;
        }
        if ((subError != kAXErrorSuccess && subError != kAXErrorAttributeUnsupported && subError != kAXErrorNoValue) ||
            (protectedError != kAXErrorSuccess && protectedError != kAXErrorAttributeUnsupported && protectedError != kAXErrorNoValue)) {
            failure = reply(@"blocked", @"Secure-field safety could not be established", nil); break;
        }
        if (root) { established = YES; break; }
        value = NULL;
        error = [self attribute:kAXParentAttribute of:current value:&value];
        if (error != kAXErrorSuccess || !value || CFGetTypeID(value) != AXUIElementGetTypeID()) {
            if (value) CFRelease(value);
            failure = [self failureForError:error detail:@"Cannot establish source ancestry"]; break;
        }
        CFRelease(current);
        current = (AXUIElementRef)value;
    }
    CFRelease(current);
    if (!established && !failure) failure = reply(@"blocked", @"Source ancestry exceeds safety limit", nil);
    return failure ?: [self budget];
}
- (NSDictionary *)cancelled {
    return atomic_load(&captureInvocation) == invocation ? nil : reply(@"cancelled", @"Capture was superseded", nil);
}
- (BOOL)rectOf:(AXUIElementRef)target result:(CGRect *)rect {
    CFTypeRef position = NULL, size = NULL;
    AXError p = [self attribute:kAXPositionAttribute of:target value:&position];
    AXError s = [self attribute:kAXSizeAttribute of:target value:&size];
    CGPoint origin; CGSize dimensions;
    BOOL valid = p == kAXErrorSuccess && s == kAXErrorSuccess && position && size &&
        CFGetTypeID(position) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID() &&
        AXValueGetValue(position, kAXValueCGPointType, &origin) && AXValueGetValue(size, kAXValueCGSizeType, &dimensions);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    if (valid) *rect = (CGRect){origin, dimensions};
    return valid;
}
- (NSArray *)displays {
    CGDirectDisplayID ids[32]; uint32_t count = 0;
    if (CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        CGRect bounds = CGDisplayBounds(ids[i]);
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(ids[i]);
        double scale = mode && bounds.size.width > 0 ? CGDisplayModeGetPixelWidth(mode) / bounds.size.width : 0;
        if (mode) CGDisplayModeRelease(mode);
        [result addObject:@{ @"bounds": [NSValue valueWithRect:bounds], @"scale": @(scale) }];
    }
    return result;
}
- (NSDictionary *)validateRegions:(NSArray<NSValue *> *)regions {
    NSDictionary *invalid = [self validate];
    if (invalid) return invalid;
    CGRect currentWindow;
    if (![self rectOf:window result:&currentWindow]) return [self budget] ?: reply(@"unavailable", @"Source window bounds are unavailable", nil);
    if (!CGRectIsEmpty(frozenWindow) && !CGRectEqualToRect(currentWindow, frozenWindow))
        return reply(@"failed", @"Source window moved; select again", nil);
    frozenWindow = currentWindow;
    if (frozenRange) {
        NSDictionary *selection = [self selectedRange];
        if (![selection[@"ax_range"] isEqual:frozenRange])
            return [self budget] ?: reply(@"failed", @"Selection changed before image acquisition", nil);
    }
    invalid = SPValidateRegions(regions, currentWindow, [self displays]);
    if (invalid) return invalid;
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    BOOL found = NO;
    for (NSDictionary *candidate in windows) {
        if ([candidate[(__bridge id)kCGWindowAlpha] doubleValue] <= 0) continue;
        CGRect rect;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)candidate[(__bridge id)kCGWindowBounds], &rect)) continue;
        CGWindowID identifier = [candidate[(__bridge id)kCGWindowNumber] unsignedIntValue];
        BOOL closeBounds = fabs(rect.origin.x - currentWindow.origin.x) <= 8 &&
            fabs(rect.origin.y - currentWindow.origin.y) <= 8 &&
            fabs(rect.size.width - currentWindow.size.width) <= 16 &&
            fabs(rect.size.height - currentWindow.size.height) <= 16;
        BOOL same = [candidate[(__bridge id)kCGWindowOwnerPID] intValue] == pid &&
            [candidate[(__bridge id)kCGWindowLayer] intValue] == 0 && closeBounds;
        if (same) {
            if (sourceWindowID && sourceWindowID != identifier) return reply(@"failed", @"Source window identity changed", nil);
            if (found) return reply(@"unavailable", @"Source window identity is ambiguous", nil);
            sourceWindowID = identifier; found = YES; continue;
        }
        if (!found) {
            for (NSValue *region in regions) {
                if (CGRectIntersectsRect(rect, region.rectValue)) return reply(@"blocked", @"Another window obscures the selected region", nil);
            }
        }
    }
    return found ? [self budget] : reply(@"unavailable", @"Cannot locate the visible source window", nil);
}
- (AXError)parameter:(CFStringRef)name value:(CFTypeRef)parameter result:(CFTypeRef *)value {
    if ([self budget]) return kAXErrorCannotComplete;
    AXUIElementSetMessagingTimeout(element, fmax(0.001, fmin(0.5, deadline - NSProcessInfo.processInfo.systemUptime)));
    return AXUIElementCopyParameterizedAttributeValue(element, name, parameter, value);
}
- (NSDictionary *)geometry:(NSDictionary *)range {
    frozenRange = range;
    NSDictionary *invalid = [self validate];
    if (invalid) return invalid;
    NSMutableArray<NSValue *> *regions = [NSMutableArray array];
    CFIndex cursor = [range[@"location"] longLongValue];
    CFIndex end = cursor + [range[@"length"] longLongValue];
    while (cursor < end) {
        if (regions.count >= 64) return reply(@"oversized", @"Select at most 64 visible lines", nil);
        CFNumberRef index = CFNumberCreate(NULL, kCFNumberCFIndexType, &cursor);
        CFTypeRef line = NULL, lineRangeValue = NULL, boundsValue = NULL;
        AXError error = [self parameter:kAXLineForIndexParameterizedAttribute value:index result:&line];
        CFRelease(index);
        CFRange lineRange;
        BOOL valid = error == kAXErrorSuccess && line && CFGetTypeID(line) == CFNumberGetTypeID();
        if (valid) error = [self parameter:kAXRangeForLineParameterizedAttribute value:line result:&lineRangeValue];
        if (line) CFRelease(line);
        valid = valid && error == kAXErrorSuccess && lineRangeValue && CFGetTypeID(lineRangeValue) == AXValueGetTypeID() &&
            AXValueGetValue(lineRangeValue, kAXValueCFRangeType, &lineRange);
        if (lineRangeValue) CFRelease(lineRangeValue);
        if (!valid) return [self budget] ?: reply(error == kAXErrorCannotComplete ? @"timed_out" : @"unavailable", @"Cannot isolate the selected lines", nil);
        if (lineRange.location < 0 || lineRange.length <= 0 || lineRange.location > cursor ||
            lineRange.location > LONG_MAX - lineRange.length || lineRange.location + lineRange.length <= cursor)
            return reply(@"unavailable", @"AX line geometry is inconsistent", nil);
        CFIndex next = MIN(end, lineRange.location + lineRange.length);
        CFRange selectedPart = CFRangeMake(cursor, next - cursor);
        AXValueRef parameter = AXValueCreate(kAXValueCFRangeType, &selectedPart);
        error = [self parameter:kAXBoundsForRangeParameterizedAttribute value:parameter result:&boundsValue];
        CFRelease(parameter);
        CGRect rect;
        valid = error == kAXErrorSuccess && boundsValue && CFGetTypeID(boundsValue) == AXValueGetTypeID() &&
            AXValueGetValue(boundsValue, kAXValueCGRectType, &rect);
        if (boundsValue) CFRelease(boundsValue);
        if (!valid) return [self budget] ?: reply(error == kAXErrorCannotComplete ? @"timed_out" : @"unavailable", @"Selected line bounds are unavailable", nil);
        // Multi-line bounding boxes and very tall/ambiguous layouts need explicit selection.
        if (rect.size.height > 256) return reply(@"unavailable", @"Cannot isolate this text layout", nil);
        [regions addObject:[NSValue valueWithRect:rect]];
        cursor = next;
    }
    NSDictionary *currentRange = [self selectedRange];
    if (![currentRange[@"ax_range"] isEqual:range])
        return [self budget] ?: reply(@"failed", @"Selection changed while locating its bounds", nil);
    invalid = [self validateRegions:regions];
    return invalid ?: @{ @"regions": regions };
}
- (BOOL)canOfferDrag {
    if ([self validate]) return NO;
    CFTypeRef role = NULL, children = NULL;
    AXError roleError = [self attribute:kAXRoleAttribute of:element value:&role];
    AXError childError = [self attribute:kAXChildrenAttribute of:element value:&children];
    BOOL textControl = roleError == kAXErrorSuccess && role && CFGetTypeID(role) == CFStringGetTypeID() &&
        [@[@"AXTextArea", @"AXTextField", @"AXStaticText"] containsObject:(__bridge id)role];
    BOOL leaf = (childError == kAXErrorAttributeUnsupported || childError == kAXErrorNoValue) ||
        (childError == kAXErrorSuccess && children && CFGetTypeID(children) == CFArrayGetTypeID() && CFArrayGetCount(children) == 0);
    if (role) CFRelease(role);
    if (children) CFRelease(children);
    return textControl && leaf;
}
- (NSDictionary *)ocr:(NSArray<NSValue *> *)regions method:(NSString *)method {
    deadline = NSProcessInfo.processInfo.systemUptime + 3.0;
    NSDictionary *invalid = [self validateRegions:regions];
    if (invalid) return invalid;
    if (!CGPreflightScreenCaptureAccess()) {
        NSMutableDictionary *required = [reply(@"permission_required", @"Screen Recording is required for local selection OCR", nil) mutableCopy];
        required[@"permission"] = @{ @"kind": @"screen_recording", @"state": @"not_granted" };
        return required;
    }
    NSDictionary *result = SPRunOCR(regions, frozenWindow, [self displays], method,
        MAX(0, deadline - NSProcessInfo.processInfo.systemUptime), ^{ return [self cancelled]; }, ^CGImageRef(CGRect region) {
            if ([self validateRegions:regions] || !CGPreflightScreenCaptureAccess()) return NULL;
            return CGWindowListCreateImage(region, kCGWindowListOptionIncludingWindow, sourceWindowID,
                kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution);
        }, ^NSDictionary *(CGImageRef image, NSTimeInterval expires, SPCheck check) {
            return SPVisionRecognize(image, expires, check);
        });
    invalid = [self validateRegions:regions];
    return invalid ?: result;
}
- (NSDictionary *)drag {
    frozenRange = nil;
    if ([self cancelled]) return [self cancelled];
    // User action explicitly restores the recorded source before showing a nonactivating overlay.
    dispatch_sync(dispatch_get_main_queue(), ^{
        [[NSRunningApplication runningApplicationWithProcessIdentifier:pid] activateWithOptions:0];
    });
    deadline = NSProcessInfo.processInfo.systemUptime + 2;
    NSDictionary *invalid = [self validate];
    if (invalid) return invalid;
    if (![self canOfferDrag]) return reply(@"blocked", @"Visual selection requires an isolated, non-secure source text field", nil);
    CGRect field;
    if (![self rectOf:element result:&field] || ![self rectOf:window result:&frozenWindow])
        return [self budget] ?: reply(@"blocked", @"Cannot establish source field bounds", nil);
    if (!CGRectContainsRect(frozenWindow, field)) return reply(@"blocked", @"Source field is not fully visible", nil);
    if (!CGPreflightScreenCaptureAccess()) {
        NSMutableDictionary *required = [reply(@"permission_required", @"Screen Recording is required for local selection OCR", nil) mutableCopy];
        required[@"permission"] = @{ @"kind": @"screen_recording", @"state": @"not_granted" };
        return required;
    }
    NSDictionary *drawn = SPDrawRegion(field, ^{ return [self cancelled]; });
    if (drawn[@"status"]) return drawn;
    // Overlay is hidden and destroyed before any pixels are acquired.
    deadline = NSProcessInfo.processInfo.systemUptime + 2;
    invalid = [self validate];
    if (invalid) return invalid;
    if (![self canOfferDrag]) return reply(@"blocked", @"Source field safety changed", nil);
    CGRect currentField;
    if (![self rectOf:element result:&currentField] || !CGRectEqualToRect(field, currentField))
        return reply(@"blocked", @"Source field moved during visual selection", nil);
    CGRect region = [drawn[@"region"] rectValue];
    if (!CGRectContainsRect(field, region) || CGRectIsEmpty(region))
        return reply(@"blocked", @"Draw a region inside the source text field", nil);
    return [self ocr:@[[NSValue valueWithRect:region]] method:@"visual_drag_ocr"];
}
- (void)dealloc {
    if (element) CFRelease(element);
    if (window) CFRelease(window);
    if (app) CFRelease(app);
}
- (NSDictionary *)validate {
    if (initialFailure) return initialFailure;
    NSDictionary *budget = [self budget];
    if (budget) return budget;
    if (!AXIsProcessTrusted()) return reply(@"permission_required", @"Accessibility access was revoked", nil);
    NSRunningApplication *running = NSWorkspace.sharedWorkspace.frontmostApplication;
    NSArray *excluded = [NSUserDefaults.standardUserDefaults arrayForKey:@"ExcludedApps"] ?: @[];
    if ([excluded containsObject:running.bundleIdentifier ?: @""])
        return reply(@"blocked", @"Source application is excluded", nil);
    if (running.processIdentifier != pid) return reply(@"failed", @"Source app lost focus", nil);
    for (NSString *attribute in @[@"AXFocusedUIElement", @"AXFocusedWindow"]) {
        CFTypeRef value = NULL;
        AXError error = [self attribute:(__bridge CFStringRef)attribute of:app value:&value];
        BOOL same = error == kAXErrorSuccess && value && CFEqual(value,
            [attribute isEqualToString:@"AXFocusedWindow"] ? window : element);
        if (value) CFRelease(value);
        if (error == kAXErrorCannotComplete) return [self failureForError:error detail:@"Source validation timed out"];
        if (!same) return reply(@"failed", @"Focused source changed during capture", nil);
    }
    return [self budget] ?: [self checkSafety];
}
- (NSDictionary *)textResult:(CFTypeRef)value error:(AXError)error {
    NSDictionary *budget = [self budget];
    if (budget) return budget;
    if (error == kAXErrorCannotComplete) return reply(@"timed_out", @"Selection read timed out", nil);
    if (error != kAXErrorSuccess || !value || CFGetTypeID(value) != CFStringGetTypeID())
        return reply(@"unavailable", @"Selection attribute is unreadable", nil);
    NSString *text = (__bridge NSString *)value;
    if (text.length > 12000) return reply(@"oversized", @"Select at most 12,000 UTF-16 code units", nil);
    return reply(text.length ? @"verified" : @"unavailable", @"AX selection text", text);
}
- (NSDictionary *)selectedText {
    CFTypeRef value = NULL;
    AXError error = [self attribute:kAXSelectedTextAttribute of:element value:&value];
    NSDictionary *result = [self textResult:value error:error];
    if (value) CFRelease(value);
    return result;
}
- (NSDictionary *)selectedRange {
    CFTypeRef value = NULL;
    AXError error = [self attribute:kAXSelectedTextRangeAttribute of:element value:&value];
    CFRange range = CFRangeMake(0, 0);
    BOOL valid = error == kAXErrorSuccess && value && CFGetTypeID(value) == AXValueGetTypeID() &&
        AXValueGetType(value) == kAXValueCFRangeType && AXValueGetValue(value, kAXValueCFRangeType, &range);
    if (value) CFRelease(value);
    NSDictionary *budget = [self budget];
    if (budget) return budget;
    if (error == kAXErrorCannotComplete) return reply(@"timed_out", @"Selection range timed out", nil);
    if (!valid) return reply(@"unavailable", @"Selection range is unavailable", nil);
    if (range.location < 0 || range.length < 0 || range.location > LONG_MAX - range.length)
        return reply(@"failed", @"Invalid selected range", nil);
    if (range.length > 12000) return reply(@"oversized", @"Select at most 12,000 UTF-16 code units", nil);
    return @{ @"status": @"verified", @"ax_range": @{ @"location": @(range.location), @"length": @(range.length) } };
}
- (NSDictionary *)stringForRange:(NSDictionary *)range {
    NSDictionary *budget = [self budget];
    if (budget) return budget;
    CFRange nativeRange = CFRangeMake([range[@"location"] longLongValue], [range[@"length"] longLongValue]);
    AXValueRef parameter = AXValueCreate(kAXValueCFRangeType, &nativeRange);
    if (!parameter) return reply(@"failed", @"Cannot construct selection range", nil);
    AXUIElementSetMessagingTimeout(element, fmax(0.001, fmin(0.5, deadline - NSProcessInfo.processInfo.systemUptime)));
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute, parameter, &value);
    CFRelease(parameter);
    NSDictionary *result = [self textResult:value error:error];
    if (value) CFRelease(value);
    return result;
}
- (NSDictionary *)contextForRange:(NSDictionary *)range {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    long long start = [range[@"location"] longLongValue];
    long long end = start + [range[@"length"] longLongValue];
    CFTypeRef value = NULL;
    AXError error = [self attribute:kAXNumberOfCharactersAttribute of:element value:&value];
    long long total = end;
    if (error == kAXErrorSuccess && value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue(value, kCFNumberLongLongType, &total);
    if (value) CFRelease(value);
    if (error == kAXErrorCannotComplete) return [self failureForError:error detail:@"Context range timed out"];
    for (NSString *side in @[@"context_before", @"context_after"]) {
        BOOL before = [side isEqualToString:@"context_before"];
        long long length = before ? MIN(start, 500) : MIN(MAX(total - end, 0), 500);
        if (!length) continue;
        NSDictionary *read = [self stringForRange:@{ @"location": @(before ? start - length : end), @"length": @(length) }];
        if (![@[@"verified", @"unavailable"] containsObject:read[@"status"]]) return read;
        NSString *text = read[@"text"];
        if (text.length > 500) return reply(@"failed", @"Context exceeded its requested range", nil);
        // Drop only a partial surrogate at the context boundary, never selection text.
        if (text.length && CFStringIsSurrogateLowCharacter([text characterAtIndex:0])) text = [text substringFromIndex:1];
        if (text.length && CFStringIsSurrogateHighCharacter([text characterAtIndex:text.length - 1])) text = [text substringToIndex:text.length - 1];
        if (text.length) result[side] = text;
    }
    return [self budget] ?: result;
}
@end

char *splainit_capture(pid_t pid, bool with_context, uint64_t invocation) {
    @autoreleasepool {
        SplainitAXProvider *provider = [[SplainitAXProvider alloc] initWithPid:pid invocation:invocation];
        NSDictionary *result = [SelectionResolver resolve:provider withContext:with_context];
        if ([result[@"status"] isEqual:@"unavailable"] && result[@"ax_range"]) {
            NSDictionary *geometry = [provider geometry:result[@"ax_range"]];
            if (geometry[@"regions"]) {
                NSDictionary *ocr = [provider ocr:geometry[@"regions"] method:@"ax_bounds_ocr"];
                NSMutableDictionary *withRange = [ocr mutableCopy];
                withRange[@"ax_range"] = result[@"ax_range"];
                result = withRange;
            } else result = geometry;
        }
        // Only unavailable recovery offers an explicit action. Terminal failures never widen capture.
        if ([result[@"status"] isEqual:@"unavailable"] && [provider canOfferDrag]) {
            initializeVisualLock(); [visualLock lock];
            if (atomic_load(&captureInvocation) == invocation) visualSource = provider;
            [visualLock unlock];
            NSMutableDictionary *recoverable = [result mutableCopy];
            recoverable[@"visual_available"] = @YES;
            result = recoverable;
        }
        return encode(result);
    }
}

char *splainit_drag_capture(uint64_t invocation) {
    @autoreleasepool {
        initializeVisualLock(); [visualLock lock];
        SplainitAXProvider *provider = visualSource; visualSource = nil;
        [visualLock unlock];
        if (!provider || atomic_load(&captureInvocation) != invocation)
            return encode(reply(@"cancelled", @"Visual selection is no longer available", nil));
        return encode([provider drag]);
    }
}

void splainit_free(char *pointer) { free(pointer); }

void splainit_activate(void) {
    [NSApp activateIgnoringOtherApps:YES];
}

char *splainit_load_shortcut(void) {
    @autoreleasepool {
        NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:@"GlobalShortcut"];
        return strdup((value ?: @"Ctrl+Alt+K").UTF8String);
    }
}

void splainit_save_shortcut(const char *value) {
    @autoreleasepool {
        if (!value) return;
        NSString *shortcut = [NSString stringWithUTF8String:value];
        if (shortcut) [NSUserDefaults.standardUserDefaults setObject:shortcut forKey:@"GlobalShortcut"];
    }
}

bool splainit_context_enabled(void) {
    @autoreleasepool {
        return [NSUserDefaults.standardUserDefaults boolForKey:@"ContextEnabled"];
    }
}

void splainit_set_context_enabled(bool enabled) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"ContextEnabled"];
    }
}

char *splainit_load_model(void) {
    @autoreleasepool {
        NSString *model = [NSUserDefaults.standardUserDefaults stringForKey:@"OpenAIModel"];
        return strdup((model ?: @SPLAINIT_DEFAULT_MODEL).UTF8String);
    }
}

void splainit_save_model(const char *value) {
    @autoreleasepool {
        if (!value) return;
        NSString *model = [NSString stringWithUTF8String:value];
        if (model) [NSUserDefaults.standardUserDefaults setObject:model forKey:@"OpenAIModel"];
    }
}

bool splainit_history_enabled(void) {
    @autoreleasepool {
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"HistoryEnabled"];
        return setting ? [setting boolValue] : true;
    }
}

void splainit_set_history_enabled(bool enabled) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"HistoryEnabled"];
    }
}

char *splainit_excluded_apps(void) {
    @autoreleasepool {
        NSArray *apps = [NSUserDefaults.standardUserDefaults arrayForKey:@"ExcludedApps"] ?: @[];
        return encode(@{ @"apps": apps });
    }
}

void splainit_save_excluded_apps(const char *value) {
    @autoreleasepool {
        if (!value) return;
        NSData *data = [[NSString stringWithUTF8String:value] dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:NSArray.class])
            [NSUserDefaults.standardUserDefaults setObject:parsed forKey:@"ExcludedApps"];
    }
}

bool splainit_is_excluded(const char *bundle_id) {
    @autoreleasepool {
        if (!bundle_id) return false;
        NSString *bundle = [NSString stringWithUTF8String:bundle_id];
        NSArray *apps = [NSUserDefaults.standardUserDefaults arrayForKey:@"ExcludedApps"] ?: @[];
        return [apps containsObject:bundle];
    }
}

static NSDictionary *keyQuery(void) {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"app.splainit.desktop.openai",
        (__bridge id)kSecAttrAccount: @"api-key"
    };
}

int splainit_store_api_key(const char *value) {
    @autoreleasepool {
        if (!value) return (int)errSecParam;
        NSData *data = [[NSString stringWithUTF8String:value] dataUsingEncoding:NSUTF8StringEncoding];
        if (!data.length) return (int)errSecParam;
        NSMutableDictionary *add = [keyQuery() mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        OSStatus result = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        if (result == errSecDuplicateItem) {
            result = SecItemUpdate((__bridge CFDictionaryRef)keyQuery(),
                                   (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
        }
        return (int)result;
    }
}

bool splainit_has_api_key(void) {
    @autoreleasepool {
        return SecItemCopyMatching((__bridge CFDictionaryRef)keyQuery(), NULL) == errSecSuccess;
    }
}

char *splainit_read_api_key(void) {
    @autoreleasepool {
        NSMutableDictionary *query = [keyQuery() mutableCopy];
        query[(__bridge id)kSecReturnData] = @YES;
        query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status != errSecSuccess || !result) return NULL;
        NSData *data = CFBridgingRelease(result);
        char *copy = malloc(data.length + 1);
        if (!copy) return NULL;
        memcpy(copy, data.bytes, data.length);
        copy[data.length] = 0;
        return copy;
    }
}

void splainit_free_api_key(char *pointer) {
    if (!pointer) return;
    size_t length = strlen(pointer);
    volatile unsigned char *bytes = (volatile unsigned char *)pointer;
    for (size_t index = 0; index < length; index++) bytes[index] = 0;
    free(pointer);
}

int splainit_remove_api_key(void) {
    @autoreleasepool {
        OSStatus result = SecItemDelete((__bridge CFDictionaryRef)keyQuery());
        return (int)(result == errSecItemNotFound ? errSecSuccess : result);
    }
}
