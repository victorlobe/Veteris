//
//  YZDownloadResumeStore.h
//  Veteris
//
//  Created by Victor on 25.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <Foundation/Foundation.h>

@class YZApplication;

extern NSString *const YZResumeInfoSourceURLKey;
extern NSString *const YZResumeInfoTotalKey;
extern NSString *const YZResumeInfoETagKey;
extern NSString *const YZResumeInfoResolvedURLKey;
extern NSString *const YZResumeInfoSegmentsKey;
extern NSString *const YZResumeInfoSegmentStartKey;
extern NSString *const YZResumeInfoSegmentEndKey;
extern NSString *const YZResumeInfoSegmentPartKey;
extern NSString *const YZResumeInfoMergingKey;


@interface YZDownloadResumeStore : NSObject
+ (NSString *)manifestPath;
+ (NSArray *)pendingRecords;
+ (NSArray *)pendingTargetPaths;
+ (void)upsertRecordForApplication:(YZApplication *)application
                         sourceURL:(NSString *)sourceURL
                        targetPath:(NSString *)targetPath
              installAfterDownload:(BOOL)installAfterDownload
                        userPaused:(BOOL)userPaused;
+ (void)removeRecordForTargetPath:(NSString *)targetPath;
+ (YZApplication *)applicationFromRecord:(NSDictionary *)record;
+ (BOOL)isUserPausedRecord:(NSDictionary *)record;



+ (BOOL)migrateLegacyDownloadDirectoryIfNeeded;

+ (NSString *)resumeInfoPathForTargetPath:(NSString *)targetPath;
+ (NSDictionary *)resumeInfoForTargetPath:(NSString *)targetPath;
+ (void)updateResumeInfoForTargetPath:(NSString *)targetPath setting:(NSDictionary *)entries removingKeys:(NSArray *)keys;

+ (NSString *)partPathForTargetPath:(NSString *)targetPath index:(NSUInteger)index;
+ (NSArray *)existingPartPathsForTargetPath:(NSString *)targetPath;
+ (void)removePartsForTargetPath:(NSString *)targetPath;

+ (void)removeArtifactsForTargetPath:(NSString *)targetPath includingTarget:(BOOL)includeTarget;
+ (NSString *)targetPathForArtifactPath:(NSString *)path;
@end
