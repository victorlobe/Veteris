#import "YZQueueOps.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../Clutch/MobileInstallation.h"
#import "../../BBHTTP/BBHTTP.h"
#import "../../BBHTTP/BBHTTPRequest+Convenience.h"
#import "../../BBHTTP/Handlers/BBHTTPFileWriter.h"
#import "../../AppDelegate.h"
#import "LSApplicationWorkspace.h"
#import "YZArchiveTLSDownloader.h"
#import "YZDownloadResumeStore.h"
#import <errno.h>
#import <string.h>

static const NSUInteger kMaxDownloadAttempts = 6;
static const unsigned long long kMinimumResumeBytes = 4096;
static const NSTimeInterval kDownloadTelemetrySampleInterval = 10.0;
static const NSUInteger kZipEndOfCentralDirectorySize = 22;
static const NSUInteger kZipMaxCommentSize = 0xFFFF;


#ifdef VETERIS_DOWNLOAD_DEBUG
#define YZDownloadLog(...) NSLog(@"[VeterisDownload] %@", [NSString stringWithFormat:__VA_ARGS__])
#else
#define YZDownloadLog(...) do {} while (0)
#endif

static NSDictionary *YZInstallOptions(void) {
    return [NSDictionary dictionaryWithObject:@"User" forKey:@"ApplicationType"];
}

