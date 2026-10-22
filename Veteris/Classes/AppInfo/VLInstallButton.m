#import "VLInstallButton.h"

static const CGFloat VLInstallButtonHeight = 25.0;
static const NSTimeInterval VLInstallButtonTransitionDuration = 0.25;
static const CGFloat VLInstallButtonIOS6Height = 27.0;
static const NSTimeInterval VLInstallButtonIOS6TransitionDuration = 0.35;
static const CGFloat VLInstallButtonIOS6CapWidth = 11.0;
static const CGFloat VLInstallButtonIOS7Height = 25.0;
static const NSTimeInterval VLInstallButtonIOS7TransitionDuration = 0.25;
static const CGFloat VLInstallButtonIOS7CapWidth = 10.0;
static const CGFloat VLInstallButtonModernHeight = 32.0;
static const CGFloat VLInstallButtonModernHorizontalPadding = 16.0;
static const CGFloat VLInstallButtonIOS5FatCapWidth = 10.0;
static const CGFloat VLInstallButtonIOS5MinimumMiddleWidth = 38.0;

VLInstallButtonStyle VLInstallButtonDefaultStyleForCurrentSystem(void) {
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    NSArray *components = [systemVersion componentsSeparatedByString:@"."];
    if ([components count] == 0 || ![[components objectAtIndex:0] respondsToSelector:@selector(integerValue)]) {
        return VLInstallButtonStyleUIButton;
    }

    NSInteger majorVersion = [[components objectAtIndex:0] integerValue];
    if (majorVersion == 5) {
        return VLInstallButtonStyleIOS5;
    }
    if (majorVersion == 6) {
        return VLInstallButtonStyleIOS6;
    }
    if (majorVersion >= 7) {
        return VLInstallButtonStyleIOS7;
    }
    return VLInstallButtonStyleUIButton;
}

NSString *VLInstallButtonNormalTitle(VLInstallButtonStyle style) {
    if (style == VLInstallButtonStyleCloud) {
        return @"";
    }
    if (style == VLInstallButtonStyleModern) {
        return NSLocalizedStringWithDefaultValue(@"DownloadButtonGetModern", nil, [NSBundle mainBundle], @"Get", nil);
    }
    return NSLocalizedStringWithDefaultValue(@"DownloadButtonGet", nil, [NSBundle mainBundle], @"GET", nil);
}

NSString *VLInstallButtonSelectedTitle(VLInstallButtonStyle style) {
    if (style == VLInstallButtonStyleCloud || style == VLInstallButtonStyleModern) {
        return VLInstallButtonNormalTitle(style);
    }
    return NSLocalizedStringWithDefaultValue(@"DownloadButtonInstallApp", nil, [NSBundle mainBundle], @"INSTALL APP", nil);
}

@interface VLInstallButton ()
- (UIImage *)imageNamed:(NSString *)name;
- (void)updateImages;
- (void)finishTransition;
- (void)setPressed:(BOOL)pressed;
- (void)layoutForWidth:(CGFloat)width;
- (void)configureForStyle;
- (void)animateToWidth:(CGFloat)width duration:(NSTimeInterval)duration;
- (void)drawIOS6ButtonInRect:(CGRect)rect;
- (void)drawIOS7ButtonInRect:(CGRect)rect;
- (void)drawModernButtonInRect:(CGRect)rect;
- (void)updateIOS6Label;
@end

@implementation VLInstallButton

- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary {
    return [self initWithFrame:frame fatBinary:fatBinary expandsLeft:NO];
}

- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft {
    return [self initWithFrame:frame fatBinary:fatBinary expandsLeft:expandsLeft normalWidth:72.0];
}

- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth {
    return [self initWithFrame:frame
                      fatBinary:fatBinary
                   expandsLeft:expandsLeft
                    normalWidth:normalWidth
                  selectedWidth:144.0];
}

