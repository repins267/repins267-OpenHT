package com.openht.app.audio

import java.io.ByteArrayOutputStream

/**
 * VR-N76 RFCOMM ch4 audio framing — `0x7e`-delimited, `0x7d`-escaped frames whose
 * first (unescaped) byte is a type tag. Direct port of benlink `protocol/audio.py`
 * and BenshiDash `audio_protocol.dart`.
 *
 *   AudioData : 0x7e  escape(0x00 + sbcBytes)        0x7e
 *   AudioEnd  : 0x7e  escape(0x01 + 0x00 * 8)        0x7e
 *   AudioAck  : 0x7e  escape(0x02 + ...)             0x7e   (RX only)
 */
object AudioFraming {
    const val DELIM = 0x7e
    const val ESC = 0x7d

    const val TYPE_DATA = 0x00      // transceiver audio (TX + ham RX); acked 1:1
    const val TYPE_END = 0x01
    const val TYPE_ACK = 0x02
    const val TYPE_DATA_FM = 0x09   // FM-broadcast-tuner RX audio (btsnoop-verified);
                                    // same SBC payload as 0x00, but not acked

    private fun escape(src: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(src.size + 8)
        for (b in src) {
            val v = b.toInt() and 0xFF
            if (v == ESC || v == DELIM) {
                out.write(ESC)
                out.write(v xor 0x20)
            } else {
                out.write(v)
            }
        }
        return out.toByteArray()
    }

    fun unescape(src: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(src.size)
        var i = 0
        while (i < src.size) {
            val v = src[i].toInt() and 0xFF
            if (v == ESC) {
                i++
                if (i < src.size) out.write((src[i].toInt() and 0xFF) xor 0x20)
            } else {
                out.write(v)
            }
            i++
        }
        return out.toByteArray()
    }

    private fun frame(payload: ByteArray): ByteArray {
        val esc = escape(payload)
        val out = ByteArray(esc.size + 2)
        out[0] = DELIM.toByte()
        System.arraycopy(esc, 0, out, 1, esc.size)
        out[out.size - 1] = DELIM.toByte()
        return out
    }

    fun buildAudioData(sbc: ByteArray): ByteArray {
        val payload = ByteArray(sbc.size + 1)
        payload[0] = TYPE_DATA.toByte()
        System.arraycopy(sbc, 0, payload, 1, sbc.size)
        return frame(payload)
    }

    /** AudioEnd — btsnoop-verified vendor bytes `01 00 01 00*6` (7 identical
     *  samples, both directions). benlink used all-zeros; the radio accepts that
     *  too, but we match the factory app exactly. */
    fun buildAudioEnd(): ByteArray =
        frame(byteArrayOf(0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))

    /** AudioAck — type byte + 8 zero pad bytes. The vendor app sends one of these
     *  back per received RX AudioData frame (btsnoop: ~1:1). */
    fun buildAudioAck(): ByteArray =
        frame(ByteArray(9).also { it[0] = TYPE_ACK.toByte() })
}

/**
 * Incremental deframer for the RX byte stream. Mirrors `parseAudioFrame` in
 * BenshiDash: scan for the start delimiter, wait for the closing delimiter,
 * unescape, split off the type byte. Garbage before the first delimiter is dropped.
 */
class AudioDeframer {
    private var buf = ByteArray(0)

    data class Message(val type: Int, val payload: ByteArray)

    fun push(data: ByteArray): List<Message> {
        buf = if (buf.isEmpty()) data.copyOf() else buf + data
        val out = ArrayList<Message>()
        while (true) {
            val start = indexOf(buf, AudioFraming.DELIM, 0)
            if (start < 0) {
                buf = ByteArray(0) // no frame start; discard
                break
            }
            val end = indexOf(buf, AudioFraming.DELIM, start + 1)
            if (end < 0) {
                // incomplete frame; keep from start delimiter onward
                if (start > 0) buf = buf.copyOfRange(start, buf.size)
                break
            }
            val frameBytes = buf.copyOfRange(start + 1, end)
            buf = buf.copyOfRange(end + 1, buf.size)
            if (frameBytes.isEmpty()) continue
            val un = AudioFraming.unescape(frameBytes)
            if (un.isEmpty()) continue
            out.add(Message(un[0].toInt() and 0xFF, un.copyOfRange(1, un.size)))
        }
        return out
    }

    fun reset() {
        buf = ByteArray(0)
    }

    private fun indexOf(a: ByteArray, value: Int, from: Int): Int {
        val target = value.toByte()
        var i = from
        while (i < a.size) {
            if (a[i] == target) return i
            i++
        }
        return -1
    }
}
