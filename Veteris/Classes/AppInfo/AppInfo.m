//
//  AppInfo.m
//  Veteris
//
//  Created by electimon on 6/8/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "AppInfo.h"
#include <Foundation/NSBundle.h>
#include <math.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import "../../AppDelegate.h"
#import "../../SVProgressHUD/SVProgressHUD.h"
#import "../Convenience/Convenience.h"
#import "../ProtoStack.h"
#import "../Protos/Application.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../YZQueue/YZQueueManager.h"
#import "../SearchViewController/SearchTableViewCell.h"
#import "../Favorites/VeterisFavoritesManager.h"

typedef NS_ENUM(NSInteger, AppInfoSection) {
    AppInfoSectionDetails = 0,
    AppInfoSectionVersions = 1,
    AppInfoSectionRelated = 2
};

static NSInteger const AppInfoVersionPickerActionSheetTag = 1001;
static NSInteger const AppInfoVersionCellActionSheetTag = 1002;
static NSInteger const AppInfoActionsActionSheetTag = 1003;
static NSInteger const AppInfoNoPendingVersionIndex = -1;
static NSInteger const AppInfoVersionActionInstallIndex = 0;
static NSInteger const AppInfoVersionActionDownloadIndex = 1;
static NSInteger const AppInfoVersionActionInfoIndex = 2;
static NSInteger const AppInfoActionFavoriteIndex = 0;
static NSInteger const AppInfoActionCopyLinkIndex = 1;
static NSInteger const AppInfoRecommendedBadgeTag = 5401;
static NSString * const AppInfoDownloadOnlyInfoShownDefaultsKey = @"AppInfoDownloadOnlyInfoShown";
static char AppInfoFavoriteActivityApplicationKey;

@interface AppInfoRecommendedBadgeLabel : UILabel
@end

@implementation AppInfoRecommendedBadgeLabel

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect textRect = [super textRectForBounds:bounds limitedToNumberOfLines:numberOfLines];
    textRect.origin.x = bounds.origin.x;
    textRect.size.width = bounds.size.width;
    textRect.origin.y = bounds.origin.y + floor((bounds.size.height - textRect.size.height) / 2.0);
    return textRect;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:[self textRectForBounds:rect limitedToNumberOfLines:self.numberOfLines]];
}

@end

static UIView *AppInfoActionSheetPresentationView(UIView *fallbackView) {
    return fallbackView.window ?: fallbackView;
}

static NSString *AppInfoURLEscape(NSString *value) {
    if (value == nil) {
        return @"";
    }
    NSString *escaped = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        NULL,
        (CFStringRef)value,
        NULL,
        (CFStringRef)@"!*'();:@&=+$,/?%#[]",
        kCFStringEncodingUTF8
    ));
    return escaped ?: @"";
}

static NSString *AppInfoStringForByteCount(unsigned long long bytes) {
    if (bytes == 0) {
        return nil;
    }

    double value = (double)bytes;
    NSArray *units = [NSArray arrayWithObjects:@"bytes", @"KB", @"MB", @"GB", nil];
    NSUInteger unitIndex = 0;
    while (value >= 1024.0 && unitIndex < [units count] - 1) {
        value /= 1024.0;
        unitIndex++;
    }

    if (unitIndex == 0) {
        return [NSString stringWithFormat:@"%llu %@", bytes, [units objectAtIndex:unitIndex]];
    }
    return [NSString stringWithFormat:@"%.1f %@", value, [units objectAtIndex:unitIndex]];
}

static NSString *AppInfoTrimmedString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *AppInfoDisplayBundleIDForApplication(Application *application) {
    NSString *primaryBundleID = AppInfoTrimmedString(application.primaryBundleID);
    if ([primaryBundleID length] > 0) {
        return primaryBundleID;
    }
    return AppInfoTrimmedString(application.bundleid);
}

static NSString *AppInfoDisplayBundleIDForVersion(Application *application, Version *version) {
    NSString *versionBundleID = AppInfoTrimmedString(version.bundleID);
    if ([versionBundleID length] > 0) {
        return versionBundleID;
    }
    return AppInfoDisplayBundleIDForApplication(application);
}

static NSString *AppInfoDistinctBundleIDForVersion(Application *application, Version *version) {
    NSString *versionBundleID = AppInfoTrimmedString(version.bundleID);
    NSString *appBundleID = AppInfoDisplayBundleIDForApplication(application);
    if ([versionBundleID length] > 0 && ![versionBundleID isEqualToString:appBundleID]) {
        return versionBundleID;
    }
    return @"";
}

static NSString *AppInfoVersionDisplayTitle(Application *application, Version *version) {
    NSString *versionText = AppInfoTrimmedString(version.version);
    NSString *bundleID = AppInfoDistinctBundleIDForVersion(application, version);
    if ([bundleID length] > 0) {
        return [NSString stringWithFormat:@"%@ - %@", versionText, bundleID];
    }
    return versionText;
}

static BOOL AppInfoVersionIsRecommended(Application *application, Version *version) {
    if (version.recommended) {
        return YES;
    }
    return NO;
}

static UILabel *AppInfoRecommendedBadge(void) {
    UIColor *accentColor = [UIColor colorWithRed:191.0 / 255.0 green:72.0 / 255.0 blue:0.0 alpha:1.0];
    UILabel *badge = [[AppInfoRecommendedBadgeLabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 78.0, 14.0)];
    badge.tag = AppInfoRecommendedBadgeTag;
    badge.text = @"Recommended";
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:8.5];
    badge.textColor = accentColor;
    badge.backgroundColor = [UIColor clearColor];
    badge.layer.cornerRadius = 7.0;
    badge.layer.masksToBounds = YES;
    badge.layer.borderColor = [accentColor CGColor];
    badge.layer.borderWidth = 1.0;
    return badge;
}

static void AppInfoConfigureRecommendedBadge(UITableViewCell *cell, BOOL recommended) {
    UILabel *badge = (UILabel *)[cell.contentView viewWithTag:AppInfoRecommendedBadgeTag];
    if (!recommended) {
        [badge removeFromSuperview];
        return;
    }
    if (badge == nil) {
        badge = AppInfoRecommendedBadge();
        badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cell.contentView addSubview:badge];
    }
    CGFloat width = 78.0;
    CGFloat height = 14.0;
    CGFloat x = MAX(0.0, cell.contentView.bounds.size.width - width - 12.0);
    CGFloat labelCenterY = CGRectGetMidY(cell.detailTextLabel.frame);
    if (labelCenterY <= 0.0) {
        labelCenterY = 38.0;
    }
    badge.frame = CGRectMake(x, floor(labelCenterY - height / 2.0), width, height);
}

static UIImage *AppInfoFavoriteActivityImage(void) {
    CGSize size = CGSizeMake(43.0, 43.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);

    CGPoint center = CGPointMake(size.width / 2.0, size.height / 2.0);
    CGFloat outerRadius = 17.0;
    CGFloat innerRadius = 7.2;
    UIBezierPath *starPath = [UIBezierPath bezierPath];
    for (NSUInteger index = 0; index < 10; index++) {
        CGFloat radius = (index % 2 == 0) ? outerRadius : innerRadius;
        CGFloat angle = (-M_PI_2) + ((CGFloat)index * (CGFloat)M_PI / 5.0);
        CGPoint point = CGPointMake(center.x + cosf(angle) * radius, center.y + sinf(angle) * radius);
        if (index == 0) {
            [starPath moveToPoint:point];
        } else {
            [starPath addLineToPoint:point];
        }
    }
    [starPath closePath];
    [[UIColor blackColor] setFill];
    [starPath fill];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static Application *AppInfoFavoriteActivityApplication(id activity) {
    return objc_getAssociatedObject(activity, &AppInfoFavoriteActivityApplicationKey);
}

static id AppInfoFavoriteActivityType(id self, SEL _cmd) {
    return @"me.victorlobe.veteris.favorite";
}

static id AppInfoFavoriteActivityTitle(id self, SEL _cmd) {
    Application *application = AppInfoFavoriteActivityApplication(self);
    BOOL favorite = [VeterisFavoritesManager isFavoriteBundleID:application.bundleid];
    return favorite ? NSLocalizedString(@"RemoveFromFavorites", nil) : NSLocalizedString(@"AddToFavorites", nil);
}

static id AppInfoFavoriteActivityActivityImage(id self, SEL _cmd) {
    return AppInfoFavoriteActivityImage();
}

static BOOL AppInfoFavoriteActivityCanPerform(id self, SEL _cmd, NSArray *activityItems) {
    Application *application = AppInfoFavoriteActivityApplication(self);
    return ([application.bundleid length] > 0);
}

static void AppInfoFavoriteActivityPrepare(id self, SEL _cmd, NSArray *activityItems) {
}

static void AppInfoFavoriteActivityPerform(id self, SEL _cmd) {
    Application *application = AppInfoFavoriteActivityApplication(self);
    if (application != nil) {
        [VeterisFavoritesManager toggleFavoriteApplication:application];
    }
    if ([self respondsToSelector:@selector(activityDidFinish:)]) {
        IMP imp = [self methodForSelector:@selector(activityDidFinish:)];
        void (*activityDidFinish)(id, SEL, BOOL) = (void *)imp;
        activityDidFinish(self, @selector(activityDidFinish:), YES);
    }
}

static Class AppInfoFavoriteActivityClass(void) {
    static Class favoriteActivityClass = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class activityClass = NSClassFromString(@"UIActivity");
        if (activityClass == Nil) {
            return;
        }
        favoriteActivityClass = objc_allocateClassPair(activityClass, "AppInfoFavoriteActivity", 0);
        class_addMethod(favoriteActivityClass, @selector(activityType), (IMP)AppInfoFavoriteActivityType, "@@:");
        class_addMethod(favoriteActivityClass, @selector(activityTitle), (IMP)AppInfoFavoriteActivityTitle, "@@:");
        class_addMethod(favoriteActivityClass, @selector(activityImage), (IMP)AppInfoFavoriteActivityActivityImage, "@@:");
        class_addMethod(favoriteActivityClass, @selector(canPerformWithActivityItems:), (IMP)AppInfoFavoriteActivityCanPerform, "c@:@");
        class_addMethod(favoriteActivityClass, @selector(prepareWithActivityItems:), (IMP)AppInfoFavoriteActivityPrepare, "v@:@");
        class_addMethod(favoriteActivityClass, @selector(performActivity), (IMP)AppInfoFavoriteActivityPerform, "v@:");
        objc_registerClassPair(favoriteActivityClass);
    });
    return favoriteActivityClass;
}

