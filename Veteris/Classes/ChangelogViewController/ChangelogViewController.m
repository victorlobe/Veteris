#import "ChangelogViewController.h"

static NSString *const VeterisChangelogURL = @"http://repo.victorlobe.me/depictions/data/com.victorlobe.veteris/com.victorlobe.veteris.json";
static NSTimeInterval const VeterisChangelogTimeout = 20.0;
static CGFloat const VeterisChangelogNoteFontSize = 15.0f;
static CGFloat const VeterisChangelogNoteVerticalPadding = 11.0f;

typedef enum {
    VeterisChangelogStateLoading,
    VeterisChangelogStateLoaded,
    VeterisChangelogStateFailed
} VeterisChangelogState;

@implementation ChangelogViewController {
    VeterisChangelogState state;
    NSArray *entries;
}

- (NSString *)settingsString:(NSString *)key
{
    NSString *settingsBundlePath = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSBundle *settingsBundle = settingsBundlePath != nil ? [NSBundle bundleWithPath:settingsBundlePath] : nil;
    return NSLocalizedStringFromTableInBundle(key, @"Root", settingsBundle != nil ? settingsBundle : [NSBundle mainBundle], nil);
}

- (id)initWithFile:(NSString *)file withKey:(NSString *)key
{
    return [self initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = [self settingsString:@"Changelog"];
    [self loadChangelog];
}

#pragma mark - Loading

- (void)loadChangelog
{
    state = VeterisChangelogStateLoading;
    entries = nil;
    [self.tableView reloadData];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:VeterisChangelogURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:VeterisChangelogTimeout];
    __weak ChangelogViewController *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        ChangelogViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSArray *parsedEntries = nil;
        if (error == nil && statusCode >= 200 && statusCode < 300) {
            parsedEntries = [ChangelogViewController entriesFromData:data];
        }

        if ([parsedEntries count] > 0) {
            strongSelf->entries = parsedEntries;
            strongSelf->state = VeterisChangelogStateLoaded;
        } else {
            strongSelf->state = VeterisChangelogStateFailed;
        }
        [strongSelf.tableView reloadData];
    }];
}

+ (NSArray *)entriesFromData:(NSData *)data
{
    if ([data length] == 0) {
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    id changelog = [(NSDictionary *)json objectForKey:@"changelog"];
    if (![changelog isKindOfClass:[NSArray class]]) {
        return nil;
    }

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableArray *result = [NSMutableArray array];
    for (id item in (NSArray *)changelog) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        id version = [(NSDictionary *)item objectForKey:@"version"];
        NSString *versionString = [version isKindOfClass:[NSString class]] || [version isKindOfClass:[NSNumber class]] ? [[version description] stringByTrimmingCharactersInSet:whitespace] : @"";

        NSMutableArray *notes = [NSMutableArray array];
        id rawNotes = [(NSDictionary *)item objectForKey:@"notes"];
        if ([rawNotes isKindOfClass:[NSArray class]]) {
            for (id note in (NSArray *)rawNotes) {
                if (![note isKindOfClass:[NSString class]]) {
                    continue;
                }
                NSString *trimmed = [(NSString *)note stringByTrimmingCharactersInSet:whitespace];
                if ([trimmed length] > 0) {
                    [notes addObject:trimmed];
                }
            }
        }

        if ([versionString length] == 0 && [notes count] == 0) {
            continue;
        }
        [result addObject:@{@"version": versionString, @"notes": notes}];
    }

    return result;
}

#pragma mark - Layout

- (UIFont *)noteFont
{
    return [UIFont systemFontOfSize:VeterisChangelogNoteFontSize];
}

- (CGFloat)noteTextWidth
{
    CGFloat tableWidth = self.tableView.bounds.size.width;
    CGFloat horizontalInset;
    if (NSFoundationVersionNumber >= NSFoundationVersionNumber_iOS_7_0) {
        horizontalInset = 15.0f * 2.0f;
    } else {
        CGFloat groupMargin = tableWidth < 400.0f ? 10.0f : MAX(31.0f, MIN(45.0f, floorf(tableWidth * 0.06f)));
        horizontalInset = (groupMargin + 10.0f) * 2.0f;
    }
    return MAX(tableWidth - horizontalInset - 4.0f, 100.0f);
}

- (NSString *)messageText
{
    return state == VeterisChangelogStateLoading ? [self settingsString:@"Loading..."] : [self settingsString:@"The changelog could not be loaded."];
}

- (NSString *)noteAtIndexPath:(NSIndexPath *)indexPath
{
    if (state != VeterisChangelogStateLoaded) {
        return indexPath.row == 0 ? [self messageText] : nil;
    }

    NSArray *notes = [[entries objectAtIndex:indexPath.section] objectForKey:@"notes"];
    return [notes objectAtIndex:indexPath.row];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return state == VeterisChangelogStateLoaded ? [entries count] : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (state) {
        case VeterisChangelogStateLoading:
            return 1;
        case VeterisChangelogStateFailed:
            return 2;
        case VeterisChangelogStateLoaded:
            return [[[entries objectAtIndex:section] objectForKey:@"notes"] count];
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (state != VeterisChangelogStateLoaded) {
        return nil;
    }

    NSString *version = [[entries objectAtIndex:section] objectForKey:@"version"];
    if ([version length] == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@ %@", [self settingsString:@"Version"], version];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *text = [self noteAtIndexPath:indexPath];
    if (text == nil) {
        return tableView.rowHeight;
    }

    CGSize textSize = [text sizeWithFont:[self noteFont]
                       constrainedToSize:CGSizeMake([self noteTextWidth], CGFLOAT_MAX)
                           lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(44.0f, ceilf(textSize.height + VeterisChangelogNoteVerticalPadding * 2.0f));
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (state == VeterisChangelogStateFailed && indexPath.row == 1) {
        static NSString *const RetryCellIdentifier = @"ChangelogRetryCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:RetryCellIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:RetryCellIdentifier];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
        cell.textLabel.text = [self settingsString:@"Try Again"];
        return cell;
    }

    static NSString *const NoteCellIdentifier = @"ChangelogNoteCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NoteCellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:NoteCellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [self noteFont];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    cell.textLabel.text = [self noteAtIndexPath:indexPath];
    if (state == VeterisChangelogStateLoading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [spinner startAnimating];
        cell.accessoryView = spinner;
    } else {
        cell.accessoryView = nil;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (state == VeterisChangelogStateFailed && indexPath.row == 1) {
        [self loadChangelog];
    }
}

@end
