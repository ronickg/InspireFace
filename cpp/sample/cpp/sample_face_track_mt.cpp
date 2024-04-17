//
// Created by Tunm-Air13 on 2024/4/17.
//
#include <iostream>
#include "opencv2/opencv.hpp"
#include "inspireface/c_api/inspireface.h"
#include <thread>

void runFaceTrack(HContextHandle ctxHandle, HImageHandle imageHandle) {
    HF_MultipleFaceData multipleFaceData = {0};
    auto ret = HF_FaceContextRunFaceTrack(ctxHandle, imageHandle, &multipleFaceData);
    if (ret != HSUCCEED) {
        std::cout << "Thread " << std::this_thread::get_id() << " Execute HF_FaceContextRunFaceTrack error: " << ret << std::endl;
    } else {
        std::cout << "Thread " << std::this_thread::get_id() << " successfully executed HF_FaceContextRunFaceTrack.\n";
    }
}

int main(int argc, char* argv[]) {
    // Check whether the number of parameters is correct
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <pack_path> <source_path>\n";
        return 1;
    }

    auto packPath = argv[1];
    auto sourcePath = argv[2];

    std::cout << "Pack file Path: " << packPath << std::endl;
    std::cout << "Source file Path: " << sourcePath << std::endl;

    HResult ret;
    // The resource file must be loaded before it can be used
    ret = HF_InspireFaceLaunch(packPath);
    if (ret != HSUCCEED) {
        std::cout << "Load Resource error: " << ret << std::endl;
        return ret;
    }

    // Enable the functions in the pipeline: mask detection, live detection, and face quality detection
    HInt32 option = HF_ENABLE_QUALITY | HF_ENABLE_MASK_DETECT | HF_ENABLE_LIVENESS;
    // Non-video or frame sequence mode uses IMAGE-MODE, which is always face detection without tracking
    HF_DetectMode detMode = HF_DETECT_MODE_IMAGE;
    // Maximum number of faces detected
    HInt32 maxDetectNum = 5;
    // Handle of the current face SDK algorithm context
    HContextHandle ctxHandle = {0};
    ret = HF_CreateFaceContextFromResourceFileOptional(option, detMode, maxDetectNum, &ctxHandle);
    if (ret != HSUCCEED) {
        std::cout << "Create FaceContext error: " << ret << std::endl;
        return ret;
    }

    // Load a image
    cv::Mat image = cv::imread(sourcePath);
    if (image.empty()) {
        std::cout << "The source entered is not a picture or read error." << std::endl;
        return 1;
    }
    // Prepare an image parameter structure for configuration
    HF_ImageData imageParam = {0};
    imageParam.data = image.data;       // Data buffer
    imageParam.width = image.cols;      // Target view width
    imageParam.height = image.rows;      // Target view width
    imageParam.rotation = CAMERA_ROTATION_0;      // Data source rotate
    imageParam.format = STREAM_BGR;      // Data source format

    // Create an image data stream
    HImageHandle imageHandle = {0};
    ret = HF_CreateImageStream(&imageParam, &imageHandle);
    if (ret != HSUCCEED) {
        std::cout << "Create ImageStream error: " << ret << std::endl;
        return ret;
    }

    // 创建并启动多个线程
    const size_t numThreads = 5; // 定义想要的线程数
    std::vector<std::thread> threads;
    for (size_t i = 0; i < numThreads; ++i) {
        threads.emplace_back(runFaceTrack, ctxHandle, imageHandle);
    }

    // 等待所有线程完成
    for (auto& thread : threads) {
        if (thread.joinable()) {
            thread.join();
        }
    }

    // The memory must be freed at the end of the program
    ret = HF_ReleaseFaceContext(ctxHandle);
    if (ret != HSUCCEED) {
        printf("Release FaceContext error: %lu\n", ret);
        return ret;
    }

    return 0;
}