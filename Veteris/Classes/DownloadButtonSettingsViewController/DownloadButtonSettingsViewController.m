#import "DownloadButtonSettingsViewController.h"
#import "../AppInfo/VLInstallButton.h"
#import "../../InAppSettingsKit/Models/IASKSettingsReader.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const DownloadButtonPreviewReuseIdentifier = @"DownloadButtonPreviewCell";
static NSString * const DownloadButtonChoiceReuseIdentifier = @"DownloadButtonChoiceCell";
static NSString * const DownloadButtonInstalledAppsReuseIdentifier = @"DownloadButtonInstalledAppsCell";

static NSArray *DownloadButtonSettingsStyles(void) {
    return @[
        @(VLInstallButtonStyleUIButton),
        @(VLInstallButtonStyleIOS5),
        @(VLInstallButtonStyleIOS6),
        @(VLInstallButtonStyleIOS7),
        @(VLInstallButtonStyleModern),
        @(VLInstallButtonStyleCloud)
    ];
}

@interface DownloadButtonPreviewCell : UITableViewCell
@property (nonatomic, retain) UIView *appInfoCanvasView;
@property (nonatomic, retain) UIView *appInfoHeaderView;
@property (nonatomic, retain) UIImageView *appInfoShadowView;
@property (nonatomic, retain) UIImageView *previewIconView;
@property (nonatomic, retain) UILabel *previewNameLabel;
@property (nonatomic, retain) UILabel *previewDeveloperLabel;
@property (nonatomic, retain) UILabel *previewVersionsLabel;
@property (nonatomic, retain) VLInstallButton *previewButton;
@property (nonatomic, retain) UIButton *cloudPreviewButton;
@property (nonatomic, retain) UIButton *nativePreviewButton;
@property (nonatomic, assign) CGFloat appInfoCanvasWidth;
- (void)setPreviewStyle:(VLInstallButtonStyle)style;
@end

