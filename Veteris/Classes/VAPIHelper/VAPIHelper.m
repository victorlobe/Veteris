//
//  VAPIHelper.m
//  Veteris
//
//  Created by electimon on 6/7/19.
//  Copyright (c) 2019-22 Electimon. All rights reserved.
//

#include <Foundation/NSBundle.h>
#include <objc/NSObjCRuntime.h>
#import "../../Clutch/ApplicationLister.h"
#import "VAPIHelper.h"
#import "../Protos/Application.h"
#import <MacTypes.h>
#include <dlfcn.h>
#import <sys/sysctl.h>
#include <stdlib.h>
#import "../../AppDelegate.h"
#import "../../BBHTTP/BBHTTP.h"
#import "../../BBHTTP/BBHTTPRequest+Convenience.h"
#import "./../AppInfo/AppInfo.h"
#import "../Protos/Version.h"
#import "../Protos/Update.h"
#import "../ProtoStack.h"
#import "../../BBHTTP/Cocoa/BBURLProtocol.h"
#import "BBHTTP/BBHTTPExecutor.h"
#import "../YZApplication/YZApplication.h"
#import <arpa/inet.h>
#import <netdb.h>

@implementation VAPIHelper {
    NSCache *_staticCache;
    BBHTTPExecutor *_apiExecutor;
    BBHTTPExecutor *_iconExecutor;
    NSInteger _VAPIErrorMask;
    VeterisMemoryLevel _appliedMemoryLevel;
    BOOL _memorySettingsApplied;
}

@synthesize VAPIDeviceString = _deviceString;

static NSString *const API_PRODUCTION_STATIC_URL = @"http://api.victorlobe.me/veteris/";
static NSString *const API_PRODUCTION_BASE_URL = @"http://api.victorlobe.me/veteris/1.1/";
static NSString *const API_DEV_STATIC_URL = @"http://api.victorlobe.me/veteris-dev/";
static NSString *const API_DEV_BASE_URL = @"http://api.victorlobe.me/veteris-dev/1.1/";
static NSString *const VAPI_INSTALL_UUID_KEY = @"VAPIInstallUUID";
static NSString *const VAPI_ANALYTICS_OPT_OUT_UUID_KEY = @"VAPIAnalyticsOptOutUUID";
static NSString *const VAPI_CRASH_REPORTING_OPT_OUT_UUID_KEY = @"VAPICrashReportingOptOutUUID";
static NSString *const VAPI_DEV_MODE_ENABLED_KEY = @"veteris_dev_mode_enabled";
static NSString *const VAPI_ANALYTICS_ENABLED_KEY = @"veteris_analytics_enabled";
static NSString *const VAPI_CRASH_REPORTING_ENABLED_KEY = @"veteris_crash_reporting_enabled";
static NSString *const VAPI_SERVER_ENVIRONMENT_KEY = @"veteris_server_environment";
static NSString *const VAPI_LANGUAGE_OVERRIDE_KEY = @"veteris_language_override";
static NSString *const VAPI_LANGUAGE_OVERRIDE_SYSTEM = @"system";
static NSString *const VAPI_SERVER_ENVIRONMENT_PRODUCTION = @"production";
static NSString *const VAPI_SERVER_ENVIRONMENT_DEV = @"dev";
static NSString *const VAPI_ANALYTICS_OPT_OUT_HEADER = @"X-Veteris-Analytics";
static NSString *const VAPI_ANALYTICS_OPT_OUT_ID_HEADER = @"X-Veteris-Analytics-Opt-Out-ID";
static NSString *const VAPI_CRASH_REPORTING_OPT_OUT_HEADER = @"X-Veteris-Crash-Reports";
static NSString *const VAPI_CRASH_REPORTING_OPT_OUT_ID_HEADER = @"X-Veteris-Crash-Reports-Opt-Out-ID";

+ (VAPIHelper*)sharedInstance
{
    static VAPIHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[VAPIHelper alloc] init];
        [sharedInstance setup];
    });
    return sharedInstance;
}

