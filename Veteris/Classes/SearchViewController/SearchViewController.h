//
//  SearchViewController.h
//  Veteris
//
//  Created by electimon on 6/9/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SearchViewController : UIViewController<UISearchDisplayDelegate, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (weak, nonatomic) IBOutlet UITableView *historyTableView;
@property (weak, nonatomic) IBOutlet UISearchBar *searchBar;
@end
