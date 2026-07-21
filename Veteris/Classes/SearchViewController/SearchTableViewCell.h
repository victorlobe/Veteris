//
//  SearchTableViewCell.h
//  Veteris
//
//  Created by electimon on 6/9/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SearchTableViewCell : UITableViewCell
@property (nonatomic, strong) UILabel *appNameLabel;
@property (nonatomic, strong) UILabel *developerNameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *getLabel;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIImageView *appUIImage;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@end
