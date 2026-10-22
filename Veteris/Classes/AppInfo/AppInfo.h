//
//  AppInfo.h
//  Veteris
//
//  Created by electimon on 6/8/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Application;
@class Version;
@class VLInstallButton;

extern NSString * const AppInfoInstalledApplicationsDidRefreshNotification;

@interface AppInfo : UIViewController <UIActionSheetDelegate, UITableViewDataSource, UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UIControl *getButton;
@property (weak, nonatomic) IBOutlet UIImageView *appUIImage;
@property (weak, nonatomic) IBOutlet UILabel *appNameLabel;
@property (weak, nonatomic) IBOutlet UIButton *appDeveloperNameButton;
@property (strong, nonatomic) UILabel *appDescriptionLabel;
@property (strong, nonatomic) UILabel *descriptionLabel;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
- (void)initialize:(NSString *)bundleID;
- (void)initialize:(NSString *)bundleID developer:(NSString *)developer name:(NSString *)name image:(UIImage *)image;
- (void)initializeVersionInfoWithApplication:(Application *)application version:(Version *)version image:(UIImage *)image;
+ (void)refreshInstalledApplicationCache;
// Bundle id -> installed app info from the last scan; nil before the first scan finished.
+ (NSDictionary *)installedApplicationsSnapshot;
+ (BOOL)isApplicationInstalled:(Application *)application;
+ (BOOL)isVersionInstalled:(Version *)version forApplication:(Application *)application;
@end
