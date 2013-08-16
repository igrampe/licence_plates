//
//  ViewController.m
//  GovNum
//
//  Created by Sema Belokovsky on 23.07.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import "VideoCaptureViewController.h"
#import "UIImage+OpenCV.h"
#include "ocr.h"

// Number of frames to average for FPS calculation
const int kFrameTimeBufferSize = 5;

@interface VideoCaptureViewController ()
- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale;
- (void)destroyCaptureSession;
- (void)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videOrientation;
- (void)updateDebugInfo;


@property (nonatomic, assign) float fps;

@end

@implementation VideoCaptureViewController {
	Contours m_templates;
	std::vector<char> m_symbols;
	Ocr *m_ocr;
}

@synthesize fps = m_fps;
@synthesize camera = m_camera;
@synthesize captureGrayscale = m_captureGrayscale;
@synthesize qualityPreset = m_qualityPreset;
@synthesize captureSession = m_captureSession;
@synthesize captureDevice = m_captureDevice;
@synthesize videoOutput = m_videoOutput;
@synthesize videoPreviewLayer = m_videoPreviewLayer;
@synthesize showDebugInfo;
@synthesize torchOn;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        m_camera = -1;
		m_qualityPreset = AVCaptureSessionPreset640x480;
        m_captureGrayscale = YES;
        
        // Create frame time circular buffer for calculating averaged fps
        m_frameTimes = (float*)malloc(sizeof(float) * kFrameTimeBufferSize);
		
		m_ocr = new Ocr([[self pathToLangugeFile] cStringUsingEncoding:NSUTF8StringEncoding]);
		
		m_frames = 0;
		
		m_plate = [[UILabel alloc] initWithFrame:CGRectMake(320-100, 0, 100, 24)];
		m_plate.backgroundColor = [UIColor clearColor];
		m_plate.textColor = [UIColor whiteColor];
    }
    return self;
}

- (void)dealloc
{
    [self destroyCaptureSession];
    m_fpsLabel = nil;
    if (m_frameTimes) {
        free(m_frameTimes);
    }
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self createCaptureSessionForCamera:m_camera qualityPreset:m_qualityPreset grayscale:m_captureGrayscale];
    [m_captureSession startRunning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [self destroyCaptureSession];
    m_fpsLabel = nil;
}

- (void)setFps:(float)fps
{
    [self willChangeValueForKey:@"fps"];
    m_fps = fps;
    [self didChangeValueForKey:@"fps"];
    
    [self updateDebugInfo];
}

- (BOOL)showDebugInfo
{
    return (m_fpsLabel != nil);
}

- (void)setShowDebugInfo:(BOOL)showDebugInfo
{
    if (!showDebugInfo && m_fpsLabel) {
        [m_fpsLabel removeFromSuperview];
        m_fpsLabel = nil;
    }
    
    if (showDebugInfo && !m_fpsLabel) {
        CGRect frame = self.view.bounds;
        frame.size.height = 40.0f;
        m_fpsLabel = [[UILabel alloc] initWithFrame:frame];
        m_fpsLabel.textColor = [UIColor whiteColor];
        m_fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
        [self.view addSubview:m_fpsLabel];
		[self.view addSubview:m_plate];
        
        [self updateDebugInfo];
    }
}

- (void)setTorchOn:(BOOL)torch
{
    NSError *error = nil;
    if ([m_captureDevice hasTorch]) {
        BOOL locked = [m_captureDevice lockForConfiguration:&error];
        if (locked) {
            m_captureDevice.torchMode = (torch)? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
            [m_captureDevice unlockForConfiguration];
        }
    }
}

- (BOOL)torchOn
{
    return (m_captureDevice.torchMode == AVCaptureTorchModeOn);
}



// camera: 0 for back camera, 1 for front camera

