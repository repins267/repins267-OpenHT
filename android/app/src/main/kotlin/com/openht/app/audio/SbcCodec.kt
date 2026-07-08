package com.openht.app.audio

/**
 * JNI bridge to BlueZ libsbc (see android/app/src/main/cpp/sbc_jni.cpp).
 *
 * The native methods are instance methods (they receive `this`), so callers use
 * an [SbcCodec] instance. Use the [SbcEncoder] / [SbcDecoder] wrappers rather
 * than calling the raw natives directly.
 */
class SbcCodec {
    external fun nativeNewEncoder(
        freq: Int, mode: Int, subbands: Int, blocks: Int, allocation: Int, bitpool: Int
    ): Long

    external fun nativeNewDecoder(): Long
    external fun nativeFree(handle: Long)
    external fun nativeCodesize(handle: Long): Int
    external fun nativeFrameLength(handle: Long): Int
    external fun nativeEncode(handle: Long, pcm: ByteArray): ByteArray
    external fun nativeDecode(handle: Long, sbc: ByteArray): ByteArray

    companion object {
        // libsbc constants (mirror sbc.h)
        const val FREQ_16000 = 0x00
        const val FREQ_32000 = 0x01
        const val FREQ_44100 = 0x02
        const val FREQ_48000 = 0x03

        const val BLK_4 = 0x00
        const val BLK_8 = 0x01
        const val BLK_12 = 0x02
        const val BLK_16 = 0x03

        const val MODE_MONO = 0x00
        const val MODE_DUAL = 0x01
        const val MODE_STEREO = 0x02
        const val MODE_JOINT_STEREO = 0x03

        const val AM_LOUDNESS = 0x00
        const val AM_SNR = 0x01

        const val SB_4 = 0x00
        const val SB_8 = 0x01

        /** VR-N76 audio channel bitpool — btsnoop-verified against the vendor app
         *  (com.benshikj.ht): SBC 32 kHz mono SB8 BLK16 Loudness, bitpool 18
         *  (44-byte frames). benlink used 16; the factory app uses 18. */
        const val DEFAULT_BITPOOL = 18

        @Volatile
        private var loaded = false

        @Synchronized
        fun ensureLoaded() {
            if (!loaded) {
                System.loadLibrary("openht_sbc")
                loaded = true
            }
        }
    }
}

/**
 * SBC encoder configured for the VR-N76 audio channel: 32 kHz, mono, 8 subbands,
 * 16 blocks, Loudness allocation. [bitpool] is tunable so a btsnoop byte-compare
 * can correct it if the radio differs.
 */
class SbcEncoder(bitpool: Int = SbcCodec.DEFAULT_BITPOOL) {
    private val codec = SbcCodec()
    private var handle: Long

    init {
        SbcCodec.ensureLoaded()
        handle = codec.nativeNewEncoder(
            SbcCodec.FREQ_32000, SbcCodec.MODE_MONO, SbcCodec.SB_8,
            SbcCodec.BLK_16, SbcCodec.AM_LOUDNESS, bitpool
        )
        require(handle != 0L) { "sbc_init encoder failed" }
    }

    /** PCM bytes (s16le, mono) consumed per produced SBC frame. */
    val codesize: Int get() = codec.nativeCodesize(handle)

    /** Compressed bytes per SBC frame. */
    val frameLength: Int get() = codec.nativeFrameLength(handle)

    /** Encodes whole code-blocks in [pcm]; trailing partial-block bytes are ignored. */
    fun encode(pcm: ByteArray): ByteArray = codec.nativeEncode(handle, pcm)

    fun close() {
        if (handle != 0L) {
            codec.nativeFree(handle)
            handle = 0L
        }
    }
}

/** SBC decoder; self-configures from each frame header. */
class SbcDecoder {
    private val codec = SbcCodec()
    private var handle: Long

    init {
        SbcCodec.ensureLoaded()
        handle = codec.nativeNewDecoder()
        require(handle != 0L) { "sbc_init decoder failed" }
    }

    /** Decodes every whole SBC frame in [sbc]; returns PCM s16le. */
    fun decode(sbc: ByteArray): ByteArray = codec.nativeDecode(handle, sbc)

    fun close() {
        if (handle != 0L) {
            codec.nativeFree(handle)
            handle = 0L
        }
    }
}
