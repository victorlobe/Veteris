//
//  UpdatesTableViewController.m
//  Veteris
//
//  Created by Victor on 12.10.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "UpdatesTableViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "VeterisUpdatesManager.h"
#import "../../AppDelegate.h"
#import "../AppInfo/AppInfo.h"
#import "../Convenience/Convenience.h"
#import "../Protos/Application.h"
#import "../AppListTableViewCell/AppListTableViewCell.h"
#import "../VAPIHelper/VAPIHelper.h"

typedef NS_ENUM(NSInteger, UpdatesSection) {
    UpdatesSectionAvailable = 0,
    UpdatesSectionMuted = 1,
};

static NSString *UpdatesString(NSString *key, NSString *english) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:english table:nil];
}

@implementation UpdatesTableViewController {
    NSArray *_availableUpdates;
    NSArray *_mutedUpdates;
    NSMutableSet *_loadingIconURLs;
    NSUInteger _iconLoadGeneration;
    BOOL _viewIsVisible;
    BOOL _installingAll;
    UILabel *_emptyLabel;
    Application *_actionSheetUpdate;
    NSInteger _updateButtonIndex;
    NSInteger _appInfoButtonIndex;
    NSInteger _muteButtonIndex;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _availableUpdates = [NSArray array];
    _mutedUpdates = [NSArray array];
    _loadingIconURLs = [NSMutableSet set];
    self.navigationItem.title = UpdatesString(@"Updates", @"Updates");
    self.updateAllButton.title = UpdatesString(@"UpdateAll", @"Update All");
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    _emptyLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.shadowColor = [UIColor whiteColor];
    _emptyLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    _emptyLabel.font = [UIFont boldSystemFontOfSize:15.0];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.tableView.backgroundView = _emptyLabel;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatesDidChange:) name:VeterisUpdatesDidChangeNotification object:nil];
    [self reloadUpdates];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _viewIsVisible = YES;
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
    VeterisUpdatesManager *manager = [VeterisUpdatesManager sharedManager];
    if ([manager checkState] == VeterisUpdatesCheckStateFailed) {
        [manager checkForUpdates];
    }
    [self reloadUpdates];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _viewIsVisible = NO;
    _iconLoadGeneration++;
    [_loadingIconURLs removeAllObjects];
}

- (void)updatesDidChange:(NSNotification *)notification {
    [self reloadUpdates];
}



- (void)setBarButtonItem:(UIBarButtonItem *)item enabled:(BOOL)enabled {
    item.enabled = enabled;
    if ([item.customView isKindOfClass:[UIControl class]]) {
        ((UIControl *)item.customView).enabled = enabled;
    }
}

- (NSString *)emptyText {
    switch ([[VeterisUpdatesManager sharedManager] checkState]) {
        case VeterisUpdatesCheckStateLoaded:
            return UpdatesString(@"NoUpdates", @"All apps are up to date.");
        case VeterisUpdatesCheckStateFailed:
            return UpdatesString(@"UpdatesCheckFailed", @"Could not check for updates.");
        default:
            return UpdatesString(@"CheckingForUpdates", @"Checking for Updates...");
    }
}

- (void)reloadUpdates {
    VeterisUpdatesManager *manager = [VeterisUpdatesManager sharedManager];
    _availableUpdates = [manager availableUpdates];
    _mutedUpdates = [manager mutedUpdates];
    BOOL hasRows = ([_availableUpdates count] + [_mutedUpdates count] > 0);
    _emptyLabel.text = [self emptyText];
    _emptyLabel.hidden = hasRows;
    self.tableView.separatorStyle = hasRows ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
    [self setBarButtonItem:self.updateAllButton enabled:(!_installingAll && [_availableUpdates count] > 0)];
    [self.tableView reloadData];
    [self loadIconsForVisibleRowsIfIdle];
}

- (NSArray *)updatesInSection:(NSInteger)section {
    return (section == UpdatesSectionMuted) ? _mutedUpdates : _availableUpdates;
}

- (Application *)updateAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *updates = [self updatesInSection:indexPath.section];
    return (indexPath.row < [updates count]) ? [updates objectAtIndex:indexPath.row] : nil;
}

- (NSString *)versionTextForUpdate:(Application *)update {
    NSString *installedVersion = [[VeterisUpdatesManager sharedManager] installedVersionForUpdate:update];
    if ([installedVersion length] == 0) {
        return [NSString stringWithFormat:NSLocalizedString(@"VersionFormat", nil), update.version];
    }
    return [NSString stringWithFormat:@"Version %1$@ ➔ %2$@", installedVersion, update.version];
}

#pragma mark - Actions

- (IBAction)updateAllPressed:(id)sender {
    if (_installingAll || [_availableUpdates count] == 0) {
        return;
    }
    NSString *message = [NSString stringWithFormat:UpdatesString(@"UpdateAllMessage", @"Download and install all available updates (%lu)?"), (unsigned long)[_availableUpdates count]];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:UpdatesString(@"UpdateAll", @"Update All")
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                              otherButtonTitles:UpdatesString(@"UpdateAll", @"Update All"), nil];
    [alertView show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex || _installingAll) {
        return;
    }
    _installingAll = YES;
    [self reloadUpdates];
    [[VeterisUpdatesManager sharedManager] installUpdates:_availableUpdates completion:^(NSUInteger failedCount) {
        _installingAll = NO;
        [self reloadUpdates];
        if (failedCount > 0) {
            alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"ServerContactError", nil), VAPIHelperErrorNetwork);
        }
    }];
}

