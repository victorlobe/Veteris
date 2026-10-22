//
//  AppDelegate.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "AppDelegate.h"
#include <sys/sysctl.h>
#import "Classes/VAPIHelper/VAPIHelper.h"
#import "Classes/QueueTableViewController/QueueTableViewController.h"
#import "Clutch/ZipArchive.h"
#import "TargetConditionals.h"
#import <QuartzCore/QuartzCore.h>
#import "Classes/YZApplication/YZApplication.h"
#import "RRFPSBar/RRFPSBar.h"
#import "Classes/YZQueue/YZQueueManager.h"
#import "Classes/YZQueue/YZQueueNotifier.h"
#import "Classes/YZQueue/YZDownloadResumeStore.h"
#import <KSCrash.h>
#import <KSCrashInstallation.h>
#import "Classes/VAPIHelper/KSCrashInstallationVAPI.h"
#import "Classes/DebugTextView/DebugTextView.h"
#import "Classes/Convenience/Convenience.h"
#import "Classes/Favorites/FavoritesTableViewController.h"
#import "Classes/Updates/UpdatesTableViewController.h"
#import "Classes/Updates/VeterisUpdatesManager.h"
#import "Classes/AppsTableViewController/AppsTableViewController.h"
#import "Classes/AppInfo/AppInfo.h"

static NSString *VeterisLastHandledURLString = nil;
static NSTimeInterval VeterisLastHandledURLTime = 0.0;
static NSString *const VeterisTabOrderDefaultsKey = @"VeterisTabOrder";
static NSString *const VeterisHomeTabIdentifier = @"HomeViewController";
static NSString *const VeterisDownloadsTabIdentifier = @"Downloads";
static NSString *const VeterisTop25TabIdentifier = @"Top25";
static NSString *const VeterisUpdatesTabIdentifier = @"Updates";
static NSString *const VeterisShuffleTabIdentifier = @"Shuffle";
static NSString *const VeterisAppSyncAlertIgnoreDateKey = @"VeterisAppSyncAlertIgnoreDate";
static const NSTimeInterval VeterisAppSyncAlertIgnoreDuration = 24.0 * 60.0 * 60.0;

@interface VeterisAppSyncAlertDelegate : NSObject <UIAlertViewDelegate>
@end

@implementation VeterisAppSyncAlertDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == [alertView cancelButtonIndex]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]]
                                                  forKey:VeterisAppSyncAlertIgnoreDateKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

@end

static VeterisAppSyncAlertDelegate *VeterisSharedAppSyncAlertDelegate(void) {
    static VeterisAppSyncAlertDelegate *delegate = nil;
    if (delegate == nil) {
        delegate = [[VeterisAppSyncAlertDelegate alloc] init];
    }
    return delegate;
}

static BOOL VeterisAppSyncIsInstalled(void) {
    NSArray *candidatePaths = [NSArray arrayWithObjects:
        @"/Library/MobileSubstrate/DynamicLibraries/AppSync.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-installd.dylib",
        @"/Library/MobileSubstrate/DynamicLibraries/AppSyncUnified-FrontBoard.dylib",
        nil];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in candidatePaths) {
        if ([fileManager fileExistsAtPath:path]) {
            return YES;
        }
    }
    return NO;
}

static BOOL VeterisIsIOS5OrNewer(void) {
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    NSArray *components = [systemVersion componentsSeparatedByString:@"."];
    return [components count] > 0 && [[components objectAtIndex:0] integerValue] >= 5;
}

static void VeterisShowAppSyncAlertIfNeeded(void) {
    id ignoredAtValue = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisAppSyncAlertIgnoreDateKey];
    NSTimeInterval ignoredAt = [ignoredAtValue respondsToSelector:@selector(doubleValue)] ? [ignoredAtValue doubleValue] : 0.0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!VeterisIsIOS5OrNewer() || VeterisAppSyncIsInstalled() ||
        (ignoredAt > 0.0 && now - ignoredAt < VeterisAppSyncAlertIgnoreDuration)) {
        return;
    }

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedStringWithDefaultValue(@"AppSyncRequiredTitle", nil, [NSBundle mainBundle], @"AppSync Required", nil)
                                                    message:NSLocalizedStringWithDefaultValue(@"AppSyncRequiredMessage", nil, [NSBundle mainBundle], @"Please install AppSync Unified from Cydia before using Veteris to install apps. Reboot your device after installation.", nil)
                                                   delegate:VeterisSharedAppSyncAlertDelegate()
                                          cancelButtonTitle:NSLocalizedStringWithDefaultValue(@"AppSyncIgnore", nil, [NSBundle mainBundle], @"Ignore", nil)
                                          otherButtonTitles:NSLocalizedString(@"OK", nil), nil];
    [alert show];
}

