#import <AppKit/AppKit.h>

typedef NSDictionary *(^SPCheck)(void);
typedef CGImageRef (^SPAcquire)(CGRect region);
typedef NSDictionary *(^SPRecognize)(CGImageRef image, NSTimeInterval deadline, SPCheck check);

// Coordinates: Quartz global display points, top-left origin, y down.
NSDictionary *SPValidateRegions(NSArray<NSValue *> *regions, CGRect window, NSArray<NSDictionary *> *displays);
NSDictionary *SPRunOCR(NSArray<NSValue *> *regions, CGRect window, NSArray<NSDictionary *> *displays,
                      NSString *method, NSTimeInterval timeout, SPCheck check,
                      SPAcquire acquire, SPRecognize recognize);
NSDictionary *SPVisionRecognize(CGImageRef image, NSTimeInterval deadline, SPCheck check);
NSDictionary *SPVisualOutcome(NSString *status, NSString *detail);

// Called on a worker. Only the overlay runs on AppKit's main thread.
NSDictionary *SPDrawRegion(CGRect allowedWindow, SPCheck cancelled);
