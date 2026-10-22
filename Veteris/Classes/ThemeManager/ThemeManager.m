#import "ThemeManager.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../Convenience/Convenience.h"
#import "../../AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "InAppSettingsKit/Models/IASKSettingsReader.h"

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]
#define KILL_IF_UNSUPPORTED if (THEME_KILLSWITCH == 1) { return; }

static NSString * const kThemeArtworkDirectory = @"ThemeArtwork";
static char kAppliedThemeKey;
static char kLeftBarButtonItemKey;
static char kArtworkButtonKey;
static char kArtworkButtonItemKey;
static char kContentTopInsetKey;

static NSValue *ThemeInsets(CGFloat top, CGFloat left, CGFloat bottom, CGFloat right) {
    return [NSValue valueWithUIEdgeInsets:UIEdgeInsetsMake(top, left, bottom, right)];
}

static NSValue *ThemeSize(CGFloat width, CGFloat height) {
    return [NSValue valueWithCGSize:CGSizeMake(width, height)];
}

static NSValue *ThemeOffset(CGFloat horizontal, CGFloat vertical) {
    return [NSValue valueWithUIOffset:UIOffsetMake(horizontal, vertical)];
}

@interface ThemeArtworkButtonItemReference : NSObject
@property (nonatomic, weak) UIBarButtonItem *item;
@end

@implementation ThemeArtworkButtonItemReference
@end

