#import "YZQueueRep.h"
#import "YZQueueOps.h"
#import "YZDownloadResumeStore.h"
#import "YZTransferSpeedMeter.h"
#import "../VAPIHelper/VAPIHelper.h"

static const NSTimeInterval kYZDownloadSpeedWindow = 5.0;
static const NSTimeInterval kYZDownloadProgressRefreshInterval = 1.0;

@implementation YZQueueRep {
    YZApplication *_app;
    YZTransferSpeedMeter *_speedMeter;
    unsigned long long _progressCurrent;
    unsigned long long _progressTotal;
    BOOL _progressRefreshScheduled;
}

static unsigned long long YZQueueFileSizeAtPath(NSString *path) {
    if ([path length] == 0) {
        return 0;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    return attrs != nil ? [attrs fileSize] : 0;
}

static NSString *YZQueueStateLogName(YZRepState state) {
    switch (state) {
        case YZRepStateInstalled: return @"installed";
        case YZRepStateInstalling: return @"installing";
        case YZRepStateDownloaded: return @"downloaded";
        case YZRepStateDownloading: return @"downloading";
        case YZRepStateQueued: return @"queued";
        case YZRepStateFailed: return @"failed";
        case YZRepStatePaused: return @"paused";
        case YZRepStateCancelled: return @"cancelled";
    }
    return @"unknown";
}

static void YZAppendQueueOperationLog(YZQueueRep *rep, YZRepState state) {
    NSString *directory = downloadPath();
    if ([directory length] == 0) {
        return;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        debugLog(@"Could not create download log directory %@: %@", directory, [error localizedDescription]);
        return;
    }

    NSString *logPath = [directory stringByAppendingPathComponent:@"VeterisDownload.log"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
    NSString *line = [NSString stringWithFormat:@"%@ event=%@ name=%@ bundle=%@ version=%@ mode=%@ path=%@\n",
                      [formatter stringFromDate:[NSDate date]],
                      YZQueueStateLogName(state),
                      rep.name ?: @"",
                      rep.bundleID ?: @"",
                      rep.version ?: @"",
                      rep.installAfterDownload ? @"install" : @"download-only",
                      rep.path ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized ([YZQueueRep class]) {
        if (![manager fileExistsAtPath:logPath]) {
            [manager createFileAtPath:logPath contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (handle == nil) {
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (NSException *exception) {
            debugLog(@"Could not append download log: %@", [exception reason]);
        } @finally {
            [handle closeFile];
        }
    }
}

- (instancetype)initWithApplication:(YZApplication *)application
                          sourceURL:(NSString *)sourceURL
                         targetPath:(NSString *)targetPath
               installAfterDownload:(BOOL)installAfterDownload
                 trackDownloadStart:(BOOL)trackDownloadStart {
    if ((self = [super init])) {
        _app = application;
        _sourceURL = [sourceURL copy];
        _targetPath = [targetPath copy];
        _invalid = NO;
        _installAfterDownload = installAfterDownload;
        _trackDownloadStart = trackDownloadStart;
        _state = YZRepStateQueued;
        _previousState = YZRepStateQueued;
        if ([targetPath length] > 0 && [sourceURL length] > 0) {
            _app.path = targetPath;
        }
        [self refreshStoredDownloadProgress];
    }
    return self;
}

- (BOOL)ownsDownloadFiles {
    return [_sourceURL length] > 0 && [_targetPath hasPrefix:[downloadPath() stringByAppendingString:@"/"]];
}

- (void)setState:(YZRepState)state {
    _previousState = _state;
    _state = state;
    _downloadFinishing = NO;
    [_speedMeter reset];
    YZAppendQueueOperationLog(self, state);
    if ([self ownsDownloadFiles]) {
        BOOL keepResumeRecord = (state == YZRepStateQueued ||
                                 state == YZRepStateDownloading ||
                                 state == YZRepStatePaused ||
                                 (self.installAfterDownload && (state == YZRepStateDownloaded || state == YZRepStateInstalling)));
        if (keepResumeRecord && !self.invalid) {
            [YZDownloadResumeStore upsertRecordForApplication:_app
                                                    sourceURL:_sourceURL
                                                   targetPath:_targetPath
                                         installAfterDownload:self.installAfterDownload
                                                   userPaused:(state == YZRepStatePaused && self.userPaused)];
        } else if (!keepResumeRecord) {
            [YZDownloadResumeStore removeRecordForTargetPath:_targetPath];
        }
    }
    [YZQueueOps notifyAppState:self];
}

- (void)refreshStoredDownloadProgress {
    NSString *targetPath = [_targetPath length] > 0 ? _targetPath : _app.path;
    unsigned long long current = YZQueueFileSizeAtPath(targetPath);
    unsigned long long total = _app.sizeBytes;
    if ([self ownsDownloadFiles]) {
        for (NSString *partPath in [YZDownloadResumeStore existingPartPathsForTargetPath:targetPath]) {
            current += YZQueueFileSizeAtPath(partPath);
        }
        unsigned long long knownTotal = [[[YZDownloadResumeStore resumeInfoForTargetPath:targetPath] objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue];
        if (knownTotal > 0) {
            total = knownTotal;
        }
    }
    if (total > 0 && current > total) {
        current = total;
    }
    self.storedProgressCurrent = (NSUInteger)MIN(current, (unsigned long long)NSUIntegerMax);
    self.storedProgressTotal = (NSUInteger)MIN(total, (unsigned long long)NSUIntegerMax);
}

- (void)reportDownloadProgress:(unsigned long long)current total:(unsigned long long)total {
    if (_speedMeter == nil) {
        _speedMeter = [[YZTransferSpeedMeter alloc] initWithWindow:kYZDownloadSpeedWindow];
    }
    [_speedMeter recordTotal:current at:[NSDate timeIntervalSinceReferenceDate]];
    _progressCurrent = current;
    _progressTotal = total;
    [self forwardDownloadProgress];
    [self scheduleProgressRefresh];
}

- (double)downloadBytesPerSecond {
    if (self.state != YZRepStateDownloading || self.downloadFinishing || _speedMeter == nil) {
        return -1.0;
    }
    return [_speedMeter bytesPerSecondAt:[NSDate timeIntervalSinceReferenceDate]];
}

- (void)forwardDownloadProgress {
    if (self.downloadProgressBlock != nil) {
        self.downloadProgressBlock((NSUInteger)MIN(_progressCurrent, (unsigned long long)NSUIntegerMax),
                                   (NSUInteger)MIN(_progressTotal, (unsigned long long)NSUIntegerMax));
    }
}

- (void)scheduleProgressRefresh {
    if (_progressRefreshScheduled) {
        return;
    }
    _progressRefreshScheduled = YES;
    __weak YZQueueRep *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYZDownloadProgressRefreshInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        YZQueueRep *rep = weakSelf;
        if (rep == nil) {
            return;
        }
        rep->_progressRefreshScheduled = NO;
        if (rep.invalid || rep.state != YZRepStateDownloading || rep.downloadFinishing) {
            return;
        }
        [rep forwardDownloadProgress];
        [rep scheduleProgressRefresh];
    });
}

- (YZApplication *)application {
    return _app;
}

- (UIImage *)icon {
    return _app.icon;
}

- (NSString *)iconurl {
    return _app.iconurl;
}

- (NSString *)fallbackIconurl {
    return _app.fallback_iconurl;
}

- (NSString *)name {
    return _app.name;
}

- (NSString *)description {
    return _app.description;
}

- (NSString *)version {
    return _app.version;
}

- (NSString *)bundleID {
    return _app.bundleID;
}

- (NSString *)developer {
    return _app.developer;
}

- (NSString *)minimumOS {
    return _app.minimumOS;
}

- (NSString *)url {
    return _app.url;
}

- (NSString *)path {
    return _app.path;
}

- (void)setPath:(NSString *)path {
    _app.path = path;
}

@end