@implementation DownloadButtonPreviewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.clipsToBounds = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.clipsToBounds = NO;
        self.contentView.backgroundColor = [UIColor clearColor];
        self.backgroundView = [[UIView alloc] initWithFrame:CGRectZero];
        self.backgroundView.backgroundColor = [UIColor clearColor];

        self.appInfoCanvasWidth = 320.0;
        self.appInfoCanvasView = [[UIView alloc] initWithFrame:CGRectZero];
        self.appInfoCanvasView.backgroundColor = [UIColor clearColor];
        self.appInfoCanvasView.clipsToBounds = NO;
        [self.contentView addSubview:self.appInfoCanvasView];

        self.appInfoHeaderView = [[UIView alloc] initWithFrame:CGRectZero];
        self.appInfoHeaderView.backgroundColor = [UIColor clearColor];
        [self.appInfoCanvasView addSubview:self.appInfoHeaderView];

        self.appInfoShadowView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.appInfoShadowView.image = [UIImage imageNamed:@"DepthShadow.png"];
        self.appInfoShadowView.contentMode = UIViewContentModeScaleToFill;
        self.appInfoShadowView.userInteractionEnabled = NO;
        [self.appInfoCanvasView addSubview:self.appInfoShadowView];

        self.previewIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        self.previewIconView.contentMode = UIViewContentModeScaleToFill;
        self.previewIconView.userInteractionEnabled = NO;
        self.previewIconView.layer.cornerRadius = 13.0;
        self.previewIconView.layer.masksToBounds = YES;
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon60x60@2x" ofType:@"png"];
        self.previewIconView.image = iconPath != nil ? [UIImage imageWithContentsOfFile:iconPath] : [UIImage imageNamed:@"Icon.png"];
        [self.appInfoHeaderView addSubview:self.previewIconView];

        self.previewNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.previewNameLabel.backgroundColor = [UIColor clearColor];
        self.previewNameLabel.text = @"Veteris";
        self.previewNameLabel.font = [UIFont boldSystemFontOfSize:17.0];
        self.previewNameLabel.minimumFontSize = 5.0;
        self.previewNameLabel.adjustsFontSizeToFitWidth = YES;
        self.previewNameLabel.userInteractionEnabled = NO;
        [self.appInfoHeaderView addSubview:self.previewNameLabel];

        self.previewDeveloperLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.previewDeveloperLabel.backgroundColor = [UIColor clearColor];
        self.previewDeveloperLabel.text = @"Victor";
        self.previewDeveloperLabel.alpha = 0.75;
        self.previewDeveloperLabel.font = [UIFont fontWithName:@"Helvetica" size:12.0];
        self.previewDeveloperLabel.minimumFontSize = 5.0;
        self.previewDeveloperLabel.adjustsFontSizeToFitWidth = YES;
        self.previewDeveloperLabel.userInteractionEnabled = NO;
        [self.appInfoHeaderView addSubview:self.previewDeveloperLabel];

        self.previewVersionsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.previewVersionsLabel.backgroundColor = [UIColor clearColor];
        self.previewVersionsLabel.text = @"12 versions";
        self.previewVersionsLabel.alpha = 0.75;
        self.previewVersionsLabel.font = [UIFont fontWithName:@"Helvetica" size:10.0];
        self.previewVersionsLabel.userInteractionEnabled = NO;
        [self.appInfoHeaderView addSubview:self.previewVersionsLabel];

        self.previewIconView.hidden = YES;
        self.previewNameLabel.hidden = YES;
        self.previewDeveloperLabel.hidden = YES;
        self.previewVersionsLabel.hidden = YES;
        self.appInfoShadowView.hidden = YES;

        self.previewButton = [[VLInstallButton alloc] initWithFrame:CGRectMake(253.0, 62.0, 47.0, 28.0)
                                                                style:VLInstallButtonStyleCloud
                                                          expandsLeft:YES
                                                           normalWidth:47.0
                                                         selectedWidth:47.0];
        self.previewButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.appInfoHeaderView addSubview:self.previewButton];

        self.cloudPreviewButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.cloudPreviewButton.frame = CGRectMake(0.0, 0.0, 47.0, 28.0);
        self.cloudPreviewButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.cloudPreviewButton setBackgroundImage:[UIImage imageNamed:@"DownloadButton.png"] forState:UIControlStateNormal];
        [self.appInfoHeaderView addSubview:self.cloudPreviewButton];

        self.nativePreviewButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        NSString *nativeButtonTitle = VLInstallButtonNormalTitle(VLInstallButtonStyleUIButton);
        CGFloat nativeButtonWidth = [VLInstallButton buttonWidthForText:nativeButtonTitle style:VLInstallButtonStyleUIButton];
        self.nativePreviewButton.frame = CGRectMake(0.0, 0.0, nativeButtonWidth, 30.0);
        [self.nativePreviewButton setTitle:nativeButtonTitle forState:UIControlStateNormal];
        [self.appInfoHeaderView addSubview:self.nativePreviewButton];
        self.previewButton.hidden = YES;
        self.nativePreviewButton.hidden = YES;

        [self.appInfoHeaderView bringSubviewToFront:self.previewButton];
        [self.appInfoHeaderView bringSubviewToFront:self.cloudPreviewButton];
        [self.appInfoHeaderView bringSubviewToFront:self.nativePreviewButton];
    }
    return self;
}