static id AppInfoFavoriteActivityForApplication(Application *application) {
    Class favoriteActivityClass = AppInfoFavoriteActivityClass();
    if (favoriteActivityClass == Nil || application == nil) {
        return nil;
    }
    id activity = [[favoriteActivityClass alloc] init];
    objc_setAssociatedObject(activity, &AppInfoFavoriteActivityApplicationKey, application, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return activity;
}

static NSArray *AppInfoExcludedSystemActivityTypes(void) {
    NSMutableArray *excludedTypes = [NSMutableArray array];
    NSString *systemTypes[] = {
        UIActivityTypePostToWeibo,
        UIActivityTypePrint,
        UIActivityTypeAssignToContact,
        UIActivityTypeSaveToCameraRoll
    };

    for (NSUInteger index = 0; index < sizeof(systemTypes) / sizeof(systemTypes[0]); index++) {
        if (systemTypes[index] != nil) {
            [excludedTypes addObject:systemTypes[index]];
        }
    }
    return excludedTypes;
}

@interface AppInfoTabButton : UIButton
@end

@interface AppInfoBadgeView : UIView
- (void)setCaption:(NSString *)caption value:(NSString *)value;
@end

@interface AppInfoDetailRowView : UIView
@property (nonatomic, assign) BOOL showsSeparator;
@property (nonatomic, copy) NSString *copyableValue;
@property (nonatomic, copy) NSString *openURLString;
- (void)setCaption:(NSString *)caption value:(NSString *)value;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@interface AppInfoCustomInfoBlockView : UIView
- (void)applyTitleFont:(UIFont *)font textColor:(UIColor *)textColor;
- (void)setTitle:(NSString *)title body:(NSString *)body fields:(NSArray *)fields;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@interface AppInfoContentTransitionView : UIView
@end

@interface AppInfoSectionBarBackground : UIView
@property (nonatomic, assign) CGRect cutoutFrame;
@end

@implementation AppInfoTabButton

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (self.selected) {
        CGRect pillRect = CGRectMake(0.5, 0.5, rect.size.width - 1.0, 22.0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetAllowsAntialiasing(context, YES);
        CGContextSetShouldAntialias(context, YES);

        UIBezierPath *pillPath = [UIBezierPath bezierPathWithRoundedRect:pillRect cornerRadius:11.0];

        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 0.0, [UIColor whiteColor].CGColor);
        [[UIColor colorWithWhite:0.0 alpha:0.15] setFill];
        [pillPath fill];
        CGContextRestoreGState(context);

        CGContextSaveGState(context);
        [pillPath addClip];
        CGRect shadowRect = CGRectInset(pillRect, -12.0, -12.0);
        UIBezierPath *innerShadowPath = [UIBezierPath bezierPathWithRect:shadowRect];
        [innerShadowPath appendPath:pillPath];
        innerShadowPath.usesEvenOddFillRule = YES;
        CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 1.5, [UIColor colorWithWhite:0.0 alpha:0.6].CGColor);
        [[UIColor blackColor] setFill];
        [innerShadowPath fill];
        CGContextRestoreGState(context);

        [[UIColor colorWithWhite:0.0 alpha:0.28] setStroke];
        pillPath.lineWidth = 1.0;
        [pillPath stroke];
    }

    [super drawRect:rect];
}

@end

@implementation AppInfoBadgeView {
    UILabel *captionLabel;
    UILabel *valueLabel;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;

        captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        captionLabel.backgroundColor = [UIColor clearColor];
        captionLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:10.0];
        captionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        captionLabel.shadowColor = [UIColor whiteColor];
        captionLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        captionLabel.textAlignment = NSTextAlignmentCenter;
        captionLabel.adjustsFontSizeToFitWidth = YES;
        captionLabel.minimumFontSize = 8.0;
        [self addSubview:captionLabel];

        valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        valueLabel.backgroundColor = [UIColor clearColor];
        valueLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13.0];
        valueLabel.textColor = [UIColor colorWithWhite:0.22 alpha:1.0];
        valueLabel.shadowColor = [UIColor whiteColor];
        valueLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        valueLabel.textAlignment = NSTextAlignmentCenter;
        valueLabel.adjustsFontSizeToFitWidth = NO;
        valueLabel.numberOfLines = 2;
        valueLabel.lineBreakMode = NSLineBreakByWordWrapping;
        valueLabel.minimumFontSize = 9.0;
        [self addSubview:valueLabel];
    }
    return self;
}

- (void)setCaption:(NSString *)caption value:(NSString *)value {
    captionLabel.text = [caption uppercaseString];
    valueLabel.text = value;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat horizontalInset = 6.0;
    CGFloat labelWidth = width - horizontalInset * 2.0;
    captionLabel.frame = CGRectMake(horizontalInset, 7.0, labelWidth, 12.0);
    valueLabel.frame = CGRectMake(horizontalInset, 21.0, labelWidth, 30.0);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    CGRect pillRect = CGRectMake(0.5, 0.5, rect.size.width - 1.0, rect.size.height - 2.0);
    UIBezierPath *pillPath = [UIBezierPath bezierPathWithRoundedRect:pillRect cornerRadius:8.0];

    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 0.0, [UIColor whiteColor].CGColor);
    [[UIColor colorWithWhite:0.0 alpha:0.08] setFill];
    [pillPath fill];
    CGContextRestoreGState(context);

    CGContextSaveGState(context);
    [pillPath addClip];
    CGRect shadowRect = CGRectInset(pillRect, -12.0, -12.0);
    UIBezierPath *innerShadowPath = [UIBezierPath bezierPathWithRect:shadowRect];
    [innerShadowPath appendPath:pillPath];
    innerShadowPath.usesEvenOddFillRule = YES;
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 2.0, [UIColor colorWithWhite:0.0 alpha:0.4].CGColor);
    [[UIColor blackColor] setFill];
    [innerShadowPath fill];
    CGContextRestoreGState(context);

    [[UIColor colorWithWhite:0.0 alpha:0.2] setStroke];
    pillPath.lineWidth = 1.0;
    [pillPath stroke];
}

@end

@implementation AppInfoDetailRowView {
    UILabel *captionLabel;
    UILabel *valueLabel;
    UIView *separatorLineView;
    UIView *separatorHighlightView;
    UILongPressGestureRecognizer *copyGestureRecognizer;
    UITapGestureRecognizer *openGestureRecognizer;
    UIColor *normalValueTextColor;
}

@synthesize showsSeparator;
@synthesize copyableValue;
@synthesize openURLString;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        showsSeparator = YES;

        captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        captionLabel.backgroundColor = [UIColor clearColor];
        captionLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:11.0];
        captionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        captionLabel.shadowColor = [UIColor whiteColor];
        captionLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self addSubview:captionLabel];

        valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        valueLabel.backgroundColor = [UIColor clearColor];
        valueLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:13.0];
        normalValueTextColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        valueLabel.textColor = normalValueTextColor;
        valueLabel.shadowColor = [UIColor whiteColor];
        valueLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        valueLabel.numberOfLines = 0;
        valueLabel.lineBreakMode = NSLineBreakByCharWrapping;
        [self addSubview:valueLabel];

        separatorLineView = [[UIView alloc] initWithFrame:CGRectZero];
        separatorLineView.backgroundColor = [UIColor colorWithWhite:0.78 alpha:1.0];
        [self addSubview:separatorLineView];

        separatorHighlightView = [[UIView alloc] initWithFrame:CGRectZero];
        separatorHighlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.75];
        [self addSubview:separatorHighlightView];

        copyGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(copyGestureRecognized:)];
        [self addGestureRecognizer:copyGestureRecognizer];
        openGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openGestureRecognized:)];
        [self addGestureRecognizer:openGestureRecognizer];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(copyMenuDidHide:)
                                                     name:UIMenuControllerDidHideMenuNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setCaption:(NSString *)caption value:(NSString *)value {
    captionLabel.text = caption;
    valueLabel.text = value;
}

- (void)setShowsSeparator:(BOOL)shows {
    showsSeparator = shows;
    separatorLineView.hidden = !shows;
    separatorHighlightView.hidden = !shows;
}

- (void)setCopyableValue:(NSString *)value {
    if (copyableValue != value) {
        copyableValue = [value copy];
    }
    [self updateUserInteractionEnabled];
}

- (void)setOpenURLString:(NSString *)value {
    if (openURLString != value) {
        openURLString = [value copy];
    }
    valueLabel.textColor = ([openURLString length] > 0)
        ? [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0]
        : normalValueTextColor;
    [self updateUserInteractionEnabled];
}

- (void)updateUserInteractionEnabled {
    self.userInteractionEnabled = ([copyableValue length] > 0 || [openURLString length] > 0);
}

- (BOOL)canBecomeFirstResponder {
    return ([copyableValue length] > 0);
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(copy:)) {
        return ([copyableValue length] > 0);
    }
    return NO;
}

- (void)copy:(id)sender {
    if ([copyableValue length] == 0) {
        return;
    }
    [UIPasteboard generalPasteboard].string = copyableValue;
}

- (void)setCopyHighlighted:(BOOL)highlighted {
    UIColor *highlightColor = nil;
    if ([self respondsToSelector:@selector(tintColor)]) {
        highlightColor = self.tintColor;
    }
    if (highlightColor == nil) {
        highlightColor = [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0];
    }
    valueLabel.textColor = highlighted ? highlightColor : normalValueTextColor;
}

- (void)copyMenuDidHide:(NSNotification *)notification {
    [self setCopyHighlighted:NO];
}

- (void)copyGestureRecognized:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateBegan || [copyableValue length] == 0) {
        return;
    }
    [self becomeFirstResponder];
    [self setCopyHighlighted:YES];
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    [menuController setTargetRect:self.bounds inView:self];
    [menuController setMenuVisible:YES animated:YES];
}

- (void)openGestureRecognized:(UITapGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded || [openURLString length] == 0) {
        return;
    }
    NSURL *url = [NSURL URLWithString:openURLString];
    if (url == nil || [url scheme] == nil) {
        return;
    }
    [[UIApplication sharedApplication] openURL:url];
}

