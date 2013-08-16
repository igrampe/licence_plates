//
//  ViewController.h
//  GovNum
//
//  Created by Sema Belokovsky on 23.07.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface VideoCaptureViewController : UIViewController <AVCaptureVideoDataOutputSampleBufferDelegate>{
	AVCaptureSession *m_captureSession;
    AVCaptureDevice *m_captureDevice;
    AVCaptureVideoDataOutput *m_videoOutput;
    AVCaptureVideoPreviewLayer *m_videoPreviewLayer;
    
    int m_camera;
    NSString *m_qualityPreset;
    BOOL m_captureGrayscale;
    
    // Fps calculation
    CMTimeValue m_lastFrameTimestamp;
    float *m_frameTimes;
    int m_frameTimesIndex;
    int m_framesToAverage;
    
    float m_captureQueueFps;
    float m_fps;
    
    UILabel *m_fpsLabel;
	UILabel *m_plate;
	
	UIImageView *m_imgView;
	
	long m_frames;
}

@property (nonatomic, readonly) float fps;

@property (nonatomic, assign) BOOL showDebugInfo;
@property (nonatomic, assign) BOOL torchOn;

// AVFoundation components
@property (nonatomic, readonly) AVCaptureSession *captureSession;
@property (nonatomic, readonly) AVCaptureDevice *captureDevice;
@property (nonatomic, readonly) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;


// -1: default, 0: back camera, 1: front camera
@property (nonatomic, assign) int camera;

@property (nonatomic, retain) NSString * const qualityPreset;
@property (nonatomic, assign) BOOL captureGrayscale;

- (CGAffineTransform)affineTransformForVideoFrame:(CGRect)videoFrame orientation:(AVCaptureVideoOrientation)videoOrientation;


@end
