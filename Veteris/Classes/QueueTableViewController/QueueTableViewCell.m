#import "QueueTableViewCell.h"
#import <QuartzCore/QuartzCore.h>
#import "../../AppDelegate.h"
#import "../Convenience/Convenience.h"

@implementation QueueTableViewCell {
    YZQueueRep *_rep;
    NSString *_imageFromURL;
    NSUInteger _lastProgressBytes;
    NSTimeInterval _lastProgressTimestamp;
}
@synthesize appNameLabel;
@synthesize appVersionLabel;
@synthesize appDeveloperLabel;
@synthesize appImageView;
@synthesize appActivityIndicator;
@synthesize appDownloadActivityIndicator;
@synthesize appProgressView;
@synthesize appProgressLabel;
@synthesize appSpeedLabel;
- (id)initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]) {
        CGFloat height = 78;

        // App Cell image background
        UIImageView *background = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, height+1)];
        background.image = [UIImage imageNamed:@"AppCellBG.png"];

        // App Image
        appImageView = [[UIImageView alloc] initWithFrame:CGRectMake(7, 8, 64, 64)];
        appImageView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
        appImageView.layer.masksToBounds = YES;
        appImageView.layer.cornerRadius = 13.0;

        // App Name
        appNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(79, 29, 186, 21)];
        appNameLabel.numberOfLines = 1;
        appNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        appNameLabel.text = @"Grrrr rawr :3";
        appNameLabel.font = [UIFont boldSystemFontOfSize:17.0];
        appNameLabel.adjustsFontSizeToFitWidth = YES;
        appNameLabel.minimumFontSize = 11.0;
        appNameLabel.autoresizingMask = 
            UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin
            | UIViewAutoresizingFlexibleWidth;
        appNameLabel.backgroundColor = [UIColor clearColor];

        // App Version
        appVersionLabel = [[UILabel alloc] initWithFrame:CGRectMake(79, 54, 180, 21)];
        appVersionLabel.text = [NSString stringWithFormat:@"Version: kys"];
        appVersionLabel.font = [UIFont systemFontOfSize:10];
        appVersionLabel.textColor = [UIColor lightGrayColor];
        appVersionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        appVersionLabel.autoresizingMask = 
            UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin
            | UIViewAutoresizingFlexibleWidth;
        appVersionLabel.backgroundColor = [UIColor clearColor];

        // App Developer
        appDeveloperLabel = [[UILabel alloc] initWithFrame:CGRectMake(79, 8, 161, 21)];
        appDeveloperLabel.text = @">:3";
        appDeveloperLabel.font = [UIFont fontWithName:@"Helvetica" size:12.0];
        appDeveloperLabel.backgroundColor = [UIColor clearColor];
        appDeveloperLabel.autoresizingMask = 
            UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin
            | UIViewAutoresizingFlexibleWidth;

        appActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        appActivityIndicator.frame = CGRectMake(290, 29, 20, 20);
        appActivityIndicator.hidesWhenStopped = YES;
        appActivityIndicator.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;

        // Progress Bar
        appProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        appProgressView.frame = CGRectMake(270, 35, 40, 20);
        appProgressView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
        appProgressView.hidden = YES;

        appSpeedLabel = [[UILabel alloc] initWithFrame:CGRectMake(266, 20, 54, 13)];
        appSpeedLabel.font = [UIFont systemFontOfSize:9];
        appSpeedLabel.textColor = [UIColor lightGrayColor];
        appSpeedLabel.textAlignment = NSTextAlignmentCenter;
        appSpeedLabel.backgroundColor = [UIColor clearColor];
        appSpeedLabel.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
        appSpeedLabel.adjustsFontSizeToFitWidth = YES;
        appSpeedLabel.minimumFontSize = 7.0;
        appSpeedLabel.hidden = YES;

        appDownloadActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        appDownloadActivityIndicator.frame = CGRectMake(280, 29, 20, 20);
        appDownloadActivityIndicator.hidesWhenStopped = YES;
        appDownloadActivityIndicator.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;

        appProgressLabel = [[UILabel alloc] initWithFrame:CGRectMake(260, 47, 60, 14)];
        appProgressLabel.font = [UIFont systemFontOfSize:9];
        appProgressLabel.textColor = [UIColor lightGrayColor];
        appProgressLabel.textAlignment = NSTextAlignmentCenter;
        appProgressLabel.backgroundColor = [UIColor clearColor];
        appProgressLabel.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
        appProgressLabel.hidden = YES;

        [self.contentView addSubview:background];
        [self.contentView addSubview:appImageView];
        [self.contentView addSubview:appNameLabel];
        [self.contentView addSubview:appVersionLabel];
        [self.contentView addSubview:appDeveloperLabel];
        [self.contentView addSubview:appActivityIndicator];
        [self.contentView addSubview:appSpeedLabel];
        [self.contentView addSubview:appProgressView];
        [self.contentView addSubview:appDownloadActivityIndicator];
        [self.contentView addSubview:appProgressLabel];

        // change cilcked color
        self.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _rep = nil;
    self.appProgressView.hidden = YES;
    self.appProgressView.progress = 0;
    [self.appDownloadActivityIndicator stopAnimating];
    self.appProgressLabel.hidden = YES;
    self.appProgressLabel.text = nil;
    self.appSpeedLabel.hidden = YES;
    self.appSpeedLabel.text = nil;
    _lastProgressBytes = 0;
    _lastProgressTimestamp = 0;
}

