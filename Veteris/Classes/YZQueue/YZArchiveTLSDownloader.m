#import "YZArchiveTLSDownloader.h"

#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/select.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <pthread.h>
#import <unistd.h>
#import <string.h>

#import "mbedtls/ctr_drbg.h"
#import "mbedtls/entropy.h"
#import "mbedtls/error.h"
#import "mbedtls/ssl.h"
#import "mbedtls/ssl_ciphersuites.h"

#import "../VAPIHelper/VAPIHelper.h"
#import "YZDownloadResumeStore.h"
#import "YZDownloadSegments.h"

#ifndef SO_NOSIGPIPE
#define SO_NOSIGPIPE 0x1022
#endif
#ifndef MBEDTLS_ERR_NET_SEND_FAILED
#define MBEDTLS_ERR_NET_SEND_FAILED -0x0052
#endif
#ifndef MBEDTLS_ERR_NET_RECV_FAILED
#define MBEDTLS_ERR_NET_RECV_FAILED -0x004E
#endif

NSString *const YZArchiveTLSErrorDomain = @"YZArchiveTLSDownloader";

static const NSUInteger kYZArchiveTLSMaxRedirects = 8;
static const NSTimeInterval kYZArchiveTLSDebugSampleInterval = 10.0;
static const unsigned long long kYZArchiveTLSParallelMinimumBytes = 2ULL * 1024ULL * 1024ULL;
static const unsigned long long kYZArchiveTLSSplitMinimumBytes = 256ULL * 1024ULL;
static const NSUInteger kYZArchiveTLSMaxSegments = 64;
static const NSTimeInterval kYZArchiveTLSStallSeconds = 6.0;
static const useconds_t kYZArchiveTLSIdlePollMicroseconds = 250000;
static const int kYZArchiveTLSConnectTimeoutSeconds = 20;
static const int kYZArchiveTLSIOTimeoutSeconds = 45;

static const int kYZArchiveTLSCipherSuites[] = {
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
    0
};

#ifdef VETERIS_DOWNLOAD_DEBUG
#define YZTLSLog(...) NSLog(@"[VeterisDownload] %@", [NSString stringWithFormat:__VA_ARGS__])
#else
#define YZTLSLog(...) do {} while (0)
#endif

typedef struct {
    int fd;
} YZTLSBio;

typedef struct {
    int fd;
    BOOL useTLS;
    BOOL tlsReady;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr;
    mbedtls_ssl_config config;
    mbedtls_ssl_context ssl;
    YZTLSBio bio;
} YZTLSConnection;

static int YZTLSBioSend(void *ctx, const unsigned char *buf, size_t len);
static int YZTLSBioRecv(void *ctx, unsigned char *buf, size_t len);

static NSUInteger YZTLSMergeChunkSize(void) {
    return [VeterisMemoryProfile activeValues].mergeChunkSize;
}

static unsigned long long YZTLSFileSize(NSString *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    return attrs != nil ? [attrs fileSize] : 0;
}

static BOOL YZTLSTruncateFile(NSString *path, unsigned long long length) {
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        return NO;
    }
    BOOL ok = YES;
    @try {
        [handle truncateFileAtOffset:length];
        [handle synchronizeFile];
    } @catch (NSException *exception) {
        ok = NO;
    } @finally {
        [handle closeFile];
    }
    return ok && YZTLSFileSize(path) == length;
}

static BOOL YZTLSWriteData(NSFileHandle *handle, NSData *data) {
    @try {
        [handle writeData:data];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

static pthread_mutex_t YZTLSSessionLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *YZTLSSessions = nil;

static NSString *YZTLSSessionKey(NSString *host, int port) {
    return [NSString stringWithFormat:@"%@:%d", [host lowercaseString], port];
}

static BOOL YZTLSApplyCachedSession(mbedtls_ssl_context *ssl, NSString *key) {
    BOOL applied = NO;
    pthread_mutex_lock(&YZTLSSessionLock);
    mbedtls_ssl_session *cached = (mbedtls_ssl_session *)[[YZTLSSessions objectForKey:key] pointerValue];
    if (cached != NULL && mbedtls_ssl_set_session(ssl, cached) == 0) {
        applied = YES;
    }
    pthread_mutex_unlock(&YZTLSSessionLock);
    return applied;
}

static void YZTLSStoreSession(mbedtls_ssl_context *ssl, NSString *key) {
    mbedtls_ssl_session *session = calloc(1, sizeof(mbedtls_ssl_session));
    if (session == NULL) {
        return;
    }
    mbedtls_ssl_session_init(session);
    if (mbedtls_ssl_get_session(ssl, session) != 0) {
        mbedtls_ssl_session_free(session);
        free(session);
        return;
    }
    pthread_mutex_lock(&YZTLSSessionLock);
    if (YZTLSSessions == nil) {
        YZTLSSessions = [[NSMutableDictionary alloc] init];
    }
    mbedtls_ssl_session *old = (mbedtls_ssl_session *)[[YZTLSSessions objectForKey:key] pointerValue];
    [YZTLSSessions setObject:[NSValue valueWithPointer:session] forKey:key];
    pthread_mutex_unlock(&YZTLSSessionLock);
    if (old != NULL) {
        mbedtls_ssl_session_free(old);
        free(old);
    }
}

@implementation YZArchiveTLSResult
@end

@interface YZArchiveTLSDownloader ()
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *targetPath;
@property (atomic, assign) unsigned long long resumeOffset;
@property (nonatomic, retain) NSDictionary *requestHeaders;
@property (nonatomic, copy) void (^progressBlock)(unsigned long long current, unsigned long long total);
@property (nonatomic, copy) void (^completionBlock)(YZArchiveTLSResult *result);
@property (atomic, assign) BOOL cancelled;
@property (atomic, assign) unsigned long long expectedTotal;
@property (atomic, copy) NSString *expectedETag;
@end

@implementation YZArchiveTLSDownloader {
    NSLock *_socketLock;
    // Distinguish a closed socket from a later one that reuses its file descriptor.
    NSMutableDictionary *_activeSockets;
    unsigned long long _socketSerial;
}

- (instancetype)initWithURL:(NSString *)url
                 targetPath:(NSString *)targetPath
               resumeOffset:(unsigned long long)resumeOffset
                    headers:(NSDictionary *)headers
                   progress:(void (^)(unsigned long long current, unsigned long long total))progress
                 completion:(void (^)(YZArchiveTLSResult *result))completion {
    if ((self = [super init])) {
        _url = [url copy];
        _targetPath = [targetPath copy];
        _resumeOffset = resumeOffset;
        _requestHeaders = [headers copy];
        _progressBlock = [progress copy];
        _completionBlock = [completion copy];
        _socketLock = [[NSLock alloc] init];
        _activeSockets = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)start {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        YZArchiveTLSResult *result = [self run];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.completionBlock != nil) {
                self.completionBlock(result);
            }
            self.completionBlock = nil;
            self.progressBlock = nil;
            self.finishingBlock = nil;
        });
    });
}

- (void)cancel {
    self.cancelled = YES;
    [_socketLock lock];
    for (NSNumber *fd in [_activeSockets allKeys]) {
        shutdown([fd intValue], SHUT_RDWR);
    }
    [_socketLock unlock];
}

