#import "ThemeManager.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../Convenience/Convenience.h"
#import "../../AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import "InAppSettingsKit/Models/IASKSettingsReader.h"

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]
#define KILL_IF_UNSUPPORTED if (THEME_KILLSWITCH == 1) { return; }

@implementation ThemeManager {
    NSDictionary *themeInfo;
    NSString *currentTheme;
    bool THEME_KILLSWITCH;
}

+ (ThemeManager *)sharedInstance {
    static ThemeManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ThemeManager alloc] init];
        [NSNotificationCenter.defaultCenter addObserver:sharedInstance selector:@selector(reconfigure:) name:kIASKAppSettingChanged object:nil];
    });
    return sharedInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        themeInfo = [self defaultThemeInfo];
        currentTheme = [[NSUserDefaults standardUserDefaults] stringForKey:@"theme_preference"];
        if (currentTheme == nil) {
            currentTheme = @"Default";
        }
        if ([currentTheme isEqualToString:@"DefaultBlack"]) {
            currentTheme = @"Default";
        }
        if (SYSTEM_VERSION_LESS_THAN(@"6.0")) {
            THEME_KILLSWITCH = 1; // ios 5 has trouble with navigation bar themes
        }
    }
    return self;
}

- (NSDictionary*)themeInfoWithName:(NSString*)name tintColor:(UIColor*)tintColor gradientColors:(NSArray*)gradientColors {
    return [self themeInfoWithName:name tintColor:tintColor gradientColors:gradientColors tabBarUsesGradient:YES];
}

- (NSDictionary*)themeInfoWithName:(NSString*)name tintColor:(UIColor*)tintColor gradientColors:(NSArray*)gradientColors tabBarUsesGradient:(BOOL)tabBarUsesGradient {
    return [self themeInfoWithName:name tintColor:tintColor gradientColors:gradientColors tabBarUsesGradient:tabBarUsesGradient usesSystemAppearance:NO];
}

- (NSDictionary*)themeInfoWithName:(NSString*)name tintColor:(UIColor*)tintColor gradientColors:(NSArray*)gradientColors tabBarUsesGradient:(BOOL)tabBarUsesGradient usesSystemAppearance:(BOOL)usesSystemAppearance {
    return @{
        @"name": name,
        @"tintColor": tintColor,
        @"gradientColors": gradientColors,
        @"tabBarUsesGradient": @(tabBarUsesGradient),
        @"usesSystemAppearance": @(usesSystemAppearance)
    };
}