- (void)setup {
    [self setVAPIDeviceString];
    _staticCache = [[NSCache alloc] init];
    _apiExecutor = [[BBHTTPExecutor alloc] initWithId:@"VAPIHelper-API"];
    _apiExecutor.manageNetworkActivityIndicator = true;
    _iconExecutor = [[BBHTTPExecutor alloc] initWithId:@"VAPIHelper-Icons"];
    _iconExecutor.manageNetworkActivityIndicator = false;
    [self applyMemorySettings];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsDidChange:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:[NSUserDefaults standardUserDefaults]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidReceiveMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    NSURL *apiURL = [NSURL URLWithString:[VAPIHelper getApiBaseURL]];
    NSString *apiHost = [apiURL host];
    if ([apiHost isEqualToString:@"apis.yzu.moe"]) {
        NSString *host = [self resolveHost:apiHost];
        if (host != nil) {
            [BBHTTPExecutor setResolvePolicy:apiHost withIP:host];
        }
    }
}

- (void)userDefaultsDidChange:(NSNotification *)notification {
    [self applyMemorySettings];
}

- (void)applicationDidReceiveMemoryWarning:(NSNotification *)notification {
    debugLog(@"Memory warning: clearing memory caches");
    [self clearMemoryCaches];
}


- (void)applyMemorySettings {
    @synchronized (self) {
        VeterisMemoryLevel level = [VeterisMemoryProfile activeLevel];
        if (_memorySettingsApplied && level == _appliedMemoryLevel) {
            return;
        }
        VeterisMemoryValues values = [VeterisMemoryProfile valuesForLevel:level smallMemory:[VeterisMemoryProfile isSmallMemoryDevice]];
        [_staticCache setTotalCostLimit:values.iconCacheCostLimit];
        [_staticCache setCountLimit:values.iconCacheCountLimit];
        _apiExecutor.maxParallelRequests = values.apiParallelRequests;
        _iconExecutor.maxParallelRequests = values.iconParallelRequests;
        if (_memorySettingsApplied && level == VeterisMemoryLevelReduced) {
            [_staticCache removeAllObjects];
        }
        _appliedMemoryLevel = level;
        _memorySettingsApplied = YES;
    }
    [VeterisMemoryProfile updateActiveLevelPreference];
}

+ (BOOL)isCrashReportingEnabled {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:VAPI_CRASH_REPORTING_ENABLED_KEY];
    if (value == nil) {
        return YES;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:VAPI_CRASH_REPORTING_ENABLED_KEY];
}

- (NSString *)resolveHost:(NSString *)host {
    struct hostent *host_entry = gethostbyname([host UTF8String]);
    if (host_entry == NULL || host_entry->h_addr_list == NULL || host_entry->h_addr_list[0] == NULL) {
        return nil;
    }
    char *buff;
    buff = inet_ntoa(*((struct in_addr *)host_entry->h_addr_list[0]));
    if (buff == NULL || strlen(buff) == 0) {
        return nil;
    }
    return [NSString stringWithUTF8String:buff];
}

+ (NSString *)getApiStaticURL {
    if ([VAPIHelper isDevModeEnabled] && [[VAPIHelper getServerEnvironment] isEqualToString:VAPI_SERVER_ENVIRONMENT_DEV]) {
        return API_DEV_STATIC_URL;
    }
    return API_PRODUCTION_STATIC_URL;
}

+ (NSString *)getApiBaseURL {
    if ([VAPIHelper isDevModeEnabled] && [[VAPIHelper getServerEnvironment] isEqualToString:VAPI_SERVER_ENVIRONMENT_DEV]) {
        return API_DEV_BASE_URL;
    }
    return API_PRODUCTION_BASE_URL;
}

+ (BOOL)isDevModeEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:VAPI_DEV_MODE_ENABLED_KEY];
}

+ (BOOL)isAnalyticsEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:VAPI_ANALYTICS_ENABLED_KEY] == nil) {
        return YES;
    }
    return [defaults boolForKey:VAPI_ANALYTICS_ENABLED_KEY];
}

+ (void)setDevModeEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:VAPI_DEV_MODE_ENABLED_KEY];
    if ([defaults objectForKey:VAPI_SERVER_ENVIRONMENT_KEY] == nil) {
        [defaults setObject:VAPI_SERVER_ENVIRONMENT_PRODUCTION forKey:VAPI_SERVER_ENVIRONMENT_KEY];
    }
    [defaults synchronize];
}

+ (NSSet *)supportedLanguageOverrides {
    return [NSSet setWithObjects:@"ar", @"de", @"en", @"es", @"fr", @"he", @"it", @"ja", @"pl", @"pt", @"ru", @"tr", @"uk", @"vi", @"zh-Hans", nil];
}

