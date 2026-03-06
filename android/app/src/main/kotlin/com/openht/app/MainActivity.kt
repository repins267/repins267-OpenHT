package com.openht.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val audioChannel = "com.openht.app/audio"
    private val rbChannel   = "com.openht.app/repeaterbook"

    // Saved reference so the SCO BroadcastReceiver can invoke Dart callbacks.
    private var audioMethodChannel: MethodChannel? = null
    private var scoReceiver: BroadcastReceiver? = null

    // ── SCO state BroadcastReceiver ───────────────────────────────────────────

    private fun registerScoReceiver() {
        scoReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1)
                val stateStr = when (state) {
                    AudioManager.SCO_AUDIO_STATE_CONNECTED    -> "connected"
                    AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> "disconnected"
                    AudioManager.SCO_AUDIO_STATE_ERROR        -> "error"
                    else -> return
                }
                // MethodChannel requires the main thread.
                Handler(Looper.getMainLooper()).post {
                    audioMethodChannel?.invokeMethod(
                        "audioStateChanged",
                        mapOf("state" to stateStr)
                    )
                }
            }
        }
        @Suppress("DEPRECATION")
        registerReceiver(
            scoReceiver,
            IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_CHANGED)
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        scoReceiver?.let { unregisterReceiver(it) }
    }

    // ── Flutter engine setup ──────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Audio SCO channel ─────────────────────────────────────────────────
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
        audioMethodChannel = ch   // Save ref for SCO receiver callback

        ch.setMethodCallHandler { call, result ->
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "startAudio" -> {
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    @Suppress("DEPRECATION")
                    am.requestAudioFocus(
                        null,
                        AudioManager.STREAM_VOICE_CALL,
                        AudioManager.AUDIOFOCUS_GAIN
                    )
                    @Suppress("DEPRECATION")
                    am.startBluetoothSco()
                    @Suppress("DEPRECATION")
                    am.isBluetoothScoOn = true
                    // Route to BT headset if A2DP is active, otherwise phone speaker
                    if (am.isBluetoothA2dpOn) {
                        am.isSpeakerphoneOn = false
                    } else {
                        am.isSpeakerphoneOn = true
                    }
                    result.success(null)
                }
                "stopAudio" -> {
                    @Suppress("DEPRECATION")
                    am.stopBluetoothSco()
                    @Suppress("DEPRECATION")
                    am.isBluetoothScoOn = false
                    am.isSpeakerphoneOn = false
                    am.mode = AudioManager.MODE_NORMAL
                    @Suppress("DEPRECATION")
                    am.abandonAudioFocus(null)
                    result.success(null)
                }
                // SCO in MODE_IN_COMMUNICATION already routes mic → BT.
                // VR-N76 TX key-up is handled from the Dart layer via Benshi protocol.
                "startPtt" -> result.success(null)
                "stopPtt"  -> result.success(null)
                else -> result.notImplemented()
            }
        }

        registerScoReceiver()

        // ── RepeaterBook Connect channel ──────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, rbChannel)
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
                                val cursor = contentResolver.query(
                                    uri, null, null, null, null
                                )
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
                                                android.database.Cursor.FIELD_TYPE_INTEGER ->
                                                    it.getLong(idx)
                                                android.database.Cursor.FIELD_TYPE_FLOAT ->
                                                    it.getDouble(idx)
                                                android.database.Cursor.FIELD_TYPE_STRING ->
                                                    it.getString(idx)
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
}
