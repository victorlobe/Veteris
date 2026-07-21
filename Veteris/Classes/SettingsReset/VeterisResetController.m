//
//  VeterisResetController.m
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "VeterisResetController.h"
#import <UIKit/UIKit.h>
#include <stdlib.h>

static NSInteger const VeterisResetConfirmAlertTag = 9101;
static NSInteger const VeterisResetCompleteAlertTag = 9102;

@implementation VeterisResetController

+ (VeterisResetController *)sharedController {
    static VeterisResetController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[VeterisResetController alloc] init];
    });
    return controller;
}

+ (void)confirmReset:(id)sender forKey:(NSString *)key {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Reset Veteris", nil)
                                                    message:NSLocalizedString(@"This will delete Veteris preferences, search history, crash reports, and caches. Veteris will close afterwards.", nil)
                                                   delegate:[VeterisResetController sharedController]
                                          cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                          otherButtonTitles:NSLocalizedString(@"Reset All", nil), nil];
    alert.tag = VeterisResetConfirmAlertTag;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == VeterisResetConfirmAlertTag) {
        if (buttonIndex != alertView.cancelButtonIndex) {
            [self resetVeterisData];
            UIAlertView *completeAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Veteris Reset", nil)
                                                                    message:NSLocalizedString(@"Veteris has been reset and will now close.", nil)
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                                          otherButtonTitles:nil];
            completeAlert.tag = VeterisResetCompleteAlertTag;
            [completeAlert show];
        }
        return;
    }

    if (alertView.tag == VeterisResetCompleteAlertTag) {
        exit(0);
    }
}

- (void)removeItemAtPath:(NSString *)path fileManager:(NSFileManager *)manager {
    if ([path length] == 0 || ![manager fileExistsAtPath:path]) {
        return;
    }

    NSError *error = nil;
    if (![manager removeItemAtPath:path error:&error]) {
        NSLog(@"Veteris reset: failed to remove %@: %@", path, [error localizedDescription]);
    }
}

- (void)resetVeterisData {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    NSString *bundleName = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"] description];
    if ([bundleName length] == 0) {
        bundleName = @"Veteris";
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removePersistentDomainForName:bundleIdentifier];
    [defaults synchronize];

    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        [cookieStorage deleteCookie:cookie];
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *paths = [NSArray arrayWithObjects:
        [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", bundleIdentifier],
        [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist.lockfile", bundleIdentifier],
        [NSString stringWithFormat:@"/var/mobile/Library/Caches/%@", bundleIdentifier],
        [NSString stringWithFormat:@"/var/mobile/Library/Caches/KSCrashReports/%@", bundleName],
        nil];

    for (NSString *path in paths) {
        [self removeItemAtPath:path fileManager:manager];
    }
}

@end