- (void)updateFromRep:(YZQueueRep *)rep {
    [rep refreshStoredDownloadProgress];
    appNameLabel.text = rep.name;
    appDeveloperLabel.text = VeterisAppCellSubtitle(rep.developer, rep.bundleID, VeterisAppCellSubtitleAreaQueue);
    if (rep.icon == nil) {
        if (rep.iconurl == nil || ![rep.iconurl isEqualToString:_imageFromURL]) {
            appImageView.image = [VAPISS imageFromCache:rep.iconurl];
            if (appImageView.image == nil) {
                [VAPISS getStatic:rep.iconurl fallbackPath:rep.fallbackIconurl completion:^(NSData *data, NSError *error) {
                    if (error == nil) {
                        appImageView.image = [UIImage imageWithData:data];
                        _imageFromURL = rep.iconurl;
                    } else {
                        debugLog(@"Failed to fetch image for %@: %@", rep.bundleID, [error localizedDescription]);
                    }
                }];
            }
        }
    } else {
        appImageView.image = rep.icon;
    }

    appVersionLabel.text = [self versionTextForRep:rep sizeText:[self sizeTextForRep:rep]];
    if (_rep != rep) {
        _lastProgressBytes = 0;
        _lastProgressTimestamp = 0;
        appSpeedLabel.text = nil;
    }
    [self setNeedsDisplay];
    _rep = rep;
    BOOL shouldShowStoredProgress = (rep.state == YZRepStatePaused ||
                                     rep.state == YZRepStateQueued ||
                                     rep.state == YZRepStateFailed ||
                                     rep.state == YZRepStateDownloading);
    if (shouldShowStoredProgress && rep.storedProgressCurrent > 0) {
        [self updateDownloadProgressWithCurrent:rep.storedProgressCurrent total:rep.storedProgressTotal];
        if (rep.state != YZRepStateDownloading) {
            [appDownloadActivityIndicator stopAnimating];
        }
    }
}

