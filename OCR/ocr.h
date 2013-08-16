//
//  ocr.h
//  OCR
//
//  Created by Sema Belokovsky on 12.08.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#ifndef __OCR__ocr__
#define __OCR__ocr__

#include <iostream>

typedef std::vector<cv::Vec4i> Hierarchy;
typedef std::vector<std::vector<cv::Point> > Contours;

class Ocr {
	tesseract::TessBaseAPI *m_tess;
	const char *m_pathToTessData;
public:
	Ocr(const char *s);
	void processFrame(cv::Mat &mat, cv::vector<cv::Mat> &candidates, cv::vector<cv::Mat> &letters, std::vector<std::string> &numbers);
};

#endif /* defined(__OCR__ocr__) */
