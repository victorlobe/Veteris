#import <UIKit/UIKit.h>
#import "../VAPIHelper/VAPIHelper.h"
#import "../Protos/Application.h"
#import "../Protos/Version.h"
#import "../ProtoStack.h"
#import "../YZQueue/YZQueueRep.h"

@interface QueueTableViewCell : UITableViewCell
@property (nonatomic, retain) UILabel *appNameLabel;
@property (nonatomic, retain) UILabel *appVersionLabel;
@property (nonatomic, retain) UILabel *appDeveloperLabel;
@property (nonatomic, retain) UIImageView *appImageView;
@property (nonatomic, retain) UIActivityIndicatorView *appActivityIndicator;
@property (nonatomic, retain) UIActivityIndicatorView *appDownloadActivityIndicator;
@property (nonatomic, retain) UIProgressView *appProgressView;
@property (nonatomic, retain) UILabel *appProgressLabel;
@property (nonatomic, retain) UILabel *appSpeedLabel;
- (void)updateFromRep:(YZQueueRep *)rep;
- (void)updateDownloadProgressWithCurrent:(NSUInteger)current total:(NSUInteger)total;
- (YZQueueRep *)rep;
@end
