//
//  VAPIHelper.h
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2022 Electimon. All rights reserved.
//

#import "../../Clutch/MobileInstallation.h"
#import "../YZLog/YZLog.h"
#import "../YZAlert/YZAlert.h"
#import "../VeterisMemoryProfile/VeterisMemoryProfile.h"

// VAPIHelper should not include any classes to avoid circular imports
@class AppDelegate;
@class YZApplication;

#define getDelegate() ((AppDelegate*)[[UIApplication sharedApplication]delegate])
#define legacyDownloadPath() @"/var/mobile/Media/Downloads/Veteris"
#define downloadPath() @"/var/mobile/Library/Veteris"
#define downloadPathFor(string) [NSString stringWithFormat:@"%@/%@.ipa", downloadPath(), [string MD5Hash]]
#define downloadPathForVersion(bundleID, version) downloadPathFor(([NSString stringWithFormat:@"%@|%@", (bundleID) ?: @"", (version) ?: @""]))
#define downloadOnlyPath() @"/var/mobile/Library/Veteris/Download"
#define VAPISS [VAPIHelper sharedInstance]
//#define alert(title,msg,target) [[[UIAlertView alloc] initWithTitle:title message:msg delegate:target cancelButtonTitle:@"OK" otherButtonTitles:nil, nil] show]
#define alert(title,msg,typ) [YZAlert alert:title message:msg type:typ]

@interface VAPIHelper : NSObject<NSURLConnectionDelegate>
+ (VAPIHelper *)sharedInstance;
+ (NSString *)getApiStaticURL;
+ (NSString *)getApiBaseURL;
+ (BOOL)isDevModeEnabled;
+ (void)setDevModeEnabled:(BOOL)enabled;
+ (NSString *)getLanguageOverride;
+ (void)applyLanguageOverride;
+ (NSString *)getServerEnvironment;
+ (void)setServerEnvironment:(NSString *)environment;
+ (void)resetNetworkState;
+ (BOOL)isCrashReportingEnabled;
- (void)get:(NSString *)endpoint path:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion;
- (void)getStatic:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion;
- (void)getStatic:(NSString *)path fallbackPath:(NSString *)fallbackPath completion:(void (^)(NSData *data, NSError *error))completion;
- (void)getMessage:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion;
- (void)postMessage:(NSString *)path data:(NSData *)data contentType:(NSString *)contentType completion:(void (^)(NSData *data, NSError *error))completion;
- (UIImage *)imageFromCache:(NSString *)url;
- (void)clearMemoryCaches;
+ (void)checkForRemoteAlert;
+ (NSDictionary *)getHeaders;
+ (void)trackDownloadStartForApplication:(YZApplication *)application url:(NSString *)url downloadOnly:(BOOL)downloadOnly;
+ (void)trackDownloadEvent:(NSString *)event
                  bundleID:(NSString *)bundleID
                   appName:(NSString *)appName
                 developer:(NSString *)developer
                   version:(NSString *)version
                    minIOS:(NSString *)minIOS
                       url:(NSString *)url
                 sizeBytes:(unsigned long long)sizeBytes
              downloadOnly:(BOOL)downloadOnly
               extraFields:(NSDictionary *)extraFields;
+ (void)showWhatsNewIfNeeded;
@property (strong, nonatomic) NSString *VAPIDeviceString;
@end
