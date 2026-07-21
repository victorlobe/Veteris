//
//  VeterisFavoritesManager.h
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Application;

extern NSString *const VeterisFavoritesDidChangeNotification;

@interface VeterisFavoritesManager : NSObject

+ (NSArray *)favoriteApplications;
+ (BOOL)isFavoriteBundleID:(NSString *)bundleID;
+ (void)addFavoriteApplication:(Application *)application;
+ (void)removeFavoriteBundleID:(NSString *)bundleID;
+ (BOOL)toggleFavoriteApplication:(Application *)application;

@end