- (void)setCamera:(int)camera
{
    if (camera != m_camera)
    {
        m_camera = camera;
        
        if (m_captureSession) {
            NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            
            [m_captureSession beginConfiguration];
            
            [m_captureSession removeInput:[[m_captureSession inputs] lastObject]];
            
            if (m_camera >= 0 && m_camera < [devices count]) {
                m_captureDevice = [devices objectAtIndex:camera];
            }
            else {
                m_captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            }
			
            // Create device input
            NSError *error = nil;
            AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:m_captureDevice error:&error];
            [m_captureSession addInput:input];
            
            [m_captureSession commitConfiguration];
        }
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate delegate methods

// AVCaptureVideoDataOutputSampleBufferDelegate delegate method called when a video frame is available
//
// This method is called on the video capture GCD queue. A cv::Mat is created from the frame data and
// passed on for processing with OpenCV.

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
//    NSAutoreleasePool *localpool = [[NSAutoreleasePool alloc] init];

    @autoreleasepool {

	
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    AVCaptureVideoOrientation videoOrientation = [[[m_videoOutput connections] objectAtIndex:0] videoOrientation];
    
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        // For grayscale mode, the luminance channel of the YUV data is used
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC1, baseaddress, 0);
        
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    else if (format == kCVPixelFormatType_32BGRA) {
        // For color mode a 4-channel cv::Mat is created from the BGRA data
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        void *baseaddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        
        cv::Mat mat(videoRect.size.height, videoRect.size.width, CV_8UC4, baseaddress, 0);
        
        [self processFrame:mat videoRect:videoRect videoOrientation:videoOrientation];
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    }
    else {
        NSLog(@"Unsupported video format");
    }
    
    // Update FPS calculation
    CMTime presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    
    if (m_lastFrameTimestamp == 0) {
        m_lastFrameTimestamp = presentationTime.value;
        m_framesToAverage = 1;
    }
    else {
        float frameTime = (float)(presentationTime.value - m_lastFrameTimestamp) / presentationTime.timescale;
        m_lastFrameTimestamp = presentationTime.value;
        
        m_frameTimes[m_frameTimesIndex++] = frameTime;
        
        if (m_frameTimesIndex >= kFrameTimeBufferSize) {
            m_frameTimesIndex = 0;
        }
        
        float totalFrameTime = 0.0f;
        for (int i = 0; i < m_framesToAverage; i++) {
            totalFrameTime += m_frameTimes[i];
        }
        
        float averageFrameTime = totalFrameTime / m_framesToAverage;
        float fps = 1.0f / averageFrameTime;
        
        if (fabsf(fps - m_captureQueueFps) > 0.1f) {
            m_captureQueueFps = fps;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setFps:fps];
            });
        }
        
        m_framesToAverage++;
        if (m_framesToAverage > kFrameTimeBufferSize) {
            m_framesToAverage = kFrameTimeBufferSize;
        }
    }
    
	}
}