static BOOL YZIsNonEmptyString(id value) {
    return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

// Ignore callbacks from earlier download attempts
static BOOL YZDownloadIsCurrent(YZQueueRep *parent, NSUInteger generation) {
    return parent != nil && !parent.invalid && parent.downloadGeneration == generation && parent.state == YZRepStateDownloading;
}

static void YZFailDownload(YZQueueRep *parent, NSUInteger generation, NSString *reason) {
    YZDownloadLog(@"failed: %@", reason);
    debugLog(@"Download failed: %@", reason);
    if (!YZDownloadIsCurrent(parent, generation)) {
        return;
    }
    parent.errorDetails = reason;
    parent.downloadTask = nil;
    parent.request = nil;
    parent.state = YZRepStateFailed;
}

static void YZClearLowMemoryCachesAfterDownload(void) {
    if ([VeterisMemoryProfile activeValues].clearsCachesAfterDownload) {
        [VAPISS clearMemoryCaches];
    }
}

static NSString *YZSanitizedURLString(NSString *urlString) {
    if (!YZIsNonEmptyString(urlString)) {
        return nil;
    }
    if ([NSURL URLWithString:urlString] != nil) {
        return urlString;
    }
    return [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *YZInstallErrorDetails(NSError *error, BOOL legacyInstaller, int result, int savedErrno) {
    NSMutableArray *lines = [NSMutableArray array];
    NSString *description = [error localizedDescription];
    if ([description length] > 0) {
        [lines addObject:description];
    } else {
        [lines addObject:NSLocalizedString(@"InstallFailureGeneric", nil)];
    }

    if (legacyInstaller) {
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureSystemResult", nil), result, (unsigned int)result]];
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureErrno", nil), savedErrno, strerror(savedErrno)]];
    } else if (error != nil) {
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureDomain", nil), error.domain ?: @""]];
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureCode", nil), (long)error.code]];

        NSString *failureReason = [error.localizedFailureReason description];
        if ([failureReason length] > 0) {
            [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureReason", nil), failureReason]];
        }
        NSString *recoverySuggestion = [error.localizedRecoverySuggestion description];
        if ([recoverySuggestion length] > 0) {
            [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureRecovery", nil), recoverySuggestion]];
        }

        NSError *underlyingError = [error.userInfo objectForKey:NSUnderlyingErrorKey];
        if ([underlyingError isKindOfClass:[NSError class]] && [[underlyingError localizedDescription] length] > 0) {
            [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"InstallFailureUnderlying", nil), [underlyingError localizedDescription]]];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *YZArchiveEscapedDownloadPath(NSString *path) {
    if (!YZIsNonEmptyString(path)) {
        return path;
    }
    return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                     (CFStringRef)path,
                                                                     CFSTR("/"),
                                                                     CFSTR(" %?#[]@!$&'()*+,;="),
                                                                     kCFStringEncodingUTF8));
}

static NSString *YZArchiveFrontURL(NSString *urlString) {
    NSString *clean = YZSanitizedURLString(urlString);
    if (!YZIsNonEmptyString(clean)) {
        return nil;
    }
    NSURL *url = [NSURL URLWithString:clean];
    NSString *host = [[url host] lowercaseString];
    if (host == nil) {
        return clean;
    }

    NSString *urlPath = [[url path] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (urlPath == nil) {
        urlPath = [url path];
    }

    if ([host isEqualToString:@"archive.org"] && [urlPath hasPrefix:@"/download/"]) {
        if ([[url scheme] isEqualToString:@"https"]) {
            return [@"http://" stringByAppendingString:[clean substringFromIndex:8]];
        }
        return clean;
    }

    if (![host hasSuffix:@".archive.org"]) {
        return clean;
    }

    NSRange schemeEnd = [clean rangeOfString:@"://"];
    if (schemeEnd.location == NSNotFound) {
        return clean;
    }
    NSString *afterScheme = [clean substringFromIndex:NSMaxRange(schemeEnd)];
    NSRange slash = [afterScheme rangeOfString:@"/"];
    if (slash.location == NSNotFound) {
        return clean;
    }
    NSString *rawPath = [afterScheme substringFromIndex:slash.location];
    NSString *decodedPath = [rawPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (decodedPath == nil) {
        decodedPath = rawPath;
    }
    NSRange items = [decodedPath rangeOfString:@"/items/"];
    if (items.location == NSNotFound) {
        return clean;
    }
    NSString *afterItems = [decodedPath substringFromIndex:NSMaxRange(items)];
    NSRange nextSlash = [afterItems rangeOfString:@"/"];
    if (nextSlash.location == NSNotFound) {
        return clean;
    }
    NSString *identifier = [afterItems substringToIndex:nextSlash.location];
    NSString *inItemPath = [afterItems substringFromIndex:NSMaxRange(nextSlash)];
    if ([identifier length] == 0 || [inItemPath length] == 0) {
        return clean;
    }
    NSString *archivePath = [NSString stringWithFormat:@"%@/%@", identifier, inItemPath];
    return [NSString stringWithFormat:@"http://archive.org/download/%@", YZArchiveEscapedDownloadPath(archivePath)];
}

static NSArray *YZDownloadCandidates(NSString *urlString) {
    NSString *clean = YZSanitizedURLString(urlString);
    if (!YZIsNonEmptyString(clean)) {
        return [NSArray array];
    }
    NSString *front = YZArchiveFrontURL(clean);
    if (front != nil && ![front isEqualToString:clean]) {
        return [NSArray arrayWithObjects:front, clean, nil];
    }
    return [NSArray arrayWithObject:clean];
}

static NSString *YZDownloadCandidateForAttempt(NSArray *candidates, NSUInteger attempt) {
    if ([candidates count] == 0) {
        return nil;
    }
    if ([candidates count] == 1) {
        return [candidates objectAtIndex:0];
    }
    if (attempt + 1 >= kMaxDownloadAttempts) {
        return [candidates lastObject];
    }
    return [candidates objectAtIndex:0];
}

static BOOL YZCanUseArchiveTLSDownloader(NSArray *candidates) {
    for (NSString *candidate in candidates) {
        if (!YZIsNonEmptyString(candidate)) {
            continue;
        }
        NSURL *url = [NSURL URLWithString:YZSanitizedURLString(candidate)];
        NSString *host = [[url host] lowercaseString];
        if ([host isEqualToString:@"archive.org"] || [host hasSuffix:@".archive.org"]) {
            return YES;
        }
    }
    return NO;
}

static NSString *YZHeaderValue(NSDictionary *headers, NSString *name) {
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:name] == NSOrderedSame) {
            return [headers objectForKey:key];
        }
    }
    return nil;
}

static unsigned long long YZTotalBytesFromHeaders(NSDictionary *headers, NSUInteger statusCode, unsigned long long resumeOffset) {
    NSString *range = YZHeaderValue(headers, @"Content-Range");
    if ([range length] > 0) {
        NSRange slash = [range rangeOfString:@"/"];
        if (slash.location != NSNotFound && slash.location + 1 < [range length]) {
            NSString *totalString = [range substringFromIndex:slash.location + 1];
            unsigned long long parsed = strtoull([totalString UTF8String], NULL, 10);
            if (parsed > 0) {
                return parsed;
            }
        }
    }

    NSString *length = YZHeaderValue(headers, @"Content-Length");
    unsigned long long contentLength = ([length length] > 0) ? strtoull([length UTF8String], NULL, 10) : 0;
    if (statusCode == 206 && contentLength > 0) {
        return resumeOffset + contentLength;
    }
    return contentLength;
}

static unsigned long long YZFileSizeAtPath(NSString *path) {
    if ([path length] == 0) {
        return 0;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    return attrs != nil ? [attrs fileSize] : 0;
}

static BOOL YZDownloadedFileMatchesExpectedTotal(NSString *path, unsigned long long expectedTotal) {
    return expectedTotal == 0 || YZFileSizeAtPath(path) == expectedTotal;
}

static BOOL YZHasZipLocalHeader(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return NO;
    }
    NSData *magic = nil;
    @try {
        magic = [handle readDataOfLength:4];
    } @catch (NSException *exception) {
        magic = nil;
    }
    [handle closeFile];
    if ([magic length] < 4) {
        return NO;
    }
    const unsigned char *b = [magic bytes];
    return (b[0] == 'P' && b[1] == 'K' && b[2] == 0x03 && b[3] == 0x04);
}

static BOOL YZShouldPreservePartialAtPath(NSString *path) {
    return YZFileSizeAtPath(path) >= kMinimumResumeBytes && YZHasZipLocalHeader(path);
}

static unsigned long long YZUnsatisfiedRangeTotal(NSDictionary *headers);
static unsigned long long YZContentRangeStart(NSDictionary *headers);

static unsigned long long YZKnownTotalForTargetPath(NSString *path) {
    return [[[YZDownloadResumeStore resumeInfoForTargetPath:path] objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue];
}

static NSString *YZResumeSourceIdentity(NSString *sourceURL) {
    return YZArchiveFrontURL(sourceURL) ?: sourceURL;
}

static void YZPrepareResumeInfo(NSString *targetPath, NSString *sourceURL) {
    NSString *identity = YZResumeSourceIdentity(sourceURL);
    if ([identity length] == 0) {
        return;
    }
    NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:targetPath];
    NSString *storedSource = [info objectForKey:YZResumeInfoSourceURLKey];
    if ([storedSource isKindOfClass:[NSString class]] && [storedSource length] > 0 && ![storedSource isEqualToString:identity]) {
        YZDownloadLog(@"partial for %@ belongs to %@, not %@; discarding", targetPath, storedSource, identity);
        [YZDownloadResumeStore removeArtifactsForTargetPath:targetPath includingTarget:YES];
    }
    [YZDownloadResumeStore updateResumeInfoForTargetPath:targetPath
                                                 setting:[NSDictionary dictionaryWithObject:identity forKey:YZResumeInfoSourceURLKey]
                                            removingKeys:nil];
}

static void YZCollapseParallelStateToPrefix(NSString *targetPath) {
    NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:targetPath];
    NSArray *segments = [info objectForKey:YZResumeInfoSegmentsKey];
    if ([segments isKindOfClass:[NSArray class]] && [segments count] > 0 && [[segments objectAtIndex:0] isKindOfClass:[NSDictionary class]]) {
        unsigned long long firstEnd = [[[segments objectAtIndex:0] objectForKey:YZResumeInfoSegmentEndKey] unsignedLongLongValue];
        if (YZFileSizeAtPath(targetPath) > firstEnd + 1) {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:targetPath];
            @try {
                [handle truncateFileAtOffset:firstEnd + 1];
                [handle synchronizeFile];
            } @catch (NSException *exception) {
                [[NSFileManager defaultManager] removeItemAtPath:targetPath error:NULL];
            }
            [handle closeFile];
        }
    }
    [YZDownloadResumeStore removePartsForTargetPath:targetPath];
    [YZDownloadResumeStore updateResumeInfoForTargetPath:targetPath
                                                 setting:[NSDictionary dictionary]
                                            removingKeys:[NSArray arrayWithObjects:YZResumeInfoSegmentsKey, YZResumeInfoMergingKey, nil]];
}

static BOOL YZStoredFileIsComplete(NSString *path, NSDictionary *headers) {
    unsigned long long total = YZUnsatisfiedRangeTotal(headers);
    if (total == 0) {
        total = YZKnownTotalForTargetPath(path);
    }
    return YZDownloadedFileMatchesExpectedTotal(path, total) && [YZQueueOps isValidIPAAtPath:path];
}

static unsigned long long YZUnsatisfiedRangeTotal(NSDictionary *headers) {
    NSString *range = YZHeaderValue(headers, @"Content-Range");
    NSRange slash = [range rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location + 1 >= [range length]) {
        return 0;
    }
    return strtoull([[range substringFromIndex:slash.location + 1] UTF8String], NULL, 10);
}

static unsigned long long YZContentRangeStart(NSDictionary *headers) {
    NSString *range = YZHeaderValue(headers, @"Content-Range");
    NSRange bytes = [range rangeOfString:@"bytes" options:NSCaseInsensitiveSearch];
    if (bytes.location == NSNotFound) {
        return ULLONG_MAX;
    }
    NSString *spec = [[range substringFromIndex:NSMaxRange(bytes)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([spec length] == 0 || ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[spec characterAtIndex:0]]) {
        return ULLONG_MAX;
    }
    return strtoull([spec UTF8String], NULL, 10);
}

static void YZFinishSuccessfulDownload(YZQueueRep *parent, NSString *filePath) {
    [YZDownloadResumeStore removeArtifactsForTargetPath:filePath includingTarget:NO];
    parent.path = filePath;
    parent.errorDetails = nil;
    parent.downloadTask = nil;
    parent.request = nil;
    parent.state = YZRepStateDownloaded;
    YZClearLowMemoryCachesAfterDownload();
}

static NSTimeInterval YZRetryDelay(NSUInteger nextAttempt, NSUInteger httpStatus) {
    if (httpStatus >= 300 && httpStatus < 400) {
        return 0.0;
    }
    return MIN(8.0, 1.0 * (1 << MIN(nextAttempt, (NSUInteger)3)));
}

#pragma mark - Target path ownership



static NSMutableSet *YZBusyTargetPaths(void) {
    static NSMutableSet *paths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        paths = [NSMutableSet set];
    });
    return paths;
}