- (CGFloat)valueHeightForWidth:(CGFloat)width {
    if ([valueLabel.text length] == 0) {
        return 0.0;
    }
    CGSize size = [valueLabel.text sizeWithFont:valueLabel.font
                              constrainedToSize:CGSizeMake(width, 10000.0)
                                  lineBreakMode:valueLabel.lineBreakMode];
    return ceil(size.height);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    return 9.0 + 14.0 + 3.0 + [self valueHeightForWidth:width] + 10.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    captionLabel.frame = CGRectMake(0.0, 9.0, width, 14.0);
    valueLabel.frame = CGRectMake(0.0, 26.0, width, [self valueHeightForWidth:width]);
    separatorLineView.frame = CGRectMake(0.0, self.bounds.size.height - 2.0, width, 1.0);
    separatorHighlightView.frame = CGRectMake(0.0, self.bounds.size.height - 1.0, width, 1.0);
}

@end

@implementation AppInfoCustomInfoBlockView {
    UILabel *titleLabel;
    UILabel *bodyLabel;
    NSMutableArray *fieldRowViews;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        fieldRowViews = [[NSMutableArray alloc] init];

        titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.backgroundColor = [UIColor clearColor];
        titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:16.0];
        titleLabel.textColor = [UIColor colorWithWhite:0.28 alpha:1.0];
        titleLabel.shadowColor = [UIColor whiteColor];
        titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:titleLabel];

        bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        bodyLabel.backgroundColor = [UIColor clearColor];
        bodyLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        bodyLabel.textColor = [UIColor darkTextColor];
        bodyLabel.shadowColor = [UIColor whiteColor];
        bodyLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        bodyLabel.numberOfLines = 0;
        bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:bodyLabel];
    }
    return self;
}

- (void)applyTitleFont:(UIFont *)font textColor:(UIColor *)textColor {
    titleLabel.font = font ?: [UIFont fontWithName:@"HelveticaNeue-Bold" size:16.0];
    titleLabel.textColor = textColor ?: [UIColor colorWithWhite:0.28 alpha:1.0];
}

- (void)setTitle:(NSString *)title body:(NSString *)body fields:(NSArray *)fields {
    titleLabel.text = title;
    bodyLabel.text = body;
    for (UIView *view in fieldRowViews) {
        [view removeFromSuperview];
    }
    [fieldRowViews removeAllObjects];
    for (ApplicationInfoField *field in fields) {
        NSString *label = AppInfoTrimmedString(field.label);
        NSString *value = AppInfoTrimmedString(field.value);
        if ([label length] == 0 && [value length] == 0) {
            continue;
        }
        AppInfoDetailRowView *row = [[AppInfoDetailRowView alloc] initWithFrame:CGRectZero];
        [row setCaption:label value:value];
        [self addSubview:row];
        [fieldRowViews addObject:row];
    }
    [(AppInfoDetailRowView *)[fieldRowViews lastObject] setShowsSeparator:NO];
}

- (CGFloat)labelHeight:(UILabel *)label width:(CGFloat)width {
    if ([label.text length] == 0) {
        return 0.0;
    }
    CGSize size = [label.text sizeWithFont:label.font
                         constrainedToSize:CGSizeMake(width, 100000.0)
                             lineBreakMode:label.lineBreakMode];
    return ceil(size.height);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat titleHeight = [self labelHeight:titleLabel width:width];
    CGFloat bodyHeight = [self labelHeight:bodyLabel width:width];
    CGFloat gap = (titleHeight > 0.0 && bodyHeight > 0.0) ? 6.0 : 0.0;
    CGFloat height = titleHeight + gap + bodyHeight;
    if ([fieldRowViews count] > 0) {
        if (height > 0.0) {
            height += 10.0;
        }
        for (AppInfoDetailRowView *row in fieldRowViews) {
            height += [row heightForWidth:width];
        }
    }
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat titleHeight = [self labelHeight:titleLabel width:width];
    titleLabel.frame = CGRectMake(0.0, 0.0, width, titleHeight);
    CGFloat y = titleHeight;
    if (titleHeight > 0.0 && [bodyLabel.text length] > 0) {
        y += 6.0;
    }
    CGFloat bodyHeight = [self labelHeight:bodyLabel width:width];
    bodyLabel.frame = CGRectMake(0.0, y, width, bodyHeight);
    y += bodyHeight;
    if ([fieldRowViews count] > 0 && y > 0.0) {
        y += 10.0;
    }
    for (AppInfoDetailRowView *row in fieldRowViews) {
        CGFloat rowHeight = [row heightForWidth:width];
        row.frame = CGRectMake(0.0, y, width, rowHeight);
        y += rowHeight;
    }
}

@end

@implementation AppInfoContentTransitionView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat locations[] = {0.0, 0.18, 1.0};
    CGFloat components[] = {
        245.0 / 255.0, 245.0 / 255.0, 245.0 / 255.0, 1.0,
        238.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0, 1.0,
        235.0 / 255.0, 235.0 / 255.0, 235.0 / 255.0, 0.0
    };
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, locations, 3);

    CGContextDrawLinearGradient(context, gradient, CGPointMake(0.0, 0.0), CGPointMake(0.0, rect.size.height), 0);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
}

@end

@implementation AppInfoSectionBarBackground

@synthesize cutoutFrame;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
    return self;
}

- (void)setCutoutFrame:(CGRect)frame {
    cutoutFrame = frame;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIColor *barBackgroundColor = [UIColor colorWithRed:245.0 / 255.0 green:245.0 / 255.0 blue:245.0 / 255.0 alpha:1.0];
    UIColor *separatorColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    BOOL hasCutout = !CGRectIsEmpty(cutoutFrame);


    CGFloat barBottom = hasCutout ? CGRectGetMaxY(cutoutFrame) : CGRectGetMaxY(rect);
    CGRect fillRect = CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetWidth(rect), barBottom - CGRectGetMinY(rect));

    CGContextSetFillColorWithColor(context, barBackgroundColor.CGColor);
    if (hasCutout) {
        CGContextBeginPath(context);
        CGContextAddRect(context, fillRect);
        CGContextMoveToPoint(context, CGRectGetMidX(cutoutFrame), CGRectGetMinY(cutoutFrame));
        CGContextAddLineToPoint(context, CGRectGetMaxX(cutoutFrame), CGRectGetMaxY(cutoutFrame));
        CGContextAddLineToPoint(context, CGRectGetMinX(cutoutFrame), CGRectGetMaxY(cutoutFrame));
        CGContextClosePath(context);
        CGContextEOFillPath(context);
    } else {
        CGContextFillRect(context, fillRect);
    }

    CGFloat separatorY = barBottom - 0.5;

    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);
    CGContextSetStrokeColorWithColor(context, separatorColor.CGColor);
    CGContextSetLineWidth(context, 1.0);
    CGContextSetLineJoin(context, kCGLineJoinMiter);
    CGContextMoveToPoint(context, CGRectGetMinX(rect), separatorY);
    if (hasCutout) {
        CGContextAddLineToPoint(context, CGRectGetMinX(cutoutFrame) + 0.5, separatorY);
        CGContextAddLineToPoint(context, CGRectGetMidX(cutoutFrame), CGRectGetMinY(cutoutFrame) + 0.5);
        CGContextAddLineToPoint(context, CGRectGetMaxX(cutoutFrame) - 0.5, separatorY);
    }
    CGContextAddLineToPoint(context, CGRectGetMaxX(rect), separatorY);
    CGContextStrokePath(context);
}

@end

@implementation AppInfo {
    AppDelegate *delegate;
    UIImage *appImage;
    BOOL initialized;
    Application *app;
    UIView *sectionBar;
    AppInfoSectionBarBackground *sectionBarBackgroundView;
    UIButton *detailsTabButton;
    UIButton *versionsTabButton;
    UIButton *relatedTabButton;
    AppInfoContentTransitionView *contentTransitionView;
    UITableView *versionsTableView;
    UITableView *relatedTableView;
    UILabel *relatedStatusLabel;
    UILabel *appVersionsLabel;
    NSMutableArray *detailBadgeViews;
    NSMutableArray *detailRowViews;
    NSMutableArray *customInfoBlockViews;
    UILabel *infoHeaderLabel;
    NSMutableArray *relatedApps;
    NSMutableSet *relatedLoadingIconURLs;
    UIPopoverController *activityPopover;
    BOOL relatedLoaded;
    BOOL relatedLoading;
    NSUInteger relatedIconLoadGeneration;
    AppInfoSection selectedSection;
    NSInteger pendingVersionActionIndex;
    BOOL versionInfoMode;
    Version *selectedVersion;
}
@synthesize getButton;
@synthesize appNameLabel;
@synthesize appUIImage;
@synthesize appDeveloperNameLabel;
@synthesize activityIndicator;
@synthesize descriptionLabel;

- (void)viewDidLoad {
    [super viewDidLoad];
    delegate = getDelegate();
    selectedSection = AppInfoSectionDetails;
    pendingVersionActionIndex = AppInfoNoPendingVersionIndex;
    relatedApps = [[NSMutableArray alloc] init];
    relatedLoadingIconURLs = [[NSMutableSet alloc] init];
    detailBadgeViews = [[NSMutableArray alloc] init];
    detailRowViews = [[NSMutableArray alloc] init];
    customInfoBlockViews = [[NSMutableArray alloc] init];
    self.view.backgroundColor = [UIColor colorWithRed:245.0 / 255.0 green:245.0 / 255.0 blue:245.0 / 255.0 alpha:1.0];
    appUIImage.layer.masksToBounds = YES;
    appUIImage.layer.cornerRadius = 13.0;
    activityIndicator.hidden = YES;
    self.navigationItem.title = NSLocalizedString(versionInfoMode ? @"VersionSingular" : @"Info", nil);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(actionsButtonPressed:)];
    self.descriptionLabel.text = NSLocalizedString(@"Description", nil);
    self.scrollView.backgroundColor = [UIColor colorWithRed:235.0 / 255.0 green:235.0 / 255.0 blue:235.0 / 255.0 alpha:1.0];
    appVersionsLabel = [self findAppVersionsLabel];
    appVersionsLabel.text = nil;
    appVersionsLabel.hidden = YES;
    [self setupSectionTabs];
    [self setupVersionsTableView];
    [self setupRelatedTableView];
    [self layoutSectionViews];
    [self selectSection:AppInfoSectionDetails];
    if (versionInfoMode) {
        [self configureVersionInfoMode];
    }
    if (app == nil) {
        [self populateLoadingContent];
        [self layoutDetailsContent];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    relatedIconLoadGeneration++;
    [relatedLoadingIconURLs removeAllObjects];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSectionViews];
    [self layoutDetailsContent];
}

