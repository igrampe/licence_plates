//
//  VideoHandlerViewController.m
//  GovNum
//
//  Created by Sema Belokovsky on 06.09.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import "VideoHandlerViewController.h"
#import "UIImage+OpenCV.h"
#include "ocr.h"
#import <CoreMedia/CoreMedia.h>

@implementation VideoHandlerViewController {
	Contours m_templates;
	std::vector<char> m_symbols;
	Ocr *m_ocr;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
		m_frames = 0;
		m_ocr = new Ocr([[self pathToLangugeFile] cStringUsingEncoding:NSUTF8StringEncoding]);
		
		NSString *path = [[NSBundle mainBundle] pathForResource:@"movie.mov" ofType:nil];
		NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
        
		NSURL *sourceMovieURL = url;
		AVURLAsset *sourceAsset = [AVURLAsset URLAssetWithURL:sourceMovieURL options:nil];
		CMTime duration = sourceAsset.duration;
		_totalSeconds = CMTimeGetSeconds(duration);
		_generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:sourceAsset];
		_generator.appliesPreferredTrackTransform=TRUE;
		NSLog(@"%f", _totalSeconds);
		_currentFrame = 0;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	m_imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1080*self.view.bounds.size.width/1920)];
	[self.view addSubview:m_imageView];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	
//	[self next];
	
	CMTime thumbTime = CMTimeMakeWithSeconds(0, _totalSeconds);
	
	AVAssetImageGeneratorCompletionHandler handler = ^(CMTime requestedTime, CGImageRef im, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error){
		if (result != AVAssetImageGeneratorSucceeded) {
			NSLog(@"couldn't generate thumbnail, error:%@", error);
		} else {
			UIImage *img = [UIImage imageWithCGImage:im];
			NSLog(@"%f %f", CMTimeGetSeconds(requestedTime), CMTimeGetSeconds(actualTime));
//			[self performSelectorOnMainThread:@selector(setImage:) withObject:img waitUntilDone:YES];
			[self detectOnImg:img];
		}
	};
	
	NSMutableArray *m = [[NSMutableArray alloc] init];
	
	for (int i = 0; i < _totalSeconds; i++) {
		thumbTime = CMTimeMakeWithSeconds(i, _totalSeconds);
		[m addObject:[NSValue valueWithCMTime:thumbTime]];
	}
	
	[_generator generateCGImagesAsynchronouslyForTimes:m completionHandler:handler];
	
	NSLog(@"DONE");
}

- (void)setImage:(UIImage *)image
{
	[m_imageView setImage:image];
}

- (void)detectOnImg:(UIImage *)image
{
	cv::Mat mat = [image CVGrayscaleMat];
	
	std::vector<cv::Mat> candidates;
	std::vector<cv::Mat> letters;
	
	std::vector<std::string> numbers;
	
	NSDate *date = [NSDate date];
	NSTimeInterval t1 = [date timeIntervalSince1970];
	
	m_ocr->processFrame(mat, candidates, letters, numbers);
	
	
	
	date = [NSDate date];
	NSTimeInterval t2 = [date timeIntervalSince1970];
	NSLog(@"proceed for %f", t2-t1);
	
	if (candidates.size()>0) {
		if (numbers.size()) {
			NSLog(@"%@", [NSString stringWithCString:numbers[0].c_str() encoding:NSUTF8StringEncoding]);
		}
	}
	
	[self performSelectorOnMainThread:@selector(setImage:) withObject:[UIImage imageWithCVMat:mat] waitUntilDone:YES];
	
	_currentFrame++;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

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
