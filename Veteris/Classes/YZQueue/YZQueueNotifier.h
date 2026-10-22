#import <Foundation/Foundation.h>

@class UILocalNotification;

extern NSString *const YZDownloadNotificationsEnabledKey;
extern NSString *const YZBackgroundStatusNotificationsEnabledKey;

@interface YZQueueNotifier : NSObject
+ (YZQueueNotifier *)sharedInstance;
+ (BOOL)isQueueNotification:(UILocalNotification *)notification;
- (void)requestPermissionIfNeeded;
- (void)notifyDownloadsPaused;
- (void)notifyContinuingInBackground;
- (void)notifyRelaunchedInBackground;
- (void)notifyBackgroundWorkFinished;
@end
