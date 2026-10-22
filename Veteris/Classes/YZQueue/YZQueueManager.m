#import "YZQueueManager.h"
#import "YZQueueReactor.h"
#import "YZBackgroundKeeper.h"
#import "YZQueueNotifier.h"
#import "YZDownloadResumeStore.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../BBHTTP/BBHTTP.h"

static void YZQueueRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static BOOL YZQueueRunOnMainSync(BOOL (^block)(void)) {
    if ([NSThread isMainThread]) {
        return block();
    }
    __block BOOL result = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        result = block();
    });
    return result;
}

static NSUInteger YZQueueMaxConcurrentDownloads(void) {
    return [VeterisMemoryProfile maxConcurrentDownloads];
}

static NSString *YZQueueDownloadURLForApplication(YZApplication *yzApp) {
    NSString *downloadURL = yzApp.url;
    if ([downloadURL length] == 0) {
        return nil;
    }
    if (![downloadURL hasPrefix:@"http://"] && ![downloadURL hasPrefix:@"https://"]) {
        downloadURL = [NSString stringWithFormat:@"%@static/%@", [VAPIHelper getApiStaticURL], [downloadURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    return downloadURL;
}

@implementation YZQueueManager {
    dispatch_queue_t _installQueue;
    NSNotificationCenter *_nc;
    NSMutableArray *_reps;
    NSObject *_repsLock;
    NSUInteger _sequence;
    BOOL _pumpScheduled;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        [self start];
    }
    return self;
}

+ (YZQueueManager *)sharedInstance {
    static YZQueueManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[YZQueueManager alloc] init];
        BBHTTPExecutor *executor = [BBHTTPExecutor sharedExecutor];
        executor.maxParallelRequests = YZQueueMaxConcurrentDownloads();
    });
    return sharedInstance;
}

- (void)start {
    _installQueue = dispatch_queue_create("com.victorlobe.veteris.queue.install", DISPATCH_QUEUE_SERIAL);
    _nc = [NSNotificationCenter defaultCenter];
    [_nc addObserver:self selector:@selector(handleNotification:) name:@"YZQueueRepStateChange" object:nil];
    _reps = [NSMutableArray array];
    _repsLock = [[NSObject alloc] init];
    [YZQueueReactor sharedInstance];
    [YZBackgroundKeeper sharedInstance];
    [YZQueueNotifier sharedInstance];
    debugLog(@"YZQueueManager started");
}

#pragma mark - Public API

+ (void)enqueueYZApplicationForDownload:(YZApplication *)yzApp {
    [BBHTTPExecutor sharedExecutor].maxParallelRequests = YZQueueMaxConcurrentDownloads();
    YZQueueRunOnMain(^{
        NSString *downloadURL = YZQueueDownloadURLForApplication(yzApp);
        NSString *targetPath = downloadPathForVersion(yzApp.bundleID, yzApp.version);
        [YZQM enqueueApplication:yzApp sourceURL:downloadURL targetPath:targetPath installAfterDownload:YES trackDownloadStart:YES paused:NO userPaused:NO];
    });
}

+ (void)enqueueYZApplicationForDownloadOnly:(YZApplication *)yzApp targetPath:(NSString *)targetPath {
    [BBHTTPExecutor sharedExecutor].maxParallelRequests = YZQueueMaxConcurrentDownloads();
    YZQueueRunOnMain(^{
        NSString *downloadURL = YZQueueDownloadURLForApplication(yzApp);
        [YZQM enqueueApplication:yzApp sourceURL:downloadURL targetPath:targetPath installAfterDownload:NO trackDownloadStart:YES paused:NO userPaused:NO];
    });
}

+ (void)enqueueYZApplicationDownloaded:(YZApplication *)yzApp {
    YZQueueRunOnMain(^{
        [YZQM enqueueApplication:yzApp sourceURL:nil targetPath:nil installAfterDownload:YES trackDownloadStart:NO paused:NO userPaused:NO];
    });
}