static NSString *VeterisURLDecodedString(NSString *value) {
    if (value == nil) {
        return nil;
    }
    NSString *decoded = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return decoded ?: value;
}

static UIImage *VeterisTintedImage(UIImage *image, UIColor *color) {
    if (image == nil) {
        return nil;
    }
    if (color == nil) {
        return image;
    }

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawAtPoint:CGPointZero];
    [color setFill];
    UIRectFillUsingBlendMode((CGRect){CGPointZero, image.size}, kCGBlendModeSourceIn);
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if ([tintedImage respondsToSelector:@selector(imageWithRenderingMode:)]) {
        return [tintedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return tintedImage ?: image;
}

@implementation AppDelegate
@synthesize themeManager;

- (void)updateQueueTabBadge {
    dispatch_async(dispatch_get_main_queue(), ^{
        UITabBarController *tabBarController = (UITabBarController *)self.window.rootViewController;
        if (![tabBarController isKindOfClass:[UITabBarController class]]) {
            return;
        }
        NSUInteger activeDownloads = [YZQueueManager activeDownloadsCount];
        NSString *badgeValue = activeDownloads > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)activeDownloads] : nil;
        for (UIViewController *viewController in tabBarController.viewControllers) {
            if (![viewController isKindOfClass:[UINavigationController class]]) {
                continue;
            }
            UINavigationController *navigationController = (UINavigationController *)viewController;
            UIViewController *rootController = [navigationController.viewControllers count] > 0 ? [navigationController.viewControllers objectAtIndex:0] : nil;
            if ([rootController isKindOfClass:[QueueTableViewController class]]) {
                navigationController.tabBarItem.badgeValue = badgeValue;
                break;
            }
        }
    });
}

- (void)updateUpdatesTabBadge {
    UITabBarController *tabBarController = (UITabBarController *)self.window.rootViewController;
    if (![tabBarController isKindOfClass:[UITabBarController class]]) {
        return;
    }
    NSUInteger updateCount = [[[VeterisUpdatesManager sharedManager] availableUpdates] count];
    UIViewController *updatesController = [self viewControllerWithIdentifier:VeterisUpdatesTabIdentifier inViewControllers:tabBarController.viewControllers];
    updatesController.tabBarItem.badgeValue = updateCount > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)updateCount] : nil;
}

- (void)handleQueueBadgeNotification:(NSNotification *)notification {
    YZQueueRep *rep = (YZQueueRep *)notification.object;
    [self updateQueueTabBadge];
    if ([rep respondsToSelector:@selector(state)] && [rep state] == YZRepStateInstalled) {
        [AppInfo refreshInstalledApplicationCache];
    }
}

- (UIViewController *)rootControllerForNavigationController:(UINavigationController *)navigationController {
    return [navigationController.viewControllers count] > 0 ? [navigationController.viewControllers objectAtIndex:0] : nil;
}

- (NSString *)tabIdentifierForViewController:(UIViewController *)viewController {
    if (![viewController isKindOfClass:[UINavigationController class]]) {
        return NSStringFromClass([viewController class]);
    }

    UINavigationController *navigationController = (UINavigationController *)viewController;
    UIViewController *rootController = [self rootControllerForNavigationController:navigationController];
    if ([rootController isKindOfClass:[QueueTableViewController class]]) {
        return VeterisDownloadsTabIdentifier;
    }
    if ([rootController isKindOfClass:[FavoritesTableViewController class]]) {
        return @"Favorites";
    }
    if ([rootController isKindOfClass:[UpdatesTableViewController class]]) {
        return VeterisUpdatesTabIdentifier;
    }
    if ([rootController isKindOfClass:[AppsTableViewController class]]) {
        AppsTableViewController *appsController = (AppsTableViewController *)rootController;
        if ([appsController.listingEndpoint hasPrefix:@"listing/top"]) {
            return VeterisTop25TabIdentifier;
        }
        return appsController.showsRefreshButton ? @"Shuffle" : @"AllApps";
    }

    return NSStringFromClass([rootController class]);
}

