#import <UIKit/UIKit.h>
#import "../../AppDelegate.h"
#import "../Protos/Application.h"

@interface VTableView : UITableViewController<UIAlertViewDelegate>
- (void)initialize:(NSString *)endpoint;
- (void)initialize:(NSString *)endpoint skipIndicator:(BOOL)skipIndicator;
- (void)setUpSortButtonWithDefaultsKey:(NSString *)defaultsKey;
- (void)initializeSortedListing:(NSString *)endpoint;
- (IBAction)showSortOptions:(id)sender;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *sortButton;
@property (strong, nonatomic) NSArray *applications;
@end