- (YZArchiveTLSResult *)run {
    YZArchiveTLSResult *result = [[YZArchiveTLSResult alloc] init];
    result.finalURL = self.url;
    NSString *currentURL = self.url;

    if ([self resumeStoredPlan:result]) {
        return result;
    }

    for (NSUInteger redirect = 0; redirect <= kYZArchiveTLSMaxRedirects; redirect++) {
        if (self.cancelled) {
            result.cancelled = YES;
            return result;
        }

        NSDictionary *headers = nil;
        NSError *error = nil;
        NSUInteger statusCode = 0;
        NSString *location = nil;
        BOOL ok = [self fetchURL:currentURL statusCode:&statusCode headers:&headers location:&location error:&error];
        result.statusCode = statusCode;
        result.headers = headers;
        result.error = error;
        result.finalURL = currentURL;

        if (self.cancelled) {
            result.cancelled = YES;
            return result;
        }
        if (!ok) {
            if (result.error == nil) {
                result.error = [self errorWithCode:-1 description:@"Download failed"];
            }
            return result;
        }
        if (![self isRedirectStatus:statusCode]) {
            return result;
        }
        if ([location length] == 0 || redirect == kYZArchiveTLSMaxRedirects) {
            result.error = [self errorWithCode:(NSInteger)statusCode description:@"Redirect without usable Location"];
            return result;
        }

        NSString *nextURL = [self absoluteURLFromLocation:location baseURL:currentURL];
        YZTLSLog(@"tls redirect %lu status=%lu location=%@ next=%@",
                 (unsigned long)(redirect + 1),
                 (unsigned long)statusCode,
                 location,
                 nextURL);
        currentURL = nextURL;
    }

    return result;
}

#pragma mark - Main request

- (BOOL)resumeStoredPlan:(YZArchiveTLSResult *)result {
    if (self.resumeOffset == 0) {
        return NO;
    }
    NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:self.targetPath];
    NSString *resolvedURL = [info objectForKey:YZResumeInfoResolvedURLKey];
    unsigned long long total = [[info objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue];
    NSArray *segments = [self validatedSegmentsFromInfo:info total:total];
    if (![resolvedURL isKindOfClass:[NSString class]] || [resolvedURL length] == 0 || segments == nil ||
        [[info objectForKey:YZResumeInfoMergingKey] boolValue]) {
        return NO;
    }
    unsigned long long firstStart = [(YZDownloadSegment *)[segments objectAtIndex:0] start];
    unsigned long long firstEnd = [(YZDownloadSegment *)[segments objectAtIndex:0] end];
    if (self.resumeOffset < firstStart || self.resumeOffset > firstEnd + 1) {
        return NO;
    }
    NSString *etag = [info objectForKey:YZResumeInfoETagKey];
    self.expectedTotal = total;
    self.expectedETag = [etag isKindOfClass:[NSString class]] ? etag : nil;
    YZTLSLog(@"tls resume stored plan url=%@ offset=%llu total=%llu", resolvedURL, self.resumeOffset, total);
    NSError *error = nil;
    BOOL ok = [self downloadURLInParallel:resolvedURL base:self.resumeOffset total:total error:&error];
    if (self.cancelled) {
        result.cancelled = YES;
        return YES;
    }
    if (!ok) {
        YZTLSLog(@"tls stored plan resume failed (%@), using the regular path", [error localizedDescription]);
        self.resumeOffset = YZTLSFileSize(self.targetPath);
        return NO;
    }
    result.statusCode = 206;
    result.finalURL = resolvedURL;
    result.error = nil;
    result.headers = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"bytes %llu-%llu/%llu", firstStart, total - 1, total]
                                                 forKey:@"Content-Range"];
    return YES;
}

- (void)discardStoredPartial:(NSString *)reason {
    YZTLSLog(@"tls discard partial %@ reason=%@", self.targetPath, reason);
    [YZDownloadResumeStore removePartsForTargetPath:self.targetPath];
    [YZDownloadResumeStore updateResumeInfoForTargetPath:self.targetPath
                                                 setting:[NSDictionary dictionary]
                                            removingKeys:[NSArray arrayWithObjects:YZResumeInfoTotalKey, YZResumeInfoETagKey, YZResumeInfoSegmentsKey, YZResumeInfoMergingKey, nil]];
    [[NSFileManager defaultManager] removeItemAtPath:self.targetPath error:NULL];
    self.resumeOffset = 0;
}

