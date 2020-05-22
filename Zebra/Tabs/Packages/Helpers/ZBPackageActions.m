//
//  ZBPackageActions.m
//  Zebra
//
//  Created by Thatchapon Unprasert on 13/5/2019
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBPackageActions.h"
#import "ZBPackage.h"

#import <ZBDevice.h>
#import <ZBAppDelegate.h>
#import <Headers/UIAlertController+Private.h>
#import <Sources/Helpers/ZBSource.h>
#import <Packages/Views/ZBPackageTableViewCell.h>
#import <Packages/Controllers/ZBPackageViewController.h>
#import <Queue/ZBQueue.h>
#import <UIColor+GlobalColors.h>
#import <Packages/Controllers/ZBPackageListTableViewController.h>
#import <Extensions/UIAlertController+Show.h>
#import <JSONParsing/ZBPurchaseInfo.h>

@implementation ZBPackageActions

#pragma mark - Package Actions

+ (UIAlertControllerStyle)alertControllerStyle {
    return [[ZBDevice deviceType] isEqualToString:@"iPad"] ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet;
}

+ (void)performExtraAction:(ZBPackageExtraActionType)action forPackage:(ZBPackage *)package completion:(void (^)(ZBPackageExtraActionType action))completion {
    switch (action) {
        case ZBPackageExtraActionShowUpdates:
            [self showUpdatesFor:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionHideUpdates:
            [self hideUpdatesFor:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionAddWishlist:
            [self addToWishlist:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionRemoveWishlist:
            [self removeFromWishlist:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionBlockAuthor:
            [self blockAuthorOf:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionUnblockAuthor:
            [self unblockAuthorOf:package];
            if (completion) completion(action);
            break;
        case ZBPackageExtraActionShare:
            if (completion) completion(action);
            break;
    }
}

+ (void)performAction:(ZBPackageActionType)action forPackages:(NSArray <ZBPackage *> *)packages completion:(void (^)(void))completion {
    dispatch_group_t group = dispatch_group_create();
    
    for (ZBPackage *package in packages) {
        dispatch_group_enter(group);
        [self performAction:action forPackage:package completion:^{
            dispatch_group_leave(group);
        }];
    }
    
    dispatch_group_notify(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
        if (completion) completion();
    });
}

+ (void)performAction:(ZBPackageActionType)action forPackage:(ZBPackage *)package completion:(void (^)(void))completion {
    [self performAction:action forPackage:package checkPayment:YES completion:completion];
}

+ (void)performAction:(ZBPackageActionType)action forPackage:(ZBPackage *)package checkPayment:(BOOL)checkPayment completion:(void (^)(void))completion {
    if (!package) return;
    if (action < ZBPackageActionInstall || action > ZBPackageActionSelectVersion) return;
    
    if (checkPayment && action != ZBPackageActionRemove && [package mightRequirePayment]) { // No need to check for authentication on show/hide updates
        [package purchaseInfo:^(ZBPurchaseInfo * _Nonnull info) {
            if (info && info.purchased && info.available) { // Either the package does not require authorization OR the package is purchased and available.
                [self performAction:action forPackage:package checkPayment:NO completion:completion];
            }
            else if (!info.available) { // Package isn't available.
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Package not available", @"") message:NSLocalizedString(@"This package is no longer for sale and cannot be downloaded.", @"") preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleDefault handler:nil];
                [alert addAction:ok];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [alert show];
                });
            }
            else if (!info.purchased) { // Package isn't purchased, purchase it.
                [package purchase:^(BOOL success, NSError * _Nullable error) {
                    if (success && !error) {
                        [self performAction:action forPackage:package completion:completion];
                    }
                    else if (error) {
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Unable to complete purchase", @"") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                        
                        UIAlertAction *ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleDefault handler:nil];
                        [alert addAction:ok];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [alert show];
                        });
                    }
                }];
            }
            else { // Fall-through, this will not check for payment info again.
                [self performAction:action forPackage:package checkPayment:NO completion:completion];
            }
        }];
        return;
    }
    
    switch (action) {
        case ZBPackageActionInstall:
            [self install:package completion:completion];
            break;
        case ZBPackageActionRemove:
            [self remove:package completion:completion];
            break;
        case ZBPackageActionReinstall:
            [self reinstall:package completion:completion];
            break;
        case ZBPackageActionUpgrade:
            [self upgrade:package completion:completion];
            break;
        case ZBPackageActionDowngrade:
            [self downgrade:package completion:completion];
            break;
        case ZBPackageActionSelectVersion:
            [self choose:package completion:completion];
            break;
    }
}

