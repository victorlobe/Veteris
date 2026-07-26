//
//  YZDownloadResumeStore.h
//  Veteris
//
//  Created by Victor on 25.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <Foundation/Foundation.h>

@class YZApplication;

@interface YZDownloadResumeStore : NSObject
+ (NSString *)manifestPath;
+ (NSArray *)pendingRecords;
+ (NSArray *)pendingTargetPaths;
+ (void)upsertRecordForApplication:(YZApplication *)application
                         sourceURL:(NSString *)sourceURL
                        targetPath:(NSString *)targetPath
              installAfterDownload:(BOOL)installAfterDownload;
+ (void)removeRecordForTargetPath:(NSString *)targetPath;
+ (YZApplication *)applicationFromRecord:(NSDictionary *)record;
@end
