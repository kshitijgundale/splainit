#import "../src/macos/resolver.h"
#include <assert.h>

@interface FixtureProvider : NSObject <SplainitSemanticProvider>
@property NSDictionary *direct;
@property NSDictionary *range;
@property NSDictionary *rangedText;
@property NSDictionary *failure;
@property NSUInteger failValidationAt;
@property NSUInteger validations;
@property NSMutableArray *calls;
@end
@implementation FixtureProvider
- (instancetype)init {
    if ((self = [super init])) {
        _direct = @{ @"status": @"verified", @"text": @"fixture", @"detail": @"misleading range message" };
        _range = @{ @"status": @"verified", @"ax_range": @{ @"location": @9, @"length": @7 } };
        _rangedText = @{ @"status": @"verified", @"text": @"fixture" };
        _calls = [NSMutableArray array];
    }
    return self;
}
- (NSDictionary *)validate {
    self.validations++;
    return self.validations == self.failValidationAt ? self.failure : nil;
}
- (NSDictionary *)selectedText { [self.calls addObject:@"direct"]; return self.direct; }
- (NSDictionary *)selectedRange { [self.calls addObject:@"range"]; return self.range; }
- (NSDictionary *)stringForRange:(NSDictionary *)range {
    assert(([range isEqual:self.range[@"ax_range"]]));
    [self.calls addObject:@"string"]; return self.rangedText;
}
- (NSDictionary *)contextForRange:(NSDictionary *)range {
    assert(([range isEqual:self.range[@"ax_range"]]));
    [self.calls addObject:@"context"]; return @{ @"context_before": @"before", @"context_after": @"after" };
}
@end

int main(void) {
    @autoreleasepool {
        FixtureProvider *p = [FixtureProvider new];
        NSDictionary *r = [SelectionResolver resolve:p withContext:NO];
        assert(([r[@"method"] isEqual:@"ax_selected_text"]));
        assert(([r[@"verification"] isEqual:@"semantic"]));
        assert(([p.calls isEqual:@[@"direct", @"range"]]));

        for (NSString *directStatus in @[@"verified", @"unavailable"]) {
            p = [FixtureProvider new];
            p.direct = @{ @"status": directStatus, @"text": @"" };
            r = [SelectionResolver resolve:p withContext:YES];
            assert(([r[@"method"] isEqual:@"ax_range"]));
            assert(([r[@"text"] isEqual:@"fixture"]));
            assert(([r[@"context_after"] isEqual:@"after"]));
            assert(([p.calls isEqual:@[@"direct", @"range", @"string", @"context"]]));
        }

        // Stale nonempty text must not override the current authoritative empty range.
        p = [FixtureProvider new];
        p.range = @{ @"status": @"verified", @"ax_range": @{ @"location": @9, @"length": @0 } };
        r = [SelectionResolver resolve:p withContext:YES];
        assert(([r[@"status"] isEqual:@"no_selection"]));
        assert(([p.calls isEqual:@[@"direct", @"range"]]));

        p = [FixtureProvider new];
        p.range = @{ @"status": @"unavailable" };
        r = [SelectionResolver resolve:p withContext:YES];
        assert(([r[@"method"] isEqual:@"ax_selected_text"]));
        assert((!r[@"context_before"]));

        // Every terminal result stops at the failing provider, including safety,
        // permission, deadline, and cancellation failures.
        for (NSString *status in @[@"blocked", @"permission_required", @"no_selection", @"oversized", @"timed_out", @"cancelled", @"failed"]) {
            for (NSUInteger stage = 0; stage < 3; stage++) {
                p = [FixtureProvider new];
                NSDictionary *failure = @{ @"status": status, @"text": @"" };
                if (stage == 0) p.direct = failure;
                if (stage == 1) p.range = failure;
                if (stage == 2) { p.direct = @{ @"status": @"unavailable" }; p.rangedText = failure; }
                r = [SelectionResolver resolve:p withContext:YES];
                assert(([r[@"status"] isEqual:status]));
                assert((p.calls.count == stage + 1));
            }
        }

        // Focus/safety changes at any validation prevent publication and context.
        for (NSUInteger stage = 1; stage <= 5; stage++) {
            p = [FixtureProvider new];
            p.direct = @{ @"status": @"unavailable" };
            p.failValidationAt = stage;
            p.failure = @{ @"status": @"failed", @"detail": @"inactive source window" };
            r = [SelectionResolver resolve:p withContext:NO];
            assert(([r[@"status"] isEqual:@"failed"]));
            assert((!r[@"text"]));
        }

        p = [FixtureProvider new];
        p.direct = @{ @"status": @"unavailable" };
        p.rangedText = @{ @"status": @"unavailable" };
        r = [SelectionResolver resolve:p withContext:YES];
        assert(([r[@"status"] isEqual:@"unavailable"]));
        assert(([r[@"ax_range"] isEqual:p.range[@"ax_range"]]));
        assert(([p.calls isEqual:@[@"direct", @"range", @"string"]]));

        p = [FixtureProvider new];
        p.direct = @{ @"status": @"verified", @"text": @"wrong length" };
        r = [SelectionResolver resolve:p withContext:NO];
        assert(([r[@"status"] isEqual:@"failed"]));
        puts("Native resolver fixtures passed (ordering, terminal states, exact range, stale focus, context).");
    }
}
