//
//  VideoHandlerViewController.h
//  GovNum
//
//  Created by Sema Belokovsky on 06.09.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVAsset.h>
#import <MediaPlayer/MediaPlayer.h>

@interface VideoHandlerViewController : UIViewController {
	MPMoviePlayerController *m_movie;
	UIImageView *m_imageView;
	int m_frames;
	AVAssetImageGenerator *_generator;
	AVURLAsset *_destinationAsset;
	float _totalSeconds;
	int _currentFrame;
}

@end