// orientation: Will generally by AVCaptureVideoOrientationLandscapeRight for the back camera and
//              AVCaptureVideoOrientationLandscapeRight for the front camera
//
- (void)processFrame:(cv::Mat&)mat videoRect:(CGRect)rect videoOrientation:(AVCaptureVideoOrientation)videOrientation
{
	
//	cv::resize(mat, mat, cv::Size(), 0.5f, 0.5f, CV_INTER_LINEAR);
//    rect.size.width /= 2.0f;
//    rect.size.height /= 2.0f;
    
    // Rotate video frame by 90deg to portrait by combining a transpose and a flip
    // Note that AVCaptureVideoDataOutput connection does NOT support hardware-accelerated
    // rotation and mirroring via videoOrientation and setVideoMirrored properties so we
    // need to do the rotation in software here.
    cv::transpose(mat, mat);
    CGFloat temp = rect.size.width;
    rect.size.width = rect.size.height;
    rect.size.height = temp;
    
    if (videOrientation == AVCaptureVideoOrientationLandscapeRight)
    {
        // flip around y axis for back camera
        cv::flip(mat, mat, 1);
    }
	
    videOrientation = AVCaptureVideoOrientationPortrait;
	
/*	cv::Mat img_blur = cv::Mat(mat.cols, mat.rows, CV_8UC1);
	cv::blur(mat, img_blur, cv::Size(5, 5));
	cv::Mat img_sobel;
	cv::Sobel(img_blur, img_sobel, CV_8U, 1, 0, 3, 1, cv::BORDER_REFLECT_101);
	cv::Mat img_threshold;
	cv::threshold(img_sobel, img_threshold, 0, 255, CV_THRESH_OTSU+CV_THRESH_BINARY);
	cv::Mat element = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(17, 3));
	cv::morphologyEx(img_threshold, img_threshold, CV_MOP_CLOSE, element);
	Contours contours;
	cv::findContours(img_threshold, contours, CV_RETR_EXTERNAL, CV_CHAIN_APPROX_NONE);
//	cv::drawContours(mat, contours, -1, cv::Scalar(0, 0, 0));

	cv::vector<cv::vector<cv::Point> >::iterator itc = contours.begin();
	cv::vector<cv::RotatedRect> rects;
	
	while (itc!=contours.end()) {
		cv::RotatedRect mr = cv::minAreaRect(cv::Mat(*itc));
		if (verifySizes(mr)) {
			++itc;
			rects.push_back(mr);
			cv::Point2f rect_points[4];
			mr.points(rect_points);
//			for (int j = 0; j < 4; j++ ) {
//				cv::line(mat, rect_points[j], rect_points[(j+1)%4], cv::Scalar(0, 0,0 ), 5, 8);
//			}
		} else {
			itc = contours.erase(itc);
		}
	}
	
//	cv::drawContours(mat, contours, -1, cv::Scalar(0, 0, 0));

	cv::vector<cv::Mat> crops;
	
	for (int i = 0; i < rects.size(); ++i) {
		
		cv::Mat m, rotated, cropped;
		float angle = rects[i].angle;
		cv::Size size = rects[i].size;
//		if (angle < -45.) {
//            angle += 90.0;
//			std::swap(size.width, size.height);
//        }
		m = cv::getRotationMatrix2D(rects[i].center, angle, 1.0);
//		cv::warpAffine(mat, rotated, m, mat.size(), cv::INTER_CUBIC);
		cv::getRectSubPix(mat, size, rects[i].center, cropped);
		
		cv::Mat dst = cv::Mat(cropped.cols, mat.rows, CV_8UC1);
//		cv::adaptiveThreshold(cropped, dst, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, CV_THRESH_BINARY, 15, 1);
		crops.push_back(cropped);
	}
	cv::vector<cv::Mat> masks;
	cv::vector<cv::Mat> candidates;
	cv::vector<cv::Mat> dsts;
	for (int i = 0; i < crops.size(); i++){
		cv::Mat dst;
		crops[i].copyTo(dst);
		dsts.push_back(dst);
		srand(time(NULL));
		cv::Point center = cv::Point(crops[i].cols/2, crops[i].rows/2);
		circle(crops[i], center, 5, cv::Scalar(255, 255, 255), -1);
		cv::Mat mask;
		mask.create(crops[i].rows + 2, crops[i].cols + 2, CV_8UC1);
		mask = cv::Scalar::all(0);
		int loDiff = 100;
		int upDiff = 100;
		int connectivity = 4;
		int newMaskVal = 255;
		int NumSeeds = 10;
		cv::Rect ccomp;
		int height = crops[i].rows / 2;
		int width = crops[i].cols / 2;
		int flags = connectivity + (newMaskVal << 8 ) + CV_FLOODFILL_FIXED_RANGE + CV_FLOODFILL_MASK_ONLY;
		for(int j=0; j<NumSeeds; ++j){
			cv::Point seed;
			seed.x = center.x+rand()%(int)width-(width/2);
			seed.y = center.y+rand()%(int)height-(height/2);
			circle(crops[i], seed, 2, cv::Scalar(255,255,255), -1);
			if (seed.x > 1 && seed.y > 1 && seed.x+1 < crops[i].cols && seed.y+1 < crops[i].rows) {
				floodFill(crops[i], mask, seed, cv::Scalar(255,255,255), &ccomp,
						  cv::Scalar(loDiff, loDiff, loDiff), cv::Scalar(upDiff, upDiff, upDiff),
						  flags);
			} else {
				NSLog(@"%d %d", seed.x, seed.y);
			}
		}
		Contours subContours;
		cv::findContours(mask, subContours, CV_RETR_EXTERNAL, CV_CHAIN_APPROX_NONE);
		
		
		
		//cv::drawContours(crops[i], subContours, -1, cv::Scalar(0, 0, 0), -1);
		
		cv::vector<cv::vector<cv::Point> >::iterator itc = subContours.begin();
		cv::vector<cv::RotatedRect> srects;
		
		while (itc!=subContours.end()) {
			cv::RotatedRect mr = cv::minAreaRect(cv::Mat(*itc));
			++itc;
			srects.push_back(mr);
		}
		
		int maxArea = 0;
		int candidate;
		
		for (int j = 0; j < srects.size(); ++j) {
			if (maxArea <= srects[j].size.width*srects[j].size.height) {
				maxArea = srects[j].size.width*srects[j].size.height;
				candidate = j;
			}
		}
		
		cv::Mat sm, scropped;
		float angle = rects[candidate].angle;
		cv::Size size = rects[i].size;
		sm = cv::getRotationMatrix2D(srects[candidate].center, angle, 1.0);
		cv::getRectSubPix(dsts[i], size, srects[candidate].center, scropped);
		
		candidates.push_back(scropped);
		
		masks.push_back(mask);
	}
	
	
	
	for (int i = 0; i < candidates.size(); ++i) {
		
		
		Contours ctrs;
		cv::Mat candidate = candidates[i];
		cv::Mat thresh;
		cv::threshold(candidate, thresh, 0, 255, CV_THRESH_OTSU+CV_THRESH_BINARY);
		cv::findContours(thresh, ctrs, CV_RETR_LIST, CV_CHAIN_APPROX_NONE);
		
//		cv::drawContours(candidate, ctrs, -1, cv::Scalar(0));
		
		for (int j = 0; j < ctrs.size(); ++j) {
			cv::Rect r = cv::boundingRect(ctrs[j]);
			if ((r.height > r.width) && r.width > 5) {
				
				
				float ratio = MAXFLOAT;
				int index = -1;
				
				for (int k = 0; k < m_templates.size(); ++k) {
					float l = cv::matchShapes(m_templates[k] , ctrs[j], CV_CONTOURS_MATCH_I3, 0);					
					if (l < ratio) {
						index = k;
						ratio = l;
					}
				}
				
				if (index >= 0) {
					NSLog(@"%d %d %c %f", j, index, m_symbols[index], ratio);
					
					cv::line(candidate, cv::Point(r.x, r.y), cv::Point(r.x + r.width, r.y), cv::Scalar(0, 0,0 ), 1);
					cv::line(candidate, cv::Point(r.x + r.width, r.y), cv::Point(r.x + r.width, r.y + r.height), cv::Scalar(0, 0,0 ), 1);
					cv::line(candidate, cv::Point(r.x + r.width, r.y + r.height), cv::Point(r.x, r.y + r.height), cv::Scalar(0, 0,0 ), 1);
					cv::line(candidate, cv::Point(r.x, r.y + r.height), cv::Point(r.x, r.y), cv::Scalar(0, 0,0 ), 1);
				}
				
			}
			
			

//				cv::rectangle(candidates[i], cv::Point(r.x, r.y), cv::Point(r.x + r.width, r.y + r.height), cv::Scalar(0), 1);

		}
//		NSLog(@"%ld", ctrs.size());
	}
*/
	std::vector<cv::Mat> candidates;
	std::vector<cv::Mat> letters;
	
	std::vector<std::string> numbers;
	
	m_ocr->processFrame(mat, candidates, letters, numbers);
	
/*	for (int i = 0; i < letters.size(); ++i) {
		UIImage *img = [UIImage imageWithCVMat:letters[i]];
		NSData *data = UIImagePNGRepresentation(img);
		NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *documentPath = [documentPaths objectAtIndex:0];
		
		NSString *name = [documentPath stringByAppendingFormat:@"/f_%ld_%d.png", m_frames, i];
		[data writeToFile:name atomically:YES];
	}*/
	
	dispatch_sync(dispatch_get_main_queue(), ^{
		if (candidates.size()>0) {
			CGRect rr = CGRectMake(0, 0, candidates[0].cols, candidates[0].rows);
			rr.origin.y = 40;
			[self display:candidates[0] forVideoRect:rr videoOrienation:videOrientation];
			if (numbers.size()) {
				m_plate.text = [NSString stringWithCString:numbers[0].c_str() encoding:NSUTF8StringEncoding];
			}			
		}
//		CGRect rr = CGRectMake(0, 0, tplM.cols, tplM.rows);
//		[self display:rs forVideoRect:rr videoOrienation:videOrientation];
    });
	m_frames++;
}

