#import <Foundation/Foundation.h>
#import "YZQueueRep.h"

@interface YZQueueOps : NSObject
+ (BOOL)installIPA:(NSString *)filePath;
+ (void)downloadFileToPath:(NSString *)urlString pathFromString:(NSString *)str parent:(YZQueueRep *)parent;
+ (void)downloadFileToPath:(NSString *)urlString targetPath:(NSString *)targetPath parent:(YZQueueRep *)parent;
+ (void)notifyAppState:(YZQueueRep *)appRep;
@end