- (BOOL)fetchURL:(NSString *)urlString statusCode:(NSUInteger *)statusCode headers:(NSDictionary **)headers location:(NSString **)location error:(NSError **)error {
    // Retry from byte 0 if the saved parts belong to a different file.
    for (NSUInteger pass = 0; pass < 2; pass++) {
        if (self.cancelled) {
            return NO;
        }
        YZTLSConnection conn;
        NSMutableData *bodyPrefix = [NSMutableData data];
        NSDictionary *parsedHeaders = nil;
        NSUInteger parsedStatus = 0;
        unsigned long long resumeOffset = self.resumeOffset;
        NSString *range = resumeOffset > 0 ? [NSString stringWithFormat:@"bytes=%llu-", resumeOffset] : nil;
        if (![self openConnection:&conn url:urlString range:range statusCode:&parsedStatus headers:&parsedHeaders bodyPrefix:bodyPrefix error:error]) {
            return NO;
        }
        if (statusCode != NULL) {
            *statusCode = parsedStatus;
        }
        if (headers != NULL) {
            *headers = parsedHeaders;
        }
        if (location != NULL) {
            *location = [self headerValue:@"Location" inHeaders:parsedHeaders];
        }

        YZTLSLog(@"tls response status=%lu contentLength=%@ contentRange=%@ url=%@",
                 (unsigned long)parsedStatus,
                 [self headerValue:@"Content-Length" inHeaders:parsedHeaders],
                 [self headerValue:@"Content-Range" inHeaders:parsedHeaders],
                 urlString);

        if (parsedStatus == 416 && resumeOffset > 0) {
            [self closeConnection:&conn];
            unsigned long long serverTotal = [self totalFromUnsatisfiedRange:parsedHeaders];
            unsigned long long knownTotal = [[[YZDownloadResumeStore resumeInfoForTargetPath:self.targetPath] objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue];
            unsigned long long expected = serverTotal > 0 ? serverTotal : knownTotal;
            unsigned long long size = YZTLSFileSize(self.targetPath);
            if (expected == 0 || size == expected) {
                [YZDownloadResumeStore removePartsForTargetPath:self.targetPath];
                return YES;
            }
            [self discardStoredPartial:[NSString stringWithFormat:@"416 size=%llu expected=%llu", size, expected]];
            continue;
        }

        if (parsedStatus < 200 || parsedStatus >= 300) {
            [self closeConnection:&conn];
            return YES;
        }

        BOOL append = (resumeOffset > 0 && parsedStatus == 206);
        if (parsedStatus == 206) {
            unsigned long long rangeStart = [self startFromContentRange:parsedHeaders];
            if (rangeStart != (append ? resumeOffset : 0)) {
                [self closeConnection:&conn];
                if (resumeOffset == 0) {
                    if (error != NULL) {
                        *error = [self errorWithCode:-8 description:@"Server returned an unexpected byte range"];
                    }
                    return NO;
                }
                [self discardStoredPartial:@"unexpected Content-Range start"];
                continue;
            }
        }

        unsigned long long base = append ? resumeOffset : 0;
        unsigned long long total = [self totalBytesFromHeaders:parsedHeaders statusCode:parsedStatus base:base];
        NSString *etag = [self headerValue:@"ETag" inHeaders:parsedHeaders];
        NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:self.targetPath];
        if (append) {
            unsigned long long knownTotal = [[info objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue];
            NSString *knownETag = [info objectForKey:YZResumeInfoETagKey];
            BOOL totalMismatch = (knownTotal > 0 && total > 0 && knownTotal != total);
            BOOL etagMismatch = ([knownETag length] > 0 && [etag length] > 0 && ![knownETag isEqualToString:etag]);
            if (totalMismatch || etagMismatch) {
                [self closeConnection:&conn];
                [self discardStoredPartial:@"validator mismatch"];
                continue;
            }
        } else {
            [YZDownloadResumeStore removePartsForTargetPath:self.targetPath];
            [YZDownloadResumeStore updateResumeInfoForTargetPath:self.targetPath
                                                         setting:[NSDictionary dictionary]
                                                    removingKeys:[NSArray arrayWithObjects:YZResumeInfoSegmentsKey, YZResumeInfoMergingKey, nil]];
            info = [YZDownloadResumeStore resumeInfoForTargetPath:self.targetPath];
        }
        NSMutableDictionary *validators = [NSMutableDictionary dictionary];
        if (total > 0) {
            [validators setObject:[NSNumber numberWithUnsignedLongLong:total] forKey:YZResumeInfoTotalKey];
        }
        if ([etag length] > 0) {
            [validators setObject:etag forKey:YZResumeInfoETagKey];
        }
        [validators setObject:urlString forKey:YZResumeInfoResolvedURLKey];
        [YZDownloadResumeStore updateResumeInfoForTargetPath:self.targetPath setting:validators removingKeys:nil];
        self.expectedTotal = total;
        self.expectedETag = [etag length] > 0 ? etag : nil;

        BOOL hasPlan = append && [self validatedSegmentsFromInfo:info total:total] != nil;
        NSUInteger parallelSegments = [VeterisMemoryProfile connectionsPerDownload];
        BOOL wantsParallel = (parallelSegments >= 2 && total > base && total - base >= kYZArchiveTLSParallelMinimumBytes);
        if (total > base && (hasPlan || wantsParallel)) {
            YZTLSLog(@"tls parallel start url=%@ base=%llu total=%llu segments=%lu plan=%d",
                     urlString, base, total, (unsigned long)parallelSegments, hasPlan);
            [self closeConnection:&conn];
            return [self downloadURLInParallel:urlString base:base total:total error:error];
        }

        BOOL ok = [self writeSingleStreamFrom:&conn prefix:bodyPrefix append:append base:base total:total url:urlString error:error];
        [self closeConnection:&conn];
        return ok && !self.cancelled;
    }

    if (error != NULL) {
        *error = [self errorWithCode:-9 description:@"Stored partial download did not match the server file"];
    }
    return NO;
}

- (BOOL)writeSingleStreamFrom:(YZTLSConnection *)conn
                       prefix:(NSData *)bodyPrefix
                       append:(BOOL)append
                         base:(unsigned long long)base
                        total:(unsigned long long)total
                          url:(NSString *)urlString
                        error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    if (!append || ![manager fileExistsAtPath:self.targetPath]) {
        [manager createFileAtPath:self.targetPath contents:nil attributes:nil];
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:self.targetPath];
    if (file == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open target file"];
        }
        return NO;
    }
    if (append) {
        [file seekToEndOfFile];
    } else {
        [file truncateFileAtOffset:0];
    }

    unsigned long long limit = total > base ? total - base : 0;
    __block unsigned long long sampleBytes = 0;
    __block NSTimeInterval sampleStartedAt = [NSDate timeIntervalSinceReferenceDate];
    unsigned long long written = 0;
    BOOL ok = [self streamBodyFrom:conn prefix:bodyPrefix toFile:file limit:limit written:&written progress:^(unsigned long long current) {
        [self reportProgress:base + current total:total];
        sampleBytes = current;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - sampleStartedAt >= kYZArchiveTLSDebugSampleInterval) {
            YZTLSLog(@"tls io url=%@ totalWritten=%llu total=%llu", urlString, base + sampleBytes, total);
            sampleStartedAt = now;
        }
    } error:error];
    [file synchronizeFile];
    [file closeFile];
    return ok;
}

#pragma mark - Parallel segments

