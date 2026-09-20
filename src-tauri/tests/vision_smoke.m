#import "../src/macos/visual.h"
#import <CoreText/CoreText.h>

int main(void) {
    @autoreleasepool {
        const size_t width = 1000, height = 200;
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        CGContextRef canvas = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(color);
        CGContextSetRGBFillColor(canvas, 1, 1, 1, 1);
        CGContextFillRect(canvas, CGRectMake(0, 0, width, height));
        CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 36, NULL);
        CGColorRef black = CGColorCreateGenericRGB(0, 0, 0, 1);
        NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"Splainit OCR fixture 123"
            attributes:@{ (__bridge id)kCTFontAttributeName: (__bridge id)font,
                          (__bridge id)kCTForegroundColorAttributeName: (__bridge id)black }];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
        CGContextSetTextPosition(canvas, 20, 100); CTLineDraw(line, canvas);
        CFRelease(line); CFRelease(font); CGColorRelease(black);
        CGImageRef image = CGBitmapContextCreateImage(canvas);
        CGContextRelease(canvas);
        CGRect region = CGRectMake(0, 0, width, height);
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        NSDictionary *result = SPRunOCR(@[[NSValue valueWithRect:region]], region,
            @[@{ @"bounds": [NSValue valueWithRect:region], @"scale": @1 }], @"ax_bounds_ocr", 3,
            ^NSDictionary *{ return nil; },
            ^CGImageRef(CGRect requested) { (void)requested; return CGImageRetain(image); },
            ^NSDictionary *(CGImageRef input, NSTimeInterval deadline, SPCheck check) {
                return SPVisionRecognize(input, deadline, check);
            });
        CGImageRelease(image);
        // This is a generated harmless fixture, never selected user text or screenshots.
        BOOL pass = [result[@"text"] isEqual:@"Splainit OCR fixture 123"] && [result[@"status"] isEqual:@"unverified"];
        printf("Vision fixture %s; elapsed_ms=%.0f; status=%s; exact_text_match=%s\n", pass ? "PASS" : "FAIL",
            (NSProcessInfo.processInfo.systemUptime - started) * 1000,
            [result[@"status"] UTF8String], pass ? "true" : "false");
        return pass ? 0 : 1;
    }
}
