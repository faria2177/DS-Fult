// libds_docnet.so — runs DocNet, DocScanner's own document-mask model
// (trained by tool/docnet/train.py on synthetic photos), with the ncnn
// inference engine (Tencent ncnn, BSD-3-Clause, linked statically).
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <jni.h>

#include <cmath>
#include <mutex>

#include "net.h"

namespace {

constexpr int kInput = 160;
constexpr int kOutput = 80;

std::mutex g_lock;
ncnn::Net* g_net = nullptr;

}  // namespace

// Kotlin: dev.doclens.doclens.DocNetEngine.loadNative(assets)
extern "C" JNIEXPORT jboolean JNICALL
Java_dev_doclens_doclens_DocNetEngine_loadNative(JNIEnv* env, jobject /* thiz */,
                                                 jobject assets) {
    std::lock_guard<std::mutex> guard(g_lock);
    if (g_net) return JNI_TRUE;
    AAssetManager* manager = AAssetManager_fromJava(env, assets);
    if (!manager) return JNI_FALSE;
    auto* net = new ncnn::Net();
    net->opt.num_threads = 2;
    net->opt.lightmode = true;
    net->opt.use_vulkan_compute = false;
    if (net->load_param(manager, "docnet/docnet.param") != 0 ||
        net->load_model(manager, "docnet/docnet.bin") != 0) {
        delete net;
        return JNI_FALSE;
    }
    g_net = net;
    return JNI_TRUE;
}

// rgb: 160×160×3 bytes. Returns 80×80 document probabilities (0..1).
extern "C" JNIEXPORT jfloatArray JNICALL
Java_dev_doclens_doclens_DocNetEngine_runNative(JNIEnv* env, jobject /* thiz */,
                                                jbyteArray rgb) {
    if (!rgb || env->GetArrayLength(rgb) != kInput * kInput * 3) return nullptr;
    std::lock_guard<std::mutex> guard(g_lock);
    if (!g_net) return nullptr;
    jbyte* bytes = env->GetByteArrayElements(rgb, nullptr);
    if (!bytes) return nullptr;
    ncnn::Mat in = ncnn::Mat::from_pixels(
        reinterpret_cast<const unsigned char*>(bytes), ncnn::Mat::PIXEL_RGB,
        kInput, kInput);
    env->ReleaseByteArrayElements(rgb, bytes, JNI_ABORT);
    const float norm[3] = {1 / 255.f, 1 / 255.f, 1 / 255.f};
    in.substract_mean_normalize(nullptr, norm);

    ncnn::Extractor ex = g_net->create_extractor();
    if (ex.input("in0", in) != 0) return nullptr;
    ncnn::Mat out;
    if (ex.extract("out0", out) != 0) return nullptr;
    if (out.w != kOutput || out.h != kOutput || out.c != 1) return nullptr;

    jfloatArray answer = env->NewFloatArray(kOutput * kOutput);
    if (!answer) return nullptr;
    float prob[kOutput * kOutput];
    const float* logits = out.channel(0);
    for (int i = 0; i < kOutput * kOutput; ++i) {
        prob[i] = 1.f / (1.f + std::exp(-logits[i]));
    }
    env->SetFloatArrayRegion(answer, 0, kOutput * kOutput, prob);
    return answer;
}
