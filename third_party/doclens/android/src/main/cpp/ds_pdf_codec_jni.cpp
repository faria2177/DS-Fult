#include <jni.h>

#include <cstdint>
#include <vector>

#include "ds_pdf_codec.h"

// Kotlin: dev.doclens.doclens.NativePdfCodec.bilevelG4Native(...)
// Returns the G4 stream when the page is black-and-white enough
// (bilevel share >= minShare and almost no colour), else null.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_dev_doclens_doclens_NativePdfCodec_bilevelG4Native(
    JNIEnv* env, jobject /* thiz */, jintArray pixels, jint width, jint height,
    jdouble min_share, jdouble max_colour) {
    if (!pixels || width < 8 || height < 8 || width > 12000 || height > 12000 ||
        static_cast<int64_t>(width) * height > 60000000) {
        return nullptr;
    }
    if (env->GetArrayLength(pixels) != width * height) return nullptr;
    jint* buffer = env->GetIntArrayElements(pixels, nullptr);
    if (!buffer) return nullptr;
    const auto* argb = reinterpret_cast<const uint32_t*>(buffer);
    std::vector<uint8_t> out;
    bool ok = ds::ColourShare(argb, width, height) <= max_colour;
    if (ok) {
        std::vector<uint8_t> gray(static_cast<size_t>(width) * static_cast<size_t>(height));
        ds::ArgbToGray(argb, width, height, gray.data());
        ok = ds::BilevelShare(gray.data(), width, height) >= min_share &&
             ds::EncodeG4(gray.data(), width, height, 128, &out);
    }
    env->ReleaseIntArrayElements(pixels, buffer, JNI_ABORT);
    if (!ok || out.empty()) return nullptr;
    jbyteArray answer = env->NewByteArray(static_cast<jsize>(out.size()));
    if (!answer) return nullptr;
    env->SetByteArrayRegion(answer, 0, static_cast<jsize>(out.size()),
                            reinterpret_cast<const jbyte*>(out.data()));
    return answer;
}
