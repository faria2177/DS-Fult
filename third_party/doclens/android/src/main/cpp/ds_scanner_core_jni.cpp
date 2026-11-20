#include <jni.h>

#include <cstdint>
#include <vector>

#include "ds_scanner_core.h"

// Kotlin: dev.doclens.doclens.NativeScannerCore
// libds_scannercore.so is built from this repository's own sources only.

extern "C" JNIEXPORT jint JNICALL
Java_dev_doclens_doclens_NativeScannerCore_magicEnhanceNative(
    JNIEnv* env, jobject /* thiz */, jintArray pixels, jint width,
    jint height, jboolean only_neutral) {
    // 0: enhanced, 1: not a black-and-white page (untouched), -1: error.
    if (!pixels || width < 8 || height < 8 || width > 8192 || height > 8192 ||
        static_cast<int64_t>(width) * height > 40000000) {
        return -1;
    }
    if (env->GetArrayLength(pixels) != width * height) return -1;
    jint* buffer = env->GetIntArrayElements(pixels, nullptr);
    if (!buffer) return -1;
    auto* argb = reinterpret_cast<uint32_t*>(buffer);
    if (only_neutral == JNI_TRUE && !ds::IsNeutralDocument(argb, width, height)) {
        env->ReleaseIntArrayElements(pixels, buffer, JNI_ABORT);
        return 1;
    }
    const bool ok = ds::MagicEnhance(argb, width, height);
    env->ReleaseIntArrayElements(pixels, buffer, ok ? 0 : JNI_ABORT);
    return ok ? 0 : -1;
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_dev_doclens_doclens_NativeScannerCore_paperRegionNative(
    JNIEnv* env, jobject /* thiz */, jintArray pixels, jint width,
    jint height) {
    // [found, paperFraction, TLx, TLy, TRx, TRy, BRx, BRy, BLx, BLy]
    if (!pixels || width < 32 || height < 32 || width > 2048 || height > 2048) {
        return nullptr;
    }
    if (env->GetArrayLength(pixels) != width * height) return nullptr;
    std::vector<jint> argb(static_cast<size_t>(width) * height);
    env->GetIntArrayRegion(pixels, 0, static_cast<jsize>(argb.size()), argb.data());
    if (env->ExceptionCheck()) return nullptr;
    ds::PaperRegion region;
    if (!ds::FindPaperRegion(reinterpret_cast<const uint32_t*>(argb.data()),
                             width, height, &region)) {
        return nullptr;
    }
    jfloat out[10]{};
    out[0] = region.found ? 1.0f : 0.0f;
    out[1] = region.paper_fraction;
    for (int i = 0; i < 8; ++i) out[2 + i] = region.corners[static_cast<size_t>(i)];
    jfloatArray answer = env->NewFloatArray(10);
    if (!answer) return nullptr;
    env->SetFloatArrayRegion(answer, 0, 10, out);
    return answer;
}