- (NSMutableArray *)validatedSegmentsFromInfo:(NSDictionary *)info total:(unsigned long long)total {
    NSArray *plan = [info objectForKey:YZResumeInfoSegmentsKey];
    if (![plan isKindOfClass:[NSArray class]] || [plan count] == 0 || total == 0) {
        return nil;
    }
    if ([[info objectForKey:YZResumeInfoTotalKey] unsignedLongLongValue] != total) {
        return nil;
    }
    NSMutableArray *segments = [NSMutableArray arrayWithCapacity:[plan count]];
    for (NSUInteger idx = 0; idx < [plan count]; idx++) {
        NSDictionary *entry = [plan objectAtIndex:idx];
        if (![entry isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        id part = [entry objectForKey:YZResumeInfoSegmentPartKey];
        YZDownloadSegment *segment = [[YZDownloadSegment alloc] init];
        segment.start = [[entry objectForKey:YZResumeInfoSegmentStartKey] unsignedLongLongValue];
        segment.end = [[entry objectForKey:YZResumeInfoSegmentEndKey] unsignedLongLongValue];
        segment.part = [part respondsToSelector:@selector(unsignedIntegerValue)] ? [part unsignedIntegerValue] : idx;
        [segments addObject:segment];
    }
    return [YZDownloadSegments segmentsAreValid:segments total:total] ? segments : nil;
}

- (NSString *)pathForSegment:(YZDownloadSegment *)segment {
    return segment.part == 0 ? self.targetPath : [YZDownloadResumeStore partPathForTargetPath:self.targetPath index:segment.part];
}

- (void)storeSegments:(NSArray *)segments total:(unsigned long long)total {
    NSMutableArray *plan = [NSMutableArray arrayWithCapacity:[segments count]];
    for (YZDownloadSegment *segment in segments) {
        [plan addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                         [NSNumber numberWithUnsignedLongLong:segment.start], YZResumeInfoSegmentStartKey,
                         [NSNumber numberWithUnsignedLongLong:segment.end], YZResumeInfoSegmentEndKey,
                         [NSNumber numberWithUnsignedInteger:segment.part], YZResumeInfoSegmentPartKey,
                         nil]];
    }
    [YZDownloadResumeStore updateResumeInfoForTargetPath:self.targetPath
                                                 setting:[NSDictionary dictionaryWithObjectsAndKeys:
                                                          plan, YZResumeInfoSegmentsKey,
                                                          [NSNumber numberWithBool:NO], YZResumeInfoMergingKey,
                                                          [NSNumber numberWithUnsignedLongLong:total], YZResumeInfoTotalKey,
                                                          nil]
                                            removingKeys:nil];
}

// The sidecar stores the segment layout so each part can resume at its saved offset.
// Split a slow segment between free connections so they can finish together.
- (BOOL)downloadURLInParallel:(NSString *)urlString base:(unsigned long long)base total:(unsigned long long)total error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *targetPath = self.targetPath;
    NSDictionary *info = [YZDownloadResumeStore resumeInfoForTargetPath:targetPath];
    NSMutableArray *segments = base > 0 ? [self validatedSegmentsFromInfo:info total:total] : nil;

    if (base == 0) {
        [YZDownloadResumeStore removePartsForTargetPath:targetPath];
        [manager createFileAtPath:targetPath contents:nil attributes:nil];
    }
    unsigned long long targetSize = YZTLSFileSize(targetPath);

    if (segments != nil) {
        YZDownloadSegment *first = [segments objectAtIndex:0];
        if ([[info objectForKey:YZResumeInfoMergingKey] boolValue] && targetSize > first.end + 1) {
            // Rebuild the target if the previous merge was interrupted.
            if (YZTLSTruncateFile(targetPath, first.end + 1)) {
                targetSize = first.end + 1;
            }
        }
        if (targetSize < first.start || targetSize > first.end + 1) {
            segments = nil;
        }
    }
    if (segments == nil) {
        [YZDownloadResumeStore removePartsForTargetPath:targetPath];
        if (targetSize >= total) {
            if (error != NULL) {
                *error = [self errorWithCode:-10 description:@"Stored partial download is larger than the server file"];
            }
            [self discardStoredPartial:@"target larger than total"];
            return NO;
        }
        segments = [YZDownloadSegments segmentsFromBase:targetSize total:total count:[VeterisMemoryProfile connectionsPerDownload]];
    }

    NSMutableSet *plannedParts = [NSMutableSet set];
    for (YZDownloadSegment *segment in segments) {
        NSString *segmentPath = [self pathForSegment:segment];
        unsigned long long have = segment.part == 0 ? targetSize - segment.start : YZTLSFileSize(segmentPath);
        if (segment.part != 0) {
            if (have > [segment length]) {
                [manager removeItemAtPath:segmentPath error:NULL];
                have = 0;
            }
            [plannedParts addObject:segmentPath];
        }
        segment.have = have;
        segment.active = NO;
    }
    for (NSString *partPath in [YZDownloadResumeStore existingPartPathsForTargetPath:targetPath]) {
        if (![plannedParts containsObject:partPath]) {
            [manager removeItemAtPath:partPath error:NULL];
        }
    }
    [self storeSegments:segments total:total];

    NSLock *lock = [[NSLock alloc] init];
    NSMutableDictionary *segmentSockets = [NSMutableDictionary dictionary];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block BOOL failed = NO;
    __block NSError *firstError = nil;
    __block NSTimeInterval lastProgressReport = 0;
    NSTimeInterval progressInterval = [VeterisMemoryProfile activeValues].progressInterval;
    NSUInteger connections = MAX((NSUInteger)1, [VeterisMemoryProfile connectionsPerDownload]);

    [self reportProgress:MIN([YZDownloadSegments storedBytesInSegments:segments], total) total:total];
    void (^progress)(void) = ^{
        [lock lock];
        unsigned long long aggregate = [YZDownloadSegments storedBytesInSegments:segments];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        BOOL shouldReport = (now - lastProgressReport) >= progressInterval || aggregate >= total;
        if (shouldReport) {
            lastProgressReport = now;
        }
        [lock unlock];
        if (shouldReport) {
            [self reportProgress:MIN(aggregate, total) total:total];
        }
    };

    for (NSUInteger connection = 0; connection < connections; connection++) {
        dispatch_group_async(group, queue, ^{
            while (YES) {
                YZDownloadSegment *segment = nil;
                NSUInteger token = 0;
                BOOL done = NO;
                [lock lock];
                if (failed || self.cancelled) {
                    done = YES;
                } else {
                    YZSegmentClaim kind = YZSegmentClaimNone;
                    segment = [YZDownloadSegments claimSegmentFrom:segments
                                                 minimumSplitBytes:kYZArchiveTLSSplitMinimumBytes
                                                   maximumSegments:kYZArchiveTLSMaxSegments
                                                     stallInterval:kYZArchiveTLSStallSeconds
                                                               now:[NSDate timeIntervalSinceReferenceDate]
                                                              kind:&kind];
                    token = segment.owner;
                    if (kind == YZSegmentClaimSplit) {
                        [manager removeItemAtPath:[self pathForSegment:segment] error:NULL];
                        [self storeSegments:segments total:total];
                        YZTLSLog(@"tls split new part=%lu start=%llu end=%llu segments=%lu",
                                 (unsigned long)segment.part, segment.start, segment.end, (unsigned long)[segments count]);
                    } else if (kind == YZSegmentClaimTakeover) {
                        // A connection that loses ownership must stop before its next write.
                        NSNumber *partKey = [NSNumber numberWithUnsignedInteger:segment.part];
                        NSArray *stalledSocket = [segmentSockets objectForKey:partKey];
                        if (stalledSocket != nil) {
                            [self shutdownSocket:[[stalledSocket objectAtIndex:0] intValue] serial:[[stalledSocket objectAtIndex:1] unsignedLongLongValue]];
                            [segmentSockets removeObjectForKey:partKey];
                        }
                        YZTLSLog(@"tls takeover part=%lu remaining=%llu takeovers=%lu",
                                 (unsigned long)segment.part, [segment remaining], (unsigned long)segment.takeovers);
                    } else if (segment == nil) {
                        done = [YZDownloadSegments allSegmentsComplete:segments];
                    }
                }
                [lock unlock];
                if (done) {
                    break;
                }
                if (segment == nil) {
                    usleep(kYZArchiveTLSIdlePollMicroseconds);
                    continue;
                }
                NSError *segmentError = nil;
                BOOL ok = [self fetchSegment:segment token:token url:urlString lock:lock sockets:segmentSockets progress:progress error:&segmentError];
                [lock lock];
                if (segment.owner == token) {
                    segment.active = NO;
                }
                if (!ok && !failed) {
                    failed = YES;
                    firstError = segmentError;
                }
                [lock unlock];
                if (!ok) {
                    if (!self.cancelled) {
                        [self abortActiveSockets];
                    }
                    break;
                }
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    if (self.cancelled) {
        return NO;
    }
    if (failed) {
        if (error != NULL) {
            *error = firstError ?: [self errorWithCode:-5 description:@"Parallel range download failed"];
        }
        return NO;
    }

    if (![self mergeSegments:segments total:total error:error]) {
        return NO;
    }
    [self reportProgress:total total:total];
    YZTLSLog(@"tls parallel complete url=%@ total=%llu segments=%lu", urlString, total, (unsigned long)[segments count]);
    return YES;
}

- (void)notifyFinishing:(unsigned long long)total {
    void (^finishingBlock)(unsigned long long) = self.finishingBlock;
    if (finishingBlock == nil || self.cancelled) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cancelled) {
            finishingBlock(total);
        }
    });
}

- (BOOL)mergeSegments:(NSArray *)segments total:(unsigned long long)total error:(NSError **)error {
    NSString *targetPath = self.targetPath;
    YZDownloadSegment *first = [segments objectAtIndex:0];
    if (YZTLSFileSize(targetPath) != first.end + 1) {
        if (error != NULL) {
            *error = [self errorWithCode:-6 description:@"First download segment is incomplete"];
        }
        return NO;
    }
    for (NSUInteger idx = 1; idx < [segments count]; idx++) {
        YZDownloadSegment *segment = [segments objectAtIndex:idx];
        if (YZTLSFileSize([self pathForSegment:segment]) != [segment length]) {
            if (error != NULL) {
                *error = [self errorWithCode:-6 description:@"Downloaded segment is incomplete"];
            }
            return NO;
        }
    }

    [self notifyFinishing:total];
    [YZDownloadResumeStore updateResumeInfoForTargetPath:targetPath
                                                 setting:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:YZResumeInfoMergingKey]
                                            removingKeys:nil];
    NSFileHandle *target = [NSFileHandle fileHandleForWritingAtPath:targetPath];
    if (target == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open target file"];
        }
        return NO;
    }
    [target seekToEndOfFile];
    NSUInteger mergeChunkSize = YZTLSMergeChunkSize();
    BOOL ok = YES;
    for (NSUInteger idx = 1; idx < [segments count] && ok; idx++) {
        NSFileHandle *part = [NSFileHandle fileHandleForReadingAtPath:[self pathForSegment:[segments objectAtIndex:idx]]];
        if (part == nil) {
            ok = NO;
            break;
        }
        while (ok) {
            if (self.cancelled) {
                ok = NO;
                break;
            }
            @autoreleasepool {
                NSData *chunk = [part readDataOfLength:mergeChunkSize];
                if ([chunk length] == 0) {
                    break;
                }
                ok = YZTLSWriteData(target, chunk);
            }
        }
        [part closeFile];
    }
    [target synchronizeFile];
    [target closeFile];

    if (!ok || YZTLSFileSize(targetPath) != total) {
        if (error != NULL && !self.cancelled) {
            *error = [self errorWithCode:-11 description:@"Could not merge downloaded segments"];
        }
        return NO;
    }
    [YZDownloadResumeStore removePartsForTargetPath:targetPath];
    [YZDownloadResumeStore updateResumeInfoForTargetPath:targetPath
                                                 setting:[NSDictionary dictionary]
                                            removingKeys:[NSArray arrayWithObjects:YZResumeInfoSegmentsKey, YZResumeInfoMergingKey, nil]];
    return YES;
}