- (NSDictionary*)defaultThemeInfo {
    if (THEME_KILLSWITCH == 1) {
        return @{};
    }
    UIColor *stockIOSTint = [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
    UIColor *defaultTint = [UIColor darkGrayColor];
    NSArray *defaultGradient = @[
        (id)UIColorFromRGB(0x2C2C2C).CGColor,
        (id)UIColorFromRGB(0x1E1E1E).CGColor,
        (id)UIColorFromRGB(0x121212).CGColor,
        (id)UIColorFromRGB(0x000000).CGColor
    ];
    UIColor *jungleTint = [UIColor colorWithRed:0.30 green:0.55 blue:0.22 alpha:1.0];
    NSArray *jungleGradient = @[
        (id)UIColorFromRGB(0x4D7330).CGColor,
        (id)UIColorFromRGB(0x3C5A27).CGColor,
        (id)UIColorFromRGB(0x2E4720).CGColor,
        (id)UIColorFromRGB(0x22351A).CGColor
    ];
    UIColor *frostTint = [UIColor colorWithRed:0.35 green:0.55 blue:0.60 alpha:1.0];
    NSArray *frostGradient = @[
        (id)UIColorFromRGB(0x8BA7B3).CGColor,
        (id)UIColorFromRGB(0x6F8B97).CGColor,
        (id)UIColorFromRGB(0x56707C).CGColor,
        (id)UIColorFromRGB(0x43575F).CGColor
    ];
    UIColor *cherryTint = [UIColor colorWithRed:0.90 green:0.65 blue:0.75 alpha:1.0];
    NSArray *cherryGradient = @[
        (id)UIColorFromRGB(0xF2B7C1).CGColor,
        (id)UIColorFromRGB(0xD89AA9).CGColor,
        (id)UIColorFromRGB(0xC57F8F).CGColor,
        (id)UIColorFromRGB(0x9E626F).CGColor
    ];
    UIColor *rubyTint = [UIColor colorWithRed:0.70 green:0.02 blue:0.16 alpha:1.0];
    NSArray *rubyGradient = @[
        (id)UIColorFromRGB(0xB3122D).CGColor,
        (id)UIColorFromRGB(0x8D0E24).CGColor,
        (id)UIColorFromRGB(0x670A1A).CGColor,
        (id)UIColorFromRGB(0x3E0610).CGColor
    ];
    UIColor *blueberryTint = [UIColor colorWithRed:0.12 green:0.55 blue:0.78 alpha:1.0];
    NSArray *blueberryGradient = @[
        (id)UIColorFromRGB(0x5FB9D1).CGColor,
        (id)UIColorFromRGB(0x3F96B5).CGColor,
        (id)UIColorFromRGB(0x277391).CGColor,
        (id)UIColorFromRGB(0x185166).CGColor
    ];
    UIColor *indigoTint = [UIColor colorWithRed:0.24 green:0.28 blue:0.72 alpha:1.0];
    NSArray *indigoGradient = @[
        (id)UIColorFromRGB(0x5C67BA).CGColor,
        (id)UIColorFromRGB(0x424C9F).CGColor,
        (id)UIColorFromRGB(0x2F3676).CGColor,
        (id)UIColorFromRGB(0x1E234E).CGColor
    ];
    UIColor *strawberryTint = [UIColor colorWithRed:0.90 green:0.16 blue:0.34 alpha:1.0];
    NSArray *strawberryGradient = @[
        (id)UIColorFromRGB(0xF06486).CGColor,
        (id)UIColorFromRGB(0xD64267).CGColor,
        (id)UIColorFromRGB(0xAA2A4C).CGColor,
        (id)UIColorFromRGB(0x6F1831).CGColor
    ];
    UIColor *limeTint = [UIColor colorWithRed:0.64 green:0.78 blue:0.08 alpha:1.0];
    NSArray *limeGradient = @[
        (id)UIColorFromRGB(0xC8D94B).CGColor,
        (id)UIColorFromRGB(0xA8BD31).CGColor,
        (id)UIColorFromRGB(0x7F9421).CGColor,
        (id)UIColorFromRGB(0x526215).CGColor
    ];
    UIColor *graphiteTint = [UIColor colorWithRed:0.42 green:0.46 blue:0.48 alpha:1.0];
    NSArray *graphiteGradient = @[
        (id)UIColorFromRGB(0x80898C).CGColor,
        (id)UIColorFromRGB(0x626A6D).CGColor,
        (id)UIColorFromRGB(0x474D50).CGColor,
        (id)UIColorFromRGB(0x303537).CGColor
    ];
    UIColor *tangerineTint = [UIColor colorWithRed:0.95 green:0.38 blue:0.04 alpha:1.0];
    NSArray *tangerineGradient = @[
        (id)UIColorFromRGB(0xF07A2A).CGColor,
        (id)UIColorFromRGB(0xCF5D19).CGColor,
        (id)UIColorFromRGB(0xA94311).CGColor,
        (id)UIColorFromRGB(0x702B0A).CGColor
    ];
    UIColor *sageTint = [UIColor colorWithRed:0.47 green:0.62 blue:0.45 alpha:1.0];
    NSArray *sageGradient = @[
        (id)UIColorFromRGB(0x9CB98D).CGColor,
        (id)UIColorFromRGB(0x789B6B).CGColor,
        (id)UIColorFromRGB(0x58784F).CGColor,
        (id)UIColorFromRGB(0x3B5536).CGColor
    ];
    UIColor *autumnTint = [UIColor colorWithRed:0.60 green:0.30 blue:0.05 alpha:1.0];
    NSArray *autumnGradient = @[
        (id)UIColorFromRGB(0x8A4315).CGColor,
        (id)UIColorFromRGB(0x6F3410).CGColor,
        (id)UIColorFromRGB(0x55260C).CGColor,
        (id)UIColorFromRGB(0x3D1A09).CGColor
    ];
    UIColor *spookyTint = [UIColor purpleColor];
    NSArray *spookyGradient = @[
        (id)UIColorFromRGB(0x454545).CGColor,
        (id)UIColorFromRGB(0x393939).CGColor,
        (id)UIColorFromRGB(0x272726).CGColor,
        (id)UIColorFromRGB(0x19191A).CGColor
    ];
    UIColor *periwinkleTint = [UIColor colorWithRed:0.55 green:0.55 blue:0.85 alpha:1.0];
    NSArray *periwinkleGradient = @[
        (id)UIColorFromRGB(0x5F5F9C).CGColor,
        (id)UIColorFromRGB(0x4B4B7D).CGColor,
        (id)UIColorFromRGB(0x39395E).CGColor,
        (id)UIColorFromRGB(0x292941).CGColor
    ];
    return @{
        @"StockIOS": [self themeInfoWithName:@"Stock iOS" tintColor:stockIOSTint gradientColors:@[] tabBarUsesGradient:NO usesSystemAppearance:YES],
        @"Default": [self themeInfoWithName:@"Midnight (Standard)" tintColor:defaultTint gradientColors:defaultGradient],
        @"Jungle": [self themeInfoWithName:@"Jungle" tintColor:jungleTint gradientColors:jungleGradient],
        @"Frost": [self themeInfoWithName:@"Frost" tintColor:frostTint gradientColors:frostGradient],
        @"Cherry": [self themeInfoWithName:@"Cherry Blossom" tintColor:cherryTint gradientColors:cherryGradient],
        @"Ruby": [self themeInfoWithName:@"Ruby" tintColor:rubyTint gradientColors:rubyGradient],
        @"Blueberry": [self themeInfoWithName:@"Blueberry" tintColor:blueberryTint gradientColors:blueberryGradient],
        @"Indigo": [self themeInfoWithName:@"Indigo" tintColor:indigoTint gradientColors:indigoGradient],
        @"Strawberry": [self themeInfoWithName:@"Strawberry" tintColor:strawberryTint gradientColors:strawberryGradient],
        @"Lime": [self themeInfoWithName:@"Lime" tintColor:limeTint gradientColors:limeGradient],
        @"Graphite": [self themeInfoWithName:@"Graphite" tintColor:graphiteTint gradientColors:graphiteGradient],
        @"Tangerine": [self themeInfoWithName:@"Tangerine" tintColor:tangerineTint gradientColors:tangerineGradient],
        @"Sage": [self themeInfoWithName:@"Sage" tintColor:sageTint gradientColors:sageGradient],
        @"Autumn": [self themeInfoWithName:@"Autumn" tintColor:autumnTint gradientColors:autumnGradient],
        @"Spooky": [self themeInfoWithName:@"Spooky" tintColor:spookyTint gradientColors:spookyGradient],
        @"Periwinkle": [self themeInfoWithName:@"Periwinkle" tintColor:periwinkleTint gradientColors:periwinkleGradient],
        @"JungleBlack": [self themeInfoWithName:@"Jungle (Black)" tintColor:jungleTint gradientColors:jungleGradient tabBarUsesGradient:NO],
        @"FrostBlack": [self themeInfoWithName:@"Frost (Black)" tintColor:frostTint gradientColors:frostGradient tabBarUsesGradient:NO],
        @"CherryBlack": [self themeInfoWithName:@"Cherry Blossom (Black)" tintColor:cherryTint gradientColors:cherryGradient tabBarUsesGradient:NO],
        @"RubyBlack": [self themeInfoWithName:@"Ruby (Black)" tintColor:rubyTint gradientColors:rubyGradient tabBarUsesGradient:NO],
        @"BlueberryBlack": [self themeInfoWithName:@"Blueberry (Black)" tintColor:blueberryTint gradientColors:blueberryGradient tabBarUsesGradient:NO],
        @"IndigoBlack": [self themeInfoWithName:@"Indigo (Black)" tintColor:indigoTint gradientColors:indigoGradient tabBarUsesGradient:NO],
        @"StrawberryBlack": [self themeInfoWithName:@"Strawberry (Black)" tintColor:strawberryTint gradientColors:strawberryGradient tabBarUsesGradient:NO],
        @"LimeBlack": [self themeInfoWithName:@"Lime (Black)" tintColor:limeTint gradientColors:limeGradient tabBarUsesGradient:NO],
        @"GraphiteBlack": [self themeInfoWithName:@"Graphite (Black)" tintColor:graphiteTint gradientColors:graphiteGradient tabBarUsesGradient:NO],
        @"TangerineBlack": [self themeInfoWithName:@"Tangerine (Black)" tintColor:tangerineTint gradientColors:tangerineGradient tabBarUsesGradient:NO],
        @"SageBlack": [self themeInfoWithName:@"Sage (Black)" tintColor:sageTint gradientColors:sageGradient tabBarUsesGradient:NO],
        @"AutumnBlack": [self themeInfoWithName:@"Autumn (Black)" tintColor:autumnTint gradientColors:autumnGradient tabBarUsesGradient:NO],
        @"SpookyBlack": [self themeInfoWithName:@"Spooky (Black)" tintColor:spookyTint gradientColors:spookyGradient tabBarUsesGradient:NO],
        @"PeriwinkleBlack": [self themeInfoWithName:@"Periwinkle (Black)" tintColor:periwinkleTint gradientColors:periwinkleGradient tabBarUsesGradient:NO]
    };
}

- (bool)deviceSupportsThemes {
    return THEME_KILLSWITCH == 0;
}

#pragma mark - Theme Management

- (UIColor*)tintColorForTheme:(NSString*)themeName {
    return [[themeInfo objectForKey:themeName] objectForKey:@"tintColor"];
}

- (UIColor*)tintColorForCurrentTheme {
    return [self tintColorForTheme:currentTheme];
}

- (UIColor*)homeShimmerColorForCurrentTheme {
    if (![self deviceSupportsThemes] || [currentTheme isEqualToString:@"Default"]) {
        return [UIColor purpleColor];
    }
    return [self tintColorForCurrentTheme];
}

- (NSArray*)gradientColorsForTheme:(NSString*)themeName {
    debugLog(@"themeName: %@", themeName);
    return [[themeInfo objectForKey:themeName] objectForKey:@"gradientColors"];
}

- (NSArray*)gradientColorsForCurrentTheme {
    return [self gradientColorsForTheme:currentTheme];
}

- (BOOL)tabBarUsesGradientForCurrentTheme {
    return [[[themeInfo objectForKey:currentTheme] objectForKey:@"tabBarUsesGradient"] boolValue];
}

- (BOOL)themeUsesSystemAppearanceForCurrentTheme {
    return [[[themeInfo objectForKey:currentTheme] objectForKey:@"usesSystemAppearance"] boolValue];
}

#pragma mark - Theme Application
- (void)applyTintToTabBar:(UITabBar *)tabBar {
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [tabBar setTintColor:nil];
        [tabBar setSelectedImageTintColor:nil];
        for (UITabBarItem *item in tabBar.items) {
            [item setTitleTextAttributes:nil forState:UIControlStateNormal];
            [item setTitleTextAttributes:nil forState:UIControlStateSelected];
        }
        return;
    }
    UIColor *tintColor = [self tintColorForCurrentTheme];
    [tabBar setTintColor:tintColor];
    [tabBar setSelectedImageTintColor:tintColor];
    for (UITabBarItem *item in tabBar.items) {
        [item setTitleTextAttributes:@{UITextAttributeTextColor: tintColor} forState:UIControlStateNormal];
        [item setTitleTextAttributes:@{UITextAttributeTextColor: [[UIColor whiteColor] tintWithColor:tintColor]} forState:UIControlStateSelected];
    }
}

