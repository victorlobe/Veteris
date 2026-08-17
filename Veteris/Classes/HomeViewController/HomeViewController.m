//
//  HomeViewController.m
//  Veteris
//
//  Created by electimon on 1/2/24.
//  Copyright (c) 2024 1pwn. All rights reserved.
//

#import "HomeViewController.h"
#import "../HomeTableViewCell/HomeTableViewCell.h"
#import "../Convenience/Convenience.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "InAppSettingsKit/Controllers/IASKAppSettingsViewController.h"
#import "InAppSettingsKit/Models/IASKSpecifier.h"
#import "InAppSettingsKit/Models/IASKSettingsReader.h"
#import <SVProgressHUD/SVProgressHUD.h>
#import "../../Reachability/Reachability.h"
#import "../YZTabBar/YZTabBar.h"
#import "../ProtoStack.h"
#import "../SettingsReset/VeterisResetController.h"

@implementation HomeViewController {
    NSDictionary *apiResponse;
    NSArray *entries;
    UIBarButtonItem *settingsButton;
    IASKAppSettingsViewController *currentSettingsViewController;
    NSUInteger maintainerTapCount;
    NSString *currentBadgeName;
}
@synthesize backgroundImage;

#define isiPhone5  ([[UIScreen mainScreen] bounds].size.height == 568)?TRUE:FALSE

static NSString *const VeterisMaintainerSettingsKey = @"credits_maintainer";
static NSString *const VeterisDevSettingsTitleKey = @"dev_settings_title";
static NSString *const VeterisDevSettingsMenuKey = @"dev_settings_menu";
static NSString *const VeterisLanguageOverrideKey = @"veteris_language_override";
static NSString *const VeterisLowMemoryModeEnabledKey = @"veteris_low_memory_mode_enabled";
static NSString *const VeterisArchiveDownloadSegmentsKey = @"veteris_archive_download_segments";
static NSString *const VeterisResetSettingsKey = @"reset_veteris_all";
static NSString *const VeterisDevSecretCode = @"VictorIsKing";
static NSInteger const VeterisDevCodeAlertTag = 8001;

- (void)applyRandomBadgeImage
{
    NSArray *badgeNames = @[
        @"honoringElectimonBadge",
        @"thankYouElectimonBadge",
        @"thankYouElectimonHeartBadge",
        @"electimonIsTheBestBadge",
        @"oneLoveBadge",
        @"welcomeBackBadge",
        @"youAreAwesomeBadge",
    ];
    NSString *badgeName = nil;
    if ([badgeNames count] > 1) {
        do {
            badgeName = [badgeNames objectAtIndex:arc4random_uniform((uint32_t)[badgeNames count])];
        } while ([badgeName isEqualToString:currentBadgeName]);
    } else {
        badgeName = [badgeNames lastObject];
    }
    currentBadgeName = badgeName;
    self.badgeImageView.image = [UIImage imageNamed:badgeName];
}

- (void)shuffleBadgeFromHomeIconTap:(UITapGestureRecognizer *)gestureRecognizer
{
    [self applyRandomBadgeImage];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self applySmallDeviceHomeFramesIfNeeded];
    self.navigationController.title = NSLocalizedString(@"Home", @"Home");
    self.navigationItem.title = NSLocalizedString(@"Home", @"Home");
    self.welcomeLabel.text = NSLocalizedString(@"WelcomeToVeteris", @"WelcomeToVeteris");
    [self.welcomeLabel.text sizeWithFont:self.welcomeLabel.font minFontSize:10 actualFontSize:nil forWidth:self.welcomeLabel.frame.size.width lineBreakMode:NSLineBreakByWordWrapping];
    self.tableView.backgroundView = nil;
    self.tableView.layer.borderColor = [UIColor colorWithWhite:0.6 alpha:1].CGColor;
    self.tableView.layer.borderWidth = 1;
    self.tableView.layer.cornerRadius = 8;
    [self setupBottomBackgroundView];
    entries = nil;
    self.appIconImageView.userInteractionEnabled = YES;
    UITapGestureRecognizer *appIconTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shuffleBadgeFromHomeIconTap:)];
    [self.appIconImageView addGestureRecognizer:appIconTapRecognizer];
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
    // Funny easter egg
    [self becomeFirstResponder];

    settingsButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Settings", nil) style:UIBarButtonItemStylePlain target:self action:@selector(showSettings)];
    self.navigationItem.leftBarButtonItem = settingsButton;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reconfigure:) name:kPleaseReloadThemes object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadNews:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingChanged:) name:kIASKAppSettingChanged object:nil];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self applySmallDeviceHomeFramesIfNeeded];
}