// Check ownership and write while holding the same lock.
- (BOOL)fetchSegment:(YZDownloadSegment *)segment
               token:(NSUInteger)token
                 url:(NSString *)urlString
                lock:(NSLock *)lock
             sockets:(NSMutableDictionary *)sockets
            progress:(void (^)(void))progress
               error:(NSError **)error {
    NSNumber *partKey = [NSNumber numberWithUnsignedInteger:segment.part];
    NSString *segmentPath = [self pathForSegment:segment];
    [lock lock];
    BOOL owned = segment.owner == token;
    unsigned long long start = segment.start + segment.have;
    unsigned long long end = segment.end;
    [lock unlock];
    if (!owned || start > end) {
        return YES;
    }

    BOOL (^release)(void) = ^BOOL{
        [lock lock];
        BOOL stillOwned = segment.owner == token;
        if (stillOwned) {
            [sockets removeObjectForKey:partKey];
        }
        [lock unlock];
        return stillOwned;
    };

    YZTLSConnection conn;
    NSMutableData *bodyPrefix = [NSMutableData data];
    NSDictionary *parsedHeaders = nil;
    NSUInteger parsedStatus = 0;
    NSString *range = [NSString stringWithFormat:@"bytes=%llu-%llu", start, end];
    BOOL opened = [self openConnection:&conn
                                   url:urlString
                                 range:range
                            statusCode:&parsedStatus
                               headers:&parsedHeaders
                            bodyPrefix:bodyPrefix
                         socketHandler:^(int fd, unsigned long long serial) {
        [lock lock];
        if (segment.owner == token) {
            [sockets setObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:fd], [NSNumber numberWithUnsignedLongLong:serial], nil] forKey:partKey];
        } else {
            [self shutdownSocket:fd serial:serial];
        }
        [lock unlock];
    }
                                 error:error];
    if (!opened) {
        return !release();
    }
    if (parsedStatus != 206 || [self startFromContentRange:parsedHeaders] != start) {
        [self closeConnection:&conn];
        if (!release()) {
            return YES;
        }
        if (error != NULL) {
            *error = [self errorWithCode:(NSInteger)parsedStatus description:[NSString stringWithFormat:@"Range request returned HTTP %lu", (unsigned long)parsedStatus]];
        }
        return NO;
    }
    unsigned long long responseTotal = [self totalBytesFromHeaders:parsedHeaders statusCode:206 base:0];
    NSString *responseETag = [self headerValue:@"ETag" inHeaders:parsedHeaders];
    NSString *expectedETag = self.expectedETag;
    if ((self.expectedTotal > 0 && responseTotal != self.expectedTotal) ||
        ([expectedETag length] > 0 && [responseETag length] > 0 && ![expectedETag isEqualToString:responseETag])) {
        [self closeConnection:&conn];
        if (!release()) {
            return YES;
        }
        if (error != NULL) {
            *error = [self errorWithCode:-13 description:@"Server file changed during the download"];
        }
        return NO;
    }

    NSFileHandle *file = nil;
    [lock lock];
    owned = segment.owner == token;
    if (owned) {
        segment.lastActivity = [NSDate timeIntervalSinceReferenceDate];
        NSFileManager *manager = [NSFileManager defaultManager];
        if ((segment.part != 0 && segment.have == 0) || ![manager fileExistsAtPath:segmentPath]) {
            [manager createFileAtPath:segmentPath contents:nil attributes:nil];
        }
        file = [NSFileHandle fileHandleForWritingAtPath:segmentPath];
        [file seekToEndOfFile];
    }
    [lock unlock];
    if (!owned) {
        [self closeConnection:&conn];
        return YES;
    }
    if (file == nil) {
        [self closeConnection:&conn];
        if (!release()) {
            return YES;
        }
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open segment file"];
        }
        return NO;
    }

    __block BOOL lost = NO;
    __block BOOL writeFailed = NO;
    BOOL (^store)(const unsigned char *, NSUInteger) = ^BOOL(const unsigned char *bytes, NSUInteger count) {
        BOOL more = NO;
        [lock lock];
        if (segment.owner != token) {
            lost = YES;
        } else {
            unsigned long long keep = MIN((unsigned long long)count, [segment remaining]);
            if (keep > 0) {
                if (YZTLSWriteData(file, [NSData dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)keep freeWhenDone:NO])) {
                    segment.have += keep;
                    segment.lastActivity = [NSDate timeIntervalSinceReferenceDate];
                } else {
                    writeFailed = YES;
                }
            }
            more = !writeFailed && ![segment isComplete];
        }
        [lock unlock];
        if (!lost && !writeFailed && progress != nil) {
            progress();
        }
        return more;
    };

    BOOL more = YES;
    NSError *readError = nil;
    if ([bodyPrefix length] > 0) {
        more = store([bodyPrefix bytes], [bodyPrefix length]);
    }
    NSUInteger bufferSize = [VeterisMemoryProfile activeValues].readBufferSize;
    NSMutableData *readBuffer = [NSMutableData dataWithLength:bufferSize];
    unsigned char *buffer = (unsigned char *)[readBuffer mutableBytes];
    while (more && !self.cancelled) {
        @autoreleasepool {
            [lock lock];
            unsigned long long left = segment.owner == token ? [segment remaining] : 0;
            [lock unlock];
            if (left == 0) {
                break;
            }
            int ret = [self readFromConnection:&conn buffer:buffer length:(size_t)MIN((unsigned long long)bufferSize, left)];
            if (ret == 0) {
                break;
            }
            if (ret < 0) {
                NSString *description = ret == MBEDTLS_ERR_SSL_TIMEOUT ? @"Connection timed out" : [self tlsErrorString:ret];
                readError = [self errorWithCode:ret description:description];
                break;
            }
            more = store(buffer, (NSUInteger)ret);
        }
    }
    [file synchronizeFile];
    [file closeFile];
    BOOL stillOwned = release();
    [self closeConnection:&conn];

    if (self.cancelled) {
        return NO;
    }
    if (lost || !stillOwned) {
        YZTLSLog(@"tls parallel segment part=%lu was taken over", (unsigned long)segment.part);
        return YES;
    }
    if (writeFailed) {
        if (error != NULL) {
            *error = [self errorWithCode:-12 description:@"Could not write to disk"];
        }
        return NO;
    }
    [lock lock];
    unsigned long long missing = [segment remaining];
    unsigned long long expected = [segment length];
    [lock unlock];
    if (missing > 0) {
        if (error != NULL) {
            *error = readError ?: [self errorWithCode:-7 description:[NSString stringWithFormat:@"Segment ended early, got %llu of %llu bytes", expected - missing, expected]];
        }
        return NO;
    }
    YZTLSLog(@"tls parallel segment part=%lu complete, started at %llu", (unsigned long)segment.part, start);
    return YES;
}