- (void)displayR:(cv::vector<cv::RotatedRect>)rs
	forVideoRect:(CGRect)rect
 videoOrienation:(AVCaptureVideoOrientation)videoOrientation
{
	NSArray *sublayers = [NSArray arrayWithArray:[self.view.layer sublayers]];
    int sublayersCount = [sublayers count];
    int currentSublayer = 0;
    
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the additional layers
	for (CALayer *layer in sublayers) {
        NSString *layerName = [layer name];
		if ([layerName isEqualToString:@"frameLayer"])
			[layer setHidden:YES];
	}
    
    // Create transform to convert from video frame coordinate space to view coordinate space
    CGAffineTransform t = [self affineTransformForVideoFrame:rect orientation:videoOrientation];
	
	for (int i = 0; i < rs.size(); i++) {
		cv::Rect r = rs[i].boundingRect();
		CGRect rect;
        rect.origin.x = r.x;
        rect.origin.y = r.y;
        rect.size.width = r.width;
        rect.size.height = r.height;
		
		rect = CGRectApplyAffineTransform(rect, t);
		
		CALayer *featureLayer = nil;
		
        while (!featureLayer && (currentSublayer < sublayersCount)) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ([[currentLayer name] isEqualToString:@"frameLayer"]) {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        if (!featureLayer) {
            // Create a new feature marker layer
			featureLayer = [[CALayer alloc] init];
            featureLayer.name = @"frameLayer";
            featureLayer.borderColor = [[UIColor redColor] CGColor];
            featureLayer.borderWidth = 4.0f;
			[self.view.layer addSublayer:featureLayer];
			featureLayer = nil;
		}
        
        featureLayer.frame = rect;
	}
    [CATransaction commit];
}

- (void)display:(cv::Mat)mat
   forVideoRect:(CGRect)rect
videoOrienation:(AVCaptureVideoOrientation)videoOrientation
{
	if (!m_imgView) {
		m_imgView = [[UIImageView alloc] initWithImage:[UIImage imageWithCVMat:mat]];
	} else {
		[m_imgView setImage:[UIImage imageWithCVMat:mat]];
	}
	[m_imgView.layer removeFromSuperlayer];
	m_imgView.frame = rect;
	[self.view.layer addSublayer:m_imgView.layer];
}

- (void)displayC:(std::vector<std::vector<cv::Point> >)contours
	forVideoRect:(CGRect)rect
 videoOrienation:(AVCaptureVideoOrientation)videoOrientation
{
	NSArray *sublayers = [NSArray arrayWithArray:[self.view.layer sublayers]];
    int sublayersCount = [sublayers count];
    int currentSublayer = 0;
    
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the additional layers
	for (CALayer *layer in sublayers) {
        NSString *layerName = [layer name];
		if ([layerName isEqualToString:@"frameLayer"])
			[layer setHidden:YES];
	}
    
    // Create transform to convert from video frame coordinate space to view coordinate space
    CGAffineTransform t = [self affineTransformForVideoFrame:rect orientation:videoOrientation];
	
	for (int i = 0; i < contours.size(); i++) {
		cv::Rect r0= cv::boundingRect(cv::Mat(contours[i]));
		CGRect rect;
        rect.origin.x = r0.x;
        rect.origin.y = r0.y;
        rect.size.width = r0.width;
        rect.size.height = r0.height;
		
		rect = CGRectApplyAffineTransform(rect, t);
		
		CALayer *featureLayer = nil;
		
        while (!featureLayer && (currentSublayer < sublayersCount)) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ([[currentLayer name] isEqualToString:@"frameLayer"]) {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        if (!featureLayer) {
            // Create a new feature marker layer
			featureLayer = [[CALayer alloc] init];
            featureLayer.name = @"frameLayer";
            featureLayer.borderColor = [[UIColor redColor] CGColor];
            featureLayer.borderWidth = 4.0f;
			[self.view.layer addSublayer:featureLayer];
			featureLayer = nil;
		}
        
        featureLayer.frame = rect;
	}
    [CATransaction commit];
}

// Create an affine transform for converting CGPoints and CGRects from the video frame coordinate space to the
// preview layer coordinate space. Usage:
//
// CGPoint viewPoint = CGPointApplyAffineTransform(videoPoint, transform);
// CGRect viewRect = CGRectApplyAffineTransform(videoRect, transform);
//
// Use CGAffineTransformInvert to create an inverse transform for converting from the view cooridinate space to
// the video frame coordinate space.
//
// videoFrame: a rect describing the dimensions of the video frame
// video orientation: the video orientation
//
// Returns an affine transform
//
- (CGAffineTransform)affineTransformForVideoFrame:(CGRect)videoFrame orientation:(AVCaptureVideoOrientation)videoOrientation
{
    CGSize viewSize = self.view.bounds.size;
    NSString * const videoGravity = m_videoPreviewLayer.videoGravity;
    CGFloat widthScale = 1.0f;
    CGFloat heightScale = 1.0f;
    
    // Move origin to center so rotation and scale are applied correctly
    CGAffineTransform t = CGAffineTransformMakeTranslation(-videoFrame.size.width / 2.0f, -videoFrame.size.height / 2.0f);
    
    switch (videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationPortraitUpsideDown:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI));
            widthScale = viewSize.width / videoFrame.size.width;
            heightScale = viewSize.height / videoFrame.size.height;
            break;
            
        case AVCaptureVideoOrientationLandscapeRight:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
            
        case AVCaptureVideoOrientationLandscapeLeft:
            t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(-M_PI_2));
            widthScale = viewSize.width / videoFrame.size.height;
            heightScale = viewSize.height / videoFrame.size.width;
            break;
    }
    
    // Adjust scaling to match video gravity mode of video preview
    if (videoGravity == AVLayerVideoGravityResizeAspect) {
        heightScale = MIN(heightScale, widthScale);
        widthScale = heightScale;
    }
    else if (videoGravity == AVLayerVideoGravityResizeAspectFill) {
        heightScale = MAX(heightScale, widthScale);
        widthScale = heightScale;
    }
    
    // Apply the scaling
    t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(widthScale, heightScale));
    
    // Move origin back from center
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(viewSize.width / 2.0f, viewSize.height / 2.0f));
	
    return t;
}

