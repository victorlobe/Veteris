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

static NSString *const YZDownloadResumeManifestName = @".VeterisPendingDownloads.plist";
static NSString *const YZDownloadResumeSchemaVersionKey = @"schema_version";
static NSString *const YZDownloadResumeRecordsKey = @"records";
static NSString *const YZDownloadResumeRecordKeyKey = @"key";
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
static NSString *const YZDownloadResumeUserPausedKey = @"user_paused";

static NSString *const YZResumeInfoFileSuffix = @".veteris-resume";
static NSString *const YZPartFileInfix = @".part.";
static NSString *const YZDownloadDirectoryMigrationCompletedKey = @"VeterisDownloadDirectoryMigrationCompleted";
static NSString *const YZDownloadMigrationTemporaryPrefix = @".VeterisMigration-";

NSString *const YZResumeInfoSourceURLKey = @"source_url";
NSString *const YZResumeInfoTotalKey = @"total";
NSString *const YZResumeInfoETagKey = @"etag";
NSString *const YZResumeInfoResolvedURLKey = @"resolved_url";
NSString *const YZResumeInfoSegmentsKey = @"segments";
NSString *const YZResumeInfoSegmentStartKey = @"start";
NSString *const YZResumeInfoSegmentEndKey = @"end";
NSString *const YZResumeInfoSegmentPartKey = @"part";
NSString *const YZResumeInfoMergingKey = @"merging";

@implementation YZDownloadResumeStore

