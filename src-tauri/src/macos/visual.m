#import "visual.h"
#import <Vision/Vision.h>

NSDictionary *SPVisualOutcome(NSString *status, NSString *detail) {
    return @{ @"status": status, @"detail": detail, @"text": @"", @"verification": @"none" };
}

static BOOL finiteRect(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height) &&
        r.size.width > 0 && r.size.height > 0 && isfinite(CGRectGetMaxX(r)) && isfinite(CGRectGetMaxY(r));
}

static NSArray<NSValue *> *orderedRegions(NSArray<NSValue *> *regions) {
    return [regions sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        CGRect x = a.rectValue, y = b.rectValue;
        if (CGRectGetMinY(x) != CGRectGetMinY(y)) return CGRectGetMinY(x) < CGRectGetMinY(y) ? NSOrderedAscending : NSOrderedDescending;
        if (CGRectGetMinX(x) != CGRectGetMinX(y)) return CGRectGetMinX(x) < CGRectGetMinX(y) ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
}

NSDictionary *SPValidateRegions(NSArray<NSValue *> *regions, CGRect window, NSArray<NSDictionary *> *displays) {
    if (!regions.count || !finiteRect(window)) return SPVisualOutcome(@"unavailable", @"Selection geometry is unavailable");
    if (regions.count > 64) return SPVisualOutcome(@"oversized", @"Select at most 64 visible lines");
    double pixels = 0;
    NSMutableArray *previous = [NSMutableArray array];
    for (NSValue *value in regions) {
        CGRect rect = value.rectValue;
        if (!finiteRect(rect) || !CGRectContainsRect(window, rect))
            return SPVisualOutcome(@"blocked", @"Selection lies outside the source window");
        NSDictionary *display = nil;
        for (NSDictionary *candidate in displays) {
            if (CGRectContainsRect([candidate[@"bounds"] rectValue], rect)) { display = candidate; break; }
        }
        double scale = [display[@"scale"] doubleValue];
        if (!display || !isfinite(scale) || scale <= 0 || scale > 4)
            return SPVisualOutcome(@"unavailable", @"Selection must fit on one visible display");
        for (NSValue *prior in previous) {
            if (CGRectIntersectsRect(rect, prior.rectValue))
                return SPVisualOutcome(@"unavailable", @"Overlapping selection regions cannot be isolated");
        }
        [previous addObject:value];
        // Round outward before acquisition, including fractional pixel edges.
        pixels += (ceil(CGRectGetMaxX(rect) * scale) - floor(CGRectGetMinX(rect) * scale)) *
                  (ceil(CGRectGetMaxY(rect) * scale) - floor(CGRectGetMinY(rect) * scale));
        if (!isfinite(pixels) || pixels > 2000000)
            return SPVisualOutcome(@"oversized", @"Select a smaller region (maximum 2,000,000 pixels)");
    }
    return nil;
}

NSDictionary *SPRunOCR(NSArray<NSValue *> *regions, CGRect window, NSArray<NSDictionary *> *displays,
                      NSString *method, NSTimeInterval timeout, SPCheck check,
                      SPAcquire acquire, SPRecognize recognize) {
    NSDictionary *invalid = check();
    if (invalid) return invalid;
    invalid = SPValidateRegions(regions, window, displays);
    if (invalid) return invalid; // Never acquire before checking the entire area budget.
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    SPCheck boundedCheck = ^NSDictionary *{
        NSDictionary *stopped = check();
        if (stopped) return stopped;
        if (NSProcessInfo.processInfo.systemUptime >= deadline)
            return SPVisualOutcome(@"timed_out", @"Local OCR exceeded three seconds");
        return nil;
    };
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableArray *bounds = [NSMutableArray array];
    NSNumber *confidence = nil;
    NSUInteger length = 0;
    for (NSValue *region in orderedRegions(regions)) {
        @autoreleasepool {
            invalid = boundedCheck();
            if (invalid) return invalid;
            CGImageRef image = acquire(region.rectValue);
            if (!image) return SPVisualOutcome(@"failed", @"Could not acquire the selected region");
            NSDictionary *recognized = nil;
            @try {
                invalid = boundedCheck();
                if (invalid) return invalid;
                if (CGImageGetHeight(image) == 0 ||
                    CGImageGetWidth(image) > 2000000 / CGImageGetHeight(image))
                    return SPVisualOutcome(@"oversized", @"Captured image exceeded its validated pixel budget");
                recognized = recognize(image, deadline, boundedCheck);
            } @finally { CGImageRelease(image); }
            invalid = boundedCheck();
            if (invalid) return invalid;
            if (recognized[@"status"]) return recognized;
            NSArray *observations = recognized[@"lines"] ?: @[];
            // Native Vision normalized y is converted to top-down coordinates by its adapter.
            observations = [observations sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                for (NSString *key in @[@"top", @"left", @"index"]) {
                    NSComparisonResult order = [a[key] compare:b[key]];
                    if (order != NSOrderedSame) return order;
                }
                return NSOrderedSame;
            }];
            for (NSDictionary *line in observations) {
                NSString *text = line[@"text"];
                if (!text.length) continue;
                length += text.length + (lines.count ? 1 : 0);
                if (length > 12000) return SPVisualOutcome(@"oversized", @"Recognized text exceeds 12,000 UTF-16 code units");
                [lines addObject:text];
                NSNumber *score = line[@"confidence"];
                if ([score isKindOfClass:NSNumber.class] && isfinite(score.doubleValue) && score.doubleValue >= 0 && score.doubleValue <= 1)
                    confidence = confidence ? @(MIN(confidence.doubleValue, score.doubleValue)) : score;
            }
            CGRect r = region.rectValue;
            [bounds addObject:@{ @"x": @(r.origin.x), @"y": @(r.origin.y), @"width": @(r.size.width), @"height": @(r.size.height) }];
        }
    }
    invalid = boundedCheck();
    if (invalid) return invalid;
    if (!lines.count) return SPVisualOutcome(@"unavailable", @"No readable text in the selected region");
    return @{ @"status": @"unverified", @"detail": @"Review locally recognized text before sending",
        @"method": method, @"verification": @"unverified", @"confidence": confidence ?: NSNull.null,
        @"text": [lines componentsJoinedByString:@"\n"], @"bounds": bounds };
}

