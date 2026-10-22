#import <Foundation/Foundation.h>

extern NSString *const YZArchiveTLSErrorDomain;

@interface YZArchiveTLSResult : NSObject
@property (nonatomic, assign) NSUInteger statusCode;
@property (nonatomic, retain) NSDictionary *headers;
@property (nonatomic, retain) NSError *error;
@property (nonatomic, copy) NSString *finalURL;
@property (nonatomic, assign) BOOL cancelled;
@end

@interface YZArchiveTLSDownloader : NSObject
- (instancetype)initWithURL:(NSString *)url
                 targetPath:(NSString *)targetPath
               resumeOffset:(unsigned long long)resumeOffset
                    headers:(NSDictionary *)headers
                   progress:(void (^)(unsigned long long current, unsigned long long total))progress
                 completion:(void (^)(YZArchiveTLSResult *result))completion;
@property (copy) void (^finishingBlock)(unsigned long long total);
- (void)start;
- (void)cancel;
@end