+ (NSString *)getLanguageOverride {
    NSString *language = [[NSUserDefaults standardUserDefaults] stringForKey:VAPI_LANGUAGE_OVERRIDE_KEY];
    if ([[VAPIHelper supportedLanguageOverrides] containsObject:language]) {
        return language;
    }
    return VAPI_LANGUAGE_OVERRIDE_SYSTEM;
}

+ (void)applyLanguageOverride {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *language = [VAPIHelper getLanguageOverride];
    if ([language isEqualToString:VAPI_LANGUAGE_OVERRIDE_SYSTEM]) {
        [defaults removeObjectForKey:@"AppleLanguages"];
    } else {
        [defaults setObject:[NSArray arrayWithObject:language] forKey:@"AppleLanguages"];
    }
    [defaults synchronize];
}

+ (NSString *)getServerEnvironment {
    NSString *environment = [[NSUserDefaults standardUserDefaults] stringForKey:VAPI_SERVER_ENVIRONMENT_KEY];
    if ([environment isEqualToString:VAPI_SERVER_ENVIRONMENT_DEV]) {
        return VAPI_SERVER_ENVIRONMENT_DEV;
    }
    return VAPI_SERVER_ENVIRONMENT_PRODUCTION;
}

+ (void)setServerEnvironment:(NSString *)environment {
    if (![environment isEqualToString:VAPI_SERVER_ENVIRONMENT_DEV]) {
        environment = VAPI_SERVER_ENVIRONMENT_PRODUCTION;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:environment forKey:VAPI_SERVER_ENVIRONMENT_KEY];
    [defaults synchronize];
    [VAPIHelper resetNetworkState];
}

+ (void)resetNetworkState {
    [[VAPIHelper sharedInstance] clearStaticCache];
}

- (void)clearStaticCache {
    [_staticCache removeAllObjects];
}

+ (NSString *)installUUID {
    static NSString *installUUID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        installUUID = [[defaults stringForKey:VAPI_INSTALL_UUID_KEY] copy];
        if (installUUID == nil || [installUUID length] == 0) {
            CFUUIDRef uuid = CFUUIDCreate(NULL);
            installUUID = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
            CFRelease(uuid);
            [defaults setObject:installUUID forKey:VAPI_INSTALL_UUID_KEY];
            [defaults synchronize];
        }
    });
    return installUUID;
}

+ (NSString *)uuidForDefaultsKey:(NSString *)key {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [defaults stringForKey:key];
    if (uuid == nil || [uuid length] == 0) {
        CFUUIDRef cfuuid = CFUUIDCreate(NULL);
        uuid = (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, cfuuid));
        CFRelease(cfuuid);
        [defaults setObject:uuid forKey:key];
        [defaults synchronize];
    }
    return uuid;
}

+ (NSString *)analyticsOptOutUUID {
    return [VAPIHelper uuidForDefaultsKey:VAPI_ANALYTICS_OPT_OUT_UUID_KEY];
}

+ (NSString *)crashReportingOptOutUUID {
    return [VAPIHelper uuidForDefaultsKey:VAPI_CRASH_REPORTING_OPT_OUT_UUID_KEY];
}

+ (NSDictionary *)getHeaders {
    NSMutableDictionary *headers = [@{
        @"X-Veteris-Device" : [VAPISS VAPIDeviceString],
        @"X-Veteris-Version" : [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"],
        @"X-Veteris-Build" : [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"],
        @"X-Veteris-Client" : @"Veteris",
        @"X-Veteris-Retina" : ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] && [UIScreen mainScreen].scale >= 2.0) ? @"1" : @"0",
        @"X-Veteris-Language" : [[NSLocale preferredLanguages] objectAtIndex:0],
    } mutableCopy];
    if (![VAPIHelper isAnalyticsEnabled]) {
        [headers setObject:@"0" forKey:VAPI_ANALYTICS_OPT_OUT_HEADER];
        [headers setObject:[VAPIHelper analyticsOptOutUUID] forKey:VAPI_ANALYTICS_OPT_OUT_ID_HEADER];
    } else {
        [headers setObject:[VAPIHelper installUUID] forKey:@"X-Veteris-UUID"];
    }
    if (![VAPIHelper isCrashReportingEnabled]) {
        [headers setObject:@"0" forKey:VAPI_CRASH_REPORTING_OPT_OUT_HEADER];
        [headers setObject:[VAPIHelper crashReportingOptOutUUID] forKey:VAPI_CRASH_REPORTING_OPT_OUT_ID_HEADER];
    }
    return headers;
}

