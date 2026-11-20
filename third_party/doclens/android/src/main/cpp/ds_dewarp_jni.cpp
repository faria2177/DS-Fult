#include <jni.h>

#include <array>
#include <cstdint>
#include <vector>

#include "ds_dewarp.h"

// Kotlin: dev.doclens.doclens.NativeDewarp.dewarpNative(...)
// Returns the flattened page (outW×outH ARGB) or null when the page's sides
// are straight or unclear (the caller then uses its perspective warp).
extern "C" JNIEXPORT jintArray JNICALL
Java_dev_doclens_doclens_NativeDewarp_dewarpNative(
    JNIEnv* env, jobject /* thiz */, jintArray pixels, jint width, jint height,
    jdoubleArray quad, jint out_width, jint out_height) {
    if (!pixels || !quad || width < 32 || height < 32 || width > 8192 ||
        height > 8192 || out_width < 32 || out_height < 32 ||
        out_width > 8000 || out_height > 8000) {
        return nullptr;
    }
    if (env->GetArrayLength(pixels) != width * height ||
        env->GetArrayLength(quad) != 8) {
        return nullptr;
    }
    std::array<double, 8> corners{};
    env->GetDoubleArrayRegion(quad, 0, 8, corners.data());
    jint* buffer = env->GetIntArrayElements(pixels, nullptr);
    if (!buffer) return nullptr;
    std::vector<uint32_t> out;
    const bool ok = ds::Dewarp(reinterpret_cast<const uint32_t*>(buffer), width,
                               height, corners, out_width, out_height, &out, nullptr);
    env->ReleaseIntArrayElements(pixels, buffer, JNI_ABORT);
    if (!ok) return nullptr;
    jintArray answer = env->NewIntArray(out_width * out_height);
    if (!answer) return nullptr;
    env->SetIntArrayRegion(answer, 0, out_width * out_height,
                           reinterpret_cast<const jint*>(out.data()));
    return answer;
}