+ (void)restorePendingDownloadsResumingInterrupted:(BOOL)resumeInterrupted {
    YZQueueRunOnMain(^{
        NSUInteger resumedCount = 0;
        NSArray *records = [YZDownloadResumeStore pendingRecords];
        for (NSDictionary *record in records) {
            YZApplication *application = [YZDownloadResumeStore applicationFromRecord:record];
            NSString *sourceURL = [record objectForKey:@"source_url"];
            NSString *targetPath = [record objectForKey:@"target_path"];
            BOOL installAfterDownload = [[record objectForKey:@"install_after_download"] boolValue];
            BOOL userPaused = [YZDownloadResumeStore isUserPausedRecord:record];
            if (application == nil || [sourceURL length] == 0 || [targetPath length] == 0) {
                [YZDownloadResumeStore removeRecordForTargetPath:targetPath];
                continue;
            }
            if ([YZQM repWithTargetPath:targetPath] != nil) {
                continue;
            }
            debugLog(@"Restoring pending download %@ %@", application.bundleID, application.version);
            [YZQM enqueueApplication:application sourceURL:sourceURL targetPath:targetPath installAfterDownload:installAfterDownload trackDownloadStart:NO paused:YES userPaused:userPaused];
            if (resumeInterrupted && !userPaused) {
                debugLog(@"Continuing %@ %@ after a background relaunch", application.bundleID, application.version);
                if ([YZQM retryRepOnMain:[YZQM repWithTargetPath:targetPath]]) {
                    resumedCount++;
                }
            }
        }
        if (resumedCount > 0) {
            [[YZQueueNotifier sharedInstance] notifyRelaunchedInBackground];
        }
    });
}

+ (void)holdBackgroundLaunchUntilRestored {
    YZQueueRunOnMain(^{
        [[YZBackgroundKeeper sharedInstance] holdForLaunchRestore];
    });
}

+ (void)releaseBackgroundLaunchHold {
    YZQueueRunOnMain(^{
        [[YZBackgroundKeeper sharedInstance] releaseLaunchHold];
    });
}

+ (BOOL)hasActiveWork {
    for (YZQueueRep *rep in [self allReps]) {
        if (rep.invalid) {
            continue;
        }
        switch (rep.state) {
            case YZRepStateQueued:
            case YZRepStateDownloading:
            case YZRepStateInstalling:
                return YES;
            case YZRepStateDownloaded:
                if (rep.installAfterDownload) {
                    return YES;
                }
                break;
            default:
                break;
        }
    }
    return NO;
}

+ (NSUInteger)interruptActiveTransfers {
    NSUInteger interruptedCount = 0;
    for (YZQueueRep *rep in [YZQueueManager allReps]) {
        if (rep.invalid || (rep.state != YZRepStateDownloading && rep.state != YZRepStateQueued)) {
            continue;
        }
        debugLog(@"Interrupting %@ for the end of the background time", rep.bundleID);
        rep.downloadGeneration++;
        [YZQueueOps stopTransferForRep:rep];
        rep.userPaused = NO;
        rep.interruptedBySystem = YES;
        rep.state = YZRepStatePaused;
        [rep refreshStoredDownloadProgress];
        interruptedCount++;
    }
    return interruptedCount;
}

+ (void)resumeInterruptedTransfers {
    YZQueueRunOnMain(^{
        for (YZQueueRep *rep in [YZQueueManager allReps]) {
            if (!rep.invalid && rep.interruptedBySystem && rep.state == YZRepStatePaused) {
                [YZQM retryRepOnMain:rep];
            }
        }
    });
}

+ (NSArray *)pendingResumeTargetPaths {
    return [YZDownloadResumeStore pendingTargetPaths];
}

