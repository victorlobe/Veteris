#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, VeterisMemoryLevel) {
    VeterisMemoryLevelNormal = 0,
    VeterisMemoryLevelReduced = 1,
};

typedef struct {
    NSUInteger iconCacheCostLimit;
    NSUInteger iconCacheCountLimit;
    BOOL retainsDecodedIcons;
    NSUInteger apiParallelRequests;
    NSUInteger iconParallelRequests;
    NSUInteger autoConcurrentDownloads;
    NSUInteger autoConnectionsPerDownload;
    NSUInteger readBufferSize;
    int receiveBufferSize;
    NSUInteger mergeChunkSize;
    NSTimeInterval progressInterval;
    BOOL clearsCachesAfterDownload;
} VeterisMemoryValues;

extern NSString *const VeterisMemoryProfileKey;
extern NSString *const VeterisMemoryProfileActiveKey;
extern NSString *const VeterisMaxConcurrentDownloadsKey;
extern NSString *const VeterisDownloadConnectionsKey;

@interface VeterisMemoryProfile : NSObject

#pragma mark - Decisions (pure, unit tested)
+ (VeterisMemoryLevel)automaticLevelForMemorySize:(unsigned long long)memorySize machine:(NSString *)machine;
+ (VeterisMemoryLevel)levelForPreference:(id)preference automaticLevel:(VeterisMemoryLevel)automaticLevel;
+ (BOOL)legacyDefaultForMemorySize:(unsigned long long)memorySize machine:(NSString *)machine;
+ (NSString *)migratedPreferenceForLegacyEnabled:(id)legacyEnabled legacyDefault:(BOOL)legacyDefault;
+ (NSUInteger)concurrentDownloadsForSetting:(NSInteger)setting level:(VeterisMemoryLevel)level;
+ (NSUInteger)connectionsForSetting:(NSInteger)setting level:(VeterisMemoryLevel)level;
+ (VeterisMemoryValues)valuesForLevel:(VeterisMemoryLevel)level smallMemory:(BOOL)smallMemory;

#pragma mark - Preferences (return YES when something was written)
+ (BOOL)migrateLegacyPreferencesInDefaults:(NSUserDefaults *)defaults memorySize:(unsigned long long)memorySize machine:(NSString *)machine;
+ (BOOL)updateActiveLevelPreferenceInDefaults:(NSUserDefaults *)defaults level:(VeterisMemoryLevel)level;
+ (BOOL)normalizeStoredPreferencesInDefaults:(NSUserDefaults *)defaults;

#pragma mark - Runtime (this device, standard user defaults)
+ (VeterisMemoryLevel)automaticLevel;
+ (BOOL)isSmallMemoryDevice;
+ (VeterisMemoryLevel)activeLevel;
+ (VeterisMemoryValues)activeValues;
+ (NSUInteger)maxConcurrentDownloads;
+ (NSUInteger)connectionsPerDownload;
+ (BOOL)prepareStoredPreferences;
+ (void)updateActiveLevelPreference;

@end