- (id)initWithFrame:(CGRect)frame fatBinary:(BOOL)fatBinary expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth selectedWidth:(CGFloat)selectedWidth {
    if ((self = [super initWithFrame:frame])) {
        _fatBinary = fatBinary;
        _expandsLeft = expandsLeft;
        _normalWidth = normalWidth;
        _selectedWidth = selectedWidth;
        _buttonStyle = VLInstallButtonStyleIOS5;
        _installSelected = NO;
        _pressed = NO;
        [self configureForStyle];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame style:(VLInstallButtonStyle)style {
    CGFloat normalWidth = [[self class] buttonWidthForText:VLInstallButtonNormalTitle(style) style:style];
    CGFloat selectedWidth = [[self class] buttonWidthForText:VLInstallButtonSelectedTitle(style) style:style];
    if (style == VLInstallButtonStyleCloud) {
        normalWidth = frame.size.width;
        selectedWidth = normalWidth;
    }
    return [self initWithFrame:frame style:style expandsLeft:NO normalWidth:normalWidth selectedWidth:selectedWidth];
}

- (id)initWithFrame:(CGRect)frame style:(VLInstallButtonStyle)style expandsLeft:(BOOL)expandsLeft normalWidth:(CGFloat)normalWidth selectedWidth:(CGFloat)selectedWidth {
    if ((self = [super initWithFrame:frame])) {
        _fatBinary = YES;
        _expandsLeft = expandsLeft;
        _normalWidth = normalWidth;
        _selectedWidth = MAX(normalWidth, selectedWidth);
        _buttonStyle = style;
        _installSelected = NO;
        _pressed = NO;
        [self configureForStyle];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame fatBinary:NO];
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_leftSlice release];
    [_middleSlice release];
    [_rightSlice release];
    [_label release];
    [_cloudImageView release];
#endif
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (UIImage *)imageNamed:(NSString *)name {
    NSString *path = [[NSBundle mainBundle] pathForResource:name
                                                      ofType:nil
                                                 inDirectory:@"downloadButton"];
    return path != nil ? [UIImage imageWithContentsOfFile:path] : nil;
}

+ (CGFloat)buttonWidthForText:(NSString *)text style:(VLInstallButtonStyle)style {
    if (style == VLInstallButtonStyleCloud) {
        return 47.0;
    }
    NSString *fontName = style == VLInstallButtonStyleIOS5 ? @"Helvetica-Bold" : @"HelveticaNeue-Bold";
    UIFont *font = [UIFont fontWithName:fontName size:13.0];
    if (font == nil) {
        font = [UIFont boldSystemFontOfSize:13.0];
    }
    CGSize textSize = [text sizeWithFont:font];
    if (style == VLInstallButtonStyleIOS5) {
        CGFloat middleWidth = MAX(VLInstallButtonIOS5MinimumMiddleWidth,
                                   ceil(textSize.width) + 8.0);
        return middleWidth + (VLInstallButtonIOS5FatCapWidth * 2.0);
    }
    if (style == VLInstallButtonStyleModern) {
        return ceil(textSize.width) + (VLInstallButtonModernHorizontalPadding * 2.0);
    }
    if (style == VLInstallButtonStyleUIButton) {
        UIButton *nativeButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [nativeButton setTitle:text forState:UIControlStateNormal];
        [nativeButton sizeToFit];
        return ceil(nativeButton.bounds.size.width);
    }
    CGFloat capWidth = style == VLInstallButtonStyleIOS7 ? VLInstallButtonIOS7CapWidth : VLInstallButtonIOS6CapWidth;
    return ceil(textSize.width) + (capWidth * 2.0);
}

- (void)configureForStyle {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (UIView *subview in [self.subviews copy]) {
        [subview removeFromSuperview];
    }
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.clipsToBounds = (_buttonStyle == VLInstallButtonStyleIOS6 || _buttonStyle == VLInstallButtonStyleIOS7 || _buttonStyle == VLInstallButtonStyleModern);

    if (_buttonStyle == VLInstallButtonStyleCloud) {
        CGRect frame = self.frame;
        frame.size.width = _normalWidth;
        frame.size.height = 28.0;
        self.frame = frame;
        _cloudImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _cloudImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _cloudImageView.contentMode = UIViewContentModeScaleToFill;
        _cloudImageView.image = [UIImage imageNamed:@"DownloadButton.png"];
        _cloudImageView.userInteractionEnabled = NO;
        [self addSubview:_cloudImageView];
        _currentWidth = _normalWidth;
        return;
    }

    CGFloat height = _buttonStyle == VLInstallButtonStyleIOS6 ? VLInstallButtonIOS6Height :
                      (_buttonStyle == VLInstallButtonStyleModern ? VLInstallButtonModernHeight : VLInstallButtonHeight);
    CGRect frame = self.frame;
    frame.size.width = _normalWidth;
    frame.size.height = height;
    self.frame = frame;

    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        _leftSlice = [[UIImageView alloc] initWithFrame:CGRectZero];
        _middleSlice = [[UIImageView alloc] initWithFrame:CGRectZero];
        _rightSlice = [[UIImageView alloc] initWithFrame:CGRectZero];
        _leftSlice.contentMode = UIViewContentModeScaleToFill;
        _middleSlice.contentMode = UIViewContentModeScaleToFill;
        _rightSlice.contentMode = UIViewContentModeScaleToFill;
        _leftSlice.userInteractionEnabled = NO;
        _middleSlice.userInteractionEnabled = NO;
        _rightSlice.userInteractionEnabled = NO;
        [self addSubview:_leftSlice];
        [self addSubview:_middleSlice];
        [self addSubview:_rightSlice];

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont fontWithName:@"Helvetica-Bold" size:13.0];
        if (_label.font == nil) {
            _label.font = [UIFont boldSystemFontOfSize:13.0];
        }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 60000
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
#else
        _label.textAlignment = UITextAlignmentCenter;
        _label.lineBreakMode = UILineBreakModeTailTruncation;
#endif
        _label.numberOfLines = 1;
        _label.text = VLInstallButtonNormalTitle(_buttonStyle);
        _label.userInteractionEnabled = NO;
        _label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.6];
        _label.shadowOffset = CGSizeMake(0.0, -1.0);
        [self addSubview:_label];
        [self layoutForWidth:_normalWidth];
        [self updateImages];
    } else if (_buttonStyle == VLInstallButtonStyleIOS6) {
        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13.0];
        if (_label.font == nil) {
            _label.font = [UIFont boldSystemFontOfSize:13.0];
        }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 60000
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByTruncatingTail;
#else
        _label.textAlignment = UITextAlignmentCenter;
        _label.lineBreakMode = UILineBreakModeTailTruncation;
