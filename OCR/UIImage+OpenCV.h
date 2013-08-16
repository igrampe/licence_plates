//
//  UIImage+OpenCV.h
//  OCR
//
//  Created by Sema Belokovsky on 12.08.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (OpenCV)

+ (UIImage *)imageWithCVMat:(const cv::Mat&)cvMat;
- (id)initWithCVMat:(const cv::Mat&)cvMat;
- (cv::Mat)CVGrayscaleMat;

@end
