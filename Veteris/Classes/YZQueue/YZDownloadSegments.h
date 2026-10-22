#import <Foundation/Foundation.h>


@interface YZDownloadSegment : NSObject
@property (nonatomic, assign) unsigned long long start;
@property (nonatomic, assign) unsigned long long end;
@property (nonatomic, assign) unsigned long long have;
@property (nonatomic, assign) NSUInteger part;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) NSUInteger owner;
@property (nonatomic, assign) NSTimeInterval lastActivity;
@property (nonatomic, assign) NSUInteger takeovers;
- (unsigned long long)length;
- (unsigned long long)remaining;
- (BOOL)isComplete;
@end

typedef enum {
    YZSegmentClaimNone = 0,
    YZSegmentClaimIdle,
    YZSegmentClaimSplit,
    YZSegmentClaimTakeover,
} YZSegmentClaim;

@interface YZDownloadSegments : NSObject
+ (NSMutableArray *)segmentsFromBase:(unsigned long long)base total:(unsigned long long)total count:(NSUInteger)count;
+ (BOOL)segmentsAreValid:(NSArray *)segments total:(unsigned long long)total;
+ (YZDownloadSegment *)claimSegmentFrom:(NSMutableArray *)segments
                      minimumSplitBytes:(unsigned long long)minimumSplitBytes
                        maximumSegments:(NSUInteger)maximumSegments
                          stallInterval:(NSTimeInterval)stallInterval
                                    now:(NSTimeInterval)now
                                   kind:(YZSegmentClaim *)kind;
+ (BOOL)allSegmentsComplete:(NSArray *)segments;
+ (unsigned long long)storedBytesInSegments:(NSArray *)segments;
@end
