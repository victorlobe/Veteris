#include "Application.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../AppDelegate.h"

@implementation ApplicationInfoBlock

+ (NSString *)stringFromProtoArg:(void *)arg {
    if (arg == NULL) {
        return @"";
    }
    NSString *value = [NSString stringWithUTF8String:(const char *)arg];
    return value ?: @"";
}

- (ApplicationInfoBlock *)initFromInfoBlockProto:(InfoBlockMsg)blockProto {
    self = [super init];
    if (self) {
        self.title = [ApplicationInfoBlock stringFromProtoArg:blockProto.title.arg];
        self.body = [ApplicationInfoBlock stringFromProtoArg:blockProto.body.arg];
        self.fields = (__bridge NSMutableArray *)blockProto.fields.arg;
    }
    return self;
}

@end

@implementation ApplicationInfoField

+ (NSString *)stringFromProtoArg:(void *)arg {
    if (arg == NULL) {
        return @"";
    }
    NSString *value = [NSString stringWithUTF8String:(const char *)arg];
    return value ?: @"";
}

- (ApplicationInfoField *)initFromInfoFieldProto:(InfoFieldMsg)fieldProto {
    self = [super init];
    if (self) {
        self.label = [ApplicationInfoField stringFromProtoArg:fieldProto.label.arg];
        self.value = [ApplicationInfoField stringFromProtoArg:fieldProto.value.arg];
    }
    return self;
}

@end

@implementation Application // This class is only used in instances where app icon is usually wanted, so even
// though its bad design to update delegate cache in the geticon method, we do it anyway because im the santa claus of this codebase

+ (NSString *)stringFromProtoArg:(void *)arg {
    if (arg == NULL) {
        return @"";
    }
    NSString *value = [NSString stringWithUTF8String:(const char *)arg];
    return value ?: @"";
}

- (Application *)initFromAppProto:(AppMsg)app {
    self = [super init];
    if (self) {
        self.versions = (__bridge NSMutableArray *)app.versions.arg;
        self.name = [Application stringFromProtoArg:app.name.arg];
        self.developer = [Application stringFromProtoArg:app.developer.arg];
        self.bundleid = [Application stringFromProtoArg:app.bundleid.arg];
        self.primaryBundleID = [Application stringFromProtoArg:app.primaryBundleID.arg];
        self.iconurl = [Application stringFromProtoArg:app.iconurl.arg];
        self.fallback_iconurl = [Application stringFromProtoArg:app.fallback_iconurl.arg];
        self.app_description = [Application stringFromProtoArg:app.description.arg];
        self.category = [Application stringFromProtoArg:app.category.arg];
        self.requiredOS = [Application stringFromProtoArg:app.minIOS.arg];
        self.deviceFamily = [Application stringFromProtoArg:app.deviceFamily.arg];
        self.archFlags = [Application stringFromProtoArg:app.archFlags.arg];
        self.backgroundModes = [Application stringFromProtoArg:app.backgroundModes.arg];
        self.executable = [Application stringFromProtoArg:app.executable.arg];
        self.releaseDate = [Application stringFromProtoArg:app.releaseDate.arg];
        self.contentRating = [Application stringFromProtoArg:app.contentRating.arg];
        self.price = [Application stringFromProtoArg:app.price.arg];
        self.subgenres = [Application stringFromProtoArg:app.subgenres.arg];
        self.copyrightText = [Application stringFromProtoArg:app.copyrightText.arg];
        self.gameCenter = [Application stringFromProtoArg:app.gameCenter.arg];
        self.newsstand = [Application stringFromProtoArg:app.newsstand.arg];
        self.requiredCapabilities = [Application stringFromProtoArg:app.requiredCapabilities.arg];
        self.customInfoBlocks = (__bridge NSMutableArray *)app.customInfoBlocks.arg;
        self.websiteURL = [Application stringFromProtoArg:app.websiteURL.arg];
        self.nilIcon = NO;
        self.isVTableEntry = NO;
    }
    return self;
}

- (Application *)initFromVTableEntryProto:(VTableEntryMsg)entry {
    self = [super init];
    if (self) {
        self.name = [Application stringFromProtoArg:entry.name.arg];
        self.bundleid = [Application stringFromProtoArg:entry.bundleid.arg];
        self.primaryBundleID = self.bundleid;
        self.developer = [Application stringFromProtoArg:entry.developer.arg];
        self.iconurl = [Application stringFromProtoArg:entry.iconurl.arg];
        self.fallback_iconurl = [Application stringFromProtoArg:entry.fallback_iconurl.arg];
        self.version = [Application stringFromProtoArg:entry.version.arg];
        self.versionCount = entry.version_count;
        self.nilIcon = NO;
        self.isVTableEntry = YES;
    }
    return self;
}

- (void)doGetIcon {
    [VAPISS getStatic:self.iconurl fallbackPath:self.fallback_iconurl completion:^(NSData *data, NSError *error){
        if (error == nil) {
            self.icon = [UIImage imageWithData:data];
            if (self.icon == nil) {
                debugLog(@"Failed to load image for %@, bundleid: %@, app image url: %@", self.name, self.bundleid, self.iconurl);
                self.nilIcon = YES;
            }
        }
    }];
}
@end
