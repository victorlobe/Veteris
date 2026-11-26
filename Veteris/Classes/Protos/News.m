#import "News.h"

static NSString *NewsPostString(void *arg) {
    if (arg == NULL) {
        return @"";
    }
    return [NSString stringWithUTF8String:(const char *)arg] ?: @"";
}

@implementation NewsPost
- (NewsPost *)initFromNewsEntryProto:(NewsEntry)proto {
    self = [super init];
    if (self) {
        self.author = NewsPostString(proto.author.arg);
        self.title = NewsPostString(proto.title.arg);
        self.body = NewsPostString(proto.body.arg);
        self.date = NewsPostString(proto.date.arg);
        self.link = NewsPostString(proto.link.arg);
    }
    return self;
}
@end
