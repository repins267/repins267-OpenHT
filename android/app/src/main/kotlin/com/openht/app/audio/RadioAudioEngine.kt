package com.openht.app.audio

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-duplex SBC audio over a dedicated RFCOMM **channel 4** socket to the radio
 * (independent of the flutter_bluetooth_serial command link). Mirrors benlink:
 *
 *  RX: socket -> [AudioDeframer] -> SBC decode -> AudioTrack (speaker) + PCM tap
 *  TX: AudioRecord / injected PCM -> SBC encode -> AudioData frame -> socket
 *      release -> AudioEnd (radio keys on AudioData, unkeys on AudioEnd; PB5 is
 *      driven internally by the radio firmware).
 *
 * All socket writes go through a single writer thread (serialized, like benlink's
 * write mutex). Callbacks are invoked on background threads; the host marshals
 * them to the main thread for the platform channels.
 */
class RadioAudioEngine(
    private val context: Context,
    private val onState: (String) -> Unit,
    private val onPcm: (ByteArray) -> Unit,
) {
    companion object {
        private const val TAG = "OpenHtAudio"
        private const val SAMPLE_RATE = 32000
        // RFCOMM *server channel* for the audio DLC. btsnoop of the vendor app
        // shows SBC audio on DLCI 4 == server channel 2 (commands are on server
        // channel 4 / DLCI 8). benlink's "ch4" was the DLCI; Android's
        // createRfcommSocket(int) takes the server channel, so this is 2.
        private const val AUDIO_CHANNEL = 2
        // How many SBC code-blocks to batch per AudioData frame / per mic read.
        private const val BLOCKS_PER_PACKET = 8
        // Time to let the final AudioEnd drain before the radio unkeys.
        private const val UNKEY_DRAIN_MS = 200L
    }

    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager)?.adapter
            ?: BluetoothAdapter.getDefaultAdapter()

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: OutputStream? = null
    @Volatile private var input: InputStream? = null

    private val running = AtomicBoolean(false)
    private var rxThread: Thread? = null
    private var writerThread: Thread? = null
    private val writeQueue = LinkedBlockingQueue<ByteArray>()

    private var track: AudioTrack? = null
    // Codecs are created lazily on first open() so a native-load failure can't
    // crash app startup (the engine is built in configureFlutterEngine).
    private var decoder: SbcDecoder? = null
    private val deframer = AudioDeframer()
    // Diagnostics: a periodic RX heartbeat (unambiguous during continuous RX,
    // unlike a first-N cap which goes silent once exhausted) + unknown-type logs.
    private var rxFrameCount = 0L
    private var rxByteCount = 0L
    private var rxLastHeartbeat = 0L
    private var rxUnkLogged = 0

    // ---- TX state (mic + injected PCM share one encoder + leftover buffer) ----
    private var txEncoder: SbcEncoder? = null
    private val txLock = Any()
    private var txLeftover = ByteArray(0)
    private val micActive = AtomicBoolean(false)
    private var micThread: Thread? = null
    private var record: AudioRecord? = null

    val isOpen: Boolean get() = running.get()

    // ───────────────────────── lifecycle ─────────────────────────

    @SuppressLint("MissingPermission")
    @Synchronized
    fun open(mac: String) {
        if (running.get()) return
        val a = adapter ?: run { onState("error"); return }
        onState("connecting")
        Thread {
            try {
                // Create codecs (loads libopenht_sbc) before connecting.
                if (decoder == null) decoder = SbcDecoder()
                if (txEncoder == null) txEncoder = SbcEncoder()
                val device = a.getRemoteDevice(mac)
                try { a.cancelDiscovery() } catch (_: SecurityException) {}
                val sock = createRfcommSocket(device, AUDIO_CHANNEL)
                sock.connect() // blocking
                socket = sock
                output = sock.outputStream
                input = sock.inputStream
                running.set(true)
                startAudioTrack()
                startWriter()
                startRx()
                onState("connected")
                Log.i(TAG, "ch2 audio socket connected (DLCI 4) to $mac")
            } catch (e: Exception) {
                Log.e(TAG, "open() failed: ${e.message}", e)
                cleanup()
                onState("error")
            }
        }.start()
    }

    @Synchronized
    fun close() {
        if (!running.get() && socket == null) return
        try { stopMicPtt() } catch (_: Exception) {}
        // Best-effort unkey before tearing down.
        try {
            output?.let { it.write(AudioFraming.buildAudioEnd()); it.flush() }
            Thread.sleep(UNKEY_DRAIN_MS)
        } catch (_: Exception) {}
        cleanup()
        onState("disconnected")
    }

    private fun cleanup() {
        running.set(false)
        micActive.set(false)
        writeQueue.clear()
        writerThread?.interrupt(); writerThread = null
        rxThread?.interrupt(); rxThread = null
        micThread?.interrupt(); micThread = null
        try { record?.stop() } catch (_: Exception) {}
        try { record?.release() } catch (_: Exception) {}
        record = null
        try { track?.stop() } catch (_: Exception) {}
        try { track?.release() } catch (_: Exception) {}
        track = null
        try { input?.close() } catch (_: Exception) {}
        try { output?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        input = null; output = null; socket = null
        deframer.reset()
        synchronized(txLock) { txLeftover = ByteArray(0) }
    }

    fun dispose() {
        close()
        decoder?.close(); decoder = null
        txEncoder?.close(); txEncoder = null
    }

    // ───────────────────────── RX ─────────────────────────

    private fun startAudioTrack() {
        val minBuf = AudioTrack.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(4096)
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(minBuf * 2)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        t.play()
        track = t
    }

    private fun startRx() {
        rxThread = Thread {
            val buf = ByteArray(1024)
            val ins = input ?: return@Thread
            try {
                while (running.get()) {
                    val n = ins.read(buf)
                    if (n < 0) break
                    if (n == 0) continue
                    for (msg in deframer.push(buf.copyOf(n))) {
                        when (msg.type) {
                            AudioFraming.TYPE_DATA, AudioFraming.TYPE_DATA_FM -> {
                                if (msg.payload.isEmpty()) continue
                                // Transceiver audio (0x00) is acked 1:1 (radio may
                                // gate RX flow on it); FM-broadcast audio (0x09) is
                                // not acked on the wire (btsnoop-verified).
                                if (msg.type == AudioFraming.TYPE_DATA && running.get()) {
                                    writeQueue.offer(AudioFraming.buildAudioAck())
                                }
                                val dec = decoder ?: continue
                                val pcm = try { dec.decode(msg.payload) } catch (e: Exception) {
                                    Log.w(TAG, "decode error: ${e.message}"); continue
                                }
                                if (pcm.isNotEmpty()) {
                                    try { track?.write(pcm, 0, pcm.size) } catch (_: Exception) {}
                                    onPcm(pcm)
                                }
                                // Periodic heartbeat: counts frames/bytes over ~2s
                                // windows so a running RX stream always logs (and a
                                // dead one is obvious by the absence of heartbeats).
                                rxFrameCount++
                                rxByteCount += pcm.size
                                val now = android.os.SystemClock.elapsedRealtime()
                                if (rxLastHeartbeat == 0L) rxLastHeartbeat = now
                                if (now - rxLastHeartbeat >= 2000L) {
                                    Log.i(TAG, "RX heartbeat: %d frames, %d PCM bytes in %dms (last type=0x%02x)"
                                        .format(rxFrameCount, rxByteCount, now - rxLastHeartbeat, msg.type))
                                    rxFrameCount = 0; rxByteCount = 0; rxLastHeartbeat = now
                                }
                            }
                            AudioFraming.TYPE_END -> Log.d(TAG, "RX AudioEnd")
                            AudioFraming.TYPE_ACK -> Log.d(TAG, "RX AudioAck")
                            else -> if (rxUnkLogged < 20) {
                                val head = msg.payload.take(6).joinToString("") { "%02x".format(it) }
                                Log.i(TAG, "RX UNKNOWN type=0x%02x len=%d head=%s"
                                    .format(msg.type, msg.payload.size, head))
                                rxUnkLogged++
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "RX loop ended: ${e.message}")
            } finally {
                if (running.get()) { cleanup(); onState("disconnected") }
            }
        }.also { it.isDaemon = true; it.name = "openht-audio-rx"; it.start() }
    }

    // ───────────────────────── TX ─────────────────────────

    private fun startWriter() {
        writerThread = Thread {
            try {
                while (running.get()) {
                    val frame = writeQueue.take()
                    val out = output ?: break
                    out.write(frame)
                    out.flush()
                }
            } catch (e: InterruptedException) {
                // shutdown
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "writer ended: ${e.message}")
            }
        }.also { it.isDaemon = true; it.name = "openht-audio-tx"; it.start() }
    }

    /** Encode whole code-blocks from accumulated PCM and enqueue one AudioData frame. */
    private fun feedTxPcm(pcm: ByteArray, flush: Boolean) {
        synchronized(txLock) {
            val enc = txEncoder ?: return
            val data = if (txLeftover.isEmpty()) pcm else txLeftover + pcm
            val cs = enc.codesize
            if (cs <= 0) return
            val whole = (data.size / cs) * cs
            if (whole > 0) {
                val block = data.copyOfRange(0, whole)
                txLeftover = data.copyOfRange(whole, data.size)
                val sbc = enc.encode(block)
                if (sbc.isNotEmpty() && running.get()) {
                    writeQueue.offer(AudioFraming.buildAudioData(sbc))
                }
            } else {
                txLeftover = data
            }
            if (flush && txLeftover.isNotEmpty()) {
                // pad final partial block with silence so no audio is dropped
                val pad = ByteArray(cs - txLeftover.size)
                val sbc = enc.encode(txLeftover + pad)
                txLeftover = ByteArray(0)
                if (sbc.isNotEmpty() && running.get()) {
                    writeQueue.offer(AudioFraming.buildAudioData(sbc))
                }
            }
        }
    }

    /** Inject app-generated PCM (s16le mono 32 kHz), e.g. SSTV tones. Does NOT unkey. */
    fun sendPcm(pcm: ByteArray) {
        if (!running.get()) return
        feedTxPcm(pcm, flush = false)
    }

    /** Flush any buffered TX PCM and send AudioEnd to unkey the radio. */
    fun endTx() {
        if (!running.get()) return
        synchronized(txLock) {
            if (txLeftover.isNotEmpty()) feedTxPcm(ByteArray(0), flush = true)
        }
        writeQueue.offer(AudioFraming.buildAudioEnd())
    }

    @SuppressLint("MissingPermission")
    fun startMicPtt() {
        if (!running.get() || micActive.get()) return
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "RECORD_AUDIO not granted"); onState("mic_denied"); return
        }
        val cs = (txEncoder?.codesize ?: 256).coerceAtLeast(256)
        val chunk = cs * BLOCKS_PER_PACKET
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(chunk * 2)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, minBuf
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord init failed"); rec.release(); onState("mic_error"); return
        }
        record = rec
        micActive.set(true)
        rec.startRecording()
        micThread = Thread {
            val buf = ByteArray(chunk)
            try {
                while (micActive.get() && running.get()) {
                    var filled = 0
                    while (filled < chunk && micActive.get()) {
                        val n = rec.read(buf, filled, chunk - filled)
                        if (n <= 0) break
                        filled += n
                    }
                    if (filled > 0) feedTxPcm(buf.copyOf(filled), flush = false)
                }
            } catch (e: Exception) {
                Log.w(TAG, "mic loop ended: ${e.message}")
            }
        }.also { it.isDaemon = true; it.name = "openht-audio-mic"; it.start() }
        onState("tx")
    }

    fun stopMicPtt() {
        if (!micActive.getAndSet(false)) return
        try { record?.stop() } catch (_: Exception) {}
        try { record?.release() } catch (_: Exception) {}
        record = null
        micThread?.interrupt(); micThread = null
        endTx()
        if (running.get()) onState("connected")
    }

    // ───────────────────────── RFCOMM raw-channel socket ─────────────────────────

    /**
     * The radio's audio endpoint is a raw RFCOMM channel (4), not an SDP UUID, so we
     * use the hidden createInsecureRfcommSocket(int) (preferred; no pairing-PIN auth
     * stall) and fall back to createRfcommSocket(int). benlink connects the same way.
     */
    private fun createRfcommSocket(
        device: android.bluetooth.BluetoothDevice, channel: Int
    ): BluetoothSocket {
        return try {
            val m = device.javaClass.getMethod("createInsecureRfcommSocket", Int::class.javaPrimitiveType)
            m.invoke(device, channel) as BluetoothSocket
        } catch (e: Exception) {
            val m = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            m.invoke(device, channel) as BluetoothSocket
        }
    }
}