static NSString *VAPIQueryEscape(NSString *value) {
    if (value == nil) {
        return @"";
    }
    NSString *escaped = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        NULL,
        (CFStringRef)value,
        NULL,
        (CFStringRef)@"!*'();:@&=+$,/?%#[]",
        kCFStringEncodingUTF8
    ));
    return escaped ?: @"";
}

+ (void)trackDownloadStartForApplication:(YZApplication *)application url:(NSString *)url downloadOnly:(BOOL)downloadOnly {
    if (application == nil || url == nil || [url length] == 0) {
        return;
    }

    [self trackDownloadEvent:@"download_start"
                    bundleID:application.bundleID
                     appName:application.name
                   developer:application.developer
                     version:application.version
                      minIOS:application.minimumOS
                         url:url
                   sizeBytes:application.sizeBytes
                downloadOnly:downloadOnly
                 extraFields:nil];
}

+ (void)trackDownloadEvent:(NSString *)event
                  bundleID:(NSString *)bundleID
                   appName:(NSString *)appName
                 developer:(NSString *)developer
                   version:(NSString *)version
                    minIOS:(NSString *)minIOS
                       url:(NSString *)url
                 sizeBytes:(unsigned long long)sizeBytes
              downloadOnly:(BOOL)downloadOnly
               extraFields:(NSDictionary *)extraFields {
    if (url == nil || [url length] == 0) {
        return;
    }

    NSMutableArray *items = [NSMutableArray array];
    NSMutableDictionary *fields = [@{
        @"event" : event ?: @"download_start",
        @"bundle_id" : bundleID ?: @"",
        @"app_name" : appName ?: @"",
        @"developer" : developer ?: @"",
        @"version" : version ?: @"",
        @"min_ios" : minIOS ?: @"",
        @"ipa_url" : url ?: @"",
        @"size_bytes" : [NSString stringWithFormat:@"%llu", sizeBytes],
        @"download_only" : downloadOnly ? @"1" : @"0",
    } mutableCopy];
    for (NSString *key in extraFields) {
        id value = [extraFields objectForKey:key];
        if ([key isKindOfClass:[NSString class]] && [key length] > 0 && value != nil) {
            [fields setObject:[value description] forKey:key];
        }
    }
    for (NSString *key in fields) {
        [items addObject:[NSString stringWithFormat:@"%@=%@", key, VAPIQueryEscape([fields objectForKey:key])]];
    }

    NSString *path = [NSString stringWithFormat:@"analytics/download?%@", [items componentsJoinedByString:@"&"]];
    [VAPISS getMessage:path completion:^(NSData *data, NSError *error) {
        if (error != nil) {
            debugLog(@"Download analytics failed: %@", error.localizedDescription);
        }
    }];
}

#define VAPI_USE_BBHTTP_DIRECT
#ifdef VAPI_USE_BBHTTP_DIRECT
- (void)get:(NSString *)endpoint path:(NSString *)path iconTraffic:(BOOL)iconTraffic completion:(void (^)(NSData *data, NSError *error))completion {
    BBHTTPExecutor *executor = iconTraffic ? _iconExecutor : _apiExecutor;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *reqHeaders = [VAPIHelper getHeaders];
        BBHTTPRequest *request = [[BBHTTPRequest alloc] initWithTarget:[NSString stringWithFormat:@"%@%@", endpoint, path] andVerb:@"GET"];
        for (id key in reqHeaders) {
            [request setValue:[reqHeaders valueForKey:key] forHeader:key];
        }
        request.finishBlock = ^(BBHTTPRequest *request) {
            if ([request hasSuccessfulResponse] || request.responseStatusCode == 503) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(request.response.content, nil);
                });
            } else {
                debugLog(@"Error occurred: %@", request.error.localizedDescription);
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, request.error);
                });
            }
        };
        [request downloadContentAsData];
        [executor executeRequest:request];
    });
}