- (UIButton *)tabButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *button = [AppInfoTabButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:14.0];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumFontSize = 10.0;
    button.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 11.0, 0.0, 11.0);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:77.0 / 255.0 green:77.0 / 255.0 blue:77.0 / 255.0 alpha:1.0] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.62 alpha:1.0] forState:UIControlStateDisabled];
    [button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateDisabled];
    [button addTarget:self action:@selector(sectionTabPressed:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (CGFloat)tabButtonWidthForButton:(UIButton *)button {
    NSString *title = [button titleForState:UIControlStateNormal];
    CGSize titleSize = [title sizeWithFont:button.titleLabel.font];
    CGFloat horizontalPadding = button.contentEdgeInsets.left + button.contentEdgeInsets.right;
    return MAX(44.0, ceil(titleSize.width + horizontalPadding));
}

- (void)setupSectionTabs {
    sectionBar = [[UIView alloc] initWithFrame:CGRectZero];
    sectionBar.backgroundColor = [UIColor clearColor];
    sectionBar.clipsToBounds = NO;
    sectionBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;

    sectionBarBackgroundView = [[AppInfoSectionBarBackground alloc] initWithFrame:CGRectZero];
    sectionBarBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    detailsTabButton = [self tabButtonWithTitle:(versionInfoMode ? NSLocalizedString(@"Info", nil) : NSLocalizedString(@"Details", nil)) tag:AppInfoSectionDetails];
    versionsTabButton = [self tabButtonWithTitle:NSLocalizedString(@"Versions", nil) tag:AppInfoSectionVersions];
    relatedTabButton = [self tabButtonWithTitle:NSLocalizedString(@"Related", nil) tag:AppInfoSectionRelated];

    [sectionBar addSubview:sectionBarBackgroundView];
    [sectionBar addSubview:detailsTabButton];
    [sectionBar addSubview:versionsTabButton];
    [sectionBar addSubview:relatedTabButton];
    [self.view addSubview:sectionBar];
}

- (BOOL)canShowLoadedSection {
    return (initialized && app != nil);
}

- (void)updateSectionTabAvailability {
    BOOL loaded = [self canShowLoadedSection];
    if (versionInfoMode) {
        detailsTabButton.enabled = YES;
        versionsTabButton.enabled = NO;
        relatedTabButton.enabled = NO;
        versionsTabButton.hidden = YES;
        relatedTabButton.hidden = YES;
        return;
    }
    versionsTabButton.hidden = NO;
    relatedTabButton.hidden = NO;
    versionsTabButton.enabled = loaded;
    relatedTabButton.enabled = loaded;
    versionsTabButton.alpha = loaded ? 1.0 : 0.55;
    relatedTabButton.alpha = loaded ? 1.0 : 0.55;
}

- (void)setupVersionsTableView {
    versionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    versionsTableView.dataSource = self;
    versionsTableView.delegate = self;
    versionsTableView.hidden = YES;
    versionsTableView.backgroundColor = [UIColor colorWithRed:235.0 / 255.0 green:235.0 / 255.0 blue:235.0 / 255.0 alpha:1.0];
    versionsTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    versionsTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:versionsTableView];

    contentTransitionView = [[AppInfoContentTransitionView alloc] initWithFrame:CGRectZero];
    contentTransitionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:contentTransitionView];
}

- (void)setupRelatedTableView {
    relatedTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    relatedTableView.dataSource = self;
    relatedTableView.delegate = self;
    relatedTableView.hidden = YES;
    relatedTableView.backgroundColor = [UIColor colorWithRed:235.0 / 255.0 green:235.0 / 255.0 blue:235.0 / 255.0 alpha:1.0];
    relatedTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    relatedTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:relatedTableView];

    relatedStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    relatedStatusLabel.hidden = YES;
    relatedStatusLabel.backgroundColor = [UIColor clearColor];
    relatedStatusLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    relatedStatusLabel.shadowColor = [UIColor whiteColor];
    relatedStatusLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    relatedStatusLabel.font = [UIFont boldSystemFontOfSize:15.0];
    relatedStatusLabel.textAlignment = NSTextAlignmentCenter;
    relatedStatusLabel.numberOfLines = 2;
    relatedStatusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:relatedStatusLabel];
}

- (void)updateTableHeaderForTableView:(UITableView *)tableView height:(CGFloat)height width:(CGFloat)width {
    UIView *headerView = tableView.tableHeaderView;
    CGRect headerFrame = CGRectMake(0.0, 0.0, width, height);

    if (headerView == nil) {
        headerView = [[UIView alloc] initWithFrame:headerFrame];
        headerView.backgroundColor = tableView.backgroundColor;
        tableView.tableHeaderView = headerView;
        return;
    }

    if (!CGRectEqualToRect(headerView.frame, headerFrame)) {
        headerView.frame = headerFrame;
        tableView.tableHeaderView = headerView;
    }
}

- (void)layoutSectionViews {
    CGFloat width = self.view.bounds.size.width;
    CGFloat tabTop = 111.0;
    CGFloat tabHeight = 43.0;
    CGFloat indicatorHeight = 8.0;
    CGFloat contentFrameTop = tabTop + tabHeight - indicatorHeight;
    CGFloat contentTopInset = indicatorHeight + 1.0;
    CGFloat contentHeight = MAX(0.0, self.view.bounds.size.height - contentFrameTop);

    sectionBar.frame = CGRectMake(0.0, tabTop, width, tabHeight);
    sectionBarBackgroundView.frame = CGRectMake(0.0, 0.0, width, tabHeight + indicatorHeight);

    CGFloat tabY = 7.0;
    CGFloat tabHeightValue = 24.0;
    CGFloat tabGap = 6.0;
    CGFloat sideMargin = 7.0;
    CGFloat availableWidth = width - (sideMargin * 2.0);
    CGFloat detailsWidth = [self tabButtonWidthForButton:detailsTabButton];
    CGFloat versionsWidth = [self tabButtonWidthForButton:versionsTabButton];
    CGFloat relatedWidth = [self tabButtonWidthForButton:relatedTabButton];
    if (versionInfoMode) {
        CGFloat singleWidth = MIN(MAX(detailsWidth, 72.0), availableWidth);
        detailsTabButton.frame = CGRectMake(floor((width - singleWidth) / 2.0), tabY, singleWidth, tabHeightValue);
        versionsTabButton.frame = CGRectZero;
        relatedTabButton.frame = CGRectZero;
        sectionBarBackgroundView.cutoutFrame = CGRectMake(CGRectGetMidX(detailsTabButton.frame) - 8.0, tabHeight - indicatorHeight, 16.0, indicatorHeight + 1.0);

        self.scrollView.frame = CGRectMake(0.0, contentFrameTop, width, contentHeight);
        versionsTableView.frame = self.scrollView.frame;
        relatedTableView.frame = self.scrollView.frame;
        [self updateTableHeaderForTableView:versionsTableView height:contentTopInset width:width];
        [self updateTableHeaderForTableView:relatedTableView height:contentTopInset width:width];
        relatedStatusLabel.frame = CGRectMake(20.0, contentFrameTop + contentTopInset + 60.0, width - 40.0, 60.0);
        contentTransitionView.frame = CGRectMake(0.0, contentFrameTop, width, contentTopInset + 10.0);
        [self.view bringSubviewToFront:sectionBar];
        return;
    }
    CGFloat totalTabWidth = detailsWidth + versionsWidth + relatedWidth + (tabGap * 2.0);

    if (totalTabWidth > availableWidth) {
        CGFloat naturalWidth = detailsWidth + versionsWidth + relatedWidth;
        CGFloat scaledAvailableWidth = availableWidth - (tabGap * 2.0);
        CGFloat scale = scaledAvailableWidth / naturalWidth;
        detailsWidth = floor(detailsWidth * scale);
        versionsWidth = floor(versionsWidth * scale);
        relatedWidth = MAX(44.0, scaledAvailableWidth - detailsWidth - versionsWidth);
        totalTabWidth = detailsWidth + versionsWidth + relatedWidth + (tabGap * 2.0);
    }

    CGFloat tabX = floor((width - totalTabWidth) / 2.0);
    detailsTabButton.frame = CGRectMake(tabX, tabY, detailsWidth, tabHeightValue);
    tabX += detailsWidth + tabGap;
    versionsTabButton.frame = CGRectMake(tabX, tabY, versionsWidth, tabHeightValue);
    tabX += versionsWidth + tabGap;
    relatedTabButton.frame = CGRectMake(tabX, tabY, relatedWidth, tabHeightValue);

    UIButton *selectedButton = [self buttonForSection:selectedSection];
    sectionBarBackgroundView.cutoutFrame = CGRectMake(CGRectGetMidX(selectedButton.frame) - 8.0, tabHeight - indicatorHeight, 16.0, indicatorHeight + 1.0);

    self.scrollView.frame = CGRectMake(0.0, contentFrameTop, width, contentHeight);
    versionsTableView.frame = self.scrollView.frame;
    relatedTableView.frame = self.scrollView.frame;
    [self updateTableHeaderForTableView:versionsTableView height:contentTopInset width:width];
    [self updateTableHeaderForTableView:relatedTableView height:contentTopInset width:width];
    relatedStatusLabel.frame = CGRectMake(20.0, contentFrameTop + contentTopInset + 60.0, width - 40.0, 60.0);
    contentTransitionView.frame = CGRectMake(0.0, contentFrameTop, width, contentTopInset + 10.0);
    [self.view bringSubviewToFront:sectionBar];
}

- (UIButton *)buttonForSection:(AppInfoSection)section {
    switch (section) {
        case AppInfoSectionVersions:
            return versionsTabButton;
        case AppInfoSectionRelated:
            return relatedTabButton;
        case AppInfoSectionDetails:
        default:
            return detailsTabButton;
    }
}

- (void)styleTabButton:(UIButton *)button selected:(BOOL)selected {
    button.selected = selected;
    if (selected) {
        button.backgroundColor = [UIColor clearColor];
        button.layer.cornerRadius = 0.0;
        button.layer.borderWidth = 0.0;
        [button setTitleColor:[UIColor colorWithRed:77.0 / 255.0 green:77.0 / 255.0 blue:77.0 / 255.0 alpha:1.0] forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor clearColor];
        button.layer.cornerRadius = 0.0;
        button.layer.borderWidth = 0.0;
        [button setTitleColor:[UIColor colorWithRed:77.0 / 255.0 green:77.0 / 255.0 blue:77.0 / 255.0 alpha:1.0] forState:UIControlStateNormal];
    }
}

- (void)sectionTabPressed:(UIButton *)sender {
    [self selectSection:(AppInfoSection)sender.tag];
}

