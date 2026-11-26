#import <UIKit/UIKit.h>

void VeterisShowAppInfo(UIViewController *source, UIViewController *appInfo);

@interface VeterisAppInfoSheetController : UINavigationController
@property (nonatomic, copy) void (^closeHandler)(void);
- (void)close;
@end

@interface VeterisAppInfoSegue : UIStoryboardSegue
@end
