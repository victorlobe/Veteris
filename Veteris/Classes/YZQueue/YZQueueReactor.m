#import "YZQueueReactor.h"
#import "YZQueueState.h"
#import "../../Clutch/ApplicationLister.h"
#import "../../AppDelegate.h"
#import <AppSupport/CPDistributedMessagingCenter.h>

static BOOL YZQueueReactorHasBundleID(NSString *bundleId) {
    return [bundleId isKindOfClass:[NSString class]] && [bundleId length] > 0;
}

@implementation YZQueueReactor {
    NSNotificationCenter *_notificationCenter;
    YZQueueState *_state;
    NSMutableArray *_systemInstalledApps;
    dispatch_queue_t _queue;
    CPDistributedMessagingCenter *_distributedMessageCenter;
}

+ (YZQueueReactor *)sharedInstance {
    static YZQueueReactor *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[YZQueueReactor alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self start];
    }
    return self;
}

- (void)start {
    _systemInstalledApps = [NSMutableArray new];
    _queue = dispatch_queue_create("com.victorlobe.veteris.queue.reactor", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(_queue, ^{
        _notificationCenter = [NSNotificationCenter defaultCenter];
        [_notificationCenter addObserver:self selector:@selector(handleNotification:) name:@"YZQueueRepStateChange" object:nil];
        _distributedMessageCenter = [CPDistributedMessagingCenter centerNamed:@"com.victorlobe.veterishelper"];
        _state = [[YZQueueState alloc] init];
        [self refreshInstalledApps];
    });
}

- (void)handleNotification:(NSNotification *)notification {
    YZQueueRep *rep = notification.object;
    if (rep == nil) {
        return;
    }
    if (rep.state == YZRepStateInstalled) {
        if ([_systemInstalledApps containsObject:rep.bundleID]) {
            return;
        }
        [self markNewlyInstalled:rep.bundleID];
        [_systemInstalledApps addObject:rep.bundleID];
    }
}

- (void)refreshInstalledApps {
    for (NSString *key in [[[ApplicationLister sharedInstance] installedApps] allKeys]) {
        if (![_systemInstalledApps containsObject:key]) {
            [_systemInstalledApps addObject:key];
        }
    }
}

- (void)markNewlyInstalled:(NSString *)bundleId {
    if (SYSTEM_VERSION_LESS_THAN(@"6.0")) {
        return;
    }
    if (!YZQueueReactorHasBundleID(bundleId)) {
        debugLog(@"Skipping mark newly installed with missing bundle identifier");
        return;
    }
    [_distributedMessageCenter sendMessageName:@"com.victorlobe.veteris.MarkNewlyInstalled" userInfo:@{@"bundleIdentifier": bundleId}];
}

- (void)launchApp:(NSString *)bundleId {
    if (!YZQueueReactorHasBundleID(bundleId)) {
        debugLog(@"Skipping launch with missing bundle identifier");
        return;
    }
    debugLog(@"Launching app: %@", bundleId);
    [_distributedMessageCenter sendMessageName:@"com.victorlobe.veteris.LaunchApp" userInfo:@{@"bundleIdentifier": bundleId}];
}

@end