- (void)selectSection:(AppInfoSection)section {
    if (versionInfoMode) {
        section = AppInfoSectionDetails;
    }
    if (section != AppInfoSectionDetails && ![self canShowLoadedSection]) {
        section = AppInfoSectionDetails;
    }
    selectedSection = section;
    [self updateSectionTabAvailability];
    [self styleTabButton:detailsTabButton selected:(section == AppInfoSectionDetails)];
    [self styleTabButton:versionsTabButton selected:(section == AppInfoSectionVersions)];
    [self styleTabButton:relatedTabButton selected:(section == AppInfoSectionRelated)];
    self.scrollView.hidden = (section != AppInfoSectionDetails);
    versionsTableView.hidden = (section != AppInfoSectionVersions);
    relatedTableView.hidden = (section != AppInfoSectionRelated);
    relatedStatusLabel.hidden = (section != AppInfoSectionRelated || [relatedApps count] > 0 || (!relatedLoading && relatedLoaded));
    if (section == AppInfoSectionRelated) {
        [self loadRelatedAppsIfNeeded];
    }
    [self layoutSectionViews];
}

- (void)configureVersionInfoMode {
    versionInfoMode = YES;
    initialized = (app != nil && selectedVersion != nil);
    selectedSection = AppInfoSectionDetails;
    self.navigationItem.title = NSLocalizedString(@"Info", nil);
    self.navigationItem.rightBarButtonItem = nil;
    if (app != nil && selectedVersion != nil) {
        self.appDeveloperNameLabel.text = app.developer;
        self.appNameLabel.text = app.name;
        if (self.appUIImage.image == nil) {
            self.appUIImage.image = app.icon;
        }
        appVersionsLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), selectedVersion.version];
        appVersionsLabel.hidden = NO;
        [activityIndicator stopAnimating];
        activityIndicator.hidden = YES;
    }
    [detailsTabButton setTitle:NSLocalizedString(@"Info", nil) forState:UIControlStateNormal];
    versionsTabButton.hidden = YES;
    relatedTabButton.hidden = YES;
    versionsTableView.hidden = YES;
    relatedTableView.hidden = YES;
    relatedStatusLabel.hidden = YES;
    [self updateSectionTabAvailability];
    [self selectSection:AppInfoSectionDetails];
    [self populateVersionInfoContent];
    [self layoutDetailsContent];
}

- (void)didReceiveInstallationStartedNotification:(NSNotification *)notification {
    debugLog(@"Installation started notification received");
}

- (NSString *)localizedCategoryDisplayName:(NSString *)categoryName {
    if ([categoryName length] == 0) {
        return nil;
    }
    NSString *tmpString = [categoryName stringByReplacingOccurrencesOfString:@"Healthcare & Fitness" withString:@"Health"];
    NSString *key = [NSString stringWithFormat:@"Category-%@", [tmpString stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    NSString *translatedString = NSLocalizedString(key, nil);
    if (translatedString != nil && ![translatedString isEqualToString:key]) {
        return translatedString;
    }
    return categoryName;
}

- (NSString *)deviceFamilyDisplayName:(NSString *)family {
    if ([family isEqualToString:@"iphone"]) {
        return @"iPhone";
    }
    if ([family isEqualToString:@"ipad"]) {
        return @"iPad";
    }
    if ([family isEqualToString:@"universal"]) {
        return NSLocalizedString(@"DeviceFamilyUniversal", nil);
    }
    return nil;
}

- (NSString *)minimumOSForApplication:(Application *)application {
    if ([application.requiredOS length] > 0) {
        return application.requiredOS;
    }
    NSString *best = nil;
    for (Version *version in application.versions) {
        NSString *candidate = version.minVersion;
        if ([candidate length] == 0) {
            continue;
        }
        if (best == nil || [candidate compare:best options:NSNumericSearch] == NSOrderedAscending) {
            best = candidate;
        }
    }
    return best;
}

- (NSString *)displayReleaseDate:(NSString *)isoDate {
    if ([isoDate length] < 10) {
        return isoDate;
    }
    NSDateFormatter *parser = [[NSDateFormatter alloc] init];
    parser.dateFormat = @"yyyy-MM-dd";
    parser.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    parser.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSDate *date = [parser dateFromString:[isoDate substringToIndex:10]];
    if (date == nil) {
        return isoDate;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    return [formatter stringFromDate:date];
}

- (void)addDetailBadgeWithCaption:(NSString *)caption value:(NSString *)value {
    if ([value length] == 0) {
        return;
    }
    AppInfoBadgeView *badge = [[AppInfoBadgeView alloc] initWithFrame:CGRectZero];
    [badge setCaption:caption value:value];
    [self.scrollView addSubview:badge];
    [detailBadgeViews addObject:badge];
}

- (void)addDetailRowWithCaption:(NSString *)caption value:(NSString *)value {
    if ([value length] == 0) {
        return;
    }
    AppInfoDetailRowView *row = [[AppInfoDetailRowView alloc] initWithFrame:CGRectZero];
    [row setCaption:caption value:value];
    [self.scrollView addSubview:row];
    [detailRowViews addObject:row];
}

- (void)addCopyableDetailRowWithCaption:(NSString *)caption value:(NSString *)value {
    if ([value length] == 0) {
        return;
    }
    AppInfoDetailRowView *row = [[AppInfoDetailRowView alloc] initWithFrame:CGRectZero];
    [row setCaption:caption value:value];
    row.copyableValue = value;
    [self.scrollView addSubview:row];
    [detailRowViews addObject:row];
}

- (void)addWebsiteDetailRowWithCaption:(NSString *)caption value:(NSString *)value {
    if ([value length] == 0) {
        return;
    }
    AppInfoDetailRowView *row = [[AppInfoDetailRowView alloc] initWithFrame:CGRectZero];
    [row setCaption:caption value:value];
    row.copyableValue = value;
    row.openURLString = value;
    [self.scrollView addSubview:row];
    [detailRowViews addObject:row];
}

- (UITableViewCell *)newVersionCellWithReuseIdentifier:(NSString *)reuseIdentifier {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    cell.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:16.0];
    cell.textLabel.textColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    cell.textLabel.shadowColor = [UIColor whiteColor];
    cell.textLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    cell.detailTextLabel.numberOfLines = 2;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

- (void)configureVersionCell:(UITableViewCell *)cell version:(Version *)version {
    cell.accessoryView = nil;
    cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), version.version];
    NSString *requiresText = [NSString stringWithFormat:NSLocalizedString(@"RequiresIOSFormat", nil), version.minVersion];
    NSString *sizeText = AppInfoStringForByteCount(version.sizeBytes);
    NSMutableArray *subtitleParts = [NSMutableArray arrayWithObject:requiresText];
    if ([sizeText length] > 0) {
        [subtitleParts addObject:sizeText];
    }
    NSString *versionBundleID = AppInfoDistinctBundleIDForVersion(app, version);
    if ([versionBundleID length] > 0) {
        [subtitleParts addObject:versionBundleID];
    }
    cell.detailTextLabel.text = [subtitleParts componentsJoinedByString:@" - "];
    [cell layoutIfNeeded];
    AppInfoConfigureRecommendedBadge(cell, AppInfoVersionIsRecommended(app, version));
}

- (void)clearDetailGeneratedViews {
    for (UIView *view in detailBadgeViews) {
        [view removeFromSuperview];
    }
    [detailBadgeViews removeAllObjects];
    for (UIView *view in detailRowViews) {
        [view removeFromSuperview];
    }
    [detailRowViews removeAllObjects];
    for (UIView *view in customInfoBlockViews) {
        [view removeFromSuperview];
    }
    [customInfoBlockViews removeAllObjects];
    [infoHeaderLabel removeFromSuperview];
    infoHeaderLabel = nil;
}

- (void)addCustomInfoBlocks:(NSArray *)blocks {
    for (ApplicationInfoBlock *block in blocks) {
        NSString *title = AppInfoTrimmedString(block.title);
        NSString *body = AppInfoTrimmedString(block.body);
        if ([title length] == 0 && [body length] == 0 && [block.fields count] == 0) {
            continue;
        }
        AppInfoCustomInfoBlockView *blockView = [[AppInfoCustomInfoBlockView alloc] initWithFrame:CGRectZero];
        [blockView applyTitleFont:self.descriptionLabel.font textColor:self.descriptionLabel.textColor];
        [blockView setTitle:title body:body fields:block.fields];
        [self.scrollView addSubview:blockView];
        [customInfoBlockViews addObject:blockView];
    }
}

- (void)populateLoadingContent {
    [self clearDetailGeneratedViews];

    self.appDescriptionLabel.text = NSLocalizedString(@"Loading", nil);
    self.appDescriptionLabel.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:13.0];
    self.appDescriptionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];

    NSString *loadingValue = NSLocalizedString(@"Loading", nil);
    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeCategory", nil) value:loadingValue];
    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeDevices", nil) value:loadingValue];
    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeRequires", nil) value:loadingValue];

    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsBundleID", nil) value:loadingValue];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsArchitectures", nil) value:loadingValue];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsBackgroundModes", nil) value:loadingValue];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsExecutable", nil) value:loadingValue];
    [(AppInfoDetailRowView *)[detailRowViews lastObject] setShowsSeparator:NO];

    infoHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    infoHeaderLabel.backgroundColor = [UIColor clearColor];
    infoHeaderLabel.font = self.descriptionLabel.font;
    infoHeaderLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    infoHeaderLabel.text = NSLocalizedString(@"Information", nil);
    [self.scrollView addSubview:infoHeaderLabel];
}

