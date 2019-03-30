//
//  ZBQueueViewController.m
//  Zebra
//
//  Created by Wilson Styres on 1/30/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBQueue.h"
#import <Packages/Helpers/ZBPackage.h>
#import <Console/ZBConsoleViewController.h>

@interface ZBQueueViewController () {
    ZBQueue *_queue;
}

@end

@implementation ZBQueueViewController

- (void)loadView {
    [super loadView];
    
    _queue = [ZBQueue sharedInstance];
    
    if ([[_queue failedQueue] count] > 0) {
        self.navigationItem.rightBarButtonItem.enabled = false;
    }
    else {
        self.navigationItem.rightBarButtonItem.enabled = true;
    }
    
    self.title = @"Queue";
}

- (IBAction)confirm:(id)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle: nil];
    ZBConsoleViewController *vc = [storyboard instantiateViewControllerWithIdentifier:@"consoleViewController"];
    [[self navigationController] pushViewController:vc animated:true];
}

- (IBAction)cancel:(id)sender {
    //    AUPMTabBarController *tabController = (AUPMTabBarController *)((AUPMAppDelegate *)[[UIApplication sharedApplication] delegate]).window.rootViewController;
    //    [tabController updatePackageTableView];
    //
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)refreshTable {
    if ([[_queue failedQueue] count] > 0) {
        self.navigationItem.rightBarButtonItem.enabled = false;
    }
    else {
        self.navigationItem.rightBarButtonItem.enabled = true;
    }
    
    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[_queue actionsToPerform] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *action = [[_queue actionsToPerform] objectAtIndex:section];
    return [_queue numberOfPackagesForQueue:action];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [[_queue actionsToPerform] objectAtIndex:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"QueuePackageTableViewCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    NSString *action = [[_queue actionsToPerform] objectAtIndex:indexPath.section];
    ZBPackage *package;
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    
    cell.backgroundColor = [UIColor whiteColor];
    if ([action isEqual:@"Install"]) {
        package = [_queue packageInQueue:ZBQueueTypeInstall atIndex:indexPath.row];
    }
    else if ([action isEqual:@"Remove"]) {
        package = [_queue packageInQueue:ZBQueueTypeRemove atIndex:indexPath.row];
    }
    else if ([action isEqual:@"Reinstall"]) {
        package = [_queue packageInQueue:ZBQueueTypeReinstall atIndex:indexPath.row];
    }
    else if ([action isEqual:@"Upgrade"]) {
        package = [_queue packageInQueue:ZBQueueTypeUpgrade atIndex:indexPath.row];
    }
    else if ([action isEqual:@"Unresolved Dependencies"]) {
        cell.backgroundColor = [UIColor colorWithRed:0.98 green:0.40 blue:0.51 alpha:1.0];
        
        NSArray *failedQ = [_queue failedQueue];
        cell.textLabel.text = failedQ[indexPath.row][0];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Could not resolve dependency for %@", [(ZBPackage *)failedQ[indexPath.row][1] name]];
        
        return cell;
    }
    
    NSString *section = [[package section] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    if ([section characterAtIndex:[section length] - 1] == ')') {
        NSArray *items = [section componentsSeparatedByString:@"("]; //Remove () from section
        section = [items[0] substringToIndex:[items[0] length] - 1];
    }
    NSString *iconPath = [NSString stringWithFormat:@"/Applications/Cydia.app/Sections/%@.png", section];
    NSError *error;
    NSData *data = [NSData dataWithContentsOfFile:iconPath options:0 error:&error];
    UIImage *sectionImage = [UIImage imageWithData:data];
    if (sectionImage != NULL) {
        cell.imageView.image = sectionImage;
    }

    cell.textLabel.text = package.name;
    
    if ([package dependencyOf] != NULL) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"dependency of %@", [[package dependencyOf] name]];
    }
    else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)", package.identifier, package.version];
    }
    
    CGSize itemSize = CGSizeMake(35, 35);
    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
    [cell.imageView.image drawInRect:imageRect];
    cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return cell;
}

#pragma mark - Table View Delegate

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *action = [[_queue actionsToPerform] objectAtIndex:indexPath.section];
        
        if ([action isEqual:@"Install"]) {
            ZBPackage *package = [_queue packageInQueue:ZBQueueTypeInstall atIndex:indexPath.row];
            [_queue removePackage:package fromQueue:ZBQueueTypeInstall];
        }
        else if ([action isEqual:@"Remove"]) {
            ZBPackage *package = [_queue packageInQueue:ZBQueueTypeRemove atIndex:indexPath.row];
            [_queue removePackage:package fromQueue:ZBQueueTypeRemove];
        }
        else if ([action isEqual:@"Reinstall"]) {
            ZBPackage *package = [_queue packageInQueue:ZBQueueTypeReinstall atIndex:indexPath.row];
            [_queue removePackage:package fromQueue:ZBQueueTypeReinstall];
        }
        else if ([action isEqual:@"Upgrade"]) {
            ZBPackage *package = [_queue packageInQueue:ZBQueueTypeUpgrade atIndex:indexPath.row];
            [_queue removePackage:package fromQueue:ZBQueueTypeUpgrade];
        }
        else {
            NSLog(@"[Zebra] MY TIME HAS COME TO BURN");
        }
        
        [self refreshTable];
        
    }
}

@end