#endif
        _label.numberOfLines = 1;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];
        _currentWidth = _normalWidth;
        [self updateIOS6Label];
        [self setNeedsDisplay];
    } else if (_buttonStyle == VLInstallButtonStyleIOS7) {
        _currentWidth = _normalWidth;
        [self setNeedsDisplay];
    } else {
        _currentWidth = _normalWidth;
        [self setNeedsDisplay];
    }
}

- (void)setButtonStyle:(VLInstallButtonStyle)style {
    if (_buttonStyle == style) {
        return;
    }
    _buttonStyle = style;
    _installSelected = NO;
    _pressed = NO;
    _normalWidth = [[self class] buttonWidthForText:VLInstallButtonNormalTitle(style) style:style];
    _selectedWidth = [[self class] buttonWidthForText:VLInstallButtonSelectedTitle(style) style:style];
    [self configureForStyle];
}

- (VLInstallButtonStyle)buttonStyle {
    return _buttonStyle;
}

- (void)updateImages {
    NSString *capPrefix;
    NSString *leftName;
    NSString *rightName;
    NSString *middleName;

    if (_installSelected) {
        capPrefix = _fatBinary ? @"green_fat" : @"green";
        leftName = _pressed ? [NSString stringWithFormat:@"left_%@_pressed.2x.png", capPrefix]
                            : [NSString stringWithFormat:@"left_%@.2x.png", capPrefix];
        rightName = _pressed ? [NSString stringWithFormat:@"right_%@_pressed.2x.png", capPrefix]
                             : [NSString stringWithFormat:@"right_%@.2x.png", capPrefix];
        middleName = _pressed ? @"middle_green_pressed.2x.png" : @"middle_green.2x.png";
    } else {
        capPrefix = _fatBinary ? @"app_fat" : @"app";
        leftName = _pressed ? [NSString stringWithFormat:@"left_%@_pressed.2x.png", capPrefix]
                            : [NSString stringWithFormat:@"left_%@.2x.png", capPrefix];
        rightName = _pressed ? [NSString stringWithFormat:@"right_%@_pressed.2x.png", capPrefix]
                             : [NSString stringWithFormat:@"right_%@.2x.png", capPrefix];
        middleName = _pressed ? @"middle_app_pressed.2x.png" : @"middle_app.2x.png";
    }

    _leftSlice.image = [self imageNamed:leftName];
    _middleSlice.image = [self imageNamed:middleName];
    _rightSlice.image = [self imageNamed:rightName];
}