- (void)populateDetailsContent {
    [self clearDetailGeneratedViews];

    if (app == nil) {
        return;
    }

    BOOL placeholderDescription = ([app.app_description length] == 0
        || [app.app_description isEqualToString:@"No description available yet."]);
    if (placeholderDescription) {
        self.appDescriptionLabel.text = NSLocalizedString(@"NoDescriptionAvailable", nil);
        self.appDescriptionLabel.font = [UIFont fontWithName:@"HelveticaNeue-Italic" size:13.0];
        self.appDescriptionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    } else {
        self.appDescriptionLabel.text = app.app_description;
        self.appDescriptionLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        self.appDescriptionLabel.textColor = [UIColor darkTextColor];
    }
    [self addCustomInfoBlocks:app.customInfoBlocks];

    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeCategory", nil)
                              value:[self localizedCategoryDisplayName:app.category]];
    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeDevices", nil)
                              value:[self deviceFamilyDisplayName:app.deviceFamily]];
    NSString *minimumOS = [self minimumOSForApplication:app];
    if ([minimumOS length] > 0) {
        [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeRequires", nil)
                                  value:[NSString stringWithFormat:NSLocalizedString(@"MinIOSBadgeFormat", nil), minimumOS]];
    }

    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsReleased", nil) value:[self displayReleaseDate:app.releaseDate]];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsRating", nil) value:app.contentRating];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsPrice", nil) value:app.price];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsSubgenres", nil) value:app.subgenres];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsCopyright", nil) value:app.copyrightText];
    if ([app.gameCenter length] > 0) {
        [self addDetailRowWithCaption:NSLocalizedString(@"DetailsGameCenter", nil) value:NSLocalizedString(@"DetailsYes", nil)];
    }
    if ([app.newsstand length] > 0) {
        [self addDetailRowWithCaption:NSLocalizedString(@"DetailsNewsstand", nil) value:NSLocalizedString(@"DetailsYes", nil)];
    }
    [self addCopyableDetailRowWithCaption:NSLocalizedString(@"DetailsBundleID", nil) value:AppInfoDisplayBundleIDForApplication(app)];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsExecutable", nil) value:app.executable];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsArchitectures", nil) value:app.archFlags];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsRequiredCapabilities", nil) value:app.requiredCapabilities];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsBackgroundModes", nil) value:app.backgroundModes];
    [self addWebsiteDetailRowWithCaption:NSLocalizedString(@"DetailsWebsite", nil) value:AppInfoTrimmedString(app.websiteURL)];
    [(AppInfoDetailRowView *)[detailRowViews lastObject] setShowsSeparator:NO];

    if ([detailRowViews count] > 0) {
        if (infoHeaderLabel == nil) {
            infoHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        }
        infoHeaderLabel.backgroundColor = [UIColor clearColor];
        infoHeaderLabel.font = self.descriptionLabel.font;
        infoHeaderLabel.textColor = self.descriptionLabel.textColor;
        infoHeaderLabel.text = NSLocalizedString(@"Information", nil);
        [self.scrollView addSubview:infoHeaderLabel];
    }
}

- (NSString *)displayMetadataSource:(NSString *)metadataSource {
    if ([metadataSource isEqualToString:@"info_plist"]) {
        return @"Info.plist";
    }
    if ([metadataSource isEqualToString:@"itunes_metadata"]) {
        return @"iTunesMetadata.plist";
    }
    if ([metadataSource isEqualToString:@"filename_fallback"]) {
        return NSLocalizedString(@"VersionInfoMetadataFilename", nil);
    }
    return metadataSource;
}

- (BOOL)versionHasITunesMetadata:(Version *)version {
    return ([version.releaseDate length] > 0
        || [version.contentRating length] > 0
        || [version.price length] > 0
        || [version.subgenres length] > 0
        || [version.copyrightText length] > 0
        || [version.gameCenter length] > 0
        || [version.newsstand length] > 0);
}

- (void)populateVersionInfoContent {
    [self clearDetailGeneratedViews];

    if (app == nil || selectedVersion == nil) {
        return;
    }

    self.descriptionLabel.text = NSLocalizedString(@"VersionSingular", nil);
    self.appDescriptionLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), selectedVersion.version];
    self.appDescriptionLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    self.appDescriptionLabel.textColor = [UIColor darkTextColor];

    [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsReleased", nil)
                              value:[self displayReleaseDate:selectedVersion.releaseDate]];
    if ([selectedVersion.minVersion length] > 0) {
        [self addDetailBadgeWithCaption:NSLocalizedString(@"DetailsBadgeRequires", nil)
                                  value:[NSString stringWithFormat:NSLocalizedString(@"MinIOSBadgeFormat", nil), selectedVersion.minVersion]];
    }
    [self addDetailBadgeWithCaption:NSLocalizedString(@"VersionInfoSize", nil)
                              value:AppInfoStringForByteCount(selectedVersion.sizeBytes)];

    [self addDetailRowWithCaption:NSLocalizedString(@"VersionSingular", nil) value:selectedVersion.version];
    if ([selectedVersion.buildVersion length] > 0 && ![selectedVersion.buildVersion isEqualToString:selectedVersion.version]) {
        [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoBuild", nil) value:selectedVersion.buildVersion];
    }
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoITunesMetadata", nil)
                            value:([self versionHasITunesMetadata:selectedVersion] ? NSLocalizedString(@"DetailsYes", nil) : NSLocalizedString(@"VersionInfoNotAvailable", nil))];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsReleased", nil) value:[self displayReleaseDate:selectedVersion.releaseDate]];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsRating", nil) value:selectedVersion.contentRating];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsPrice", nil) value:selectedVersion.price];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsSubgenres", nil) value:selectedVersion.subgenres];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsCopyright", nil) value:selectedVersion.copyrightText];
    if ([selectedVersion.gameCenter length] > 0) {
        [self addDetailRowWithCaption:NSLocalizedString(@"DetailsGameCenter", nil) value:NSLocalizedString(@"DetailsYes", nil)];
    }
    if ([selectedVersion.newsstand length] > 0) {
        [self addDetailRowWithCaption:NSLocalizedString(@"DetailsNewsstand", nil) value:NSLocalizedString(@"DetailsYes", nil)];
    }
    [self addCopyableDetailRowWithCaption:NSLocalizedString(@"DetailsBundleID", nil) value:AppInfoDisplayBundleIDForVersion(app, selectedVersion)];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsBadgeDevices", nil)
                            value:[self deviceFamilyDisplayName:selectedVersion.platform]];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsArchitectures", nil) value:selectedVersion.archFlags];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoFairPlay", nil) value:selectedVersion.fairplayStatus];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsExecutable", nil) value:selectedVersion.executable];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsRequiredCapabilities", nil) value:selectedVersion.requiredCapabilities];
    [self addDetailRowWithCaption:NSLocalizedString(@"DetailsBackgroundModes", nil) value:selectedVersion.backgroundModes];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoArchiveItem", nil) value:selectedVersion.sourceItem];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoArchiveFile", nil) value:selectedVersion.sourceFile];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoIconPath", nil) value:selectedVersion.iconPath];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoIconBundleID", nil) value:selectedVersion.iconBundleID];
    [self addCopyableDetailRowWithCaption:@"SHA1" value:selectedVersion.sha1];
    [self addDetailRowWithCaption:@"MD5" value:selectedVersion.md5];
    [self addDetailRowWithCaption:NSLocalizedString(@"VersionInfoMetadataSource", nil)
                            value:[self displayMetadataSource:selectedVersion.metadataSource]];
    [self addCopyableDetailRowWithCaption:NSLocalizedString(@"VersionInfoDownloadURL", nil) value:selectedVersion.fileName];
    [(AppInfoDetailRowView *)[detailRowViews lastObject] setShowsSeparator:NO];

    if ([detailRowViews count] > 0) {
        if (infoHeaderLabel == nil) {
            infoHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        }
        infoHeaderLabel.backgroundColor = [UIColor clearColor];
        infoHeaderLabel.font = self.descriptionLabel.font;
        infoHeaderLabel.textColor = self.descriptionLabel.textColor;
        infoHeaderLabel.text = NSLocalizedString(@"Information", nil);
        [self.scrollView addSubview:infoHeaderLabel];
    }
}

- (void)layoutDetailsContent {
    if (self.scrollView == nil) {
        return;
    }
    CGFloat width = self.scrollView.bounds.size.width;
    if (width <= 0.0) {
        width = self.view.bounds.size.width;
    }
    CGFloat margin = 20.0;
    CGFloat contentWidth = width - margin * 2.0;
    CGFloat sectionGap = 24.0;
    CGFloat y = 14.0;

    NSUInteger badgeCount = [detailBadgeViews count];
    if (badgeCount > 0) {
        CGFloat badgeGap = 8.0;
        CGFloat badgeHeight = 55.0;
        CGFloat badgeWidth = floor((contentWidth - badgeGap * (badgeCount - 1)) / badgeCount);
        CGFloat x = margin;
        for (AppInfoBadgeView *badge in detailBadgeViews) {
            badge.frame = CGRectMake(x, y, badgeWidth, badgeHeight);
            x += badgeWidth + badgeGap;
        }
        AppInfoBadgeView *lastBadge = [detailBadgeViews lastObject];
        CGRect lastFrame = lastBadge.frame;
        lastFrame.size.width = margin + contentWidth - lastFrame.origin.x;
        lastBadge.frame = lastFrame;
        y += badgeHeight + sectionGap;
    }

    self.descriptionLabel.frame = CGRectMake(margin, y, contentWidth, 30.0);
    y += 34.0;
    CGFloat descriptionHeight = 0.0;
    if ([self.appDescriptionLabel.text length] > 0) {
        CGSize descriptionSize = [self.appDescriptionLabel.text sizeWithFont:self.appDescriptionLabel.font
                                                           constrainedToSize:CGSizeMake(contentWidth, 100000.0)
                                                               lineBreakMode:self.appDescriptionLabel.lineBreakMode];
        descriptionHeight = ceil(descriptionSize.height);
    }
    self.appDescriptionLabel.frame = CGRectMake(margin, y, contentWidth, descriptionHeight);
    y += descriptionHeight;

    for (AppInfoCustomInfoBlockView *blockView in customInfoBlockViews) {
        y += sectionGap;
        CGFloat blockHeight = [blockView heightForWidth:contentWidth];
        blockView.frame = CGRectMake(margin, y, contentWidth, blockHeight);
        y += blockHeight;
    }

    if ([detailRowViews count] > 0) {
        y += sectionGap;
        infoHeaderLabel.frame = CGRectMake(margin, y, contentWidth, 30.0);
        y += 34.0;
        for (AppInfoDetailRowView *row in detailRowViews) {
            CGFloat rowHeight = [row heightForWidth:contentWidth];
            row.frame = CGRectMake(margin, y, contentWidth, rowHeight);
            y += rowHeight;
        }
    }

    self.scrollView.contentSize = CGSizeMake(width, y + 20.0);
}