// camera: -1 for default, 0 for back camera, 1 for front camera
// qualityPreset: [AVCaptureSession sessionPreset] value

- (BOOL)createCaptureSessionForCamera:(NSInteger)camera qualityPreset:(NSString *)qualityPreset grayscale:(BOOL)grayscale
{
    m_lastFrameTimestamp = 0;
    m_frameTimesIndex = 0;
    m_captureQueueFps = 0.0f;
    m_fps = 0.0f;
	
    // Set up AV capture
    NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    if ([devices count] == 0) {
        NSLog(@"No video capture devices found");
        return NO;
    }
    
    if (camera == -1) {
        m_camera = -1;
        m_captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    else if (camera >= 0 && camera < [devices count]) {
        m_camera = camera;
        m_captureDevice = [devices objectAtIndex:camera];
    }
    else {
        m_camera = -1;
        m_captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        NSLog(@"Camera number out of range. Using default camera");
    }
    
    // Create the capture session
    m_captureSession = [[AVCaptureSession alloc] init];
    m_captureSession.sessionPreset = (qualityPreset)? qualityPreset : AVCaptureSessionPreset1920x1080;
    
    // Create device input
    NSError *error = nil;
    AVCaptureDeviceInput *input = [[AVCaptureDeviceInput alloc] initWithDevice:m_captureDevice error:&error];
    
    // Create and configure device output
    m_videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    dispatch_queue_t queue = dispatch_queue_create("cameraQueue", NULL);
    [m_videoOutput setSampleBufferDelegate:self queue:queue];
	
//    dispatch_release(queue);
    
    m_videoOutput.alwaysDiscardsLateVideoFrames = YES;
    
    // For grayscale mode, the luminance channel from the YUV fromat is used
    // For color mode, BGRA format is used
    OSType format = kCVPixelFormatType_32BGRA;
	
    // Check YUV format is available before selecting it
    if (grayscale && [m_videoOutput.availableVideoCVPixelFormatTypes containsObject:
                      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]) {
        format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    }
    
    m_videoOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:format]
															  forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    // Connect up inputs and outputs
    if ([m_captureSession canAddInput:input]) {
        [m_captureSession addInput:input];
    }
    
    if ([m_captureSession canAddOutput:m_videoOutput]) {
        [m_captureSession addOutput:m_videoOutput];
    }
    
    // Create the preview layer
    m_videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:m_captureSession];
    [m_videoPreviewLayer setFrame:self.view.bounds];
    m_videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:m_videoPreviewLayer atIndex:0];
    
    return YES;
}

