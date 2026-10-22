//
//  UpdatesTableViewController.h
//  Veteris
//
//  Created by Victor on 12.10.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UpdatesTableViewController : UITableViewController <UIActionSheetDelegate, UIAlertViewDelegate>
@property (weak, nonatomic) IBOutlet UIBarButtonItem *updateAllButton;
- (IBAction)updateAllPressed:(id)sender;
@end