- (void)initialize:(NSString *)bundleID developer:(NSString *)developer name:(NSString *)name image:(UIImage *)image {
    debugLog(@"Initializing with bundleID: %@ developer: %@ name: %@", bundleID, developer, name);
    debugLog(@"Versions: %@", app.versions);
    initialized = NO;
    app = nil;
    if ([self isViewLoaded]) {
        [self selectSection:AppInfoSectionDetails];
    }
    relatedLoaded = NO;
    relatedLoading = NO;
    relatedIconLoadGeneration++;
    [relatedApps removeAllObjects];
    [relatedLoadingIconURLs removeAllObjects];
    [relatedTableView reloadData];
    relatedStatusLabel.text = NSLocalizedString(@"Loading", nil);
    [self populateLoadingContent];
    [self layoutDetailsContent];
    dispatch_async(dispatch_get_main_queue(), ^{
        activityIndicator.hidden = NO;
        [activityIndicator startAnimating];
        if (developer != nil || name != nil || image != NULL) {
            self.appDeveloperNameLabel.text = developer;
            self.appNameLabel.text = name;
            self.appUIImage.image = image;
        }
    });
    [VAPISS getMessage:[NSString stringWithFormat:@"listing/app/%@", bundleID] completion:^(NSData *data, NSError *error) {
        if (error) {
            [SVProgressHUD dismiss];
            alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"ServerContactError", nil), VAPIHelperErrorNetwork);
            return;
        }
        app = (Application *)(CFBridgingRelease(decode([data bytes], [data length], AppResponse)));
        [self populateDetailsContent];
        [self layoutDetailsContent];
        [self loadImageIfNeeded];
        self.appDeveloperNameLabel.text = app.developer;
        self.appNameLabel.text = app.name;
        NSString *versionCountText = [self versionCountTextForApplication:app];
        appVersionsLabel.text = versionCountText;
        appVersionsLabel.hidden = ([versionCountText length] == 0);
        [versionsTableView reloadData];
        if (selectedSection == AppInfoSectionRelated) {
            [self loadRelatedAppsIfNeeded];
        }
        initialized = YES;
        [self updateSectionTabAvailability];
    }];
}

- (void)initialize:(NSString *)bundleID {
    [self initialize:bundleID developer:nil name:nil image:NULL];
}

- (void)initializeVersionInfoWithApplication:(Application *)application version:(Version *)version image:(UIImage *)image {
    versionInfoMode = YES;
    app = application;
    selectedVersion = version;
    initialized = (app != nil && selectedVersion != nil);
    relatedLoaded = YES;
    relatedLoading = NO;
    relatedIconLoadGeneration++;
    [relatedApps removeAllObjects];
    [relatedLoadingIconURLs removeAllObjects];

    if (![self isViewLoaded]) {
        return;
    }

    self.appDeveloperNameLabel.text = app.developer;
    self.appNameLabel.text = app.name;
    self.appUIImage.image = image ?: app.icon;
    appVersionsLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), selectedVersion.version];
    appVersionsLabel.hidden = NO;
    [activityIndicator stopAnimating];
    activityIndicator.hidden = YES;
    [self configureVersionInfoMode];
    [self loadImageIfNeeded];
}

- (void)loadImageIfNeeded {
    if (self.appUIImage.image == NULL) {
        [VAPISS getStatic:app.iconurl fallbackPath:app.fallback_iconurl completion:^(NSData *data, NSError *error){
            if (error != nil) {
                debugLog(@"Failed to fetch image for %@", app.bundleid);
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            dispatch_async(dispatch_get_main_queue(), ^{
                appUIImage.image = image;
                if ([VAPIHelper shouldRetainDecodedIcons]) {
                    app.icon = image;
                }
                [activityIndicator stopAnimating];
                activityIndicator.hidden = YES;
            });
        }];
    }
}

- (void)loadRelatedAppsIfNeeded {
    if (relatedLoaded || relatedLoading || app == nil || [app.bundleid length] == 0) {
        return;
    }

    relatedLoading = YES;
    relatedStatusLabel.text = NSLocalizedString(@"Loading", nil);
    relatedStatusLabel.hidden = (selectedSection != AppInfoSectionRelated);

    NSString *endpoint = [NSString stringWithFormat:@"listing/related/%@", [app.bundleid stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [VAPISS getMessage:endpoint completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            relatedLoading = NO;
            relatedLoaded = YES;
            if (error == nil) {
                NSMutableArray *decodedApps = (NSMutableArray *)(CFBridgingRelease(decode([data bytes], [data length], VTableResponse)));
                relatedApps = decodedApps ?: [NSMutableArray array];
                relatedStatusLabel.text = ([relatedApps count] == 0) ? NSLocalizedString(@"NoRelatedAvailable", nil) : @"";
            } else {
                relatedStatusLabel.text = NSLocalizedString(@"FailedToLoadContent", nil);
            }
            relatedStatusLabel.hidden = (selectedSection != AppInfoSectionRelated || [relatedApps count] > 0);
            [relatedTableView reloadData];
        });
    }];
}

- (NSString *)subtitleForRelatedApp:(Application *)relatedApp {
    return VeterisAppCellSubtitle(relatedApp.developer, relatedApp.bundleid, VeterisAppCellSubtitleAreaRelated);
}

- (UILabel *)findAppVersionsLabel {
    UIView *headerView = self.appDeveloperNameLabel.superview;
    UILabel *bestLabel = nil;
    CGFloat developerBottom = CGRectGetMaxY(self.appDeveloperNameLabel.frame);
    CGFloat bestDistance = CGFLOAT_MAX;

    for (UIView *subview in headerView.subviews) {
        if (![subview isKindOfClass:[UILabel class]] || subview == self.appNameLabel || subview == self.appDeveloperNameLabel) {
            continue;
        }

        CGFloat distance = subview.frame.origin.y - developerBottom;
        if (distance >= 0.0 && distance < bestDistance) {
            bestLabel = (UILabel *)subview;
            bestDistance = distance;
        }
    }

    if (bestLabel != nil) {
        CGRect frame = bestLabel.frame;
        frame.size.width = MAX(frame.size.width, self.appDeveloperNameLabel.frame.size.width);
        bestLabel.frame = frame;
    }

    return bestLabel;
}

- (NSString *)versionCountTextForApplication:(Application *)application {
    NSUInteger versionCount = application.versionCount;
    if (versionCount == 0 && [application.versions count] > 0) {
        versionCount = [application.versions count];
    }
    if (versionCount == 0) {
        return nil;
    }
    NSString *versionWord = (versionCount == 1) ? NSLocalizedString(@"VersionSingular", nil) : NSLocalizedString(@"Versions", nil);
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)versionCount, versionWord];
}

- (void)configureRelatedIconForCell:(SearchTableViewCell *)cell app:(Application *)relatedApp {
    UIImage *cachedIcon = relatedApp.icon;
    if (cachedIcon == nil) {
        cachedIcon = [VAPISS imageFromCache:relatedApp.iconurl];
        if (cachedIcon != nil) {
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                relatedApp.icon = cachedIcon;
            }
        }
    }
    cell.appUIImage.image = cachedIcon;
    if (cachedIcon != nil || relatedApp.nilIcon) {
        [cell.activityIndicator stopAnimating];
    } else {
        [cell.activityIndicator startAnimating];
    }
}

- (void)loadRelatedIconForApp:(Application *)relatedApp atIndexPath:(NSIndexPath *)indexPath {
    if (relatedApp == nil || relatedApp.icon != nil || relatedApp.nilIcon) {
        return;
    }
    NSString *iconKey = ([relatedApp.iconurl length] > 0) ? relatedApp.iconurl : relatedApp.fallback_iconurl;
    if ([iconKey length] == 0 || [relatedLoadingIconURLs containsObject:iconKey]) {
        return;
    }

    UIImage *cachedIcon = [VAPISS imageFromCache:relatedApp.iconurl];
    if (cachedIcon != nil) {
        if ([VAPIHelper shouldRetainDecodedIcons]) {
            relatedApp.icon = cachedIcon;
        }
        SearchTableViewCell *cell = (SearchTableViewCell *)[relatedTableView cellForRowAtIndexPath:indexPath];
        cell.appUIImage.image = cachedIcon;
        [cell.activityIndicator stopAnimating];
        return;
    }

    [relatedLoadingIconURLs addObject:iconKey];
    NSUInteger generation = relatedIconLoadGeneration;
    [VAPISS getStatic:relatedApp.iconurl fallbackPath:relatedApp.fallback_iconurl completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [relatedLoadingIconURLs removeObject:iconKey];
            if (generation != relatedIconLoadGeneration) {
                return;
            }
            if (error != nil) {
                debugLog(@"Failed to load related icon for %@, bundleid: %@, app image url: %@", relatedApp.name, relatedApp.bundleid, relatedApp.iconurl);
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) {
                debugLog(@"Failed to decode related icon for %@, bundleid: %@, app image url: %@", relatedApp.name, relatedApp.bundleid, relatedApp.iconurl);
                relatedApp.nilIcon = YES;
                return;
            }
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                relatedApp.icon = image;
            }
            if (indexPath.row >= [relatedApps count] || [relatedApps objectAtIndex:indexPath.row] != relatedApp) {
                return;
            }
            SearchTableViewCell *cell = (SearchTableViewCell *)[relatedTableView cellForRowAtIndexPath:indexPath];
            if (cell == nil) {
                return;
            }
            cell.appUIImage.image = image;
            [cell.activityIndicator stopAnimating];
        });
    }];
}

- (void)showVersionActionSheetAtIndex:(NSInteger)versionIndex includeInfo:(BOOL)includeInfo {
    if (versionIndex < 0 || versionIndex >= [app.versions count]) {
        return;
    }
    pendingVersionActionIndex = versionIndex;
    Version *version = [app.versions objectAtIndex:versionIndex];
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), AppInfoVersionDisplayTitle(app, version)];
    UIActionSheet *actionSheet;
    if (includeInfo) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                  delegate:self
                                         cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                    destructiveButtonTitle:nil
                                         otherButtonTitles:NSLocalizedString(@"Install", nil), NSLocalizedString(@"Download", nil), NSLocalizedString(@"Info", nil), nil];
    } else {
        actionSheet = [[UIActionSheet alloc] initWithTitle:title
                                                  delegate:self
                                         cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                    destructiveButtonTitle:nil
                                         otherButtonTitles:NSLocalizedString(@"Install", nil), NSLocalizedString(@"Download", nil), nil];
    }
    actionSheet.tag = AppInfoVersionCellActionSheetTag;
    [actionSheet showInView:AppInfoActionSheetPresentationView(self.view)];
}