static NSMutableDictionary *YZTargetPathWaiters(void) {
    static NSMutableDictionary *waiters = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        waiters = [NSMutableDictionary dictionary];
    });
    return waiters;
}

static void YZClaimTargetPath(NSString *path) {
    [YZBusyTargetPaths() addObject:path];
}

static void YZReleaseTargetPath(NSString *path) {
    [YZBusyTargetPaths() removeObject:path];
    NSMutableArray *waiters = [YZTargetPathWaiters() objectForKey:path];
    while ([waiters count] > 0 && ![YZBusyTargetPaths() containsObject:path]) {
        dispatch_block_t block = [waiters objectAtIndex:0];
        [waiters removeObjectAtIndex:0];
        block();
    }
    if ([waiters count] == 0) {
        [YZTargetPathWaiters() removeObjectForKey:path];
    }
}

#pragma mark - BBHTTP writer tracking


@interface YZTrackedFileWriter : BBHTTPFileWriter
- (void)runWhenIdle:(dispatch_block_t)block;
@end

@implementation YZTrackedFileWriter {
    BOOL _opened;
    BOOL _finished;
    BOOL _abandoned;
    NSMutableArray *_idleBlocks;
}

- (BOOL)prepareForResponse:(NSUInteger)statusCode message:(NSString *)message headers:(NSDictionary *)headers error:(NSError **)error {
    @synchronized (self) {
        if (_abandoned) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:@"YZQueueOps" code:-1 userInfo:[NSDictionary dictionaryWithObject:@"Download was stopped" forKey:NSLocalizedDescriptionKey]];
            }
            return NO;
        }
        _opened = YES;
    }
    return [super prepareForResponse:statusCode message:message headers:headers error:error];
}

- (id)parseContent:(NSError **)error {
    id content = [super parseContent:error];
    [self markFinished];
    return content;
}

- (void)cleanup {
    [super cleanup];
    [self markFinished];
}

