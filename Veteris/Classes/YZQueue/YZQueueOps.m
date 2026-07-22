#import "YZQueueOps.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../Clutch/MobileInstallation.h"
#import "../../BBHTTP/BBHTTP.h"
#import "../../BBHTTP/BBHTTPRequest+Convenience.h"
#import "../../BBHTTP/Handlers/BBHTTPFileWriter.h"
#import "../../AppDelegate.h"
#import "LSApplicationWorkspace.h"
#import "YZArchiveTLSDownloader.h"

static const NSUInteger kMaxDownloadAttempts = 6;
static const unsigned long long kMinimumResumeBytes = 4096;


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

static void YZFailDownload(YZQueueRep *parent, NSString *reason) {
    YZDownloadLog(@"failed before download: %@", reason);
    debugLog(@"Download failed before start: %@", reason);
    if (parent != nil) {
        parent.downloadTask = nil;
        parent.state = YZRepStateFailed;
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

    if ([host isEqualToString:@"archive.org"] && [[url path] hasPrefix:@"/download/"]) {
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
    NSRange items = [rawPath rangeOfString:@"/items/"];
    if (items.location == NSNotFound) {
        return clean;
    }
    NSString *afterItems = [rawPath substringFromIndex:NSMaxRange(items)];
    NSRange nextSlash = [afterItems rangeOfString:@"/"];
    if (nextSlash.location == NSNotFound) {
        return clean;
    }
    NSString *identifier = [afterItems substringToIndex:nextSlash.location];
    NSString *inItemPath = [afterItems substringFromIndex:NSMaxRange(nextSlash)];
    if ([identifier length] == 0 || [inItemPath length] == 0) {
        return clean;
    }
    return [NSString stringWithFormat:@"http://archive.org/download/%@/%@", identifier, inItemPath];
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
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    return attrs != nil ? [attrs fileSize] : 0;
}

static BOOL YZDownloadedFileMatchesExpectedTotal(NSString *path, unsigned long long expectedTotal) {
    return expectedTotal == 0 || YZFileSizeAtPath(path) >= expectedTotal;
}

static BOOL YZShouldPreservePartialAtPath(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    if (attrs == nil || [attrs fileSize] < kMinimumResumeBytes) {
        return NO;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return NO;
    }
    NSData *magic = [handle readDataOfLength:4];
    [handle closeFile];
    if ([magic length] < 4) {
        return NO;
    }
    const unsigned char *b = [magic bytes];
    return (b[0] == 'P' && b[1] == 'K' && b[2] == 0x03 && b[3] == 0x04);
}




@implementation YZQueueOps
#pragma mark - Main Methods
+ (BOOL)installIPA:(NSString *)filePath {
    if (![YZQueueOps doesPathExist:filePath]) {
        debugLog(@"File does not exist at path but skipping: %@", filePath);
        return false;
    }
    NSDictionary *options = YZInstallOptions();
    int ret = -1;
    if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {
        ret = MobileInstallationInstall((__bridge CFStringRef)filePath, (__bridge CFDictionaryRef)options, NULL, NULL);
        YZDownloadLog(@"mobile installation finished path=%@ ret=%d", filePath, ret);
    } else {
        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        NSError *error = nil;
        BOOL installed = [workspace installApplication:[NSURL fileURLWithPath:filePath] withOptions:options error:&error];
        if (error) {
            debugLog(@"Install error: %@", [error localizedDescription]);
            YZDownloadLog(@"workspace install failed path=%@ error=%@ userInfo=%@", filePath, error, [error userInfo]);
        } else if (!installed) {
            YZDownloadLog(@"workspace install returned NO path=%@", filePath);
        } else {
            ret = 0;
        }
    }
    BOOL success = (ret == 0);
    if (success) {
        [self removeFileAt:filePath];
    }
    return success;
}

+ (void)downloadFileToPath:(NSString *)urlString pathFromString:(NSString *)str parent:(YZQueueRep *)parent {
    if (!YZIsNonEmptyString(str)) {
        YZFailDownload(parent, @"missing target bundle identifier");
        return;
    }
    [self downloadFileToPath:urlString targetPath:downloadPathFor(str) parent:parent];
}

+ (void)downloadFileToPath:(NSString *)urlString targetPath:(NSString *)targetPath parent:(YZQueueRep *)parent {
    if (!YZIsNonEmptyString(urlString)) {
        YZFailDownload(parent, @"missing download URL");
        return;
    }
    if (!YZIsNonEmptyString(targetPath)) {
        YZFailDownload(parent, @"missing target path");
        return;
    }
    NSArray *candidates = YZDownloadCandidates(urlString);
    if ([candidates count] == 0) {
        YZFailDownload(parent, @"invalid download URL");
        return;
    }
    YZDownloadLog(@"candidates for %@: %@", targetPath, candidates);
    if (YZCanUseArchiveTLSDownloader(candidates)) {
        [self downloadFileWithArchiveTLS:urlString candidates:candidates targetPath:targetPath parent:parent attempt:0];
    } else {
        [self downloadFileViaBBHTTP:urlString candidates:candidates targetPath:targetPath parent:parent attempt:0];
    }
}

+ (void)downloadFileWithArchiveTLS:(NSString *)originalURL candidates:(NSArray *)candidates targetPath:(NSString *)filePath parent:(YZQueueRep *)parent attempt:(NSUInteger)attempt {
    NSString *urlString = [candidates objectAtIndex:(attempt % [candidates count])];
    YZDownloadLog(@"tls start %@ attempt %lu/%lu url=%@", filePath, (unsigned long)(attempt + 1), (unsigned long)kMaxDownloadAttempts, urlString);
    if (!YZShouldPreservePartialAtPath(filePath)) {
        [self removeFileAt:filePath];
    }
    unsigned long long resumeOffset = 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
    if (attrs != nil) {
        resumeOffset = [attrs fileSize];
    }
    YZDownloadLog(@"tls file=%@ resumeOffset=%llu", filePath, resumeOffset);

    NSMutableDictionary *reqHeaders = [[VAPIHelper getHeaders] mutableCopy];
    YZArchiveTLSDownloader *downloader = [[YZArchiveTLSDownloader alloc] initWithURL:urlString
                                                                          targetPath:filePath
                                                                        resumeOffset:resumeOffset
                                                                             headers:reqHeaders
                                                                            progress:^(unsigned long long current, unsigned long long total) {
        if (parent.downloadProgressBlock != nil) {
            parent.downloadProgressBlock((NSUInteger)current, (NSUInteger)total);
        }
    } completion:^(YZArchiveTLSResult *result) {
        parent.downloadTask = nil;
        NSUInteger httpStatus = result.statusCode;
        BOOL cancelled = result.cancelled || parent.state == YZRepStateCancelled || parent.state == YZRepStateFailed || parent.invalid;
        BOOL httpOK = httpStatus >= 200 && httpStatus < 300;
        unsigned long long expectedTotal = YZTotalBytesFromHeaders(result.headers, httpStatus, (httpStatus == 206 ? resumeOffset : 0));
        BOOL complete = YZDownloadedFileMatchesExpectedTotal(filePath, expectedTotal);
        BOOL validIPA = httpOK && complete && [YZQueueOps isValidIPAAtPath:filePath];

        if (cancelled) {
            YZDownloadLog(@"tls cancelled %@ url=%@", filePath, urlString);
            [self removeFileAt:filePath];
        } else if (httpStatus == 416 && [YZQueueOps isValidIPAAtPath:filePath]) {
            YZDownloadLog(@"tls success %@ existing file complete status=416", filePath);
            parent.state = YZRepStateDownloaded;
            parent.path = filePath;
        } else if (validIPA) {
            YZDownloadLog(@"tls success %@ status=%lu size=%llu expected=%llu finalURL=%@",
                          filePath,
                          (unsigned long)httpStatus,
                          YZFileSizeAtPath(filePath),
                          expectedTotal,
                          result.finalURL);
            parent.state = YZRepStateDownloaded;
            parent.path = filePath;
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
            if (httpOK || (httpStatus >= 400 && httpStatus < 500 && httpStatus != 429)) {
                [self removeFileAt:filePath];
            }
            NSUInteger nextAttempt = attempt + 1;
            if (nextAttempt < kMaxDownloadAttempts) {
                BOOL redirectStopped = (httpStatus >= 300 && httpStatus < 400);
                NSTimeInterval delay = redirectStopped ? 0.0 : MIN(8.0, 1.0 * (1 << MIN(nextAttempt, 3)));
                NSString *nextURL = [candidates objectAtIndex:(nextAttempt % [candidates count])];
                YZDownloadLog(@"tls retry %@ nextAttempt=%lu delay=%.1f nextURL=%@", filePath, (unsigned long)(nextAttempt + 1), delay, nextURL);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (parent.invalid || parent.state == YZRepStateCancelled) {
                        return;
                    }
                    [self downloadFileWithArchiveTLS:originalURL candidates:candidates targetPath:filePath parent:parent attempt:nextAttempt];
                });
            } else {
                YZDownloadLog(@"tls final failure %@ after %lu attempts; falling back to BBHTTP", filePath, (unsigned long)kMaxDownloadAttempts);
                [self downloadFileViaBBHTTP:originalURL candidates:candidates targetPath:filePath parent:parent attempt:0];
            }
        }
    }];
    parent.path = filePath;
    parent.request = nil;
    parent.downloadTask = downloader;
    [downloader start];
}