- (NSArray *)tabOrderForViewControllers:(NSArray *)viewControllers {
    NSMutableArray *tabOrder = [NSMutableArray array];
    for (UIViewController *viewController in viewControllers) {
        NSString *identifier = [self tabIdentifierForViewController:viewController];
        if (identifier != nil) {
            [tabOrder addObject:identifier];
        }
    }
    return tabOrder;
}

- (NSArray *)viewControllers:(NSArray *)viewControllers orderedBySavedTabOrder:(NSArray *)savedTabOrder {
    if ([savedTabOrder count] == 0) {
        return viewControllers;
    }

    NSMutableArray *effectiveSavedTabOrder = [NSMutableArray arrayWithArray:savedTabOrder];
    if ([self viewControllerWithIdentifier:VeterisTop25TabIdentifier inViewControllers:viewControllers] != nil
        && ![effectiveSavedTabOrder containsObject:VeterisTop25TabIdentifier]) {
        NSUInteger favoritesIndex = [effectiveSavedTabOrder indexOfObject:@"Favorites"];
        if (favoritesIndex != NSNotFound) {
            [effectiveSavedTabOrder insertObject:VeterisTop25TabIdentifier atIndex:favoritesIndex + 1];
        } else {
            NSUInteger categoriesIndex = [effectiveSavedTabOrder indexOfObject:@"CategoriesTableViewController"];
            if (categoriesIndex != NSNotFound) {
                [effectiveSavedTabOrder insertObject:VeterisTop25TabIdentifier atIndex:categoriesIndex];
            }
        }
    }

    NSMutableDictionary *viewControllersByIdentifier = [NSMutableDictionary dictionary];
    for (UIViewController *viewController in viewControllers) {
        NSString *identifier = [self tabIdentifierForViewController:viewController];
        if (identifier != nil && [viewControllersByIdentifier objectForKey:identifier] == nil) {
            [viewControllersByIdentifier setObject:viewController forKey:identifier];
        }
    }

    NSMutableArray *orderedViewControllers = [NSMutableArray array];
    for (NSString *identifier in effectiveSavedTabOrder) {
        UIViewController *viewController = [viewControllersByIdentifier objectForKey:identifier];
        if (viewController != nil && ![orderedViewControllers containsObject:viewController]) {
            [orderedViewControllers addObject:viewController];
        }
    }

    for (UIViewController *viewController in viewControllers) {
        if (![orderedViewControllers containsObject:viewController]) {
            [orderedViewControllers addObject:viewController];
        }
    }

    return [orderedViewControllers count] == [viewControllers count] ? orderedViewControllers : viewControllers;
}

- (UIViewController *)viewControllerWithIdentifier:(NSString *)identifier inViewControllers:(NSArray *)viewControllers {
    for (UIViewController *viewController in viewControllers) {
        if ([[self tabIdentifierForViewController:viewController] isEqualToString:identifier]) {
            return viewController;
        }
    }
    return nil;
}

- (BOOL)selectTabWithIdentifier:(NSString *)identifier inTabBarController:(UITabBarController *)tabBarController {
    NSUInteger index = 0;
    for (UIViewController *viewController in tabBarController.viewControllers) {
        if ([[self tabIdentifierForViewController:viewController] isEqualToString:identifier]) {
            tabBarController.selectedIndex = index;
            return YES;
        }
        index++;
    }
    return NO;
}

