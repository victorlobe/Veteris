#import <Foundation/Foundation.h>
#import "NSString+Ext.h"
#import "UIWindow+Ext.h"
#import "UIColor+Ext.h"

typedef NS_ENUM(NSInteger, VeterisAppCellSubtitleArea) {
    VeterisAppCellSubtitleAreaList = 0,
    VeterisAppCellSubtitleAreaSearch,
    VeterisAppCellSubtitleAreaRelated,
    VeterisAppCellSubtitleAreaQueue
};

static NSString *const VeterisAppCellSubtitleModeKey = @"app_cell_subtitle_mode";
static NSString *const VeterisAppCellSubtitleModeCustomValue = @"Custom";
static NSString *const VeterisAppCellSubtitleGlobalPreferenceKey = @"search_results_subtitle_preference";
static NSString *const VeterisAppCellSubtitleBundleIDValue = @"BundleID";
static NSString *const VeterisAppCellSubtitleDeveloperNameValue = @"DeveloperName";

static inline NSString *VeterisTrimmedString(NSString *string) {
    if (![string isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static inline NSString *VeterisAppCellSubtitlePreferenceKeyForArea(VeterisAppCellSubtitleArea area) {
    switch (area) {
        case VeterisAppCellSubtitleAreaList:
            return @"app_cell_subtitle_list_preference";
        case VeterisAppCellSubtitleAreaSearch:
            return @"app_cell_subtitle_search_preference";
        case VeterisAppCellSubtitleAreaRelated:
            return @"app_cell_subtitle_related_preference";
        case VeterisAppCellSubtitleAreaQueue:
            return @"app_cell_subtitle_queue_preference";
    }
    return nil;
}

static inline BOOL VeterisAppCellSubtitlePrefersBundleIDForArea(VeterisAppCellSubtitleArea area) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *mode = [defaults stringForKey:VeterisAppCellSubtitleModeKey];
    NSString *preference = nil;

    if ([mode isEqualToString:VeterisAppCellSubtitleModeCustomValue]) {
        preference = [defaults stringForKey:VeterisAppCellSubtitlePreferenceKeyForArea(area)];
        return [preference isEqualToString:VeterisAppCellSubtitleBundleIDValue];
    }

    preference = [defaults stringForKey:VeterisAppCellSubtitleGlobalPreferenceKey];
    return [preference isEqualToString:VeterisAppCellSubtitleBundleIDValue];
}

static inline NSString *VeterisAppCellSubtitle(NSString *developer, NSString *bundleID, VeterisAppCellSubtitleArea area) {
    NSString *trimmedBundleID = VeterisTrimmedString(bundleID);
    NSString *trimmedDeveloper = VeterisTrimmedString(developer);
    BOOL hasKnownDeveloper = ([trimmedDeveloper length] > 0 && ![[trimmedDeveloper lowercaseString] isEqualToString:@"unknown developer"]);

    if (VeterisAppCellSubtitlePrefersBundleIDForArea(area) && [trimmedBundleID length] > 0) {
        return trimmedBundleID;
    }
    if (hasKnownDeveloper) {
        return trimmedDeveloper;
    }
    return trimmedBundleID;
}
