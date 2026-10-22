//
//  IASKSpecifierValuesViewController.m
//  http://www.inappsettingskit.com
//
//  Copyright (c) 2009:
//  Luc Vandal, Edovia Inc., http://www.edovia.com
//  Ortwin Gentz, FutureTap GmbH, http://www.futuretap.com
//  All rights reserved.
// 
//  It is appreciated but not required that you give credit to Luc Vandal and Ortwin Gentz, 
//  as the original authors of this code. You can give credit in a blog post, a tweet or on 
//  a info page of your app. Also, the original authors appreciate letting them know if you use this code.
//
//  This code is licensed under the BSD license that is available at: http://www.opensource.org/licenses/bsd-license.php
//

#import "IASKSpecifierValuesViewController.h"
#import "IASKSpecifier.h"
#import "IASKSettingsReader.h"
#import "IASKSettingsStoreUserDefaults.h"
#import "../../Classes/ThemeManager/ThemeManager.h"

#define kCellValue      @"kCellValue"
#define kThemeColorPreviewTag 14201

@interface IASKSpecifierValuesViewController()
- (void)userDefaultsDidChange;
- (void)configureThemePreviewForCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
- (UIImage *)themePreviewImageForColor:(UIColor *)color blackVariant:(BOOL)blackVariant size:(CGSize)size;
- (BOOL)isThemePreferenceSpecifier;
@end

@implementation IASKSpecifierValuesViewController

@synthesize tableView=_tableView;
@synthesize currentSpecifier=_currentSpecifier;
@synthesize checkedItem=_checkedItem;
@synthesize settingsReader = _settingsReader;
@synthesize settingsStore = _settingsStore;

- (void) updateCheckedItem {
    NSInteger index;
	
	// Find the currently checked item
    if([self.settingsStore objectForKey:[_currentSpecifier key]]) {
      index = [[_currentSpecifier multipleValues] indexOfObject:[self.settingsStore objectForKey:[_currentSpecifier key]]];
    } else {
      index = [[_currentSpecifier multipleValues] indexOfObject:[_currentSpecifier defaultValue]];
    }
	[self setCheckedItem:[NSIndexPath indexPathForRow:index inSection:0]];
}

- (id<IASKSettingsStore>)settingsStore {
    if(_settingsStore == nil) {
        _settingsStore = [[IASKSettingsStoreUserDefaults alloc] init];
    }
    return _settingsStore;
}

- (void)loadView
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
    UIViewAutoresizingFlexibleHeight;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    
    self.view = _tableView;
}

- (void)viewWillAppear:(BOOL)animated {
    if (_currentSpecifier) {
        [self setTitle:[_currentSpecifier title]];
        [self updateCheckedItem];
    }
    
    if (_tableView) {
        [_tableView reloadData];

		// Make sure the currently checked item is visible
        [_tableView scrollToRowAtIndexPath:[self checkedItem] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
	[super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
	[_tableView flashScrollIndicators];
	[super viewDidAppear:animated];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(userDefaultsDidChange)
												 name:NSUserDefaultsDidChangeNotification
											   object:[NSUserDefaults standardUserDefaults]];
}

- (void)viewDidDisappear:(BOOL)animated {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSUserDefaultsDidChangeNotification object:nil];
	[super viewDidDisappear:animated];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
	self.tableView = nil;
}

#pragma mark -
#pragma mark UITableView delegates

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_currentSpecifier multipleValuesCount];
}

- (void)selectCell:(UITableViewCell *)cell {
	[cell setAccessoryType:UITableViewCellAccessoryCheckmark];
	[[cell textLabel] setTextColor:kIASKgrayBlueColor];
}