- (void)setPreviewStyle:(VLInstallButtonStyle)style {
    self.previewButton.transform = CGAffineTransformIdentity;
    self.cloudPreviewButton.transform = CGAffineTransformIdentity;
    self.nativePreviewButton.transform = CGAffineTransformIdentity;
    self.cloudPreviewButton.hidden = style != VLInstallButtonStyleCloud;
    self.nativePreviewButton.hidden = style != VLInstallButtonStyleUIButton;
    self.previewButton.hidden = style == VLInstallButtonStyleCloud || style == VLInstallButtonStyleUIButton;
    if (style == VLInstallButtonStyleCloud) {
        [self setNeedsLayout];
        return;
    }
    if (style == VLInstallButtonStyleUIButton) {
        [self setNeedsLayout];
        return;
    }
    [self.previewButton reset];
    CGFloat normalWidth = [VLInstallButton buttonWidthForText:VLInstallButtonNormalTitle(style) style:style];
    CGFloat selectedWidth = [VLInstallButton buttonWidthForText:VLInstallButtonSelectedTitle(style) style:style];
    CGRect frame = self.previewButton.frame;
    frame.origin.x = self.appInfoCanvasWidth - 20.0 - normalWidth;
    frame.origin.y = 62.0;
    frame.size.width = normalWidth;
    frame.size.height = style == VLInstallButtonStyleIOS6 ? 27.0 : (style == VLInstallButtonStyleModern ? 32.0 : (style == VLInstallButtonStyleCloud ? 28.0 : 25.0));
    self.previewButton.frame = frame;
    [self.previewButton setButtonStyle:style];
    [self.previewButton setSelectedWidth:selectedWidth];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat contentWidth = self.contentView.bounds.size.width;
    CGFloat canvasWidth = self.appInfoCanvasWidth;
    UIView *superview = self.superview;
    while (superview != nil && ![superview isKindOfClass:[UITableView class]]) {
        superview = superview.superview;
    }
    if ([superview isKindOfClass:[UITableView class]] && superview.bounds.size.width > 0.0) {
        canvasWidth = superview.bounds.size.width;
        self.appInfoCanvasWidth = canvasWidth;
    }

    CGFloat contentHeight = self.contentView.bounds.size.height;
    self.appInfoCanvasView.frame = CGRectMake(floor((contentWidth - canvasWidth) / 2.0), 0.0, canvasWidth, contentHeight);

    self.appInfoHeaderView.frame = CGRectMake(0.0, 0.0, canvasWidth, contentHeight);
    self.appInfoShadowView.frame = CGRectMake(0.0, 111.0, canvasWidth, 44.0);
    self.previewIconView.frame = CGRectMake(20.0, 20.0, 70.0, 70.0);
    self.previewNameLabel.frame = CGRectMake(100.0, 20.0, 179.0, 23.0);
    self.previewDeveloperLabel.frame = CGRectMake(100.0, 44.0, 138.0, 21.0);
    self.previewVersionsLabel.frame = CGRectMake(100.0, 69.0, 138.0, 21.0);

    UIControl *activeButton = self.cloudPreviewButton.hidden
        ? (self.nativePreviewButton.hidden ? self.previewButton : self.nativePreviewButton)
        : self.cloudPreviewButton;
    activeButton.transform = CGAffineTransformIdentity;
    activeButton.center = CGPointMake(canvasWidth / 2.0, contentHeight / 2.0);
}

@end

@interface DownloadButtonSettingsViewController ()
@property (nonatomic, retain) DownloadButtonPreviewCell *previewCell;
@end

@implementation DownloadButtonSettingsViewController

- (id)initWithFile:(NSString *)file withKey:(NSString *)key {
    return [self initWithStyle:UITableViewStyleGrouped];
}

- (NSString *)settingsString:(NSString *)key {
    NSString *settingsBundlePath = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSBundle *settingsBundle = settingsBundlePath != nil ? [NSBundle bundleWithPath:settingsBundlePath] : nil;
    return NSLocalizedStringFromTableInBundle(key, @"Root", settingsBundle != nil ? settingsBundle : [NSBundle mainBundle], nil);
}

