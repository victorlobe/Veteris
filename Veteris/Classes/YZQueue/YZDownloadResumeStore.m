//
//  YZDownloadResumeStore.m
//  Veteris
//
//  Created by Victor on 25.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "YZDownloadResumeStore.h"

#import "../VAPIHelper/VAPIHelper.h"
#import "../YZApplication/YZApplication.h"

static NSString *const YZDownloadResumeSchemaVersionKey = @"schema_version";
static NSString *const YZDownloadResumeRecordsKey = @"records";
static NSString *const YZDownloadResumeSourceURLKey = @"source_url";
static NSString *const YZDownloadResumeTargetPathKey = @"target_path";
static NSString *const YZDownloadResumeInstallAfterDownloadKey = @"install_after_download";
static NSString *const YZDownloadResumeNameKey = @"name";
static NSString *const YZDownloadResumeDeveloperKey = @"developer";
static NSString *const YZDownloadResumeBundleIDKey = @"bundle_id";
static NSString *const YZDownloadResumeVersionKey = @"version";
static NSString *const YZDownloadResumeMinimumOSKey = @"minimum_os";
static NSString *const YZDownloadResumeIconURLKey = @"icon_url";
static NSString *const YZDownloadResumeFallbackIconURLKey = @"fallback_icon_url";
static NSString *const YZDownloadResumeSizeBytesKey = @"size_bytes";
static NSString *const YZDownloadResumeUpdatedAtKey = @"updated_at";

@implementation YZDownloadResumeStore

+ (NSString *)manifestPath {
    return [downloadPath() stringByAppendingPathComponent:@".VeterisPendingDownloads.plist"];
}

+ (NSArray *)pendingRecords {
    @synchronized (self) {
        return [[self normalizedRecordsFromManifest:[self manifest]] copy];
    }
}

+ (NSArray *)pendingTargetPaths {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSDictionary *record in [self pendingRecords]) {
        NSString *targetPath = [record objectForKey:YZDownloadResumeTargetPathKey];
        if ([self isValidTargetPath:targetPath]) {
            [paths addObject:targetPath];
        }
    }
    return paths;
}

+ (void)upsertRecordForApplication:(YZApplication *)application
                         sourceURL:(NSString *)sourceURL
                        targetPath:(NSString *)targetPath
              installAfterDownload:(BOOL)installAfterDownload {
    if (application == nil || ![self isValidSourceURL:sourceURL] || ![self isValidTargetPath:targetPath]) {
        return;
    }

    @synchronized (self) {
        NSMutableArray *records = [NSMutableArray arrayWithArray:[self normalizedRecordsFromManifest:[self manifest]]];
        NSString *key = [self recordKeyForBundleID:application.bundleID version:application.version targetPath:targetPath];
        if ([key length] == 0) {
            return;
        }

        NSDictionary *record = [NSDictionary dictionaryWithObjectsAndKeys:
                                key, @"key",
                                sourceURL, YZDownloadResumeSourceURLKey,
                                targetPath, YZDownloadResumeTargetPathKey,
                                [NSNumber numberWithBool:installAfterDownload], YZDownloadResumeInstallAfterDownloadKey,
                                [self safeString:application.name], YZDownloadResumeNameKey,
                                [self safeString:application.developer], YZDownloadResumeDeveloperKey,
                                [self safeString:application.bundleID], YZDownloadResumeBundleIDKey,
                                [self safeString:application.version], YZDownloadResumeVersionKey,
                                [self safeString:application.minimumOS], YZDownloadResumeMinimumOSKey,
                                [self safeString:application.iconurl], YZDownloadResumeIconURLKey,
                                [self safeString:application.fallback_iconurl], YZDownloadResumeFallbackIconURLKey,
                                [NSNumber numberWithUnsignedLongLong:application.sizeBytes], YZDownloadResumeSizeBytesKey,
                                [NSDate date], YZDownloadResumeUpdatedAtKey,
                                nil];

        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger i = 0; i < [records count]; i++) {
            NSDictionary *existing = [records objectAtIndex:i];
            if ([[existing objectForKey:@"key"] isEqualToString:key]) {
                existingIndex = i;
                break;
            }
        }
        if (existingIndex == NSNotFound) {
            [records addObject:record];
        } else {
            [records replaceObjectAtIndex:existingIndex withObject:record];
        }
        [self writeRecords:records];
    }
}