- (void)get:(NSString *)endpoint path:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    [self get:endpoint path:path iconTraffic:NO completion:completion];
}
#else // has broken network activity indicator
- (void)get:(NSString *)endpoint path:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [endpoint stringByReplacingOccurrencesOfString:@"https" withString:@"bbhttps"], path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSDictionary *reqHeaders = [VAPIHelper getHeaders];
    for (id key in reqHeaders) {
        [request setValue:[reqHeaders valueForKey:key] forHTTPHeaderField:key];
    }
    [request setHTTPMethod:@"GET"];
    [NSURLProtocol registerClass:[BBURLProtocol class]];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
        if (error != nil) {
            debugLog(@"Error occurred: %@", error.localizedDescription);
        }
        completion(data, error);
    }];
}
#endif



- (void)getCached:(NSString *)endpoint path:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    if (path == nil || [path length] == 0) {
        completion(nil, [NSError errorWithDomain:@"VAPIHelper"
                                            code:NSURLErrorBadURL
                                        userInfo:@{NSLocalizedDescriptionKey: @"empty asset path"}]);
        return;
    }
    bool isImage = [[path lastPathComponent] rangeOfString:@"png"].location != NSNotFound
        || [[[path pathExtension] lowercaseString] isEqualToString:@"jpg"];
    BOOL isAbsoluteURL = [path hasPrefix:@"http://"] || [path hasPrefix:@"https://"];
    NSString *endpointToUse = isAbsoluteURL ? @"" : endpoint;
    NSString *pathToUse = isAbsoluteURL ? path : [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *cacheKey = [NSString stringWithFormat:@"%@%@", endpointToUse, pathToUse];
    if (isImage) {
        NSData *cachedData = [_staticCache objectForKey:cacheKey];
        if (cachedData != nil) {
            completion(cachedData, nil);
            return;
        }
    }
    [self get:endpointToUse path:pathToUse iconTraffic:YES completion:^(NSData *data, NSError *error){
        if (data != nil && isImage) {
            [_staticCache setObject:data forKey:cacheKey cost:[data length]];
        }
        completion(data, error);
    }];
}

- (void)getStatic:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    [self getCached:[VAPIHelper getApiStaticURL] path:path completion:completion];
}

- (void)getStatic:(NSString *)path fallbackPath:(NSString *)fallbackPath completion:(void (^)(NSData *data, NSError *error))completion {
    [self getStatic:path completion:^(NSData *data, NSError *error) {
        if (error == nil && data != nil) {
            completion(data, nil);
            return;
        }
        if (fallbackPath == nil || [fallbackPath length] == 0 || [fallbackPath isEqualToString:path]) {
            completion(data, error);
            return;
        }
        debugLog(@"Primary static asset failed, trying fallback: %@ -> %@", path, fallbackPath);
        [self getCached:[VAPIHelper getApiStaticURL] path:fallbackPath completion:^(NSData *fallbackData, NSError *fallbackError) {
            if (fallbackError == nil && fallbackData != nil && path != nil) {
                BOOL pathIsAbsoluteURL = [path hasPrefix:@"http://"] || [path hasPrefix:@"https://"];
                NSString *primaryPathToUse = pathIsAbsoluteURL ? path : [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                NSString *primaryCacheKey = pathIsAbsoluteURL ? primaryPathToUse : [NSString stringWithFormat:@"%@%@", [VAPIHelper getApiStaticURL], primaryPathToUse];
                [_staticCache setObject:fallbackData forKey:primaryCacheKey cost:[fallbackData length]];
            }
            completion(fallbackData, fallbackError);
        }];
    }];
}

- (void)getMessage:(NSString *)path completion:(void (^)(NSData *data, NSError *error))completion {
    [self get:[VAPIHelper getApiBaseURL] path:path completion:completion];
}



- (void)postMessage:(NSString *)path data:(NSData *)data contentType:(NSString *)contentType completion:(void (^)(NSData *data, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *url = [NSString stringWithFormat:@"%@%@", [VAPIHelper getApiBaseURL], path];
        BBHTTPRequest *request = [BBHTTPRequest createResource:url withData:data contentType:contentType];
        if (request == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"VAPIHelper" code:NSURLErrorBadURL userInfo:nil]);
            });
            return;
        }


        NSDictionary *reqHeaders = [VAPIHelper getHeaders];
        for (id key in reqHeaders) {
            [request setValue:[reqHeaders valueForKey:key] forHeader:key];
        }
        request.finishBlock = ^(BBHTTPRequest *request) {
            NSData *content = nil;
            NSError *error = nil;
            if ([request hasSuccessfulResponse]) {
                content = request.response.content ?: [NSData data];
            } else {
                debugLog(@"POST %@ failed: %ld %@", path, (long)request.responseStatusCode, request.error.localizedDescription);
                error = request.error ?: [NSError errorWithDomain:@"VAPIHelper" code:request.responseStatusCode userInfo:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(content, error);
            });
        };
        [request downloadContentAsData];
        [_apiExecutor executeRequest:request];
    });
}

