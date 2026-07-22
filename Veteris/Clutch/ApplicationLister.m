//
//  ApplicationLister.h
//  Hand Brake
//
//  Created by Zorro
//
//  Re-tailored for use in Clutch

#import "ApplicationLister.h"
#import "MobileInstallation.h"
#import "Preferences.h"
#import "out.h"
#import "../../AppDelegate.h"
#import "LSApplicationProxy.h"
#import "LSApplicationWorkspace.h"
#import <dlfcn.h>

#define crackedAppPath @"/etc/cracked.clutch"

typedef NSDictionary *(*YZMobileInstallationLookupFunction)(NSDictionary *options);

static BOOL YZIsNonEmptyString(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

static NSDictionary *YZMobileInstallationLookup(NSDictionary *options) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY);
    if (handle == NULL) {
        DebugLog(@"MobileInstallation framework unavailable");
        return nil;
    }

    YZMobileInstallationLookupFunction lookup = (YZMobileInstallationLookupFunction)dlsym(handle, "MobileInstallationLookup");
    if (lookup == NULL) {
        DebugLog(@"MobileInstallationLookup unavailable");
        return nil;
    }

    @try {
        NSDictionary *apps = lookup(options);
        if ([apps isKindOfClass:[NSDictionary class]]) {
            return apps;
        }
        DebugLog(@"MobileInstallationLookup returned unexpected object: %@", apps);
    } @catch (NSException *exception) {
        DebugLog(@"MobileInstallationLookup failed: %@ %@", [exception name], [exception reason]);
    }
    return nil;
}

static BOOL YZAppHasSCInfo(NSString *appPath) {
    if (!YZIsNonEmptyString(appPath)) {
        return NO;
    }
    NSString *scInfoPath = [appPath stringByAppendingPathComponent:@"SC_Info"];
    BOOL isDirectory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:scInfoPath isDirectory:&isDirectory] && isDirectory;
}

NSDictionary *get_application_list() {
    NSMutableDictionary *installedApps = [[NSMutableDictionary alloc] init];
    if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {
        NSDictionary *options = @{@"ApplicationType" : @"User", @"ReturnAttributes" : @[ @"CFBundleShortVersionString", @"CFBundleVersion", @"Path", @"CFBundleDisplayName", @"CFBundleExecutable", @"MinimumOSVersion" ]};
        NSDictionary *lookupApps = YZMobileInstallationLookup(options);
        if (lookupApps != nil) {
            [installedApps addEntriesFromDictionary:lookupApps];
        }
    } else {
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        NSArray *apps = [workspace allInstalledApplications];
        for (LSApplicationProxy *app in apps) {
            NSString *shortVersionString = YZIsNonEmptyString([app shortVersionString]) ? [app shortVersionString] : [app bundleVersion];
            NSString *bundleVersion = YZIsNonEmptyString([app bundleVersion]) ? [app bundleVersion] : @"Unknown";
            NSString *path = YZIsNonEmptyString([app bundleContainerURL].path) ? [app bundleContainerURL].path : @"Unknown";
            NSString *displayName = YZIsNonEmptyString([app localizedName]) ? [app localizedName] : @"Unknown";
            NSString *executable = YZIsNonEmptyString([app bundleExecutable]) ? [app bundleExecutable] : @"Unknown";
            NSString *minimumOSVersion = YZIsNonEmptyString([app minimumSystemVersion]) ? [app minimumSystemVersion] : @"Unknown";
            if (!YZIsNonEmptyString(shortVersionString)) {
                shortVersionString = bundleVersion;
            }
            
            if (YZIsNonEmptyString([app applicationIdentifier])) {
                [installedApps setObject:@{
                    @"CFBundleShortVersionString" : shortVersionString,
                    @"CFBundleVersion" : bundleVersion,
                    @"Path" : path,
                    @"CFBundleDisplayName" : displayName,
                    @"CFBundleExecutable" : executable,
                    @"MinimumOSVersion" : minimumOSVersion
                } forKey:[app applicationIdentifier]];
            }
        }
    }
    return (NSDictionary *)installedApps;
}

