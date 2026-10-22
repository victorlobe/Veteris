//
//  VeterisUpdatesManager.h
//  Veteris
//
//  Created by Victor on 12.10.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Application;

extern NSString *const VeterisUpdatesDidChangeNotification;

typedef NS_ENUM(NSInteger, VeterisUpdatesCheckState) {
    VeterisUpdatesCheckStateNone = 0,
    VeterisUpdatesCheckStateChecking = 1,
    VeterisUpdatesCheckStateLoaded = 2,
    VeterisUpdatesCheckStateFailed = 3,
};

@interface VeterisUpdatesManager : NSObject



+ (VeterisUpdatesManager *)sharedManager;
- (void)start;
- (void)checkForUpdates;
- (VeterisUpdatesCheckState)checkState;
- (NSArray *)availableUpdates;
- (NSArray *)mutedUpdates;
- (NSString *)installedVersionForUpdate:(Application *)update;
- (BOOL)isUpdateMuted:(Application *)update;
- (void)setUpdate:(Application *)update muted:(BOOL)muted;
- (void)installUpdates:(NSArray *)updates completion:(void (^)(NSUInteger failedCount))completion;

@end