- (void)applyThemeToTabBar:(UITabBar *)tabBar {
    KILL_IF_UNSUPPORTED;
    UIView *bgView = [self findTabBarBackgroundView:tabBar];
    [self cleanViewOfGradientLayers:bgView];
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        tabBar.backgroundImage = nil;
        tabBar.selectionIndicatorImage = nil;
        [bgView setNeedsDisplay];
        return;
    }
    tabBar.backgroundImage = [UIImage imageNamed:@"UITabBarBG"];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        tabBar.selectionIndicatorImage = [[UIImage alloc] init];
    }
    if (![self tabBarUsesGradientForCurrentTheme]) {
        [bgView setNeedsDisplay];
        return;
    }
    CAGradientLayer *gradientLayer = [self createGradientLayerForCurrentThemeWithFrame:bgView.bounds];
    [bgView.layer insertSublayer:gradientLayer atIndex:0];
}

- (void)applyTintToTabBars {
    KILL_IF_UNSUPPORTED;
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [UITabBar.appearance setBackgroundImage:nil];
        [UITabBar.appearance setTintColor:nil];
        [UITabBar.appearance setSelectedImageTintColor:nil];
        [UITabBarItem.appearance setTitleTextAttributes:nil forState:UIControlStateNormal];
        [UITabBarItem.appearance setTitleTextAttributes:nil forState:UIControlStateSelected];
        UITabBarController *tabBarController = (UITabBarController *)getDelegate().window.rootViewController;
        if ([tabBarController isKindOfClass:[UITabBarController class]]) {
            [self applyTintToTabBar:tabBarController.tabBar];
        }
        return;
    }
    [UITabBar.appearance setBackgroundImage:[UIImage imageNamed:@"UITabBarBG"]];
    [UITabBar.appearance setTintColor:[self tintColorForCurrentTheme]];
    [UITabBar.appearance setSelectedImageTintColor:[self tintColorForCurrentTheme]];
    [UITabBarItem.appearance setTitleTextAttributes:@{UITextAttributeTextColor: [self tintColorForCurrentTheme]} forState:UIControlStateNormal];
    [UITabBarItem.appearance setTitleTextAttributes:@{UITextAttributeTextColor: [[UIColor whiteColor] tintWithColor:[self tintColorForCurrentTheme]]} forState:UIControlStateSelected];
    UITabBarController *tabBarController = (UITabBarController *)getDelegate().window.rootViewController;
    if ([tabBarController isKindOfClass:[UITabBarController class]]) {
        [self applyTintToTabBar:tabBarController.tabBar];
    }
}