- (void)markFinished {
    NSArray *blocks = nil;
    @synchronized (self) {
        if (_finished) {
            return;
        }
        _finished = YES;
        blocks = [_idleBlocks copy];
        _idleBlocks = nil;
    }
    for (dispatch_block_t block in blocks) {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

- (void)runWhenIdle:(dispatch_block_t)block {
    BOOL runNow = NO;
    @synchronized (self) {
        if (!_opened) {
            _abandoned = YES;
            runNow = YES;
        } else if (_finished) {
            runNow = YES;
        } else {
            if (_idleBlocks == nil) {
                _idleBlocks = [NSMutableArray array];
            }
            [_idleBlocks addObject:[block copy]];
        }
    }
    if (runNow) {
        block();
    }
}

- (void)dealloc {
    [self markFinished];
}

@end

static NSString *YZStringFromUnsignedLongLong(unsigned long long value) {
    return [NSString stringWithFormat:@"%llu", value];
}

static NSString *YZStringFromDouble(double value) {
    return [NSString stringWithFormat:@"%.2f", value];
}

static void YZSetTelemetryField(NSMutableDictionary *fields, NSString *key, id value) {
    if ([key length] == 0 || value == nil) {
        return;
    }
    NSString *stringValue = [value description];
    if ([stringValue length] > 0) {
        [fields setObject:stringValue forKey:key];
    }
}

static void YZTrackDownloadTelemetry(YZQueueRep *parent,
                                     NSString *event,
                                     NSString *originalURL,
                                     NSString *candidateURL,
                                     NSString *finalURL,
                                     NSString *downloader,
                                     NSUInteger attempt,
                                     NSUInteger httpStatus,
                                     unsigned long long currentBytes,
                                     unsigned long long totalBytes,
                                     NSTimeInterval elapsed,
                                     unsigned long long intervalBytesPerSecond,
                                     unsigned long long averageBytesPerSecond,
                                     NSDictionary *headers,
                                     NSError *error) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    YZSetTelemetryField(fields, @"candidate_url", candidateURL);
    YZSetTelemetryField(fields, @"final_url", finalURL);
    YZSetTelemetryField(fields, @"downloader", downloader);
    YZSetTelemetryField(fields, @"attempt", [NSString stringWithFormat:@"%lu", (unsigned long)(attempt + 1)]);
    YZSetTelemetryField(fields, @"attempts", [NSString stringWithFormat:@"%lu", (unsigned long)kMaxDownloadAttempts]);
    YZSetTelemetryField(fields, @"http_status", [NSString stringWithFormat:@"%lu", (unsigned long)httpStatus]);
    YZSetTelemetryField(fields, @"current_bytes", YZStringFromUnsignedLongLong(currentBytes));
    YZSetTelemetryField(fields, @"total_bytes", YZStringFromUnsignedLongLong(totalBytes));
    YZSetTelemetryField(fields, @"elapsed_seconds", YZStringFromDouble(elapsed));
    YZSetTelemetryField(fields, @"interval_bps", YZStringFromUnsignedLongLong(intervalBytesPerSecond));
    YZSetTelemetryField(fields, @"average_bps", YZStringFromUnsignedLongLong(averageBytesPerSecond));
    YZSetTelemetryField(fields, @"content_length", YZHeaderValue(headers, @"Content-Length"));
    YZSetTelemetryField(fields, @"content_range", YZHeaderValue(headers, @"Content-Range"));
    YZSetTelemetryField(fields, @"location", YZHeaderValue(headers, @"Location"));
    YZSetTelemetryField(fields, @"error", [error localizedDescription]);
    [VAPIHelper trackDownloadEvent:event
                          bundleID:parent.bundleID
                           appName:parent.name
                         developer:parent.developer
                           version:parent.version
                            minIOS:parent.minimumOS
                               url:originalURL
                         sizeBytes:totalBytes
                      downloadOnly:!parent.installAfterDownload
                       extraFields:fields];
    YZDownloadLog(@"telemetry event=%@ downloader=%@ bundle=%@ version=%@ attempt=%lu/%lu status=%lu current=%llu total=%llu elapsed=%.2fs intervalBps=%llu avgBps=%llu original=%@ candidate=%@ final=%@ contentLength=%@ contentRange=%@ location=%@ error=%@",
                  event,
                  downloader,
                  parent.bundleID,
                  parent.version,
                  (unsigned long)(attempt + 1),
                  (unsigned long)kMaxDownloadAttempts,
                  (unsigned long)httpStatus,
                  currentBytes,
                  totalBytes,
                  elapsed,
                  intervalBytesPerSecond,
                  averageBytesPerSecond,
                  originalURL,
                  candidateURL,
                  finalURL,
                  YZHeaderValue(headers, @"Content-Length"),
                  YZHeaderValue(headers, @"Content-Range"),
                  YZHeaderValue(headers, @"Location"),
                  [error localizedDescription]);
}




@implementation YZQueueOps
#pragma mark - Main Methods
+ (BOOL)installIPA:(NSString *)filePath errorDetails:(NSString **)errorDetails {
    if (errorDetails != NULL) {
        *errorDetails = nil;
    }
    if (![YZQueueOps doesPathExist:filePath]) {
        debugLog(@"File does not exist at path but skipping: %@", filePath);
        if (errorDetails != NULL) {
            *errorDetails = NSLocalizedString(@"InstallFailureMissingIPA", nil);
        }
        return false;
    }
    NSDictionary *options = YZInstallOptions();
    int ret = -1;
    int savedErrno = 0;
    BOOL legacyInstaller = SYSTEM_VERSION_LESS_THAN(@"8.0");
    NSError *installError = nil;
    if (legacyInstaller) {
        errno = 0;
        ret = MobileInstallationInstall((__bridge CFStringRef)filePath, (__bridge CFDictionaryRef)options, NULL, NULL);
        savedErrno = errno;
        YZDownloadLog(@"mobile installation finished path=%@ ret=%d", filePath, ret);
        if (ret != 0) {
            installError = [NSError errorWithDomain:@"MobileInstallation" code:ret userInfo:nil];
        }
    } else {
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        BOOL installed = [workspace installApplication:[NSURL fileURLWithPath:filePath] withOptions:options error:&installError];
        if (installError != nil) {
            debugLog(@"Install error: %@", [installError localizedDescription]);
            YZDownloadLog(@"workspace install failed path=%@ error=%@ userInfo=%@", filePath, installError, [installError userInfo]);
        } else if (!installed) {
            YZDownloadLog(@"workspace install returned NO path=%@", filePath);
        } else {
            ret = 0;
        }
    }
    BOOL success = (ret == 0);
    if (success) {
        [self removeFileAt:filePath];
    } else if (errorDetails != NULL) {
        *errorDetails = YZInstallErrorDetails(installError, legacyInstaller, ret, savedErrno);
    }
    return success;
}

+ (void)startDownloadForRep:(YZQueueRep *)parent {
    NSUInteger generation = parent.downloadGeneration;
    NSString *urlString = parent.sourceURL;
    NSString *targetPath = parent.targetPath;
    if (!YZIsNonEmptyString(urlString)) {
        YZFailDownload(parent, generation, @"missing download URL");
        return;
    }
    if (!YZIsNonEmptyString(targetPath)) {
        YZFailDownload(parent, generation, @"missing target path");
        return;
    }
    NSArray *candidates = YZDownloadCandidates(urlString);
    if ([candidates count] == 0) {
        YZFailDownload(parent, generation, @"invalid download URL");
        return;
    }
    NSError *error = nil;
    NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        YZFailDownload(parent, generation, [NSString stringWithFormat:@"Could not create download folder: %@", [error localizedDescription]]);
        return;
    }
    parent.path = targetPath;
    YZDownloadLog(@"candidates for %@: %@", targetPath, candidates);
    BOOL useArchiveTLS = YZCanUseArchiveTLSDownloader(candidates);
    [self performWhenTargetPathIdle:targetPath block:^{
        if (!YZDownloadIsCurrent(parent, generation)) {
            return;
        }
        if (useArchiveTLS) {
            [self downloadFileWithArchiveTLS:urlString candidates:candidates targetPath:targetPath parent:parent generation:generation attempt:0];
        } else {
            [self downloadFileViaBBHTTP:urlString candidates:candidates targetPath:targetPath parent:parent generation:generation attempt:0];
        }
    }];
}

+ (void)stopTransferForRep:(YZQueueRep *)rep {
    id downloadTask = rep.downloadTask;
    BBHTTPRequest *request = rep.request;
    if (request == nil && [downloadTask isKindOfClass:[BBHTTPRequest class]]) {
        request = (BBHTTPRequest *)downloadTask;
    }
    if (request != nil) {
        [request cancel];
    }
    if ([downloadTask isKindOfClass:[YZArchiveTLSDownloader class]]) {
        [(YZArchiveTLSDownloader *)downloadTask cancel];
    }
    rep.downloadTask = nil;
    rep.request = nil;
}