- (void)applySmallDeviceHomeFramesIfNeeded
{
    if (!isiPhone5) {
        self.appIconImageView.frame = CGRectMake(60, 20, 201, 251);
        self.badgeImageView.frame = CGRectMake(156, 21, 75, 64);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [self applyRandomBadgeImage];
    // Warn user if no internet
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus status = [reachability currentReachabilityStatus];
    if (status == NotReachable) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"NoInternet", nil) message:NSLocalizedString(@"NoInternetMessage", nil) delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
        [alert show];
    } else {
        [SVProgressHUD showWithStatus:NSLocalizedString(@"Loading", @"") maskType:SVProgressHUDMaskTypeBlack];
        [self loadNews:nil];
    }
    debugLog(@"Reachability: %lu", (long)status);
    [self setupTopBackgroundView:[getDelegate().themeManager homeShimmerColorForCurrentTheme]];
    // TEMP: changelog disabled
    // [VAPIHelper showWhatsNewIfNeeded];
    [super viewWillAppear:animated];
}

- (void)loadNews:(NSNotification *)notification {
    [VAPISS getMessage:@"news" completion:^(NSData *data, NSError *error){
        if (error == nil) {
            entries = (NSArray *)(CFBridgingRelease(decode([data bytes], [data length], NewsResponse)));
            [self.tableView reloadData];
            [SVProgressHUD dismiss];
        } else {
            [SVProgressHUD dismiss];
            alert(NSLocalizedString(@"Oops", @""), NSLocalizedString(@"ServerContactError", nil), VAPIHelperErrorNetwork);
        }
    }];
}

- (void)showSettings {
    IASKAppSettingsViewController *appSettingsViewController = [[IASKAppSettingsViewController alloc] init];
    currentSettingsViewController = appSettingsViewController;
    maintainerTapCount = 0;
    appSettingsViewController.delegate = self;
    appSettingsViewController.showDoneButton = NO;
    appSettingsViewController.showCreditsFooter = NO;
    appSettingsViewController.title = NSLocalizedString(@"Settings", @"");
    appSettingsViewController.hiddenKeys = [self hiddenSettingsKeys];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:appSettingsViewController];
    navController.navigationBar.barStyle = UIBarStyleBlack;
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", nil) style:UIBarButtonItemStylePlain target:self action:@selector(dismissSettingsAnimated)];
    doneButton.style = UIBarButtonItemStyleBordered;
    appSettingsViewController.navigationItem.rightBarButtonItem = doneButton;
    [getDelegate().themeManager applyThemeToNavigationBar:navController.navigationBar];
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.75];
    [UIView setAnimationTransition:UIViewAnimationTransitionCurlUp forView:getDelegate().window cache:NO];
    UINavigationController *topNavController = (UINavigationController *)((UITabBarController *)getDelegate().window.rootViewController).selectedViewController;
    [topNavController presentViewController:navController animated:NO completion:nil];
    [UIView commitAnimations];
}

- (void)dismissSettingsAnimated {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.75];
    [UIView setAnimationTransition:UIViewAnimationTransitionCurlDown forView:getDelegate().window cache:NO];
    [getDelegate().window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    [UIView commitAnimations];
    currentSettingsViewController = nil;
    maintainerTapCount = 0;
    UINavigationController *topNavController = (UINavigationController *)((UITabBarController *)getDelegate().window.rootViewController).selectedViewController;
    [getDelegate().themeManager applyThemeToNavigationBar:topNavController.navigationBar];
    if ([getDelegate().themeManager deviceSupportsThemes]) {
        settingsButton.tintColor = [getDelegate().themeManager tintColorForCurrentTheme];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSet *)hiddenSettingsKeys {
    NSMutableSet *hiddenKeys = [NSMutableSet set];
    if (![getDelegate().themeManager deviceSupportsThemes]) {
        [hiddenKeys addObject:@"theme_preference"];
        [hiddenKeys addObject:@"customization_title"];
    }
    if (![VAPIHelper isDevModeEnabled]) {
        [hiddenKeys addObject:VeterisDevSettingsTitleKey];
        [hiddenKeys addObject:VeterisDevSettingsMenuKey];
    }
    return hiddenKeys;
}

- (void)settingsViewControllerDidEnd:(IASKAppSettingsViewController *)sender {
    [self dismissSettingsAnimated];
}

- (void)settingsViewController:(IASKAppSettingsViewController *)sender buttonTappedForSpecifier:(IASKSpecifier *)specifier {
    if ([[specifier key] isEqualToString:VeterisResetSettingsKey]) {
        [VeterisResetController confirmReset:sender forKey:[specifier key]];
        return;
    }
    if (![[specifier key] isEqualToString:VeterisMaintainerSettingsKey]) {
        return;
    }
    maintainerTapCount++;
    if (maintainerTapCount >= 10) {
        maintainerTapCount = 0;
        [self showDevCodeAlert];
    }
}

- (void)showDevCodeAlert {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Secret menu"
                                                        message:@"Enter your super secret code"
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                              otherButtonTitles:NSLocalizedString(@"Ok", nil), nil];
    alertView.tag = VeterisDevCodeAlertTag;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *textField = [alertView textFieldAtIndex:0];
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.secureTextEntry = YES;
    [alertView show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != VeterisDevCodeAlertTag || buttonIndex == alertView.cancelButtonIndex) {
        return;
    }
    NSString *code = [[alertView textFieldAtIndex:0] text];
    if ([code isEqualToString:VeterisDevSecretCode]) {
        [VAPIHelper setDevModeEnabled:YES];
        [VAPIHelper resetNetworkState];
        [currentSettingsViewController setHiddenKeys:[self hiddenSettingsKeys] animated:YES];
        [[[UIAlertView alloc] initWithTitle:@"Dev Mode"
                                    message:@"Enabled"
                                   delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                          otherButtonTitles:nil] show];
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Dev Mode"
                                    message:@"Invalid code"
                                   delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                          otherButtonTitles:nil] show];
    }
}