+ (void)install:(ZBPackage *)package completion:(void (^)(void))completion {
    [[ZBQueue sharedQueue] addPackage:package toQueue:ZBQueueTypeInstall];
    if (completion) completion();
}

+ (void)remove:(ZBPackage *)package completion:(void (^)(void))completion {
    [[ZBQueue sharedQueue] addPackage:package toQueue:ZBQueueTypeRemove];
    if (completion) completion();
}

+ (void)reinstall:(ZBPackage *)package completion:(void (^)(void))completion {
    [[ZBQueue sharedQueue] addPackage:package toQueue:ZBQueueTypeReinstall];
    if (completion) completion();
}

+ (void)choose:(ZBPackage *)package completion:(void (^)(void))completion {
    NSMutableArray *allVersions = [package allVersions];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Version", @"") message:NSLocalizedString(@"Select a version to install:", @"") preferredStyle:[self alertControllerStyle]];
    
    NSCountedSet *versionStrings = [NSCountedSet new];
    for (ZBPackage *otherPackage in allVersions) {
        [versionStrings addObject:[otherPackage version]];
    }
    
    for (ZBPackage *otherPackage in allVersions) {
        NSString *title = [self determinePackageTitle:otherPackage versionStrings:versionStrings withLatest:otherPackage == allVersions[0]];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [otherPackage setRequiresAuthorization:[package requiresAuthorization]];
            [[ZBQueue sharedQueue] addPackage:otherPackage toQueue:ZBQueueTypeInstall];
            
            if (completion) completion();
        }];
        
        [alert addAction:action];
    }
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];
    [alert _setIndexesOfActionSectionSeparators:[NSIndexSet indexSetWithIndex:1]];
    
    [alert show];
}

+ (void)upgrade:(ZBPackage *)package completion:(void (^)(void))completion {
    NSMutableArray *greaterVersions = [package greaterVersions];
    if ([greaterVersions count] > 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Version", @"") message:NSLocalizedString(@"Select a version to upgrade to:", @"") preferredStyle:[self alertControllerStyle]];
        
        NSCountedSet *versionStrings = [NSCountedSet new];
        for (ZBPackage *otherPackage in greaterVersions) {
            [versionStrings addObject:[otherPackage version]];
        }
        
        for (ZBPackage *otherPackage in greaterVersions) {
            NSString *title = [self determinePackageTitle:otherPackage versionStrings:versionStrings withLatest:NO];
            UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [otherPackage setRequiresAuthorization:[package requiresAuthorization]];
                [[ZBQueue sharedQueue] addPackage:otherPackage toQueue:ZBQueueTypeUpgrade];
                
                if (completion) completion();
            }];
            
            [alert addAction:action];
        }
        
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];
        
        [alert show];
    }
    else {
        ZBPackage *upgrade = [greaterVersions count] == 1 ? greaterVersions[0] : package;
        [[ZBQueue sharedQueue] addPackage:upgrade toQueue:ZBQueueTypeUpgrade];
        
        if (completion) completion();
    }
}

+ (void)downgrade:(ZBPackage *)package completion:(void (^)(void))completion {
    NSMutableArray *lesserVersions = [package lesserVersions];
    if ([lesserVersions count] > 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Version", @"") message:NSLocalizedString(@"Select a version to downgrade to:", @"") preferredStyle:[self alertControllerStyle]];
        
        NSCountedSet *versionStrings = [NSCountedSet new];
        for (ZBPackage *otherPackage in lesserVersions) {
            [versionStrings addObject:[otherPackage version]];
        }
        
        for (ZBPackage *otherPackage in lesserVersions) {
            if ([[otherPackage source] sourceID] < 1) continue;
            
            NSString *title = [self determinePackageTitle:otherPackage versionStrings:versionStrings withLatest:NO];
            UIAlertAction *action = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [otherPackage setRequiresAuthorization:[package requiresAuthorization]];
                [[ZBQueue sharedQueue] addPackage:otherPackage toQueue:ZBQueueTypeDowngrade];
                if (completion) completion();
            }];
            
            [alert addAction:action];
        }
        
        UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:cancel];
        
        [alert show];
    }
    else {
        ZBPackage *upgrade = [lesserVersions count] == 1 ? lesserVersions[0] : package;
        [[ZBQueue sharedQueue] addPackage:upgrade toQueue:ZBQueueTypeDowngrade];
        
        if (completion) completion();
    }
}

