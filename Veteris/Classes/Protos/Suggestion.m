#import "Suggestion.h"

@implementation Suggestion
- (NSString *)stringFromProtoArg:(void *)arg {
    if (arg == NULL) {
        return nil;
    }
    return [NSString stringWithUTF8String:arg];
}

- (Suggestion *)initFromSuggestionProto:(SuggestionMsg)proto {
    self = [super init];
    if (self) {
        self.name = [self stringFromProtoArg:proto.name.arg];
        self.bundleid = [self stringFromProtoArg:proto.bundleid.arg];
        self.developer = [self stringFromProtoArg:proto.developer.arg];
        self.iconurl = [self stringFromProtoArg:proto.iconurl.arg];
        self.fallback_iconurl = [self stringFromProtoArg:proto.fallback_iconurl.arg];
        self.versionCount = proto.version_count;
    }
    return self;
}
@end
