#import <UIKit/UIKit.h>
#import "../../Protos/Suggestions.pb.h"

@interface Suggestion : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *bundleid;
@property (nonatomic, strong) NSString *developer;
@property (nonatomic, strong) NSString *iconurl;
@property (nonatomic, strong) NSString *fallback_iconurl;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic) BOOL nilIcon;
@property (nonatomic) NSUInteger versionCount;
- (Suggestion *)initFromSuggestionProto:(SuggestionMsg)proto;
@end
