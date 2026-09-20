#import "resolver.h"

static NSDictionary *outcome(NSString *status, NSString *detail) {
    return @{ @"status": status, @"detail": detail, @"text": @"", @"verification": @"none" };
}

static BOOL terminal(NSDictionary *result) {
    return ![@[@"verified", @"unavailable"] containsObject:result[@"status"]];
}

@implementation SelectionResolver
+ (NSDictionary *)resolve:(id<SplainitSemanticProvider>)provider withContext:(BOOL)withContext {
    NSDictionary *invalid = [provider validate];
    if (invalid) return invalid;
    // Query direct text first. Range evidence is still checked before auto-send:
    // some controls expose stale text alongside a current zero-length range.
    NSDictionary *direct = [provider selectedText];
    if (terminal(direct)) return direct;
    invalid = [provider validate];
    if (invalid) return invalid;
    NSDictionary *rangeResult = [provider selectedRange];
    if (terminal(rangeResult)) return rangeResult;
    NSDictionary *range = rangeResult[@"ax_range"];
    if (range && [range[@"length"] unsignedLongLongValue] == 0)
        return outcome(@"no_selection", @"The current AX selection is empty");

    NSString *text = direct[@"text"];
    NSDictionary *chosen = direct;
    NSString *method = @"ax_selected_text";
    if (!text.length && range) {
        invalid = [provider validate];
        if (invalid) return invalid;
        chosen = [provider stringForRange:range];
        if (terminal(chosen)) return chosen;
        text = chosen[@"text"];
        method = @"ax_range";
    }
    invalid = [provider validate];
    if (invalid) return invalid;
    if (!text.length) {
        NSMutableDictionary *missing = [outcome(@"unavailable", @"Semantic selection text is unavailable") mutableCopy];
        if (range) missing[@"ax_range"] = range;
        return missing;
    }
    if (text.length > 12000) return outcome(@"oversized", @"Select at most 12,000 UTF-16 code units");
    if (range && text.length != [range[@"length"] unsignedLongLongValue])
        return outcome(@"failed", @"Selected text and range disagree; select again");

    NSMutableDictionary *result = [chosen mutableCopy];
    result[@"status"] = @"verified";
    result[@"method"] = method;
    result[@"verification"] = @"semantic";
    if (range) result[@"ax_range"] = range;
    if (withContext && range) {
        NSDictionary *context = [provider contextForRange:range];
        if (context[@"status"]) return context;
        [result addEntriesFromDictionary:context];
    }
    invalid = [provider validate];
    return invalid ?: result;
}
@end
