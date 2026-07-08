// sbc_jni.cpp — thin JNI bridge over BlueZ libsbc for OpenHT.
//
// Exposes encode/decode to com.openht.app.audio.SbcCodec. Encoder is configured
// to match the VR-N76 audio channel (benlink-verified): 32 kHz, mono, 8 subbands,
// 16 blocks, Loudness allocation, bitpool 16, little-endian PCM s16. Decoder
// self-configures from each SBC frame header.
//
// All buffers are heap-free per call (small, mono); a handle is an sbc_t* boxed
// in a jlong.

#include <jni.h>
#include <android/log.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

extern "C" {
#include "sbc.h"
}

#define LOG_TAG "OpenHtSbc"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

inline sbc_t *as_sbc(jlong h) { return reinterpret_cast<sbc_t *>(static_cast<uintptr_t>(h)); }

} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_openht_app_audio_SbcCodec_nativeNewEncoder(
        JNIEnv *, jobject, jint freq, jint mode, jint subbands,
        jint blocks, jint allocation, jint bitpool) {
    sbc_t *s = static_cast<sbc_t *>(calloc(1, sizeof(sbc_t)));
    if (!s) return 0;
    if (sbc_init(s, 0) < 0) {
        free(s);
        return 0;
    }
    s->frequency = static_cast<uint8_t>(freq);
    s->mode = static_cast<uint8_t>(mode);
    s->subbands = static_cast<uint8_t>(subbands);
    s->blocks = static_cast<uint8_t>(blocks);
    s->allocation = static_cast<uint8_t>(allocation);
    s->bitpool = static_cast<uint8_t>(bitpool);
    s->endian = SBC_LE;
    return static_cast<jlong>(reinterpret_cast<uintptr_t>(s));
}

JNIEXPORT jlong JNICALL
Java_com_openht_app_audio_SbcCodec_nativeNewDecoder(JNIEnv *, jobject) {
    sbc_t *s = static_cast<sbc_t *>(calloc(1, sizeof(sbc_t)));
    if (!s) return 0;
    if (sbc_init(s, 0) < 0) {
        free(s);
        return 0;
    }
    s->endian = SBC_LE;
    return static_cast<jlong>(reinterpret_cast<uintptr_t>(s));
}

JNIEXPORT void JNICALL
Java_com_openht_app_audio_SbcCodec_nativeFree(JNIEnv *, jobject, jlong h) {
    if (!h) return;
    sbc_t *s = as_sbc(h);
    sbc_finish(s);
    free(s);
}

// Uncompressed bytes consumed to produce one SBC frame (PCM s16, all channels).
JNIEXPORT jint JNICALL
Java_com_openht_app_audio_SbcCodec_nativeCodesize(JNIEnv *, jobject, jlong h) {
    if (!h) return 0;
    return static_cast<jint>(sbc_get_codesize(as_sbc(h)));
}

// Compressed bytes per SBC frame.
JNIEXPORT jint JNICALL
Java_com_openht_app_audio_SbcCodec_nativeFrameLength(JNIEnv *, jobject, jlong h) {
    if (!h) return 0;
    return static_cast<jint>(sbc_get_frame_length(as_sbc(h)));
}

// Encode as many whole code blocks as the PCM holds. Returns the concatenated
// SBC frames (may be empty if < 1 block of input).
JNIEXPORT jbyteArray JNICALL
Java_com_openht_app_audio_SbcCodec_nativeEncode(
        JNIEnv *env, jobject, jlong h, jbyteArray pcm) {
    if (!h || !pcm) return env->NewByteArray(0);
    sbc_t *s = as_sbc(h);
    const size_t codesize = sbc_get_codesize(s);
    if (codesize == 0) return env->NewByteArray(0);

    const jsize inLen = env->GetArrayLength(pcm);
    jbyte *in = env->GetByteArrayElements(pcm, nullptr);
    if (!in) return env->NewByteArray(0);

    std::vector<uint8_t> out;
    uint8_t frame[1024];
    size_t off = 0;
    while (off + codesize <= static_cast<size_t>(inLen)) {
        ssize_t written = 0;
        ssize_t consumed = sbc_encode(s, in + off, codesize,
                                      frame, sizeof(frame), &written);
        if (consumed <= 0 || written <= 0) break;
        out.insert(out.end(), frame, frame + written);
        off += static_cast<size_t>(consumed);
    }
    env->ReleaseByteArrayElements(pcm, in, JNI_ABORT);

    jbyteArray res = env->NewByteArray(static_cast<jsize>(out.size()));
    if (res && !out.empty())
        env->SetByteArrayRegion(res, 0, static_cast<jsize>(out.size()),
                                reinterpret_cast<const jbyte *>(out.data()));
    return res;
}

// Decode every whole SBC frame present in the input. Returns PCM s16le bytes.
JNIEXPORT jbyteArray JNICALL
Java_com_openht_app_audio_SbcCodec_nativeDecode(
        JNIEnv *env, jobject, jlong h, jbyteArray sbcArr) {
    if (!h || !sbcArr) return env->NewByteArray(0);
    sbc_t *s = as_sbc(h);

    const jsize inLen = env->GetArrayLength(sbcArr);
    jbyte *in = env->GetByteArrayElements(sbcArr, nullptr);
    if (!in) return env->NewByteArray(0);

    std::vector<uint8_t> out;
    uint8_t pcm[8192];
    size_t off = 0;
    while (off < static_cast<size_t>(inLen)) {
        size_t written = 0;
        ssize_t consumed = sbc_decode(s, in + off,
                                      static_cast<size_t>(inLen) - off,
                                      pcm, sizeof(pcm), &written);
        if (consumed <= 0) break;
        if (written > 0) out.insert(out.end(), pcm, pcm + written);
        off += static_cast<size_t>(consumed);
    }
    env->ReleaseByteArrayElements(sbcArr, in, JNI_ABORT);

    jbyteArray res = env->NewByteArray(static_cast<jsize>(out.size()));
    if (res && !out.empty())
        env->SetByteArrayRegion(res, 0, static_cast<jsize>(out.size()),
                                reinterpret_cast<const jbyte *>(out.data()));
    return res;
}

} // extern "C"
