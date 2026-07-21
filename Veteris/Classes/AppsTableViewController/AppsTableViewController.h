//
//  AppsTableViewController.h
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "../VTableView/VTableView.h"

@interface AppsTableViewController : VTableView

@property (copy, nonatomic) NSString *listingEndpoint;
@property (copy, nonatomic) NSString *listingTitleKey;
@property (nonatomic) BOOL showsRefreshButton;

@end
