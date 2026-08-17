#import "YZQueueManager.h"
#import "YZQueueReactor.h"
#import "YZArchiveTLSDownloader.h"
#import "YZDownloadResumeStore.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../BBHTTP/BBHTTP.h"

@implementation YZQueueManager {
    dispatch_queue_t _installQueue;
    dispatch_queue_t _queue;
    NSNotificationCenter *_nc;
    NSMutableSet *_reps;
    NSObject *_repsLock;
    YZQueueReactor *_reactor;
}

struct StateContext {
    YZRepState state;
    NSUInteger *count;
};

static void YZRemoveDownloadPartFiles(NSString *targetPath) {
    NSString *directory = [targetPath stringByDeletingLastPathComponent];
    NSString *prefix = [[targetPath lastPathComponent] stringByAppendingString:@".part."];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *entry in contents) {
        if (![entry hasPrefix:prefix]) {
            continue;
        }
        NSString *suffix = [entry substringFromIndex:[prefix length]];
        if ([suffix length] == 0 || [suffix rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
            continue;
        }
        [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:entry] error:nil];
    }
}

#pragma - mark Initialization

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
        executor.maxParallelRequests = [VAPIHelper usesLowMemoryDownloadMode] ? 1 : 3;
    });
    return sharedInstance;
}

- (void)start {
    _installQueue = dispatch_queue_create("com.victorlobe.veteris.queue.install", DISPATCH_QUEUE_SERIAL);
    _queue = dispatch_queue_create("com.victorlobe.veteris.queue.main", DISPATCH_QUEUE_CONCURRENT);
    _nc = [NSNotificationCenter defaultCenter];
    [_nc addObserver:self selector:@selector(handleNotification:) name:@"YZQueueRepStateChange" object:nil];
    _reps = [NSMutableSet new];
    _repsLock = [[NSObject alloc] init];
    _reactor = [[YZQueueReactor alloc] init];
    debugLog(@"YZQueueManager started");
        // Application *app = [[Application alloc] init];
        // app.app_description = @"This is a description";
        // app.developer = @"Developer";
        // app.name = @"App Name";
        // app.bundleid = @"com.example.app";
        // app.icon = [UIImage imageNamed:@"icon.png"];
        // Version *version = [[Version alloc] init];
        // version.version = @"1.0";
        // YZApplication *app2 = [[YZApplication alloc] initFromApp:app version:version];

        // [YZQueueRep detachRepWithYZApp:app2 andURL:nil];
}

