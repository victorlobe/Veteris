#import "YZTransferSpeedMeter.h"

static const NSTimeInterval kYZSpeedMinimumSpan = 1.0;

@implementation YZTransferSpeedMeter {
    NSTimeInterval _window;
    NSMutableArray *_times;
    NSMutableArray *_totals;
}

- (instancetype)initWithWindow:(NSTimeInterval)window {
    if ((self = [super init])) {
        _window = MAX(window, kYZSpeedMinimumSpan);
        _times = [NSMutableArray array];
        _totals = [NSMutableArray array];
    }
    return self;
}

- (void)reset {
    [_times removeAllObjects];
    [_totals removeAllObjects];
}

- (void)pruneBefore:(NSTimeInterval)windowStart {
    while ([_times count] > 1 && [[_times objectAtIndex:1] doubleValue] <= windowStart) {
        [_times removeObjectAtIndex:0];
        [_totals removeObjectAtIndex:0];
    }
}

- (void)recordTotal:(unsigned long long)total at:(NSTimeInterval)time {
    if ([_totals count] > 0 && total < [[_totals lastObject] unsignedLongLongValue]) {
        [self reset];
    }
    [_times addObject:[NSNumber numberWithDouble:time]];
    [_totals addObject:[NSNumber numberWithUnsignedLongLong:total]];
    [self pruneBefore:time - _window];
}

- (double)bytesPerSecondAt:(NSTimeInterval)time {
    if ([_times count] == 0) {
        return -1.0;
    }
    NSTimeInterval windowStart = time - _window;
    [self pruneBefore:windowStart];
    NSTimeInterval firstTime = [[_times objectAtIndex:0] doubleValue];
    unsigned long long firstTotal = [[_totals objectAtIndex:0] unsignedLongLongValue];
    unsigned long long lastTotal = [[_totals lastObject] unsignedLongLongValue];
    NSTimeInterval span = firstTime > windowStart ? time - firstTime : _window;
    if (span < kYZSpeedMinimumSpan) {
        return -1.0;
    }
    return (double)(lastTotal - firstTotal) / span;
}

@end
