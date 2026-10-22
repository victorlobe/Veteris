#import "QueueTableViewController.h"
#import "../../AppDelegate.h"
#import "../YZQueue/YZQueueManager.h"
#import "../YZQueue/YZQueueState.h"
#import "../AppInfo/AppInfo.h"
#define NSArrayAtIndex(arr, idx) ((NSArray *)([arr objectAtIndex:(idx)]))

@implementation QueueTableViewController {
    YZQueueState *_queueState;
    UIView *_noItemsView;
    YZQueueRep *_actionSheetRep;
    NSInteger _appInfoButtonIndex;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.title = NSLocalizedString(@"Queue", @"Queue");
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleNotification:) name:@"YZQueueRepStateChange" object:nil];
    CGRect frame = CGRectMake(self.navigationController.view.bounds.origin.x, self.navigationController.view.bounds.origin.y, self.navigationController.view.bounds.size.width, self.navigationController.view.bounds.size.height - self.navigationController.navigationBar.frame.size.height*2);
    _noItemsView = [[UIView alloc] initWithFrame:frame];
    _noItemsView.backgroundColor = [UIColor whiteColor];
    UILabel *noItemsLabel = [[UILabel alloc] initWithFrame:_noItemsView.bounds];
    noItemsLabel.text = NSLocalizedString(@"NoItemsInQueue", @"No items in queue");
    noItemsLabel.textAlignment = NSTextAlignmentCenter;
    noItemsLabel.alpha = 0.7;
    [noItemsLabel sizeToFit];
    [noItemsLabel setCenter:CGPointMake(CGRectGetMidX(_noItemsView.bounds), CGRectGetMidY(_noItemsView.bounds))];
    [_noItemsView addSubview:noItemsLabel];
    _queueState = [[YZQueueState alloc] init];
    [self reloadData];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [getDelegate().themeManager applyThemeToNavigationBar:self.navigationController.navigationBar];
}

- (void)handleNotification:(NSNotification *)notification {
    [self reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
     if (self.tableView.backgroundView == _noItemsView) {
        return 0;
    }
    return 7;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 78;
}

- (void)reloadData {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_queueState refreshReps];
        if ([_queueState total] == 0) {
            self.tableView.backgroundView = _noItemsView;
            self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
            [self.tableView reloadData];
            return;
        }
        self.tableView.backgroundView = nil;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        [self.tableView reloadData];
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_queueState totalWithState:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"QueueTableCell";
    QueueTableViewCell __block *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        CGRect frame = CGRectMake(0, 0, self.view.frame.size.width, 78.0);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        cell = [[QueueTableViewCell alloc] initWithFrame:frame reuseIdentifier:cellIdentifier];
#pragma clang diagnostic pop
    }
    YZQueueRep *rep = [_queueState repForSection:indexPath.section atIndex:indexPath.row];
    switch (indexPath.section) {
        case YZRepStateInstalled:
            [cell.appActivityIndicator stopAnimating];
            break;
        case YZRepStateInstalling:
            [cell.appActivityIndicator startAnimating];
            break;
        case YZRepStateDownloaded:
            [cell.appActivityIndicator stopAnimating];
            break;
        case YZRepStateDownloading: {
            [cell.appActivityIndicator stopAnimating];
            // tell the queue manager we'd like to attach a progress block/observer
            cell.appProgressView.hidden = NO;
            [_queueState attachProgressBlock:^(NSUInteger current, NSUInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([cell rep] == rep) {
                        [cell updateDownloadProgressWithCurrent:current total:total];
                    }
                });
            } toRep:rep];
            break;
        }
		
        case YZRepStateQueued:
            [cell.appActivityIndicator stopAnimating];
            break;
        case YZRepStateFailed:
            [cell.appActivityIndicator stopAnimating];
            break;
        case YZRepStatePaused:
            [cell.appActivityIndicator stopAnimating];
            break;
    }
    if (rep.state != YZRepStateDownloading) {
        cell.appProgressView.hidden = YES;
        [cell.appDownloadActivityIndicator stopAnimating];
        cell.appProgressLabel.hidden = YES;
        cell.appSpeedLabel.hidden = YES;
    }
    [cell updateFromRep:rep];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"Installed", @"Installed");
        case 1:
            return NSLocalizedString(@"Installing", @"Installing");
        case 2:
            return NSLocalizedString(@"Downloaded", @"Downloaded");
        case 3:
            return NSLocalizedString(@"Downloading", @"Downloading");
        case 4:
            return NSLocalizedString(@"Queued", @"Queued");
        case 5:
            return NSLocalizedString(@"Failed", @"Failed");
        case 6:
            return NSLocalizedString(@"Paused", @"Paused");
        default:
            return nil;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UIActionSheet *actionSheet;
    if (indexPath.section == YZRepStateDownloading) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Options", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:NSLocalizedString(@"RemoveFromQueue", @"Remove from Queue") otherButtonTitles:NSLocalizedString(@"Pause", nil), nil];
    } else if (indexPath.section == YZRepStateFailed) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Options", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:NSLocalizedString(@"RemoveFromQueue", @"Remove from Queue") otherButtonTitles:NSLocalizedString(@"Retry", nil), NSLocalizedString(@"ShowErrorDetails", @"Show error details"), nil];
    } else if (indexPath.section == YZRepStatePaused) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Options", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:NSLocalizedString(@"RemoveFromQueue", @"Remove from Queue") otherButtonTitles:NSLocalizedString(@"Resume", nil), nil];
    } else if (indexPath.section == YZRepStateInstalled) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Options", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:NSLocalizedString(@"RemoveFromQueue", @"Remove from Queue") otherButtonTitles:NSLocalizedString(@"Launch", nil), nil];
    } else {
        actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Options", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:NSLocalizedString(@"RemoveFromQueue", @"Remove from Queue") otherButtonTitles:nil, nil];
    }
    // Only catalog entries can open the App Info screen.
    _actionSheetRep = [_queueState repForSection:indexPath.section atIndex:indexPath.row];
    _appInfoButtonIndex = -1;
    if ([_actionSheetRep sourceURL] != nil && [[_actionSheetRep bundleID] length] > 0) {
        _appInfoButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"QueueShowAppInfo", nil, [NSBundle mainBundle], @"Show App Info", nil)];
    }
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Close", nil)];
    [actionSheet showInView:self.view.window];
}

