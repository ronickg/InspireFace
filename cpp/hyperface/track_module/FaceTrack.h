//
// Created by tunm on 2023/8/29.
//
#pragma once
#ifndef HYPERFACEREPO_FACETRACK_H
#define HYPERFACEREPO_FACETRACK_H
#include <iostream>
#include "face_detect/FaceDetect.h"
#include "face_detect/RNet.h"
#include "landmark/FaceLandmark.h"
#include "face_info/all.h"
#include "middleware/camera_stream/camera_stream.h"

using namespace std;

namespace hyper {

class HYPER_API FaceTrack {
public:

    FaceTrack();

    int Configuration(ModelLoader &loader);

    void UpdateStream(CameraStream &image, bool is_detect);

private:


    void SparseLandmarkPredict(const cv::Mat &raw_face_crop,
                               std::vector<cv::Point2f> &landmarks_output,
                               float &score, float size);

    bool TrackFace(CameraStream &image, FaceObject &face);

    static void BlackingTrackingRegion(cv::Mat &image, cv::Rect &rect_mask);

    void nms(float th = 0.5);

    void DetectFace(const cv::Mat &input, float scale);

    int InitLandmarkModel(Model* model);
    int InitDetectModel(Model* model);
    int InitRNetModel(Model* model);

public:

    std::vector<FaceObject> trackingFace;

private:
    std::vector<FaceObject> candidate_faces_;
    int detection_index_;
    int detection_interval_ = 1;
    int tracking_idx_;
    double det_use_time_;
    double track_total_use_time_;
    int max_detected_faces_ = 2;

private:

    std::shared_ptr<FaceDetect> m_face_detector_;

    std::shared_ptr<FaceLandmark> m_landmark_predictor_;

    std::shared_ptr<RNet> m_refine_net_;

};

}   // namespace hyper

#endif //HYPERFACEREPO_FACETRACK_H
