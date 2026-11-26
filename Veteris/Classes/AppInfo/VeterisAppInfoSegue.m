#import "VeterisAppInfoSegue.h"
#import "AppInfo.h"

static BOOL VeterisViewIsBehindView(UIView *view, UIView *frontView) {
    if (view == nil || frontView == nil || [view isDescendantOfView:frontView]) {
        return NO;
    }
    if ([frontView isDescendantOfView:view]) {
        return YES;
    }

    NSMutableArray *frontChain = [NSMutableArray array];
    for (UIView *ancestor = frontView; ancestor != nil; ancestor = ancestor.superview) {
        [frontChain addObject:ancestor];
    }

    UIView *viewBranch = view;
    for (UIView *ancestor = view.superview; ancestor != nil; ancestor = ancestor.superview) {
        NSUInteger index = [frontChain indexOfObjectIdenticalTo:ancestor];
        if (index != NSNotFound && index > 0) {
            UIView *frontBranch = [frontChain objectAtIndex:index - 1];
            NSArray *siblings = ancestor.subviews;
            NSUInteger viewIndex = [siblings indexOfObjectIdenticalTo:viewBranch];
            NSUInteger frontIndex = [siblings indexOfObjectIdenticalTo:frontBranch];
            return viewIndex != NSNotFound && frontIndex != NSNotFound && viewIndex < frontIndex;
        }
        viewBranch = ancestor;
    }
    return NO;
}

@interface VeterisAppInfoSheetController () <UIGestureRecognizerDelegate>
@end

@implementation VeterisAppInfoSheetController {
    UITapGestureRecognizer *outsideTapRecognizer;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIWindow *window = self.view.window;
    if (outsideTapRecognizer == nil && window != nil) {
        outsideTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleOutsideTap:)];
        outsideTapRecognizer.cancelsTouchesInView = NO;
        outsideTapRecognizer.delegate = self;
        [window addGestureRecognizer:outsideTapRecognizer];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self removeOutsideTapRecognizer];
}

- (void)dealloc {
    [self removeOutsideTapRecognizer];
}

- (void)removeOutsideTapRecognizer {
    if (outsideTapRecognizer == nil) {
        return;
    }
    outsideTapRecognizer.delegate = nil;
    [outsideTapRecognizer.view removeGestureRecognizer:outsideTapRecognizer];
    outsideTapRecognizer = nil;
}

- (BOOL)isShowingAppInfoPopover {
    for (UIViewController *controller in self.viewControllers) {
        if ([controller isKindOfClass:[AppInfo class]] && [(AppInfo *)controller isShowingActivityPopover]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (self.presentedViewController != nil || [self isShowingAppInfoPopover]) {
        return NO;
    }
    return VeterisViewIsBehindView(touch.view, self.view);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleOutsideTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded && self.presentedViewController == nil) {
        [self close];
    }
}

- (void)close {
    for (UIViewController *controller in self.viewControllers) {
        if ([controller isKindOfClass:[AppInfo class]]) {
            [(AppInfo *)controller dismissActivityPopoverAnimated:NO];
        }
    }
    [self removeOutsideTapRecognizer];
    void (^handler)(void) = self.closeHandler;
    if (handler != nil) {
        handler();
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return VeterisShouldAutorotateToInterfaceOrientation(interfaceOrientation);
}

@end

void VeterisShowAppInfo(UIViewController *source, UIViewController *appInfo) {
    if (source == nil || appInfo == nil) {
        return;
    }
    UINavigationController *navigationController = [source isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)source
        : source.navigationController;

    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad ||
        [navigationController isKindOfClass:[VeterisAppInfoSheetController class]]) {
        [navigationController pushViewController:appInfo animated:YES];
        return;
    }

    UIViewController *presenter = navigationController.tabBarController ?: source.tabBarController ?: navigationController ?: source;
    UIViewController *presented = presenter.presentedViewController;
    if ([presented isKindOfClass:[VeterisAppInfoSheetController class]]) {
        [(VeterisAppInfoSheetController *)presented pushViewController:appInfo animated:YES];
        return;
    }
    if (presented != nil) {
        [navigationController pushViewController:appInfo animated:YES];
        return;
    }

    VeterisAppInfoSheetController *sheet = [[VeterisAppInfoSheetController alloc] initWithRootViewController:appInfo];
    sheet.modalPresentationStyle = UIModalPresentationFormSheet;
    sheet.navigationBar.barStyle = UIBarStyleBlack;
    appInfo.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                             target:sheet
                                                                                             action:@selector(close)];
    [presenter presentViewController:sheet animated:YES completion:nil];
}

@implementation VeterisAppInfoSegue

- (void)perform {
    VeterisShowAppInfo(self.sourceViewController, self.destinationViewController);
}

@end
