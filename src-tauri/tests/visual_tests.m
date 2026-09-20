#import "../src/macos/visual.h"
#include <assert.h>

static int liveImages = 0;
static void released(void *info, const void *data, size_t size) {
    (void)info; (void)size; free((void *)data); liveImages--;
}
static CGImageRef fixtureImage(void) {
    unsigned char *data = calloc(16 * 16, 4);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, data, 16 * 16 * 4, released);
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(16, 16, 8, 32, 16 * 4, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, false, kCGRenderingIntentDefault);
    liveImages++;
    CGColorSpaceRelease(color); CGDataProviderRelease(provider);
    return image;
}
static NSDictionary *line(NSString *text, double top, double left, int index) {
    return @{ @"text": text, @"top": @(top), @"left": @(left), @"index": @(index), @"confidence": @0.95 };
}
int main(void) {
    @autoreleasepool {
        CGRect window = CGRectMake(0, 0, 1500, 1000);
        NSArray *displays = @[@{ @"bounds": [NSValue valueWithRect:window], @"scale": @2 }];
        NSArray *regions = @[[NSValue valueWithRect:CGRectMake(20, 80, 200, 20)],
                             [NSValue valueWithRect:CGRectMake(20, 20, 200, 20)]];
        __block int acquired = 0;
        SPCheck valid = ^NSDictionary *{ return nil; };
        SPAcquire image = ^CGImageRef(CGRect rect) { (void)rect; acquired++; return fixtureImage(); };
        SPRecognize recognize = ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
            (void)input; (void)deadline; (void)check;
            return @{ @"lines": @[line(@"bottom", 0.8, 0, 0), line(@"right", 0.1, 0.5, 1), line(@"left", 0.1, 0, 2)] };
        };
        for (NSString *method in @[@"ax_bounds_ocr", @"visual_drag_ocr"]) {
            NSDictionary *result = SPRunOCR(regions, window, displays, method, 3, valid, image, recognize);
            assert(([result[@"text"] isEqual:@"left\nright\nbottom\nleft\nright\nbottom"]));
            assert(([result[@"method"] isEqual:method]));
            assert(([result[@"verification"] isEqual:@"unverified"]));
            assert(([result[@"bounds"][0][@"y"] doubleValue] == 20));
            assert((liveImages == 0));
            assert((!result[@"context_before"] && !result[@"image"] && !result[@"image_url"]));

            acquired = 0;
            NSArray *huge = @[[NSValue valueWithRect:CGRectMake(0, 0, 1200, 600)]];
            result = SPRunOCR(huge, window, displays, method, 3, valid, image, recognize);
            assert(([result[@"status"] isEqual:@"oversized"] && acquired == 0));
            NSArray *outside = @[[NSValue valueWithRect:CGRectMake(-10, 10, 20, 20)]];
            result = SPRunOCR(outside, window, displays, method, 3, valid, image, recognize);
            assert(([result[@"status"] isEqual:@"blocked"] && acquired == 0));
            result = SPRunOCR(@[regions[0], regions[0]], window, displays, method, 3, valid, image, recognize);
            assert(([result[@"status"] isEqual:@"unavailable"] && acquired == 0));
            NSArray *invalid = @[[NSValue valueWithRect:CGRectMake(NAN, 0, 20, 20)]];
            result = SPRunOCR(invalid, window, displays, method, 3, valid, image, recognize);
            assert(([result[@"status"] isEqual:@"blocked"] && acquired == 0));

            result = SPRunOCR(regions, window, displays, method, -1, valid, image, recognize);
            assert(([result[@"status"] isEqual:@"timed_out"] && acquired == 0));
            for (NSString *status in @[@"cancelled", @"blocked", @"permission_required", @"failed"]) {
                result = SPRunOCR(regions, window, displays, method, 3,
                    ^{ return SPVisualOutcome(status, @"fixture"); }, image, recognize);
                assert(([result[@"status"] isEqual:status] && acquired == 0));
            }

            // Supersession after acquisition and during recognition both release the image.
            __block BOOL superseded = NO;
            result = SPRunOCR(regions, window, displays, method, 3,
                ^{ return superseded ? SPVisualOutcome(@"cancelled", @"superseded") : nil; },
                ^CGImageRef(CGRect rect) { (void)rect; superseded = YES; return fixtureImage(); }, recognize);
            assert(([result[@"status"] isEqual:@"cancelled"] && liveImages == 0));
            superseded = NO;
            result = SPRunOCR(regions, window, displays, method, 3,
                ^{ return superseded ? SPVisualOutcome(@"cancelled", @"superseded") : nil; }, image,
                ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
                    (void)input; (void)deadline; (void)check; superseded = YES;
                    return @{ @"lines": @[line(@"stale", 0, 0, 0)] };
                });
            assert(([result[@"status"] isEqual:@"cancelled"] && liveImages == 0 && ![result[@"text"] length]));

            result = SPRunOCR(regions, window, displays, method, 0.005, valid, image,
                ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
                    (void)input; (void)deadline; (void)check; [NSThread sleepForTimeInterval:0.01];
                    return @{ @"lines": @[line(@"late", 0, 0, 0)] };
                });
            assert(([result[@"status"] isEqual:@"timed_out"] && liveImages == 0));
            result = SPRunOCR(regions, window, displays, method, 3, valid, image,
                ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
                    (void)input; (void)deadline; (void)check;
                    return @{ @"lines": @[line([@"x" stringByPaddingToLength:12001 withString:@"x" startingAtIndex:0], 0, 0, 0)] };
                });
            assert(([result[@"status"] isEqual:@"oversized"] && liveImages == 0));
            result = SPRunOCR(regions, window, displays, method, 3, valid, image,
                ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
                    (void)input; (void)deadline; (void)check; return SPVisualOutcome(@"failed", @"fixture recognizer failure");
                });
            assert(([result[@"status"] isEqual:@"failed"] && liveImages == 0));
        }
        // Acquisition receives only the ordered, exact original rectangles.
        __block NSUInteger index = 0;
        SPRunOCR(regions, window, displays, @"ax_bounds_ocr", 3, valid,
            ^CGImageRef(CGRect rect) {
                CGRect expected = [regions[index == 0 ? 1 : 0] rectValue];
                assert((CGRectEqualToRect(rect, expected))); index++; return fixtureImage();
            }, recognize);
        assert((index == 2 && liveImages == 0));
        puts("Native visual fixtures passed (area, isolation, order, timeout, supersession, disposal, text limits).");
    }
}
