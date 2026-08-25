#import "Version.h"

@implementation Version
+ (NSString *)stringFromProtoArg:(void *)arg {
    if (arg == NULL) {
        return @"";
    }
    NSString *value = [NSString stringWithUTF8String:(const char *)arg];
    return value ?: @"";
}

- (Version *)initFromVersionProto:(VersionMsg)versionProto {
    self = [super init];
    if (self) {
        self.version = [Version stringFromProtoArg:versionProto.version.arg];
        self.fileName = [Version stringFromProtoArg:versionProto.fileName.arg];
        self.minVersion = [Version stringFromProtoArg:versionProto.minVersion.arg];
        self.sizeBytes = versionProto.has_sizeBytes ? versionProto.sizeBytes : 0;
        self.buildVersion = [Version stringFromProtoArg:versionProto.buildVersion.arg];
        self.platform = [Version stringFromProtoArg:versionProto.platform.arg];
        self.sourceItem = [Version stringFromProtoArg:versionProto.sourceItem.arg];
        self.sourceFile = [Version stringFromProtoArg:versionProto.sourceFile.arg];
        self.sha1 = [Version stringFromProtoArg:versionProto.sha1.arg];
        self.md5 = [Version stringFromProtoArg:versionProto.md5.arg];
        self.fairplayStatus = [Version stringFromProtoArg:versionProto.fairplayStatus.arg];
        self.archFlags = [Version stringFromProtoArg:versionProto.archFlags.arg];
        self.backgroundModes = [Version stringFromProtoArg:versionProto.backgroundModes.arg];
        self.executable = [Version stringFromProtoArg:versionProto.executable.arg];
        self.releaseDate = [Version stringFromProtoArg:versionProto.releaseDate.arg];
        self.contentRating = [Version stringFromProtoArg:versionProto.contentRating.arg];
        self.price = [Version stringFromProtoArg:versionProto.price.arg];
        self.subgenres = [Version stringFromProtoArg:versionProto.subgenres.arg];
        self.copyrightText = [Version stringFromProtoArg:versionProto.copyrightText.arg];
        self.gameCenter = [Version stringFromProtoArg:versionProto.gameCenter.arg];
        self.newsstand = [Version stringFromProtoArg:versionProto.newsstand.arg];
        self.requiredCapabilities = [Version stringFromProtoArg:versionProto.requiredCapabilities.arg];
        self.metadataSource = [Version stringFromProtoArg:versionProto.metadataSource.arg];
        self.iconPath = [Version stringFromProtoArg:versionProto.iconPath.arg];
        self.iconBundleID = [Version stringFromProtoArg:versionProto.iconBundleID.arg];
        self.bundleID = [Version stringFromProtoArg:versionProto.bundleID.arg];
        self.recommended = versionProto.has_recommended && versionProto.recommended;
    }
    return self;
}
@end
