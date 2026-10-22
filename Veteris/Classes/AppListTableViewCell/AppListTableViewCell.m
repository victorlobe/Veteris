//
//  AppListTableViewCell.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "AppListTableViewCell.h"
#import "../Convenience/Convenience.h"

static CGFloat const VeterisRankColumnWidth = 36.0;
static CGFloat const VeterisRankIconGap = 2.0;

@interface AppListTableViewCell ()
@property (nonatomic, strong) UILabel *rankLabel;
@property (nonatomic, assign) CGRect defaultAppImageFrame;
@property (nonatomic, assign) CGRect defaultActivityIndicatorFrame;
@property (nonatomic, assign) CGRect defaultAppNameFrame;
@property (nonatomic, assign) CGRect defaultDeveloperNameFrame;
@property (nonatomic, assign) CGRect defaultVersionFrame;
@property (nonatomic, assign) BOOL defaultFramesCaptured;
@end

@implementation AppListTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)awakeFromNib {
    // Initialization code
    [super awakeFromNib];
    self.getLabel.hidden = !VeterisShowGetLabels();
    self.rankLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.rankLabel.backgroundColor = [UIColor clearColor];
    self.rankLabel.textAlignment = NSTextAlignmentCenter;
    self.rankLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.rankLabel.textColor = [UIColor colorWithWhite:0.35 alpha:0.75];
    self.rankLabel.adjustsFontSizeToFitWidth = YES;
    self.rankLabel.minimumScaleFactor = 0.75;
    self.rankLabel.hidden = YES;
    [self.contentView addSubview:self.rankLabel];
    [self captureDefaultFramesIfNeeded];
}

- (void)captureDefaultFramesIfNeeded {
    if (self.defaultFramesCaptured) {
        return;
    }
    self.defaultAppImageFrame = self.appUIImage.frame;
    self.defaultActivityIndicatorFrame = self.activityIndicator.frame;
    self.defaultAppNameFrame = self.appNameLabel.frame;
    self.defaultDeveloperNameFrame = self.developerNameLabel.frame;
    self.defaultVersionFrame = self.versionLabel.frame;
    self.defaultFramesCaptured = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self captureDefaultFramesIfNeeded];

    BOOL rankingVisible = self.rankLabel != nil && !self.rankLabel.hidden;
    CGFloat shift = rankingVisible ? VeterisRankColumnWidth : 0.0;
    CGFloat appImageShift = rankingVisible
        ? shift - self.defaultAppImageFrame.origin.x + VeterisRankIconGap
        : 0.0;
    CGRect appImageFrame = self.defaultAppImageFrame;
    appImageFrame.origin.x += appImageShift;
    self.appUIImage.frame = appImageFrame;

    CGRect activityIndicatorFrame = self.defaultActivityIndicatorFrame;
    activityIndicatorFrame.origin.x += appImageShift;
    self.activityIndicator.frame = activityIndicatorFrame;

    CGRect appNameFrame = self.defaultAppNameFrame;
    appNameFrame.origin.x += shift;
    appNameFrame.size.width = MAX(0.0, appNameFrame.size.width - shift);
    self.appNameLabel.frame = appNameFrame;

    CGRect developerNameFrame = self.defaultDeveloperNameFrame;
    developerNameFrame.origin.x += shift;
    developerNameFrame.size.width = MAX(0.0, developerNameFrame.size.width - shift);
    self.developerNameLabel.frame = developerNameFrame;

    CGRect versionFrame = self.defaultVersionFrame;
    versionFrame.origin.x += shift;
    versionFrame.size.width = MAX(0.0, versionFrame.size.width - shift);
    self.versionLabel.frame = versionFrame;

    self.rankLabel.frame = CGRectMake(0.0, 0.0, VeterisRankColumnWidth, CGRectGetHeight(self.contentView.bounds));
}

- (void)setRankingPosition:(NSUInteger)position {
    [self captureDefaultFramesIfNeeded];
    self.rankLabel.text = position > 0 ? [NSString stringWithFormat:@"#%lu", (unsigned long)position] : nil;
    self.rankLabel.hidden = position == 0;
    [self setNeedsLayout];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self setRankingPosition:0];
    self.appUIImage.image = nil;
    self.versionLabel.text = nil;
    self.versionLabel.hidden = YES;
    self.getLabel.hidden = !VeterisShowGetLabels();
}

@end
