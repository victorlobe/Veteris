#import "../../Protos/App.pb.h"

@interface Version : NSObject
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *fileName;
@property (nonatomic, strong) NSString *minVersion;
@property (nonatomic, assign) unsigned long long sizeBytes;
@property (nonatomic, strong) NSString *buildVersion;
@property (nonatomic, strong) NSString *platform;
@property (nonatomic, strong) NSString *sourceItem;
@property (nonatomic, strong) NSString *sourceFile;
@property (nonatomic, strong) NSString *sha1;
@property (nonatomic, strong) NSString *md5;
@property (nonatomic, strong) NSString *fairplayStatus;
@property (nonatomic, strong) NSString *archFlags;
@property (nonatomic, strong) NSString *backgroundModes;
@property (nonatomic, strong) NSString *executable;
@property (nonatomic, strong) NSString *releaseDate;
@property (nonatomic, strong) NSString *contentRating;
@property (nonatomic, strong) NSString *price;
@property (nonatomic, strong) NSString *subgenres;
@property (nonatomic, strong) NSString *copyrightText;
@property (nonatomic, strong) NSString *gameCenter;
@property (nonatomic, strong) NSString *newsstand;
@property (nonatomic, strong) NSString *requiredCapabilities;
@property (nonatomic, strong) NSString *metadataSource;
@property (nonatomic, strong) NSString *iconPath;
@property (nonatomic, strong) NSString *iconBundleID;
@property (nonatomic, strong) NSString *bundleID;
@property (nonatomic, assign) BOOL recommended;
- (Version *)initFromVersionProto:(VersionMsg)versionProto;
@end
