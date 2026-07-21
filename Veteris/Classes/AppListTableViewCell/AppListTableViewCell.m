//
//  AppListTableViewCell.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "AppListTableViewCell.h"

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
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.appUIImage.image = nil;
    self.versionLabel.text = nil;
    self.versionLabel.hidden = YES;
}

@end
