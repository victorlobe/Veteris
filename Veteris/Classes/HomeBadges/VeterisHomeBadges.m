//
//  VeterisHomeBadges.m
//  Veteris
//
//  Created by Victor on 28.11.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "VeterisHomeBadges.h"
#import "../ProtoStack.h"

NSString *const VeterisHomeBadgesDidChangeNotification = @"VeterisHomeBadgesDidChangeNotification";

static NSString *const VeterisHomeBadgesListKey = @"veteris_home_badges";
static NSString *const VeterisHomeBadgesStateKey = @"veteris_home_badges_state";
static NSString *const VeterisRemoteBadgePrefix = @"remote:";

static BOOL VeterisHomeBadgesRefreshing = NO;
static BOOL VeterisHomeBadgesFirstSettled = NO;
static NSMutableSet *VeterisHomeBadgesDownloading = nil;



@implementation VeterisHomeBadges

+ (NSArray *)builtinBadges
{
    return @[
        @"honoringElectimonBadge",
        @"thankYouElectimonBadge",
        @"thankYouElectimonHeartBadge",
        @"electimonIsTheBestBadge",
        @"oneLoveBadge",
        @"welcomeBackBadge",
        @"youAreAwesomeBadge",
    ];
}

+ (NSString *)imageDirectory
{
    return [downloadPath() stringByAppendingPathComponent:@"HomeBadges"];
}

+ (NSString *)imagePathForBadge:(NSDictionary *)badge
{
    return [[self imageDirectory] stringByAppendingPathComponent:[badge objectForKey:@"file"]]; 
}

+ (NSDictionary *)storedList
{
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:VeterisHomeBadgesListKey] ?: @{};
}

+ (NSDateFormatter *)formatterWithFormat:(NSString *)format
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone systemTimeZone];
    formatter.dateFormat = format;
    return formatter;
}

+ (NSDictionary *)settingsFromBody:(NSString *)body
{
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
        NSRange separator = [line rangeOfString:@"="];
        if (separator.location == NSNotFound || separator.location == 0) {
            continue;
        }
        [settings setObject:[line substringFromIndex:NSMaxRange(separator)] forKey:[line substringToIndex:separator.location]];
    }
    return settings;
}

+ (NSDictionary *)listFromEntries:(NSArray *)entries
{
    if (![entries isKindOfClass:[NSArray class]] || [entries count] == 0) {
        return nil;
    }
    NewsPost *header = [entries objectAtIndex:0];
    NSString *hideBuiltin = [[self settingsFromBody:header.body] objectForKey:@"hide_builtin"];
    if ([header.title length] > 0 || [header.link length] > 0 || hideBuiltin == nil) {
        return nil;
    }
    NSMutableArray *badges = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (NewsPost *entry in [entries subarrayWithRange:NSMakeRange(1, [entries count] - 1)]) {
        NSString *file = [entry.link lastPathComponent];
        if ([entry.title length] == 0 || [ids containsObject:entry.title]
            || ![[file pathExtension] isEqualToString:@"png"]
            || ![entry.link isEqualToString:[@"badges/" stringByAppendingString:file]]) {
            continue;
        }
        NSMutableDictionary *badge = [NSMutableDictionary dictionaryWithDictionary:[self settingsFromBody:entry.body]];
        [badge setObject:entry.title forKey:@"id"];
        [badge setObject:entry.link forKey:@"link"];
        [badge setObject:file forKey:@"file"];
        [badges addObject:badge];
        [ids addObject:entry.title];
    }
    return @{@"hide_builtin": @([hideBuiltin boolValue]), @"badges": badges};
}

+ (void)refresh
{
    if (VeterisHomeBadgesRefreshing) {
        return;
    }
    VeterisHomeBadgesRefreshing = YES;
    [VAPISS getMessage:@"client/badges" completion:^(NSData *data, NSError *error) {
        VeterisHomeBadgesRefreshing = NO;
        if (error != nil || [data length] == 0) {
            return;
        }
        NSArray *entries = (NSArray *)(CFBridgingRelease(decode([data bytes], [data length], NewsResponse)));
        NSDictionary *list = [self listFromEntries:entries];
        if (list == nil) {
            return; 
        }
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:list forKey:VeterisHomeBadgesListKey];
        [self pruneForList:list];
        [defaults synchronize];
        [self downloadMissingImagesForList:list];
        [[NSNotificationCenter defaultCenter] postNotificationName:VeterisHomeBadgesDidChangeNotification object:nil];
    }];
}

