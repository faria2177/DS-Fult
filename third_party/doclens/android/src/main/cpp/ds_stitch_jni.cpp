#include <jni.h>

#include <cstdint>

#include "ds_stitch.h"

// Kotlin: dev.doclens.doclens.LongImageStitcher.findOverlapNative(...)
// Returns {rows, shift, score × 1000} or null when the pages do not overlap.
extern "C" JNIEXPORT jintArray JNICALL
Java_dev_doclens_doclens_LongImageStitcher_findOverlapNative(
    JNIEnv* env, jobject /* thiz */, jbyteArray gray_a, jint height_a,
    jbyteArray gray_b, jint height_b, jint width) {
    if (!gray_a || !gray_b || width < 64 || width > 8000 || height_a < 64 ||
        height_b < 64) {
        return nullptr;
    }
    if (env->GetArrayLength(gray_a) != width * height_a ||
        env->GetArrayLength(gray_b) != width * height_b) {
        return nullptr;
    }
    jbyte* a = env->GetByteArrayElements(gray_a, nullptr);
    jbyte* b = env->GetByteArrayElements(gray_b, nullptr);
    ds::Overlap overlap;
    bool ok = false;
    if (a && b) {
        ok = ds::FindOverlap(reinterpret_cast<const uint8_t*>(a), height_a,
                             reinterpret_cast<const uint8_t*>(b), height_b,
                             width, &overlap);
    }
    if (a) env->ReleaseByteArrayElements(gray_a, a, JNI_ABORT);
    if (b) env->ReleaseByteArrayElements(gray_b, b, JNI_ABORT);
    if (!ok) return nullptr;
    jint result[3] = {overlap.rows, overlap.shift,
                      static_cast<jint>(overlap.score * 1000.0f)};
    jintArray answer = env->NewIntArray(3);
    if (!answer) return nullptr;
    env->SetIntArrayRegion(answer, 0, 3, result);
    return answer;
}