- (void)deselectCell:(UITableViewCell *)cell {
	[cell setAccessoryType:UITableViewCellAccessoryNone];
	[[cell textLabel] setTextColor:[UIColor darkTextColor]];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [_currentSpecifier footerText];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell   = [tableView dequeueReusableCellWithIdentifier:kCellValue];
    NSArray *titles         = [_currentSpecifier multipleTitles];
	
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellValue];
    }
	
	if ([indexPath isEqual:[self checkedItem]]) {
		[self selectCell:cell];
    } else {
        [self deselectCell:cell];
    }
	
	@try {
		[[cell textLabel] setText:[self.settingsReader titleForStringId:[titles objectAtIndex:indexPath.row]]];
	}
	@catch (NSException * e) {}
    [self configureThemePreviewForCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
    if (indexPath == [self checkedItem]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    NSArray *values         = [_currentSpecifier multipleValues];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self deselectCell:[tableView cellForRowAtIndexPath:[self checkedItem]]];
    [self selectCell:[tableView cellForRowAtIndexPath:indexPath]];
    [self setCheckedItem:indexPath];
	
    [self.settingsStore setObject:[values objectAtIndex:indexPath.row] forKey:[_currentSpecifier key]];
	[self.settingsStore synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIASKAppSettingChanged
                                                        object:[_currentSpecifier key]
                                                      userInfo:[NSDictionary dictionaryWithObject:[values objectAtIndex:indexPath.row]
                                                                                           forKey:[_currentSpecifier key]]];
}

- (CGSize)contentSizeForViewInPopover {
    return [[self view] sizeThatFits:CGSizeMake(320, 2000)];
}


#pragma mark Notifications

- (void)userDefaultsDidChange {
	NSIndexPath *oldCheckedItem = self.checkedItem;
	if(_currentSpecifier) {
		[self updateCheckedItem];
	}
	
	// only reload the table if it had changed; prevents animation cancellation
	if (![self.checkedItem isEqual:oldCheckedItem]) {
		[_tableView reloadData];
	}
}

- (BOOL)isThemePreferenceSpecifier {
    return [[_currentSpecifier key] isEqualToString:@"theme_preference"];
}

- (void)configureThemePreviewForCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    UIView *existingPreviewView = [cell.contentView viewWithTag:kThemeColorPreviewTag];
    if (![self isThemePreferenceSpecifier]) {
        [existingPreviewView removeFromSuperview];
        return;
    }

    UIImageView *previewView = [existingPreviewView isKindOfClass:[UIImageView class]] ? (UIImageView *)existingPreviewView : nil;
    if (previewView == nil) {
        [existingPreviewView removeFromSuperview];
        previewView = [[UIImageView alloc] initWithFrame:CGRectMake(cell.contentView.bounds.size.width - 34, 13, 18, 18)];
        previewView.tag = kThemeColorPreviewTag;
        previewView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [cell.contentView addSubview:previewView];
    }

    CGFloat previewSize = 18;
    CGFloat contentWidth = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : cell.bounds.size.width;
    CGFloat contentHeight = cell.contentView.bounds.size.height > 0 ? cell.contentView.bounds.size.height : cell.bounds.size.height;
    previewView.frame = CGRectMake(contentWidth - previewSize - 16,
                                   floorf((contentHeight - previewSize) / 2.0f),
                                   previewSize,
                                   previewSize);
    NSArray *values = [_currentSpecifier multipleValues];
    NSString *themeName = [values objectAtIndex:indexPath.row];
    UIColor *previewColor = [[ThemeManager sharedInstance] previewColorForTheme:themeName];
    BOOL blackVariant = [themeName hasSuffix:@"Black"];
    previewView.image = [self themePreviewImageForColor:previewColor ?: [UIColor darkGrayColor]
                                           blackVariant:blackVariant
                                                   size:CGSizeMake(previewSize, previewSize)];
    previewView.highlightedImage = previewView.image;
}

- (UIImage *)themePreviewImageForColor:(UIColor *)color blackVariant:(BOOL)blackVariant size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    CGRect outerCircle = CGRectInset(bounds, 1, 1);

    if (blackVariant) {
        [[UIColor blackColor] setFill];
        CGContextFillEllipseInRect(context, outerCircle);
        [[UIColor colorWithWhite:1 alpha:0.45] setStroke];
        CGContextSetLineWidth(context, 1);
        CGContextStrokeEllipseInRect(context, outerCircle);

        [color setFill];
        CGContextFillEllipseInRect(context, CGRectInset(outerCircle, 3, 3));
    } else {
        [color setFill];
        CGContextFillEllipseInRect(context, outerCircle);
        [[UIColor colorWithWhite:0 alpha:0.35] setStroke];
        CGContextSetLineWidth(context, 1);
        CGContextStrokeEllipseInRect(context, outerCircle);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
