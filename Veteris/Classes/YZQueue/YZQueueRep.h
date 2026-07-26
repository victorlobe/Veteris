#import <Foundation/Foundation.h>
#import "../YZApplication/YZApplication.h"

@class BBHTTPRequest;

typedef enum {
    YZRepStateInstalled = 0,
    YZRepStateInstalling,
    YZRepStateDownloaded,
    YZRepStateDownloading,
    YZRepStateQueued,
    YZRepStateFailed,
    YZRepStatePaused,
    YZRepStateCancelled,
} YZRepState;

@interface YZQueueRep : NSObject
+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url;
+ (void)detachRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url trackDownloadStart:(BOOL)trackDownloadStart;
+ (void)detachPausedRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath;
+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath;
+ (void)detachDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath trackDownloadStart:(BOOL)trackDownloadStart;
+ (void)detachPausedDownloadOnlyRepWithYZApp:(YZApplication *)yzApp andURL:(NSString *)url targetPath:(NSString *)targetPath;
- (UIImage *)icon;
- (NSString *)iconurl;
- (NSString *)fallbackIconurl;
- (NSString *)name;
- (NSString *)description;
- (NSString *)version;
- (NSString *)bundleID;
- (NSString *)developer;
- (NSString *)minimumOS;
- (NSString *)path;
- (void)setPath:(NSString *)path;
@property (nonatomic) bool invalid;
@property (nonatomic) BOOL installAfterDownload;
@property (nonatomic, assign) YZRepState state;
@property (nonatomic) BOOL preservePartialOnCancel;
@property (nonatomic, weak) BBHTTPRequest *request;
@property (nonatomic, strong) id downloadTask;
@property (nonatomic, copy) void (^downloadProgressBlock)(NSUInteger current, NSUInteger total);
@property (nonatomic, copy) void (^downloadSelf)(void);
@end
