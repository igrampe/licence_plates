//
//  ocr.cpp
//  OCR
//
//  Created by Sema Belokovsky on 12.08.13.
//  Copyright (c) 2013 Sema Belokovsky. All rights reserved.
//

#include "ocr.h"

bool compareRect (cv::RotatedRect r1, cv::RotatedRect r2) {
    double i = r1.center.x;
    double j = r2.center.x;
    return (i < j);
}

Ocr::Ocr(const char *s)
{
	m_pathToTessData = s;
	m_tess = new tesseract::TessBaseAPI();
	m_tess->Init(m_pathToTessData, "eng");
	m_tess->SetPageSegMode(tesseract::PSM_SINGLE_CHAR);
	m_tess->SetVariable("tessedit_char_whitelist","ABCEHKMOPTXY1234567890");
}

bool verifySizes(cv::RotatedRect mr) {
	
    float aspect = 4.6428;
    
    int min = 20*20*aspect;
	
    int area = mr.size.height * mr.size.width;
	float r = mr.size.width / (float)mr.size.height;
	
	if (area < min || mr.angle > 35 || mr.angle < -35 || r<3 || mr.size.height < 20) {
		return false;
	} else {
		return true;
	}
}

void makeCrops(cv::Mat &mat, Contours ctrs, std::vector<cv::Mat> &mats) {
	
	cv::vector<cv::vector<cv::Point> >::iterator itc = ctrs.begin();
	cv::vector<cv::RotatedRect> rects;
	
	while (itc != ctrs.end()) {
		cv::RotatedRect mr = cv::minAreaRect(cv::Mat(*itc));
		++itc;
		rects.push_back(mr);
	}
	
	std::sort(rects.begin(), rects.end(), compareRect);	
	
	cv::Mat sm, scropped;
	for (int i = 0; i < rects.size(); ++i) {
		if (rects[i].size.width < rects[i].size.height && rects[i].size.width > 10 &&
			rects[i].size.height / (float)rects[i].size.width < (20/15.0)*1.4 &&
			rects[i].size.height / (float)rects[i].size.width > (20/15.0)*0.8) {
			float angle = rects[i].angle;
			cv::Size size = rects[i].size;
			sm = cv::getRotationMatrix2D(rects[i].center, angle, 1.0);
			cv::getRectSubPix(mat, size, rects[i].center, scropped);
			cv::Mat bw;
			cv::threshold(scropped, bw, 0, 255, CV_THRESH_OTSU+CV_THRESH_BINARY);
			mats.push_back(bw);
		}
	}
}

void Ocr::processFrame(cv::Mat &mat, cv::vector<cv::Mat> &candidates, cv::vector<cv::Mat> &letters, std::vector<std::string> &numbers)
{
	cv::Mat img_blur = cv::Mat(mat.cols, mat.rows, CV_8UC1);
	cv::blur(mat, img_blur, cv::Size(5, 5));
	cv::Mat img_sobel;
	cv::Sobel(img_blur, img_sobel, CV_8U, 1, 0, 3, 1, cv::BORDER_REFLECT_101);
	cv::Mat img_threshold;
	cv::threshold(img_sobel, img_threshold, 0, 255, CV_THRESH_OTSU+CV_THRESH_BINARY);
	cv::Mat element = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(17, 3));
	cv::morphologyEx(img_threshold, img_threshold, CV_MOP_CLOSE, element);
	Contours contours;
	cv::findContours(img_threshold, contours, CV_RETR_EXTERNAL, CV_CHAIN_APPROX_NONE);
	
	cv::vector<cv::vector<cv::Point> >::iterator itc = contours.begin();
	cv::vector<cv::RotatedRect> rects;
	
	while (itc!=contours.end()) {
		cv::RotatedRect mr = cv::minAreaRect(cv::Mat(*itc));
		if (verifySizes(mr)) {
			++itc;
			rects.push_back(mr);
			cv::Point2f rect_points[4];
			mr.points(rect_points);
		} else {
			itc = contours.erase(itc);
		}
	}
	
	cv::vector<cv::Mat> crops;
	
	for (int i = 0; i < rects.size(); ++i) {
		cv::Mat m, rotated, cropped;
		float angle = rects[i].angle;
		cv::Size size = rects[i].size;
		m = cv::getRotationMatrix2D(rects[i].center, angle, 1.0);
		cv::getRectSubPix(mat, size, rects[i].center, cropped);
		
		cv::Mat dst = cv::Mat(cropped.cols, mat.rows, CV_8UC1);
		crops.push_back(cropped);
	}