- (void)updateDownloadProgressWithCurrent:(NSUInteger)current total:(NSUInteger)total {
    if (_rep != nil) {
        _rep.storedProgressCurrent = current;
        _rep.storedProgressTotal = total;
    }
    if (total == 0) {
        appProgressView.hidden = YES;
        appProgressView.progress = 0;
        appProgressLabel.text = nil;
        appProgressLabel.hidden = YES;
        appSpeedLabel.text = nil;
        appSpeedLabel.hidden = YES;
        _lastProgressBytes = current;
        _lastProgressTimestamp = [NSDate timeIntervalSinceReferenceDate];
        [appDownloadActivityIndicator startAnimating];
        appVersionLabel.text = [self versionTextForRep:_rep sizeText:[QueueTableViewCell stringForByteCount:current]];
        return;
    }
    [appDownloadActivityIndicator stopAnimating];
    appProgressView.hidden = NO;
    float progress = (float)current / (float)total;
    progress = MIN(MAX(progress, 0.0), 1.0);
    appProgressView.progress = progress;
    appProgressLabel.text = [NSString stringWithFormat:@"%lu%%", (unsigned long)(progress * 100.0f + 0.5f)];
    appProgressLabel.hidden = NO;
    NSString *speedText = [self speedTextForCurrent:current];
    if ([speedText length] > 0) {
        appSpeedLabel.text = speedText;
        appSpeedLabel.hidden = NO;
    }
    appVersionLabel.text = [self versionTextForRep:_rep sizeText:[QueueTableViewCell stringForByteCount:total]];
}

- (YZQueueRep *)rep {
    return _rep;
}

- (NSString *)versionTextForRep:(YZQueueRep *)rep sizeText:(NSString *)sizeText {
    NSString *versionText = [NSString stringWithFormat:NSLocalizedString(@"Version", nil), rep.version];
    if (sizeText == nil || [sizeText length] == 0) {
        return versionText;
    }
    return [NSString stringWithFormat:@"%@ - %@", versionText, sizeText];
}

- (NSString *)sizeTextForRep:(YZQueueRep *)rep {
    if (rep.path == nil || [[rep.path lowercaseString] hasPrefix:@"http"]) {
        return nil;
    }
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:rep.path error:NULL];
    if (attrs == nil || [attrs fileSize] == 0) {
        return nil;
    }
    return [QueueTableViewCell stringForByteCount:[attrs fileSize]];
}

+ (NSString *)stringForByteCount:(unsigned long long)byteCount {
    double bytes = (double)byteCount;
    NSArray *units = [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", nil];
    NSUInteger unitIndex = 0;
    while (bytes >= 1024.0 && unitIndex < ([units count] - 1)) {
        bytes = bytes / 1024.0;
        unitIndex++;
    }
    if (unitIndex == 0) {
        return [NSString stringWithFormat:@"%llu %@", byteCount, [units objectAtIndex:unitIndex]];
    }
    return [NSString stringWithFormat:@"%.1f %@", bytes, [units objectAtIndex:unitIndex]];
}

- (NSString *)speedTextForCurrent:(NSUInteger)current {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSString *speedText = nil;
    if (_lastProgressTimestamp > 0 && current >= _lastProgressBytes) {
        NSTimeInterval elapsed = now - _lastProgressTimestamp;
        NSUInteger delta = current - _lastProgressBytes;
        if (elapsed >= 0.2 && delta > 0) {
            speedText = [QueueTableViewCell stringForByteRate:(double)delta / elapsed];
        }
    }
    _lastProgressBytes = current;
    _lastProgressTimestamp = now;
    return speedText;
}

+ (NSString *)stringForByteRate:(double)bytesPerSecond {
    NSArray *units = [NSArray arrayWithObjects:@"B/s", @"KB/s", @"MB/s", @"GB/s", nil];
    NSUInteger unitIndex = 0;
    while (bytesPerSecond >= 1024.0 && unitIndex < ([units count] - 1)) {
        bytesPerSecond = bytesPerSecond / 1024.0;
        unitIndex++;
    }
    if (unitIndex == 0) {
        return [NSString stringWithFormat:@"%.0f %@", bytesPerSecond, [units objectAtIndex:unitIndex]];
    }
    return [NSString stringWithFormat:@"%.1f %@", bytesPerSecond, [units objectAtIndex:unitIndex]];
}

@end
