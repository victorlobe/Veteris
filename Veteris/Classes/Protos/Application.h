#import "../../Protos/App.pb.h"
#import "../Protos/VTableResponse.pb.h"

@interface ApplicationInfoBlock : NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *body;
@property (nonatomic, strong) NSMutableArray *fields;
- (ApplicationInfoBlock *)initFromInfoBlockProto:(InfoBlockMsg)blockProto;
@end

@interface ApplicationInfoField : NSObject
@property (nonatomic, strong) NSString *label;
@property (nonatomic, strong) NSString *value;
- (ApplicationInfoField *)initFromInfoFieldProto:(InfoFieldMsg)fieldProto;
@end



@interface ApplicationScreenshot : NSObject
@property (nonatomic, strong) NSString *url;
@property (nonatomic, strong) NSString *retinaURL;
@property (nonatomic, assign) CGSize pixelSize;
- (ApplicationScreenshot *)initFromScreenshotProto:(ScreenshotMsg)screenshotProto;
@end

@interface Application : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *developer;
@property (nonatomic, strong) NSString *bundleid;
@property (nonatomic, strong) NSString *primaryBundleID;
@property (nonatomic, strong) NSString *category;
@property (nonatomic, strong) NSString *requiredOS;
@property (nonatomic, strong) NSString *deviceFamily;
@property (nonatomic, strong) NSString *archFlags;
@property (nonatomic, strong) NSString *backgroundModes;
@property (nonatomic, strong) NSString *executable;
@property (nonatomic, strong) NSString *releaseDate;
@property (nonatomic, strong) NSString *contentRating;
@property (nonatomic, strong) NSString *price;
@property (nonatomic, strong) NSString *subgenres;
@property (nonatomic, strong) NSString *copyrightText;
// "1" when set, empty otherwise (server only sends these flags when true)
@property (nonatomic, strong) NSString *gameCenter;
@property (nonatomic, strong) NSString *newsstand;
@property (nonatomic, strong) NSString *requiredCapabilities;
@property (nonatomic, strong) NSString *app_description;
@property (nonatomic, strong) NSMutableArray *customInfoBlocks;
@property (nonatomic, strong) NSString *websiteURL;
@property (nonatomic, strong) NSString *descriptionDate;
@property (nonatomic, strong) NSMutableArray *screenshots;
@property (nonatomic, strong) NSMutableArray *ipadScreenshots;
@property (nonatomic, strong) NSString *screenshotDate;
@property (nonatomic, strong) NSMutableArray *versions;
@property (nonatomic, strong) NSString *version; // Latest version
@property (nonatomic) NSUInteger versionCount;
@property (nonatomic, assign) unsigned long long downloadCount;
@property (nonatomic, assign) BOOL hasDownloadCount;
@property (nonatomic, strong) NSString *iconurl;
@property (nonatomic, strong) NSString *fallback_iconurl;
@property (nonatomic, strong) UIImage *icon;
@property bool nilIcon;
// VTableEntries are missing rich metadata like descriptions
@property (nonatomic) bool isVTableEntry;
@property (nonatomic, strong) NSString *updateBundleID;

- (Application *)initFromAppProto:(AppMsg)appProto;
- (Application *)initFromVTableEntryProto:(VTableEntryMsg)entry;
- (void)doGetIcon;
@end