- (void)layoutForWidth:(CGFloat)width {
    CGFloat capWidth = _fatBinary ? VLInstallButtonIOS5FatCapWidth : 6.0;
    CGFloat middleWidth = width - (capWidth * 2.0);
    CGFloat halfHeight = VLInstallButtonHeight / 2.0;

    _leftSlice.frame = CGRectMake(0.0, 0.0, capWidth, VLInstallButtonHeight);
    _middleSlice.bounds = CGRectMake(0.0, 0.0, 1.0, VLInstallButtonHeight);
    _middleSlice.center = CGPointMake(capWidth + (middleWidth / 2.0), halfHeight);
    _middleSlice.transform = CGAffineTransformMakeScale(middleWidth, 1.0);
    _rightSlice.bounds = CGRectMake(0.0, 0.0, capWidth, VLInstallButtonHeight);
    _rightSlice.center = CGPointMake(_normalWidth - (capWidth / 2.0), halfHeight);
    _rightSlice.transform = CGAffineTransformMakeTranslation(width - _normalWidth, 0.0);
    _label.frame = CGRectMake(capWidth, 0.0, middleWidth, VLInstallButtonHeight);
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        [self updateImages];
    } else if (_buttonStyle == VLInstallButtonStyleIOS6 || _buttonStyle == VLInstallButtonStyleIOS7 || _buttonStyle == VLInstallButtonStyleModern) {
        [self setNeedsDisplay];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking;
    tracking = [super beginTrackingWithTouch:touch withEvent:event];
    if (tracking) [self setPressed:YES];
    return tracking;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL inside = CGRectContainsPoint(self.bounds, [touch locationInView:self]);
    [self setPressed:inside];
    return [super continueTrackingWithTouch:touch withEvent:event];
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self setPressed:NO];
    [super endTrackingWithTouch:touch withEvent:event];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self setPressed:NO];
    [super cancelTrackingWithEvent:event];
}

- (void)activate {
    if (_buttonStyle == VLInstallButtonStyleCloud || _buttonStyle == VLInstallButtonStyleModern || _installSelected || !self.enabled) return;
    _installSelected = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishTransition) object:nil];
    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        [self updateImages];
        _label.text = VLInstallButtonSelectedTitle(_buttonStyle);
        [self animateToWidth:_selectedWidth duration:VLInstallButtonTransitionDuration];
    } else if (_buttonStyle == VLInstallButtonStyleIOS6) {
        [self updateIOS6Label];
        [self setNeedsDisplay];
        [self animateToWidth:_selectedWidth duration:VLInstallButtonIOS6TransitionDuration];
    } else {
        [self setNeedsDisplay];
        [self animateToWidth:_selectedWidth duration:VLInstallButtonIOS7TransitionDuration];
    }
    [self performSelector:@selector(finishTransition)
               withObject:nil
               afterDelay:(_buttonStyle == VLInstallButtonStyleIOS6 ? VLInstallButtonIOS6TransitionDuration :
                           (_buttonStyle == VLInstallButtonStyleIOS7 ? VLInstallButtonIOS7TransitionDuration : VLInstallButtonTransitionDuration))];
}