- (void)configureDefaultPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL changed = NO;

    NSDictionary *appSubtitleDefaults = @{
        VeterisAppCellSubtitleModeKey : @"Global",
        VeterisAppCellSubtitleGlobalPreferenceKey : VeterisAppCellSubtitleDeveloperNameValue,
        VeterisAppCellSubtitlePreferenceKeyForArea(VeterisAppCellSubtitleAreaList) : VeterisAppCellSubtitleDeveloperNameValue,
        VeterisAppCellSubtitlePreferenceKeyForArea(VeterisAppCellSubtitleAreaSearch) : VeterisAppCellSubtitleDeveloperNameValue,
        VeterisAppCellSubtitlePreferenceKeyForArea(VeterisAppCellSubtitleAreaRelated) : VeterisAppCellSubtitleDeveloperNameValue,
        VeterisAppCellSubtitlePreferenceKeyForArea(VeterisAppCellSubtitleAreaQueue) : VeterisAppCellSubtitleDeveloperNameValue
    };

    for (NSString *key in appSubtitleDefaults) {
        if ([defaults objectForKey:key] == nil) {
            [defaults setObject:[appSubtitleDefaults objectForKey:key] forKey:key];
            changed = YES;
        }
    }

    if ([defaults objectForKey:@"veteris_crash_reporting_enabled"] == nil) {
        [defaults setBool:YES forKey:@"veteris_crash_reporting_enabled"];
        changed = YES;
    }
    if ([defaults objectForKey:@"veteris_home_icon_badge_enabled"] == nil) {
        [defaults setBool:YES forKey:@"veteris_home_icon_badge_enabled"];
        changed = YES;
    }
    if ([defaults objectForKey:YZDownloadNotificationsEnabledKey] == nil) {
        [defaults setBool:YES forKey:YZDownloadNotificationsEnabledKey];
        changed = YES;
    }
    if ([defaults objectForKey:YZBackgroundStatusNotificationsEnabledKey] == nil) {
        [defaults setBool:YES forKey:YZBackgroundStatusNotificationsEnabledKey];
        changed = YES;
    }

    if ([VeterisMemoryProfile prepareStoredPreferences]) {
        changed = YES;
    }
    if (changed) {
        [defaults synchronize];
    }
    [VeterisMemoryProfile updateActiveLevelPreference];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self configureDefaultPreferences];
    [VAPIHelper applyLanguageOverride];
    themeManager = [ThemeManager sharedInstance];
    UINavigationBar *moreNaviBar = [((UITabBarController *)self.window.rootViewController) moreNavigationController].navigationBar;
    [moreNaviBar setBarStyle:UIBarStyleBlack];
    [moreNaviBar setTranslucent:false];

    UINavigationController *queuedNaviController = [[UINavigationController alloc] initWithRootViewController:[[QueueTableViewController alloc] init]];
    queuedNaviController.navigationBar.barStyle = UIBarStyleBlack;
    queuedNaviController.tabBarItem = [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemDownloads tag:0];
    queuedNaviController.title = NSLocalizedString(@"Downloads", @"Downloads");
    queuedNaviController.tabBarItem.title = NSLocalizedString(@"Downloads", @"Downloads");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleQueueBadgeNotification:) name:@"YZQueueRepStateChange" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUpdatesTabBadge) name:VeterisUpdatesDidChangeNotification object:nil];
    UINavigationController *favoritesNaviController = [[UINavigationController alloc] initWithRootViewController:[[FavoritesTableViewController alloc] init]];
    favoritesNaviController.navigationBar.barStyle = UIBarStyleBlack;
    favoritesNaviController.tabBarItem = [[UITabBarItem alloc] initWithTabBarSystemItem:UITabBarSystemItemFavorites tag:0];
    favoritesNaviController.tabBarItem.title = NSLocalizedString(@"Favorites", @"Favorites");
    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:[NSBundle mainBundle]];
    AppsTableViewController *randomAppsController = [mainStoryboard instantiateViewControllerWithIdentifier:@"AppsTableViewController"];
    randomAppsController.listingTitleKey = @"Shuffle";
    randomAppsController.listingEndpoint = @"listing/random?limit=25";
    randomAppsController.showsRefreshButton = YES;
    UINavigationController *randomAppsNaviController = [[UINavigationController alloc] initWithRootViewController:randomAppsController];
    randomAppsNaviController.navigationBar.barStyle = UIBarStyleBlack;
    randomAppsNaviController.title = NSLocalizedString(@"Shuffle", nil);
    UIImage *randomAppsTabIcon = [UIImage imageNamed:@"RandomAppsTabIcon"];
    if (randomAppsTabIcon == nil) {
        randomAppsTabIcon = [UIImage imageNamed:@"RandomAppsTabIcon.png"];
    }
    randomAppsNaviController.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Shuffle", nil) image:randomAppsTabIcon tag:0];
    AppsTableViewController *topAppsController = [mainStoryboard instantiateViewControllerWithIdentifier:@"AppsTableViewController"];
    topAppsController.listingTitleKey = @"Top 25";
    topAppsController.listingEndpoint = @"listing/top";
    UINavigationController *topAppsNaviController = [[UINavigationController alloc] initWithRootViewController:topAppsController];
    topAppsNaviController.navigationBar.barStyle = UIBarStyleBlack;
    topAppsNaviController.title = NSLocalizedString(@"Top 25", nil);
    UIImage *top25TabIcon = [UIImage imageNamed:@"Top25TabIcon"];
    if (top25TabIcon == nil) {
        top25TabIcon = [UIImage imageNamed:@"Top25TabIcon.png"];
    }
    topAppsNaviController.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Top 25", nil) image:top25TabIcon tag:0];
    topAppsNaviController.tabBarItem.title = NSLocalizedString(@"Top 25", nil);
    NSMutableArray *viewControllers = [NSMutableArray arrayWithArray:((UITabBarController *)self.window.rootViewController).viewControllers];
    [viewControllers insertObject:queuedNaviController atIndex:2];
    [viewControllers insertObject:favoritesNaviController atIndex:4];
    [viewControllers insertObject:randomAppsNaviController atIndex:7];
    [viewControllers insertObject:topAppsNaviController atIndex:5];


    UIViewController *updatesNaviController = [self viewControllerWithIdentifier:VeterisUpdatesTabIdentifier inViewControllers:viewControllers];
    if (updatesNaviController != nil) {
        NSString *updatesTitle = NSLocalizedStringWithDefaultValue(@"Updates", nil, [NSBundle mainBundle], @"Updates", nil);
        updatesNaviController.title = updatesTitle;
        updatesNaviController.tabBarItem.title = updatesTitle;
        [viewControllers removeObject:updatesNaviController];
        UIViewController *shuffleNaviController = [self viewControllerWithIdentifier:VeterisShuffleTabIdentifier inViewControllers:viewControllers];
        NSUInteger shuffleIndex = shuffleNaviController != nil ? [viewControllers indexOfObject:shuffleNaviController] : NSNotFound;
        [viewControllers insertObject:updatesNaviController atIndex:(shuffleIndex != NSNotFound ? shuffleIndex + 1 : [viewControllers count])];
    }
    id savedTabOrder = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisTabOrderDefaultsKey];
    if (![savedTabOrder isKindOfClass:[NSArray class]]) {
        savedTabOrder = nil;
    }
    viewControllers = [NSMutableArray arrayWithArray:[self viewControllers:viewControllers orderedBySavedTabOrder:savedTabOrder]];
    [((UITabBarController *)self.window.rootViewController) setViewControllers:viewControllers];
    [((UITabBarController *)self.window.rootViewController) setCustomizableViewControllers:viewControllers];
    ((UITabBarController *)self.window.rootViewController).delegate = self;
    [self updateQueueTabBadge];
    [[VeterisUpdatesManager sharedManager] start];
    [self updateUpdatesTabBadge];
    [self selectTabWithIdentifier:VeterisHomeTabIdentifier inTabBarController:(UITabBarController *)self.window.rootViewController];
    UILocalNotification *launchNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if ([YZQueueNotifier isQueueNotification:launchNotification]) {
        [self selectTabWithIdentifier:VeterisDownloadsTabIdentifier inTabBarController:(UITabBarController *)self.window.rootViewController];
    }
    VeterisShowAppSyncAlertIfNeeded();

