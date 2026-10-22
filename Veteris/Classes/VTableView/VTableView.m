#import "VTableView.h"
#import <QuartzCore/QuartzCore.h>
#import "../../AppDelegate.h"
#import "../AppInfo/AppInfo.h"
#import "../AppListTableViewCell/AppListTableViewCell.h"
#import "../Convenience/Convenience.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "InAppSettingsKit/Models/IASKSettingsReader.h"
#import "../ProtoStack.h"
#import "../LoadingIndicatorView/LoadingIndicatorView.h"

enum {
    VeterisListSortOptionID = 0,
    VeterisListSortOptionMode,
    VeterisListSortOptionOrder,
    VeterisListSortOptionKey,
    VeterisListSortOptionTitle
};

static NSArray *VeterisListSortOptions(void) {
    return @[
        @[@"name", @"name", @"asc", @"ListSortName", @"Name (A–Z)"],
        @[@"name-desc", @"name", @"desc", @"ListSortNameReverse", @"Name (Z–A)"],
        @[@"developer", @"developer", @"asc", @"ListSortDeveloper", @"Developer (A–Z)"],
        @[@"developer-desc", @"developer", @"desc", @"ListSortDeveloperReverse", @"Developer (Z–A)"],
        @[@"versions", @"versions", @"desc", @"ListSortMostVersions", @"Most Versions"],
        @[@"versions-asc", @"versions", @"asc", @"ListSortFewestVersions", @"Fewest Versions"],
        @[@"popular", @"popular", @"desc", @"ListSortMostPopular", @"Most Popular"],
        @[@"popular-asc", @"popular", @"asc", @"ListSortLeastPopular", @"Least Popular"],
        @[@"size", @"size", @"asc", @"ListSortSmallestSize", @"Smallest Size"],
        @[@"size-desc", @"size", @"desc", @"ListSortLargestSize", @"Largest Size"]
    ];
}

static NSArray *VeterisListSortOption(NSString *identifier) {
    for (NSArray *option in VeterisListSortOptions()) {
        if ([[option objectAtIndex:VeterisListSortOptionID] isEqualToString:identifier]) {
            return option;
        }
    }
    return nil;
}

static NSString *VeterisListSortTitle(NSArray *option) {
    return [[NSBundle mainBundle] localizedStringForKey:[option objectAtIndex:VeterisListSortOptionKey]
                                                  value:[option objectAtIndex:VeterisListSortOptionTitle]
                                                  table:nil];
}

@interface VTableView () <UIActionSheetDelegate>
- (void)loadIconsForVisibleRowsIfIdle;
- (void)loadIconForApp:(Application *)app atIndexPath:(NSIndexPath *)indexPath;
- (void)configureIconForCell:(AppListTableViewCell *)cell app:(Application *)app;
@end

@implementation VTableView {
    NSString *_endpoint;
    LoadingIndicatorView *loadingIndicator;
    UILabel *errorLabel;
    NSMutableSet *_loadingIconURLs;
    NSUInteger _iconLoadGeneration;
    BOOL _viewIsVisible;
    BOOL _registeredForThemeNotifications;
    bool inInit;
    int firstAppear;
    NSString *_sortDefaultsKey;
    NSString *_sortOption;
    NSString *_sortBaseEndpoint;
    UIActionSheet *_sortSheet;
}
@synthesize applications;

- (void)initialize:(NSString *)endpoint {
    [self initialize:endpoint skipIndicator:NO];
}

- (void)initialize:(NSString *)endpoint skipIndicator:(BOOL)skipIndicator {
    inInit = YES;
    if (_loadingIconURLs == nil) {
        _loadingIconURLs = [[NSMutableSet alloc] init];
    }
    if (!_registeredForThemeNotifications) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(reconfigure:) name:kPleaseReloadThemes object:nil];
        _registeredForThemeNotifications = YES;
    }
    debugLog(@"Initializing with endpoint: %@", endpoint);
    _endpoint = endpoint;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundView = [[UIView alloc] initWithFrame:self.tableView.frame];
    self.tableView.backgroundView.backgroundColor = [UIColor whiteColor];
    if (!skipIndicator) {
        NSString *loadingTextKey = ([endpoint hasPrefix:@"listing/random"]) ? @"Shuffling" : @"Loading";
        loadingIndicator = [LoadingIndicatorView attachToView:getDelegate().window textKey:loadingTextKey];
    }

    if (errorLabel == nil) {
        errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        errorLabel.text = NSLocalizedString(@"FailedToLoadContent", nil);
        [errorLabel sizeToFit];
        errorLabel.textColor = [UIColor grayColor];
        errorLabel.backgroundColor = [UIColor clearColor];
        errorLabel.textAlignment = NSTextAlignmentCenter;
        errorLabel.center = CGPointMake(self.tableView.center.x, getDelegate().window.center.y);
    }

    [VAPISS getMessage:endpoint completion:^(NSData *data, NSError *error){
        if (error == nil) {
            applications = (NSMutableArray *)(CFBridgingRelease(decode([data bytes], [data length], VTableResponse)));
            if (!skipIndicator) {
                [loadingIndicator destroy];
                loadingIndicator = nil; // kaboom
            }
            self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
            [self.tableView reloadData];
            [self loadIconsForVisibleRowsIfIdle];
            [errorLabel removeFromSuperview];
        } else {
            if (!skipIndicator) {
                [loadingIndicator destroy];
                loadingIndicator = nil; // btooom
            }
            alert(NSLocalizedString(@"Oops", @""), NSLocalizedString(@"ServerContactError", nil), VAPIHelperErrorNetwork);
            [getDelegate().window addSubview:errorLabel];
        }
    }];
    inInit = NO;
    firstAppear = NO;
}

