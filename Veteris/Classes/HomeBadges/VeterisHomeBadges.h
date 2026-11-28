//
//  VeterisHomeBadges.h
//  Veteris
//
//  Created by Victor on 28.11.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const VeterisHomeBadgesDidChangeNotification;

@interface VeterisHomeBadges : NSObject

+ (void)refresh;
+ (void)noteAppOpen;
+ (void)skipFirstBadge;
+ (NSString *)pendingFirstBadge;
+ (NSString *)badgeAfter:(NSString *)current allowFirst:(BOOL)allowFirst;
+ (UIImage *)imageForBadge:(NSString *)name;

@end