- (void)reset {
    if (_buttonStyle == VLInstallButtonStyleCloud || _buttonStyle == VLInstallButtonStyleModern || !_installSelected) return;
    _installSelected = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishTransition) object:nil];
    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        [self updateImages];
        _label.text = VLInstallButtonNormalTitle(_buttonStyle);
        [self animateToWidth:_normalWidth duration:VLInstallButtonTransitionDuration];
    } else if (_buttonStyle == VLInstallButtonStyleIOS6) {
        [self updateIOS6Label];
        [self setNeedsDisplay];
        [self animateToWidth:_normalWidth duration:VLInstallButtonIOS6TransitionDuration];
    } else {
        [self setNeedsDisplay];
        [self animateToWidth:_normalWidth duration:VLInstallButtonIOS7TransitionDuration];
    }
    [self performSelector:@selector(finishTransition)
               withObject:nil
               afterDelay:(_buttonStyle == VLInstallButtonStyleIOS6 ? VLInstallButtonIOS6TransitionDuration :
                           (_buttonStyle == VLInstallButtonStyleIOS7 ? VLInstallButtonIOS7TransitionDuration : VLInstallButtonTransitionDuration))];
}

- (void)animateToWidth:(CGFloat)width duration:(NSTimeInterval)duration {
    CGRect frame = self.frame;
    CGFloat oldWidth = frame.size.width;
    if (_expandsLeft) {
        frame.origin.x += oldWidth - width;
    }
    frame.size.width = width;
    _currentWidth = width;
    [UIView beginAnimations:@"VLInstallButtonWidth" context:NULL];
    [UIView setAnimationDuration:duration];
    self.frame = frame;
    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        [self layoutForWidth:width];
    } else if (_buttonStyle == VLInstallButtonStyleIOS6) {
        [self updateIOS6Label];
    } else if (_buttonStyle == VLInstallButtonStyleIOS7) {
        [self setNeedsDisplay];
    }
    [UIView commitAnimations];
    if (_buttonStyle == VLInstallButtonStyleIOS6 || _buttonStyle == VLInstallButtonStyleIOS7) {
        [self setNeedsDisplay];
    }
}

- (void)setSelectedWidth:(CGFloat)selectedWidth {
    _selectedWidth = MAX(_normalWidth, selectedWidth);
}

- (void)finishTransition {
    if (_buttonStyle == VLInstallButtonStyleIOS5) {
        _label.text = _installSelected ? VLInstallButtonSelectedTitle(_buttonStyle) : VLInstallButtonNormalTitle(_buttonStyle);
    }
}

- (BOOL)isInstallSelected {
    return _installSelected;
}

- (void)drawRect:(CGRect)rect {
    if (_buttonStyle == VLInstallButtonStyleIOS6) {
        [self drawIOS6ButtonInRect:rect];
    } else if (_buttonStyle == VLInstallButtonStyleIOS7) {
        [self drawIOS7ButtonInRect:rect];
    } else if (_buttonStyle == VLInstallButtonStyleModern) {
        [self drawModernButtonInRect:rect];
    }
}

- (void)drawModernButtonInRect:(CGRect)rect {
    CGFloat width = MAX(1.0, self.bounds.size.width);
    CGFloat height = VLInstallButtonModernHeight;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);

    UIColor *backgroundColor = _pressed
        ? [UIColor colorWithRed:0.0 green:115.0 / 255.0 blue:240.0 / 255.0 alpha:1.0]
        : [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:255.0 / 255.0 alpha:1.0];
    CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
    UIBezierPath *buttonPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, width, height)
                                                               cornerRadius:height / 2.0];
    CGContextAddPath(context, buttonPath.CGPath);
    CGContextFillPath(context);

    NSString *text = VLInstallButtonNormalTitle(VLInstallButtonStyleModern);
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13.0];
    if (font == nil) {
        font = [UIFont boldSystemFontOfSize:13.0];
    }
    CGSize textSize = [text sizeWithFont:font];
    [[UIColor colorWithWhite:1.0 alpha:0.85] set];
    [text drawAtPoint:CGPointMake(floor((width - textSize.width) / 2.0),
                                  floor((height - textSize.height) / 2.0))
             withFont:font];
    CGContextRestoreGState(context);
}

