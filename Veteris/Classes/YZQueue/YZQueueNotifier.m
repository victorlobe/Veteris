#import "YZQueueNotifier.h"
#import "YZQueueRep.h"
#import "../VAPIHelper/VAPIHelper.h"
#import <UIKit/UIKit.h>

NSString *const YZDownloadNotificationsEnabledKey = @"veteris_download_notifications_enabled";
NSString *const YZBackgroundStatusNotificationsEnabledKey = @"veteris_background_status_notifications_enabled";

static NSString *const YZQueueNotificationKindKey = @"veteris_queue_notification";

static NSString *YZNotificationString(NSString *key, NSString *english) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:english table:nil];
}

static NSString *YZNotificationAppTitle(YZQueueRep *rep) {
    NSString *name = [rep.name length] > 0 ? rep.name : rep.bundleID;
    if ([name length] == 0) {
        name = @"?";
    }
    return [rep.version length] > 0 ? [NSString stringWithFormat:@"%@ %@", name, rep.version] : name;
}

@implementation YZQueueNotifier {
    BOOL _permissionRequested;
}

+ (YZQueueNotifier *)sharedInstance {
    static YZQueueNotifier *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[YZQueueNotifier alloc] init];
    });
    return sharedInstance;
}

+ (BOOL)isQueueNotification:(UILocalNotification *)notification {
    return [[notification.userInfo objectForKey:YZQueueNotificationKindKey] isKindOfClass:[NSString class]];
}


- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(queueStateChanged:) name:@"YZQueueRepStateChange" object:nil];
    }
    return self;
}

- (BOOL)downloadNotificationsEnabled {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:YZDownloadNotificationsEnabledKey];
    return value == nil || [value boolValue];
}

- (BOOL)backgroundStatusNotificationsEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:YZBackgroundStatusNotificationsEnabledKey];
}

- (void)requestPermissionIfNeeded {
    if (_permissionRequested || (![self downloadNotificationsEnabled] && ![self backgroundStatusNotificationsEnabled])) {
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
    if (settingsClass == Nil || ![application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        return;
    }
    _permissionRequested = YES;
    id settings = [settingsClass settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeSound) categories:nil];
    [application registerUserNotificationSettings:settings];
}

#pragma mark - Download notifications

- (void)queueStateChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self queueStateChanged:notification];
        });
        return;
    }
    YZQueueRep *rep = notification.object;
    if (![rep isKindOfClass:[YZQueueRep class]] || rep.invalid || ![self downloadNotificationsEnabled]) {
        return;
    }
    switch (rep.state) {
        case YZRepStateInstalled:
            if (rep.previousState == YZRepStateInstalling) {
                [self postKind:@"installed" body:[NSString stringWithFormat:YZNotificationString(@"NotificationAppInstalled", @"%@ was installed."), YZNotificationAppTitle(rep)] sound:YES];
            }
            break;
        case YZRepStateDownloaded:
            if (!rep.installAfterDownload && rep.previousState == YZRepStateDownloading) {
                [self postKind:@"downloaded" body:[NSString stringWithFormat:YZNotificationString(@"NotificationAppDownloaded", @"%@ was downloaded."), YZNotificationAppTitle(rep)] sound:YES];
            }
            break;
        case YZRepStateFailed:
            if (rep.previousState == YZRepStateInstalling) {
                [self postKind:@"install_failed" body:[NSString stringWithFormat:YZNotificationString(@"NotificationInstallFailed", @"%@ could not be installed."), YZNotificationAppTitle(rep)] sound:YES];
            } else if (rep.previousState != YZRepStateFailed) {
                [self postKind:@"download_failed" body:[NSString stringWithFormat:YZNotificationString(@"NotificationDownloadFailed", @"%@ could not be downloaded."), YZNotificationAppTitle(rep)] sound:YES];
            }
            break;
        default:
            break;
    }
}

- (void)notifyDownloadsPaused {
    if ([self downloadNotificationsEnabled]) {
        [self postKind:@"paused" body:YZNotificationString(@"NotificationDownloadsPaused", @"Downloads were paused. Open Veteris to continue them.") sound:YES];
    }
}

#pragma mark - Background status notifications

- (void)notifyContinuingInBackground {
    if ([self backgroundStatusNotificationsEnabled]) {
        [self postKind:@"background_continuing" body:YZNotificationString(@"NotificationContinuingInBackground", @"Veteris continues your downloads in the background.") sound:NO];
    }
}

- (void)notifyRelaunchedInBackground {
    if ([self backgroundStatusNotificationsEnabled]) {
        [self postKind:@"background_relaunched" body:YZNotificationString(@"NotificationRelaunchedInBackground", @"Veteris was closed and restarted in the background to finish your downloads.") sound:NO];
    }
}

- (void)notifyBackgroundWorkFinished {
    if ([self backgroundStatusNotificationsEnabled]) {
        [self postKind:@"background_finished" body:YZNotificationString(@"NotificationBackgroundWorkFinished", @"Veteris has finished all downloads and no longer runs in the background.") sound:NO];
    }
}

#pragma mark - Posting

- (void)postKind:(NSString *)kind body:(NSString *)body sound:(BOOL)sound {
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive || [body length] == 0) {
        return;
    }
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    localNotification.alertBody = body;
    if (sound) {
        localNotification.soundName = UILocalNotificationDefaultSoundName;
    }
    localNotification.userInfo = [NSDictionary dictionaryWithObject:kind forKey:YZQueueNotificationKindKey];
    [application presentLocalNotificationNow:localNotification];
    debugLog(@"Posted %@ notification", kind);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