- (void)showAppInfoForRep:(YZQueueRep *)rep {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard" bundle:[NSBundle mainBundle]];
    AppInfo *appinfo = [storyboard instantiateViewControllerWithIdentifier:@"AppInfoViewController"];
    [appinfo view];
    [appinfo initialize:[rep bundleID] developer:[rep developer] name:[rep name] image:[rep icon]];
    [self.navigationController pushViewController:appinfo animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    debugLog(@"Button index: %ld", (long)buttonIndex);

    if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex == -1) {
        debugLog(@"Action sheet dismissed or cancel clicked");
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }

    NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];

    if (buttonIndex == _appInfoButtonIndex) {
        YZQueueRep *rep = _actionSheetRep;
        _actionSheetRep = nil;
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self showAppInfoForRep:rep];
        return;
    }

    if (indexPath.section == YZRepStateFailed && buttonIndex == 2) {
        YZQueueRep *rep = [_queueState repForSection:indexPath.section atIndex:indexPath.row];
        NSString *message = rep.errorDetails;
        if ([message length] == 0) {
            message = NSLocalizedString(@"NoErrorDetailsAvailable", @"No diagnostic details were recorded.");
        }
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ErrorDetails", @"Error details") message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil];
        [alert show];
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
        return;
    }

    QueueTableViewCell *cell = (QueueTableViewCell *)[self.tableView cellForRowAtIndexPath:[self.tableView indexPathForSelectedRow]];
    YZQueueRep *rep = [cell rep];
    bool isDownloading = rep.state == YZRepStateDownloading;
    bool isFailed = rep.state == YZRepStateFailed;
    bool isPaused = rep.state == YZRepStatePaused;
    if (buttonIndex == 0) {
        if (rep.state == YZRepStateInstalling) {
            alert(@"Error", @"The application is already installing.", VAPIHelperErrorUnknown);
        } else {
            bool success = [_queueState markRepAsCancelled:rep];
        }
    } else if (buttonIndex == 1) {
        if (isDownloading) {
            [_queueState pauseRep:rep];
        } else if (isFailed || isPaused) {
            [_queueState retryRep:rep];
        } else {
            if (indexPath.section == YZRepStateInstalled) {
                [_queueState launchApp:rep.bundleID];
            } else {
                alert(@"Error", @"You can only retry failed or paused applications.", VAPIHelperErrorUnknown);
            }
        }
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)actionSheetCancel:(UIActionSheet *)actionSheet {
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}
@end
