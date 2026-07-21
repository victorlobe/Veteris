//
//  AppCellSubtitleSettingsViewController.m
//  Veteris
//
//  Created by Victor on 01.07.26.
//  Copyright (c) 2026 Victor Lobe. All rights reserved.
//

#import "AppCellSubtitleSettingsViewController.h"
#import "Convenience.h"

@implementation AppCellSubtitleSettingsViewController {
    UISegmentedControl *modeControl;
}

static CGFloat const VeterisAppSubtitleModeControlInset = 10.0f;

- (UIView *)clearCellBackgroundView
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [UIColor clearColor];
    return view;
}

- (NSString *)settingsString:(NSString *)key
{
    NSString *settingsBundlePath = [[NSBundle mainBundle] pathForResource:@"Settings" ofType:@"bundle"];
    NSBundle *settingsBundle = settingsBundlePath != nil ? [NSBundle bundleWithPath:settingsBundlePath] : nil;
    return NSLocalizedStringFromTableInBundle(key, @"Root", settingsBundle != nil ? settingsBundle : [NSBundle mainBundle], nil);
}

- (void)centerModeControlInCell:(UITableViewCell *)cell
{
    CGRect modeFrame = modeControl.frame;
    CGFloat contentWidth = cell.contentView.bounds.size.width;
    CGFloat contentHeight = cell.contentView.bounds.size.height;
    CGFloat inset = VeterisAppSubtitleModeControlInset;

    if (contentWidth <= 0.0f) {
        contentWidth = cell.bounds.size.width;
    }
    if (contentHeight <= 0.0f) {
        contentHeight = 44.0f;
    }

    if (contentWidth > inset * 2.0f + modeFrame.size.width) {
        modeFrame.size.width = floor(contentWidth - inset * 2.0f);
    }
    modeFrame.origin.x = floor((contentWidth - modeFrame.size.width) / 2.0f);
    modeFrame.origin.y = floor((contentHeight - modeFrame.size.height) / 2.0f);
    modeControl.frame = modeFrame;
}

- (id)initWithFile:(NSString *)file withKey:(NSString *)key
{
    return [self initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = [self settingsString:@"App Subtitles"];

    modeControl = [[UISegmentedControl alloc] initWithItems:@[[self settingsString:@"All"], [self settingsString:@"Custom"]]];
    [modeControl sizeToFit];
    modeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateModeControl];
    [self.tableView reloadData];
}

- (BOOL)usesCustomMode
{
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:VeterisAppCellSubtitleModeKey];
    return [mode isEqualToString:VeterisAppCellSubtitleModeCustomValue];
}

- (void)updateModeControl
{
    modeControl.selectedSegmentIndex = [self usesCustomMode] ? 1 : 0;
}

- (void)storePreferenceValue:(NSString *)value forKey:(NSString *)key
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:value forKey:key];
    [defaults synchronize];
}

- (void)modeChanged:(UISegmentedControl *)sender
{
    NSString *mode = sender.selectedSegmentIndex == 1 ? VeterisAppCellSubtitleModeCustomValue : @"Global";
    [self storePreferenceValue:mode forKey:VeterisAppCellSubtitleModeKey];
    [self.tableView reloadData];
}

- (NSString *)preferenceKeyForSection:(NSInteger)section
{
    if (![self usesCustomMode]) {
        return VeterisAppCellSubtitleGlobalPreferenceKey;
    }

    return VeterisAppCellSubtitlePreferenceKeyForArea((VeterisAppCellSubtitleArea)(section - 1));
}

- (NSString *)titleForPreferenceSection:(NSInteger)section
{
    if (![self usesCustomMode]) {
        return [self settingsString:@"Subtitle"];
    }

    NSArray *titles = @[[self settingsString:@"Browse"], [self settingsString:@"Search"], [self settingsString:@"Related"], [self settingsString:@"Queue"]];
    return [titles objectAtIndex:section - 1];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self usesCustomMode] ? 5 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return 1;
    }

    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        return [self settingsString:@"Apply To"];
    }

    return [self titleForPreferenceSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        static NSString *const ModeCellIdentifier = @"SubtitleModeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ModeCellIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ModeCellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor clearColor];
            cell.contentView.backgroundColor = [UIColor clearColor];
            cell.backgroundView = [self clearCellBackgroundView];
            cell.selectedBackgroundView = [self clearCellBackgroundView];
        }

        cell.textLabel.text = nil;
        [self updateModeControl];
        [self centerModeControlInCell:cell];
        [cell.contentView addSubview:modeControl];
        return cell;
    }

    static NSString *const CellIdentifier = @"SubtitleChoiceCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }

    BOOL bundleID = indexPath.row == 1;
    NSString *preference = [[NSUserDefaults standardUserDefaults] stringForKey:[self preferenceKeyForSection:indexPath.section]];
    if (preference == nil) {
        preference = VeterisAppCellSubtitleDeveloperNameValue;
    }

    cell.textLabel.text = bundleID ? [self settingsString:@"Bundle ID"] : [self settingsString:@"Developer Name"];
    cell.accessoryType = [preference isEqualToString:(bundleID ? VeterisAppCellSubtitleBundleIDValue : VeterisAppCellSubtitleDeveloperNameValue)] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
        cell.backgroundView = [self clearCellBackgroundView];
        cell.selectedBackgroundView = [self clearCellBackgroundView];
        [self centerModeControlInCell:cell];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return;
    }

    NSString *value = indexPath.row == 1 ? VeterisAppCellSubtitleBundleIDValue : VeterisAppCellSubtitleDeveloperNameValue;
    [self storePreferenceValue:value forKey:[self preferenceKeyForSection:indexPath.section]];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