#pragma mark - Sorting
- (void)setUpSortButtonWithDefaultsKey:(NSString *)defaultsKey {
    _sortDefaultsKey = [defaultsKey copy];
    NSString *savedOption = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];
    _sortOption = (savedOption != nil && VeterisListSortOption(savedOption) != nil) ? savedOption : @"name";
    self.sortButton.title = NSLocalizedStringWithDefaultValue(@"ListSortButton", nil, [NSBundle mainBundle], @"Sort", nil);
}

- (NSString *)sortedEndpoint:(NSString *)endpoint {
    NSArray *option = VeterisListSortOption(_sortOption);
    if (option == nil || [_sortOption isEqualToString:@"name"]) {
        return endpoint;
    }
    NSString *separator = ([endpoint rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
    return [NSString stringWithFormat:@"%@%@sort=%@&order=%@", endpoint, separator,
            [option objectAtIndex:VeterisListSortOptionMode], [option objectAtIndex:VeterisListSortOptionOrder]];
}

- (void)initializeSortedListing:(NSString *)endpoint {
    _sortBaseEndpoint = [endpoint copy];
    [self initialize:[self sortedEndpoint:endpoint]];
}

- (IBAction)showSortOptions:(id)sender {
    if (_sortSheet != nil) {
        [_sortSheet dismissWithClickedButtonIndex:_sortSheet.cancelButtonIndex animated:YES];
        return;
    }
    // Don't start another request while the current list is loading.
    if (loadingIndicator != nil || _sortBaseEndpoint == nil) {
        return;
    }
    NSString *sheetTitle = NSLocalizedStringWithDefaultValue(@"ListSortTitle", nil, [NSBundle mainBundle], @"Sort By", nil);
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:sheetTitle delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSArray *option in VeterisListSortOptions()) {
        NSString *title = VeterisListSortTitle(option);
        if ([[option objectAtIndex:VeterisListSortOptionID] isEqualToString:_sortOption]) {
            title = [NSString stringWithFormat:@"✓ %@", title];
        }
        [sheet addButtonWithTitle:title];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    _sortSheet = sheet;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet showFromBarButtonItem:self.sortButton animated:YES];
    } else {
        [sheet showInView:self.view.window];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet != _sortSheet || buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }
    NSArray *options = VeterisListSortOptions();
    if (buttonIndex >= (NSInteger)[options count]) {
        return;
    }
    NSString *identifier = [[options objectAtIndex:buttonIndex] objectAtIndex:VeterisListSortOptionID];
    if ([identifier isEqualToString:_sortOption]) {
        return;
    }
    _sortOption = identifier;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:identifier forKey:_sortDefaultsKey];
    [defaults synchronize];
    [self reloadSortedListing];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet == _sortSheet) {
        _sortSheet = nil;
    }
}

- (void)reloadSortedListing {
    _iconLoadGeneration++;
    [_loadingIconURLs removeAllObjects];
    applications = nil;
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.contentInset.top) animated:NO];
    [self initialize:[self sortedEndpoint:_sortBaseEndpoint]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSMutableSet *visibleApps = [NSMutableSet set];
    if ([self isViewLoaded]) {
        for (NSIndexPath *indexPath in [self.tableView indexPathsForVisibleRows]) {
            if (indexPath.row < [applications count]) {
                [visibleApps addObject:[applications objectAtIndex:indexPath.row]];
            }
        }
    }
    for (Application *app in applications) {
        if (![visibleApps containsObject:app]) {
            app.icon = nil;
        }
    }
}

