//
//  VeterisUpdatesManager.m
//  Veteris
//
//  Created by Victor on 12.10.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "VeterisUpdatesManager.h"
#import <UIKit/UIKit.h>
#import "../AppInfo/AppInfo.h"
#import "../Convenience/Convenience.h"
#import "../ProtoStack.h"
#import "../Protos/Application.h"
#import "../Protos/Version.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../YZApplication/YZApplication.h"
#import "../YZQueue/YZQueueManager.h"

NSString *const VeterisUpdatesDidChangeNotification = @"VeterisUpdatesDidChangeNotification";

static NSString *const VeterisMutedUpdatesDefaultsKey = @"VeterisMutedUpdates";
static const NSTimeInterval VeterisUpdatesRecheckInterval = 6.0 * 60.0 * 60.0;
static const NSTimeInterval VeterisUpdatesRetryInterval = 60.0;


static NSString *VeterisUpdatesBundleIDForVersion(Application *app, Version *version) {
    if ([version.bundleID length] > 0) {
        return version.bundleID;
    }
    return ([app.primaryBundleID length] > 0) ? app.primaryBundleID : app.bundleid;
}

@implementation VeterisUpdatesManager {
    NSArray *_updates;
    NSDictionary *_checkedVersions;
    NSDate *_lastCheckDate;
    NSDate *_lastAttemptDate;
    VeterisUpdatesCheckState _checkState;
    BOOL _started;
    BOOL _requestInFlight;
    BOOL _checkAgain;
    BOOL _forceNextCheck;
}

+ (VeterisUpdatesManager *)sharedManager {
    static VeterisUpdatesManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[VeterisUpdatesManager alloc] init];
    });
    return sharedManager;
}

- (id)init {
    self = [super init];
    if (self) {
        _updates = [NSArray array];
        _checkState = VeterisUpdatesCheckStateNone;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)start {
    if (_started) {
        return;
    }
    _started = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(installedApplicationsDidRefresh:)
                                                 name:AppInfoInstalledApplicationsDidRefreshNotification
                                               object:nil];
    if ([AppInfo installedApplicationsSnapshot] != nil) {
        [self checkInstalledApplicationsForcing:NO];
    }
}

- (void)checkForUpdates {
    _forceNextCheck = YES;
    if (!_requestInFlight) {
        [self setCheckState:VeterisUpdatesCheckStateChecking];
    }
    [AppInfo refreshInstalledApplicationCache];
}

- (VeterisUpdatesCheckState)checkState {
    return _checkState;
}

- (void)setCheckState:(VeterisUpdatesCheckState)checkState {
    _checkState = checkState;
    [[NSNotificationCenter defaultCenter] postNotificationName:VeterisUpdatesDidChangeNotification object:self];
}

- (void)installedApplicationsDidRefresh:(NSNotification *)notification {
    BOOL force = _forceNextCheck;
    _forceNextCheck = NO;
    [self checkInstalledApplicationsForcing:force];
}

// User apps only bc iOS 8+ also lists system apps
+ (NSDictionary *)installedVersionsFromSnapshot:(NSDictionary *)snapshot {
    NSMutableDictionary *versions = [NSMutableDictionary dictionary];
    for (NSString *bundleID in snapshot) {
        NSDictionary *info = [snapshot objectForKey:bundleID];
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0 || ![info isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *path = [info objectForKey:@"Path"];
        if (![path isKindOfClass:[NSString class]] ||
            !([path hasPrefix:@"/var/"] || [path hasPrefix:@"/private/var/"]) ||
            [path rangeOfString:@"/stash/"].location != NSNotFound) {
            continue;
        }
        NSString *version = VeterisTrimmedString([info objectForKey:@"CFBundleShortVersionString"]);
        if ([version length] == 0) {
            version = VeterisTrimmedString([info objectForKey:@"CFBundleVersion"]);
        }
        if ([version length] == 0 || [version isEqualToString:@"Unknown"]) {
            continue;
        }
        [versions setObject:version forKey:bundleID];
    }
    return versions;
}

- (void)checkInstalledApplicationsForcing:(BOOL)force {
    NSDictionary *snapshot = [AppInfo installedApplicationsSnapshot];
    if (snapshot == nil) {
        return;
    }
    NSDictionary *installed = [[self class] installedVersionsFromSnapshot:snapshot];
    if (_requestInFlight) {
        _checkAgain = YES;
        return;
    }
    if (!force) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
            return;
        }
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        BOOL changed = (_checkedVersions == nil || ![installed isEqualToDictionary:_checkedVersions]);
        BOOL stale = (_lastCheckDate == nil || now - [_lastCheckDate timeIntervalSince1970] > VeterisUpdatesRecheckInterval);
        BOOL retryTooSoon = (_checkState == VeterisUpdatesCheckStateFailed && _lastAttemptDate != nil &&
                             now - [_lastAttemptDate timeIntervalSince1970] < VeterisUpdatesRetryInterval);
        if ((!changed && !stale) || retryTooSoon) {
            return;
        }
    }
    if ([installed count] == 0) {
        _updates = [NSArray array];
        _checkedVersions = installed;
        _lastCheckDate = [NSDate date];
        [self setCheckState:VeterisUpdatesCheckStateLoaded];
        return;
    }
    [self requestUpdatesForInstalledVersions:installed];
}

