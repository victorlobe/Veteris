#import "YZBackgroundKeeper.h"
#import "YZQueueManager.h"
#import "YZQueueReactor.h"
#import "YZQueueNotifier.h"
#import "../VAPIHelper/VAPIHelper.h"
#import <UIKit/UIKit.h>

static const NSTimeInterval kYZLaunchHoldTimeout = 60.0;

@implementation YZBackgroundKeeper {
    UIBackgroundTaskIdentifier _backgroundTask;
    BOOL _reportedActive;
    BOOL _helperKeepsAlive;
    BOOL _expiredInBackground;
    BOOL _launchHold;
    NSUInteger _launchHoldToken;
    BOOL _backgroundSessionHadWork;
    BOOL _interrupting;
}

+ (YZBackgroundKeeper *)sharedInstance {
    static YZBackgroundKeeper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[YZBackgroundKeeper alloc] init];
    });
    return sharedInstance;
}



- (instancetype)init {
    self = [super init];
    if (self) {
        _backgroundTask = UIBackgroundTaskInvalid;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(queueStateChanged:) name:@"YZQueueRepStateChange" object:nil];
        [center addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)queueStateChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self update];
        });
        return;
    }
    [self update];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    if ([YZQueueManager hasActiveWork]) {
        [[YZQueueNotifier sharedInstance] notifyContinuingInBackground];
    }
    [self update];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    _expiredInBackground = NO;
    _backgroundSessionHadWork = NO;
    [YZQueueManager resumeInterruptedTransfers];
    [self update];
}

- (void)update {
    BOOL queueWork = [YZQueueManager hasActiveWork];
    BOOL hasWork = _launchHold || queueWork;
    BOOL inBackground = ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground);
    if (queueWork && inBackground) {
        _backgroundSessionHadWork = YES;
    }
    if (hasWork) {
        [self beginBackgroundTaskIfNeeded];
    } else {
        [self endBackgroundTask];
    }
    if (hasWork == _reportedActive) {
        return;
    }
    _reportedActive = hasWork;
    _helperKeepsAlive = NO;
    if (hasWork && [UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        [[YZQueueNotifier sharedInstance] requestPermissionIfNeeded];
    }
    if (!hasWork && inBackground && _backgroundSessionHadWork && !_interrupting) {
        _backgroundSessionHadWork = NO;
        // Post the background status
        dispatch_async(dispatch_get_main_queue(), ^{
            [[YZQueueNotifier sharedInstance] notifyBackgroundWorkFinished];
        });
    }
    [[YZQueueReactor sharedInstance] setBackgroundWorkActive:hasWork completion:^(BOOL helperKeepsAlive) {
        if (_reportedActive == hasWork) {
            _helperKeepsAlive = hasWork && helperKeepsAlive;
        }
    }];
}

- (void)holdForLaunchRestore {
    _launchHold = YES;
    NSUInteger token = ++_launchHoldToken;
    [self update];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYZLaunchHoldTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (_launchHold && _launchHoldToken == token) {
            [self releaseLaunchHold];
        }
    });
}

- (void)releaseLaunchHold {
    if (!_launchHold) {
        return;
    }
    _launchHold = NO;
    _launchHoldToken++;
    [self update];
}

#pragma mark - Background task

- (void)beginBackgroundTaskIfNeeded {
    if (_backgroundTask != UIBackgroundTaskInvalid || _expiredInBackground) {
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    _backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [self backgroundTaskExpired];
    }];
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        debugLog(@"Began background task for queue work");
    }
}

- (void)endBackgroundTask {
    if (_backgroundTask == UIBackgroundTaskInvalid) {
        return;
    }
    UIBackgroundTaskIdentifier task = _backgroundTask;
    _backgroundTask = UIBackgroundTaskInvalid;
    [[UIApplication sharedApplication] endBackgroundTask:task];
    debugLog(@"Ended background task for queue work");
}

// iOS suspends Veteris after this unless the helper holds it
- (void)backgroundTaskExpired {
    debugLog(@"Background time expired (helper keeps alive: %d)", _helperKeepsAlive);
    _expiredInBackground = YES;
    if (!_helperKeepsAlive) {
        // Pause
        _interrupting = YES;
        NSUInteger interruptedCount = [YZQueueManager interruptActiveTransfers];
        _interrupting = NO;
        if (interruptedCount > 0) {
            _backgroundSessionHadWork = NO;
            [[YZQueueNotifier sharedInstance] notifyDownloadsPaused];
        }
    }
    [self endBackgroundTask];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
