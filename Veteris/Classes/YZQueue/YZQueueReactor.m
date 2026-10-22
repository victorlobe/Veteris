#import "YZQueueReactor.h"
#import "YZQueueState.h"
#import "../../Clutch/ApplicationLister.h"
#import "../../AppDelegate.h"
#import <AppSupport/CPDistributedMessagingCenter.h>
#import <unistd.h>

static NSString *const YZHelperCenterName = @"com.victorlobe.veterishelper";
static NSString *const YZHelperMessageBackgroundWorkBegin = @"com.victorlobe.veteris.BackgroundWorkBegin";
static NSString *const YZHelperMessageBackgroundWorkEnd = @"com.victorlobe.veteris.BackgroundWorkEnd";

static BOOL YZQueueReactorHasBundleID(NSString *bundleId) {
    return [bundleId isKindOfClass:[NSString class]] && [bundleId length] > 0;
}

@implementation YZQueueReactor {
    NSNotificationCenter *_notificationCenter;
    YZQueueState *_state;
    NSMutableArray *_systemInstalledApps;
    dispatch_queue_t _queue;
    dispatch_queue_t _helperQueue; // preserve the order of background begin/end messages
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
    _helperQueue = dispatch_queue_create("com.victorlobe.veteris.queue.helper", DISPATCH_QUEUE_SERIAL);
    dispatch_async(_queue, ^{
        _notificationCenter = [NSNotificationCenter defaultCenter];
        [_notificationCenter addObserver:self selector:@selector(handleNotification:) name:@"YZQueueRepStateChange" object:nil];
        _distributedMessageCenter = [CPDistributedMessagingCenter centerNamed:YZHelperCenterName];
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
        NSString *bundleID = rep.bundleID;
        if (!YZQueueReactorHasBundleID(bundleID)) {
            return;
        }
        @synchronized (_systemInstalledApps) {
            if ([_systemInstalledApps containsObject:bundleID]) {
                return;
            }
            [_systemInstalledApps addObject:bundleID];
        }
        [self markNewlyInstalled:bundleID];
    }
}

- (void)refreshInstalledApps {
    NSArray *installed = [[[ApplicationLister sharedInstance] installedApps] allKeys];
    @synchronized (_systemInstalledApps) {
        for (NSString *key in installed) {
            if (![_systemInstalledApps containsObject:key]) {
                [_systemInstalledApps addObject:key];
            }
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

- (void)setBackgroundWorkActive:(BOOL)active completion:(void (^)(BOOL helperKeepsAlive))completion {
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:getpid()] forKey:@"pid"];
    dispatch_async(_helperQueue, ^{
        CPDistributedMessagingCenter *center = [CPDistributedMessagingCenter centerNamed:YZHelperCenterName];
        BOOL keepsAlive = NO;
        if (active) {
            NSDictionary *reply = [center sendMessageAndReceiveReplyName:YZHelperMessageBackgroundWorkBegin userInfo:userInfo];
            id value = [reply isKindOfClass:[NSDictionary class]] ? [reply objectForKey:@"keepAlive"] : nil;
            keepsAlive = [value respondsToSelector:@selector(boolValue)] && [value boolValue];
        } else {
            [center sendMessageName:YZHelperMessageBackgroundWorkEnd userInfo:userInfo];
        }
        debugLog(@"Background work %@ reported to VeterisHelper (keep alive: %d)", active ? @"start" : @"end", keepsAlive);
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(keepsAlive);
            });
        }
    });
}

@end