+ (BOOL)isTargetPathInUse:(NSString *)targetPath {
    if ([targetPath length] == 0) {
        return NO;
    }
    YZQueueManager *manager = YZQM;
    @synchronized (manager->_repsLock) {
        for (YZQueueRep *rep in manager->_reps) {
            if ([rep ownsDownloadFiles] && [rep.targetPath isEqualToString:targetPath]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (bool)markRepAsCancelled:(YZQueueRep *)rep {
    return YZQueueRunOnMainSync(^BOOL{
        return [YZQM cancelRep:rep];
    });
}

+ (bool)pauseRep:(YZQueueRep *)rep {
    return YZQueueRunOnMainSync(^BOOL{
        return [YZQM pauseRepOnMain:rep];
    });
}

+ (bool)retryRep:(YZQueueRep *)rep {
    return YZQueueRunOnMainSync(^BOOL{
        return [YZQM retryRepOnMain:rep];
    });
}

+ (NSArray *)allReps {
    YZQueueManager *manager = YZQM;
    @synchronized (manager->_repsLock) {
        return [manager->_reps copy];
    }
}

+ (NSUInteger)activeDownloadsCount {
    NSUInteger count = 0;
    YZQueueManager *manager = YZQM;
    @synchronized (manager->_repsLock) {
        for (YZQueueRep *rep in manager->_reps) {
            if (!rep.invalid && (rep.state == YZRepStateDownloading || rep.state == YZRepStateQueued)) {
                count++;
            }
        }
    }
    return count;
}

+ (void)attachProgressBlock:(void (^)(NSUInteger current, NSUInteger total))block toRep:(YZQueueRep *)rep {
    YZQueueRunOnMain(^{
        YZQueueRep *actualRep = [YZQM actualRepForRep:rep];
        if (actualRep == nil) {
            return;
        }
        [actualRep refreshStoredDownloadProgress];
        if (block != nil && actualRep.storedProgressCurrent > 0) {
            block(actualRep.storedProgressCurrent, actualRep.storedProgressTotal);
        }
        actualRep.downloadProgressBlock = block;
    });
}

#pragma mark - Queue bookkeeping (main thread)

- (YZQueueRep *)actualRepForRep:(YZQueueRep *)rep {
    if (rep == nil) {
        return nil;
    }
    @synchronized (_repsLock) {
        NSUInteger index = [_reps indexOfObjectIdenticalTo:rep];
        return index != NSNotFound ? rep : nil;
    }
}

- (YZQueueRep *)repWithTargetPath:(NSString *)targetPath {
    if ([targetPath length] == 0) {
        return nil;
    }
    @synchronized (_repsLock) {
        for (YZQueueRep *rep in _reps) {
            if ([rep.targetPath isEqualToString:targetPath]) {
                return rep;
            }
        }
    }
    return nil;
}

- (YZQueueRep *)localRepWithPath:(NSString *)path {
    if ([path length] == 0) {
        return nil;
    }
    @synchronized (_repsLock) {
        for (YZQueueRep *rep in _reps) {
            if (![rep ownsDownloadFiles] && [rep.path isEqualToString:path]) {
                return rep;
            }
        }
    }
    return nil;
}

- (void)addRep:(YZQueueRep *)rep {
    @synchronized (_repsLock) {
        [_reps addObject:rep];
    }
}

- (void)removeRep:(YZQueueRep *)rep {
    @synchronized (_repsLock) {
        rep.invalid = YES;
        [_reps removeObjectIdenticalTo:rep];
    }
}

- (void)enqueueApplication:(YZApplication *)application
                 sourceURL:(NSString *)sourceURL
                targetPath:(NSString *)targetPath
      installAfterDownload:(BOOL)installAfterDownload
        trackDownloadStart:(BOOL)trackDownloadStart
                    paused:(BOOL)paused
                userPaused:(BOOL)userPaused {
    if (application == nil) {
        return;
    }
    BOOL isLocalIPA = ([sourceURL length] == 0);
    if (!isLocalIPA && [targetPath length] == 0) {
        return;
    }

    YZQueueRep *existing = isLocalIPA ? [self localRepWithPath:application.path] : [self repWithTargetPath:targetPath];
    if (existing != nil) {
        switch (existing.state) {
            case YZRepStateQueued:
            case YZRepStateDownloading:
            case YZRepStateInstalling:
                return;
            case YZRepStateDownloaded:
                if (existing.installAfterDownload || !installAfterDownload) {
                    return;
                }
                break;
            case YZRepStatePaused:
            case YZRepStateFailed:
                if (!paused) {
                    [self retryRepOnMain:existing];
                }
                return;
            case YZRepStateInstalled:
            case YZRepStateCancelled:
                break;
        }
        [self removeRep:existing];
    }

    if (installAfterDownload && !paused && [application.bundleID length] > 0) {
        for (YZQueueRep *other in [YZQueueManager allReps]) {
            if (!other.installAfterDownload || ![other.bundleID isEqualToString:application.bundleID]) {
                continue;
            }
            if (other.state == YZRepStateQueued || other.state == YZRepStateDownloading ||
                other.state == YZRepStatePaused || other.state == YZRepStateFailed ||
                other.state == YZRepStateDownloaded) {
                debugLog(@"Replacing queued install of %@ %@ with version %@", other.bundleID, other.version, application.version);
                [self cancelRep:other];
            }
        }
    }

    YZQueueRep *rep = [[YZQueueRep alloc] initWithApplication:application
                                                    sourceURL:sourceURL
                                                   targetPath:targetPath
                                         installAfterDownload:installAfterDownload
                                           trackDownloadStart:trackDownloadStart];
    rep.enqueueSequence = ++_sequence;
    [self addRep:rep];
    if (isLocalIPA) {
        rep.state = YZRepStateDownloaded;
    } else if (paused) {
        rep.userPaused = userPaused;
        rep.state = YZRepStatePaused;
    } else {
        rep.state = YZRepStateQueued;
    }
    [self schedulePump];
}

- (void)schedulePump {
    if (_pumpScheduled) {
        return;
    }
    _pumpScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        _pumpScheduled = NO;
        [self pumpQueue];
    });
}

- (void)pumpQueue {
    NSArray *reps = [YZQueueManager allReps];
    NSUInteger active = 0;
    for (YZQueueRep *rep in reps) {
        if (!rep.invalid && rep.state == YZRepStateDownloading) {
            active++;
        }
    }
    NSUInteger limit = YZQueueMaxConcurrentDownloads();
    for (YZQueueRep *rep in reps) {
        if (active >= limit) {
            break;
        }
        if (rep.invalid || rep.state != YZRepStateQueued) {
            continue;
        }
        [self startRep:rep];
        active++;
    }
}

- (void)startRep:(YZQueueRep *)rep {
    rep.downloadGeneration++;
    rep.errorDetails = nil;
    rep.installScheduled = NO;
    rep.state = YZRepStateDownloading;
    if (rep.trackDownloadStart) {
        rep.trackDownloadStart = NO;
        [VAPIHelper trackDownloadStartForApplication:[rep application] url:rep.sourceURL downloadOnly:!rep.installAfterDownload];
    }
    [YZQueueOps startDownloadForRep:rep];
}

- (BOOL)cancelRep:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [self actualRepForRep:rep];
    if (actualRep == nil) {
        return NO;
    }
    if (actualRep.state == YZRepStateInstalling) {
        return NO;
    }
    debugLog(@"Cancelling %@ %@", actualRep.bundleID, actualRep.version);
    YZRepState previousState = actualRep.state;
    actualRep.downloadGeneration++;
    [YZQueueOps stopTransferForRep:actualRep];

    BOOL keepsUserFile = (previousState == YZRepStateDownloaded && !actualRep.installAfterDownload);
    BOOL deleteFiles = [actualRep ownsDownloadFiles] && !keepsUserFile && previousState != YZRepStateInstalled;
    NSString *targetPath = actualRep.targetPath;
    if ([actualRep ownsDownloadFiles]) {
        [YZDownloadResumeStore removeRecordForTargetPath:targetPath];
    }
    [self removeRep:actualRep];
    if (rep != actualRep) {
        rep.invalid = YES;
    }

    if (deleteFiles) {
        // Do not reuse the path until the previous writer has stopped.
        [YZQueueOps performWhenTargetPathIdle:targetPath block:^{
            if ([self repWithTargetPath:targetPath] == nil) {
                [YZDownloadResumeStore removeArtifactsForTargetPath:targetPath includingTarget:YES];
            }
        }];
    }
    [YZQueueOps notifyAppState:nil];
    [self schedulePump];
    return YES;
}

- (BOOL)pauseRepOnMain:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [self actualRepForRep:rep];
    if (actualRep == nil || (actualRep.state != YZRepStateDownloading && actualRep.state != YZRepStateQueued)) {
        return NO;
    }
    debugLog(@"Pausing %@", actualRep.bundleID);
    actualRep.downloadGeneration++;
    [YZQueueOps stopTransferForRep:actualRep];
    actualRep.userPaused = YES;
    actualRep.interruptedBySystem = NO;
    actualRep.state = YZRepStatePaused;
    [actualRep refreshStoredDownloadProgress];
    [self schedulePump];
    return YES;
}