#pragma mark - Connection handling

- (BOOL)openConnection:(YZTLSConnection *)conn
                   url:(NSString *)urlString
                 range:(NSString *)range
            statusCode:(NSUInteger *)statusCode
               headers:(NSDictionary **)headers
            bodyPrefix:(NSMutableData *)bodyPrefix
                 error:(NSError **)error {
    return [self openConnection:conn url:urlString range:range statusCode:statusCode headers:headers bodyPrefix:bodyPrefix socketHandler:nil error:error];
}

- (BOOL)openConnection:(YZTLSConnection *)conn
                   url:(NSString *)urlString
                 range:(NSString *)range
            statusCode:(NSUInteger *)statusCode
               headers:(NSDictionary **)headers
            bodyPrefix:(NSMutableData *)bodyPrefix
         socketHandler:(void (^)(int fd, unsigned long long serial))socketHandler
                 error:(NSError **)error {
    memset(conn, 0, sizeof(YZTLSConnection));
    conn->fd = -1;

    NSURL *url = [NSURL URLWithString:urlString];
    NSString *scheme = [[url scheme] lowercaseString];
    NSString *host = [url host];
    NSNumber *portNumber = [url port];
    BOOL useTLS = [scheme isEqualToString:@"https"];
    int port = [portNumber intValue] > 0 ? [portNumber intValue] : (useTLS ? 443 : 80);
    if ([host length] == 0 || (!useTLS && ![scheme isEqualToString:@"http"])) {
        if (error != NULL) {
            *error = [self errorWithCode:-1 description:@"Unsupported or malformed URL"];
        }
        return NO;
    }

    int fd = [self connectToHost:host port:port socketHandler:socketHandler error:error];
    if (fd < 0) {
        return NO;
    }
    conn->fd = fd;
    conn->useTLS = useTLS;
    conn->bio.fd = fd;

    if (useTLS) {
        conn->tlsReady = YES;
        if (![self setupTLS:&conn->ssl config:&conn->config entropy:&conn->entropy ctr:&conn->ctr bio:&conn->bio host:host port:port error:error]) {
            [self closeConnection:conn];
            return NO;
        }
    }

    NSString *path = [self requestPathForURLString:urlString];
    NSMutableString *request = [NSMutableString stringWithFormat:@"GET %@ HTTP/1.0\r\nHost: %@\r\nUser-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 6_1 like Mac OS X) Veteris/2.1\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n", path, host];
    for (NSString *key in self.requestHeaders) {
        NSString *value = [self.requestHeaders objectForKey:key];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
            continue;
        }
        if ([key length] > 0 && [value length] > 0 &&
            [key rangeOfString:@"\r"].location == NSNotFound && [key rangeOfString:@"\n"].location == NSNotFound &&
            [value rangeOfString:@"\r"].location == NSNotFound && [value rangeOfString:@"\n"].location == NSNotFound &&
            [key caseInsensitiveCompare:@"Range"] != NSOrderedSame &&
            [key caseInsensitiveCompare:@"Accept-Encoding"] != NSOrderedSame) {
            [request appendFormat:@"%@: %@\r\n", key, value];
        }
    }
    if ([range length] > 0) {
        [request appendFormat:@"Range: %@\r\n", range];
    }
    [request appendString:@"\r\n"];

    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wroteRequest = useTLS ? [self tlsWrite:&conn->ssl data:requestData error:error] : [self socketWrite:fd data:requestData error:error];
    if (!wroteRequest) {
        [self closeConnection:conn];
        return NO;
    }

    NSMutableData *headerData = [NSMutableData data];
    if (![self readHeaderFromConnection:conn headerData:headerData error:error]) {
        [self closeConnection:conn];
        return NO;
    }
    [bodyPrefix setLength:0];

    NSDictionary *parsedHeaders = nil;
    NSUInteger parsedStatus = [self parseHeaderData:headerData headers:&parsedHeaders];
    if (parsedStatus == 0) {
        if (error != NULL) {
            *error = [self errorWithCode:-3 description:@"Malformed HTTP response"];
        }
        [self closeConnection:conn];
        return NO;
    }
    if (statusCode != NULL) {
        *statusCode = parsedStatus;
    }
    if (headers != NULL) {
        *headers = parsedHeaders;
    }
    return YES;
}

- (void)closeConnection:(YZTLSConnection *)conn {
    if (conn->tlsReady) {
        if (!self.cancelled) {
            mbedtls_ssl_close_notify(&conn->ssl);
        }
        mbedtls_ssl_free(&conn->ssl);
        mbedtls_ssl_config_free(&conn->config);
        mbedtls_ctr_drbg_free(&conn->ctr);
        mbedtls_entropy_free(&conn->entropy);
        conn->tlsReady = NO;
    }
    if (conn->fd >= 0) {
        [self closeSocket:conn->fd];
        conn->fd = -1;
    }
}

- (int)readFromConnection:(YZTLSConnection *)conn buffer:(unsigned char *)buffer length:(size_t)length {
    while (!self.cancelled) {
        if (conn->useTLS) {
            int ret = mbedtls_ssl_read(&conn->ssl, buffer, length);
            if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
                continue;
            }
            if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
                return 0;
            }
            return ret;
        }
        ssize_t readBytes = recv(conn->fd, buffer, length, 0);
        if (readBytes < 0 && errno == EINTR) {
            continue;
        }
        if (readBytes < 0) {
            return (errno == EAGAIN || errno == EWOULDBLOCK) ? MBEDTLS_ERR_SSL_TIMEOUT : MBEDTLS_ERR_NET_RECV_FAILED;
        }
        return (int)readBytes;
    }
    return 0;
}

- (BOOL)streamBodyFrom:(YZTLSConnection *)conn
                prefix:(NSData *)bodyPrefix
                toFile:(NSFileHandle *)file
                 limit:(unsigned long long)limit
               written:(unsigned long long *)writtenOut
              progress:(void (^)(unsigned long long written))progress
                 error:(NSError **)error {
    unsigned long long written = 0;
    BOOL ok = YES;
    if ([bodyPrefix length] > 0) {
        NSData *data = bodyPrefix;
        if (limit > 0 && [data length] > limit) {
            data = [data subdataWithRange:NSMakeRange(0, (NSUInteger)limit)];
        }
        if (!YZTLSWriteData(file, data)) {
            ok = NO;
            if (error != NULL) {
                *error = [self errorWithCode:-12 description:@"Could not write to disk"];
            }
        } else {
            written += [data length];
            if (progress != nil) {
                progress(written);
            }
        }
    }

    NSUInteger bufferSize = [VeterisMemoryProfile activeValues].readBufferSize;
    NSMutableData *readBuffer = [NSMutableData dataWithLength:bufferSize];
    unsigned char *buffer = (unsigned char *)[readBuffer mutableBytes];
    while (ok && !self.cancelled && (limit == 0 || written < limit)) {
        @autoreleasepool {
            size_t wanted = bufferSize;
            if (limit > 0 && limit - written < wanted) {
                wanted = (size_t)(limit - written);
            }
            int ret = [self readFromConnection:conn buffer:buffer length:wanted];
            if (ret == 0) {
                break;
            }
            if (ret < 0) {
                ok = NO;
                if (error != NULL && !self.cancelled) {
                    NSString *description = ret == MBEDTLS_ERR_SSL_TIMEOUT ? @"Connection timed out" : [self tlsErrorString:ret];
                    *error = [self errorWithCode:ret description:description];
                }
                break;
            }
            if (!YZTLSWriteData(file, [NSData dataWithBytesNoCopy:buffer length:(NSUInteger)ret freeWhenDone:NO])) {
                ok = NO;
                if (error != NULL) {
                    *error = [self errorWithCode:-12 description:@"Could not write to disk"];
                }
                break;
            }
            written += (unsigned long long)ret;
            if (progress != nil) {
                progress(written);
            }
        }
    }
    if (writtenOut != NULL) {
        *writtenOut = written;
    }
    return ok && !self.cancelled;
}

