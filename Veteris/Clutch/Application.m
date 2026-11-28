//
//  Application.m
//  Hand Brake
//
//  Created by Ninja on 28/02/2013.
//  Copyright (c) 2013 Hackulous. All rights reserved.
//

#import "Application.h"
#import "Binary.h"

@interface ApplicationC () {

    NSString *applicationContainer, // /private/var/mobile/Applications/C320A08E-1295-4F40-8B4F-9D8A5634CE92/
        *applicationDisplayName,    // what you see on SpringBoard
        *applicationName,           // AppAddict.app - .app = AppAddict
        *appDirectory,              // AppAddict.app
        *realUniqueID,              // C320A08E-1295-4F40-8B4F-9D8A5634CE92
        *applicationVersion,        // 1.0
        *applicationBundleID,       // com.apple.purpleshit
        *applicationExecutableName, // Clutch-1.3.2-git4
        *minimumOSVersion;          // 4.3

    NSData *applicationSINF; // NSData of /SC_Info/$(applicationExecutableName).sinf
    UIImage *applicationIcon;

    NSDictionary *dictRep; // NSDictionary representation of all stuff above,except applicationIcon(UIImage)
}

@end

@implementation ApplicationC

- (void)addIconFiles:(id)files toArray:(NSMutableArray *)iconNames {
    if ([files isKindOfClass:[NSString class]]) {
        [iconNames addObject:files];
    } else if ([files isKindOfClass:[NSArray class]]) {
        for (id file in [files reverseObjectEnumerator]) {
            if ([file isKindOfClass:[NSString class]]) {
                [iconNames addObject:file];
            }
        }
    }
}

- (void)addPrimaryIconFilesFromIcons:(id)icons toArray:(NSMutableArray *)iconNames {
    if (![icons isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id primaryIcon = [icons objectForKey:@"CFBundlePrimaryIcon"];
    if ([primaryIcon isKindOfClass:[NSDictionary class]]) {
        [self addIconFiles:[primaryIcon objectForKey:@"CFBundleIconFiles"] toArray:iconNames];
    }
}

- (UIImage *)iconFromInfoPlistInDirectory:(NSString *)directory {
    if (directory == nil) {
        return nil;
    }
    NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:[directory stringByAppendingPathComponent:@"Info.plist"]];
    NSMutableArray *iconNames = [NSMutableArray array];
    if ([infoPlist isKindOfClass:[NSDictionary class]]) {
        [self addPrimaryIconFilesFromIcons:[infoPlist objectForKey:@"CFBundleIcons"] toArray:iconNames];
        [self addPrimaryIconFilesFromIcons:[infoPlist objectForKey:@"CFBundleIcons~ipad"] toArray:iconNames];
        [self addIconFiles:[infoPlist objectForKey:@"CFBundleIconFiles"] toArray:iconNames];
        [self addIconFiles:[infoPlist objectForKey:@"CFBundleIconFile"] toArray:iconNames];
    }
    [iconNames addObject:@"Icon@2x.png"];
    [iconNames addObject:@"Icon-72.png"];

    for (NSString *iconName in iconNames) {
        NSString *baseName = iconName;
        if ([[baseName pathExtension] length] > 0) {
            baseName = [baseName stringByDeletingPathExtension];
        }
        NSArray *candidates = @[[baseName stringByAppendingString:@".png"], [baseName stringByAppendingString:@"@2x.png"]];
        for (NSString *candidate in candidates) {
            UIImage *icon = [UIImage imageWithContentsOfFile:[directory stringByAppendingPathComponent:candidate]];
            if (icon != nil) {
                return icon;
            }
        }
    }
    return nil;
}

- (id)initWithAppInfo:(NSDictionary *)info {

    if (self = [super init]) {
        applicationContainer = [info objectForKey:@"ApplicationContainer"];
        applicationDisplayName = [info objectForKey:@"ApplicationDisplayName"];
        applicationName = [info objectForKey:@"ApplicationName"];
        appDirectory = [info objectForKey:@"ApplicationBasename"];
        realUniqueID = [info objectForKey:@"RealUniqueID"];
        applicationVersion = [info objectForKey:@"ApplicationVersion"];
        applicationBundleID = [info objectForKey:@"ApplicationBundleID"];
        applicationExecutableName = [info objectForKey:@"ApplicationExecutableName"];
        applicationSINF = [info objectForKey:@"ApplicationSINF"];
        minimumOSVersion = [info objectForKey:@"MinimumOSVersion"];
        applicationIcon = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/Icon.png", [info objectForKey:@"ApplicationDirectory"]]];
        if (applicationIcon == nil) {
            applicationIcon = [self iconFromInfoPlistInDirectory:[info objectForKey:@"ApplicationDirectory"]];
        }
        NSMutableDictionary *copy = [[NSMutableDictionary alloc] initWithDictionary:info];
        [copy removeObjectForKey:@"ApplicationSINF"]; // slow
        dictRep = copy;
        isCracking = NO;
        finishedSuccessfully = NO;
        _info = info;
    }
    return self;
}

- (NSString *)applicationContainer {
    return applicationContainer;
}

- (NSString *)applicationDirectory {
    return [applicationContainer lastPathComponent];
}

- (NSString *)applicationDisplayName {
    return applicationDisplayName;
}

- (NSString *)applicationName {
    return applicationName;
}

- (NSString *)appDirectory {
    return appDirectory;
}

- (NSString *)realUniqueID {
    return realUniqueID;
}

- (UIImage *)applicationIcon {
    return applicationIcon;
}

- (NSString *)applicationVersion {
    return applicationVersion;
}
- (NSString *)applicationExecutableName {
    return applicationExecutableName;
}
- (NSString *)applicationBundleID {
    return applicationBundleID;
}

- (NSData *)applicationSINF {
    return applicationSINF;
}

- (NSString *)minimumOSVersion {
    return minimumOSVersion;
}


- (NSDictionary *)dictionaryRepresentation {
    return dictRep;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, appName: %@, bundleID: %@>", NSStringFromClass([self class]), self, self.applicationName, self.applicationBundleID];
}

- (NSInteger)appVersion {
    return [[applicationVersion stringByReplacingOccurrencesOfString:@"." withString:@""] integerValue];
}

@end
