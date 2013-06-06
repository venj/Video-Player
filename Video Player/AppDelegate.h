//
//  AppDelegate.h
//  Video Player
//
//  Created by 朱 文杰 on 13-5-27.
//  Copyright (c) 2013年 Home. All rights reserved.
//

#import <UIKit/UIKit.h>

@class VPFileInfoViewController;
@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) VPFileInfoViewController *fileInfoViewController;

+ (AppDelegate *)shared;
- (NSString *)fileLinkWithPath:(NSString *)path;
- (NSString *)fileInfoWithPath:(NSString *)path fileName:(NSString *)fileName;
@end
