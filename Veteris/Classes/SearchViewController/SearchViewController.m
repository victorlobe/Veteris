//
//  SearchViewController.m
//  Veteris
//
//  Created by Electimon on 12/22/18.
//  Copyright (c) 2022 Electimon. All rights reserved.
//
//

#import "SearchViewController.h"
#import "../AppInfo/AppInfo.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "../../SVProgressHUD/SVProgressHUD.h"
#import "../Convenience/Convenience.h"
#import "../ProtoStack.h"
#import "../Protos/Suggestion.h"
#import "SearchTableViewCell.h"

static NSString *const VeterisSearchHistoryDefaultsKey = @"SearchHistory";
static NSUInteger const VeterisSearchHistoryLimit = 10;

@implementation SearchViewController {
    NSMutableArray *searchResults;
    NSArray *results;
    NSMutableArray *_searchHistory;
    NSMutableSet *_loadingIconURLs;
    NSUInteger _iconLoadGeneration;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    searchResults = [NSMutableArray array];
    _searchHistory = [[self loadSearchHistory] mutableCopy];
    _loadingIconURLs = [NSMutableSet set];
    self.historyTableView.dataSource = self;
    self.historyTableView.delegate = self;
    self.historyTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self updateHistoryTableVisibility];
    self.definesPresentationContext = YES;
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString {
    return NO;
}

- (void)searchDisplayController:(UISearchDisplayController *)controller willShowSearchResultsTableView:(UITableView *)tableView {
    tableView.rowHeight = 77.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.historyTableView) {
        return [_searchHistory count];
    }
    return [searchResults count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.historyTableView) {
        static NSString *historyCellIdentifier = @"SearchHistoryCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:historyCellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:historyCellIdentifier];
        }
        cell.textLabel.text = [_searchHistory objectAtIndex:indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    static NSString *cellIdentifier = @"SearchTableViewCell";

    SearchTableViewCell *cell = (SearchTableViewCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[SearchTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    Suggestion *suggestion = [searchResults objectAtIndex:indexPath.row];
    cell.appNameLabel.text = suggestion.name;
    cell.developerNameLabel.text = [self subtitleForSuggestion:suggestion];
    NSString *versionCountText = [self versionCountTextForSuggestion:suggestion];
    cell.versionLabel.text = versionCountText;
    cell.versionLabel.hidden = ([versionCountText length] == 0);
    [self configureIconForCell:cell suggestion:suggestion];
    [self loadIconForSuggestion:suggestion atIndexPath:indexPath tableView:tableView];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.historyTableView) {
        return 44.0;
    }
    return 77.0;
}

- (NSString *)versionCountTextForSuggestion:(Suggestion *)suggestion {
    NSUInteger versionCount = suggestion.versionCount;
    if (versionCount == 0) {
        return nil;
    }
    NSString *versionWord = (versionCount == 1) ? NSLocalizedString(@"VersionSingular", nil) : NSLocalizedString(@"Versions", nil);
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)versionCount, versionWord];
}

- (NSString *)subtitleForSuggestion:(Suggestion *)suggestion {
    return VeterisAppCellSubtitle(suggestion.developer, suggestion.bundleid, VeterisAppCellSubtitleAreaSearch);
}

- (void)configureIconForCell:(SearchTableViewCell *)cell suggestion:(Suggestion *)suggestion {
    UIImage *cachedIcon = suggestion.icon;
    if (cachedIcon == nil) {
        cachedIcon = [VAPISS imageFromCache:suggestion.iconurl];
        if (cachedIcon != nil) {
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                suggestion.icon = cachedIcon;
            }
        }
    }
    cell.appUIImage.image = cachedIcon;
    if (cachedIcon != nil || suggestion.nilIcon) {
        [cell.activityIndicator stopAnimating];
    } else {
        [cell.activityIndicator startAnimating];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self updateHistoryTableVisibility];

    // to limit network activity, reload half a second after last key press.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchExecute) object:nil];
    if (searchText.length > 2)
        [self performSelector:@selector(searchExecute) withObject:nil afterDelay:0.3];
    else {
        if ([searchResults count] != 0) {
            [searchResults removeAllObjects];
            [_loadingIconURLs removeAllObjects];
            _iconLoadGeneration++;
            [self.searchDisplayController.searchResultsTableView reloadData];
        }
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if ([[self normalizedSearchText:searchBar.text] length] > 0) {
        [self addSearchHistoryEntry:searchBar.text];
    }
}

