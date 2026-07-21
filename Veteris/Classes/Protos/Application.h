#import "../../Protos/App.pb.h"
#import "../Protos/VTableResponse.pb.h"

@interface Application : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *developer;
@property (nonatomic, strong) NSString *bundleid;
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
@property (nonatomic, strong) NSMutableArray *versions;
@property (nonatomic, strong) NSString *version; // Latest version
@property (nonatomic) NSUInteger versionCount;
@property (nonatomic, strong) NSString *iconurl;
@property (nonatomic, strong) NSString *fallback_iconurl;
@property (nonatomic, strong) UIImage *icon;
@property bool nilIcon;
// VTableEntries are missing rich metadata like descriptions
@property (nonatomic) bool isVTableEntry;

- (Application *)initFromAppProto:(AppMsg)appProto;
- (Application *)initFromVTableEntryProto:(VTableEntryMsg)entry;
- (void)doGetIcon;
@end