- (void)reconfigure:(NSNotification *)notification {
    debugLog(@"Reloading theme for HomeViewController");
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
    [self setupTopBackgroundView:[getDelegate().themeManager homeShimmerColorForCurrentTheme]];
}

- (void)settingChanged:(NSNotification *)notification {
    if ([[notification object] isEqualToString:VeterisArchiveDownloadSegmentsKey]) {
        NSInteger streamCount = [[[notification userInfo] objectForKey:VeterisArchiveDownloadSegmentsKey] integerValue];
        if (streamCount > 4 && [VAPIHelper usesLowMemoryDownloadMode]) {
            NSString *message = [VAPIHelper isVeryLowMemoryDevice] ?
                NSLocalizedString(@"VeryLowMemoryStreamsWarning", nil) :
                NSLocalizedString(@"LowMemoryStreamsWarning", nil);
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"DownloadStreamsAlertTitle", nil)
                                        message:message
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                              otherButtonTitles:nil] show];
        }
        return;
    }
    if ([[notification object] isEqualToString:VeterisLowMemoryModeEnabledKey]) {
        BOOL enabled = [[[notification userInfo] objectForKey:VeterisLowMemoryModeEnabledKey] boolValue];
        NSInteger streamCount = [[NSUserDefaults standardUserDefaults] integerForKey:VeterisArchiveDownloadSegmentsKey];
        if (enabled && streamCount > 4) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"DownloadStreamsAlertTitle", nil)
                                        message:NSLocalizedString(@"LowMemoryManualStreamsWarning", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                              otherButtonTitles:nil] show];
        }
        return;
    }
    if ([[notification object] isEqualToString:VeterisLanguageOverrideKey]) {
        [VAPIHelper applyLanguageOverride];
        [[[UIAlertView alloc] initWithTitle:@"Language"
                                    message:@"Restart Veteris to reload all localized screens."
                                   delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"Ok", nil)
                          otherButtonTitles:nil] show];
    }
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    [super motionBegan:motion withEvent:event];
    if(event.subtype == UIEventSubtypeMotionShake)
    {
        [self setupTopBackgroundView:[UIColor colorWithRed:arc4random_uniform(255)/255.0f green:arc4random_uniform(255)/255.0f blue:arc4random_uniform(255)/255.0f alpha:.7]];
    }
}

- (void)setupTopBackgroundView:(UIColor *)color {
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            [layer removeFromSuperlayer];
            break;
        }
    }
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.backgroundView.bounds;
    gradient.colors = @[
                        (id)[UIColor blackColor].CGColor,
                        (id)[UIColor blackColor].CGColor,
                        (id)color.CGColor,
                        ];
    gradient.locations = @[
                           @0,
                           @0.25,
                           @0.7
                           ];
    [self.view.layer insertSublayer:gradient atIndex:0];
    self.backgroundImage.image = [self imageWithColor:[UIColor blackColor] size:self.backgroundImage.bounds.size];
    self.backgroundImage.alpha = 0.06;
}

- (void)setupBottomBackgroundView {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.backgroundView.bounds;
    gradient.colors = @[
                        (id)[UIColor darkGrayColor].CGColor,
                        (id)[UIColor blackColor].CGColor,
                        (id)[UIColor blackColor].CGColor,
                        ];
    gradient.locations = @[
                           @0,
                           @0.2,
                           @1
                           ];
    [self.backgroundView.layer insertSublayer:gradient atIndex:0];
}

- (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (BOOL)canBecomeFirstResponder
{
#ifdef DEBUG
    bool debug = true;
#else
    bool debug = false;
#endif
    return !debug;
}

#pragma mark UITableView Delegate Methods
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (entries == nil) {
        return 0;
    }
    debugLog(@"Returning %lu", (unsigned long)[entries count]);
    return [entries count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (entries == nil || indexPath.row >= [entries count]) {
        return 140.0f;
    }

    NewsPost *post = [entries objectAtIndex:indexPath.row];
    return [HomeTableViewCell heightForContentText:post.body tableWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"HomeTableViewCell";
    HomeTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[HomeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    NewsPost *post = [entries objectAtIndex:indexPath.row];
    if (post != nil) {
        cell.headlineLabel.text = post.title;
        cell.dateLabel.text = post.date;
        cell.contentLabel.text = post.body;
        [cell setNeedsLayout];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //Change the selected background view of the cell.
    NewsPost *post = [entries objectAtIndex:indexPath.row];
    if ([post.link length] > 0) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:((NewsPost*)[entries objectAtIndex:indexPath.row]).link]];
    } else {
        alert(NSLocalizedString(@"Oops", @""), NSLocalizedString(@"NoLink", @""), VAPIHelperErrorUnknown);
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
