#include <jni.h>

#include <cstdint>
#include "ds_image_enhancer.h"

// Kotlin: dev.doclens.doclens.NativeImageEnhancer.enhanceArgbNative()
extern "C" JNIEXPORT jboolean JNICALL
Java_dev_doclens_doclens_NativeImageEnhancer_enhanceArgbNative(
    JNIEnv* env, jobject /* instance */, jintArray pixels,
    jint width, jint height, jboolean black_and_white) {
    if (!pixels || width < 8 || height < 8 || width > 3200 ||
        height > 3200 || static_cast<int64_t>(width) * height > 8000000) {
        return JNI_FALSE;
    }
    if (env->GetArrayLength(pixels) != width * height) return JNI_FALSE;
    jint* buffer = env->GetIntArrayElements(pixels, nullptr);
    if (!buffer) return JNI_FALSE;
    const bool success = ds::EnhanceArgb(
        reinterpret_cast<uint32_t*>(buffer), width, height,
        black_and_white == JNI_TRUE);
    env->ReleaseIntArrayElements(pixels, buffer, success ? 0 : JNI_ABORT);
    return success ? JNI_TRUE : JNI_FALSE;
}
