//
//  AppsTableViewController.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "AppsTableViewController.h"
#import "../AppListTableViewCell/AppListTableViewCell.h"
#include <stdlib.h>

static NSString *const VeterisDefaultAppsListingEndpoint = @"listing/all";
static NSString *const VeterisDefaultAppsTitleKey = @"AllApps";
static NSString *const VeterisAllAppsSortDefaultsKey = @"VeterisAllAppsSort";
static NSString *const VeterisDeveloperListSortDefaultsKey = @"VeterisDeveloperListSort";

@interface AppsTableViewController ()
- (NSString *)currentListingEndpoint;
- (void)refreshListing;
@end

@implementation AppsTableViewController
- (void)viewDidLoad {
    [super viewDidLoad];

    if ([self.listingTitle length] > 0) {
        self.navigationItem.title = self.listingTitle;
    } else {
        NSString *titleKey = self.listingTitleKey;
        if ([titleKey length] == 0) {
            titleKey = VeterisDefaultAppsTitleKey;
        }

        self.navigationItem.title = NSLocalizedString(titleKey, titleKey);
    }

    if (self.showsRefreshButton) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Shuffle" style:UIBarButtonItemStylePlain target:self action:@selector(refreshListing)];
        [self initialize:[self currentListingEndpoint]];
        return;
    }

    NSString *endpoint = [self currentListingEndpoint];
    if ([endpoint hasPrefix:@"listing/top"]) {
        self.navigationItem.rightBarButtonItem = nil;
        [self initialize:endpoint];
        return;
    }

    BOOL isDeveloperListing = [endpoint hasPrefix:@"listing/developer/"];
    [self setUpSortButtonWithDefaultsKey:(isDeveloperListing ? VeterisDeveloperListSortDefaultsKey : VeterisAllAppsSortDefaultsKey)];
    [self initializeSortedListing:endpoint];
}

- (NSString *)currentListingEndpoint {
    NSString *endpoint = self.listingEndpoint;
    if ([endpoint length] == 0) {
        endpoint = VeterisDefaultAppsListingEndpoint;
    }

    if (!self.showsRefreshButton) {
        return endpoint;
    }

    unsigned long long timestamp = (unsigned long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    NSString *separator = ([endpoint rangeOfString:@"?"].location == NSNotFound) ? @"?" : @"&";
    return [NSString stringWithFormat:@"%@%@refresh=%llu-%u", endpoint, separator, timestamp, arc4random()];
}

- (void)refreshListing {
    [self initialize:[self currentListingEndpoint]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AppListTableViewCell *cell = (AppListTableViewCell *)[super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([self.listingEndpoint hasPrefix:@"listing/top"]) {
        [cell setRankingPosition:indexPath.row + 1];
    } else {
        [cell setRankingPosition:0];
    }
    return cell;
}
@end