#ifdef DEBUG
    [DebugTextView attachToWindow:self.window];
//#endif
    [self becomeFirstResponder];
    //[[RRFPSBar sharedInstance] setHidden:NO];
#endif
    // UI Changes
    UIImage *backgroundImage = [UIImage imageNamed:@"UITabBarBG"];
    [[UITabBar appearance] setBackgroundImage:backgroundImage];
    [UINavigationBar.appearance setBackgroundImage:[UIImage imageNamed:@"UITitleBarBG"] forBarMetrics:UIBarMetricsDefault];
    [((UITabBarController *)self.window.rootViewController) moreNavigationController].delegate = self;
    [themeManager applyTintToTabBars];
    [themeManager applyTintToNavigationBars];
    self.window.backgroundColor = [UIColor whiteColor];
    NSArray *currentViewControllers = ((UITabBarController *)self.window.rootViewController).viewControllers;
    UINavigationController *categoriesNaviController = (UINavigationController *)[self viewControllerWithIdentifier:@"CategoriesTableViewController" inViewControllers:currentViewControllers];
    categoriesNaviController.title = NSLocalizedString(@"Categories", @"Categories");
    UINavigationController *allAppsNaviController = (UINavigationController *)[self viewControllerWithIdentifier:@"AllApps" inViewControllers:currentViewControllers];
    allAppsNaviController.title = NSLocalizedString(@"AllApps", @"AllApps");
    UINavigationController *topAppsTabController = (UINavigationController *)[self viewControllerWithIdentifier:VeterisTop25TabIdentifier inViewControllers:currentViewControllers];
    topAppsTabController.title = NSLocalizedString(@"Top 25", nil);
    topAppsTabController.tabBarItem.title = NSLocalizedString(@"Top 25", nil);
    UINavigationController *crackNaviController = (UINavigationController *)[self viewControllerWithIdentifier:@"CrackTableViewController" inViewControllers:currentViewControllers];
    crackNaviController.title = NSLocalizedString(@"Crack", @"Crack");
    crackNaviController.tabBarItem.title = NSLocalizedString(@"Crack", @"Crack");
    UINavigationController *featuredNaviController = (UINavigationController *)[self viewControllerWithIdentifier:@"FeaturedTableViewController" inViewControllers:currentViewControllers];
    featuredNaviController.title = NSLocalizedString(@"Featured", @"Featured");
    // Register for crash handling
