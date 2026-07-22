//
//  FavoritesTableViewController.m
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "FavoritesTableViewController.h"
#import "VeterisFavoritesManager.h"
#import "../../AppDelegate.h"
#import "../AppInfo/AppInfo.h"
#import "../Convenience/Convenience.h"
#import "../Protos/Application.h"
#import "../SearchViewController/SearchTableViewCell.h"
#import "../VAPIHelper/VAPIHelper.h"

@implementation FavoritesTableViewController {
    NSMutableArray *applications;
    NSMutableSet *_loadingIconURLs;
    NSUInteger _iconLoadGeneration;
    BOOL _viewIsVisible;
    UILabel *_emptyLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    applications = [NSMutableArray array];
    _loadingIconURLs = [NSMutableSet set];
    self.navigationItem.title = NSLocalizedString(@"Favorites", nil);
    self.tableView.rowHeight = 77.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor colorWithRed:0.9404956698 green:0.9404675364 blue:0.9404835105 alpha:1.0];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    _emptyLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.text = NSLocalizedString(@"NoFavorites", nil);
    _emptyLabel.textColor = [UIColor grayColor];
    _emptyLabel.shadowColor = [UIColor whiteColor];
    _emptyLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    _emptyLabel.font = [UIFont boldSystemFontOfSize:15.0];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.tableView.backgroundView = _emptyLabel;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(favoritesDidChange:) name:VeterisFavoritesDidChangeNotification object:nil];
    [self reloadFavorites];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _viewIsVisible = YES;
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
    [self reloadFavorites];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _viewIsVisible = NO;
    _iconLoadGeneration++;
    [_loadingIconURLs removeAllObjects];
}

- (void)favoritesDidChange:(NSNotification *)notification {
    [self reloadFavorites];
}

- (void)reloadFavorites {
    applications = [[VeterisFavoritesManager favoriteApplications] mutableCopy];
    _emptyLabel.hidden = ([applications count] > 0);
    self.tableView.separatorStyle = ([applications count] > 0) ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
    [self.tableView reloadData];
    [self loadIconsForVisibleRowsIfIdle];
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

- (void)configureIconForCell:(SearchTableViewCell *)cell app:(Application *)application {
    UIImage *cachedIcon = application.icon;
    if (cachedIcon == nil) {
        cachedIcon = [VAPISS imageFromCache:application.iconurl];
        if (cachedIcon != nil) {
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                application.icon = cachedIcon;
            }
        }
    }
    cell.appUIImage.image = cachedIcon;
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
        if (indexPath.row < [applications count]) {
            [self loadIconForApp:[applications objectAtIndex:indexPath.row] atIndexPath:indexPath];
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

    UIImage *cachedIcon = [VAPISS imageFromCache:application.iconurl];
    if (cachedIcon != nil) {
        if ([VAPIHelper shouldRetainDecodedIcons]) {
            application.icon = cachedIcon;
        }
        SearchTableViewCell *cell = (SearchTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        cell.appUIImage.image = cachedIcon;
        [cell.activityIndicator stopAnimating];
        return;
    }

    [_loadingIconURLs addObject:iconKey];
    NSUInteger generation = _iconLoadGeneration;
    [VAPISS getStatic:application.iconurl fallbackPath:application.fallback_iconurl completion:^(NSData *data, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_loadingIconURLs removeObject:iconKey];
            if (!_viewIsVisible || generation != _iconLoadGeneration) {
                return;
            }
            if (error != nil) {
                debugLog(@"Failed to load favorite icon for %@, bundleid: %@, app image url: %@", application.name, application.bundleid, application.iconurl);
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) {
                debugLog(@"Failed to decode favorite icon for %@, bundleid: %@, app image url: %@", application.name, application.bundleid, application.iconurl);
                application.nilIcon = YES;
                return;
            }
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                application.icon = image;
            }
            if (indexPath.row >= [applications count] || [applications objectAtIndex:indexPath.row] != application) {
                return;
            }
            SearchTableViewCell *cell = (SearchTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
            if (cell == nil) {
                return;
            }
            cell.appUIImage.image = image;
            [cell.activityIndicator stopAnimating];
        });
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [applications count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 77.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"FavoritesTableViewCell";
    SearchTableViewCell *cell = (SearchTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[SearchTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    Application *application = [applications objectAtIndex:indexPath.row];
    cell.appNameLabel.text = application.name;
    cell.developerNameLabel.text = VeterisAppCellSubtitle(application.developer, application.bundleid, VeterisAppCellSubtitleAreaList);
    NSString *versionCountText = [self versionCountTextForApplication:application];
    cell.versionLabel.text = versionCountText;
    cell.versionLabel.hidden = ([versionCountText length] == 0);
    [self configureIconForCell:cell app:application];
    [self loadIconForApp:application atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= [applications count]) {
        return;
    }

    Application *application = [applications objectAtIndex:indexPath.row];
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:[NSBundle mainBundle]];
    AppInfo *appinfo = [storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
    [appinfo view];
    SearchTableViewCell *cell = (SearchTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
    [appinfo initialize:application.bundleid developer:application.developer name:application.name image:cell.appUIImage.image];
    [self.navigationController pushViewController:appinfo animated:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self loadIconsForVisibleRowsIfIdle];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self loadIconsForVisibleRowsIfIdle];
}

@end