- (void)drawIOS7ButtonInRect:(CGRect)rect {
    CGFloat width = MAX(1.0, self.bounds.size.width);
    CGFloat height = VLInstallButtonIOS7Height;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);

    UIColor *buttonColor = _installSelected
        ? [UIColor colorWithRed:25.0 / 255.0 green:171.0 / 255.0 blue:32.0 / 255.0 alpha:1.0]
        : [UIColor colorWithRed:57.0 / 255.0 green:170.0 / 255.0 blue:220.0 / 255.0 alpha:1.0];

    CGRect buttonRect = CGRectMake(0.5, 0.5, MAX(0.0, width - 1.0), height - 1.0);
    UIBezierPath *buttonPath = [UIBezierPath bezierPathWithRoundedRect:buttonRect cornerRadius:3.0];
    CGContextAddPath(context, buttonPath.CGPath);
    CGContextSetLineWidth(context, 1.0);
    CGContextSetStrokeColorWithColor(context, buttonColor.CGColor);
    if (_pressed) {
        CGContextSetFillColorWithColor(context, buttonColor.CGColor);
        CGContextDrawPath(context, kCGPathFillStroke);
    } else {
        CGContextDrawPath(context, kCGPathStroke);
    }

    NSString *text = _installSelected ? VLInstallButtonSelectedTitle(_buttonStyle) : VLInstallButtonNormalTitle(_buttonStyle);
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13.0];
    if (font == nil) {
        font = [UIFont boldSystemFontOfSize:13.0];
    }
    UIColor *textColor = _pressed ? [UIColor whiteColor] : buttonColor;
    CGFloat textX = VLInstallButtonIOS7CapWidth;
    CGFloat textY = 17.0 - font.ascender;
    [textColor set];
    [text drawAtPoint:CGPointMake(textX, textY) withFont:font];
    CGContextRestoreGState(context);
}