NSArray *get_crackable_apps_list(BOOL sort) {
    NSDictionary *installedApps = get_application_list();
    NSMutableArray *returnArray = [[NSMutableArray alloc] init];
    for (NSString *bundleID in [installedApps allKeys]) {
        if (!YZIsNonEmptyString(bundleID)) {
            continue;
        }
        NSDictionary *appI = [installedApps objectForKey:bundleID];
        if (![appI isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *rawAppPath = [appI objectForKey:@"Path"];
        if (!YZIsNonEmptyString(rawAppPath)) {
            continue;
        }
        NSString *appPath = [rawAppPath stringByAppendingString:@"/"];
        NSString *container = [[appPath stringByDeletingLastPathComponent] stringByAppendingString:@"/"];
        NSString *displayName = [appI objectForKey:@"CFBundleDisplayName"];
        NSString *executableName = [appI objectForKey:@"CFBundleExecutable"];

        NSString *minimumOSVersion = [appI objectForKey:@"MinimumOSVersion"];

        minimumOSVersion = YZIsNonEmptyString(minimumOSVersion) ? minimumOSVersion : @"1.0";

        if (!YZIsNonEmptyString(displayName)) {
            displayName = [[appPath lastPathComponent] stringByReplacingOccurrencesOfString:@".app" withString:@""];
        }
        if (!YZIsNonEmptyString(executableName)) {
            executableName = [[appPath lastPathComponent] stringByReplacingOccurrencesOfString:@".app" withString:@""];
        }

        NSString *version = @"Unknown";

        if ([[appI allKeys] containsObject:@"CFBundleShortVersionString"]) {
            version = [appI objectForKey:@"CFBundleShortVersionString"];
        } else {
            version = [appI objectForKey:@"CFBundleVersion"];
        }
        if (!YZIsNonEmptyString(version)) {
            version = @"Unknown";
        }

        NSData *SINF = [appI objectForKey:@"ApplicationSINF"];

        if (SINF || YZAppHasSCInfo(appPath)) {
            ApplicationC *app = [[ApplicationC alloc] initWithAppInfo:@{
                @"ApplicationContainer" : container,
                @"ApplicationDirectory" : appPath,
                @"ApplicationDisplayName" : displayName,
                @"ApplicationName" : [[appPath lastPathComponent] stringByReplacingOccurrencesOfString:@".app" withString:@""],
                @"RealUniqueID" : [container lastPathComponent],
                @"ApplicationBasename" : [appPath lastPathComponent],
                @"ApplicationVersion" : version,
                @"ApplicationBundleID" : bundleID,
                //@"ApplicationSINF":SINF,
                @"ApplicationExecutableName" : executableName,
                @"MinimumOSVersion" : minimumOSVersion
            }];

            [returnArray addObject:app];
        }
    }

    if ([returnArray count] == 0) {
        return nil;
    }

    if (sort) {
        NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"applicationName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];

        NSArray *sortDescriptors = [NSArray arrayWithObject:sorter];

        [returnArray sortUsingDescriptors:sortDescriptors];
    }

    return (NSArray *)returnArray;
}

@implementation ApplicationLister

+ (instancetype)sharedInstance {
    static dispatch_once_t pred;
    static ApplicationLister *shared = nil;

    dispatch_once(&pred, ^{
        shared = [ApplicationLister new];
    });

    return shared;
}

- (NSArray *)modifiedApps {
    NSDictionary *cracked = [self crackedAppsList];
    NSArray *apps = get_crackable_apps_list(YES);
    NSMutableArray *modifiedApps = [[NSMutableArray alloc] init];
    for (ApplicationC *app in apps) {
        NSDictionary *appInfo = [cracked objectForKey:app.applicationBundleID];
        if (appInfo == nil) {
            continue;
        }
        ApplicationC *oldApp = [[ApplicationC alloc] initWithAppInfo:appInfo];
        DebugLog(@"new app version: %ld, %ld", (long)oldApp.appVersion, (long)app.appVersion);
        if (app.appVersion > oldApp.appVersion) {
            [modifiedApps addObject:app];
        }
    }
    DebugLog(@"modified apps array %@", modifiedApps);
    return modifiedApps;
}

- (void)crackedApp:(ApplicationC *)app {
    DebugLog(@"cracked app ok");
    DebugLog(@"this crack lol %ld", (long)app.appVersion);
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:[self crackedAppsList]];
    if (dict == nil) {
        dict = [[NSMutableDictionary alloc] init];
    }
    [dict setObject:app.dictionaryRepresentation forKey:app.applicationBundleID];
    // DebugLog(@"da dict %@", dict);
    [dict writeToFile:crackedAppPath atomically:YES];
}

- (NSDictionary *)crackedAppsList {
    return [[NSDictionary alloc] initWithContentsOfFile:crackedAppPath];
}

- (NSDictionary *)installedApps {
    return get_application_list();
}

- (NSArray*)crackableApps {
    return get_crackable_apps_list(YES);    
}

- (NSArray *)crackedApps {
    NSString *crackedPath = [NSString stringWithFormat:@"%@/", [[Preferences sharedInstance] ipaDirectory]];
    NSArray *array = [[NSArray alloc] initWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:crackedPath error:nil]];
    NSMutableArray *paths = [[NSMutableArray alloc] init];

    for (int i = 0; i < array.count; i++) {
        if (![[[array objectAtIndex:i] pathExtension] caseInsensitiveCompare:@"ipa"]) {
            [paths addObject:[array objectAtIndex:i]];
        }
    }

    return paths;
}

@end