NSDictionary *SPVisionRecognize(CGImageRef image, NSTimeInterval deadline, SPCheck check) {
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    request.automaticallyDetectsLanguage = YES;
    // The watchdog requests native cancellation; no late results escape SPRunOCR.
    dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_timer(watchdog, DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC, NSEC_PER_MSEC);
    dispatch_source_set_event_handler(watchdog, ^{
        if (NSProcessInfo.processInfo.systemUptime >= deadline || check()) [request cancel];
    });
    dispatch_resume(watchdog);
    NSError *error = nil;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:&error];
    dispatch_source_cancel(watchdog);
    NSDictionary *invalid = check();
    if (invalid) return invalid;
    if (!ok || error) return SPVisualOutcome(@"failed", @"Local text recognition failed");
    NSMutableArray *lines = [NSMutableArray array];
    NSUInteger index = 0;
    for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
        if (candidate.string.length) {
            CGRect r = observation.boundingBox;
            [lines addObject:@{ @"text": candidate.string, @"confidence": @(candidate.confidence),
                @"top": @(1 - CGRectGetMaxY(r)), @"left": @(CGRectGetMinX(r)), @"index": @(index) }];
        }
        index++;
    }
    return @{ @"lines": lines };
}

@interface SPRegionView : NSView
@property CGPoint anchor;
@property CGRect selected;
@property(copy) void (^finished)(BOOL, CGRect);
@end
@implementation SPRegionView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event { self.anchor = [self convertPoint:event.locationInWindow fromView:nil]; }
- (void)mouseDragged:(NSEvent *)event {
    CGPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    self.selected = CGRectMake(MIN(p.x, self.anchor.x), MIN(p.y, self.anchor.y), fabs(p.x - self.anchor.x), fabs(p.y - self.anchor.y));
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event { [self mouseDragged:event]; self.finished(NO, self.selected); }
- (void)keyDown:(NSEvent *)event { if (event.keyCode == 53) self.finished(YES, CGRectZero); }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithWhite:0 alpha:0.15] setFill]; NSRectFill(self.bounds);
    [NSColor.systemBlueColor setStroke];
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:self.selected]; path.lineWidth = 2; [path stroke];
    [@"Drag over text in the source field • Esc to cancel" drawAtPoint:NSMakePoint(12, 12)
        withAttributes:@{NSForegroundColorAttributeName: NSColor.whiteColor, NSFontAttributeName:[NSFont systemFontOfSize:15]}];
}
@end

@interface SPRegionPanel : NSPanel
@end
@implementation SPRegionPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

NSDictionary *SPDrawRegion(CGRect allowedWindow, SPCheck cancelled) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block SPRegionPanel *panel = nil;
    __block NSDictionary *result = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *invalid = cancelled();
        if (invalid) { result = invalid; dispatch_semaphore_signal(done); return; }
        CGFloat mainHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
        CGRect frame = CGRectMake(allowedWindow.origin.x, mainHeight - CGRectGetMaxY(allowedWindow), allowedWindow.size.width, allowedWindow.size.height);
        panel = [[SPRegionPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        panel.level = NSScreenSaverWindowLevel;
        panel.opaque = NO; panel.backgroundColor = NSColor.clearColor; panel.hidesOnDeactivate = NO;
        SPRegionView *view = [[SPRegionView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
        view.finished = ^(BOOL wasCancelled, CGRect r) {
            if (result) return;
            [panel orderOut:nil];
            result = wasCancelled ? SPVisualOutcome(@"cancelled", @"Visual selection cancelled") :
                @{ @"region": [NSValue valueWithRect:CGRectOffset(r, allowedWindow.origin.x, allowedWindow.origin.y)] };
            dispatch_semaphore_signal(done);
        };
        panel.contentView = view; [panel makeKeyAndOrderFront:nil]; [panel makeFirstResponder:view];
    });
    for (;;) {
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC)) == 0) break;
        if (cancelled()) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (!result) { result = cancelled(); [panel orderOut:nil]; dispatch_semaphore_signal(done); }
            });
        }
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        [panel orderOut:nil];
        ((SPRegionView *)panel.contentView).finished = nil;
        [panel close]; panel = nil;
    });
    return result;
}