- (UIImage *)imageFromCache:(NSString *)url {
    BOOL isAbsoluteURL = [url hasPrefix:@"http://"] || [url hasPrefix:@"https://"];
    NSString *pathToUse = isAbsoluteURL ? url : [url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *cacheKey = isAbsoluteURL ? pathToUse : [NSString stringWithFormat:@"%@%@", [VAPIHelper getApiStaticURL], pathToUse];
    NSData *cachedData = [_staticCache objectForKey:cacheKey];
    if (cachedData != nil) {
        return [UIImage imageWithData:cachedData];
    }
    return nil;
}

- (void)clearMemoryCaches {
    [_staticCache removeAllObjects];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (NSString *)getSysInfoByName:(char *)typeSpecifier {
    size_t size;
    sysctlbyname(typeSpecifier, NULL, &size, NULL, 0);

    char *answer = malloc(size);
    sysctlbyname(typeSpecifier, answer, &size, NULL, 0);

    NSString *results = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];

    free(answer);
    return results;
}

- (void)setVAPIDeviceString {
    AppDelegate *delegate = getDelegate();
    NSArray *deviceInfo = @[[self getSysInfoByName:"hw.model"], [self getSysInfoByName:"hw.machine"], [[UIDevice currentDevice] systemVersion]];
    _deviceString = [deviceInfo componentsJoinedByString:@"/"];
    debugLog(@"VAPI Device String: %@", _deviceString);
}


+ (void)checkForRemoteAlert {
    [VAPISS getMessage:@"client/alerts" completion:^(NSData *data, NSError *error) {
        if (error != nil || data == nil || [data length] <= 1) {
            return;
        }

        NSArray *alerts = (NSArray *)(CFBridgingRelease(decode([data bytes], [data length], NewsResponse)));
        NewsPost *remoteAlert = [alerts firstObject];
        if (remoteAlert == nil || remoteAlert.title.length == 0 || remoteAlert.body.length == 0) {
            return;
        }

        // Save alert ID before showing it to avoid duplicates
        NSString *alertID = remoteAlert.date.length > 0 ? remoteAlert.date : remoteAlert.title;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        @synchronized (defaults) {
            NSMutableArray *seenAlertIDs = [NSMutableArray arrayWithArray:[defaults objectForKey:@"seen_remote_alert_ids"] ?: @[]];
            // Migrate
            NSString *legacyAlertID = [defaults objectForKey:@"last_remote_alert_id"];
            if (legacyAlertID.length > 0 && ![seenAlertIDs containsObject:legacyAlertID]) {
                [seenAlertIDs addObject:legacyAlertID];
            }
            if ([seenAlertIDs containsObject:alertID]) {
                return;
            }
            [seenAlertIDs addObject:alertID];
            while (seenAlertIDs.count > 100) {
                [seenAlertIDs removeObjectAtIndex:0];
            }
            [defaults setObject:seenAlertIDs forKey:@"seen_remote_alert_ids"];
            [defaults removeObjectForKey:@"last_remote_alert_id"];
            [defaults synchronize];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alertView = [[UIAlertView alloc]
                initWithTitle:remoteAlert.title
                      message:remoteAlert.body
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
            [alertView show];
        });
    }];
}

+ (void)showWhatsNewIfNeeded {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSDictionary *latest_changelog = [defaults objectForKey:@"latest_changelog"];
        NSString *currentVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
        debugLog(@"Latest changelog: %@", latest_changelog);
        debugLog(@"Current version: %@", currentVersion);
        if (latest_changelog != nil && [latest_changelog objectForKey:currentVersion] != nil) {
            NSString *changelog = [latest_changelog objectForKey:currentVersion];
            [YZAlert alert:NSLocalizedString(@"What's New", nil) message:changelog separator:@"\n"];
            [defaults removeObjectForKey:@"latest_changelog"];
            [defaults synchronize];
        } else {
            debugLog(@"No changelog found for current version");
        }
    });
}
@end
