#import <Foundation/Foundation.h>

@interface YZQueueReactor : NSObject
+ (YZQueueReactor *)sharedInstance;
- (void)launchApp:(NSString *)bundleId;
- (void)setBackgroundWorkActive:(BOOL)active completion:(void (^)(BOOL helperKeepsAlive))completion;
@end
