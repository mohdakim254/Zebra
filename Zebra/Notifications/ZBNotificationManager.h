//
//  ZBNotificationManager.h
//  Zebra
//
//  Created by Arthur Chaloin on 06/06/2020.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

#ifndef ZBNotificationManager_h
#define ZBNotificationManager_h

@import UIKit;
@import UserNotifications;

#import <Tabs/Sources/Helpers/ZBSourceDelegate.h>
#import <Tabs/Packages/Helpers/ZBPackage.h>

typedef void (^BackgroundCompletionHandler)(UIBackgroundFetchResult);

typedef NSMutableArray<ZBPackage *> ZBPackageList;

@interface ZBNotificationManager : NSObject <ZBSourceDelegate, UNUserNotificationCenterDelegate>

- (void)ensureNotificationAccess;
- (void)performBackgroundFetch:(nonnull BackgroundCompletionHandler)completionHandler;
- (UIBackgroundFetchResult)notifyNewUpdatesBetween:(nonnull ZBPackageList *)oldUpdates newUpdates:(nonnull ZBPackageList *)newUpdates;
- (void)notifyUpdateForPackages:(nonnull ZBPackageList *)packages;
- (void)notify:(nonnull NSString *)body withTitle:(nonnull NSString *)title withUserInfo:(nonnull NSDictionary *)userInfo;

+ (nonnull instancetype)sharedInstance;

@end

#endif /* ZBNotificationManager_h */