- (int)connectToHost:(NSString *)host port:(int)port socketHandler:(void (^)(int fd, unsigned long long serial))socketHandler error:(NSError **)error {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char portString[16];
    snprintf(portString, sizeof(portString), "%d", port);
    struct addrinfo *ai = NULL;
    int rc = getaddrinfo([host UTF8String], portString, &hints, &ai);
    if (rc != 0) {
        if (error != NULL) {
            *error = [self errorWithCode:rc description:[NSString stringWithFormat:@"DNS failed for %@:%d", host, port]];
        }
        return -1;
    }

    int fd = -1;
    int lastError = 0;
    for (struct addrinfo *p = ai; p != NULL && !self.cancelled; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) {
            lastError = errno;
            continue;
        }
        unsigned long long serial = [self registerSocket:fd];
        if (socketHandler != nil) {
            socketHandler(fd, serial);
        }
        int one = 1;
        int receiveBuffer = [VeterisMemoryProfile activeValues].receiveBufferSize;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, sizeof(receiveBuffer));
        struct timeval tv;
        tv.tv_sec = kYZArchiveTLSIOTimeoutSeconds;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        if ([self connectSocket:fd address:p->ai_addr length:p->ai_addrlen]) {
#ifdef VETERIS_DOWNLOAD_DEBUG
            socklen_t len = sizeof(receiveBuffer);
            if (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, &len) == 0) {
                YZTLSLog(@"socket connected host=%@ port=%d receiveBuffer=%d", host, port, receiveBuffer);
            }
#endif
            break;
        }
        lastError = errno;
        [self closeSocket:fd];
        fd = -1;
    }
    freeaddrinfo(ai);

    if (fd < 0 && error != NULL) {
        NSString *description = self.cancelled ? @"Cancelled" : [NSString stringWithFormat:@"Connect failed for %@:%d", host, port];
        *error = [self errorWithCode:lastError description:description];
    }
    return fd;
}

- (BOOL)connectSocket:(int)fd address:(const struct sockaddr *)address length:(socklen_t)length {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        return connect(fd, address, length) == 0;
    }
    BOOL connected = NO;
    if (connect(fd, address, length) == 0) {
        connected = YES;
    } else if (errno == EINPROGRESS || errno == EINTR) {
        int waitedSeconds = 0;
        while (!self.cancelled && waitedSeconds < kYZArchiveTLSConnectTimeoutSeconds) {
            fd_set writeSet;
            FD_ZERO(&writeSet);
            FD_SET(fd, &writeSet);
            struct timeval tv;
            tv.tv_sec = 1;
            tv.tv_usec = 0;
            int selected = select(fd + 1, NULL, &writeSet, NULL, &tv);
            if (selected > 0) {
                int socketError = 0;
                socklen_t errorLength = sizeof(socketError);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 && socketError == 0) {
                    connected = YES;
                } else {
                    errno = socketError != 0 ? socketError : ECONNREFUSED;
                }
                break;
            }
            if (selected < 0 && errno != EINTR) {
                break;
            }
            if (selected == 0) {
                waitedSeconds++;
            }
        }
        if (!connected && waitedSeconds >= kYZArchiveTLSConnectTimeoutSeconds) {
            errno = ETIMEDOUT;
        }
    }
    fcntl(fd, F_SETFL, flags);
    return connected && !self.cancelled;
}

- (unsigned long long)registerSocket:(int)fd {
    [_socketLock lock];
    unsigned long long serial = ++_socketSerial;
    [_activeSockets setObject:[NSNumber numberWithUnsignedLongLong:serial] forKey:[NSNumber numberWithInt:fd]];
    if (self.cancelled) {
        shutdown(fd, SHUT_RDWR);
    }
    [_socketLock unlock];
    return serial;
}

- (void)shutdownSocket:(int)fd serial:(unsigned long long)serial {
    [_socketLock lock];
    if ([[_activeSockets objectForKey:[NSNumber numberWithInt:fd]] unsignedLongLongValue] == serial) {
        shutdown(fd, SHUT_RDWR);
    }
    [_socketLock unlock];
}

- (void)closeSocket:(int)fd {
    [_socketLock lock];
    [_activeSockets removeObjectForKey:[NSNumber numberWithInt:fd]];
    close(fd);
    [_socketLock unlock];
}

- (void)abortActiveSockets {
    [_socketLock lock];
    for (NSNumber *fd in [_activeSockets allKeys]) {
        shutdown([fd intValue], SHUT_RDWR);
    }
    [_socketLock unlock];
}