- (void)applyThemeToNavigationBar:(UINavigationBar *)navigationBar {
    KILL_IF_UNSUPPORTED;
    UIView *bgView = [self findNavigationBarBackgroundView:navigationBar];
    [self cleanViewOfGradientLayers:bgView];
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [navigationBar setBarStyle:UIBarStyleDefault];
        [navigationBar setTintColor:nil];
        [bgView setNeedsDisplay];
        return;
    }
    [navigationBar setBackgroundImage:[UIImage imageNamed:@"UITitleBarBG"] forBarMetrics:UIBarMetricsDefault];
    [navigationBar setBarStyle:UIBarStyleBlack];
    CAGradientLayer *gradientLayer = [self createGradientLayerForCurrentThemeWithFrame:navigationBar.bounds];
    [bgView.layer insertSublayer:gradientLayer atIndex:0];
    [bgView setNeedsDisplay];
    // set tint color here anyway, sometimes the shown viewcontroller doesnt get redrawn
    [navigationBar setTintColor:[self tintColorForCurrentTheme]];
}

- (void)applyTintToNavigationBars {
    KILL_IF_UNSUPPORTED;
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [UINavigationBar.appearance setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [UINavigationBar.appearance setBarStyle:UIBarStyleDefault];
        [UINavigationBar.appearance setTintColor:nil];
        return;
    }
    [UINavigationBar.appearance setBackgroundImage:[UIImage imageNamed:@"UITitleBarBG"] forBarMetrics:UIBarMetricsDefault];
    [UINavigationBar.appearance setBarStyle:UIBarStyleBlack];
    [UINavigationBar.appearance setTintColor:[self tintColorForCurrentTheme]];
}

