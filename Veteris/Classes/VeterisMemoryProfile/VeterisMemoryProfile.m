#import "VeterisMemoryProfile.h"
#import <sys/sysctl.h>

NSString *const VeterisMemoryProfileKey = @"veteris_memory_profile";
NSString *const VeterisMemoryProfileActiveKey = @"veteris_memory_profile_active";
NSString *const VeterisMaxConcurrentDownloadsKey = @"veteris_max_concurrent_downloads";
NSString *const VeterisDownloadConnectionsKey = @"veteris_archive_download_segments";

static NSString *const VeterisMemoryProfileAuto = @"auto";
static NSString *const VeterisMemoryProfileNormal = @"normal";
static NSString *const VeterisMemoryProfileReduced = @"reduced";
static NSString *const VeterisLegacyLowMemoryModeEnabledKey = @"veteris_low_memory_mode_enabled";
static NSString *const VeterisLegacyLowMemoryModeStatusKey = @"veteris_low_memory_mode_status";

// Some 256 MB devices report more memory than they have.
static const unsigned long long VeterisSmallMemoryLimit = 320ULL * 1024ULL * 1024ULL;

static const unsigned long long VeterisLegacySmallMemoryLimit = 256ULL * 1024ULL * 1024ULL;
static const NSUInteger VeterisMaxConcurrentDownloadsLimit = 3;
static const NSUInteger VeterisMaxConnectionsLimit = 12;

// Invalid picker values are reset to 0
static NSNumber *VeterisNormalizedIntegerSetting(id value, NSUInteger limit) {
    NSInteger integer = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    if (integer <= 0) {
        return [NSNumber numberWithInteger:0];
    }
    return [NSNumber numberWithUnsignedInteger:MIN((NSUInteger)integer, limit)];
}

// Use known 256MB models when memsize is unavailable.
static BOOL VeterisIsKnownSmallMemoryMachine(NSString *machine) {
    return ([machine isEqualToString:@"iPad1,1"] ||
            [machine isEqualToString:@"iPod3,1"] ||
            [machine isEqualToString:@"iPod4,1"] ||
            [machine isEqualToString:@"iPhone2,1"]);
}

static NSString *VeterisHardwareMachine(void) {
    static NSString *machine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        size_t size = 0;
        if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0) {
            machine = @"";
            return;
        }
        char *buffer = malloc(size);
        if (buffer == NULL) {
            machine = @"";
            return;
        }
        if (sysctlbyname("hw.machine", buffer, &size, NULL, 0) == 0) {
            machine = [[NSString stringWithUTF8String:buffer] copy] ?: @"";
        } else {
            machine = @"";
        }
        free(buffer);
    });
    return machine;
}

static unsigned long long VeterisMemorySize(void) {
    static unsigned long long memorySize = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint64_t value = 0;
        size_t size = sizeof(value);
        if (sysctlbyname("hw.memsize", &value, &size, NULL, 0) == 0) {
            memorySize = value;
        }
    });
    return memorySize;
}

@implementation VeterisMemoryProfile

#pragma mark - Decisions

+ (VeterisMemoryLevel)automaticLevelForMemorySize:(unsigned long long)memorySize machine:(NSString *)machine {
    if (memorySize > 0) {
        return memorySize <= VeterisSmallMemoryLimit ? VeterisMemoryLevelReduced : VeterisMemoryLevelNormal;
    }
    return VeterisIsKnownSmallMemoryMachine(machine) ? VeterisMemoryLevelReduced : VeterisMemoryLevelNormal;
}

+ (VeterisMemoryLevel)levelForPreference:(id)preference automaticLevel:(VeterisMemoryLevel)automaticLevel {
    if ([preference isEqual:VeterisMemoryProfileNormal]) {
        return VeterisMemoryLevelNormal;
    }
    if ([preference isEqual:VeterisMemoryProfileReduced]) {
        return VeterisMemoryLevelReduced;
    }
    return automaticLevel;
}