- (IBAction)getButtonPressed:(id)sender {
    if (!initialized) {
        alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"WaitForAppFinishLoading", nil), VAPIHelperErrorUnknown);
        return;
    }
    if (versionInfoMode) {
        NSUInteger versionIndex = [app.versions indexOfObjectIdenticalTo:selectedVersion];
        if (versionIndex == NSNotFound) {
            versionIndex = [app.versions indexOfObject:selectedVersion];
        }
        if (versionIndex == NSNotFound) {
            NSString *message = [NSString stringWithFormat:NSLocalizedString(@"NoVersionsAvailable", @"%@ has NOT been installed, no versions available."), app.name];
            alert(@"Error", message, VAPIHelperErrorUnknown);
            return;
        }
        [self showVersionActionSheetAtIndex:versionIndex includeInfo:NO];
        return;
    }
    // Set initialized here because if the button is pressed the view must be fully loaded
    initialized = YES;
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"SelectAVersion", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil, nil];
    actionSheet.tag = AppInfoVersionPickerActionSheetTag;
    for (Version *ver in app.versions) {
        [actionSheet addButtonWithTitle:AppInfoVersionDisplayTitle(app, ver)];
    }
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [actionSheet setCancelButtonIndex:[app.versions count]];
    [actionSheet showInView:AppInfoActionSheetPresentationView(self.view)];

}

- (NSString *)shareTextForCurrentApplication {
    NSString *name = ([app.name length] > 0) ? app.name : app.bundleid;
    NSString *developer = VeterisTrimmedString(app.developer);
    BOOL hasKnownDeveloper = ([developer length] > 0 && ![[developer lowercaseString] isEqualToString:@"unknown developer"]);
    if (hasKnownDeveloper) {
        return [NSString stringWithFormat:@"%@ by %@ on Veteris", name, developer];
    }
    return [NSString stringWithFormat:@"%@ on Veteris", name];
}

- (NSURL *)shareURLForCurrentApplication {
    if ([app.bundleid length] == 0) {
        return nil;
    }
    NSString *urlString = [NSString stringWithFormat:@"veteris://app/%@", AppInfoURLEscape(app.bundleid)];
    return [NSURL URLWithString:urlString];
}

- (void)showActionsFallbackActionSheet {
    BOOL favorite = [VeterisFavoritesManager isFavoriteBundleID:app.bundleid];
    NSString *favoriteTitle = favorite ? NSLocalizedString(@"RemoveFromFavorites", nil) : NSLocalizedString(@"AddToFavorites", nil);
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:app.name
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:favoriteTitle, NSLocalizedString(@"CopyLink", nil), nil];
    actionSheet.tag = AppInfoActionsActionSheetTag;
    [actionSheet showInView:AppInfoActionSheetPresentationView(self.view)];
}

- (void)copyCurrentApplicationLink {
    NSURL *shareURL = [self shareURLForCurrentApplication];
    NSString *link = [shareURL absoluteString];
    if ([link length] == 0) {
        return;
    }
    [UIPasteboard generalPasteboard].string = link;
}

- (void)presentNativeShareMenu {
    Class activityViewControllerClass = NSClassFromString(@"UIActivityViewController");
    if (activityViewControllerClass == Nil) {
        [self showActionsFallbackActionSheet];
        return;
    }

    id favoriteActivity = AppInfoFavoriteActivityForApplication(app);
    NSArray *applicationActivities = (favoriteActivity != nil) ? [NSArray arrayWithObject:favoriteActivity] : nil;
    NSMutableArray *activityItems = [NSMutableArray arrayWithObject:[self shareTextForCurrentApplication]];
    NSURL *shareURL = [self shareURLForCurrentApplication];
    if (shareURL != nil) {
        [activityItems addObject:shareURL];
    }
    id activityController = [[activityViewControllerClass alloc] initWithActivityItems:activityItems applicationActivities:applicationActivities];
    if ([activityController respondsToSelector:@selector(setExcludedActivityTypes:)]) {
        [activityController setExcludedActivityTypes:AppInfoExcludedSystemActivityTypes()];
    }
    UIViewController *activityViewController = (UIViewController *)activityController;

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityPopover = [[UIPopoverController alloc] initWithContentViewController:activityViewController];
        [activityPopover presentPopoverFromBarButtonItem:self.navigationItem.rightBarButtonItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [self presentViewController:activityViewController animated:YES completion:nil];
    }
}

- (void)actionsButtonPressed:(id)sender {
    if (!initialized || app == nil) {
        alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"WaitForAppFinishLoading", nil), VAPIHelperErrorUnknown);
        return;
    }

    [self presentNativeShareMenu];
}

- (void)enqueueVersionAtIndex:(NSInteger)versionIndex {
    if (versionIndex >= 0 && [app.versions count] > versionIndex) {
        YZApplication *yzApp = [[YZApplication alloc] initFromApp:app version:[app.versions objectAtIndex:versionIndex]];
        [YZQueueManager enqueueYZApplicationForDownload:yzApp];
    } else {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"NoVersionsAvailable", @"%@ has NOT been installed, no versions available."), app.name];
        alert(@"Error", message, VAPIHelperErrorUnknown);
    }
}

- (NSString *)safeDownloadFileComponent:(NSString *)string {
    if ([string length] == 0) {
        return @"Unknown";
    }
    NSMutableCharacterSet *disallowed = [[[NSCharacterSet alphanumericCharacterSet] invertedSet] mutableCopy];
    [disallowed removeCharactersInString:@"._- "];
    NSArray *parts = [string componentsSeparatedByCharactersInSet:disallowed];
    NSString *clean = [parts componentsJoinedByString:@"_"];
    while ([clean rangeOfString:@"__"].location != NSNotFound) {
        clean = [clean stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    }
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return ([clean length] > 0) ? clean : @"Unknown";
}

- (NSString *)downloadOnlyPathForVersion:(Version *)version {
    NSString *name = [self safeDownloadFileComponent:app.name ?: app.bundleid];
    NSString *versionString = [self safeDownloadFileComponent:version.version];
    NSString *bundleID = [self safeDownloadFileComponent:AppInfoDisplayBundleIDForVersion(app, version)];
    NSString *fileName = [NSString stringWithFormat:@"%@-%@-%@.ipa", name, versionString, bundleID];
    return [downloadOnlyPath() stringByAppendingPathComponent:fileName];
}

- (void)showDownloadOnlyInfoAlertIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:AppInfoDownloadOnlyInfoShownDefaultsKey]) {
        return;
    }

    [defaults setBool:YES forKey:AppInfoDownloadOnlyInfoShownDefaultsKey];
    [defaults synchronize];

    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"DownloadOnlyInfoMessageFormat", nil), downloadOnlyPath()];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Download", nil)
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void)downloadVersionAtIndex:(NSInteger)versionIndex {
    if (versionIndex >= 0 && [app.versions count] > versionIndex) {
        Version *version = [app.versions objectAtIndex:versionIndex];
        YZApplication *yzApp = [[YZApplication alloc] initFromApp:app version:version];
        [self showDownloadOnlyInfoAlertIfNeeded];
        [YZQueueManager enqueueYZApplicationForDownloadOnly:yzApp targetPath:[self downloadOnlyPathForVersion:version]];
    } else {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"NoVersionsAvailable", @"%@ has NOT been installed, no versions available."), app.name];
        alert(@"Error", message, VAPIHelperErrorUnknown);
    }
}

- (void)showVersionInfoAtIndex:(NSInteger)versionIndex {
    if (versionIndex < 0 || versionIndex >= [app.versions count]) {
        return;
    }
    Version *version = [app.versions objectAtIndex:versionIndex];
    AppInfo *versionInfo = [self.storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
    [versionInfo view];
    [versionInfo initializeVersionInfoWithApplication:app version:version image:self.appUIImage.image];
    [self.navigationController pushViewController:versionInfo animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == AppInfoActionsActionSheetTag) {
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            return;
        }
        if (buttonIndex == AppInfoActionFavoriteIndex) {
            [VeterisFavoritesManager toggleFavoriteApplication:app];
        } else if (buttonIndex == AppInfoActionCopyLinkIndex) {
            [self copyCurrentApplicationLink];
        }
        return;
    }

    if (actionSheet.tag == AppInfoVersionCellActionSheetTag) {
        if (buttonIndex == actionSheet.cancelButtonIndex) {
            pendingVersionActionIndex = AppInfoNoPendingVersionIndex;
            return;
        }
        if (buttonIndex == AppInfoVersionActionInstallIndex) {
            [self enqueueVersionAtIndex:pendingVersionActionIndex];
        } else if (buttonIndex == AppInfoVersionActionDownloadIndex) {
            [self downloadVersionAtIndex:pendingVersionActionIndex];
        } else if (buttonIndex == AppInfoVersionActionInfoIndex) {
            [self showVersionInfoAtIndex:pendingVersionActionIndex];
        }
        pendingVersionActionIndex = AppInfoNoPendingVersionIndex;
        return;
    }

    if (buttonIndex == [app.versions count]) {
        return;
    }
    [self enqueueVersionAtIndex:buttonIndex];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == relatedTableView) {
        return [relatedApps count];
    }
    return [app.versions count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == relatedTableView) {
        return 77.0;
    }
    return 58.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == relatedTableView) {
        static NSString *relatedCellIdentifier = @"AppInfoRelatedCell";
        SearchTableViewCell *cell = (SearchTableViewCell *)[tableView dequeueReusableCellWithIdentifier:relatedCellIdentifier];
        if (cell == nil) {
            cell = [[SearchTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:relatedCellIdentifier];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }

        Application *relatedApp = [relatedApps objectAtIndex:indexPath.row];
        cell.appNameLabel.text = relatedApp.name;
        cell.developerNameLabel.text = [self subtitleForRelatedApp:relatedApp];
        NSString *versionCountText = [self versionCountTextForApplication:relatedApp];
        cell.versionLabel.text = versionCountText;
        cell.versionLabel.hidden = ([versionCountText length] == 0);
        [self configureRelatedIconForCell:cell app:relatedApp];
        [self loadRelatedIconForApp:relatedApp atIndexPath:indexPath];
        return cell;
    }

    static NSString *cellIdentifier = @"AppInfoVersionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [self newVersionCellWithReuseIdentifier:cellIdentifier];
    }

    Version *version = [app.versions objectAtIndex:indexPath.row];
    [self configureVersionCell:cell version:version];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (tableView == relatedTableView) {
        if (indexPath.row >= [relatedApps count]) {
            return;
        }
        Application *relatedApp = [relatedApps objectAtIndex:indexPath.row];
        AppInfo *appinfo = [self.storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
        [appinfo view];
        SearchTableViewCell *cell = (SearchTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
        [appinfo initialize:relatedApp.bundleid developer:relatedApp.developer name:relatedApp.name image:cell.appUIImage.image];
        [self.navigationController pushViewController:appinfo animated:YES];
        return;
    }

    if (indexPath.row >= [app.versions count]) {
        return;
    }

    [self showVersionActionSheetAtIndex:indexPath.row includeInfo:YES];
}
@end
