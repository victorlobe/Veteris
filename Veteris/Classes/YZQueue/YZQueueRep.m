#import "YZQueueRep.h"
#import "YZQueueOps.h"
#import "YZDownloadResumeStore.h"
#import "../VAPIHelper/VAPIHelper.h"

@implementation YZQueueRep {
    YZApplication *_app;
    NSString *_resumeSourceURL;
    NSString *_resumeTargetPath;
}

+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url {
    [self detachRepWithYZApp:yzApp andURL:url trackDownloadStart:YES];
}

+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url trackDownloadStart:(BOOL)trackDownloadStart {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = YES;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [downloadPathFor(yzApp.bundleID) copy];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        if (trackDownloadStart) {
            [VAPIHelper trackDownloadStartForApplication:yzApp url:url downloadOnly:NO];
        }
        [YZQueueOps downloadFileToPath:url pathFromString:yzApp.bundleID parent:weakSelf];
    };
    if (url != nil) {
        rep->_app.path = url;
        [YZDownloadResumeStore upsertRecordForApplication:yzApp sourceURL:url targetPath:rep->_resumeTargetPath installAfterDownload:YES];
        [rep setState:YZRepStateQueued];
    } else {
        [rep setState:YZRepStateDownloaded];
    }
}

+ (void)detachPausedRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = YES;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        [YZQueueOps downloadFileToPath:url pathFromString:yzApp.bundleID parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [rep setState:YZRepStatePaused];
}

+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    [self detachDownloadOnlyRepWithYZApp:yzApp andURL:url targetPath:targetPath trackDownloadStart:YES];
}

+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath trackDownloadStart:(BOOL)trackDownloadStart {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = NO;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        if (trackDownloadStart) {
            [VAPIHelper trackDownloadStartForApplication:yzApp url:url downloadOnly:YES];
        }
        [YZQueueOps downloadFileToPath:url targetPath:targetPath parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [YZDownloadResumeStore upsertRecordForApplication:yzApp sourceURL:url targetPath:targetPath installAfterDownload:NO];
    [rep setState:YZRepStateQueued];
}

+ (void)detachPausedDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath {
    YZQueueRep *rep = [[YZQueueRep alloc] init];
    rep->_app = yzApp;
    rep->_invalid = NO;
    rep->_installAfterDownload = NO;
    rep->_resumeSourceURL = [url copy];
    rep->_resumeTargetPath = [targetPath copy];
    __typeof__(rep) weakSelf = rep;
    rep->_downloadSelf = ^{
        [weakSelf setState:YZRepStateDownloading];
        [YZQueueOps downloadFileToPath:url targetPath:targetPath parent:weakSelf];
    };
    rep->_app.path = targetPath;
    [rep setState:YZRepStatePaused];
}

- (void)setState:(YZRepState)state {
    _state = state;
    if (_resumeSourceURL != nil && _resumeTargetPath != nil) {
        BOOL keepResumeRecord = (state == YZRepStateQueued ||
                                 state == YZRepStateDownloading ||
                                 state == YZRepStatePaused ||
                                 (self.installAfterDownload && (state == YZRepStateDownloaded || state == YZRepStateInstalling)));
        if (keepResumeRecord) {
            [YZDownloadResumeStore upsertRecordForApplication:_app
                                                    sourceURL:_resumeSourceURL
                                                   targetPath:_resumeTargetPath
                                         installAfterDownload:self.installAfterDownload];
        } else {
            [YZDownloadResumeStore removeRecordForTargetPath:_resumeTargetPath];
        }
    }
    [YZQueueOps notifyAppState:self];
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return true;
    }
    if (![object isKindOfClass:[YZQueueRep class]]) {
        return false;
    }
    YZQueueRep *rep = (YZQueueRep *)object;
    return [rep.bundleID isEqualToString:self.bundleID] && [rep.version isEqualToString:self.version];
}

- (NSUInteger)hash {
    return [self.bundleID hash] ^ [self.version hash];
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