+ (BOOL)legacyDefaultForMemorySize:(unsigned long long)memorySize machine:(NSString *)machine {
    if (VeterisIsKnownSmallMemoryMachine(machine)) {
        return YES;
    }
    return memorySize > 0 && memorySize <= VeterisLegacySmallMemoryLimit;
}

+ (NSString *)migratedPreferenceForLegacyEnabled:(id)legacyEnabled legacyDefault:(BOOL)legacyDefault {
    // Only a value different from the old default counts as a user choice.
    BOOL enabled = [legacyEnabled respondsToSelector:@selector(boolValue)] && [legacyEnabled boolValue];
    return (enabled && !legacyDefault) ? VeterisMemoryProfileReduced : VeterisMemoryProfileAuto;
}

+ (NSUInteger)concurrentDownloadsForSetting:(NSInteger)setting level:(VeterisMemoryLevel)level {
    if (setting <= 0) {
        return [self valuesForLevel:level smallMemory:NO].autoConcurrentDownloads;
    }
    return MIN((NSUInteger)setting, VeterisMaxConcurrentDownloadsLimit);
}

+ (NSUInteger)connectionsForSetting:(NSInteger)setting level:(VeterisMemoryLevel)level {
    if (setting <= 0) {
        return [self valuesForLevel:level smallMemory:NO].autoConnectionsPerDownload;
    }
    return MIN((NSUInteger)setting, VeterisMaxConnectionsLimit);
}

+ (VeterisMemoryValues)valuesForLevel:(VeterisMemoryLevel)level smallMemory:(BOOL)smallMemory {
    VeterisMemoryValues values = {0};
    if (level == VeterisMemoryLevelReduced) {
        values.iconCacheCostLimit = 5 * 1024 * 1024;
        values.iconCacheCountLimit = 80;
        values.retainsDecodedIcons = NO;
        values.apiParallelRequests = 2;
        values.iconParallelRequests = 1;
        values.autoConcurrentDownloads = 1;
        values.autoConnectionsPerDownload = 4;
        values.readBufferSize = smallMemory ? 32 * 1024 : 64 * 1024;
        values.receiveBufferSize = smallMemory ? 64 * 1024 : 128 * 1024;
        values.mergeChunkSize = 32 * 1024;
        values.progressInterval = 1.0;
        values.clearsCachesAfterDownload = YES;
    } else {
        values.iconCacheCostLimit = 50 * 1024 * 1024;
        values.iconCacheCountLimit = 0;
        values.retainsDecodedIcons = YES;
        values.apiParallelRequests = 3;
        values.iconParallelRequests = 4;
        values.autoConcurrentDownloads = 3;
        values.autoConnectionsPerDownload = 6;
        values.readBufferSize = 128 * 1024;
        values.receiveBufferSize = 512 * 1024;
        values.mergeChunkSize = 64 * 1024;
        values.progressInterval = 0.25;
        values.clearsCachesAfterDownload = NO;
    }
    return values;
}

#pragma mark - Preferences

+ (BOOL)migrateLegacyPreferencesInDefaults:(NSUserDefaults *)defaults memorySize:(unsigned long long)memorySize machine:(NSString *)machine {
    BOOL changed = NO;
    if ([defaults objectForKey:VeterisMemoryProfileKey] == nil) {
        id legacyEnabled = [defaults objectForKey:VeterisLegacyLowMemoryModeEnabledKey];
        BOOL legacyDefault = [self legacyDefaultForMemorySize:memorySize machine:machine];
        [defaults setObject:[self migratedPreferenceForLegacyEnabled:legacyEnabled legacyDefault:legacyDefault]
                     forKey:VeterisMemoryProfileKey];
        changed = YES;
    }
    for (NSString *legacyKey in @[VeterisLegacyLowMemoryModeEnabledKey, VeterisLegacyLowMemoryModeStatusKey]) {
        if ([defaults objectForKey:legacyKey] != nil) {
            [defaults removeObjectForKey:legacyKey];
            changed = YES;
        }
    }
    return changed;
}

