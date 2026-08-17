#import "YZArchiveTLSDownloader.h"

#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netdb.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <unistd.h>
#import <string.h>

#import "mbedtls/ctr_drbg.h"
#import "mbedtls/entropy.h"
#import "mbedtls/error.h"
#import "mbedtls/ssl.h"
#import "mbedtls/ssl_ciphersuites.h"

#import "../VAPIHelper/VAPIHelper.h"

#ifndef SO_NOSIGPIPE
#define SO_NOSIGPIPE 0x1022
#endif
#ifndef MBEDTLS_ERR_NET_SEND_FAILED
#define MBEDTLS_ERR_NET_SEND_FAILED -0x0052
#endif
#ifndef MBEDTLS_ERR_NET_RECV_FAILED
#define MBEDTLS_ERR_NET_RECV_FAILED -0x004E
#endif

static const NSUInteger kYZArchiveTLSMaxRedirects = 8;
static const NSTimeInterval kYZArchiveTLSDebugSampleInterval = 10.0;
static const unsigned long long kYZArchiveTLSParallelMinimumBytes = 2ULL * 1024ULL * 1024ULL;
static const NSUInteger kYZArchiveTLSMergeChunkSize = 64 * 1024;
static const NSUInteger kYZArchiveTLSLowMemoryMergeChunkSize = 32 * 1024;

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

static int YZTLSBioSend(void *ctx, const unsigned char *buf, size_t len);
static int YZTLSBioRecv(void *ctx, unsigned char *buf, size_t len);

static unsigned long long YZTLSNowUsec(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((unsigned long long)tv.tv_sec * 1000000ULL) + (unsigned long long)tv.tv_usec;
}

static NSUInteger YZTLSMergeChunkSize(void) {
    return [VAPIHelper usesLowMemoryDownloadMode] ? kYZArchiveTLSLowMemoryMergeChunkSize : kYZArchiveTLSMergeChunkSize;
}

@implementation YZArchiveTLSResult
@end

@interface YZArchiveTLSDownloader ()
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *targetPath;
@property (nonatomic, assign) unsigned long long resumeOffset;
@property (nonatomic, retain) NSDictionary *requestHeaders;
@property (nonatomic, copy) void (^progressBlock)(unsigned long long current, unsigned long long total);
@property (nonatomic, copy) void (^completionBlock)(YZArchiveTLSResult *result);
@property (nonatomic, assign) BOOL cancelled;
@end

@implementation YZArchiveTLSDownloader

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
        });
    });
}

- (void)cancel {
    self.cancelled = YES;
}

