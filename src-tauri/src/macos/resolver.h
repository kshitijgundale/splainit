#import <Foundation/Foundation.h>

// Providers return `unavailable` only for unsupported/unreadable attributes.
// Every other unsuccessful outcome is terminal. Validation returns nil on success.
@protocol SplainitSemanticProvider <NSObject>
- (NSDictionary *)validate;
- (NSDictionary *)selectedText;
- (NSDictionary *)selectedRange;
- (NSDictionary *)stringForRange:(NSDictionary *)range;
- (NSDictionary *)contextForRange:(NSDictionary *)range;
@end

@interface SelectionResolver : NSObject
+ (NSDictionary *)resolve:(id<SplainitSemanticProvider>)provider withContext:(BOOL)withContext;
@end