- (void)destroyCaptureSession
{
    [m_captureSession stopRunning];
    
    [m_videoPreviewLayer removeFromSuperlayer];
    m_videoPreviewLayer = nil;
    m_videoOutput = nil;
    m_captureDevice = nil;
    m_captureSession = nil;
    
    m_videoPreviewLayer = nil;
    m_videoOutput = nil;
    m_captureDevice = nil;
    m_captureSession = nil;
}

- (void)updateDebugInfo {
    if (m_fpsLabel) {
        m_fpsLabel.text = [NSString stringWithFormat:@"FPS: %0.1f", m_fps];
    }
}

/*bool verifySizes(cv::RotatedRect mr) {
	
//    float error=0.5;
    //Car plate size: 520x112 aspect 4.6428
    float aspect=4.6428;
    //Set a min and max area. All other patchs are discarded
    int min = 20*20*aspect;
	int max = 540*540*aspect;
    //Get only patchs that match to a respect ratio.
//    float rmin = aspect-aspect*error;
//    float rmax = aspect+aspect*error;
	
    int area = mr.size.height * mr.size.width;
	float r = mr.size.width / (float)mr.size.height;
	
	if (area < min || mr.angle > 35 || mr.angle < -35 || r<3 || mr.size.height < 20) {
		return false;
	} else {
		return true;
	}
}*/

- (NSString *)pathToLangugeFile{
    
    // Set up the tessdata path. This is included in the application bundle
    // but is copied to the Documents directory on the first run.
	
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentPath = ([documentPaths count] > 0) ? [documentPaths objectAtIndex:0] : nil;
    
    NSString *dataPath = [documentPath stringByAppendingPathComponent:@"tessdata"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // If the expected store doesn't exist, copy the default store.
    if (![fileManager fileExistsAtPath:dataPath]) {
        // get the path to the app bundle (with the tessdata dir)
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
        NSString *tessdataPath = [bundlePath stringByAppendingPathComponent:@"tessdata"];
        if (tessdataPath) {
            [fileManager copyItemAtPath:tessdataPath toPath:dataPath error:NULL];
        }
    }
    
	setenv("TESSDATA_PREFIX", [[documentPath stringByAppendingString:@"/"] UTF8String], 1);
	
    return dataPath;
}

@end