+ (BOOL)updateActiveLevelPreferenceInDefaults:(NSUserDefaults *)defaults level:(VeterisMemoryLevel)level {
    // A write reloads open Settings on iOS 10, so avoid writing unchanged values.
    NSString *value = (level == VeterisMemoryLevelReduced) ? VeterisMemoryProfileReduced : VeterisMemoryProfileNormal;
    if ([[defaults objectForKey:VeterisMemoryProfileActiveKey] isEqual:value]) {
        return NO;
    }
    [defaults setObject:value forKey:VeterisMemoryProfileActiveKey];
    return YES;
}

+ (BOOL)normalizeStoredPreferencesInDefaults:(NSUserDefaults *)defaults {
    BOOL changed = NO;
    id profile = [defaults objectForKey:VeterisMemoryProfileKey];
    if (profile != nil &&
        ![profile isEqual:VeterisMemoryProfileAuto] &&
        ![profile isEqual:VeterisMemoryProfileNormal] &&
        ![profile isEqual:VeterisMemoryProfileReduced]) {
        [defaults setObject:VeterisMemoryProfileAuto forKey:VeterisMemoryProfileKey];
        changed = YES;
    }
    NSDictionary *limits = @{
        VeterisMaxConcurrentDownloadsKey : [NSNumber numberWithUnsignedInteger:VeterisMaxConcurrentDownloadsLimit],
        VeterisDownloadConnectionsKey : [NSNumber numberWithUnsignedInteger:VeterisMaxConnectionsLimit],
    };
    for (NSString *key in limits) {
        id value = [defaults objectForKey:key];
        if (value == nil) {
            continue;
        }
        NSNumber *normalized = VeterisNormalizedIntegerSetting(value, [[limits objectForKey:key] unsignedIntegerValue]);
        if (![value isEqual:normalized]) {
            [defaults setObject:normalized forKey:key];
            changed = YES;
        }
    }
    return changed;
}

#pragma mark - Runtime

+ (VeterisMemoryLevel)automaticLevel {
    return [self automaticLevelForMemorySize:VeterisMemorySize() machine:VeterisHardwareMachine()];
}

+ (BOOL)isSmallMemoryDevice {
    return [self automaticLevel] == VeterisMemoryLevelReduced;
}

+ (VeterisMemoryLevel)activeLevel {
    id preference = [[NSUserDefaults standardUserDefaults] objectForKey:VeterisMemoryProfileKey];
    return [self levelForPreference:preference automaticLevel:[self automaticLevel]];
}

+ (VeterisMemoryValues)activeValues {
    return [self valuesForLevel:[self activeLevel] smallMemory:[self isSmallMemoryDevice]];
}

+ (NSUInteger)maxConcurrentDownloads {
    NSInteger setting = [[NSUserDefaults standardUserDefaults] integerForKey:VeterisMaxConcurrentDownloadsKey];
    return [self concurrentDownloadsForSetting:setting level:[self activeLevel]];
}

+ (NSUInteger)connectionsPerDownload {
    NSInteger setting = [[NSUserDefaults standardUserDefaults] integerForKey:VeterisDownloadConnectionsKey];
    return [self connectionsForSetting:setting level:[self activeLevel]];
}

+ (BOOL)prepareStoredPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL migrated = [self migrateLegacyPreferencesInDefaults:defaults memorySize:VeterisMemorySize() machine:VeterisHardwareMachine()];
    BOOL normalized = [self normalizeStoredPreferencesInDefaults:defaults];
    return migrated || normalized;
}

+ (void)updateActiveLevelPreference {
    [self updateActiveLevelPreferenceInDefaults:[NSUserDefaults standardUserDefaults] level:[self activeLevel]];
}

@end