- (BOOL)setupTLS:(mbedtls_ssl_context *)ssl
          config:(mbedtls_ssl_config *)config
         entropy:(mbedtls_entropy_context *)entropy
             ctr:(mbedtls_ctr_drbg_context *)ctr
             bio:(YZTLSBio *)bio
            host:(NSString *)host
            port:(int)port
           error:(NSError **)error {
    mbedtls_entropy_init(entropy);
    mbedtls_ctr_drbg_init(ctr);
    mbedtls_ssl_config_init(config);
    mbedtls_ssl_init(ssl);

    const char *pers = "VeterisArchiveTLS";
    int ret = mbedtls_ctr_drbg_seed(ctr, mbedtls_entropy_func, entropy, (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        if (error != NULL) {
            *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
        }
        return NO;
    }
    ret = mbedtls_ssl_config_defaults(config, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        if (error != NULL) {
            *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
        }
        return NO;
    }
    mbedtls_ssl_conf_authmode(config, MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_rng(config, mbedtls_ctr_drbg_random, ctr);
    mbedtls_ssl_conf_ciphersuites(config, kYZArchiveTLSCipherSuites);
    ret = mbedtls_ssl_setup(ssl, config);
    if (ret != 0) {
        if (error != NULL) {
            *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
        }
        return NO;
    }
    mbedtls_ssl_set_hostname(ssl, [host UTF8String]);
    mbedtls_ssl_set_bio(ssl, bio, YZTLSBioSend, YZTLSBioRecv, NULL);
    NSString *sessionKey = YZTLSSessionKey(host, port);
    BOOL offeredSession = YZTLSApplyCachedSession(ssl, sessionKey);
    unsigned long long handshakeStartedAt = (unsigned long long)([NSDate timeIntervalSinceReferenceDate] * 1000.0);

    while (!self.cancelled && (ret = mbedtls_ssl_handshake(ssl)) != 0) {
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        if (error != NULL) {
            *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
        }
        return NO;
    }
    if (self.cancelled) {
        return NO;
    }
    YZTLSStoreSession(ssl, sessionKey);
    YZTLSLog(@"tls handshake host=%@ version=%s cipher=%s sessionOffered=%d ms=%llu",
             host,
             mbedtls_ssl_get_version(ssl),
             mbedtls_ssl_get_ciphersuite(ssl),
             offeredSession,
             (unsigned long long)([NSDate timeIntervalSinceReferenceDate] * 1000.0) - handshakeStartedAt);
    return YES;
}

- (BOOL)socketWrite:(int)fd data:(NSData *)data error:(NSError **)error {
    const unsigned char *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining > 0 && !self.cancelled) {
        ssize_t wrote = send(fd, bytes, remaining, 0);
        if (wrote < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (error != NULL) {
                *error = [self errorWithCode:errno description:@"Socket write failed"];
            }
            return NO;
        }
        bytes += wrote;
        remaining -= (NSUInteger)wrote;
    }
    return remaining == 0;
}

- (BOOL)tlsWrite:(mbedtls_ssl_context *)ssl data:(NSData *)data error:(NSError **)error {
    const unsigned char *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining > 0 && !self.cancelled) {
        int wrote = mbedtls_ssl_write(ssl, bytes, remaining);
        if (wrote > 0) {
            bytes += wrote;
            remaining -= (NSUInteger)wrote;
            continue;
        }
        if (wrote == MBEDTLS_ERR_SSL_WANT_READ || wrote == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        if (error != NULL) {
            *error = [self errorWithCode:wrote description:[self tlsErrorString:wrote]];
        }
        return NO;
    }
    return remaining == 0;
}

- (BOOL)readHeaderFromConnection:(YZTLSConnection *)conn headerData:(NSMutableData *)headerData error:(NSError **)error {
    unsigned char byte = 0;
    while (!self.cancelled) {
        int ret = [self readFromConnection:conn buffer:&byte length:1];
        if (ret == 1) {
            [headerData appendBytes:&byte length:1];
            NSUInteger length = [headerData length];
            if (length >= 4) {
                const unsigned char *b = [headerData bytes];
                if (b[length - 4] == '\r' && b[length - 3] == '\n' && b[length - 2] == '\r' && b[length - 1] == '\n') {
                    return YES;
                }
            }
            if (length > 65536) {
                if (error != NULL) {
                    *error = [self errorWithCode:-3 description:@"HTTP header too large"];
                }
                return NO;
            }
            continue;
        }
        if (error != NULL) {
            NSString *description = ret == MBEDTLS_ERR_SSL_TIMEOUT ? @"Connection timed out" : @"Connection closed before headers";
            *error = [self errorWithCode:ret description:description];
        }
        return NO;
    }
    return NO;
}

#pragma mark - Header helpers

- (NSUInteger)parseHeaderData:(NSData *)data headers:(NSDictionary **)headers {
    NSString *headerString = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [headerString componentsSeparatedByString:@"\r\n"];
    NSUInteger status = 0;
    NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
    if ([lines count] > 0) {
        NSArray *parts = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
        if ([parts count] > 1 && [[parts objectAtIndex:0] hasPrefix:@"HTTP/"]) {
            status = (NSUInteger)MAX(0, [[parts objectAtIndex:1] intValue]);
        }
    }
    for (NSUInteger i = 1; i < [lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [line substringToIndex:colon.location];
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([key length] > 0 && value != nil) {
            [parsed setObject:value forKey:key];
        }
    }
    if (headers != NULL) {
        *headers = parsed;
    }
    return status;
}

- (NSString *)headerValue:(NSString *)name inHeaders:(NSDictionary *)headers {
    for (NSString *key in headers) {
        if ([key caseInsensitiveCompare:name] == NSOrderedSame) {
            return [headers objectForKey:key];
        }
    }
    return nil;
}

- (unsigned long long)totalBytesFromHeaders:(NSDictionary *)headers statusCode:(NSUInteger)statusCode base:(unsigned long long)base {
    NSString *range = [self headerValue:@"Content-Range" inHeaders:headers];
    if ([range length] > 0) {
        NSRange slash = [range rangeOfString:@"/"];
        if (slash.location != NSNotFound && slash.location + 1 < [range length]) {
            unsigned long long total = strtoull([[range substringFromIndex:slash.location + 1] UTF8String], NULL, 10);
            if (total > 0) {
                return total;
            }
        }
    }
    NSString *length = [self headerValue:@"Content-Length" inHeaders:headers];
    unsigned long long contentLength = [length length] > 0 ? strtoull([length UTF8String], NULL, 10) : 0;
    if (statusCode == 206) {
        return contentLength > 0 ? base + contentLength : 0;
    }
    return contentLength;
}

- (unsigned long long)startFromContentRange:(NSDictionary *)headers {
    NSString *range = [self headerValue:@"Content-Range" inHeaders:headers];
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

- (unsigned long long)totalFromUnsatisfiedRange:(NSDictionary *)headers {
    NSString *range = [self headerValue:@"Content-Range" inHeaders:headers];
    NSRange slash = [range rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location + 1 >= [range length]) {
        return 0;
    }
    return strtoull([[range substringFromIndex:slash.location + 1] UTF8String], NULL, 10);
}

- (void)reportProgress:(unsigned long long)current total:(unsigned long long)total {
    void (^progressBlock)(unsigned long long, unsigned long long) = self.progressBlock;
    if (progressBlock == nil || self.cancelled) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.cancelled) {
            progressBlock(current, total);
        }
    });
}

- (NSString *)requestPathForURLString:(NSString *)urlString {
    NSRange scheme = [urlString rangeOfString:@"://"];
    if (scheme.location == NSNotFound) {
        return @"/";
    }
    NSUInteger authorityStart = NSMaxRange(scheme);
    NSRange slash = [[urlString substringFromIndex:authorityStart] rangeOfString:@"/"];
    if (slash.location == NSNotFound) {
        return @"/";
    }
    return [urlString substringFromIndex:authorityStart + slash.location];
}

- (NSString *)absoluteURLFromLocation:(NSString *)location baseURL:(NSString *)baseURL {
    NSURL *absolute = [NSURL URLWithString:location];
    if (absolute != nil && [absolute scheme] != nil) {
        return location;
    }
    NSURL *base = [NSURL URLWithString:baseURL];
    return [[NSURL URLWithString:location relativeToURL:base] absoluteString];
}

- (BOOL)isRedirectStatus:(NSUInteger)statusCode {
    return statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:YZArchiveTLSErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:(description ?: @"Download failed") forKey:NSLocalizedDescriptionKey]];
}

- (NSString *)tlsErrorString:(int)ret {
    char buffer[160];
    mbedtls_strerror(ret, buffer, sizeof(buffer));
    return [NSString stringWithUTF8String:buffer];
}

@end

static int YZTLSBioSend(void *ctx, const unsigned char *buf, size_t len) {
    int fd = ((YZTLSBio *)ctx)->fd;
    ssize_t wrote = send(fd, buf, len, 0);
    if (wrote < 0) {
        if (errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_TIMEOUT;
        }
        return MBEDTLS_ERR_NET_SEND_FAILED;
    }
    return (int)wrote;
}

static int YZTLSBioRecv(void *ctx, unsigned char *buf, size_t len) {
    int fd = ((YZTLSBio *)ctx)->fd;
    ssize_t readBytes = recv(fd, buf, len, 0);
    if (readBytes < 0) {
        if (errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_TIMEOUT;
        }
        return MBEDTLS_ERR_NET_RECV_FAILED;
    }
    if (readBytes == 0) {
        return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    }
    return (int)readBytes;
}