- (void)reconfigure:(NSNotification *)notification {
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _viewIsVisible = NO;
    _iconLoadGeneration++;
    [_loadingIconURLs removeAllObjects];
    firstAppear = 3;
    if (loadingIndicator != nil) {
        [loadingIndicator destroy];
        loadingIndicator = nil;
    }
    if (errorLabel != nil) {
        [errorLabel removeFromSuperview];
        errorLabel = nil;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _viewIsVisible = YES;
    for (AppListTableViewCell *cell in self.tableView.visibleCells) {
        cell.getLabel.hidden = !VeterisShowGetLabels();
    }
    debugLog(@"conditions: %d %d %d %d", applications == nil, _endpoint != nil, loadingIndicator == nil, !inInit);
    if (applications == nil && _endpoint != nil && loadingIndicator == nil && !inInit && firstAppear == 3) {
        [self initialize:_endpoint];
    }
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
    [self loadIconsForVisibleRowsIfIdle];
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    return [applications count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 78;
}

#pragma mark - UITableViewDelegate
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"AppListTableViewCell";
    AppListTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];

    Application *app = [applications objectAtIndex:indexPath.row];

    cell.tag = indexPath.row;
    cell.getLabel.hidden = !VeterisShowGetLabels();
    cell.appNameLabel.text = app.name;
    cell.developerNameLabel.text = VeterisAppCellSubtitle(app.developer, app.bundleid, VeterisAppCellSubtitleAreaList);
    NSUInteger versionCount = app.versionCount;
    if (versionCount == 0 && [app.versions count] > 0) {
        versionCount = [app.versions count];
    }
    if (versionCount == 0) {
        cell.versionLabel.text = nil;
        cell.versionLabel.hidden = YES;
    } else {
        NSString *versionWord = (versionCount == 1) ? NSLocalizedString(@"VersionSingular", nil) : NSLocalizedString(@"Versions", nil);
        cell.versionLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)versionCount, versionWord];
        cell.versionLabel.hidden = NO;
    }
    [self configureIconForCell:cell app:app];
    return cell;
}

- (void)configureIconForCell:(AppListTableViewCell *)cell app:(Application *)app {
    if (cell == nil) {
        return;
    }
    UIImage *cachedIcon = app.icon;
    if (cachedIcon == nil) {
        cachedIcon = [VAPISS imageFromCache:app.iconurl];
        if (cachedIcon != nil) {
            if ([VeterisMemoryProfile activeValues].retainsDecodedIcons) {
                app.icon = cachedIcon;
            }
        }
    }
    cell.appUIImage.image = cachedIcon;
    cell.appUIImage.layer.masksToBounds = YES;
    cell.appUIImage.layer.cornerRadius = 13.0;
    if (cachedIcon != nil) {
        [cell.activityIndicator stopAnimating];
        cell.indicatorCounter = 1;
    } else {
        [cell.activityIndicator startAnimating];
        cell.indicatorCounter = 0;
    }
}

- (void)loadIconsForVisibleRowsIfIdle {
    if (!_viewIsVisible || self.tableView.dragging || self.tableView.decelerating) {
        return;
    }
    NSArray *visibleIndexPaths = [self.tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visibleIndexPaths) {
        if (indexPath.row < [applications count]) {
            Application *app = [applications objectAtIndex:indexPath.row];
            [self loadIconForApp:app atIndexPath:indexPath];
        }
    }
}

- (void)loadIconForApp:(Application *)app atIndexPath:(NSIndexPath *)indexPath {
    if (app == nil || app.icon != nil || app.nilIcon) {
        return;
    }
    NSString *iconKey = ([app.iconurl length] > 0) ? app.iconurl : app.fallback_iconurl;
    if ([iconKey length] == 0 || [_loadingIconURLs containsObject:iconKey]) {
        return;
    }

    UIImage *cachedIcon = [VAPISS imageFromCache:app.iconurl];
    if (cachedIcon != nil) {
        if ([VeterisMemoryProfile activeValues].retainsDecodedIcons) {
            app.icon = cachedIcon;
        }
        AppListTableViewCell *cell = (AppListTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        cell.appUIImage.image = cachedIcon;
        [cell.activityIndicator stopAnimating];
        cell.indicatorCounter = 1;
        return;
    }

    [_loadingIconURLs addObject:iconKey];
    NSUInteger generation = _iconLoadGeneration;
    [VAPISS getStatic:app.iconurl fallbackPath:app.fallback_iconurl completion:^(NSData *data, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [_loadingIconURLs removeObject:iconKey];
            if (!_viewIsVisible || generation != _iconLoadGeneration) {
                return;
            }
            if (error != nil) {
                debugLog(@"Oopsie :3 failed to load image for %@, bundleid: %@, app image url: %@", app.name, app.bundleid, app.iconurl);
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) {
                debugLog(@"Failed to load image for %@, bundleid: %@, app image url: %@", app.name, app.bundleid, app.iconurl);
                app.nilIcon = YES;
                return;
            }
            if ([VeterisMemoryProfile activeValues].retainsDecodedIcons) {
                app.icon = image;
            }
            if (indexPath.row >= [applications count] || [applications objectAtIndex:indexPath.row] != app) {
                return;
            }
            AppListTableViewCell *cell = (AppListTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            if (cell == nil) {
                return;
            }
            [self configureIconForCell:cell app:app];
        });
    }];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self loadIconsForVisibleRowsIfIdle];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self loadIconsForVisibleRowsIfIdle];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier rangeOfString:@"AppInfoPush"].location != NSNotFound) {

        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];

        AppListTableViewCell *cell = (AppListTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];

        AppInfo *appinfo = segue.destinationViewController;
        Application *app = [applications objectAtIndex:indexPath.row];
        [appinfo initialize:app.bundleid developer:app.developer name:app.name image:cell.appUIImage.image];
    }
}
@end
