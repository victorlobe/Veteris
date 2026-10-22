#import <Foundation/Foundation.h>

@interface YZBackgroundKeeper : NSObject
+ (YZBackgroundKeeper *)sharedInstance;
- (void)update;
- (void)holdForLaunchRestore;
- (void)releaseLaunchHold;
@end