- (void)installUpdate:(Application *)update {
    [[VeterisUpdatesManager sharedManager] installUpdates:[NSArray arrayWithObject:update] completion:^(NSUInteger failedCount) {
        if (failedCount > 0) {
            alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"ServerContactError", nil), VAPIHelperErrorNetwork);
        }
    }];
}

- (void)showAppInfoForUpdate:(Application *)update {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:[NSBundle mainBundle]];
    AppInfo *appinfo = [storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
    [appinfo view];
    [appinfo initialize:update.bundleid developer:update.developer name:update.name image:update.icon ?: [VAPISS imageFromCache:update.iconurl]];
    [self.navigationController pushViewController:appinfo animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    Application *update = _actionSheetUpdate;
    _actionSheetUpdate = nil;
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    if (update == nil || buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0) {
        return;
    }
    if (buttonIndex == _updateButtonIndex) {
        [self installUpdate:update];
    } else if (buttonIndex == _appInfoButtonIndex) {
        [self showAppInfoForUpdate:update];
    } else if (buttonIndex == _muteButtonIndex) {
        VeterisUpdatesManager *manager = [VeterisUpdatesManager sharedManager];
        [manager setUpdate:update muted:![manager isUpdateMuted:update]];
    }
}

- (void)actionSheetCancel:(UIActionSheet *)actionSheet {
    _actionSheetUpdate = nil;
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

#pragma mark - Icons

- (void)configureIconForCell:(AppListTableViewCell *)cell app:(Application *)application {
    UIImage *cachedIcon = application.icon;
    if (cachedIcon == nil) {
        cachedIcon = [VAPISS imageFromCache:application.iconurl];
        if (cachedIcon != nil && [VeterisMemoryProfile activeValues].retainsDecodedIcons) {
            application.icon = cachedIcon;
        }
    }
    cell.appUIImage.image = cachedIcon;
    cell.appUIImage.layer.masksToBounds = YES;
    cell.appUIImage.layer.cornerRadius = 13.0;
    if (cachedIcon != nil || application.nilIcon) {
        [cell.activityIndicator stopAnimating];
    } else {
        [cell.activityIndicator startAnimating];
    }
}

- (void)loadIconsForVisibleRowsIfIdle {
    if (!_viewIsVisible || self.tableView.dragging || self.tableView.decelerating) {
        return;
    }
    for (NSIndexPath *indexPath in [self.tableView indexPathsForVisibleRows]) {
        Application *update = [self updateAtIndexPath:indexPath];
        if (update != nil) {
            [self loadIconForApp:update atIndexPath:indexPath];
        }
    }
}

- (void)loadIconForApp:(Application *)application atIndexPath:(NSIndexPath *)indexPath {
    if (application == nil || application.icon != nil || application.nilIcon) {
        return;
    }
    NSString *iconKey = ([application.iconurl length] > 0) ? application.iconurl : application.fallback_iconurl;
    if ([iconKey length] == 0 || [_loadingIconURLs containsObject:iconKey]) {
        return;
    }

    [_loadingIconURLs addObject:iconKey];
    NSUInteger generation = _iconLoadGeneration;
    [VAPISS getStatic:application.iconurl fallbackPath:application.fallback_iconurl completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_loadingIconURLs removeObject:iconKey];
            if (!_viewIsVisible || generation != _iconLoadGeneration || error != nil) {
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) {
                application.nilIcon = YES;
                return;
            }
            if ([VeterisMemoryProfile activeValues].retainsDecodedIcons) {
                application.icon = image;
            }
            if ([self updateAtIndexPath:indexPath] != application) {
                return;
            }
            AppListTableViewCell *cell = (AppListTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            cell.appUIImage.image = image;
            [cell.activityIndicator stopAnimating];
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

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[self updatesInSection:section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([_mutedUpdates count] == 0 || [[self updatesInSection:section] count] == 0) {
        return nil;
    }
    if (section == UpdatesSectionMuted) {
        return UpdatesString(@"MutedUpdates", @"Muted");
    }
    return UpdatesString(@"AvailableUpdates", @"Available");
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 78.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AppListTableViewCell";
    AppListTableViewCell *cell = (AppListTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    Application *update = [self updateAtIndexPath:indexPath];
    cell.appNameLabel.text = update.name;
    cell.developerNameLabel.text = VeterisAppCellSubtitle(update.developer, update.bundleid, VeterisAppCellSubtitleAreaList);
    cell.versionLabel.text = [self versionTextForUpdate:update];
    cell.versionLabel.hidden = NO;
    cell.getLabel.hidden = YES;

    CGFloat alpha = (indexPath.section == UpdatesSectionMuted) ? 0.5 : 1.0;
    cell.appUIImage.alpha = alpha;
    cell.appNameLabel.alpha = alpha;
    [self configureIconForCell:cell app:update];
    [self loadIconForApp:update atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Application *update = [self updateAtIndexPath:indexPath];
    if (update == nil) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    BOOL muted = [[VeterisUpdatesManager sharedManager] isUpdateMuted:update];
    _actionSheetUpdate = update;
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:update.name delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    _updateButtonIndex = [actionSheet addButtonWithTitle:UpdatesString(@"UpdateApp", @"Update")];
    _appInfoButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"QueueShowAppInfo", nil, [NSBundle mainBundle], @"Show App Info", nil)];
    _muteButtonIndex = [actionSheet addButtonWithTitle:muted ? UpdatesString(@"UnmuteUpdates", @"Unmute Updates") : UpdatesString(@"MuteUpdates", @"Mute Updates")];
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [actionSheet showInView:self.view.window ?: self.view];
}

@end