+ (void)performWhenTargetPathIdle:(NSString *)path block:(dispatch_block_t)block {
    if (block == nil) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performWhenTargetPathIdle:path block:block];
        });
        return;
    }
    if ([path length] == 0 || ![YZBusyTargetPaths() containsObject:path]) {
        block();
        return;
    }
    NSMutableArray *waiters = [YZTargetPathWaiters() objectForKey:path];
    if (waiters == nil) {
        waiters = [NSMutableArray array];
        [YZTargetPathWaiters() setObject:waiters forKey:path];
    }
    [waiters addObject:[block copy]];
}

+ (void)scheduleAttemptForParent:(YZQueueRep *)parent generation:(NSUInteger)generation targetPath:(NSString *)filePath delay:(NSTimeInterval)delay attempt:(dispatch_block_t)attempt {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performWhenTargetPathIdle:filePath block:^{
            if (YZDownloadIsCurrent(parent, generation)) {
                attempt();
            }
        }];
    });
}

+ (void)downloadFileWithArchiveTLS:(NSString *)originalURL candidates:(NSArray *)candidates targetPath:(NSString *)filePath parent:(YZQueueRep *)parent generation:(NSUInteger)generation attempt:(NSUInteger)attempt {
    if (!YZDownloadIsCurrent(parent, generation)) {
        return;
    }
    NSString *urlString = YZDownloadCandidateForAttempt(candidates, attempt);
    YZDownloadLog(@"tls start %@ attempt %lu/%lu url=%@", filePath, (unsigned long)(attempt + 1), (unsigned long)kMaxDownloadAttempts, urlString);
    parent.downloadFinishing = NO;
    YZPrepareResumeInfo(filePath, originalURL);
    if (!YZShouldPreservePartialAtPath(filePath)) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
    }
    unsigned long long resumeOffset = YZFileSizeAtPath(filePath);
    YZDownloadLog(@"tls file=%@ resumeOffset=%llu", filePath, resumeOffset);
    __block NSTimeInterval telemetryStartedAt = [NSDate timeIntervalSinceReferenceDate];
    __block NSTimeInterval telemetryLastSampleAt = telemetryStartedAt;
    __block unsigned long long telemetryLastBytes = resumeOffset;
    __block __weak YZArchiveTLSDownloader *weakDownloader = nil;

    NSMutableDictionary *reqHeaders = [[VAPIHelper getHeaders] mutableCopy];
    YZArchiveTLSDownloader *downloader = [[YZArchiveTLSDownloader alloc] initWithURL:urlString
                                                                          targetPath:filePath
                                                                        resumeOffset:resumeOffset
                                                                             headers:reqHeaders
                                                                            progress:^(unsigned long long current, unsigned long long total) {
        if (!YZDownloadIsCurrent(parent, generation)) {
            return;
        }
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - telemetryLastSampleAt >= kDownloadTelemetrySampleInterval) {
            NSTimeInterval interval = MAX(0.001, now - telemetryLastSampleAt);
            NSTimeInterval elapsed = MAX(0.001, now - telemetryStartedAt);
            unsigned long long intervalBytes = current >= telemetryLastBytes ? current - telemetryLastBytes : 0;
            unsigned long long downloadedBytes = current >= resumeOffset ? current - resumeOffset : 0;
            YZTrackDownloadTelemetry(parent,
                                     @"download_progress_sample",
                                     originalURL,
                                     urlString,
                                     nil,
                                     @"archive_tls",
                                     attempt,
                                     0,
                                     current,
                                     total,
                                     elapsed,
                                     (unsigned long long)((double)intervalBytes / interval),
                                     (unsigned long long)((double)downloadedBytes / elapsed),
                                     nil,
                                     nil);
            telemetryLastSampleAt = now;
            telemetryLastBytes = current;
        }
        [parent reportDownloadProgress:current total:total];
    } completion:^(YZArchiveTLSResult *result) {
        if (weakDownloader != nil && parent.downloadTask == weakDownloader) {
            parent.downloadTask = nil;
        }
        if (!YZDownloadIsCurrent(parent, generation)) {
            YZDownloadLog(@"tls stale completion %@ cancelled=%d", filePath, result.cancelled);
            YZReleaseTargetPath(filePath);
            return;
        }
        NSUInteger httpStatus = result.statusCode;
        BOOL httpOK = httpStatus >= 200 && httpStatus < 300;
        unsigned long long expectedTotal = YZTotalBytesFromHeaders(result.headers, httpStatus, (httpStatus == 206 ? resumeOffset : 0));
        if (expectedTotal == 0) {
            expectedTotal = YZKnownTotalForTargetPath(filePath);
        }
        BOOL complete = YZDownloadedFileMatchesExpectedTotal(filePath, expectedTotal);
        BOOL validIPA = httpOK && result.error == nil && complete && [YZQueueOps isValidIPAAtPath:filePath];
        NSTimeInterval finishedAt = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval elapsed = MAX(0.001, finishedAt - telemetryStartedAt);
        unsigned long long currentSize = YZFileSizeAtPath(filePath);
        unsigned long long downloadedBytes = currentSize >= resumeOffset ? currentSize - resumeOffset : 0;

        YZTrackDownloadTelemetry(parent,
                                 @"download_response",
                                 originalURL,
                                 urlString,
                                 result.finalURL,
                                 @"archive_tls",
                                 attempt,
                                 httpStatus,
                                 currentSize,
                                 expectedTotal,
                                 elapsed,
                                 0,
                                 (unsigned long long)((double)downloadedBytes / elapsed),
                                 result.headers,
                                 result.error);

        if (httpStatus == 416 && result.error == nil && YZStoredFileIsComplete(filePath, result.headers)) {
            YZDownloadLog(@"tls success %@ existing file complete status=416", filePath);
            YZFinishSuccessfulDownload(parent, filePath);
        } else if (validIPA) {
            YZTrackDownloadTelemetry(parent,
                                     @"download_complete",
                                     originalURL,
                                     urlString,
                                     result.finalURL,
                                     @"archive_tls",
                                     attempt,
                                     httpStatus,
                                     currentSize,
                                     expectedTotal,
                                     elapsed,
                                     0,
                                     (unsigned long long)((double)downloadedBytes / elapsed),
                                     result.headers,
                                     result.error);
            YZDownloadLog(@"tls success %@ status=%lu size=%llu expected=%llu finalURL=%@",
                          filePath,
                          (unsigned long)httpStatus,
                          YZFileSizeAtPath(filePath),
                          expectedTotal,
                          result.finalURL);
            YZFinishSuccessfulDownload(parent, filePath);
        } else {
            NSString *location = YZHeaderValue(result.headers, @"Location");
            YZDownloadLog(@"tls failure %@ status=%lu size=%llu expected=%llu error=%@ location=%@ url=%@ finalURL=%@",
                          filePath,
                          (unsigned long)httpStatus,
                          YZFileSizeAtPath(filePath),
                          expectedTotal,
                          [result.error localizedDescription],
                          location,
                          urlString,
                          result.finalURL);
            // Keep partial data for network errors
            BOOL badContent = httpOK && result.error == nil && complete;
            BOOL hardClientError = (httpStatus >= 400 && httpStatus < 500 && httpStatus != 416 && httpStatus != 429);
            if (badContent || hardClientError || httpStatus == 416) {
                [YZDownloadResumeStore removeArtifactsForTargetPath:filePath includingTarget:YES];
            }
            NSUInteger nextAttempt = attempt + 1;
            if (nextAttempt < kMaxDownloadAttempts) {
                NSTimeInterval delay = YZRetryDelay(nextAttempt, httpStatus);
                YZDownloadLog(@"tls retry %@ nextAttempt=%lu delay=%.1f nextURL=%@", filePath, (unsigned long)(nextAttempt + 1), delay, YZDownloadCandidateForAttempt(candidates, nextAttempt));
                [self scheduleAttemptForParent:parent generation:generation targetPath:filePath delay:delay attempt:^{
                    [self downloadFileWithArchiveTLS:originalURL candidates:candidates targetPath:filePath parent:parent generation:generation attempt:nextAttempt];
                }];
            } else {
                YZTrackDownloadTelemetry(parent,
                                         @"download_failure",
                                         originalURL,
                                         urlString,
                                         result.finalURL,
                                         @"archive_tls",
                                         attempt,
                                         httpStatus,
                                         currentSize,
                                         expectedTotal,
                                         elapsed,
                                         0,
                                         (unsigned long long)((double)downloadedBytes / elapsed),
                                         result.headers,
                                         result.error);
                YZDownloadLog(@"tls final failure %@ after %lu attempts; falling back to BBHTTP", filePath, (unsigned long)kMaxDownloadAttempts);
                NSMutableDictionary *analyticsFields = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                         [NSString stringWithFormat:@"%lu", (unsigned long)kMaxDownloadAttempts], @"attempts",
                                                         [NSString stringWithFormat:@"%lu", (unsigned long)httpStatus], @"http_status",
                                                         @"archive_tls", @"fallback_from",
                                                         @"bbhttp", @"fallback_to",
                                                         nil];
                if ([urlString length] > 0) {
                    [analyticsFields setObject:urlString forKey:@"attempt_url"];
                }
                if ([result.finalURL length] > 0) {
                    [analyticsFields setObject:result.finalURL forKey:@"final_url"];
                }
                if ([[result.error localizedDescription] length] > 0) {
                    [analyticsFields setObject:[result.error localizedDescription] forKey:@"error"];
                }
                [VAPIHelper trackDownloadEvent:@"download_tls_fallback"
                                      bundleID:parent.bundleID
                                       appName:parent.name
                                     developer:parent.developer
                                       version:parent.version
                                        minIOS:parent.minimumOS
                                           url:originalURL
                                     sizeBytes:0
                                  downloadOnly:!parent.installAfterDownload
                                   extraFields:analyticsFields];
                [self scheduleAttemptForParent:parent generation:generation targetPath:filePath delay:0.0 attempt:^{
                    [self downloadFileViaBBHTTP:originalURL candidates:candidates targetPath:filePath parent:parent generation:generation attempt:0];
                }];
            }
        }
        YZReleaseTargetPath(filePath);
    }];
    downloader.finishingBlock = ^(unsigned long long total) {
        if (YZDownloadIsCurrent(parent, generation)) {
            parent.downloadFinishing = YES;
            [parent reportDownloadProgress:total total:total];
        }
    };
    weakDownloader = downloader;
    YZClaimTargetPath(filePath);
    parent.path = filePath;
    parent.request = nil;
    parent.downloadTask = downloader;
    [downloader start];
}

