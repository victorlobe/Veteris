//
//  CategoriesTableViewController.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "CategoriesTableViewController.h"
#import "../CategorySelectedViewController/CategorySelectedViewController.h"
#import "CategoriesTableViewCell.h"
#import "../VAPIHelper/VAPIHelper.h"
#import "InAppSettingsKit/Models/IASKSettingsReader.h"
#import <SVProgressHUD/SVProgressHUD.h>
#import "../ProtoStack.h"
#import "../LoadingIndicatorView/LoadingIndicatorView.h"

@implementation CategoriesTableViewController {
    NSMutableArray *categories;
    LoadingIndicatorView *loadingIndicator;
    UILabel *errorLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.title = NSLocalizedString(@"Categories", @"Categories");
    self.navigationItem.title = NSLocalizedString(@"Categories", @"Categories");
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(reconfigure:) name:kPleaseReloadThemes object:nil];
    [self reconfigure:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (categories == nil) {
        [self initialize];
    }
}

- (void)reconfigure:(NSNotification *)notification {
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
}

- (NSString *)localizedNameForCategory:(CategoryProt *)category {
    NSString *tmpString = [category.name stringByReplacingOccurrencesOfString:@"Healthcare & Fitness" withString:@"Health"];
    NSString *key = [NSString stringWithFormat:@"Category-%@", [tmpString stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    NSString *translatedString = NSLocalizedString(key, nil);
    if (translatedString != nil && ![translatedString isEqualToString:key]) {
        return translatedString;
    }
    return category.name;
}

- (BOOL)isUnknownCategory:(CategoryProt *)category {
    return [category.id isEqualToString:@"unknown"] || [category.name caseInsensitiveCompare:@"Unknown"] == NSOrderedSame;
}

- (void)sortCategories {
    NSArray *sortedCategories = [categories sortedArrayUsingComparator:^NSComparisonResult(CategoryProt *left, CategoryProt *right) {
        BOOL leftUnknown = [self isUnknownCategory:left];
        BOOL rightUnknown = [self isUnknownCategory:right];
        if (leftUnknown && !rightUnknown) {
            return NSOrderedDescending;
        }
        if (!leftUnknown && rightUnknown) {
            return NSOrderedAscending;
        }
        return [[self localizedNameForCategory:left] localizedCaseInsensitiveCompare:[self localizedNameForCategory:right]];
    }];
    categories = [NSMutableArray arrayWithArray:sortedCategories];
}

- (void)initialize {
    loadingIndicator = [LoadingIndicatorView attachToView:self.view];
    if (errorLabel == nil) {
        errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
        errorLabel.text = NSLocalizedString(@"FailedToLoadContent", nil);
        [errorLabel sizeToFit];
        errorLabel.textColor = [UIColor grayColor];
        errorLabel.backgroundColor = [UIColor clearColor];
        errorLabel.textAlignment = NSTextAlignmentCenter;
        errorLabel.center = CGPointMake(self.tableView.center.x, getDelegate().window.center.y);
    }
    [VAPISS getMessage:@"listing/categories" completion:^(NSData *data, NSError *error){
        [loadingIndicator destroy];
        loadingIndicator = nil;
        if (error == nil) {
            categories = (NSMutableArray *)(CFBridgingRelease(decode([data bytes], [data length], CategoriesResponse)));
            [self sortCategories];
            [errorLabel removeFromSuperview];
            [self.tableView reloadData];
        } else {
            alert(NSLocalizedString(@"Oops", nil), NSLocalizedString(@"ServerContactError", nil), 1);
            [getDelegate().window addSubview:errorLabel];
        }
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (loadingIndicator != nil) {
        [loadingIndicator destroy];
        loadingIndicator = nil;
    }
    if (errorLabel != nil) {
        [errorLabel removeFromSuperview];
    }
}

#pragma mark - Table view data source
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return [categories count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CategoriesTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CategoriesTableViewCell"];
    CategoryProt *category = [categories objectAtIndex:indexPath.row];
    cell.categoryLabel.text = [self localizedNameForCategory:category];
    return cell;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqual:@"CategorySelectedPush"]) {
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];

        CategorySelectedViewController *categorySelected = segue.destinationViewController;
        CategoryProt *category = [categories objectAtIndex:indexPath.row];
        CategoriesTableViewCell *cell = (CategoriesTableViewCell*)[self.tableView cellForRowAtIndexPath:indexPath];
        [categorySelected setCategoryID:category.id];
        [categorySelected setCategoryName:cell.categoryLabel.text];
    }
}
@end