//	cv::vector<cv::Mat> candidates;
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
				printf("error floodFill: %d %d", seed.x, seed.y);
			}
		}
		Contours subContours;
		cv::findContours(mask, subContours, CV_RETR_EXTERNAL, CV_CHAIN_APPROX_NONE);
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
	}
	
	
	
	std::vector<cv::Mat> mats;
	std::string str;
	std::vector<std::string> plates;
	
	for (int i = 0; i < candidates.size(); ++i) {
		str.clear();
		
		Contours ctrs;
		cv::Mat candidate = candidates[i];
		cv::Mat thresh;
		cv::threshold(candidate, thresh, 0, 255, CV_THRESH_OTSU+CV_THRESH_BINARY);
		cv::findContours(thresh, ctrs, CV_RETR_LIST, CV_CHAIN_APPROX_NONE);
		
		mats.clear();
		if (ctrs.size()) {
			makeCrops(candidates[i], ctrs, mats);
		}
		
		m_tess->SetVariable("tessedit_char_whitelist","ABCEHKMOPTXY");
		if (mats.size() > 0) {
			cv::Mat m = mats[0];
			m_tess->SetImage((uchar *)m.data, m.size().width, m.size().height, m.channels(), m.step1());
			m_tess->Recognize(0);
			const char *out = m_tess->GetUTF8Text();
			if (out) {
				str += out[0];
			}
		}
		
		
		m_tess->SetVariable("tessedit_char_whitelist","1234567890");
		for (int j = 1; j < mats.size() && j < 4; ++j) {
			cv::Mat m = mats[j];
			m_tess->SetImage((uchar *)m.data, m.size().width, m.size().height, m.channels(), m.step1());
			m_tess->Recognize(0);
			const char *out = m_tess->GetUTF8Text();
			if (out) {
				str += out[0];
			}						
		}
		
		m_tess->SetVariable("tessedit_char_whitelist","ABCEHKMOPTXY");
		for (int j = 4; j < mats.size() && j < 6; ++j) {
			cv::Mat m = mats[j];
			m_tess->SetImage((uchar *)m.data, m.size().width, m.size().height, m.channels(), m.step1());
			m_tess->Recognize(0);
			const char *out = m_tess->GetUTF8Text();
			if (out) {
				str += out[0];
			}
		}
		
//		if (str.length() == 6 || str.length() == 8 || str.length() == 9) {
			plates.push_back(str);
//		}
		
		for (int j = 0; j < ctrs.size(); ++j) {
			cv::Rect r = cv::boundingRect(ctrs[j]);
			if ((r.height > r.width) && r.width > 5) {
				cv::line(candidate, cv::Point(r.x, r.y), cv::Point(r.x + r.width, r.y), cv::Scalar(0, 0,0 ), 1);
				cv::line(candidate, cv::Point(r.x + r.width, r.y), cv::Point(r.x + r.width, r.y + r.height), cv::Scalar(0, 0,0 ), 1);
				cv::line(candidate, cv::Point(r.x + r.width, r.y + r.height), cv::Point(r.x, r.y + r.height), cv::Scalar(0, 0,0 ), 1);
				cv::line(candidate, cv::Point(r.x, r.y + r.height), cv::Point(r.x, r.y), cv::Scalar(0, 0,0 ), 1);
			}
		}

	}
	letters = mats;
	numbers = plates;
}