+ (void)downloadFileViaBBHTTP:(NSString *)originalURL candidates:(NSArray *)candidates targetPath:(NSString *)filePath parent:(YZQueueRep *)parent generation:(NSUInteger)generation attempt:(NSUInteger)attempt {
    if (!YZDownloadIsCurrent(parent, generation)) {
        return;
    }
    NSString *urlString = YZDownloadCandidateForAttempt(candidates, attempt);
    YZDownloadLog(@"start %@ attempt %lu/%lu url=%@", filePath, (unsigned long)(attempt + 1), (unsigned long)kMaxDownloadAttempts, urlString);
    parent.downloadFinishing = NO;
    YZPrepareResumeInfo(filePath, originalURL);
    YZCollapseParallelStateToPrefix(filePath);
    if (!YZShouldPreservePartialAtPath(filePath)) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
    }
    unsigned long long knownTotal = YZKnownTotalForTargetPath(filePath);
    unsigned long long resumeOffset = YZFileSizeAtPath(filePath);
    if (knownTotal > 0 && resumeOffset > knownTotal) {
        [YZDownloadResumeStore removeArtifactsForTargetPath:filePath includingTarget:YES];
        YZPrepareResumeInfo(filePath, originalURL);
        resumeOffset = 0;
    }
    YZDownloadLog(@"file=%@ resumeOffset=%llu", filePath, resumeOffset);
    __block NSTimeInterval telemetryStartedAt = [NSDate timeIntervalSinceReferenceDate];
    __block NSTimeInterval telemetryLastSampleAt = telemetryStartedAt;
    __block unsigned long long telemetryLastBytes = resumeOffset;

    BBHTTPRequest *request = [[BBHTTPRequest alloc] initWithTarget:urlString andVerb:@"GET"];
    request.allowInvalidSSLCertificates = YES;
    request.maxRedirects = 8;
    request.connectionTimeout = 45;
    request.downloadTimeout = BBTransferSpeedMake(1024, 45);
    if (resumeOffset > 0) {
        [request setValue:[NSString stringWithFormat:@"bytes=%llu-", resumeOffset] forHeader:@"Range"];
    }
    NSMutableDictionary *reqHeaders = [[VAPIHelper getHeaders] mutableCopy];
    for (id key in reqHeaders) {
        if ([key isKindOfClass:[NSString class]] && [(NSString *)key caseInsensitiveCompare:@"Range"] == NSOrderedSame) {
            continue;
        }
        [request setValue:[reqHeaders valueForKey:key] forHeader:key];
    }
    __block NSUInteger responseStatus = 0;
    __block NSDictionary *responseHeaders = nil;
    __block unsigned long long progressBase = resumeOffset;
    __block unsigned long long expectedTotal = 0;
    request.initialResponseBlock = ^(NSUInteger statusCode, NSDictionary *headers) {
        responseStatus = statusCode;
        responseHeaders = headers;
        if (statusCode != 206) {
            progressBase = 0;
        }
        expectedTotal = YZTotalBytesFromHeaders(headers, statusCode, progressBase);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        YZTrackDownloadTelemetry(parent,
                                 @"download_response",
                                 originalURL,
                                 urlString,
                                 nil,
                                 @"bbhttp",
                                 attempt,
                                 statusCode,
                                 progressBase,
                                 expectedTotal,
                                 MAX(0.001, now - telemetryStartedAt),
                                 0,
                                 0,
                                 headers,
                                 nil);
        YZDownloadLog(@"response %@ status=%lu contentLength=%@ contentRange=%@ expectedTotal=%llu",
                      filePath,
                      (unsigned long)statusCode,
                      YZHeaderValue(headers, @"Content-Length"),
                      YZHeaderValue(headers, @"Content-Range"),
                      expectedTotal);
        unsigned long long reportBase = progressBase;
        unsigned long long reportTotal = expectedTotal;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (YZDownloadIsCurrent(parent, generation) && reportTotal > 0) {
                [parent reportDownloadProgress:MIN(reportBase, reportTotal) total:reportTotal];
            }
        });
    };
    __block NSTimeInterval progressLastReportedAt = 0;
    NSTimeInterval progressInterval = [VeterisMemoryProfile activeValues].progressInterval;
    request.downloadProgressBlock = ^(NSUInteger current, NSUInteger total) {
        if (!YZDownloadIsCurrent(parent, generation)) {
            return;
        }
        unsigned long long fullCurrent = progressBase + current;
        unsigned long long fullTotal = expectedTotal > 0 ? expectedTotal : (progressBase + total);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - telemetryLastSampleAt >= kDownloadTelemetrySampleInterval) {
            NSTimeInterval interval = MAX(0.001, now - telemetryLastSampleAt);
            NSTimeInterval elapsed = MAX(0.001, now - telemetryStartedAt);
            unsigned long long intervalBytes = fullCurrent >= telemetryLastBytes ? fullCurrent - telemetryLastBytes : 0;
            unsigned long long downloadedBytes = fullCurrent >= resumeOffset ? fullCurrent - resumeOffset : 0;
            YZTrackDownloadTelemetry(parent,
                                     @"download_progress_sample",
                                     originalURL,
                                     urlString,
                                     nil,
                                     @"bbhttp",
                                     attempt,
                                     responseStatus,
                                     fullCurrent,
                                     fullTotal,
                                     elapsed,
                                     (unsigned long long)((double)intervalBytes / interval),
                                     (unsigned long long)((double)downloadedBytes / elapsed),
                                     nil,
                                     nil);
            telemetryLastSampleAt = now;
            telemetryLastBytes = fullCurrent;
        }
        BOOL shouldReportProgress = (now - progressLastReportedAt) >= progressInterval ||
                                    (fullTotal > 0 && fullCurrent >= fullTotal);
        if (shouldReportProgress) {
            progressLastReportedAt = now;
        }
        if (shouldReportProgress) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (YZDownloadIsCurrent(parent, generation)) {
                    [parent reportDownloadProgress:fullCurrent total:fullTotal];
                }
            });
        }
    };
    YZTrackedFileWriter *writer = [[YZTrackedFileWriter alloc] initWithTargetFile:filePath appendFromOffset:resumeOffset deletePartialOnCleanup:NO];
    request.finishBlock = ^(BBHTTPRequest *request) {
        [writer runWhenIdle:^{
            YZReleaseTargetPath(filePath);
        }];
        if (parent.downloadTask == request) {
            parent.downloadTask = nil;
            parent.request = nil;
        }
        if (!YZDownloadIsCurrent(parent, generation)) {
            YZDownloadLog(@"stale finish %@ cancelled=%d", filePath, [request wasCancelled]);
            return;
        }
        NSUInteger httpStatus = request.responseStatusCode;
        if (httpStatus == 0) {
            httpStatus = responseStatus;
        }
        NSDictionary *headers = request.response.headers ?: responseHeaders;
        BOOL cancelled = [request wasCancelled];
        // Protect the installer from redirect or error stubs
        BOOL httpOK = !cancelled && [request hasSuccessfulResponse] && httpStatus >= 200 && httpStatus < 300;
        BOOL appended = resumeOffset > 0 && httpStatus == 206;
        BOOL resumeMismatch = NO;
        if (httpStatus == 206 && YZContentRangeStart(headers) != (appended ? resumeOffset : 0)) {
            resumeMismatch = YES;
        }
        NSString *etag = YZHeaderValue(headers, @"ETag");
        NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:filePath];
        NSString *knownETag = [info objectForKey:YZResumeInfoETagKey];
        if (appended && ((knownTotal > 0 && expectedTotal > 0 && knownTotal != expectedTotal) ||
                         ([knownETag length] > 0 && [etag length] > 0 && ![knownETag isEqualToString:etag]))) {
            resumeMismatch = YES;
        }
        if (httpOK && !resumeMismatch) {
            NSMutableDictionary *validators = [NSMutableDictionary dictionary];
            if (expectedTotal > 0) {
                [validators setObject:[NSNumber numberWithUnsignedLongLong:expectedTotal] forKey:YZResumeInfoTotalKey];
            }
            if ([etag length] > 0) {
                [validators setObject:etag forKey:YZResumeInfoETagKey];
            }
            [YZDownloadResumeStore updateResumeInfoForTargetPath:filePath setting:validators removingKeys:nil];
        }
        BOOL complete = YZDownloadedFileMatchesExpectedTotal(filePath, expectedTotal);
        BOOL validIPA = httpOK && !resumeMismatch && request.error == nil && complete && [YZQueueOps isValidIPAAtPath:filePath];
        NSTimeInterval finishedAt = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval elapsed = MAX(0.001, finishedAt - telemetryStartedAt);
        unsigned long long currentSize = YZFileSizeAtPath(filePath);
        unsigned long long downloadedBytes = currentSize >= resumeOffset ? currentSize - resumeOffset : 0;

        if (httpStatus == 416 && resumeOffset > 0 && YZStoredFileIsComplete(filePath, headers)) {
            YZDownloadLog(@"success %@ existing file complete status=416", filePath);
            YZFinishSuccessfulDownload(parent, filePath);
        } else if (validIPA) {
            YZTrackDownloadTelemetry(parent,
                                     @"download_complete",
                                     originalURL,
                                     urlString,
                                     request.effectiveURL,
                                     @"bbhttp",
                                     attempt,
                                     httpStatus,
                                     currentSize,
                                     expectedTotal,
                                     elapsed,
                                     0,
                                     (unsigned long long)((double)downloadedBytes / elapsed),
                                     headers,
                                     request.error);
            YZDownloadLog(@"success %@ status=%lu url=%@", filePath, (unsigned long)httpStatus, urlString);
            YZFinishSuccessfulDownload(parent, filePath);
        } else {
            NSString *location = YZHeaderValue(headers, @"Location");
            YZDownloadLog(@"failure %@ status=%lu error=%@ location=%@ url=%@ mismatch=%d",
                          filePath,
                          (unsigned long)httpStatus,
                          [request.error localizedDescription],
                          location,
                          urlString,
                          resumeMismatch);
            BOOL badContent = httpOK && request.error == nil && complete;
            BOOL hardClientError = (httpStatus >= 400 && httpStatus < 500 && httpStatus != 429);
            BOOL discard = resumeMismatch || badContent || hardClientError;
            NSUInteger nextAttempt = attempt + 1;
            if (nextAttempt < kMaxDownloadAttempts) {
                NSTimeInterval delay = YZRetryDelay(nextAttempt, httpStatus);
                YZDownloadLog(@"retry %@ nextAttempt=%lu delay=%.1f discard=%d", filePath, (unsigned long)(nextAttempt + 1), delay, discard);
                [self scheduleAttemptForParent:parent generation:generation targetPath:filePath delay:delay attempt:^{
                    if (discard) {
                        [YZDownloadResumeStore removeArtifactsForTargetPath:filePath includingTarget:YES];
                    }
                    [self downloadFileViaBBHTTP:originalURL candidates:candidates targetPath:filePath parent:parent generation:generation attempt:nextAttempt];
                }];
            } else {
                YZTrackDownloadTelemetry(parent,
                                         @"download_failure",
                                         originalURL,
                                         urlString,
                                         request.effectiveURL,
                                         @"bbhttp",
                                         attempt,
                                         httpStatus,
                                         currentSize,
                                         expectedTotal,
                                         elapsed,
                                         0,
                                         (unsigned long long)((double)downloadedBytes / elapsed),
                                         headers,
                                         request.error);
                YZDownloadLog(@"final failure %@ after %lu attempts", filePath, (unsigned long)kMaxDownloadAttempts);
                if (discard) {
                    [self performWhenTargetPathIdle:filePath block:^{
                        [YZDownloadResumeStore removeArtifactsForTargetPath:filePath includingTarget:YES];
                    }];
                }
                YZFailDownload(parent, generation, [request.error localizedDescription] ?: [NSString stringWithFormat:@"Download failed with HTTP status %lu", (unsigned long)httpStatus]);
            }
        }
    };
    //request.downloadSpeedLimit = 1204; // 256KB/s
    request.responseContentHandler = writer;
    YZClaimTargetPath(filePath);
    parent.path = filePath;
    parent.request = request; // this is a weak reference, please check it for nil
    parent.downloadTask = request;
    if (![[BBHTTPExecutor sharedExecutor] executeRequest:request]) {
        parent.downloadTask = nil;
        parent.request = nil;
        YZReleaseTargetPath(filePath);
        YZFailDownload(parent, generation, @"Could not start download request");
    }
}

