//
//  VeterisFavoritesManager.m
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "VeterisFavoritesManager.h"
#import "../Protos/Application.h"

NSString *const VeterisFavoritesDidChangeNotification = @"VeterisFavoritesDidChangeNotification";

static NSString *const VeterisFavoritesDefaultsKey = @"VeterisFavorites";
static NSString *const VeterisFavoriteNameKey = @"name";
static NSString *const VeterisFavoriteDeveloperKey = @"developer";
static NSString *const VeterisFavoriteBundleIDKey = @"bundleid";
static NSString *const VeterisFavoriteIconURLKey = @"iconurl";
static NSString *const VeterisFavoriteFallbackIconURLKey = @"fallback_iconurl";
static NSString *const VeterisFavoriteVersionKey = @"version";
static NSString *const VeterisFavoriteVersionCountKey = @"version_count";

@implementation VeterisFavoritesManager

+ (NSString *)safeString:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return @"";
}

+ (NSArray *)favoriteDictionaries {
    id favorites = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisFavoritesDefaultsKey];
    if ([favorites isKindOfClass:[NSArray class]]) {
        return favorites;
    }
    return [NSArray array];
}

+ (NSUInteger)indexOfBundleID:(NSString *)bundleID inFavorites:(NSArray *)favorites {
    if ([bundleID length] == 0) {
        return NSNotFound;
    }
    for (NSUInteger index = 0; index < [favorites count]; index++) {
        NSDictionary *favorite = [favorites objectAtIndex:index];
        if (![favorite isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if ([[favorite objectForKey:VeterisFavoriteBundleIDKey] isEqualToString:bundleID]) {
            return index;
        }
    }
    return NSNotFound;
}

+ (NSDictionary *)dictionaryForApplication:(Application *)application {
    if (application == nil || [application.bundleid length] == 0) {
        return nil;
    }

    NSUInteger versionCount = application.versionCount;
    if (versionCount == 0 && [application.versions count] > 0) {
        versionCount = [application.versions count];
    }

    return @{
        VeterisFavoriteNameKey : [self safeString:application.name],
        VeterisFavoriteDeveloperKey : [self safeString:application.developer],
        VeterisFavoriteBundleIDKey : [self safeString:application.bundleid],
        VeterisFavoriteIconURLKey : [self safeString:application.iconurl],
        VeterisFavoriteFallbackIconURLKey : [self safeString:application.fallback_iconurl],
        VeterisFavoriteVersionKey : [self safeString:application.version],
        VeterisFavoriteVersionCountKey : [NSNumber numberWithUnsignedInteger:versionCount]
    };
}

+ (Application *)applicationForFavoriteDictionary:(NSDictionary *)favorite {
    if (![favorite isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *bundleID = [self safeString:[favorite objectForKey:VeterisFavoriteBundleIDKey]];
    if ([bundleID length] == 0) {
        return nil;
    }

    Application *application = [[Application alloc] init];
    application.name = [self safeString:[favorite objectForKey:VeterisFavoriteNameKey]];
    application.developer = [self safeString:[favorite objectForKey:VeterisFavoriteDeveloperKey]];
    application.bundleid = bundleID;
    application.iconurl = [self safeString:[favorite objectForKey:VeterisFavoriteIconURLKey]];
    application.fallback_iconurl = [self safeString:[favorite objectForKey:VeterisFavoriteFallbackIconURLKey]];
    application.version = [self safeString:[favorite objectForKey:VeterisFavoriteVersionKey]];
    application.versionCount = [[favorite objectForKey:VeterisFavoriteVersionCountKey] unsignedIntegerValue];
    application.versions = [NSMutableArray array];
    application.nilIcon = NO;
    application.isVTableEntry = YES;
    return application;
}

+ (void)saveFavoriteDictionaries:(NSArray *)favorites {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:favorites forKey:VeterisFavoritesDefaultsKey];
    [defaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:VeterisFavoritesDidChangeNotification object:nil];
}

+ (NSArray *)favoriteApplications {
    NSMutableArray *applications = [NSMutableArray array];
    for (NSDictionary *favorite in [self favoriteDictionaries]) {
        Application *application = [self applicationForFavoriteDictionary:favorite];
        if (application != nil) {
            [applications addObject:application];
        }
    }
    return applications;
}

+ (BOOL)isFavoriteBundleID:(NSString *)bundleID {
    return [self indexOfBundleID:bundleID inFavorites:[self favoriteDictionaries]] != NSNotFound;
}

+ (void)addFavoriteApplication:(Application *)application {
    NSDictionary *favorite = [self dictionaryForApplication:application];
    if (favorite == nil) {
        return;
    }

    NSMutableArray *favorites = [[self favoriteDictionaries] mutableCopy];
    NSUInteger existingIndex = [self indexOfBundleID:application.bundleid inFavorites:favorites];
    if (existingIndex != NSNotFound) {
        [favorites removeObjectAtIndex:existingIndex];
    }
    [favorites insertObject:favorite atIndex:0];
    [self saveFavoriteDictionaries:favorites];
}

+ (void)removeFavoriteBundleID:(NSString *)bundleID {
    NSMutableArray *favorites = [[self favoriteDictionaries] mutableCopy];
    NSUInteger existingIndex = [self indexOfBundleID:bundleID inFavorites:favorites];
    if (existingIndex == NSNotFound) {
        return;
    }
    [favorites removeObjectAtIndex:existingIndex];
    [self saveFavoriteDictionaries:favorites];
}

+ (BOOL)toggleFavoriteApplication:(Application *)application {
    if ([self isFavoriteBundleID:application.bundleid]) {
        [self removeFavoriteBundleID:application.bundleid];
        return NO;
    }

    [self addFavoriteApplication:application];
    return YES;
}

@end