+ (void)showUpdatesFor:(ZBPackage *)package {
    [package setIgnoreUpdates:NO];
}

+ (void)hideUpdatesFor:(ZBPackage *)package {
    [package setIgnoreUpdates:YES];
}

+ (void)addToWishlist:(ZBPackage *)package {
    NSMutableArray *wishList = [[ZBSettings wishlist] mutableCopy];
    BOOL inWishList = [wishList containsObject:package.identifier];
    if (!inWishList) {
        [wishList addObject:package.identifier];
    }
    [ZBSettings setWishlist:wishList];
}

+ (void)removeFromWishlist:(ZBPackage *)package {
    NSMutableArray *wishList = [[ZBSettings wishlist] mutableCopy];
    BOOL inWishList = [wishList containsObject:package.identifier];
    if (inWishList) {
        [wishList removeObject:package.identifier];
    }
    [ZBSettings setWishlist:wishList];
}

+ (void)blockAuthorOf:(ZBPackage *)package {
    NSMutableDictionary *blockedAuthors = [[ZBSettings blockedAuthors] mutableCopy];
    
    [blockedAuthors setObject:[package authorName] forKey:[package authorEmail]];
    
    [ZBSettings setBlockedAuthors:blockedAuthors];
}

+ (void)unblockAuthorOf:(ZBPackage *)package {
    NSMutableDictionary *blockedAuthors = [[ZBSettings blockedAuthors] mutableCopy];
    
    [blockedAuthors removeObjectForKey:[package authorName]];
    [blockedAuthors removeObjectForKey:[package authorEmail]];
    
    [ZBSettings setBlockedAuthors:blockedAuthors];
}

+ (void)share:(ZBPackage *)package {
    // Likely implement later, gets a bit complicated due to presentation
}

#pragma mark - Display Actions

+ (void)buttonTitleForPackage:(ZBPackage *)package completion:(void (^)(NSString * _Nullable title))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *title = [self buttonTitleForPackage:package];
        if ([package mightRequirePayment]) {
            [package purchaseInfo:^(ZBPurchaseInfo * _Nonnull info) {
                if (info) { // Package does have purchase info
                    BOOL installed = [package isInstalled:NO];
                    if (!info.purchased && !installed) { // If the user has not purchased the package
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(info.price);
                        });
                        return;
                    }
                    else if (info.purchased && !installed) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(@"Install");
                        });
                        return;
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(title);
                });
                return;
            }];
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(title);
        });
    });
}

+ (void (^)(void))buttonActionForPackage:(ZBPackage *)package {
    NSArray <NSNumber *> *actions = [package possibleActions];
    if ([actions count] > 1) {
        return ^{
            UIAlertController *selectAction = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ (%@)", package.name, package.version] message:nil preferredStyle:[self alertControllerStyle]];

            for (UIAlertAction *action in [ZBPackageActions alertActionsForPackage:package]) {
                    [selectAction addAction:action];
            }

            [selectAction show];
        };
    }
    else {
        return ^{
            // If the user has pressed the bar button twice (i.e. the same package is already in the Queue, present it
            ZBPackageActionType action = actions[0].intValue;
            if ([[ZBQueue sharedQueue] contains:package inQueue:[self actionToQueue:action]]) {
                [[ZBAppDelegate tabBarController] openQueue:YES];
            }
            else {
                [self performAction:action forPackage:package completion:nil];
            }
        };
    }
}

+ (NSArray <UITableViewRowAction *> *)rowActionsForPackage:(ZBPackage *)package inTableView:(UITableView *)tableView {
    NSMutableArray *rowActions = [NSMutableArray new];
    
    NSArray *actions = [package possibleActions];
    for (NSNumber *number in actions) {
        ZBPackageActionType action = number.intValue;
        
        NSString *title = [self titleForAction:action useIcon:YES];
        UITableViewRowActionStyle style = action == ZBPackageActionRemove ? UITableViewRowActionStyleDestructive : UITableViewRowActionStyleNormal;
        UITableViewRowAction *rowAction = [UITableViewRowAction rowActionWithStyle:style title:title handler:^(UITableViewRowAction *rowAction, NSIndexPath *indexPath) {
            [self performAction:action forPackage:package completion:^{
                if (tableView) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [tableView reloadRowsAtIndexPaths:[tableView indexPathsForVisibleRows] withRowAnimation:UITableViewRowAnimationNone];
                    });
                }
            }];
        }];
        
        rowAction.backgroundColor = [self colorForAction:action];
        [rowActions addObject:rowAction];
    }
    
    return rowActions;
}