- (void)drawIOS6ButtonInRect:(CGRect)rect {
    CGFloat width = MAX(1.0, self.bounds.size.width);
    CGFloat height = VLInstallButtonIOS6Height;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *fillColors;
    NSArray *strokeColors;
    if (_installSelected) {
        fillColors = _pressed ? @[
            (id)[UIColor colorWithRed:185.0/255.0 green:218.0/255.0 blue:173.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:109.0/255.0 green:173.0/255.0 blue:82.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:66.0/255.0 green:122.0/255.0 blue:39.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:61.0/255.0 green:113.0/255.0 blue:35.0/255.0 alpha:1.0].CGColor
        ] : @[
            (id)[UIColor colorWithRed:194.0/255.0 green:232.0/255.0 blue:179.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:128.0/255.0 green:203.0/255.0 blue:97.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:77.0/255.0 green:143.0/255.0 blue:46.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:71.0/255.0 green:132.0/255.0 blue:42.0/255.0 alpha:1.0].CGColor
        ];
        strokeColors = _pressed ? @[
            (id)[UIColor colorWithRed:89.0/255.0 green:141.0/255.0 blue:67.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:29.0/255.0 green:56.0/255.0 blue:17.0/255.0 alpha:1.0].CGColor
        ] : @[
            (id)[UIColor colorWithRed:104.0/255.0 green:166.0/255.0 blue:79.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:34.0/255.0 green:66.0/255.0 blue:20.0/255.0 alpha:1.0].CGColor
        ];
    } else if (_pressed) {
        fillColors = @[
            (id)[UIColor colorWithWhite:0.937 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.937 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.859 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:205.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.749 alpha:1.0].CGColor
        ];
        strokeColors = @[
            (id)[UIColor colorWithWhite:0.690 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.588 alpha:1.0].CGColor
        ];
    } else {
        fillColors = @[
            (id)[UIColor whiteColor].CGColor,
            (id)[UIColor whiteColor].CGColor,
            (id)[UIColor colorWithWhite:239.0/255.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.859 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.816 alpha:1.0].CGColor
        ];
        strokeColors = @[
            (id)[UIColor colorWithWhite:0.753 alpha:1.0].CGColor,
            (id)[UIColor colorWithWhite:0.639 alpha:1.0].CGColor
        ];
    }

    CGFloat fillLocations[] = {0.0,
                               _installSelected ? 0.10 : 0.07,
                               _installSelected ? 0.89 : 0.08,
                               _installSelected ? 1.0 : 0.89,
                               1.0};
    CGFloat strokeLocations[] = {0.0, 1.0};
    CGGradientRef fillGradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)fillColors, fillLocations);
    CGGradientRef strokeGradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)strokeColors, strokeLocations);

    CGMutablePathRef shadowPath = CGPathCreateMutable();
    CGPathMoveToPoint(shadowPath, NULL, 3.5, 1.0);
    CGPathAddArcToPoint(shadowPath, NULL, width - 0.5, 1.0, width - 0.5, height - 1.0, 3.0);
    CGPathAddArcToPoint(shadowPath, NULL, width - 0.5, height - 1.0, 0.5, height - 1.0, 3.0);
    CGPathAddArcToPoint(shadowPath, NULL, 0.5, height - 1.0, 0.5, 1.0, 3.0);
    CGPathAddArcToPoint(shadowPath, NULL, 0.5, 1.0, width - 0.5, 1.0, 3.0);
    CGPathCloseSubpath(shadowPath);
    CGContextAddPath(context, shadowPath);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextFillPath(context);
    CGPathRelease(shadowPath);

    CGMutablePathRef buttonPath = CGPathCreateMutable();
    CGPathMoveToPoint(buttonPath, NULL, 3.5, 0.5);
    CGPathAddArcToPoint(buttonPath, NULL, width - 0.5, 0.5, width - 0.5, height - 2.5, 3.0);
    CGPathAddArcToPoint(buttonPath, NULL, width - 0.5, height - 2.5, 0.5, height - 2.5, 3.0);
    CGPathAddArcToPoint(buttonPath, NULL, 0.5, height - 2.5, 0.5, 0.5, 3.0);
    CGPathAddArcToPoint(buttonPath, NULL, 0.5, 0.5, width - 0.5, 0.5, 3.0);
    CGPathCloseSubpath(buttonPath);
    CGContextAddPath(context, buttonPath);
    CGContextSaveGState(context);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, fillGradient, CGPointMake(0.0, 0.0), CGPointMake(0.0, height), 0);
    CGContextRestoreGState(context);
    CGContextAddPath(context, buttonPath);
    CGContextSaveGState(context);
    CGContextReplacePathWithStrokedPath(context);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, strokeGradient, CGPointMake(0.0, 0.0), CGPointMake(0.0, height), 0);
    CGContextRestoreGState(context);
    CGPathRelease(buttonPath);

    CGGradientRelease(fillGradient);
    CGGradientRelease(strokeGradient);
    CGColorSpaceRelease(colorSpace);
    CGContextRestoreGState(context);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_buttonStyle == VLInstallButtonStyleIOS6) {
        [self updateIOS6Label];
        _currentWidth = self.bounds.size.width;
        [self setNeedsDisplay];
    } else if (_buttonStyle == VLInstallButtonStyleIOS7) {
        _currentWidth = self.bounds.size.width;
        [self setNeedsDisplay];
    } else if (_buttonStyle == VLInstallButtonStyleModern) {
        _currentWidth = self.bounds.size.width;
        [self setNeedsDisplay];
    }
}

- (void)updateIOS6Label {
    if (_buttonStyle != VLInstallButtonStyleIOS6 || _label == nil) {
        return;
    }
    _label.text = _installSelected ? VLInstallButtonSelectedTitle(_buttonStyle) : VLInstallButtonNormalTitle(_buttonStyle);
    _label.textColor = _installSelected ? [UIColor whiteColor] : [UIColor colorWithWhite:0.416 alpha:1.0];
    _label.shadowColor = _installSelected ? [UIColor colorWithWhite:0.0 alpha:0.5] : [UIColor whiteColor];
    _label.shadowOffset = CGSizeMake(0.0, _installSelected ? -1.0 : 1.0);
    _label.clipsToBounds = YES;
    _label.frame = CGRectMake(VLInstallButtonIOS6CapWidth,
                              0.0,
                              MAX(0.0, self.bounds.size.width - (VLInstallButtonIOS6CapWidth * 2.0)),
                              VLInstallButtonIOS6Height);
}

@end