@implementation ThemeManager {
    NSDictionary *themeInfo;
    NSString *currentTheme;
    bool THEME_KILLSWITCH;
    BOOL artworkThemeWasUsed;
    NSString *artworkAssetsTheme;
    NSDictionary *artworkAssets;
    NSString *artworkAppearanceTheme;
    NSHashTable *styledBarButtonItems;
    NSMutableDictionary *artworkPreviewColors;
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



- (NSDictionary*)artworkThemeInfoWithName:(NSString*)name folder:(NSString*)folder tintColor:(UIColor*)tintColor homeColor:(UIColor*)homeColor artwork:(NSDictionary*)artwork {
    NSMutableDictionary *info = [[self themeInfoWithName:name tintColor:tintColor gradientColors:@[] tabBarUsesGradient:NO] mutableCopy];
    NSMutableDictionary *artworkInfo = [artwork mutableCopy];
    [artworkInfo setObject:folder forKey:@"folder"];
    [info setObject:artworkInfo forKey:@"artwork"];
    [info setObject:homeColor forKey:@"homeColor"];
    return info;
}

- (NSDictionary*)artworkThemeInfo {
    UIColor *white = [UIColor whiteColor];
    NSValue *shadowUp = ThemeOffset(0, -1);
    NSValue *shadowDown = ThemeOffset(0, 1);

    UIColor *notesPaper = UIColorFromRGB(0xFAF693);
    NSValue *notesButtonInsets = ThemeInsets(0, 5, 0, 5);
    NSValue *notesBackInsets = ThemeInsets(0, 14, 0, 4);
    NSDictionary *notes = [self artworkThemeInfoWithName:@"Notes" folder:@"Notes" tintColor:UIColorFromRGB(0x5B3F36) homeColor:notesPaper artwork:@{
        @"navigationBar": @{@"file": @"top bar@2x~iphone.png"},
        @"tabBar": @{@"file": @"SearchBar@2x~iphone.png", @"capInsets": ThemeInsets(2, 0, 2, 0), @"size": ThemeSize(320, 49)},
        @"button": @{@"file": @"header button@2x~iphone.png", @"capInsets": notesButtonInsets},
        @"buttonPressed": @{@"file": @"header button pressed@2x~iphone.png", @"capInsets": notesButtonInsets},
        @"backButton": @{@"file": @"header back@2x.png", @"capInsets": notesBackInsets},
        @"backButtonPressed": @{@"file": @"header back pressed@2x.png", @"capInsets": notesBackInsets},
        @"titleColor": white,
        @"buttonTitleColor": white,
        @"tabTitleColor": UIColorFromRGB(0xC9B7A6),
        @"tabSelectedTitleColor": notesPaper,
        @"tabSelectedImageColor": notesPaper,
        @"shadowColor": [UIColor colorWithWhite:0 alpha:0.5],
        @"shadowOffset": shadowUp
    }];



    UIColor *remindersTitle = [UIColor colorWithWhite:0.808 alpha:1];
    NSValue *remindersButtonInsets = ThemeInsets(0, 9, 0, 9);
    NSValue *remindersButtonAlignment = ThemeInsets(4, 3, 3, 3);
    NSValue *remindersBackInsets = ThemeInsets(0, 16, 0, 7);
    NSValue *remindersBackAlignment = ThemeInsets(4, 2, 2, 3);
    NSDictionary *reminders = [self artworkThemeInfoWithName:@"Reminders" folder:@"Reminders" tintColor:UIColorFromRGB(0x383838) homeColor:UIColorFromRGB(0xDD2730) artwork:@{
        @"navigationBar": @{@"layers": @[@[@"background@2x~iphone.png", @0]], @"size": ThemeSize(320, 44)},
        @"tabBar": @{@"layers": @[@[@"background@2x~iphone.png", @(-300)]], @"size": ThemeSize(320, 49)},
        @"leftButton": @{@"file": @"ButtonLeft@2x~iphone.png", @"capInsets": remindersButtonInsets, @"alignmentInsets": remindersButtonAlignment},
        @"leftButtonPressed": @{@"file": @"ButtonLeftDown@2x~iphone.png", @"capInsets": remindersButtonInsets, @"alignmentInsets": remindersButtonAlignment},
        @"button": @{@"file": @"ButtonRight@2x~iphone.png", @"capInsets": remindersButtonInsets, @"alignmentInsets": remindersButtonAlignment},
        @"buttonPressed": @{@"file": @"ButtonRightDown@2x~iphone.png", @"capInsets": remindersButtonInsets, @"alignmentInsets": remindersButtonAlignment},
        @"backButton": @{@"file": @"backButton@2x~iphone.png", @"capInsets": remindersBackInsets, @"alignmentInsets": remindersBackAlignment},
        @"backButtonPressed": @{@"file": @"backButtonPressed@2x~iphone.png", @"capInsets": remindersBackInsets, @"alignmentInsets": remindersBackAlignment},
        @"titleColor": remindersTitle,
        @"buttonTitleColor": remindersTitle,
        @"buttonTitleFont": [UIFont boldSystemFontOfSize:12],
        // Keep Reminders' custom bar buttons at their full 36 pt height.
        @"buttonsAsCustomViews": @YES,
        @"buttonContentInsets": ThemeInsets(0, 8, 0, 8),
        @"buttonMinimumWidth": @54,
        @"actionButtonImage": @{@"file": @"UIButtonBarAction.png"},
        @"tabTitleColor": UIColorFromRGB(0x9A9A9A),
        @"tabSelectedTitleColor": white,
        @"tabSelectedImageColor": UIColorFromRGB(0xDD2730),
        @"shadowColor": [UIColor colorWithWhite:0 alpha:0.75],
        @"shadowOffset": shadowUp
    }];
	

    NSValue *gameCenterButtonInsets = ThemeInsets(0, 6, 0, 6);
    NSValue *gameCenterBackInsets = ThemeInsets(0, 15, 0, 4);
    NSDictionary *gameCenter = [self artworkThemeInfoWithName:@"Game Center" folder:@"GameCenter" tintColor:UIColorFromRGB(0x935337) homeColor:UIColorFromRGB(0x33935E) artwork:@{
        @"navigationBar": @{@"file": @"GKNavbarPortrait@2x.png"},
        @"navigationBarShadow": @{@"file": @"GKNavbarShadow@2x.png"},
        @"tabBar": @{@"file": @"GKTabbarPortrait@2x.png"},
        @"tabBarSelection": @{@"file": @"GKTabbarActiveTab@2x~iphone.png"},
        @"button": @{@"file": @"GKNavbarButtonNormal@2x.png", @"capInsets": gameCenterButtonInsets},
        @"buttonPressed": @{@"file": @"GKNavbarButtonPressed@2x.png", @"capInsets": gameCenterButtonInsets},
        @"backButton": @{@"file": @"GKNavbarBackButtonNormal@2x.png", @"capInsets": gameCenterBackInsets},
        @"backButtonPressed": @{@"file": @"GKNavbarBackButtonPressed@2x.png", @"capInsets": gameCenterBackInsets},
        @"titleColor": white,
        @"buttonTitleColor": white,
        @"tabTitleColor": UIColorFromRGB(0xF2DFC4),
        @"tabSelectedTitleColor": white,
        @"tabSelectedImageColor": UIColorFromRGB(0xEDD999),
        @"shadowColor": [UIColor colorWithWhite:0 alpha:0.6],
        @"shadowOffset": shadowUp
    }];



    UIColor *findMyFriendsBrown = UIColorFromRGB(0x503815);
    UIColor *findMyFriendsHighlight = [UIColor colorWithWhite:1 alpha:0.5];
    NSValue *findMyFriendsButtonInsets = ThemeInsets(0, 12, 0, 12);
    NSValue *findMyFriendsBackInsets = ThemeInsets(0, 15, 0, 5);
    NSDictionary *findMyFriends = [self artworkThemeInfoWithName:@"Find My Friends" folder:@"FindMyFriends" tintColor:UIColorFromRGB(0x956635) homeColor:UIColorFromRGB(0xCAA86D) artwork:@{
        @"navigationBar": @{@"file": @"navbar_top@2x.png"},
        @"navigationBarShadow": @{@"file": @"navbar_bottom@2x.png"},
        @"contentTopInset": @10,
        @"tabBar": @{@"file": @"toolbar_noshadow@2x.png", @"capInsets": ThemeInsets(4, 0, 4, 0), @"size": ThemeSize(320, 49)},
        @"tabBarSelection": @{@"file": @"icon_rectangle_selected@2x.png", @"capInsets": ThemeInsets(8, 8, 8, 8), @"size": ThemeSize(62, 47)},
        @"button": @{@"file": @"btn_normal@2x.png", @"capInsets": findMyFriendsButtonInsets},
        @"buttonPressed": @{@"file": @"btn_pressed@2x.png", @"capInsets": findMyFriendsButtonInsets},
        @"backButton": @{@"file": @"btn_back_normal@2x.png", @"capInsets": findMyFriendsBackInsets},
        @"backButtonPressed": @{@"file": @"btn_back_pressed@2x.png", @"capInsets": findMyFriendsBackInsets},
        @"titleColor": findMyFriendsBrown,
        @"titleShadowColor": findMyFriendsHighlight,
        @"titleShadowOffset": shadowDown,
        @"buttonTitleColor": white,
        @"tabTitleColor": UIColorFromRGB(0x7F552A),
        @"tabTitleShadowColor": findMyFriendsHighlight,
        @"tabTitleShadowOffset": shadowDown,
        @"tabSelectedTitleColor": UIColorFromRGB(0xF2E2C2),
        @"tabSelectedImageColor": UIColorFromRGB(0xD2B581),
        @"shadowColor": [UIColor colorWithWhite:0 alpha:0.4],
        @"shadowOffset": shadowUp
    }];

    return @{
        @"Notes": notes,
        @"Reminders": reminders,
        @"GameCenter": gameCenter,
        @"FindMyFriends": findMyFriends
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
    NSMutableDictionary *themes = [NSMutableDictionary dictionaryWithDictionary:@{
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
    }];
    [themes addEntriesFromDictionary:[self artworkThemeInfo]];
    return themes;
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

- (UIColor*)previewColorForTheme:(NSString*)themeName {
    NSDictionary *artwork = [self artworkForTheme:themeName];
    if (artwork == nil) {
        return [self tintColorForTheme:themeName];
    }
    UIColor *previewColor = [artworkPreviewColors objectForKey:themeName];
    if (previewColor != nil) {
        return previewColor;
    }
    UIImage *navigationBarImage = [self artworkImageForSpec:[artwork objectForKey:@"navigationBar"] folder:[artwork objectForKey:@"folder"]];
    if (navigationBarImage == nil) {
        return [self tintColorForTheme:themeName];
    }
    CGSize size = CGSizeMake(22, 22);
    UIGraphicsBeginImageContextWithOptions(size, YES, 2.0);
    [navigationBarImage drawAtPoint:CGPointMake(floorf((size.width - navigationBarImage.size.width) / 2), floorf((size.height - navigationBarImage.size.height) / 2))];
    UIImage *swatch = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    previewColor = [UIColor colorWithPatternImage:swatch];
    if (artworkPreviewColors == nil) {
        artworkPreviewColors = [NSMutableDictionary dictionary];
    }
    [artworkPreviewColors setObject:previewColor forKey:themeName];
    return previewColor;
}

- (UIColor*)homeShimmerColorForCurrentTheme {
    if (![self deviceSupportsThemes] || [currentTheme isEqualToString:@"Default"]) {
        return [UIColor purpleColor];
    }
    UIColor *homeColor = [[themeInfo objectForKey:currentTheme] objectForKey:@"homeColor"];
    if (homeColor != nil) {
        return homeColor;
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

- (NSDictionary*)artworkForTheme:(NSString*)themeName {
    if (themeName == nil) {
        return nil;
    }
    return [[themeInfo objectForKey:themeName] objectForKey:@"artwork"];
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
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    if (artwork != nil) {
        UIColor *selectedImageColor = [artwork objectForKey:@"tabSelectedImageColor"];
        NSDictionary *normalAttributes = [self textAttributesForArtwork:artwork prefix:@"tabTitle"];
        NSDictionary *selectedAttributes = [self textAttributesForArtwork:artwork prefix:@"tabSelectedTitle"];
        [tabBar setTintColor:selectedImageColor];
        [tabBar setSelectedImageTintColor:selectedImageColor];
        for (UITabBarItem *item in tabBar.items) {
            [item setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
            [item setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
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
    NSDictionary *artworkAssetImages = [self artworkAssetsForCurrentTheme];
    if (artworkAssetImages != nil) {
        UIImage *selectionImage = [artworkAssetImages objectForKey:@"tabBarSelection"];
        if (selectionImage == nil) {
            selectionImage = [[UIImage alloc] init];
        }
        tabBar.backgroundImage = [artworkAssetImages objectForKey:@"tabBar"];
        tabBar.selectionIndicatorImage = selectionImage;
        [bgView setNeedsDisplay];
        return;
    }
    tabBar.backgroundImage = [UIImage imageNamed:@"UITabBarBG"];
    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        tabBar.selectionIndicatorImage = [[UIImage alloc] init];
    } else if (artworkThemeWasUsed) {
        tabBar.selectionIndicatorImage = nil;
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
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    if (artwork != nil) {
        UIColor *selectedImageColor = [artwork objectForKey:@"tabSelectedImageColor"];
        [UITabBar.appearance setBackgroundImage:[[self artworkAssetsForCurrentTheme] objectForKey:@"tabBar"]];
        [UITabBar.appearance setTintColor:selectedImageColor];
        [UITabBar.appearance setSelectedImageTintColor:selectedImageColor];
        [UITabBarItem.appearance setTitleTextAttributes:[self textAttributesForArtwork:artwork prefix:@"tabTitle"] forState:UIControlStateNormal];
        [UITabBarItem.appearance setTitleTextAttributes:[self textAttributesForArtwork:artwork prefix:@"tabSelectedTitle"] forState:UIControlStateSelected];
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
    [self applyArtworkToNavigationBar:navigationBar];
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [navigationBar setBarStyle:UIBarStyleDefault];
        [navigationBar setTintColor:nil];
        [bgView setNeedsDisplay];
        return;
    }
    NSDictionary *artworkAssetImages = [self artworkAssetsForCurrentTheme];
    if (artworkAssetImages != nil) {
        [navigationBar setBackgroundImage:[artworkAssetImages objectForKey:@"navigationBar"] forBarMetrics:UIBarMetricsDefault];
        [navigationBar setBarStyle:UIBarStyleBlack];
        [bgView setNeedsDisplay];
        [navigationBar setTintColor:[self tintColorForCurrentTheme]];
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
    [self updateArtworkAppearanceIfNeeded];
    if ([self themeUsesSystemAppearanceForCurrentTheme]) {
        [UINavigationBar.appearance setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [UINavigationBar.appearance setBarStyle:UIBarStyleDefault];
        [UINavigationBar.appearance setTintColor:nil];
        return;
    }
    NSDictionary *artworkAssetImages = [self artworkAssetsForCurrentTheme];
    if (artworkAssetImages != nil) {
        [UINavigationBar.appearance setBackgroundImage:[artworkAssetImages objectForKey:@"navigationBar"] forBarMetrics:UIBarMetricsDefault];
        [UINavigationBar.appearance setBarStyle:UIBarStyleBlack];
        [UINavigationBar.appearance setTintColor:[self tintColorForCurrentTheme]];
        return;
    }
    [UINavigationBar.appearance setBackgroundImage:[UIImage imageNamed:@"UITitleBarBG"] forBarMetrics:UIBarMetricsDefault];
    [UINavigationBar.appearance setBarStyle:UIBarStyleBlack];
    [UINavigationBar.appearance setTintColor:[self tintColorForCurrentTheme]];
}

#pragma mark - Artwork Themes
- (UIImage *)artworkImageNamed:(NSString *)fileName folder:(NSString *)folder {
    NSString *directory = [kThemeArtworkDirectory stringByAppendingPathComponent:folder];
    NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:nil inDirectory:directory];
    UIImage *image = path != nil ? [UIImage imageWithContentsOfFile:path] : nil;
    if (image.CGImage == NULL) {
        debugLog(@"Missing theme artwork %@/%@", folder, fileName);
        return nil;
    }
    return [UIImage imageWithCGImage:image.CGImage scale:2.0 orientation:UIImageOrientationUp];
}

- (UIImage *)stretchableImage:(UIImage *)image capInsets:(UIEdgeInsets)capInsets {
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:resizingMode:)]) {
        return [image resizableImageWithCapInsets:capInsets resizingMode:UIImageResizingModeStretch];
    }
    return [image resizableImageWithCapInsets:capInsets];
}

- (UIImage *)artworkImageForSpec:(NSDictionary *)spec folder:(NSString *)folder {
    NSArray *layers = [spec objectForKey:@"layers"];
    NSString *file = [spec objectForKey:@"file"];
    if (layers == nil && file != nil) {
        layers = @[@[file, @0]];
    }
    if (layers.count == 0) {
        return nil;
    }
    NSValue *capInsets = [spec objectForKey:@"capInsets"];
    NSValue *sizeValue = [spec objectForKey:@"size"];
    NSMutableArray *images = [NSMutableArray arrayWithCapacity:layers.count];
    for (NSArray *layer in layers) {
        UIImage *image = [self artworkImageNamed:[layer objectAtIndex:0] folder:folder];
        if (image == nil) {
            return nil;
        }
        if (capInsets != nil) {
            image = [self stretchableImage:image capInsets:[capInsets UIEdgeInsetsValue]];
        }
        [images addObject:image];
    }
    if (sizeValue == nil) {
        UIImage *image = [images objectAtIndex:0];
        NSValue *alignmentInsets = [spec objectForKey:@"alignmentInsets"];
        if (alignmentInsets != nil && [image respondsToSelector:@selector(imageWithAlignmentRectInsets:)]) {
            image = [image imageWithAlignmentRectInsets:[alignmentInsets UIEdgeInsetsValue]];
        }
        return image;
    }
    CGSize size = [sizeValue CGSizeValue];
    UIGraphicsBeginImageContextWithOptions(size, NO, 2.0);
    for (NSUInteger index = 0; index < images.count; index++) {
        UIImage *image = [images objectAtIndex:index];
        CGFloat y = [[[layers objectAtIndex:index] objectAtIndex:1] floatValue];
        if (capInsets != nil) {
            [image drawInRect:CGRectMake(0, y, size.width, size.height)];
        } else {
            [image drawAtPoint:CGPointMake(0, y)];
        }
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (NSDictionary *)artworkAssetsForCurrentTheme {
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    if (artwork == nil) {
        artworkAssets = nil;
        artworkAssetsTheme = nil;
        return nil;
    }
    if (artworkAssets != nil && [artworkAssetsTheme isEqualToString:currentTheme]) {
        return artworkAssets;
    }
    artworkThemeWasUsed = YES;
    NSString *folder = [artwork objectForKey:@"folder"];
    NSMutableDictionary *assets = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"navigationBar", @"navigationBarShadow", @"tabBar", @"tabBarSelection", @"button", @"buttonPressed", @"leftButton", @"leftButtonPressed", @"backButton", @"backButtonPressed", @"actionButtonImage"]) {
        UIImage *image = [self artworkImageForSpec:[artwork objectForKey:key] folder:folder];
        if (image != nil) {
            [assets setObject:image forKey:key];
        }
    }
    artworkAssets = assets;
    artworkAssetsTheme = currentTheme;
    return artworkAssets;
}

- (NSDictionary *)textAttributesForArtwork:(NSDictionary *)artwork prefix:(NSString *)prefix {
    UIColor *color = [artwork objectForKey:[prefix stringByAppendingString:@"Color"]];
    if (color == nil) {
        return nil;
    }
    UIColor *shadowColor = [artwork objectForKey:[prefix stringByAppendingString:@"ShadowColor"]] ?: [artwork objectForKey:@"shadowColor"];
    NSValue *shadowOffset = [artwork objectForKey:[prefix stringByAppendingString:@"ShadowOffset"]] ?: [artwork objectForKey:@"shadowOffset"];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithObject:color forKey:UITextAttributeTextColor];
    if (shadowColor != nil) {
        [attributes setObject:shadowColor forKey:UITextAttributeTextShadowColor];
    }
    if (shadowOffset != nil) {
        [attributes setObject:shadowOffset forKey:UITextAttributeTextShadowOffset];
    }
    UIFont *font = [artwork objectForKey:[prefix stringByAppendingString:@"Font"]];
    if (font != nil) {
        [attributes setObject:font forKey:UITextAttributeFont];
    }
    return attributes;
}

- (void)applyButtonArtworkToBarButtonItem:(UIBarButtonItem *)item left:(BOOL)left {
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    NSDictionary *assets = [self artworkAssetsForCurrentTheme];
    NSDictionary *titleAttributes = [self textAttributesForArtwork:artwork prefix:@"buttonTitle"];
    NSString *buttonKey = (left && [assets objectForKey:@"leftButton"] != nil) ? @"leftButton" : @"button";
    [item setBackgroundImage:[assets objectForKey:buttonKey] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [item setBackgroundImage:[assets objectForKey:[buttonKey stringByAppendingString:@"Pressed"]] forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [item setBackButtonBackgroundImage:[assets objectForKey:@"backButton"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [item setBackButtonBackgroundImage:[assets objectForKey:@"backButtonPressed"] forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [item setTitleTextAttributes:titleAttributes forState:UIControlStateNormal];
    [item setTitleTextAttributes:titleAttributes forState:UIControlStateHighlighted];
}

- (void)applyArtworkToBarButtonItem:(UIBarButtonItem *)item left:(BOOL)left {
    UIButton *artworkButton = objc_getAssociatedObject(item, &kArtworkButtonKey);
    BOOL hasArtworkButton = artworkButton != nil && item.customView == artworkButton;
    if (item.customView != nil && !hasArtworkButton) {
        return;
    }
    objc_setAssociatedObject(item, &kLeftBarButtonItemKey, @(left), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    if ([[artwork objectForKey:@"buttonsAsCustomViews"] boolValue] && [self installArtworkButtonOnItem:item left:left]) {
        [self applyButtonArtworkToBarButtonItem:item left:left];
    } else {
        if (hasArtworkButton) {
            item.customView = nil;
            objc_setAssociatedObject(item, &kArtworkButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [self applyButtonArtworkToBarButtonItem:item left:left];
    }
    if (styledBarButtonItems == nil) {
        styledBarButtonItems = [NSHashTable weakObjectsHashTable];
    }
    [styledBarButtonItems addObject:item];
}


- (BOOL)installArtworkButtonOnItem:(UIBarButtonItem *)item left:(BOOL)left {
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    NSDictionary *assets = [self artworkAssetsForCurrentTheme];
    NSString *buttonKey = (left && [assets objectForKey:@"leftButton"] != nil) ? @"leftButton" : @"button";
    UIImage *background = [assets objectForKey:buttonKey];
    UIImage *pressedBackground = [assets objectForKey:[buttonKey stringByAppendingString:@"Pressed"]];
    if (background == nil) {
        return NO;
    }
    NSString *title = nil;
    UIImage *image = nil;
    BOOL isSystemItem = [item respondsToSelector:NSSelectorFromString(@"isSystemItem")] && [[item valueForKey:@"isSystemItem"] boolValue];
    if (isSystemItem) {
        if ([[item valueForKey:@"systemItem"] integerValue] != UIBarButtonSystemItemAction) {
            return NO;
        }
        image = [assets objectForKey:@"actionButtonImage"];
        if (image == nil) {
            return NO;
        }
    } else if (item.image == nil && item.title.length > 0) {
        title = item.title;
    } else {
        return NO;
    }

    UIButton *button = objc_getAssociatedObject(item, &kArtworkButtonKey);
    if (button == nil) {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button addTarget:self action:@selector(artworkButtonTapped:forEvent:) forControlEvents:UIControlEventTouchUpInside];
        ThemeArtworkButtonItemReference *reference = [[ThemeArtworkButtonItemReference alloc] init];
        reference.item = item;
        objc_setAssociatedObject(button, &kArtworkButtonItemKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(item, &kArtworkButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSValue *contentInsets = [artwork objectForKey:@"buttonContentInsets"];
    if (contentInsets != nil) {
        button.contentEdgeInsets = [contentInsets UIEdgeInsetsValue];
    }
    [button setBackgroundImage:background forState:UIControlStateNormal];
    [button setBackgroundImage:background forState:UIControlStateDisabled];
    [button setBackgroundImage:pressedBackground forState:UIControlStateHighlighted];
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:image forState:UIControlStateNormal];
    NSDictionary *titleAttributes = [self textAttributesForArtwork:artwork prefix:@"buttonTitle"];
    [button setTitleColor:[titleAttributes objectForKey:UITextAttributeTextColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:[titleAttributes objectForKey:UITextAttributeTextShadowColor] forState:UIControlStateNormal];
    NSValue *shadowOffset = [titleAttributes objectForKey:UITextAttributeTextShadowOffset];
    if (shadowOffset != nil) {
        UIOffset offset = [shadowOffset UIOffsetValue];
        button.titleLabel.shadowOffset = CGSizeMake(offset.horizontal, offset.vertical);
    }
    UIFont *font = [titleAttributes objectForKey:UITextAttributeFont];
    if (font != nil) {
        button.titleLabel.font = font;
    }
    button.enabled = item.enabled;
    [button sizeToFit];
    CGRect frame = button.frame;
    frame.size.width = MAX(frame.size.width, [[artwork objectForKey:@"buttonMinimumWidth"] floatValue]);
    button.frame = frame;
    if (item.customView != button) {
        item.customView = button;
    }
    return YES;
}



- (void)artworkButtonTapped:(UIButton *)button forEvent:(UIEvent *)event {
    UIBarButtonItem *item = [(ThemeArtworkButtonItemReference *)objc_getAssociatedObject(button, &kArtworkButtonItemKey) item];
    if (item != nil && item.action != NULL) {
        [[UIApplication sharedApplication] sendAction:item.action to:item.target from:item forEvent:event];
    }
}



- (void)updateArtworkAppearanceIfNeeded {
    if ([artworkAppearanceTheme isEqualToString:currentTheme]) {
        return;
    }
    artworkAppearanceTheme = currentTheme;
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    NSDictionary *assets = [self artworkAssetsForCurrentTheme];
    if (artwork == nil && !artworkThemeWasUsed) {
        return;
    }
    UINavigationBar *navigationBarAppearance = [UINavigationBar appearance];
    [navigationBarAppearance setTitleTextAttributes:[self textAttributesForArtwork:artwork prefix:@"title"]];
    if ([UINavigationBar instancesRespondToSelector:@selector(setShadowImage:)]) {
        [navigationBarAppearance setShadowImage:[assets objectForKey:@"navigationBarShadow"]];
    }
    [self applyButtonArtworkToBarButtonItem:[UIBarButtonItem appearanceWhenContainedIn:[UINavigationBar class], nil] left:NO];
    for (UIBarButtonItem *item in [styledBarButtonItems allObjects]) {
        [self applyArtworkToBarButtonItem:item left:[objc_getAssociatedObject(item, &kLeftBarButtonItemKey) boolValue]];
    }
}

- (void)applyArtworkToNavigationBar:(UINavigationBar *)navigationBar {
    [self updateArtworkAppearanceIfNeeded];
    NSDictionary *artwork = [self artworkForTheme:currentTheme];
    NSDictionary *assets = [self artworkAssetsForCurrentTheme];
    NSString *appliedTheme = objc_getAssociatedObject(navigationBar, &kAppliedThemeKey);
    objc_setAssociatedObject(navigationBar, &kAppliedThemeKey, currentTheme, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (artwork == nil && !artworkThemeWasUsed) {
        return;
    }
    navigationBar.titleTextAttributes = [self textAttributesForArtwork:artwork prefix:@"title"];
    if ([navigationBar respondsToSelector:@selector(setShadowImage:)]) {
        navigationBar.shadowImage = [assets objectForKey:@"navigationBarShadow"];
    }
    [self applyContentTopInsetBelowNavigationBar:navigationBar];
    [self applyArtworkToBarButtonItemsOfNavigationBar:navigationBar];
    if (appliedTheme != nil && ![appliedTheme isEqualToString:currentTheme]) {
        [self recreateBackButtonsOfNavigationBar:navigationBar];
    }
    if ([artwork objectForKey:@"contentTopInset"] != nil) {
        [self applyContentTopInsetBelowNavigationBarLater:navigationBar];
    }
    if ([[artwork objectForKey:@"buttonsAsCustomViews"] boolValue]) {
        __weak UINavigationBar *weakNavigationBar = navigationBar;
        NSString *theme = currentTheme;
        dispatch_async(dispatch_get_main_queue(), ^{
            UINavigationBar *bar = weakNavigationBar;
            if (bar != nil && [theme isEqualToString:currentTheme]) {
                [self applyArtworkToBarButtonItemsOfNavigationBar:bar];
            }
        });
    }
}



- (UIScrollView *)topScrollViewBelowNavigationBar:(UINavigationBar *)navigationBar {
    UINavigationController *navigationController = (UINavigationController *)navigationBar.delegate;
    if (![navigationController isKindOfClass:[UINavigationController class]] || ![navigationController.topViewController isViewLoaded]) {
        return nil;
    }
    UIView *view = navigationController.topViewController.view;
    if ([view isKindOfClass:[UIScrollView class]]) {
        return (UIScrollView *)view;
    }
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]] && !subview.hidden && CGRectGetMinY(subview.frame) <= 0) {
            return (UIScrollView *)subview;
        }
    }
    return nil;
}

- (void)applyContentTopInsetBelowNavigationBar:(UINavigationBar *)navigationBar {
    UIScrollView *scrollView = [self topScrollViewBelowNavigationBar:navigationBar];
    if (scrollView == nil) {
        return;
    }
    CGFloat extraInset = [[[self artworkForTheme:currentTheme] objectForKey:@"contentTopInset"] floatValue];
    NSArray *applied = objc_getAssociatedObject(scrollView, &kContentTopInsetKey);
    UIEdgeInsets contentInset = scrollView.contentInset;
    UIEdgeInsets indicatorInsets = scrollView.scrollIndicatorInsets;
    CGFloat baseTop = contentInset.top;
    CGFloat baseIndicatorTop = indicatorInsets.top;
    if (applied != nil) {
        if (contentInset.top == [[applied objectAtIndex:1] floatValue]) {
            baseTop -= [[applied objectAtIndex:0] floatValue];
        }
        if (indicatorInsets.top == [[applied objectAtIndex:2] floatValue]) {
            baseIndicatorTop -= [[applied objectAtIndex:0] floatValue];
        }
    } else if (extraInset == 0) {
        return;
    }
    if (contentInset.top == baseTop + extraInset && indicatorInsets.top == baseIndicatorTop + extraInset) {
        return;
    }
    BOOL wasAtTop = scrollView.contentOffset.y <= -contentInset.top;
    contentInset.top = baseTop + extraInset;
    indicatorInsets.top = baseIndicatorTop + extraInset;
    scrollView.contentInset = contentInset;
    scrollView.scrollIndicatorInsets = indicatorInsets;
    if (wasAtTop) {
        scrollView.contentOffset = CGPointMake(scrollView.contentOffset.x, -contentInset.top);
    }
    objc_setAssociatedObject(scrollView, &kContentTopInsetKey, (extraInset == 0 ? nil : (id)@[@(extraInset), @(contentInset.top), @(indicatorInsets.top)]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)applyContentTopInsetBelowNavigationBarLater:(UINavigationBar *)navigationBar {
    __weak UINavigationBar *weakNavigationBar = navigationBar;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationBar *bar = weakNavigationBar;
        if (bar != nil) {
            [self applyContentTopInsetBelowNavigationBar:bar];
        }
    });
}

- (void)applyArtworkToBarButtonItemsOfNavigationBar:(UINavigationBar *)navigationBar {
    for (UINavigationItem *item in navigationBar.items) {
        for (UIBarButtonItem *button in item.leftBarButtonItems) {
            [self applyArtworkToBarButtonItem:button left:YES];
        }
        for (UIBarButtonItem *button in item.rightBarButtonItems) {
            [self applyArtworkToBarButtonItem:button left:NO];
        }
        if (item.backBarButtonItem != nil) {
            [self applyArtworkToBarButtonItem:item.backBarButtonItem left:YES];
        }
    }
}



- (void)recreateBackButtonsOfNavigationBar:(UINavigationBar *)navigationBar {
    NSArray *items = navigationBar.items;
    for (NSUInteger index = 0; index + 1 < items.count; index++) {
        UINavigationItem *item = [items objectAtIndex:index];
        if (item.backBarButtonItem != nil) {
            continue;
        }
        item.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:item.title style:UIBarButtonItemStyleBordered target:nil action:NULL];
        item.backBarButtonItem = nil;
    }
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
