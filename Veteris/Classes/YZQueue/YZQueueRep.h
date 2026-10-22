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
- (instancetype)initWithApplication:(YZApplication *)application
                          sourceURL:(NSString *)sourceURL
                         targetPath:(NSString *)targetPath
               installAfterDownload:(BOOL)installAfterDownload
                 trackDownloadStart:(BOOL)trackDownloadStart;
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
- (YZApplication *)application;
// YES when Veteris owns the files at targetPath
- (BOOL)ownsDownloadFiles;
@property (nonatomic, readonly, copy) NSString *sourceURL;
@property (nonatomic, readonly, copy) NSString *targetPath;
@property (nonatomic) bool invalid;
@property (nonatomic) BOOL installAfterDownload;
@property (nonatomic) BOOL trackDownloadStart;
@property (nonatomic) BOOL installScheduled;
@property (nonatomic, assign) YZRepState state;
@property (nonatomic, readonly) YZRepState previousState;
@property (nonatomic, copy) NSString *errorDetails;
@property (nonatomic) NSUInteger storedProgressCurrent;
@property (nonatomic) NSUInteger storedProgressTotal;
@property (nonatomic) NSUInteger downloadGeneration;
@property (nonatomic) NSUInteger enqueueSequence;
@property (nonatomic, weak) BBHTTPRequest *request;
@property (nonatomic, strong) id downloadTask;
@property (nonatomic, copy) void (^downloadProgressBlock)(NSUInteger current, NSUInteger total);
@property (nonatomic) BOOL downloadFinishing;
// User-paused entries stay paused after a background relaunch.
@property (nonatomic) BOOL userPaused;
@property (nonatomic) BOOL interruptedBySystem;
- (void)refreshStoredDownloadProgress;
- (void)reportDownloadProgress:(unsigned long long)current total:(unsigned long long)total;
- (double)downloadBytesPerSecond;
@end