- (BOOL)retryRepOnMain:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [self actualRepForRep:rep];
    if (actualRep == nil || (actualRep.state != YZRepStatePaused && actualRep.state != YZRepStateFailed)) {
        return NO;
    }
    actualRep.errorDetails = nil;
    actualRep.installScheduled = NO;
    actualRep.userPaused = NO;
    actualRep.interruptedBySystem = NO;
    if (![actualRep ownsDownloadFiles]) {
        // Retrying an IPA opened from another app installs it again.
        if (!actualRep.installAfterDownload || ![[NSFileManager defaultManager] fileExistsAtPath:actualRep.path]) {
            return NO;
        }
        actualRep.state = YZRepStateDownloaded;
        return YES;
    }
    actualRep.state = YZRepStateQueued;
    [self schedulePump];
    return YES;
}

#pragma mark - Install

- (void)enqueueAppContainerForInstall:(YZQueueRep *)appRep {
    appRep.installScheduled = YES;
    dispatch_async(_installQueue, ^{
        __block NSString *path = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (appRep.invalid || appRep.state != YZRepStateDownloaded || !appRep.installAfterDownload) {
                return;
            }
            path = [appRep.path copy];
            appRep.errorDetails = nil;
            appRep.state = YZRepStateInstalling;
        });
        if ([path length] == 0) {
            return;
        }
        [VAPISS clearMemoryCaches];
        NSString *errorDetails = nil;
        BOOL installed = [YZQueueOps installIPA:path errorDetails:&errorDetails];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (installed) {
                appRep.state = YZRepStateInstalled;
            } else {
                appRep.errorDetails = errorDetails;
                appRep.state = YZRepStateFailed;
            }
            [self schedulePump];
        });
    });
}

#pragma mark - Notification Handling

- (void)handleNotification:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleNotification:notification];
        });
        return;
    }
    YZQueueRep *rep = notification.object;
    if (rep == nil || rep.invalid || [self actualRepForRep:rep] == nil) {
        return;
    }
    switch (rep.state) {
        case YZRepStateDownloaded:
            if (rep.installAfterDownload && !rep.installScheduled) {
                [self enqueueAppContainerForInstall:rep];
            }
            [self schedulePump];
            break;
        case YZRepStateFailed:
        case YZRepStatePaused:
        case YZRepStateInstalled:
            [self schedulePump];
            break;
        default:
            break;
    }
}

- (void)dealloc {
    [_nc removeObserver:self];
}
@end