+ (void)downloadFileViaBBHTTP:(NSString *)originalURL candidates:(NSArray *)candidates targetPath:(NSString *)filePath parent:(YZQueueRep *)parent attempt:(NSUInteger)attempt {
    NSString *urlString = [candidates objectAtIndex:(attempt % [candidates count])];
    YZDownloadLog(@"start %@ attempt %lu/%lu url=%@", filePath, (unsigned long)(attempt + 1), (unsigned long)kMaxDownloadAttempts, urlString);
    if (!YZShouldPreservePartialAtPath(filePath)) {
        [self removeFileAt:filePath];
    }
    unsigned long long resumeOffset = 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:NULL];
    if (attrs != nil) {
        resumeOffset = [attrs fileSize];
    }
    YZDownloadLog(@"file=%@ resumeOffset=%llu", filePath, resumeOffset);

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
        [request setValue:[reqHeaders valueForKey:key] forHeader:key];
    }
    __block NSUInteger responseStatus = 0;
    __block unsigned long long progressBase = resumeOffset;
    __block unsigned long long expectedTotal = 0;
    request.initialResponseBlock = ^(NSUInteger statusCode, NSDictionary *headers) {
        responseStatus = statusCode;
        if (statusCode != 206) {
            progressBase = 0;
        }
        expectedTotal = YZTotalBytesFromHeaders(headers, statusCode, progressBase);
        if (statusCode == 416 && resumeOffset > 0) {
            expectedTotal = resumeOffset;
        }
        YZDownloadLog(@"response %@ status=%lu contentLength=%@ contentRange=%@ expectedTotal=%llu",
                      filePath,
                      (unsigned long)statusCode,
                      YZHeaderValue(headers, @"Content-Length"),
                      YZHeaderValue(headers, @"Content-Range"),
                      expectedTotal);
        if (parent.downloadProgressBlock != nil && expectedTotal > 0) {
            parent.downloadProgressBlock((NSUInteger)MIN(progressBase, expectedTotal), (NSUInteger)expectedTotal);
        }
    };
    request.downloadProgressBlock = ^(NSUInteger current, NSUInteger total) {
        unsigned long long fullCurrent = progressBase + current;
        unsigned long long fullTotal = expectedTotal > 0 ? expectedTotal : (progressBase + total);
        if (parent.downloadProgressBlock != nil) {
            parent.downloadProgressBlock((NSUInteger)fullCurrent, (NSUInteger)fullTotal);
        }
    };
    request.finishBlock = ^(BBHTTPRequest *request) {
        NSUInteger httpStatus = request.responseStatusCode;
        if (httpStatus == 0) {
            httpStatus = responseStatus;
        }
        BOOL cancelled = [request wasCancelled] || parent.state == YZRepStateCancelled || parent.state == YZRepStateFailed;
        // Protect the installer from redirect or error stubs
        BOOL httpOK = [request hasSuccessfulResponse] && httpStatus >= 200 && httpStatus < 300;
        BOOL complete = YZDownloadedFileMatchesExpectedTotal(filePath, expectedTotal);
        BOOL validIPA = httpOK && complete && [YZQueueOps isValidIPAAtPath:filePath];

        if (cancelled) {
            YZDownloadLog(@"cancelled %@ url=%@", filePath, urlString);
            [self removeFileAt:filePath];
        } else if (httpStatus == 416 && [YZQueueOps isValidIPAAtPath:filePath]) {
            YZDownloadLog(@"success %@ existing file complete status=416", filePath);
            parent.state = YZRepStateDownloaded;
            parent.path = filePath;
        } else if (validIPA) {
            YZDownloadLog(@"success %@ status=%lu url=%@", filePath, (unsigned long)httpStatus, urlString);
            parent.state = YZRepStateDownloaded;
            parent.path = filePath;
        } else {
            NSString *location = YZHeaderValue(request.response.headers, @"Location");
            YZDownloadLog(@"failure %@ status=%lu error=%@ location=%@ url=%@",
                          filePath,
                          (unsigned long)httpStatus,
                          [request.error localizedDescription],
                          location,
                          urlString);
            if (httpOK || (httpStatus >= 400 && httpStatus < 500 && httpStatus != 429)) {
                [self removeFileAt:filePath];
            }
            NSUInteger nextAttempt = attempt + 1;
            if (nextAttempt < kMaxDownloadAttempts) {
                BOOL redirectStopped = (httpStatus >= 300 && httpStatus < 400);
                NSTimeInterval delay = redirectStopped ? 0.0 : MIN(8.0, 1.0 * (1 << MIN(nextAttempt, 3)));
                NSString *nextURL = [candidates objectAtIndex:(nextAttempt % [candidates count])];
                YZDownloadLog(@"retry %@ nextAttempt=%lu delay=%.1f nextURL=%@", filePath, (unsigned long)(nextAttempt + 1), delay, nextURL);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (parent.invalid || parent.state == YZRepStateCancelled) {
                        return;
                    }
                    [self downloadFileViaBBHTTP:originalURL candidates:candidates targetPath:filePath parent:parent attempt:nextAttempt];
                });
            } else {
                YZDownloadLog(@"final failure %@ after %lu attempts", filePath, (unsigned long)kMaxDownloadAttempts);
                [self removeFileAt:filePath];
                parent.state = YZRepStateFailed;
            }
        }
    };
    //request.downloadSpeedLimit = 1204; // 256KB/s
    request.responseContentHandler = [[BBHTTPFileWriter alloc] initWithTargetFile:filePath appendFromOffset:resumeOffset];
    parent.path = filePath;
    parent.request = request; // this is a weak reference, please check it for nil
    parent.downloadTask = request;
    [[BBHTTPExecutor sharedExecutor] executeRequest:request];
}

#pragma mark - Misc Methods
+ (BOOL)isValidIPAAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        return NO;
    }
    unsigned long long size = [[fm attributesOfItemAtPath:path error:NULL] fileSize];
    if (size < 4096) { // real IPAs are large, redirect stubs are a few hundred bytes
        return NO;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return NO;
    }
    NSData *magic = [handle readDataOfLength:4];
    [handle closeFile];
    if (magic.length < 4) {
        return NO;
    }
    const unsigned char *b = magic.bytes;
    return (b[0] == 'P' && b[1] == 'K' && b[2] == 0x03 && b[3] == 0x04);
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
