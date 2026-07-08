package com.openht.app

import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.openht.app.audio.RadioAudioEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioChannel = "com.openht.app/audio"
    private val audioRxChannel = "com.openht.app/audio_rx"
    private val rbChannel = "com.openht.app/repeaterbook"

    private val main = Handler(Looper.getMainLooper())

    private var audioMethodChannel: MethodChannel? = null
    private var rxSink: EventChannel.EventSink? = null
    private var audioEngine: RadioAudioEngine? = null

    // Diagnostics: rate-limited PCM-tap heartbeat (chunks forwarded to Dart +
    // whether a Dart consumer is currently subscribed).
    private var pcmTapCount = 0L
    private var pcmTapLast = 0L

    // ── Flutter engine setup ──────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ── RX PCM tap (decoded s16le mono 32 kHz) → Dart DSP (SSTV/APT/LRPT) ──
        EventChannel(messenger, audioRxChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    rxSink = events
                }

                override fun onCancel(arguments: Any?) {
                    rxSink = null
                }
            }
        )

        // ── RFCOMM ch4 SBC audio engine ───────────────────────────────────────
        val ch = MethodChannel(messenger, audioChannel)
        audioMethodChannel = ch

        val engine = RadioAudioEngine(
            context = applicationContext,
            onState = { state ->
                main.post {
                    audioMethodChannel?.invokeMethod("audioStateChanged", mapOf("state" to state))
                }
            },
            onPcm = { pcm ->
                main.post {
                    val sink = rxSink
                    sink?.success(pcm)
                    pcmTapCount++
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (pcmTapLast == 0L) pcmTapLast = now
                    if (now - pcmTapLast >= 2000L) {
                        android.util.Log.i("OpenHtAudio",
                            "PCM tap: %d chunks to Dart in %dms (dartListener=%b)"
                                .format(pcmTapCount, now - pcmTapLast, sink != null))
                        pcmTapCount = 0; pcmTapLast = now
                    }
                }
            },
        )
        audioEngine = engine

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // RX monitor: open/close the dedicated ch4 audio socket.
                "openAudio" -> {
                    val mac = call.argument<String>("mac")
                    if (mac.isNullOrEmpty()) {
                        result.error("NO_MAC", "openAudio requires 'mac'", null)
                    } else {
                        engine.open(mac); result.success(null)
                    }
                }
                "closeAudio" -> { engine.close(); result.success(null) }

                // TX voice (mic) PTT.
                "startPtt" -> { engine.startMicPtt(); result.success(null) }
                "stopPtt" -> { engine.stopMicPtt(); result.success(null) }

                // TX injected PCM (SSTV tones / wx uplink). 'endTx' unkeys.
                "sendPcm" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                    if (pcm == null) result.error("NO_PCM", "sendPcm requires 'pcm'", null)
                    else { engine.sendPcm(pcm); result.success(null) }
                }
                "endTx" -> { engine.endTx(); result.success(null) }

                "isOpen" -> result.success(engine.isOpen)

                else -> result.notImplemented()
            }
        }

        // ── RepeaterBook Connect channel ──────────────────────────────────────
        MethodChannel(messenger, rbChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> {
                        val installed = try {
                            packageManager.getPackageInfo("com.zbm2.repeaterbook", 0)
                            true
                        } catch (_: PackageManager.NameNotFoundException) { false }
                        result.success(installed)
                    }
                    "queryRepeaters" -> {
                        Thread {
                            try {
                                val uri = Uri.parse(
                                    "content://com.zbm2.repeaterbook.RBContentProvider/repeaters"
                                )
                                val cursor = contentResolver.query(uri, null, null, null, null)
                                if (cursor == null) {
                                    android.util.Log.w("OpenHT", "RB: cursor null — app not installed or provider not exported")
                                    result.success(emptyList<Map<String, Any?>>())
                                    return@Thread
                                }
                                android.util.Log.i("OpenHT", "RB: ${cursor.count} rows, columns=${cursor.columnNames.toList()}")
                                if (cursor.count == 0) {
                                    android.util.Log.w("OpenHT", "RB: database empty — open RepeaterBook app and load your area first")
                                    cursor.close()
                                    result.success(emptyList<Map<String, Any?>>())
                                    return@Thread
                                }
                                val rows = mutableListOf<Map<String, Any?>>()
                                cursor.use {
                                    while (it.moveToNext()) {
                                        val row = mutableMapOf<String, Any?>()
                                        for (col in it.columnNames) {
                                            val idx = it.getColumnIndex(col)
                                            row[col] = when (it.getType(idx)) {
                                                android.database.Cursor.FIELD_TYPE_INTEGER -> it.getLong(idx)
                                                android.database.Cursor.FIELD_TYPE_FLOAT -> it.getDouble(idx)
                                                android.database.Cursor.FIELD_TYPE_STRING -> it.getString(idx)
                                                else -> null
                                            }
                                        }
                                        rows.add(row)
                                    }
                                }
                                result.success(rows)
                            } catch (e: Exception) {
                                result.error("RB_QUERY_FAILED", e.message, null)
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioEngine?.dispose()
        audioEngine = null
    }
}