+ (void)pruneForList:(NSDictionary *)list
{
    NSArray *badges = [list objectForKey:@"badges"];
    NSArray *ids = [badges valueForKey:@"id"];
    NSArray *files = [badges valueForKey:@"file"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *states = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:VeterisHomeBadgesStateKey]];
    for (NSString *badgeID in [states allKeys]) {
        if (![ids containsObject:badgeID]) {
            [states removeObjectForKey:badgeID];
        }
    }
    [defaults setObject:states forKey:VeterisHomeBadgesStateKey];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = [self imageDirectory];
    for (NSString *file in [manager contentsOfDirectoryAtPath:directory error:NULL]) {
        if (![files containsObject:file]) {
            [manager removeItemAtPath:[directory stringByAppendingPathComponent:file] error:NULL];
        }
    }
}

+ (void)downloadMissingImagesForList:(NSDictionary *)list
{
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:[self imageDirectory] withIntermediateDirectories:YES attributes:nil error:NULL];
    if (VeterisHomeBadgesDownloading == nil) {
        VeterisHomeBadgesDownloading = [NSMutableSet set];
    }
    for (NSDictionary *badge in [list objectForKey:@"badges"]) {
        NSString *path = [self imagePathForBadge:badge];
        if ([manager fileExistsAtPath:path] || [VeterisHomeBadgesDownloading containsObject:path]) {
            continue;
        }
        [VeterisHomeBadgesDownloading addObject:path];
        [VAPISS get:[VAPIHelper getApiStaticURL] path:[badge objectForKey:@"link"] completion:^(NSData *data, NSError *error) {
            [VeterisHomeBadgesDownloading removeObject:path];
            if (error != nil || [data length] == 0 || [UIImage imageWithData:data] == nil || ![data writeToFile:path atomically:YES]) {
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:VeterisHomeBadgesDidChangeNotification object:nil];
        }];
    }
}

+ (BOOL)date:(NSDate **)date forBadge:(NSDictionary *)badge key:(NSString *)key
{
    NSString *value = [badge objectForKey:key];
    if ([value length] == 0) {
        *date = nil;
        return YES;
    }
    if ([[badge objectForKey:@"time"] isEqualToString:@"local"]) {
        *date = [[self formatterWithFormat:@"yyyy-MM-dd'T'HH:mm:ss"] dateFromString:value];
    } else {
        *date = [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
    }
    return *date != nil;
}

+ (BOOL)isBadgeActive:(NSDictionary *)badge now:(NSDate *)now
{
    NSDate *start = nil;
    NSDate *end = nil;
    if (![self date:&start forBadge:badge key:@"starts_at"] || ![self date:&end forBadge:badge key:@"expires_at"]) {
        return NO;
    }
    return (start == nil || [now compare:start] != NSOrderedAscending)
        && (end == nil || [now compare:end] == NSOrderedAscending);
}

+ (NSArray *)activeBadges
{
    NSDate *now = [NSDate date];
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray *active = [NSMutableArray array];
    for (NSDictionary *badge in [[self storedList] objectForKey:@"badges"]) {
        if ([self isBadgeActive:badge now:now] && [manager fileExistsAtPath:[self imagePathForBadge:badge]]) {
            [active addObject:badge]; 
        }
    }
    return active;
}

+ (NSString *)nameForBadge:(NSDictionary *)badge
{
    return [VeterisRemoteBadgePrefix stringByAppendingString:[badge objectForKey:@"id"]];
}

+ (BOOL)canShowFirstBadge:(NSDictionary *)badge state:(NSDictionary *)state now:(NSDate *)now
{
    NSString *show = [badge objectForKey:@"first_show"];
    NSInteger count = [[state objectForKey:@"count"] integerValue];
    if ([show isEqualToString:@"always"]) {
        return YES;
    }
    if ([show isEqualToString:@"launches"]) {
        return count < [[badge objectForKey:@"launches"] integerValue];
    }
    if ([show isEqualToString:@"daily"]) {
        return ![[state objectForKey:@"day"] isEqualToString:[[self formatterWithFormat:@"yyyy-MM-dd"] stringFromDate:now]];
    }
    if ([show isEqualToString:@"day"]) {
        NSNumber *firstShown = [state objectForKey:@"first"];
        return firstShown == nil || [now timeIntervalSince1970] - [firstShown doubleValue] < 24 * 60 * 60;
    }
    return count == 0;
}

+ (void)recordFirstBadge:(NSDictionary *)badge now:(NSDate *)now
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *states = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:VeterisHomeBadgesStateKey]];
    NSString *badgeID = [badge objectForKey:@"id"];
    NSDictionary *old = [states objectForKey:badgeID];
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:old];
    [state setObject:@([[old objectForKey:@"count"] integerValue] + 1) forKey:@"count"];
    if ([old objectForKey:@"first"] == nil) {
        [state setObject:@([now timeIntervalSince1970]) forKey:@"first"];
    }
    [state setObject:[[self formatterWithFormat:@"yyyy-MM-dd"] stringFromDate:now] forKey:@"day"];
    [states setObject:state forKey:badgeID];
    [defaults setObject:states forKey:VeterisHomeBadgesStateKey];
    [defaults synchronize];
}

