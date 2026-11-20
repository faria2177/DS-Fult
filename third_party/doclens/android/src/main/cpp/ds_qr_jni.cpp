#include <jni.h>

#include <cstdint>
#include <string>
#include <vector>

#include "ds_qr.h"

// Kotlin: dev.doclens.doclens.QrReader.readNative(...)
// Returns [format, text, "x,y,x,y,x,y,x,y", format, text, ...] or null.
extern "C" JNIEXPORT jobjectArray JNICALL
Java_dev_doclens_doclens_QrReader_readNative(JNIEnv* env, jobject /* thiz */,
                                             jbyteArray luma, jint width,
                                             jint height, jboolean try_harder) {
    if (!luma || width < 16 || height < 16 || width > 8192 || height > 8192) {
        return nullptr;
    }
    if (env->GetArrayLength(luma) != width * height) return nullptr;
    jbyte* data = env->GetByteArrayElements(luma, nullptr);
    if (!data) return nullptr;
    std::vector<ds::Code> codes;
    const bool ok = ds::ReadCodes(reinterpret_cast<const uint8_t*>(data), width,
                                  height, try_harder == JNI_TRUE, &codes);
    env->ReleaseByteArrayElements(luma, data, JNI_ABORT);
    if (!ok || codes.empty()) return nullptr;
    jclass string_class = env->FindClass("java/lang/String");
    if (!string_class) return nullptr;
    const jsize n = static_cast<jsize>(codes.size() * 3);
    jobjectArray out = env->NewObjectArray(n, string_class, nullptr);
    if (!out) return nullptr;
    jclass charset_holder = env->FindClass("java/nio/charset/StandardCharsets");
    if (!charset_holder) return nullptr;
    jfieldID utf8_field = env->GetStaticFieldID(
        charset_holder, "UTF_8", "Ljava/nio/charset/Charset;");
    jobject utf8 = utf8_field ? env->GetStaticObjectField(charset_holder, utf8_field) : nullptr;
    jmethodID ctor = env->GetMethodID(string_class, "<init>",
                                      "([BLjava/nio/charset/Charset;)V");
    if (!utf8 || !ctor) return nullptr;
    for (size_t i = 0; i < codes.size(); ++i) {
        std::string corners;
        for (size_t k = 0; k < 8; ++k) {
            if (k) corners += ',';
            corners += std::to_string(codes[i].corners[k]);
        }
        // Modified UTF-8 differs from UTF-8 only for NUL and 4-byte
        // characters; pass bytes through a Java String constructor instead.
        const std::string* parts[3] = {&codes[i].format, &codes[i].text, &corners};
        for (int p = 0; p < 3; ++p) {
            const std::string& s = *parts[p];
            jbyteArray bytes = env->NewByteArray(static_cast<jsize>(s.size()));
            if (!bytes) return nullptr;
            env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(s.size()),
                                    reinterpret_cast<const jbyte*>(s.data()));
            jobject str = env->NewObject(string_class, ctor, bytes, utf8);
            env->SetObjectArrayElement(out, static_cast<jsize>(i * 3 + static_cast<size_t>(p)), str);
            env->DeleteLocalRef(str);
            env->DeleteLocalRef(bytes);
        }
    }
    return out;
}
