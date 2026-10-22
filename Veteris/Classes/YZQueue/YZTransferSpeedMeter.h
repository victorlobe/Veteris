#import <Foundation/Foundation.h>

@interface YZTransferSpeedMeter : NSObject
- (instancetype)initWithWindow:(NSTimeInterval)window;
- (void)recordTotal:(unsigned long long)total at:(NSTimeInterval)time;
- (double)bytesPerSecondAt:(NSTimeInterval)time;
- (void)reset;
@end
