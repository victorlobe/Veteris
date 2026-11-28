#import "YZZipArchive.h"
#import "zip/zip.h"
#import "../VAPIHelper/VAPIHelper.h"

static NSString *YZZipEntryNameString(const char *name) {
    if (name == NULL) {
        return nil;
    }
    NSString *string = [NSString stringWithUTF8String:name];
    if (string == nil) {
        NSStringEncoding cp437 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSLatinUS);
        string = [NSString stringWithCString:name encoding:cp437];
    }
    if (string == nil) {
        string = [NSString stringWithCString:name encoding:NSISOLatin1StringEncoding];
    }
    return string;
}

@implementation YZZipArchive {
    struct zip_t *zip;
    NSMutableDictionary *entryIndexes;
}
+ (YZZipArchive *)open:(NSString *)path {
    YZZipArchive *archive = [[YZZipArchive alloc] init];
    int err = 0;
    archive->zip = zip_openwitherror([path UTF8String], 0, 'r', &err);
    if (err != 0) {
        debugLog(@"[YZZipArchive] Failed to open archive: %s", zip_strerror(err));
        return nil;
    }
    return archive;
}

- (NSData *)readFile:(NSString *)path {
    void *buf = NULL;
    size_t bufsize = 0;
    NSNumber *index = (path != nil) ? [entryIndexes objectForKey:path] : nil;
    int opened = (index != nil) ? zip_entry_openbyindex(zip, [index unsignedIntegerValue])
                                : zip_entry_open(zip, [path UTF8String]);
    if (opened < 0) {
        return nil;
    }
    zip_entry_read(zip, &buf, &bufsize);
    zip_entry_close(zip);
    if (buf == NULL || bufsize == 0) {
        return nil;
    }
    NSData *data = [NSData dataWithBytes:buf length:bufsize];
    free(buf);
    return data;
}

- (NSArray *)files {
    ssize_t n = zip_entries_total(zip);
    if (n < 0) {
        return nil;
    }
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    entryIndexes = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)n];
    for (ssize_t i = 0; i < n; ++i) {
        if (zip_entry_openbyindex(zip, (size_t)i) < 0) {
            continue;
        }
        NSString *name = YZZipEntryNameString(zip_entry_name(zip));
        zip_entry_close(zip);
        if (name == nil) {
            continue;
        }
        [files addObject:name];
        [entryIndexes setObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)i] forKey:name];
    }
    return files;
}

- (void)close {
    if (zip != NULL) {
        zip_close(zip);
        zip = NULL; // Prevent double close or accessing invalid memory
    }
}

- (void)dealloc {
    [self close];
}
@end