+ (void)noteAppOpen
{
    VeterisHomeBadgesFirstSettled = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:VeterisHomeBadgesDidChangeNotification object:nil];
}



+ (void)skipFirstBadge
{
    VeterisHomeBadgesFirstSettled = YES;
}

+ (NSString *)pendingFirstBadge
{
    if (VeterisHomeBadgesFirstSettled) {
        return nil;
    }
    NSDate *now = [NSDate date];
    NSDictionary *states = [[NSUserDefaults standardUserDefaults] dictionaryForKey:VeterisHomeBadgesStateKey];
    for (NSDictionary *badge in [self activeBadges]) {
        if (![[badge objectForKey:@"mode"] isEqualToString:@"first"]
            || ![self canShowFirstBadge:badge state:[states objectForKey:[badge objectForKey:@"id"]] now:now]) {
            continue;
        }
        VeterisHomeBadgesFirstSettled = YES;
        [self recordFirstBadge:badge now:now];
        return [self nameForBadge:badge];
    }
    return nil;
}

+ (NSArray *)badgePool
{
    BOOL hideBuiltin = [[[self storedList] objectForKey:@"hide_builtin"] boolValue];
    NSMutableArray *exclusive = [NSMutableArray array];
    NSMutableArray *cycle = [NSMutableArray array];
    for (NSDictionary *badge in [self activeBadges]) {
        NSString *mode = [badge objectForKey:@"mode"];
        if ([mode isEqualToString:@"exclusive"]) {
            [exclusive addObject:[self nameForBadge:badge]];
        } else if ([mode isEqualToString:@"cycle"]) {
            [cycle addObject:[self nameForBadge:badge]];
        }
        hideBuiltin = hideBuiltin || [[badge objectForKey:@"hide_builtin"] boolValue];
    }
    if ([exclusive count] > 0) {
        return exclusive;
    }
    if (!hideBuiltin) {
        [cycle addObjectsFromArray:[self builtinBadges]];
    }
    return [cycle count] > 0 ? cycle : [self builtinBadges];
}

+ (NSString *)badgeAfter:(NSString *)current allowFirst:(BOOL)allowFirst
{
    NSString *first = allowFirst ? [self pendingFirstBadge] : nil;
    if (first != nil) {
        return first;
    }
    NSArray *pool = [self badgePool];
    NSString *name = [pool lastObject];
    if ([pool count] > 1) {
        do {
            name = [pool objectAtIndex:arc4random_uniform((uint32_t)[pool count])];
        } while ([name isEqualToString:current]);
    }
    return name;
}

+ (UIImage *)imageForBadge:(NSString *)name
{
    if (![name hasPrefix:VeterisRemoteBadgePrefix]) {
        return [UIImage imageNamed:name];
    }
    NSString *badgeID = [name substringFromIndex:[VeterisRemoteBadgePrefix length]];
    for (NSDictionary *badge in [[self storedList] objectForKey:@"badges"]) {
        if ([[badge objectForKey:@"id"] isEqualToString:badgeID]) {
            return [UIImage imageWithContentsOfFile:[self imagePathForBadge:badge]];
        }
    }
    return nil;
}

@end