#pragma - mark Queue Operations
+ (void)enqueueYZApplicationForDownload:(YZApplication *)yzApp {
    [BBHTTPExecutor sharedExecutor].maxParallelRequests = [VAPIHelper usesLowMemoryDownloadMode] ? 1 : 3;
    dispatch_async([YZQueueManager sharedInstance]->_queue, ^{
        NSString *downloadURL = yzApp.url;
        if (![downloadURL hasPrefix:@"http://"] && ![downloadURL hasPrefix:@"https://"]) {
            downloadURL = [NSString stringWithFormat:@"%@static/%@", [VAPIHelper getApiStaticURL], [downloadURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        }
        [YZQueueRep detachRepWithYZApp:yzApp andURL:downloadURL];
    });
}

+ (void)enqueueYZApplicationForDownloadOnly:(YZApplication *)yzApp targetPath:(NSString *)targetPath {
    [BBHTTPExecutor sharedExecutor].maxParallelRequests = [VAPIHelper usesLowMemoryDownloadMode] ? 1 : 3;
    dispatch_async([YZQueueManager sharedInstance]->_queue, ^{
        NSString *downloadURL = yzApp.url;
        if (![downloadURL hasPrefix:@"http://"] && ![downloadURL hasPrefix:@"https://"]) {
            downloadURL = [NSString stringWithFormat:@"%@static/%@", [VAPIHelper getApiStaticURL], [downloadURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        }
        NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            debugLog(@"Failed to create download-only directory %@: %@", targetDir, [error localizedDescription]);
            return;
        }
        [YZQueueRep detachDownloadOnlyRepWithYZApp:yzApp andURL:downloadURL targetPath:targetPath];
    });
}

+ (void)enqueueYZApplicationDownloaded:(YZApplication *)yzApp {
    dispatch_async([YZQueueManager sharedInstance]->_queue, ^{
        [YZQueueRep detachRepWithYZApp:yzApp andURL:nil];
    });
}

+ (void)restorePendingDownloads {
    dispatch_async([YZQueueManager sharedInstance]->_queue, ^{
        NSArray *records = [YZDownloadResumeStore pendingRecords];
        if ([records count] == 0) {
            return;
        }

        NSFileManager *manager = [NSFileManager defaultManager];
        for (NSDictionary *record in records) {
            YZApplication *application = [YZDownloadResumeStore applicationFromRecord:record];
            NSString *sourceURL = [record objectForKey:@"source_url"];
            NSString *targetPath = [record objectForKey:@"target_path"];
            BOOL installAfterDownload = [[record objectForKey:@"install_after_download"] boolValue];
            if (application == nil || [sourceURL length] == 0 || [targetPath length] == 0) {
                [YZDownloadResumeStore removeRecordForTargetPath:targetPath];
                continue;
            }

            NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
            NSError *error = nil;
            if (![manager createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:&error]) {
                debugLog(@"Failed to create restored download directory %@: %@", targetDir, [error localizedDescription]);
                continue;
            }

            BOOL alreadyQueued = NO;
            @synchronized ([YZQueueManager sharedInstance]->_repsLock) {
                for (YZQueueRep *existingRep in [YZQueueManager sharedInstance]->_reps) {
                    if ([existingRep.bundleID isEqualToString:application.bundleID] &&
                        [existingRep.version isEqualToString:application.version]) {
                        alreadyQueued = YES;
                        break;
                    }
                }
            }
            if (alreadyQueued) {
                continue;
            }

            debugLog(@"Restoring pending download %@ %@", application.bundleID, application.version);
            if (installAfterDownload) {
                [YZQueueRep detachPausedRepWithYZApp:application andURL:sourceURL targetPath:targetPath];
            } else {
                [YZQueueRep detachPausedDownloadOnlyRepWithYZApp:application andURL:sourceURL targetPath:targetPath];
            }
        }
    });
}

+ (NSArray *)pendingResumeTargetPaths {
    return [YZDownloadResumeStore pendingTargetPaths];
}

- (void)enqueueAppContainerForInstall:(YZQueueRep *)appRep {
    dispatch_async(_installQueue, ^{
        appRep.state = YZRepStateInstalling;
        [VAPISS clearMemoryCaches];
        bool ret = [YZQueueOps installIPA:appRep.path];
        if (!ret) {
            appRep.state = YZRepStateFailed;
            return;
        }
        appRep.state = YZRepStateInstalled;
    });
}

#pragma - mark Notification Handling

- (void)handleNotification:(NSNotification *)notification {
    YZQueueRep __block *rep = notification.object;
    if (rep == nil) {
        return; // no rep, no party
    }
    YZRepState repState;
    @synchronized (_repsLock) {
        if (rep.invalid) { // check in the lock because before then we could be waiting
            return;
        }
        [_reps addObject:rep];
        repState = rep.state;
    }
    switch (repState) {
        case YZRepStateDownloaded:
            if (rep.installAfterDownload) {
                [self enqueueAppContainerForInstall:rep];
            }
            break;
        case YZRepStateQueued:
            dispatch_async(_queue, ^{
                rep.downloadSelf();
            });
            break;
        default:
            break;
    }
}

#pragma - mark Misc Methods

+ (YZQueueRep *)actualRepForRep:(YZQueueRep *)rep {
    YZQueueRep *actualRep;
    @synchronized ([YZQueueManager sharedInstance]->_repsLock) {
        actualRep = [YZQM->_reps member:rep];
    }
    return actualRep;
}

+ (bool)markRepAsCancelled:(YZQueueRep *)rep {
    // no one has the live state of the rep, instead they should have a copy
    // we can match the rep by bundleId and version
    YZQueueRep *actualRep = [YZQueueManager actualRepForRep:rep];
    if (actualRep == nil) {
        return NO;
    }
    debugLog(@"Cancelling %@", actualRep.bundleID);
    BBHTTPRequest *request = actualRep.request;
    id downloadTask = actualRep.downloadTask;
    if (request == nil && [downloadTask isKindOfClass:[BBHTTPRequest class]]) {
        request = (BBHTTPRequest *)downloadTask;
    }
    if (request != nil) {
        [request cancel];
    }
    if ([downloadTask isKindOfClass:[YZArchiveTLSDownloader class]]) {
        [(YZArchiveTLSDownloader *)downloadTask cancel];
    }
    if (actualRep.installAfterDownload) {
        [YZDownloadResumeStore removeRecordForTargetPath:downloadPathFor(actualRep.bundleID)];
    } else {
        [YZDownloadResumeStore removeRecordForTargetPath:actualRep.path];
    }
    if (actualRep.state == YZRepStatePaused && [actualRep.path hasPrefix:[downloadPath() stringByAppendingString:@"/"]]) {
        [[NSFileManager defaultManager] removeItemAtPath:actualRep.path error:NULL];
        YZRemoveDownloadPartFiles(actualRep.path);
    }
    // destroy the fucker
    @synchronized ([YZQueueManager sharedInstance]->_repsLock) {
        [YZQM->_reps removeObject:actualRep];
        rep.invalid = YES; // the original rep should be marked, the actual rep is non-existent now
    }
    [YZQueueOps notifyAppState:nil];
    return YES;
}

+ (bool)pauseRep:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [YZQueueManager actualRepForRep:rep];
    if (actualRep == nil || actualRep.state != YZRepStateDownloading) {
        return NO;
    }
    debugLog(@"Pausing %@", actualRep.bundleID);
    actualRep.preservePartialOnCancel = YES;
    BBHTTPRequest *request = actualRep.request;
    id downloadTask = actualRep.downloadTask;
    if (request == nil && [downloadTask isKindOfClass:[BBHTTPRequest class]]) {
        request = (BBHTTPRequest *)downloadTask;
    }
    if (request != nil) {
        [request cancel];
    }
    if ([downloadTask isKindOfClass:[YZArchiveTLSDownloader class]]) {
        YZArchiveTLSDownloader *downloader = (YZArchiveTLSDownloader *)downloadTask;
        downloader.preservePartialOnCancel = YES;
        [downloader cancel];
    }
    actualRep.state = YZRepStatePaused;
    return YES;
}

+ (bool)retryRep:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [YZQueueManager actualRepForRep:rep];
    if (actualRep != nil) {
        actualRep.preservePartialOnCancel = NO;
        actualRep.state = YZRepStateQueued;
        return YES;
    }
    return NO;
}

+ (NSArray *)allReps {
    NSArray *reps;
    @synchronized ([YZQueueManager sharedInstance]->_repsLock) {
        reps = [YZQM->_reps allObjects];
    }
    return reps;
}

+ (NSUInteger)activeDownloadsCount {
    NSUInteger count = 0;
    @synchronized ([YZQueueManager sharedInstance]->_repsLock) {
        for (YZQueueRep *rep in YZQM->_reps) {
            if (!rep.invalid && rep.state == YZRepStateDownloading) {
                count++;
            }
        }
    }
    return count;
}

+ (void)attachProgressBlock:(void (^)(NSUInteger current, NSUInteger total))block toRep:(YZQueueRep *)rep {
    YZQueueRep *actualRep = [YZQueueManager actualRepForRep:rep];
    if (actualRep != nil) {
        [actualRep refreshStoredDownloadProgress];
        if (block != nil && actualRep.storedProgressCurrent > 0) {
            block(actualRep.storedProgressCurrent, actualRep.storedProgressTotal);
        }
        actualRep.downloadProgressBlock = block;
    }
}

- (void)dealloc {
    [_nc removeObserver:self];
}
@end