#ifdef DEBUG
    NSSetUncaughtExceptionHandler(&myExceptionHandler);
#endif
    NSURL *launchURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if (launchURL == nil) {
        // safe to delete sandbox
        debugLog(@"Emptying sandbox");
        [self emptySandbox];
    } else {
        [self handlePendingLaunchURLIfNeeded:launchURL];
    }
    // Relaunch
    BOOL launchedInBackground = (application.applicationState == UIApplicationStateBackground);
    if (launchedInBackground) {
        [YZQueueManager holdBackgroundLaunchUntilRestored];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL downloadDirectoryReady = [self cleanDownloadDirectory];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (downloadDirectoryReady) {
                [YZQueueManager restorePendingDownloadsResumingInterrupted:launchedInBackground];
            }
            if (launchedInBackground) {
                [YZQueueManager releaseBackgroundLaunchHold];
            }
        });
        [self installCrashHandler];
    });
    return YES;
}

- (BOOL)cleanDownloadDirectory {
    if (![YZDownloadResumeStore migrateLegacyDownloadDirectoryIfNeeded]) {
        debugLog(@"Skipping download cleanup and resume until folder migration completes");
        return NO;
    }
    NSString *downloadDir = downloadPath();
    NSFileManager *manager = [[NSFileManager alloc] init];
    if (![manager fileExistsAtPath:downloadDir]) {
        NSError *createDirError = nil;
        if (![manager createDirectoryAtPath:downloadDir withIntermediateDirectories:YES attributes:nil error:&createDirError]) {
            debugLog(@"Failed to create download directory: %@, error: %@", downloadDir, createDirError.localizedDescription);
            return NO;
        } else {
            debugLog(@"Created download directory: %@", downloadDir);
        }
    }
    NSSet *pendingResumePaths = [NSSet setWithArray:[YZQueueManager pendingResumeTargetPaths]];
    NSString *resumeManifestPath = [YZDownloadResumeStore manifestPath];
    NSString *savedDownloadDir = downloadOnlyPath();
    NSString *savedDownloadPrefix = [savedDownloadDir stringByAppendingString:@"/"];
    NSDirectoryEnumerator *fileEnumerator = [manager enumeratorAtPath:downloadDir];
    for (NSString *filename in fileEnumerator) {
        NSString *filePath = [downloadDir stringByAppendingPathComponent:filename];
        if ([filePath isEqualToString:resumeManifestPath] || [filePath isEqualToString:savedDownloadDir]) {
            continue;
        }
        NSString *artifactOwner = [YZDownloadResumeStore targetPathForArtifactPath:filePath];
        NSString *ownerPath = artifactOwner ?: filePath;
        if ([pendingResumePaths containsObject:ownerPath] || [YZQueueManager isTargetPathInUse:ownerPath]) {
            continue;
        }
        NSError *error = nil;
        NSDictionary *attributes = [manager attributesOfItemAtPath:filePath error:&error];
        if (!attributes) {
            debugLog(@"Failed to get attributes for file: %@, error: %@", filename, error.localizedDescription);
            continue;
        }
        if (![[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
            continue;
        }
        if ([filePath hasPrefix:savedDownloadPrefix]) {
            // Kill unfinished downloads
            BOOL unfinishedIPA = (artifactOwner == nil && [manager fileExistsAtPath:[YZDownloadResumeStore resumeInfoPathForTargetPath:filePath]]);
            if (artifactOwner == nil && !unfinishedIPA) {
                continue;
            }
        }
        if (![manager removeItemAtPath:filePath error:&error]) {
            debugLog(@"Failed to delete file: %@, error: %@", filename, error.localizedDescription);
        } else {
            debugLog(@"Deleted file: %@", filename);
        }
    }
    return YES;
}

#ifdef DEBUG
void myExceptionHandler(NSException *exception)
{
    debugLog(@"CRASH: %@", exception);
    debugLog(@"Stack Trace: %@", [exception callStackSymbols]);
}
#endif
- (BOOL)openAppInfoForBundleID:(NSString *)bundleID {
    bundleID = VeterisTrimmedString(VeterisURLDecodedString(bundleID));
    if ([bundleID length] == 0) {
        return NO;
    }

    UITabBarController *tabBarController = (UITabBarController *)self.window.rootViewController;
    if (![tabBarController isKindOfClass:[UITabBarController class]]) {
        return NO;
    }

    UIViewController *selectedController = tabBarController.selectedViewController;
    UINavigationController *navigationController = nil;
    if ([selectedController isKindOfClass:[UINavigationController class]]) {
        navigationController = (UINavigationController *)selectedController;
    } else {
        for (UIViewController *controller in tabBarController.viewControllers) {
            if ([controller isKindOfClass:[UINavigationController class]]) {
                navigationController = (UINavigationController *)controller;
                NSUInteger selectedIndex = [tabBarController.viewControllers indexOfObject:controller];
                if (selectedIndex != NSNotFound) {
                    tabBarController.selectedIndex = selectedIndex;
                }
                break;
            }
        }
    }
    if (navigationController == nil) {
        return NO;
    }

    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:[NSBundle mainBundle]];
    AppInfo *appinfo = [storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
    [appinfo view];
    [appinfo initialize:bundleID];
    [navigationController pushViewController:appinfo animated:YES];
    return YES;
}

- (BOOL)handleVeterisURL:(NSURL *)url {
    NSString *host = [[url host] lowercaseString];
    if (![host isEqualToString:@"app"]) {
        return NO;
    }

    NSString *path = [url path];
    if ([path hasPrefix:@"/"] && [path length] > 1) {
        return [self openAppInfoForBundleID:[path substringFromIndex:1]];
    }
    return NO;
}

- (BOOL)handleIPAURL:(NSURL *)url {
    if ([[url pathExtension] isEqualToString:@"ipa"]) {
        [self selectTabWithIdentifier:VeterisDownloadsTabIdentifier inTabBarController:(UITabBarController *)self.window.rootViewController];
        debugLog(@"Opening IPA file: %@", [url path]);
        YZApplication *app = [YZApplication open:[url path]];
        if (app == nil) {
            debugLog(@"Failed to open IPA file");
            return NO;
        }
        debugLog(@"App container created");
        [YZQueueManager enqueueYZApplicationDownloaded:app];
        return YES;
    }
    return NO;
}

- (BOOL)handleIncomingURL:(NSURL *)url {
    if (url == nil) {
        return NO;
    }
    NSString *absoluteString = [url absoluteString];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ([absoluteString isEqualToString:VeterisLastHandledURLString] && now - VeterisLastHandledURLTime < 1.0) {
        return YES;
    }

    BOOL handled = NO;
    if ([[[url scheme] lowercaseString] isEqualToString:@"veteris"]) {
        handled = [self handleVeterisURL:url];
    } else {
        handled = [self handleIPAURL:url];
    }
    if (handled) {
        VeterisLastHandledURLString = [absoluteString copy];
        VeterisLastHandledURLTime = now;
    }
    return handled;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return [self handleIncomingURL:url];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [self handleIncomingURL:url];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    return [self handleIncomingURL:url];
}

- (void)handleLaunchURL:(NSURL *)url {
    [self handleIncomingURL:url];
}

- (void)handlePendingLaunchURLIfNeeded:(NSURL *)url {
    if (url == nil || ![[[url scheme] lowercaseString] isEqualToString:@"veteris"]) {
        return;
    }
    [self performSelector:@selector(handleLaunchURL:) withObject:url afterDelay:0.0];
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    if (application.applicationState == UIApplicationStateInactive && [YZQueueNotifier isQueueNotification:notification]) {
        [self selectTabWithIdentifier:VeterisDownloadsTabIdentifier inTabBarController:(UITabBarController *)self.window.rootViewController];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // TEMP: update check disabled
    // [VAPIHelper checkForUpdates];
    [AppInfo refreshInstalledApplicationCache];
    [VAPIHelper checkForRemoteAlert];
}

-(void)emptySandbox {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *rootPath = [NSString stringWithFormat:@"/var/mobile/Library/Application Support/Containers/%@/Documents/Inbox", bundleID];
    
    NSFileManager *manager = [[NSFileManager alloc] init];
    NSDirectoryEnumerator *fileEnumerator = [manager enumeratorAtPath:rootPath];

    for (NSString *filename in fileEnumerator) {
        debugLog(@"filename = %@", filename);
        NSString *filePath = [rootPath stringByAppendingPathComponent:filename];
        
        NSError *error = nil;
        if (![manager removeItemAtPath:filePath error:&error]) {
            debugLog(@"Failed to delete file: %@, error: %@", filename, error.localizedDescription);
        } else {
            debugLog(@"Deleted file: %@", filename);
        }
    }
    
    debugLog(@"Sandbox has been emptied.");
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        NSString *bundleid = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
        NSString *urlStr = [NSString stringWithFormat:@"cydia://package/%@", bundleid];
        NSURL *url = [NSURL URLWithString:urlStr];
        [[UIApplication sharedApplication] openURL:url];
    }
}

#pragma mark - UITabBarControllerDelegate
- (void)tabBarController:(UITabBarController *)tabBarController didEndCustomizingViewControllers:(NSArray *)viewControllers changed:(BOOL)changed {
    if (!changed) {
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:[self tabOrderForViewControllers:viewControllers] forKey:VeterisTabOrderDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - UINavigationControllerDelegate
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *) viewController animated:(BOOL)animated {
    if (viewController == [navigationController.viewControllers objectAtIndex:0]) {
        [themeManager applyThemeToNavigationBar:navigationController.navigationBar];
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#ifdef DEBUG
- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if(event.type == UIEventSubtypeMotionShake)
    {
        [[DebugTextView fromWindow:self.window] toggle];
    }
}
#endif

- (void) installCrashHandler
{
    KSCrashInstallation* installation = [KSCrashInstallationVAPI sharedInstance];
    // Install the crash handler. This should be done as early as possible.
    // This will record any crashes that occur, but it doesn't automatically send them.
    [installation install];
    // Send all outstanding reports. You can do this any time; it doesn't need
    // to happen right as the app launches. Advanced-Example shows how to defer
    // displaying the main view controller until crash reporting completes.
    [installation sendAllReportsWithCompletion:^(NSArray* reports, BOOL completed, NSError* error)
     {
         if(completed)
         {
             debugLog(@"Sent %d reports", (int)[reports count]);
         }
         else
         {
             debugLog(@"Failed to send reports: %@", error);
         }
     }];
}
@end
