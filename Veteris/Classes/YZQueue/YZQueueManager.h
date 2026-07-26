#import <Foundation/Foundation.h>
#import "YZQueueRep.h"
#import "YZQueueOps.h"

#define YZQM [YZQueueManager sharedInstance]

@interface YZQueueManager : NSObject
+ (YZQueueManager *)sharedInstance;
+ (void)enqueueYZApplicationForDownload:(YZApplication *)yzApp;
+ (void)enqueueYZApplicationForDownloadOnly:(YZApplication *)yzApp targetPath:(NSString *)targetPath;
+ (void)enqueueYZApplicationDownloaded:(YZApplication *)yzApp;
+ (void)restorePendingDownloads;
+ (NSArray *)pendingResumeTargetPaths;
+ (bool)markRepAsCancelled:(YZQueueRep *)rep;
+ (bool)pauseRep:(YZQueueRep *)rep;
+ (bool)retryRep:(YZQueueRep *)rep;
+ (NSArray *)allReps;
+ (NSUInteger)activeDownloadsCount;
+ (void)attachProgressBlock:(void (^)(NSUInteger current, NSUInteger total))block toRep:(YZQueueRep *)rep;
@end