+ (NSArray <UIAlertAction *> *)alertActionsForPackage:(ZBPackage *)package {
    NSMutableArray <UIAlertAction *> *alertActions = [NSMutableArray new];
    
    NSArray *actions = [package possibleActions];
    for (NSNumber *number in actions) {
        ZBPackageActionType action = number.intValue;
        
        NSString *title = [self titleForAction:action useIcon:NO];
        UIAlertActionStyle style = action == ZBPackageActionRemove ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
        UIAlertAction *alertAction = [UIAlertAction actionWithTitle:title style:style handler:^(UIAlertAction *alertAction) {
            [self performAction:action forPackage:package completion:nil];
        }];
        [alertActions addObject:alertAction];
    }
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:NULL];
    [alertActions addObject:cancel];
    
    return alertActions;
}

+ (NSArray <UIAlertAction *> *)extraAlertActionsForPackage:(ZBPackage *)package selectionCallback:(void (^)(ZBPackageExtraActionType action))callback {
    NSMutableArray <UIAlertAction *> *alertActions = [NSMutableArray new];
    
    NSArray *actions = [package possibleExtraActions];
    for (NSNumber *number in actions) {
        ZBPackageExtraActionType action = number.intValue;
        
        NSString *title = [self titleForExtraAction:action];
        UIAlertAction *alertAction = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *alertAction) {
            [self performExtraAction:action forPackage:package completion:callback];
        }];
        [alertActions addObject:alertAction];
    }
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:NULL];
    [alertActions addObject:cancel];
    
    return alertActions;
}

+ (NSArray <UIPreviewAction *> *)previewActionsForPackage:(ZBPackage *)package inTableView:(UITableView *_Nullable)tableView {
    NSMutableArray <UIPreviewAction *> *previewActions = [NSMutableArray new];
    
    NSArray *actions = [package possibleActions];
    for (NSNumber *number in actions) {
        ZBPackageActionType action = number.intValue;
        
        NSString *title = [self titleForAction:action useIcon:NO];
        UIPreviewActionStyle style = action == ZBPackageActionRemove ? UIPreviewActionStyleDestructive : UIPreviewActionStyleDefault;
        UIPreviewAction *previewAction = [UIPreviewAction actionWithTitle:title style:style handler:^(UIPreviewAction *previewAction, UIViewController *previewViewController) {
            [self performAction:action forPackage:package completion:^{
                if (tableView) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [tableView reloadRowsAtIndexPaths:[tableView indexPathsForVisibleRows] withRowAnimation:UITableViewRowAnimationNone];
                    });
                }
            }];
        }];
        
        [previewActions addObject:previewAction];
    }
    
    return previewActions;
}

+ (NSArray <UIAction *> *)menuElementsForPackage:(ZBPackage *)package inTableView:(UITableView *_Nullable)tableView API_AVAILABLE(ios(13.0)) {
    NSMutableArray <UIAction *> *uiActions = [NSMutableArray new];
    
    NSArray *actions = [package possibleActions];
    for (NSNumber *number in actions) {
        ZBPackageActionType action = number.intValue;
        
        NSString *title = [self titleForAction:action useIcon:NO];
        UIImage *image = [self systemImageForAction:action];
        
        UIAction *uiAction = [UIAction actionWithTitle:title image:image identifier:nil handler:^(__kindof UIAction *uiAction) {
            [self performAction:action forPackage:package completion:^{
                if (tableView) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [tableView reloadRowsAtIndexPaths:[tableView indexPathsForVisibleRows] withRowAnimation:UITableViewRowAnimationNone];
                    });
                }
            }];
        }];
        [uiActions addObject:uiAction];
    }
    
    return uiActions;
}

#pragma mark - Displaying Actions to User

+ (UIColor *)colorForAction:(ZBPackageActionType)action {
    switch (action) {
        case ZBPackageActionInstall:
        case ZBPackageActionSelectVersion:
            return [UIColor systemTealColor];
        case ZBPackageActionRemove:
            return [UIColor systemPinkColor];
        case ZBPackageActionReinstall:
            return [UIColor systemOrangeColor];
        case ZBPackageActionUpgrade:
            return [UIColor systemBlueColor];
        case ZBPackageActionDowngrade:
            return [UIColor systemPurpleColor];
        default:
            return nil;
    }
}

