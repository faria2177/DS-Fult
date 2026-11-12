#include <jni.h>

#include <cstdint>
#include <vector>

#include "ds_page_scanner.h"

// Kotlin: dev.doclens.doclens.NativePageScanner.detectArgbNative(...)
// jniLibs/arm64-v8a is NOT used for the user-supplied proprietary archive.
// This CMake target produces a self-contained application-owned native .so.
extern "C" JNIEXPORT jfloatArray JNICALL
Java_dev_doclens_doclens_NativePageScanner_detectArgbNative(
    JNIEnv* env, jobject /* thiz */, jintArray pixels, jint width,
    jint height, jboolean prefer_card) {
    if (!pixels || width < 64 || height < 64 || width > 2048 ||
        height > 2048 || static_cast<int64_t>(width) * height > 1200000) {
        return nullptr;
    }
    if (env->GetArrayLength(pixels) != width * height) return nullptr;
    std::vector<jint> argb(static_cast<size_t>(width) * height);
    env->GetIntArrayRegion(pixels, 0, static_cast<jsize>(argb.size()), argb.data());
    if (env->ExceptionCheck()) return nullptr;
    ds::Boundary boundary;
    if (!ds::DetectDocument(reinterpret_cast<const uint32_t*>(argb.data()),
                            width, height, prefer_card == JNI_TRUE, &boundary)) {
        return nullptr;
    }
    jfloat result[10]{};
    for (int i = 0; i < 8; ++i) result[i] = boundary.corners[i];
    result[8] = boundary.confidence;
    result[9] = static_cast<float>(boundary.mode);
    jfloatArray answer = env->NewFloatArray(10);
    if (!answer) return nullptr;
    env->SetFloatArrayRegion(answer, 0, 10, result);
    return answer;
}
