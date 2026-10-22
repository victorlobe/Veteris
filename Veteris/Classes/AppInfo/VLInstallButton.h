#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, VLInstallButtonStyle) {
    VLInstallButtonStyleCloud = 0,
    VLInstallButtonStyleIOS5 = 1,
    VLInstallButtonStyleIOS6 = 2,
    VLInstallButtonStyleIOS7 = 3,
    VLInstallButtonStyleModern = 4,
    VLInstallButtonStyleUIButton = 5,
};

static NSString * const VLDownloadButtonStylePreferenceKey = @"veteris_download_button_style";
static NSString * const VLInstalledAppsCloudButtonPreferenceKey = @"veteris_installed_apps_cloud_button_enabled";

static BOOL VLInstalledAppsCloudButtonEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:VLInstalledAppsCloudButtonPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

FOUNDATION_EXPORT VLInstallButtonStyle VLInstallButtonDefaultStyleForCurrentSystem(void);

FOUNDATION_EXPORT NSString *VLInstallButtonNormalTitle(VLInstallButtonStyle style);
FOUNDATION_EXPORT NSString *VLInstallButtonSelectedTitle(VLInstallButtonStyle style);

@interface VLInstallButton : UIControl {
    UIImageView *_leftSlice;
    UIImageView *_middleSlice;
    UIImageView *_rightSlice;
    UILabel *_label;
    UIImageView *_cloudImageView;
    BOOL _fatBinary;
    BOOL _expandsLeft;
    BOOL _installSelected;
    BOOL _pressed;
    CGFloat _normalWidth;
    CGFloat _selectedWidth;
    VLInstallButtonStyle _buttonStyle;
    CGFloat _currentWidth;
}

- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary;
- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft;
- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth;
- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth selectedWidth:(CGFloat)selectedWidth;
- (id)initWithFrame:(CGRect)frame style:(VLInstallButtonStyle)style;
- (id)initWithFrame:(CGRect)frame style:(VLInstallButtonStyle)style expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth selectedWidth:(CGFloat)selectedWidth;
- (void)setButtonStyle:(VLInstallButtonStyle)style;
- (VLInstallButtonStyle)buttonStyle;
+ (CGFloat)buttonWidthForText:(NSString *)text style:(VLInstallButtonStyle)style;
- (void)activate;
- (void)reset;
- (void)setSelectedWidth:(CGFloat)selectedWidth;
- (BOOL)isInstallSelected;
@end