- (void)requestUpdatesForInstalledVersions:(NSDictionary *)installed {
    NSMutableArray *apps = [NSMutableArray arrayWithCapacity:[installed count]];
    for (NSString *bundleID in [[installed allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [apps addObject:@{@"bundle_id" : bundleID, @"version" : [installed objectForKey:bundleID]}];
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"apps" : apps} options:0 error:NULL];
    if (body == nil) {
        [self setCheckState:VeterisUpdatesCheckStateFailed];
        return;
    }

    _requestInFlight = YES;
    _lastAttemptDate = [NSDate date];
    [self setCheckState:VeterisUpdatesCheckStateChecking];
    [VAPISS postMessage:@"listing/updates" data:body contentType:@"application/json" completion:^(NSData *data, NSError *error) {
        _requestInFlight = NO;
        NSArray *updates = nil;
        if (error == nil) {
            // No updates
            updates = ([data length] > 0) ? (NSArray *)CFBridgingRelease(decode([data bytes], [data length], VTableResponse)) : [NSArray array];
        }
        if (updates == nil) {
            debugLog(@"Update check failed: %@", error.localizedDescription);
            [self setCheckState:VeterisUpdatesCheckStateFailed];
        } else {
            NSMutableArray *validUpdates = [NSMutableArray arrayWithCapacity:[updates count]];
            for (Application *update in updates) {
                if ([update.updateBundleID length] > 0 && [update.bundleid length] > 0) {
                    [validUpdates addObject:update];
                }
            }
            _updates = validUpdates;
            _checkedVersions = installed;
            _lastCheckDate = [NSDate date];
            [self setCheckState:VeterisUpdatesCheckStateLoaded];
        }
        if (_checkAgain || _forceNextCheck) {
            BOOL force = _forceNextCheck;
            _checkAgain = NO;
            _forceNextCheck = NO;
            [self checkInstalledApplicationsForcing:force];
        }
    }];
}

#pragma mark - Muting

- (NSArray *)mutedBundleIDs {
    id muted = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisMutedUpdatesDefaultsKey];
    return [muted isKindOfClass:[NSArray class]] ? muted : [NSArray array];
}

- (BOOL)isUpdateMuted:(Application *)update {
    return [update.updateBundleID length] > 0 && [[self mutedBundleIDs] containsObject:update.updateBundleID];
}

- (void)setUpdate:(Application *)update muted:(BOOL)muted {
    NSString *bundleID = update.updateBundleID;
    if ([bundleID length] == 0) {
        return;
    }
    NSMutableArray *mutedBundleIDs = [[self mutedBundleIDs] mutableCopy];
    [mutedBundleIDs removeObject:bundleID];
    if (muted) {
        [mutedBundleIDs addObject:bundleID];
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:mutedBundleIDs forKey:VeterisMutedUpdatesDefaultsKey];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:VeterisUpdatesDidChangeNotification object:self];
}

- (NSArray *)updatesMuted:(BOOL)muted {
    NSArray *mutedBundleIDs = [self mutedBundleIDs];
    NSMutableArray *updates = [NSMutableArray array];
    for (Application *update in _updates) {
        if ([mutedBundleIDs containsObject:update.updateBundleID] == muted) {
            [updates addObject:update];
        }
    }
    return updates;
}

- (NSArray *)availableUpdates {
    return [self updatesMuted:NO];
}

- (NSArray *)mutedUpdates {
    return [self updatesMuted:YES];
}

- (NSString *)installedVersionForUpdate:(Application *)update {
    return [_checkedVersions objectForKey:update.updateBundleID];
}

#pragma mark - Installing

- (void)installUpdates:(NSArray *)updates completion:(void (^)(NSUInteger failedCount))completion {
    [self installUpdates:[updates copy] fromIndex:0 failedCount:0 completion:completion];
}


- (void)installUpdates:(NSArray *)updates fromIndex:(NSUInteger)index failedCount:(NSUInteger)failedCount completion:(void (^)(NSUInteger failedCount))completion {
    if (index >= [updates count]) {
        if (completion != nil) {
            completion(failedCount);
        }
        return;
    }
    [self loadQueueApplicationForUpdate:[updates objectAtIndex:index] completion:^(YZApplication *yzApp) {
        if (yzApp != nil) {
            [YZQueueManager enqueueYZApplicationForDownload:yzApp];
        }
        [self installUpdates:updates fromIndex:index + 1 failedCount:failedCount + (yzApp == nil ? 1 : 0) completion:completion];
    }];
}


- (void)loadQueueApplicationForUpdate:(Application *)update completion:(void (^)(YZApplication *yzApp))completion {
    NSString *path = [NSString stringWithFormat:@"listing/app/%@", [update.bundleid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [VAPISS getMessage:path completion:^(NSData *data, NSError *error) {
        Application *app = nil;
        if (error == nil && [data length] > 0) {
            app = (Application *)CFBridgingRelease(decode([data bytes], [data length], AppResponse));
        }
        Version *target = nil;
        for (Version *version in app.versions) {
            if ([version.version isEqualToString:update.version] &&
                [VeterisUpdatesBundleIDForVersion(app, version) isEqualToString:update.updateBundleID]) {
                target = version;
                break;
            }
        }
        if (target == nil) {
            debugLog(@"Update %@ %@ not found in listing/app/%@", update.updateBundleID, update.version, update.bundleid);
            completion(nil);
            return;
        }
        if (app.icon == nil) {
            app.icon = update.icon;
        }
        completion([[YZApplication alloc] initFromApp:app version:target]);
    }];
}

@end
