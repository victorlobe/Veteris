#import "Version.h"

@implementation Version
- (Version *)initFromVersionProto:(VersionMsg)versionProto {
    self = [super init];
    if (self) {
        self.version = [NSString stringWithUTF8String:versionProto.version.arg];
        self.fileName = [NSString stringWithUTF8String:versionProto.fileName.arg];
        self.minVersion = [NSString stringWithUTF8String:versionProto.minVersion.arg];
        self.sizeBytes = versionProto.has_sizeBytes ? versionProto.sizeBytes : 0;
    }
    return self;
}
@end