- (YZArchiveTLSResult *)run {
    YZArchiveTLSResult *result = [[YZArchiveTLSResult alloc] init];
    result.finalURL = self.url;
    NSString *currentURL = self.url;

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
            return result;
        }
        if (![self isRedirectStatus:statusCode]) {
            return result;
        }
        if ([location length] == 0 || redirect == kYZArchiveTLSMaxRedirects) {
            result.error = [NSError errorWithDomain:@"YZArchiveTLSDownloader" code:statusCode userInfo:[NSDictionary dictionaryWithObject:@"Redirect without usable Location" forKey:NSLocalizedDescriptionKey]];
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

- (BOOL)fetchURL:(NSString *)urlString statusCode:(NSUInteger *)statusCode headers:(NSDictionary **)headers location:(NSString **)location error:(NSError **)error {
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

    int fd = [self connectToHost:host port:port error:error];
    if (fd < 0) {
        return NO;
    }

    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr;
    mbedtls_ssl_config config;
    mbedtls_ssl_context ssl;
    YZTLSBio bio;
    memset(&entropy, 0, sizeof(entropy));
    memset(&ctr, 0, sizeof(ctr));
    memset(&config, 0, sizeof(config));
    memset(&ssl, 0, sizeof(ssl));
    memset(&bio, 0, sizeof(bio));
    bio.fd = fd;

    if (useTLS && ![self setupTLS:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio host:host error:error]) {
        close(fd);
        return NO;
    }

    NSString *path = [self requestPathForURLString:urlString];
    NSMutableString *request = [NSMutableString stringWithFormat:@"GET %@ HTTP/1.0\r\nHost: %@\r\nUser-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 6_1 like Mac OS X) Veteris/2.1\r\nAccept: */*\r\nConnection: close\r\n", path, host];
    for (NSString *key in self.requestHeaders) {
        NSString *value = [self.requestHeaders objectForKey:key];
        if ([key length] > 0 && [value length] > 0 && [key rangeOfString:@"\r"].location == NSNotFound && [key rangeOfString:@"\n"].location == NSNotFound) {
            [request appendFormat:@"%@: %@\r\n", key, value];
        }
    }
    if (self.resumeOffset > 0) {
        [request appendFormat:@"Range: bytes=%llu-\r\n", self.resumeOffset];
    }
    [request appendString:@"\r\n"];

    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wroteRequest = useTLS ? [self tlsWrite:&ssl data:requestData error:error] : [self socketWrite:fd data:requestData error:error];
    if (!wroteRequest) {
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    NSMutableData *headerData = [NSMutableData data];
    NSMutableData *bodyPrefix = [NSMutableData data];
    BOOL readHeader = [self readHeaderFromFD:fd ssl:(useTLS ? &ssl : NULL) headerData:headerData bodyPrefix:bodyPrefix error:error];
    if (!readHeader) {
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    NSDictionary *parsedHeaders = nil;
    NSUInteger parsedStatus = [self parseHeaderData:headerData headers:&parsedHeaders];
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

    BOOL shouldWrite = (parsedStatus >= 200 && parsedStatus < 300);
    if (!shouldWrite) {
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return YES;
    }

    BOOL append = (self.resumeOffset > 0 && parsedStatus == 206);
    unsigned long long base = append ? self.resumeOffset : 0;
    unsigned long long total = [self totalBytesFromHeaders:parsedHeaders statusCode:parsedStatus base:base];
    NSUInteger parallelSegments = [VAPIHelper archiveDownloadParallelSegments];
    if (parallelSegments >= 2 &&
        total > base &&
        total - base >= kYZArchiveTLSParallelMinimumBytes &&
        (parsedStatus == 200 || parsedStatus == 206)) {
        YZTLSLog(@"tls parallel start url=%@ base=%llu total=%llu segments=%lu",
                 urlString,
                 base,
                 total,
                 (unsigned long)parallelSegments);
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return [self downloadURLInParallel:urlString base:base total:total error:error];
    }

    NSFileHandle *file = nil;
    if (append) {
        file = [NSFileHandle fileHandleForWritingAtPath:self.targetPath];
        [file seekToEndOfFile];
    } else {
        [[NSFileManager defaultManager] createFileAtPath:self.targetPath contents:nil attributes:nil];
        file = [NSFileHandle fileHandleForWritingAtPath:self.targetPath];
    }
    if (file == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open target file"];
        }
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    unsigned long long written = 0;
    unsigned long long sampleBytes = 0;
    unsigned long long sampleReads = 0;
    unsigned long long sampleReadUsec = 0;
    unsigned long long sampleWriteUsec = 0;
    NSUInteger bufferSize = [VAPIHelper archiveDownloadBufferSize];
    NSTimeInterval sampleStartedAt = [NSDate timeIntervalSinceReferenceDate];
    if ([bodyPrefix length] > 0) {
        unsigned long long writeStarted = YZTLSNowUsec();
        [file writeData:bodyPrefix];
        sampleWriteUsec += YZTLSNowUsec() - writeStarted;
        written += [bodyPrefix length];
        sampleBytes += [bodyPrefix length];
        [self reportProgress:base + written total:total];
    }

    NSMutableData *readBuffer = [NSMutableData dataWithLength:bufferSize];
    unsigned char *buffer = (unsigned char *)[readBuffer mutableBytes];
    while (!self.cancelled) {
        @autoreleasepool {
            unsigned long long readStarted = YZTLSNowUsec();
            int ret = useTLS ? mbedtls_ssl_read(&ssl, buffer, bufferSize) : (int)recv(fd, buffer, bufferSize, 0);
            sampleReadUsec += YZTLSNowUsec() - readStarted;
            if (ret > 0) {
                unsigned long long writeStarted = YZTLSNowUsec();
                [file writeData:[NSData dataWithBytes:buffer length:(NSUInteger)ret]];
                sampleWriteUsec += YZTLSNowUsec() - writeStarted;
                written += (unsigned long long)ret;
                sampleBytes += (unsigned long long)ret;
                sampleReads++;
                [self reportProgress:base + written total:total];
                NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                NSTimeInterval sampleElapsed = now - sampleStartedAt;
                if (sampleElapsed >= kYZArchiveTLSDebugSampleInterval) {
                    unsigned long long bps = (unsigned long long)((double)sampleBytes / MAX(0.001, sampleElapsed));
                    unsigned long long avgChunk = sampleReads > 0 ? sampleBytes / sampleReads : 0;
                    YZTLSLog(@"tls io url=%@ bytes=%llu totalWritten=%llu total=%llu bps=%llu reads=%llu avgChunk=%llu readMs=%.1f writeMs=%.1f",
                             urlString,
                             sampleBytes,
                             base + written,
                             total,
                             bps,
                             sampleReads,
                             avgChunk,
                             (double)sampleReadUsec / 1000.0,
                             (double)sampleWriteUsec / 1000.0);
                    sampleBytes = 0;
                    sampleReads = 0;
                    sampleReadUsec = 0;
                    sampleWriteUsec = 0;
                    sampleStartedAt = now;
                }
                continue;
            }
            if (useTLS && (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)) {
                continue;
            }
            if (ret == 0 || (useTLS && ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY)) {
                break;
            }
            if (error != NULL) {
                *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
            }
        }
        [file closeFile];
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    [file closeFile];
    [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
    close(fd);
    return !self.cancelled;
}

- (BOOL)downloadURLInParallel:(NSString *)urlString base:(unsigned long long)base total:(unsigned long long)total error:(NSError **)error {
    if (base > 0) {
        [self mergeExistingParallelPartsForTotal:total error:error];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.targetPath error:NULL];
        if (attrs != nil) {
            base = [attrs fileSize];
            if (base >= total) {
                [self reportProgress:total total:total];
                YZTLSLog(@"tls parallel recovered complete target=%@ total=%llu", self.targetPath, total);
                return YES;
            }
        }
    }

    unsigned long long remaining = total - base;
    NSUInteger maxSegments = [VAPIHelper archiveDownloadParallelSegments];
    NSUInteger segmentCount = (NSUInteger)MIN((unsigned long long)maxSegments, remaining);
    if (segmentCount < 2) {
        return [self fetchURLRange:urlString
                              start:base
                                end:total - 1
                         targetPath:self.targetPath
                             append:YES
                           progress:^(unsigned long long current) {
            [self reportProgress:base + current total:total];
        }
                              error:error];
    }

    if (base == 0) {
        [[NSFileManager defaultManager] createFileAtPath:self.targetPath contents:nil attributes:nil];
    }

    NSMutableArray *partPaths = [NSMutableArray arrayWithCapacity:segmentCount];
    unsigned long long *segmentProgress = calloc(segmentCount, sizeof(unsigned long long));
    if (segmentProgress == NULL) {
        if (error != NULL) {
            *error = [self errorWithCode:-4 description:@"Could not allocate segment progress"];
        }
        return NO;
    }

    NSLock *lock = [[NSLock alloc] init];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block BOOL failed = NO;
    __block NSError *firstError = nil;
    __block NSTimeInterval lastProgressReport = 0;
    NSTimeInterval progressInterval = [VAPIHelper downloadProgressInterval];

    unsigned long long segmentSize = (remaining + segmentCount - 1) / segmentCount;
    for (NSUInteger idx = 0; idx < segmentCount; idx++) {
        unsigned long long start = base + ((unsigned long long)idx * segmentSize);
        unsigned long long end = MIN(total - 1, start + segmentSize - 1);
        BOOL writesContiguousPrefix = (idx == 0);
        NSString *partPath = writesContiguousPrefix ? self.targetPath : [NSString stringWithFormat:@"%@.part.%lu", self.targetPath, (unsigned long)idx];
        if (!writesContiguousPrefix) {
            [[NSFileManager defaultManager] removeItemAtPath:partPath error:nil];
        }
        [partPaths addObject:writesContiguousPrefix ? [NSNull null] : partPath];

        dispatch_group_async(group, queue, ^{
            NSError *segmentError = nil;
            BOOL ok = [self fetchURLRange:urlString
                                    start:start
                                      end:end
                               targetPath:partPath
                                   append:writesContiguousPrefix
                                 progress:^(unsigned long long current) {
                [lock lock];
                segmentProgress[idx] = current;
                unsigned long long aggregate = 0;
                for (NSUInteger progressIdx = 0; progressIdx < segmentCount; progressIdx++) {
                    aggregate += segmentProgress[progressIdx];
                }
                NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                BOOL shouldReport = (now - lastProgressReport) >= progressInterval || base + aggregate >= total;
                if (shouldReport) {
                    lastProgressReport = now;
                }
                [lock unlock];
                if (shouldReport) {
                    [self reportProgress:base + aggregate total:total];
                }
            }
                                    error:&segmentError];
            if (!ok) {
                [lock lock];
                failed = YES;
                if (firstError == nil) {
                    firstError = segmentError;
                }
                [lock unlock];
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    free(segmentProgress);

    if (self.cancelled) {
        if (!self.preservePartialOnCancel) {
            for (id partPath in partPaths) {
                if ([partPath isKindOfClass:[NSString class]]) {
                    [[NSFileManager defaultManager] removeItemAtPath:partPath error:nil];
                }
            }
        }
        return NO;
    }
    if (failed) {
        for (id partPath in partPaths) {
            if ([partPath isKindOfClass:[NSString class]]) {
                [[NSFileManager defaultManager] removeItemAtPath:partPath error:nil];
            }
        }
        if (error != NULL) {
            *error = firstError ?: [self errorWithCode:-5 description:@"Parallel range download failed"];
        }
        return NO;
    }

    if (![self mergeParallelPartPaths:partPaths total:total error:error]) {
        return NO;
    }
    [self reportProgress:total total:total];
    YZTLSLog(@"tls parallel complete url=%@ base=%llu total=%llu segments=%lu",
             urlString,
             base,
             total,
             (unsigned long)segmentCount);
    return !self.cancelled;
}

- (BOOL)mergeExistingParallelPartsForTotal:(unsigned long long)total error:(NSError **)error {
    NSArray *partPaths = [self existingParallelPartPaths];
    if ([partPaths count] == 0) {
        return NO;
    }
    return [self mergeParallelPartPaths:partPaths total:total error:error];
}

- (NSArray *)existingParallelPartPaths {
    NSString *directory = [self.targetPath stringByDeletingLastPathComponent];
    NSString *name = [self.targetPath lastPathComponent];
    NSString *prefix = [name stringByAppendingString:@".part."];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *entry in contents) {
        if (![entry hasPrefix:prefix]) {
            continue;
        }
        NSString *suffix = [entry substringFromIndex:[prefix length]];
        if ([suffix length] == 0 || [suffix rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
            continue;
        }
        [paths addObject:[directory stringByAppendingPathComponent:entry]];
    }
    [paths sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        NSInteger leftIndex = [[[left lastPathComponent] substringFromIndex:[prefix length]] integerValue];
        NSInteger rightIndex = [[[right lastPathComponent] substringFromIndex:[prefix length]] integerValue];
        if (leftIndex < rightIndex) {
            return NSOrderedAscending;
        }
        if (leftIndex > rightIndex) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return paths;
}

- (BOOL)mergeParallelPartPaths:(NSArray *)partPaths total:(unsigned long long)total error:(NSError **)error {
    NSFileHandle *target = [NSFileHandle fileHandleForWritingAtPath:self.targetPath];
    if (target == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open target file"];
        }
        return NO;
    }
    unsigned long long targetSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.targetPath error:NULL] fileSize];
    unsigned long long partBytes = 0;
    for (id partPath in partPaths) {
        if ([partPath isKindOfClass:[NSString class]]) {
            partBytes += [[[NSFileManager defaultManager] attributesOfItemAtPath:partPath error:NULL] fileSize];
        }
    }
    unsigned long long duplicateBytes = (targetSize + partBytes > total) ? (targetSize + partBytes - total) : 0;

    [target seekToEndOfFile];
    NSUInteger mergeChunkSize = YZTLSMergeChunkSize();
    for (id partPath in partPaths) {
        if (![partPath isKindOfClass:[NSString class]]) {
            continue;
        }
        NSFileHandle *part = [NSFileHandle fileHandleForReadingAtPath:partPath];
        if (part == nil) {
            [target closeFile];
            if (error != NULL) {
                *error = [self errorWithCode:-6 description:@"Could not open downloaded segment"];
            }
            return NO;
        }
        unsigned long long partSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:partPath error:NULL] fileSize];
        unsigned long long skipBytes = MIN(duplicateBytes, partSize);
        duplicateBytes -= skipBytes;
        if (skipBytes > 0) {
            [part seekToFileOffset:skipBytes];
        }
        BOOL reachedEnd = NO;
        while (!self.cancelled) {
            @autoreleasepool {
                NSData *chunk = [part readDataOfLength:mergeChunkSize];
                if ([chunk length] == 0) {
                    reachedEnd = YES;
                    break;
                }
                [target writeData:chunk];
            }
        }
        [part closeFile];
        if (!reachedEnd) {
            [target closeFile];
            return NO;
        }
        [[NSFileManager defaultManager] removeItemAtPath:partPath error:nil];
    }
    [target closeFile];
    return !self.cancelled;
}

- (BOOL)fetchURLRange:(NSString *)urlString
                start:(unsigned long long)start
                  end:(unsigned long long)end
           targetPath:(NSString *)targetPath
                append:(BOOL)append
             progress:(void (^)(unsigned long long current))progress
                error:(NSError **)error {
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

    int fd = [self connectToHost:host port:port error:error];
    if (fd < 0) {
        return NO;
    }

    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr;
    mbedtls_ssl_config config;
    mbedtls_ssl_context ssl;
    YZTLSBio bio;
    memset(&entropy, 0, sizeof(entropy));
    memset(&ctr, 0, sizeof(ctr));
    memset(&config, 0, sizeof(config));
    memset(&ssl, 0, sizeof(ssl));
    memset(&bio, 0, sizeof(bio));
    bio.fd = fd;

    if (useTLS && ![self setupTLS:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio host:host error:error]) {
        close(fd);
        return NO;
    }

    NSString *path = [self requestPathForURLString:urlString];
    NSMutableString *request = [NSMutableString stringWithFormat:@"GET %@ HTTP/1.0\r\nHost: %@\r\nUser-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 6_1 like Mac OS X) Veteris/2.1\r\nAccept: */*\r\nConnection: close\r\n", path, host];
    for (NSString *key in self.requestHeaders) {
        NSString *value = [self.requestHeaders objectForKey:key];
        if ([key length] > 0 && [value length] > 0 && [key rangeOfString:@"\r"].location == NSNotFound && [key rangeOfString:@"\n"].location == NSNotFound && [key caseInsensitiveCompare:@"Range"] != NSOrderedSame) {
            [request appendFormat:@"%@: %@\r\n", key, value];
        }
    }
    [request appendFormat:@"Range: bytes=%llu-%llu\r\n\r\n", start, end];

    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wroteRequest = useTLS ? [self tlsWrite:&ssl data:requestData error:error] : [self socketWrite:fd data:requestData error:error];
    if (!wroteRequest) {
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    NSMutableData *headerData = [NSMutableData data];
    NSMutableData *bodyPrefix = [NSMutableData data];
    BOOL readHeader = [self readHeaderFromFD:fd ssl:(useTLS ? &ssl : NULL) headerData:headerData bodyPrefix:bodyPrefix error:error];
    if (!readHeader) {
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    NSDictionary *parsedHeaders = nil;
    NSUInteger parsedStatus = [self parseHeaderData:headerData headers:&parsedHeaders];
    if (parsedStatus != 206) {
        if (error != NULL) {
            *error = [self errorWithCode:parsedStatus description:[NSString stringWithFormat:@"Range request returned HTTP %lu", (unsigned long)parsedStatus]];
        }
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    if (append) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
            [[NSFileManager defaultManager] createFileAtPath:targetPath contents:nil attributes:nil];
        }
    } else {
        [[NSFileManager defaultManager] createFileAtPath:targetPath contents:nil attributes:nil];
    }
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:targetPath];
    if (file == nil) {
        if (error != NULL) {
            *error = [self errorWithCode:-2 description:@"Could not open segment file"];
        }
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    unsigned long long expected = end - start + 1;
    unsigned long long written = 0;
    NSUInteger bufferSize = [VAPIHelper archiveDownloadBufferSize];
    if (append) {
        [file seekToEndOfFile];
    }
    if ([bodyPrefix length] > 0) {
        [file writeData:bodyPrefix];
        written += [bodyPrefix length];
        if (progress != nil) {
            progress(written);
        }
    }

    NSMutableData *readBuffer = [NSMutableData dataWithLength:bufferSize];
    unsigned char *buffer = (unsigned char *)[readBuffer mutableBytes];
    while (!self.cancelled) {
        @autoreleasepool {
            int ret = useTLS ? mbedtls_ssl_read(&ssl, buffer, bufferSize) : (int)recv(fd, buffer, bufferSize, 0);
            if (ret > 0) {
                [file writeData:[NSData dataWithBytes:buffer length:(NSUInteger)ret]];
                written += (unsigned long long)ret;
                if (progress != nil) {
                    progress(written);
                }
                continue;
            }
            if (useTLS && (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)) {
                continue;
            }
            if (ret == 0 || (useTLS && ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY)) {
                break;
            }
            if (error != NULL) {
                *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
            }
        }
        [file closeFile];
        [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
        close(fd);
        return NO;
    }

    [file closeFile];
    [self teardownTLS:useTLS ssl:&ssl config:&config entropy:&entropy ctr:&ctr bio:&bio];
    close(fd);

    if (!self.cancelled && written != expected) {
        if (error != NULL) {
            *error = [self errorWithCode:-7 description:[NSString stringWithFormat:@"Segment size mismatch got %llu expected %llu", written, expected]];
        }
        return NO;
    }
    YZTLSLog(@"tls parallel segment start=%llu end=%llu bytes=%llu", start, end, written);
    return !self.cancelled;
}

- (int)connectToHost:(NSString *)host port:(int)port error:(NSError **)error {
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
    for (struct addrinfo *p = ai; p != NULL; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) {
            continue;
        }
        int one = 1;
        int receiveBuffer = [VAPIHelper archiveDownloadReceiveBufferSize];
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, sizeof(receiveBuffer));
        struct timeval tv;
        tv.tv_sec = 45;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        if (connect(fd, p->ai_addr, p->ai_addrlen) == 0) {
#ifdef VETERIS_DOWNLOAD_DEBUG
            socklen_t len = sizeof(receiveBuffer);
            if (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, &len) == 0) {
                YZTLSLog(@"socket connected host=%@ port=%d receiveBuffer=%d", host, port, receiveBuffer);
            }
#endif
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(ai);

    if (fd < 0 && error != NULL) {
        *error = [self errorWithCode:errno description:[NSString stringWithFormat:@"Connect failed for %@:%d", host, port]];
    }
    return fd;
}

- (BOOL)setupTLS:(mbedtls_ssl_context *)ssl
          config:(mbedtls_ssl_config *)config
         entropy:(mbedtls_entropy_context *)entropy
             ctr:(mbedtls_ctr_drbg_context *)ctr
             bio:(YZTLSBio *)bio
            host:(NSString *)host
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

    while (!self.cancelled && (ret = mbedtls_ssl_handshake(ssl)) != 0) {
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        if (error != NULL) {
            *error = [self errorWithCode:ret description:[self tlsErrorString:ret]];
        }
        return NO;
    }
    YZTLSLog(@"tls handshake host=%@ version=%s cipher=%s",
             host,
             mbedtls_ssl_get_version(ssl),
             mbedtls_ssl_get_ciphersuite(ssl));
    return !self.cancelled;
}

- (void)teardownTLS:(BOOL)useTLS
                ssl:(mbedtls_ssl_context *)ssl
             config:(mbedtls_ssl_config *)config
            entropy:(mbedtls_entropy_context *)entropy
                ctr:(mbedtls_ctr_drbg_context *)ctr
                bio:(YZTLSBio *)bio {
    if (!useTLS) {
        return;
    }
    mbedtls_ssl_close_notify(ssl);
    mbedtls_ssl_free(ssl);
    mbedtls_ssl_config_free(config);
    mbedtls_ctr_drbg_free(ctr);
    mbedtls_entropy_free(entropy);
}

- (BOOL)socketWrite:(int)fd data:(NSData *)data error:(NSError **)error {
    const unsigned char *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining > 0) {
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
    return YES;
}

- (BOOL)tlsWrite:(mbedtls_ssl_context *)ssl data:(NSData *)data error:(NSError **)error {
    const unsigned char *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining > 0) {
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
    return YES;
}

- (BOOL)readHeaderFromFD:(int)fd ssl:(mbedtls_ssl_context *)ssl headerData:(NSMutableData *)headerData bodyPrefix:(NSMutableData *)bodyPrefix error:(NSError **)error {
    unsigned char byte = 0;
    while (!self.cancelled) {
        int ret = ssl != NULL ? mbedtls_ssl_read(ssl, &byte, 1) : (int)recv(fd, &byte, 1, 0);
        if (ret == 1) {
            [headerData appendBytes:&byte length:1];
            NSUInteger length = [headerData length];
            if (length >= 4) {
                const unsigned char *b = [headerData bytes];
                if (b[length - 4] == '\r' && b[length - 3] == '\n' && b[length - 2] == '\r' && b[length - 1] == '\n') {
                    return YES;
                }
            }
            if ([headerData length] > 65536) {
                if (error != NULL) {
                    *error = [self errorWithCode:-3 description:@"HTTP header too large"];
                }
                return NO;
            }
            continue;
        }
        if (ssl != NULL && (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE)) {
            continue;
        }
        if (error != NULL) {
            *error = [self errorWithCode:ret description:@"Connection closed before headers"];
        }
        return NO;
    }
    return NO;
}

- (NSUInteger)parseHeaderData:(NSData *)data headers:(NSDictionary **)headers {
    NSString *headerString = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    NSArray *lines = [headerString componentsSeparatedByString:@"\r\n"];
    NSUInteger status = 0;
    NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
    if ([lines count] > 0) {
        NSArray *parts = [[lines objectAtIndex:0] componentsSeparatedByString:@" "];
        if ([parts count] > 1) {
            status = (NSUInteger)[[parts objectAtIndex:1] intValue];
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
        return base + contentLength;
    }
    return contentLength;
}

- (void)reportProgress:(unsigned long long)current total:(unsigned long long)total {
    if (self.progressBlock == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressBlock != nil) {
            self.progressBlock(current, total);
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
    return [NSError errorWithDomain:@"YZArchiveTLSDownloader" code:code userInfo:[NSDictionary dictionaryWithObject:(description ?: @"Download failed") forKey:NSLocalizedDescriptionKey]];
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
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        return MBEDTLS_ERR_NET_SEND_FAILED;
    }
    return (int)wrote;
}

static int YZTLSBioRecv(void *ctx, unsigned char *buf, size_t len) {
    int fd = ((YZTLSBio *)ctx)->fd;
    ssize_t readBytes = recv(fd, buf, len, 0);
    if (readBytes < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        return MBEDTLS_ERR_NET_RECV_FAILED;
    }
    if (readBytes == 0) {
        return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    }
    return (int)readBytes;
}
