//
//  SearchTableViewCell.m
//  Veteris
//
//  Created by electimon on 6/9/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "SearchTableViewCell.h"
#import <QuartzCore/QuartzCore.h>

@implementation SearchTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.8419164419 green:0.8418912888 blue:0.8419055343 alpha:1.0];

        self.backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.backgroundImageView.image = [UIImage imageNamed:@"AppCellBG.png"];
        self.backgroundImageView.contentMode = UIViewContentModeScaleToFill;
        [self.contentView addSubview:self.backgroundImageView];

        self.appUIImage = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.appUIImage.contentMode = UIViewContentModeScaleToFill;
        self.appUIImage.layer.masksToBounds = YES;
        self.appUIImage.layer.cornerRadius = 13.0;
        [self.contentView addSubview:self.appUIImage];

        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.activityIndicator.hidesWhenStopped = YES;
        self.activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
        if ([self.activityIndicator respondsToSelector:@selector(setColor:)]) {
            self.activityIndicator.color = [UIColor colorWithWhite:0.33333333333333331 alpha:1.0];
        }

        self.developerNameLabel = [self subtitleLabel];
        [self.contentView addSubview:self.developerNameLabel];

        self.versionLabel = [self subtitleLabel];
        self.versionLabel.hidden = YES;
        [self.contentView addSubview:self.versionLabel];

        self.getLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.getLabel.backgroundColor = [UIColor clearColor];
        self.getLabel.alpha = 0.60000002384185791;
        self.getLabel.font = [UIFont boldSystemFontOfSize:14.0];
        self.getLabel.textColor = [UIColor colorWithRed:0.2784313725 green:0.2784313725 blue:0.2784313725 alpha:1.0];
        self.getLabel.shadowColor = [UIColor whiteColor];
        self.getLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        self.getLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.getLabel.text = @"GET";
        [self.contentView addSubview:self.getLabel];

        self.appNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.appNameLabel.backgroundColor = [UIColor clearColor];
        self.appNameLabel.font = [UIFont boldSystemFontOfSize:17.0];
        self.appNameLabel.textColor = [UIColor colorWithRed:0.27843137254901962 green:0.27843137254901962 blue:0.27843137254901962 alpha:1.0];
        self.appNameLabel.shadowColor = [UIColor whiteColor];
        self.appNameLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        self.appNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.appNameLabel.numberOfLines = 0;
        self.appNameLabel.minimumFontSize = 5.0;
        if ([self.appNameLabel respondsToSelector:@selector(setAdjustsLetterSpacingToFitWidth:)]) {
            self.appNameLabel.adjustsLetterSpacingToFitWidth = YES;
        }
        [self.contentView addSubview:self.appNameLabel];

        [self.contentView addSubview:self.activityIndicator];
    }
    return self;
}

- (UILabel *)subtitleLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.backgroundColor = [UIColor clearColor];
    label.alpha = 0.75;
    label.font = [UIFont fontWithName:@"Helvetica" size:11.0];
    label.textColor = [UIColor colorWithRed:0.53725490196078429 green:0.53725490196078429 blue:0.53725490196078429 alpha:1.0];
    label.shadowColor = [UIColor whiteColor];
    label.shadowOffset = CGSizeMake(0.0, 1.0);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.minimumFontSize = 5.0;
    if ([label respondsToSelector:@selector(setAdjustsLetterSpacingToFitWidth:)]) {
        label.adjustsLetterSpacingToFitWidth = YES;
    }
    return label;
}

- (void)awakeFromNib {
    [super awakeFromNib];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.backgroundImageView.frame = CGRectMake(0.0, 0.0, 320.0, 78.0);
    self.appUIImage.frame = CGRectMake(8.0, 8.0, 62.0, 62.0);
    self.developerNameLabel.frame = CGRectMake(78.0, 8.0, 184.0, 12.0);
    self.versionLabel.frame = CGRectMake(78.0, 58.0, 184.0, 12.0);
    self.getLabel.frame = CGRectMake(270.0, 29.0, 30.0, 19.0);
    self.appNameLabel.frame = CGRectMake(78.0, 18.0, 184.0, 42.0);
    self.activityIndicator.frame = CGRectMake(21.0, 20.0, 37.0, 37.0);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.appUIImage.image = nil;
    self.appNameLabel.text = nil;
    self.developerNameLabel.text = nil;
    self.versionLabel.text = nil;
    self.versionLabel.hidden = YES;
    self.getLabel.text = @"GET";
    [self.activityIndicator stopAnimating];
}

@end
