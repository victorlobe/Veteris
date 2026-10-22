#import "YZDownloadSegments.h"

static const NSUInteger kYZMaxTakeoverBackoffSteps = 3;

@implementation YZDownloadSegment

- (unsigned long long)length {
    return self.end >= self.start ? self.end - self.start + 1 : 0;
}

- (unsigned long long)remaining {
    unsigned long long length = [self length];
    return self.have < length ? length - self.have : 0;
}

- (BOOL)isComplete {
    return [self remaining] == 0;
}

@end

@implementation YZDownloadSegments

+ (NSMutableArray *)segmentsFromBase:(unsigned long long)base total:(unsigned long long)total count:(NSUInteger)count {
    NSMutableArray *segments = [NSMutableArray array];
    if (total <= base) {
        return segments;
    }
    unsigned long long remaining = total - base;
    NSUInteger segmentCount = (NSUInteger)MIN((unsigned long long)MAX(count, (NSUInteger)1), remaining);
    unsigned long long segmentSize = (remaining + segmentCount - 1) / segmentCount;
    for (NSUInteger idx = 0; idx < segmentCount; idx++) {
        unsigned long long start = base + ((unsigned long long)idx * segmentSize);
        if (start >= total) {
            break;
        }
        YZDownloadSegment *segment = [[YZDownloadSegment alloc] init];
        segment.start = start;
        segment.end = MIN(total - 1, start + segmentSize - 1);
        segment.part = idx;
        [segments addObject:segment];
    }
    return segments;
}

+ (BOOL)segmentsAreValid:(NSArray *)segments total:(unsigned long long)total {
    if ([segments count] == 0 || total == 0) {
        return NO;
    }
    NSMutableSet *parts = [NSMutableSet set];
    unsigned long long expectedStart = [(YZDownloadSegment *)[segments objectAtIndex:0] start];
    for (NSUInteger idx = 0; idx < [segments count]; idx++) {
        YZDownloadSegment *segment = [segments objectAtIndex:idx];
        if (![segment isKindOfClass:[YZDownloadSegment class]] || segment.start != expectedStart || segment.end < segment.start) {
            return NO;
        }
        if ((idx == 0) != (segment.part == 0)) {
            return NO;
        }
        NSNumber *part = [NSNumber numberWithUnsignedInteger:segment.part];
        if ([parts containsObject:part]) {
            return NO;
        }
        [parts addObject:part];
        expectedStart = segment.end + 1;
    }
    return expectedStart == total;
}

+ (YZDownloadSegment *)claimSegmentFrom:(NSMutableArray *)segments
                      minimumSplitBytes:(unsigned long long)minimumSplitBytes
                        maximumSegments:(NSUInteger)maximumSegments
                          stallInterval:(NSTimeInterval)stallInterval
                                    now:(NSTimeInterval)now
                                   kind:(YZSegmentClaim *)kind {
    YZSegmentClaim claim = YZSegmentClaimNone;
    YZDownloadSegment *claimed = nil;

    for (YZDownloadSegment *segment in segments) {
        if (!segment.active && ![segment isComplete]) {
            claimed = segment;
            claim = YZSegmentClaimIdle;
            break;
        }
    }

    NSUInteger victimIndex = NSNotFound;
    unsigned long long victimRemaining = 0;
    YZDownloadSegment *stalled = nil;
    NSUInteger nextPart = 0;
    if (claimed == nil) {
        for (NSUInteger idx = 0; idx < [segments count]; idx++) {
            YZDownloadSegment *segment = [segments objectAtIndex:idx];
            nextPart = MAX(nextPart, segment.part + 1);
            unsigned long long remaining = [segment remaining];
            if (!segment.active || remaining == 0) {
                continue;
            }
            if (remaining > victimRemaining) {
                victimIndex = idx;
                victimRemaining = remaining;
            }
            NSTimeInterval allowedSilence = stallInterval * (double)(1U << MIN(segment.takeovers, kYZMaxTakeoverBackoffSteps));
            if (now - segment.lastActivity >= allowedSilence && (stalled == nil || remaining > [stalled remaining])) {
                stalled = segment;
            }
        }
    }

    if (claimed == nil && victimIndex != NSNotFound && [segments count] < maximumSegments &&
        victimRemaining >= MAX(minimumSplitBytes, 2ULL)) {
        YZDownloadSegment *victim = [segments objectAtIndex:victimIndex];
        unsigned long long splitStart = victim.start + victim.have + victimRemaining / 2;
        claimed = [[YZDownloadSegment alloc] init];
        claimed.start = splitStart;
        claimed.end = victim.end;
        claimed.part = nextPart;
        victim.end = splitStart - 1;
        [segments insertObject:claimed atIndex:victimIndex + 1];
        claim = YZSegmentClaimSplit;
    }

    if (claimed == nil && stalled != nil) {
        claimed = stalled;
        claimed.takeovers += 1;
        claim = YZSegmentClaimTakeover;
    }

    if (claimed != nil) {
        claimed.active = YES;
        claimed.owner += 1;
        claimed.lastActivity = now;
    }
    if (kind != NULL) {
        *kind = claim;
    }
    return claimed;
}

+ (BOOL)allSegmentsComplete:(NSArray *)segments {
    for (YZDownloadSegment *segment in segments) {
        if (![segment isComplete]) {
            return NO;
        }
    }
    return YES;
}

+ (unsigned long long)storedBytesInSegments:(NSArray *)segments {
    if ([segments count] == 0) {
        return 0;
    }
    unsigned long long stored = [(YZDownloadSegment *)[segments objectAtIndex:0] start];
    for (YZDownloadSegment *segment in segments) {
        stored += MIN(segment.have, [segment length]);
    }
    return stored;
}

@end
