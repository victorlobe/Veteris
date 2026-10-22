#import <Foundation/Foundation.h>
#import "YZQueueRep.h"

@interface YZQueueOps : NSObject
+ (BOOL)installIPA:(NSString *)filePath errorDetails:(NSString **)errorDetails;
+ (void)startDownloadForRep:(YZQueueRep *)rep;
+ (void)stopTransferForRep:(YZQueueRep *)rep;
+ (void)performWhenTargetPathIdle:(NSString *)path block:(dispatch_block_t)block;
+ (BOOL)isValidIPAAtPath:(NSString *)path;
+ (void)notifyAppState:(YZQueueRep *)appRep;
@end