#pragma mark - View Helpers
- (UIView *)findTabBarBackgroundView:(UITabBar *)tabBar {
    for (UIView *view in tabBar.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"_UITabBarBackgroundView")]) {
            return view;
        }
    }
    return nil;
}

- (UIView *)findNavigationBarBackgroundView:(UINavigationBar *)navigationBar {
    for (UIView *view in navigationBar.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"_UINavigationBarBackground")]) {
            return view;
        }
    }
    return nil;
}

#pragma mark - Layer Helpers
- (void)cleanViewOfGradientLayers:(UIView *)view {
    for (CALayer *layer in [view.layer.sublayers copy]) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }
}

#pragma mark - Gradient Layer Creation
- (CAGradientLayer *)createGradientLayerWithColors:(NSArray *)baseColors tintColor:(UIColor *)tintColor frame:(CGRect)frame {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = frame;
    
    NSMutableArray *tintedColors = [NSMutableArray array];
    for (id cgColor in baseColors) {
        UIColor *color = [UIColor colorWithCGColor:(__bridge CGColorRef)cgColor];
        UIColor *tintedColor = [color tintWithColor:tintColor];
        [tintedColors addObject:(id)tintedColor.CGColor];
    }
    
    gradient.colors = tintedColors;
    return gradient;
}

- (CAGradientLayer *)createGradientLayerForCurrentThemeWithFrame:(CGRect)frame {
    return [self createGradientLayerWithColors:[self gradientColorsForCurrentTheme] tintColor:[self tintColorForCurrentTheme] frame:frame];
}

#pragma mark - Misc
- (void)reconfigure:(NSNotification *)notification {
    debugLog(@"notification: %@", notification);
    if (![notification.object isKindOfClass:[NSString class]] || ![(NSString *)notification.object isEqualToString:@"theme_preference"]) {
        debugLog(@"Not a theme change, ignoring");
        return;
    }
    if (![self deviceSupportsThemes]) {
        debugLog(@"Device does not support themes, ignoring");
        return;
    }
    currentTheme = [[notification userInfo] valueForKey:@"theme_preference"];
    [NSNotificationCenter.defaultCenter postNotificationName:kPleaseReloadThemes object:nil];   
    UIViewController *shownVC = [getDelegate().window visibleViewController];
    if (shownVC.navigationController != nil) {
        [self applyThemeToNavigationBar:shownVC.navigationController.navigationBar];
    }
    [self applyTintToTabBars];
    [self applyTintToNavigationBars];
}
@end
