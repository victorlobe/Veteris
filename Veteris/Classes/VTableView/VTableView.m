
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

@interface VTableView ()
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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
            app.icon = cachedIcon;
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
        app.icon = cachedIcon;
        AppListTableViewCell *cell = (AppListTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        [self configureIconForCell:cell app:app];
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
            app.icon = image;
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