- (void)searchExecute {
    NSString *searchText = [self normalizedSearchText:self.searchDisplayController.searchBar.text];
    if ([searchText length] == 0) {
        return;
    }
    debugLog(@"Searching for %@", searchText);
    // begin new search
    [VAPISS getMessage:[NSString stringWithFormat:@"listing/suggest?query=%@", [searchText stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] completion:^(NSData *data, NSError *error){
        if (error == nil) {
            searchResults = (NSMutableArray *)(CFBridgingRelease(decode([data bytes], [data length], SuggestionsResponse)));
            dispatch_async(dispatch_get_main_queue(), ^{
                _iconLoadGeneration++;
                [_loadingIconURLs removeAllObjects];
                [self.searchDisplayController.searchResultsTableView reloadData];
            });
        }
    }];
}

- (void)loadIconForSuggestion:(Suggestion *)suggestion atIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView {
    if (suggestion == nil || suggestion.icon != nil || suggestion.nilIcon) {
        return;
    }
    NSString *iconKey = ([suggestion.iconurl length] > 0) ? suggestion.iconurl : suggestion.fallback_iconurl;
    if ([iconKey length] == 0 || [_loadingIconURLs containsObject:iconKey]) {
        return;
    }

    UIImage *cachedIcon = [VAPISS imageFromCache:suggestion.iconurl];
    if (cachedIcon != nil) {
        if ([VAPIHelper shouldRetainDecodedIcons]) {
            suggestion.icon = cachedIcon;
        }
        SearchTableViewCell *cell = (SearchTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
        cell.appUIImage.image = cachedIcon;
        [cell.activityIndicator stopAnimating];
        return;
    }

    [_loadingIconURLs addObject:iconKey];
    NSUInteger generation = _iconLoadGeneration;
    [VAPISS getStatic:suggestion.iconurl fallbackPath:suggestion.fallback_iconurl completion:^(NSData *data, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [_loadingIconURLs removeObject:iconKey];
            if (generation != _iconLoadGeneration) {
                return;
            }
            if (error != nil) {
                debugLog(@"Failed to load search icon for %@, bundleid: %@, app image url: %@", suggestion.name, suggestion.bundleid, suggestion.iconurl);
                return;
            }
            UIImage *image = [UIImage imageWithData:data];
            if (image == nil) {
                debugLog(@"Failed to decode search icon for %@, bundleid: %@, app image url: %@", suggestion.name, suggestion.bundleid, suggestion.iconurl);
                suggestion.nilIcon = YES;
                return;
            }
            if ([VAPIHelper shouldRetainDecodedIcons]) {
                suggestion.icon = image;
            }
            if (indexPath.row >= [searchResults count] || [searchResults objectAtIndex:indexPath.row] != suggestion) {
                return;
            }
            SearchTableViewCell *cell = (SearchTableViewCell *)[tableView cellForRowAtIndexPath:indexPath];
            if (cell == nil) {
                return;
            }
            cell.appUIImage.image = image;
            [cell.activityIndicator stopAnimating];
        });
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == self.historyTableView) {
        NSString *historySearch = [_searchHistory objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchExecute) object:nil];
        [self.searchDisplayController setActive:YES animated:NO];
        self.searchDisplayController.searchBar.text = historySearch;
        [self.searchDisplayController.searchBar becomeFirstResponder];
        [self addSearchHistoryEntry:historySearch];
        [self updateHistoryTableVisibility];
        [self searchExecute];
        return;
    }

    [self addSearchHistoryEntry:self.searchDisplayController.searchBar.text];
    [self performSegueWithIdentifier:@"SearchViewAppInfoPush" sender:indexPath];

    self.navigationController.navigationBarHidden = NO;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqual:@"SearchViewAppInfoPush"]) {
        NSIndexPath *indexPath = (NSIndexPath *)sender;
        AppInfo *appinfo = segue.destinationViewController;
        Suggestion *suggestion = [searchResults objectAtIndex:indexPath.row];
        [appinfo initialize:suggestion.bundleid];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [self.navigationController setNavigationBarHidden:YES];
}

- (NSArray *)loadSearchHistory {
    NSArray *history = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisSearchHistoryDefaultsKey];
    if ([history isKindOfClass:[NSArray class]]) {
        return history;
    }
    return [NSArray array];
}

- (NSString *)normalizedSearchText:(NSString *)searchText {
    return [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)addSearchHistoryEntry:(NSString *)searchText {
    NSString *normalizedSearchText = [self normalizedSearchText:searchText];
    if ([normalizedSearchText length] == 0) {
        return;
    }

    [_searchHistory removeObject:normalizedSearchText];
    [_searchHistory insertObject:normalizedSearchText atIndex:0];
    while ([_searchHistory count] > VeterisSearchHistoryLimit) {
        [_searchHistory removeLastObject];
    }

    [[NSUserDefaults standardUserDefaults] setObject:_searchHistory forKey:VeterisSearchHistoryDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.historyTableView reloadData];
}

- (void)updateHistoryTableVisibility {
    self.historyTableView.hidden = ([self.searchBar.text length] > 0);
}

@end