+ (UIImage *)systemImageForAction:(ZBPackageActionType)action API_AVAILABLE(ios(13.0)) {
    NSString *imageName;
    switch (action) {
        case ZBPackageActionInstall:
        case ZBPackageActionSelectVersion:
            imageName = @"icloud.and.arrow.down";
            break;
        case ZBPackageActionRemove:
            imageName = @"trash";
            break;
        case ZBPackageActionReinstall:
            imageName = @"arrow.clockwise";
            break;
        case ZBPackageActionUpgrade:
            imageName = @"arrow.up";
            break;
        case ZBPackageActionDowngrade:
            imageName = @"arrow.down";
            break;
    }
    
    UIImageSymbolConfiguration *imgConfig = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightHeavy];
    return [UIImage systemImageNamed:imageName withConfiguration:imgConfig];
}

+ (NSString *)titleForAction:(ZBPackageActionType)action useIcon:(BOOL)icon {
    BOOL useIcon = icon && [ZBDevice useIcon];
    
    switch (action) {
        case ZBPackageActionInstall:
        case ZBPackageActionSelectVersion:
            return useIcon ? @"⇩" : NSLocalizedString(@"Free", @"");
        case ZBPackageActionRemove:
            return useIcon ? @"╳" : NSLocalizedString(@"Remove", @"");
        case ZBPackageActionReinstall:
            return useIcon ? @"↺" : NSLocalizedString(@"Reinstall", @"");
        case ZBPackageActionUpgrade:
            return useIcon ? @"↑" : NSLocalizedString(@"Upgrade", @"");
        case ZBPackageActionDowngrade:
            return useIcon ? @"↓" : NSLocalizedString(@"Downgrade", @"");
        default:
            break;
    }
    return @"Undefined";
}

+ (NSString *)titleForExtraAction:(ZBPackageExtraActionType)action {
    switch (action) {
        case ZBPackageExtraActionShowUpdates:
            return NSLocalizedString(@"Show Updates", @"");
        case ZBPackageExtraActionHideUpdates:
            return NSLocalizedString(@"Hide Updates", @"");
        case ZBPackageExtraActionAddWishlist:
            return NSLocalizedString(@"Add to Wishlist", @"");
        case ZBPackageExtraActionRemoveWishlist:
            return NSLocalizedString(@"Remove from Wishlist", @"");
        case ZBPackageExtraActionBlockAuthor:
            return NSLocalizedString(@"Block Author", @"");
        case ZBPackageExtraActionUnblockAuthor:
            return NSLocalizedString(@"Unblock Author", @"");
        case ZBPackageExtraActionShare:
            return NSLocalizedString(@"Share Package", @"");
        default:
            return @"Undefined";
    }
}

+ (NSString *)buttonTitleForPackage:(ZBPackage *)package {
    NSArray <NSNumber *> *actions = [package possibleActions];
    if ([actions count] > 1) {
        return NSLocalizedString(@"Modify", @"");
    }
    else {
        ZBPackageActionType action = actions[0].intValue;
        return [self titleForAction:action useIcon:NO];
    }
}

+ (ZBQueueType)actionToQueue:(ZBPackageActionType)action {
    switch (action) {
        case ZBPackageActionInstall:
            return ZBQueueTypeInstall;
        case ZBPackageActionRemove:
            return ZBQueueTypeRemove;
        case ZBPackageActionReinstall:
            return ZBQueueTypeReinstall;
        case ZBPackageActionDowngrade:
            return ZBQueueTypeDowngrade;
        case ZBPackageActionUpgrade:
            return ZBQueueTypeUpgrade;
        case ZBPackageActionSelectVersion:
            return ZBQueueTypeInstall;
        default:
            return ZBQueueTypeClear;
    }
}

+ (NSString *)determinePackageTitle:(ZBPackage *)package versionStrings:(NSCountedSet *)versionStrings withLatest:(BOOL)latest {
    NSString *versionString = latest ? [NSString stringWithFormat:@"%@ (%@)", NSLocalizedString(@"Latest", @""), [package version]] : [package version];
    return [versionStrings countForObject:[package version]] > 1 ? [NSString stringWithFormat:@"%@ (%@)", versionString, [[package source] label]] : versionString;
}

@end