#pragma mark - Misc Methods
// Check the ZIP header and end record before treating a response as an IPA!!!
+ (BOOL)isValidIPAAtPath:(NSString *)path {
    unsigned long long size = YZFileSizeAtPath(path);
    if (size < kMinimumResumeBytes || !YZHasZipLocalHeader(path)) {
        return NO;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return NO;
    }
    unsigned long long tailLength = MIN(size, (unsigned long long)(kZipEndOfCentralDirectorySize + kZipMaxCommentSize));
    unsigned long long tailOffset = size - tailLength;
    NSData *tail = nil;
    @try {
        [handle seekToFileOffset:tailOffset];
        tail = [handle readDataOfLength:(NSUInteger)tailLength];
    } @catch (NSException *exception) {
        tail = nil;
    }
    [handle closeFile];
    if ([tail length] < kZipEndOfCentralDirectorySize) {
        return NO;
    }
    const unsigned char *b = [tail bytes];
    for (NSInteger i = (NSInteger)[tail length] - (NSInteger)kZipEndOfCentralDirectorySize; i >= 0; i--) {
        if (b[i] != 'P' || b[i + 1] != 'K' || b[i + 2] != 0x05 || b[i + 3] != 0x06) {
            continue;
        }
        uint32_t centralDirectorySize = (uint32_t)b[i + 12] | ((uint32_t)b[i + 13] << 8) | ((uint32_t)b[i + 14] << 16) | ((uint32_t)b[i + 15] << 24);
        uint32_t centralDirectoryOffset = (uint32_t)b[i + 16] | ((uint32_t)b[i + 17] << 8) | ((uint32_t)b[i + 18] << 16) | ((uint32_t)b[i + 19] << 24);
        if (centralDirectorySize == 0xFFFFFFFF || centralDirectoryOffset == 0xFFFFFFFF) {
            return YES;
        }
        unsigned long long recordOffset = tailOffset + (unsigned long long)i;
        return (unsigned long long)centralDirectoryOffset + (unsigned long long)centralDirectorySize <= recordOffset;
    }
    return NO;
}

+ (void)removeFileAt:(NSString *)path {
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) {
        debugLog(@"Error: %@, file already removed?", [error localizedDescription]);
    }
}

+ (void)notifyAppState:(YZQueueRep *)appRep {
    debugLog(@"Notifying app state change for %@, newState: %d", appRep.bundleID, appRep.state);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YZQueueRepStateChange" object:appRep];
}

+ (BOOL)doesPathExist:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}
@end
