# OpenHT — Audio & PTT Reference

> **Source:** HTCommander `RadioAudio.cs` (Ylianst, Apache 2.0)  
> This document covers both SCO monitoring audio and PTT voice transmission.  
> The audio channel is **completely separate** from the control/data RFCOMM channel.

---

## Two Separate Bluetooth Channels

The radio presents as two Bluetooth devices simultaneously:

| Channel | UUID | Purpose |
|---------|------|---------|
| Control | `00001101-0000-1000-8000-00805F9B34FB` | SPP — all MDC protocol commands |
| Audio | `00001203-0000-1000-8000-00805F9B34FB` | GenericAudio — SBC voice frames |

> ⚠️ **UUID correction from earlier docs:** The audio channel uses  
> `00001203` (GenericAudio), NOT `00001102` as previously noted.  
> HTCommander source confirms: `Guid genericAudioUuid = new Guid("00001203-0000-1000-8000-00805f9b34fb");`

Both channels must be independently paired and connected on Android. They operate
simultaneously — control commands flow on SPP while audio streams on GenericAudio.

---

## Audio Frame Format (GenericAudio Channel)

All frames on the audio channel use HDLC-style framing with `0x7E` as start/end markers
and `0x7D` as an escape byte (same convention as HDLC/PPP):

```
0x7E        frame start marker
[cmd]       1-byte command/type identifier
[payload]   SBC-encoded audio data (escaped)
0x7E        frame end marker

Escaping rules:
  If payload byte == 0x7E: emit 0x7D, 0x5E
  If payload byte == 0x7D: emit 0x7D, 0x5D
  (XOR with 0x20)
```

### Frame Type Bytes

```
0x00  Received audio (even frames)
0x03  Received audio (odd frames — treated same as 0x00)
0x01  Audio end / silence  (used for both TX end and RX end)
0x02  Audio ACK
0x09  Transmit audio (radio is currently transmitting)
```

### Audio End Frame (sent to stop TX)
```
7E 01 00 01 00 00 00 00 00 00 7E
```

---

## SBC Codec Parameters

HTCommander uses SBC (Sub-Band Coding) at:
```
Sample rate:  32000 Hz
Bit depth:    16-bit
Channels:     1 (mono)
```

Audio runs at 64 KB/s PCM throughput (32000 Hz × 2 bytes = 64000 bytes/sec).
The SBC encoder parameters (blocks, subbands) are set during audio channel connect.

---

## PTT Voice Transmission

**PTT does NOT use an MDC command on the control channel.**

To key up the radio and transmit voice:
1. Connect the GenericAudio RFCOMM channel (`00001203-...`)
2. Encode PCM microphone audio as SBC frames
3. Send escaped SBC frames with frame type `0x00` over the audio channel
4. When done, send the audio end frame: `7E 01 00 01 00 00 00 00 00 00 7E`

The radio keys up automatically when it receives audio frames. There is no separate
"PTT on" / "PTT off" command — audio presence = keyed, end frame = unkeyed.

### Dart Implementation Path
```
AudioService.startPtt()
  → MethodChannel 'com.openht.app/audio' → startPtt
    → MainActivity.kt
      → Connect GenericAudio RFCOMM socket (UUID 00001203...)
      → SBC encode mic PCM
      → Write escaped frames to audio output stream
      → On release: write end frame 7E 01 00 01 00 00 00 00 00 00 7E
```

### Current Status: ⚠️ STUB
`RadioService.startTransmit()` and `stopTransmit()` are stubs that log a warning.
The `AudioService` SCO monitoring path works. PTT TX needs:
1. Second RFCOMM socket connection to GenericAudio UUID
2. SBC encoder in Kotlin (NAudio not available on Android — use `libsbc` or `android-sbc`)
3. Mic capture → encode → write frame loop
4. End frame on PTT release

---

## SCO Audio Monitoring (RX)

SCO (Synchronous Connection-Oriented) is used for real-time RX audio monitoring.
This is the path that makes received audio audible through the phone speaker or BT headset.

### Android Implementation (`MainActivity.kt`)
```kotlin
// Start SCO
AudioManager.startBluetoothSco()
AudioManager.isBluetoothScoOn = true

// Fallback to phone speaker
AudioManager.isSpeakerphoneOn = true

// Listen for state changes
// ACTION_SCO_AUDIO_STATE_CHANGED broadcast
//   EXTRA_SCO_AUDIO_STATE: SCO_AUDIO_STATE_CONNECTED / DISCONNECTED / ERROR
```

### SCO State Machine
```
off → connecting → connected
            ↓           ↓
          error       error
```

### MethodChannel Bridge
```
Channel name: com.openht.app/audio

Dart → Kotlin:
  startAudio    → AudioManager.startBluetoothSco()
  stopAudio     → AudioManager.stopBluetoothSco()
  startPtt      → (stub — see PTT section above)
  stopPtt       → (stub)

Kotlin → Dart callback:
  audioStateChanged({state: connected|disconnected|error})
```

### Dashboard Speaker Icon States
```
Grey    = SCO off / disconnected
Orange  = SCO connecting
Green   = SCO connected (audio flowing)
Red     = SCO error
```

---

## A2DP vs SCO

These are two different Bluetooth audio profiles:

| Profile | Use case | OpenHT use |
|---------|---------|-----------|
| A2DP | Stereo music streaming | Not used |
| SCO/HFP | Mono voice, hands-free | RX audio monitoring |
| GenericAudio RFCOMM | Custom framed audio | PTT TX (planned) |

For SCO to work, the radio must be paired as a Hands-Free device (HFP/HSP profile).
If HFP is not available, OpenHT falls back to phone speaker via `isSpeakerphoneOn = true`.

---

## Voice Clips (Future)

HTCommander supports pre-recorded audio clip transmission via the same GenericAudio channel.
The `TransmitVoicePCM` path in `RadioAudio.cs` handles this with optional local playback.
OpenHT can implement this using the same SBC frame format once PTT TX is working.

---

## To Identify PTT Opcode (Not Needed — See Above)

Earlier sessions speculated that PTT might use `DO_PROG_FUNC` (cmd 66) with `Main-PTT`
on the control channel. **This is incorrect.** The source confirms PTT is purely
audio-channel-based: send SBC frames, radio keys up. No MDC command needed.

---

*Source: HTCommander `RadioAudio.cs` (Ylianst, Apache 2.0)*  
*Last updated: March 2026*