- (VLInstallButtonStyle)selectedStyle {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:VLDownloadButtonStylePreferenceKey];
    if (value == nil) {
        return VLInstallButtonDefaultStyleForCurrentSystem();
    }
    NSInteger style = [value integerValue];
    return (style >= VLInstallButtonStyleCloud && style <= VLInstallButtonStyleUIButton) ? (VLInstallButtonStyle)style : VLInstallButtonStyleUIButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self settingsString:@"Download Button"];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.previewCell setPreviewStyle:[self selectedStyle]];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    }
    return section == 1 ? [DownloadButtonSettingsStyles() count] : 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 100.0 : 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return 0.1;
    }

    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (title.length == 0) {
        return 0.0;
    }

    UIFont *font = [UIFont boldSystemFontOfSize:[UIFont labelFontSize]];
    CGSize titleSize = [title sizeWithFont:font
                         constrainedToSize:CGSizeMake(tableView.bounds.size.width - 38.0, CGFLOAT_MAX)
                             lineBreakMode:NSLineBreakByWordWrapping];
    return ceil(titleSize.height + 15.0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) {
        return [self settingsString:@"Button Style"];
    }
    return section == 0 ? nil : [self settingsString:@"Installed Apps"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        self.previewCell = [tableView dequeueReusableCellWithIdentifier:DownloadButtonPreviewReuseIdentifier];
        if (self.previewCell == nil) {
            self.previewCell = [[DownloadButtonPreviewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DownloadButtonPreviewReuseIdentifier];
            [self.previewCell.previewButton addTarget:self action:@selector(previewButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.previewCell.cloudPreviewButton addTarget:self action:@selector(previewButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        [self.previewCell setPreviewStyle:[self selectedStyle]];
        return self.previewCell;
    }

    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DownloadButtonInstalledAppsReuseIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DownloadButtonInstalledAppsReuseIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = [self settingsString:@"Show Cloud Button"];
        UISwitch *cloudButtonSwitch = (UISwitch *)cell.accessoryView;
        if (![cloudButtonSwitch isKindOfClass:[UISwitch class]]) {
            cloudButtonSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
            [cloudButtonSwitch addTarget:self action:@selector(installedAppsCloudButtonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = cloudButtonSwitch;
        }
        cloudButtonSwitch.on = VLInstalledAppsCloudButtonEnabled();
        cloudButtonSwitch.enabled = [self selectedStyle] != VLInstallButtonStyleCloud;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DownloadButtonChoiceReuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DownloadButtonChoiceReuseIdentifier];
    }
    NSArray *styles = DownloadButtonSettingsStyles();
    VLInstallButtonStyle style = [[styles objectAtIndex:indexPath.row] integerValue];
    NSString *title;
    switch (style) {
        case VLInstallButtonStyleCloud:
            title = [self settingsString:@"Cloud"];
            break;
        case VLInstallButtonStyleIOS5:
            title = [self settingsString:@"iOS 5"];
            break;
        case VLInstallButtonStyleIOS6:
            title = [self settingsString:@"iOS 6"];
            break;
        case VLInstallButtonStyleIOS7:
            title = [self settingsString:@"iOS 7"];
            break;
        case VLInstallButtonStyleModern:
            title = [self settingsString:@"iOS 26"];
            break;
        case VLInstallButtonStyleUIButton:
        default:
            title = [self settingsString:@"UIButton"];
            break;
    }
    if (style == VLInstallButtonDefaultStyleForCurrentSystem()) {
        title = [NSString stringWithFormat:@"%@ (%@)", title, [self settingsString:@"Default"]];
    }
    cell.textLabel.text = title;
    cell.accessoryType = [self selectedStyle] == style ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)installedAppsCloudButtonSwitchChanged:(UISwitch *)cloudButtonSwitch {
    [[NSUserDefaults standardUserDefaults] setBool:cloudButtonSwitch.on forKey:VLInstalledAppsCloudButtonPreferenceKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIASKAppSettingChanged
                                                        object:VLInstalledAppsCloudButtonPreferenceKey
                                                      userInfo:@{VLInstalledAppsCloudButtonPreferenceKey : [NSNumber numberWithBool:cloudButtonSwitch.on]}];
}

- (void)previewButtonTapped:(UIControl *)button {
    if (![button isKindOfClass:[VLInstallButton class]]) {
        return;
    }
    VLInstallButton *installButton = (VLInstallButton *)button;
    if ([installButton buttonStyle] == VLInstallButtonStyleCloud) {
        return;
    }
    if ([installButton buttonStyle] == VLInstallButtonStyleModern) {
        return;
    }
    if ([installButton isInstallSelected]) {
        [installButton reset];
    } else {
        [installButton activate];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    NSArray *styles = DownloadButtonSettingsStyles();
    VLInstallButtonStyle style = [[styles objectAtIndex:indexPath.row] integerValue];
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:VLDownloadButtonStylePreferenceKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIASKAppSettingChanged
                                                        object:VLDownloadButtonStylePreferenceKey
                                                      userInfo:@{VLDownloadButtonStylePreferenceKey : [NSNumber numberWithInteger:style]}];
    [self.previewCell setPreviewStyle:style];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