+ (NSString *)manifestPath {
    return [downloadPath() stringByAppendingPathComponent:YZDownloadResumeManifestName];
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
              installAfterDownload:(BOOL)installAfterDownload
                        userPaused:(BOOL)userPaused {
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
                                key, YZDownloadResumeRecordKeyKey,
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
                                [NSNumber numberWithBool:userPaused], YZDownloadResumeUserPausedKey,
                                nil];

        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger i = 0; i < [records count]; i++) {
            NSDictionary *existing = [records objectAtIndex:i];
            if ([[existing objectForKey:YZDownloadResumeTargetPathKey] isEqualToString:targetPath]) {
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

+ (BOOL)isUserPausedRecord:(NSDictionary *)record {
    if (![record isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    id value = [record objectForKey:YZDownloadResumeUserPausedKey];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

#pragma mark - Legacy folder migration

+ (BOOL)migrateLegacyDownloadDirectoryIfNeeded {
    NSString *legacyDir = legacyDownloadPath();
    NSString *currentDir = downloadPath();
    NSFileManager *manager = [[NSFileManager alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:legacyDir isDirectory:&isDirectory] || !isDirectory) {
        [defaults setBool:YES forKey:YZDownloadDirectoryMigrationCompletedKey];
        [defaults synchronize];
        return YES;
    }
    if ([defaults boolForKey:YZDownloadDirectoryMigrationCompletedKey]) {
        // A downgraded app may recreate this folder after migration
        [defaults setBool:NO forKey:YZDownloadDirectoryMigrationCompletedKey];
        [defaults synchronize];
    }

    @synchronized (self) {
        NSString *legacyManifestPath = [legacyDir stringByAppendingPathComponent:YZDownloadResumeManifestName];
        NSArray *legacyRecords = [self migratedRecordsFromManifestAtPath:legacyManifestPath legacyDirectory:legacyDir];
        NSArray *currentRecords = [manager fileExistsAtPath:currentDir] ? [self normalizedRecordsFromManifest:[self manifest]] : [NSArray array];

        NSError *error = nil;
        if (![manager createDirectoryAtPath:currentDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            debugLog(@"Could not create %@ for migration: %@", currentDir, [error localizedDescription]);
            return NO;
        }
        NSDictionary *legacyManifest = [NSDictionary dictionaryWithContentsOfFile:legacyManifestPath];
        if ([manager fileExistsAtPath:legacyManifestPath] &&
            (![legacyManifest isKindOfClass:[NSDictionary class]] ||
             ![[legacyManifest objectForKey:YZDownloadResumeRecordsKey] isKindOfClass:[NSArray class]])) {
            debugLog(@"Legacy resume manifest is unreadable; preserving %@", legacyDir);
            return NO;
        }
        NSArray *rawLegacyRecords = [legacyManifest objectForKey:YZDownloadResumeRecordsKey];
        if ([rawLegacyRecords count] != [legacyRecords count]) {
            debugLog(@"Legacy resume manifest contains records that cannot be migrated; preserving %@", legacyDir);
            return NO;
        }
        if (![self copyDirectoryContentsSafelyAtPath:legacyDir toPath:currentDir skippingPath:legacyManifestPath manager:manager]) {
            debugLog(@"Migration paused; legacy folder is preserved at %@", legacyDir);
            return NO;
        }

        NSMutableArray *records = [NSMutableArray arrayWithArray:currentRecords];
        for (NSDictionary *record in legacyRecords) {
            NSString *targetPath = [record objectForKey:YZDownloadResumeTargetPathKey];
            BOOL duplicate = NO;
            for (NSDictionary *existing in records) {
                if ([[existing objectForKey:YZDownloadResumeTargetPathKey] isEqualToString:targetPath]) {
                    duplicate = YES;
                    break;
                }
            }
            if (!duplicate) {
                [records addObject:record];
            }
        }
        [self writeRecords:records];
        NSDictionary *expectedManifest = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithUnsignedInteger:1], YZDownloadResumeSchemaVersionKey,
                                          records, YZDownloadResumeRecordsKey,
                                          nil];
        NSDictionary *writtenManifest = [NSDictionary dictionaryWithContentsOfFile:[self manifestPath]];
        BOOL manifestIsVerified = [records count] == 0 ? writtenManifest == nil : [writtenManifest isEqualToDictionary:expectedManifest];
        if (!manifestIsVerified ||
            ![self directoryContentsAtPath:legacyDir areSafelyPresentInPath:currentDir skippingPath:legacyManifestPath manager:manager]) {
            debugLog(@"Migration verification failed; legacy folder is preserved at %@", legacyDir);
            return NO;
        }

        error = nil;
        if (![manager removeItemAtPath:legacyDir error:&error] || [manager fileExistsAtPath:legacyDir]) {
            debugLog(@"Could not remove fully copied legacy folder %@: %@", legacyDir, [error localizedDescription]);
            return NO;
        }

        [defaults setBool:YES forKey:YZDownloadDirectoryMigrationCompletedKey];
        [defaults synchronize];
        debugLog(@"Migrated and verified Veteris download folder %@ -> %@ (records=%lu)", legacyDir, currentDir, (unsigned long)[records count]);
        return YES;
    }
}

+ (NSArray *)migratedRecordsFromManifestAtPath:(NSString *)manifestPath legacyDirectory:(NSString *)legacyDir {
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
    NSArray *rawRecords = [manifest isKindOfClass:[NSDictionary class]] ? [manifest objectForKey:YZDownloadResumeRecordsKey] : nil;
    if (![rawRecords isKindOfClass:[NSArray class]]) {
        return [NSArray array];
    }
    NSString *legacyPrefix = [legacyDir stringByAppendingString:@"/"];
    NSMutableArray *records = [NSMutableArray array];
    for (id rawRecord in rawRecords) {
        if (![rawRecord isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSMutableDictionary *record = [rawRecord mutableCopy];
        NSString *targetPath = [record objectForKey:YZDownloadResumeTargetPathKey];
        if ([targetPath isKindOfClass:[NSString class]] && [targetPath hasPrefix:legacyPrefix]) {
            targetPath = [downloadPath() stringByAppendingPathComponent:[targetPath substringFromIndex:[legacyPrefix length]]];
            [record setObject:targetPath forKey:YZDownloadResumeTargetPathKey];
            NSString *key = [self recordKeyForBundleID:[record objectForKey:YZDownloadResumeBundleIDKey]
                                               version:[record objectForKey:YZDownloadResumeVersionKey]
                                            targetPath:targetPath];
            if ([key length] > 0) {
                [record setObject:key forKey:YZDownloadResumeRecordKeyKey];
            }
        }
        if ([self isValidSourceURL:[record objectForKey:YZDownloadResumeSourceURLKey]] && [self isValidTargetPath:targetPath]) {
            [records addObject:record];
        }
    }
    return records;
}

+ (BOOL)copyDirectoryContentsSafelyAtPath:(NSString *)sourceDir toPath:(NSString *)destinationDir skippingPath:(NSString *)skippedPath manager:(NSFileManager *)manager {
    NSError *error = nil;
    NSArray *entries = [manager contentsOfDirectoryAtPath:sourceDir error:&error];
    if (entries == nil) {
        debugLog(@"Could not list migration source %@: %@", sourceDir, [error localizedDescription]);
        return NO;
    }
    for (NSString *entry in entries) {
        NSString *source = [sourceDir stringByAppendingPathComponent:entry];
        NSString *destination = [destinationDir stringByAppendingPathComponent:entry];
        if ([source isEqualToString:skippedPath]) {
            continue;
        }

        NSDictionary *sourceAttributes = [manager attributesOfItemAtPath:source error:&error];
        if (sourceAttributes == nil) {
            debugLog(@"Could not inspect migration source %@: %@", source, [error localizedDescription]);
            return NO;
        }
        NSString *fileType = [sourceAttributes objectForKey:NSFileType];
        if ([fileType isEqualToString:NSFileTypeDirectory]) {
            BOOL destinationIsDirectory = NO;
            if ([manager fileExistsAtPath:destination isDirectory:&destinationIsDirectory] && !destinationIsDirectory) {
                debugLog(@"Migration conflict at %@; preserving %@", destination, source);
                return NO;
            }
            if (![manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error] ||
                ![self copyDirectoryContentsSafelyAtPath:source toPath:destination skippingPath:skippedPath manager:manager]) {
                debugLog(@"Could not migrate directory %@: %@", source, [error localizedDescription]);
                return NO;
            }
        } else if ([fileType isEqualToString:NSFileTypeRegular]) {
            if ([manager fileExistsAtPath:destination]) {
                if (![self filesAtPath:source equalContentsOfPath:destination manager:manager]) {
                    debugLog(@"Migration conflict at %@; preserving %@", destination, source);
                    return NO;
                }
                continue;
            }

            NSString *temporaryName = [NSString stringWithFormat:@"%@%@", YZDownloadMigrationTemporaryPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
            NSString *temporary = [destinationDir stringByAppendingPathComponent:temporaryName];
            if (![manager copyItemAtPath:source toPath:temporary error:&error] ||
                ![self filesAtPath:source equalContentsOfPath:temporary manager:manager]) {
                [manager removeItemAtPath:temporary error:NULL];
                debugLog(@"Could not safely copy %@: %@", source, [error localizedDescription]);
                return NO;
            }
            if (![manager moveItemAtPath:temporary toPath:destination error:&error]) {
                [manager removeItemAtPath:temporary error:NULL];
                debugLog(@"Could not commit copied file %@: %@", destination, [error localizedDescription]);
                return NO;
            }
        } else {
            debugLog(@"Unsupported item in migration source %@; preserving the legacy folder", source);
            return NO;
        }
    }
    return YES;
}

+ (BOOL)directoryContentsAtPath:(NSString *)sourceDir areSafelyPresentInPath:(NSString *)destinationDir skippingPath:(NSString *)skippedPath manager:(NSFileManager *)manager {
    NSError *error = nil;
    NSArray *entries = [manager contentsOfDirectoryAtPath:sourceDir error:&error];
    if (entries == nil) {
        debugLog(@"Could not verify migration source %@: %@", sourceDir, [error localizedDescription]);
        return NO;
    }
    for (NSString *entry in entries) {
        NSString *source = [sourceDir stringByAppendingPathComponent:entry];
        NSString *destination = [destinationDir stringByAppendingPathComponent:entry];
        if ([source isEqualToString:skippedPath]) {
            continue;
        }
        NSDictionary *attributes = [manager attributesOfItemAtPath:source error:&error];
        if (attributes == nil) {
            return NO;
        }
        NSString *fileType = [attributes objectForKey:NSFileType];
        if ([fileType isEqualToString:NSFileTypeDirectory]) {
            BOOL destinationIsDirectory = NO;
            if (![manager fileExistsAtPath:destination isDirectory:&destinationIsDirectory] || !destinationIsDirectory ||
                ![self directoryContentsAtPath:source areSafelyPresentInPath:destination skippingPath:skippedPath manager:manager]) {
                return NO;
            }
        } else if (![fileType isEqualToString:NSFileTypeRegular] ||
                   ![self filesAtPath:source equalContentsOfPath:destination manager:manager]) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)filesAtPath:(NSString *)leftPath equalContentsOfPath:(NSString *)rightPath manager:(NSFileManager *)manager {
    NSDictionary *leftAttributes = [manager attributesOfItemAtPath:leftPath error:NULL];
    NSDictionary *rightAttributes = [manager attributesOfItemAtPath:rightPath error:NULL];
    if (leftAttributes == nil || rightAttributes == nil ||
        [[leftAttributes objectForKey:NSFileSize] unsignedLongLongValue] != [[rightAttributes objectForKey:NSFileSize] unsignedLongLongValue]) {
        return NO;
    }

    NSFileHandle *left = [NSFileHandle fileHandleForReadingAtPath:leftPath];
    NSFileHandle *right = [NSFileHandle fileHandleForReadingAtPath:rightPath];
    if (left == nil || right == nil) {
        [left closeFile];
        [right closeFile];
        return NO;
    }
    BOOL equal = YES;
    @try {
        while (YES) {
            NSData *leftChunk = [left readDataOfLength:256 * 1024];
            NSData *rightChunk = [right readDataOfLength:256 * 1024];
            if (![leftChunk isEqualToData:rightChunk]) {
                equal = NO;
                break;
            }
            if ([leftChunk length] == 0) {
                break;
            }
        }
    } @catch (NSException *exception) {
        equal = NO;
        debugLog(@"Could not compare migration files %@ and %@: %@", leftPath, rightPath, [exception reason]);
    }
    [left closeFile];
    [right closeFile];
    return equal;
}

#pragma mark - Resume sidecar and segment files

+ (NSString *)resumeInfoPathForTargetPath:(NSString *)targetPath {
    if ([targetPath length] == 0) {
        return nil;
    }
    return [targetPath stringByAppendingString:YZResumeInfoFileSuffix];
}

+ (NSDictionary *)resumeInfoForTargetPath:(NSString *)targetPath {
    NSString *infoPath = [self resumeInfoPathForTargetPath:targetPath];
    if (infoPath == nil) {
        return nil;
    }
    @synchronized (self) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        return [info isKindOfClass:[NSDictionary class]] ? info : nil;
    }
}

+ (void)updateResumeInfoForTargetPath:(NSString *)targetPath setting:(NSDictionary *)entries removingKeys:(NSArray *)keys {
    NSString *infoPath = [self resumeInfoPathForTargetPath:targetPath];
    if (infoPath == nil) {
        return;
    }
    @synchronized (self) {
        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSMutableDictionary *info = [existing isKindOfClass:[NSDictionary class]] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            [info removeObjectForKey:key];
        }
        [info addEntriesFromDictionary:entries];
        [[NSFileManager defaultManager] createDirectoryAtPath:[infoPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        if (![info writeToFile:infoPath atomically:YES]) {
            debugLog(@"Could not write resume info %@", infoPath);
        }
    }
}

+ (NSString *)partPathForTargetPath:(NSString *)targetPath index:(NSUInteger)index {
    return [NSString stringWithFormat:@"%@%@%lu", targetPath, YZPartFileInfix, (unsigned long)index];
}

+ (NSArray *)existingPartPathsForTargetPath:(NSString *)targetPath {
    if ([targetPath length] == 0) {
        return [NSArray array];
    }
    NSString *directory = [targetPath stringByDeletingLastPathComponent];
    NSString *prefix = [[targetPath lastPathComponent] stringByAppendingString:YZPartFileInfix];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL]) {
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
        return leftIndex > rightIndex ? NSOrderedDescending : NSOrderedSame;
    }];
    return paths;
}

+ (void)removePartsForTargetPath:(NSString *)targetPath {
    for (NSString *partPath in [self existingPartPathsForTargetPath:targetPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:partPath error:NULL];
    }
}

+ (void)removeArtifactsForTargetPath:(NSString *)targetPath includingTarget:(BOOL)includeTarget {
    if ([targetPath length] == 0) {
        return;
    }
    [self removePartsForTargetPath:targetPath];
    @synchronized (self) {
        [[NSFileManager defaultManager] removeItemAtPath:[self resumeInfoPathForTargetPath:targetPath] error:NULL];
    }
    if (includeTarget) {
        [[NSFileManager defaultManager] removeItemAtPath:targetPath error:NULL];
    }
}

+ (NSString *)targetPathForArtifactPath:(NSString *)path {
    if ([path hasSuffix:YZResumeInfoFileSuffix]) {
        return [path substringToIndex:[path length] - [YZResumeInfoFileSuffix length]];
    }
    NSRange partRange = [path rangeOfString:YZPartFileInfix options:NSBackwardsSearch];
    if (partRange.location == NSNotFound) {
        return nil;
    }
    NSString *suffix = [path substringFromIndex:NSMaxRange(partRange)];
    if ([suffix length] == 0 || [suffix rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
        return nil;
    }
    return [path substringToIndex:partRange.location];
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
    if (![manifest writeToFile:manifestPath atomically:YES]) {
        debugLog(@"Could not write resume manifest %@", manifestPath);
    }
}

+ (NSString *)recordKeyForBundleID:(NSString *)bundleID version:(NSString *)version targetPath:(NSString *)targetPath {
    if (![bundleID isKindOfClass:[NSString class]] || ![version isKindOfClass:[NSString class]] ||
        [bundleID length] == 0 || [version length] == 0 || [targetPath length] == 0) {
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
    return [targetPath hasPrefix:root] && [targetPath rangeOfString:@"/../"].location == NSNotFound;
}

+ (NSString *)safeString:(id)value {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

@end