+ (void)removeRecordForTargetPath:(NSString *)targetPath {
    if (![self isValidTargetPath:targetPath]) {
        return;
    }

    @synchronized (self) {
        NSMutableArray *records = [NSMutableArray arrayWithArray:[self normalizedRecordsFromManifest:[self manifest]]];
        NSIndexSet *indexes = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *record, NSUInteger idx, BOOL *stop) {
            return [[record objectForKey:YZDownloadResumeTargetPathKey] isEqualToString:targetPath];
        }];
        if ([indexes count] == 0) {
            return;
        }
        [records removeObjectsAtIndexes:indexes];
        [self writeRecords:records];
    }
}

+ (YZApplication *)applicationFromRecord:(NSDictionary *)record {
    if (![record isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *sourceURL = [record objectForKey:YZDownloadResumeSourceURLKey];
    NSString *targetPath = [record objectForKey:YZDownloadResumeTargetPathKey];
    if (![self isValidSourceURL:sourceURL] || ![self isValidTargetPath:targetPath]) {
        return nil;
    }

    YZApplication *application = [[YZApplication alloc] init];
    application.name = [self safeString:[record objectForKey:YZDownloadResumeNameKey]];
    application.developer = [self safeString:[record objectForKey:YZDownloadResumeDeveloperKey]];
    application.bundleID = [self safeString:[record objectForKey:YZDownloadResumeBundleIDKey]];
    application.version = [self safeString:[record objectForKey:YZDownloadResumeVersionKey]];
    application.minimumOS = [self safeString:[record objectForKey:YZDownloadResumeMinimumOSKey]];
    application.iconurl = [self safeString:[record objectForKey:YZDownloadResumeIconURLKey]];
    application.fallback_iconurl = [self safeString:[record objectForKey:YZDownloadResumeFallbackIconURLKey]];
    application.url = sourceURL;
    application.path = targetPath;
    id sizeValue = [record objectForKey:YZDownloadResumeSizeBytesKey];
    if ([sizeValue respondsToSelector:@selector(unsignedLongLongValue)]) {
        application.sizeBytes = [sizeValue unsignedLongLongValue];
    }

    if ([application.bundleID length] == 0 || [application.version length] == 0) {
        return nil;
    }
    return application;
}

#pragma mark - Private helpers

+ (NSDictionary *)manifest {
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:[self manifestPath]];
    return [manifest isKindOfClass:[NSDictionary class]] ? manifest : [NSDictionary dictionary];
}

+ (NSArray *)normalizedRecordsFromManifest:(NSDictionary *)manifest {
    NSArray *records = [manifest objectForKey:YZDownloadResumeRecordsKey];
    if (![records isKindOfClass:[NSArray class]]) {
        return [NSArray array];
    }

    NSMutableArray *normalized = [NSMutableArray array];
    for (id record in records) {
        if (![record isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *sourceURL = [record objectForKey:YZDownloadResumeSourceURLKey];
        NSString *targetPath = [record objectForKey:YZDownloadResumeTargetPathKey];
        if ([self isValidSourceURL:sourceURL] && [self isValidTargetPath:targetPath]) {
            [normalized addObject:record];
        }
    }
    return normalized;
}

+ (void)writeRecords:(NSArray *)records {
    NSString *downloadDir = downloadPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:downloadDir withIntermediateDirectories:YES attributes:nil error:NULL];

    NSString *manifestPath = [self manifestPath];
    if ([records count] == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:manifestPath error:NULL];
        return;
    }

    NSDictionary *manifest = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithUnsignedInteger:1], YZDownloadResumeSchemaVersionKey,
                              records, YZDownloadResumeRecordsKey,
                              nil];
    [manifest writeToFile:manifestPath atomically:YES];
}

+ (NSString *)recordKeyForBundleID:(NSString *)bundleID version:(NSString *)version targetPath:(NSString *)targetPath {
    if ([bundleID length] == 0 || [version length] == 0 || [targetPath length] == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@|%@|%@", bundleID, version, targetPath];
}

+ (BOOL)isValidSourceURL:(NSString *)sourceURL {
    if (![sourceURL isKindOfClass:[NSString class]] || [sourceURL length] == 0) {
        return NO;
    }
    NSString *lower = [sourceURL lowercaseString];
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
}

+ (BOOL)isValidTargetPath:(NSString *)targetPath {
    if (![targetPath isKindOfClass:[NSString class]] || [targetPath length] == 0) {
        return NO;
    }
    NSString *root = [downloadPath() stringByAppendingString:@"/"];
    return [targetPath hasPrefix:root];
}

+ (NSString *)safeString:(id)value {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

@end
