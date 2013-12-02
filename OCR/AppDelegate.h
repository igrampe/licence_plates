//
//  AppDelegate.h
//  OCR
//
//  Created by Sema Belokovsky on 12.08.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import <UIKit/UIKit.h>

@class VideoCaptureViewController;
@class VideoHandlerViewController;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) VideoCaptureViewController *viewController;
@property (strong, nonatomic) VideoHandlerViewController *handlerViewController;

@end
