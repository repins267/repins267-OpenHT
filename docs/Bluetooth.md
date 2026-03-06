# OpenHT — Bluetooth Protocol Reference

> **Sources:** BS_HT.apk DEX decompilation · HTCommander C# source (Ylianst, Apache 2.0) · VR-N76 User Manual  
> **Confirmed against:** Live VR-N76 hardware (BT MAC `38:D2:00:00:F7:F5`)  
> **This document is the ground truth for all protocol decisions in OpenHT.**  
> Claude Code: read this file at the start of every session before touching radio-related code.

---

## Compatible Hardware

All radios below share the **identical Benshi/MDC Bluetooth protocol** over RFCOMM SPP.
Capabilities are self-reported per radio via `GET_DEV_INFO` — read `Info.*` flags, do not hardcode.

| Radio | VFO | Dual Watch | DMR | NOAA | FM Broadcast | GMRS | Test Status |
|-------|-----|-----------|-----|------|-------------|------|-------------|
| Vero VR-N76 | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ Primary test device |
| Vero VR-N7600 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ Protocol compatible |
| Vero VR-N7500 | ✅ | ✅ | ❓ | ✅ | ✅ | ❌ | 🔬 Untested |
| BTech UV-Pro | ✅ | ✅ | ❓ | ✅ | ✅ | ❌ | 🔬 Untested |
| BTech UV-50Pro | ✅ | ✅ | ❓ | ✅ | ✅ | ❌ | 🔬 Untested |
| RadioOddity GA-5WB | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 🔬 Untested |

---

## Transport Layer

**Protocol:** Bluetooth Classic RFCOMM (NOT BLE)  
**Profile:** SPP — Serial Port Profile

### RFCOMM Service UUIDs

| UUID | Profile | Purpose |
|------|---------|---------|
| `00001101-0000-1000-8000-00805F9B34FB` | SPP | Radio control data channel ← **use this** |
| `00001107-D102-11E1-9B23-00025B00A5A5` | GAIA | Firmware updates only — do not use |
| `00001102-D102-11E1-9B23-00025B00A5A5` | Audio | SCO audio channel (separate from control) |

> The radio presents as **two separate Bluetooth devices**: an audio device and a control device.
> Both must be paired on Android. Flutter connects to the SPP UUID for all protocol commands.

### Flutter Package

Protocol is implemented via [`flutter_benlink`](https://github.com/SarahRoseLives/flutter_benlink),
a Dart port of [benlink](https://github.com/khusmann/benlink) (KC3SLD).  
Local workspace path: `../flutter_benlink` relative to OpenHT root (`C:\Projects\flutter_benlink`).

---

## MDC Packet Wire Format

```
Byte 0:    0xFF          frame start marker
Byte 1:    0x01          protocol version
Bytes 2-3: length        big-endian uint16 — byte count of payload only (NOT including header)
Byte 4:    command byte  ordinal from command table below
Bytes 5+:  payload       protobuf-encoded or raw bytes depending on command
Last byte: 0xFF          EOF marker — if this byte == 0xFF, set length field = 3
```

**Max packet body:** 270 bytes  
**SPP read buffer:** 1024 bytes

### ⚠️ Critical Serialization Rule

MDC frame header bytes (`FF 01`) must **never** appear inside the protobuf payload.  
If `ToByteArray()` prepends header bytes into the payload, the radio returns `INVALID_PARAMETER` (status 6).  
Fix: strip the first 5 header bytes from any serialized packet before treating the remainder as payload.

---

## Connection Sequence (Mandatory)

**This exact sequence is required. Deviation leaves the radio in a state where writes are silently rejected.**

Source: `HTCommander/Radio.cs → RadioTransport_OnConnected()`

```
1.  BT RFCOMM connect (SPP UUID)
2.  → GET_DEV_INFO         (cmd 4, arg=3)
3.  → READ_SETTINGS        (cmd 10)
4.  → READ_BSS_SETTINGS    (cmd 33)
5.  → RequestPowerStatus   (BATTERY_LEVEL_AS_PERCENTAGE)
6.  ← GET_DEV_INFO response → allocate Channels[], set state = Connected
7.  → REGISTER_NOTIFICATION HT_STATUS_CHANGED
8.  ← READ_SETTINGS response → parse full radio config
9.  ← READ_BSS_SETTINGS response → parse APRS/BSS config
    ══════════════════════════════════════════════
    Radio is now ready for writes
    ══════════════════════════════════════════════
10. → WRITE_RF_CH / WRITE_SETTINGS / FREQ_MODE_SET_PAR etc.
11. ← WRITE response: if success, re-read to confirm
12. → READ_RF_CH (same index) — HTCommander always confirms writes
```

```csharp
// From HTCommander Radio.cs — exact C# reference:
private void RadioTransport_OnConnected()
{
    SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
    SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
    SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_BSS_SETTINGS, null);
    RequestPowerStatus(RadioPowerStatus.BATTERY_LEVEL_AS_PERCENTAGE);
}

case RadioBasicCommand.GET_DEV_INFO:
    Info = new RadioDevInfo(value);
    Channels = new RadioChannelInfo[Info.channel_count];
    UpdateState(RadioState.Connected);           // ← write gate opens HERE
    SendCommand(REGISTER_NOTIFICATION, HT_STATUS_CHANGED);
    break;
```

**Key facts:**
- HTCommander does **NOT** use `SYNC_SETTINGS`. The BS_HT Android app's SYNC_SETTINGS step is an app-specific quirk, not a protocol requirement.
- The write gate in `flutter_benlink` is `isReadyToUpdate`, **not** `isDeviceReady`. Using the wrong flag was the root cause of all silent write failures prior to OpenHT Session 1.
- After connect, always call `FREQ_MODE_GET_STATUS` (cmd 36) to sync the displayed frequency with the radio's actual current frequency.

---

## Command Table

All 77 commands confirmed from BS_HT APK decompilation + HTCommander C# source.

```
Ordinal  Name                     Notes
───────  ───────────────────────  ────────────────────────────────────────────────
  0      UNKNOWN
  1      GET_DEV_ID
  2      SET_REG_TIMES
  3      GET_REG_TIMES
  4      GET_DEV_INFO             ← Send on connect (arg=3). Returns radio capabilities.
  5      READ_STATUS
  6      REGISTER_NOTIFICATION   ← Subscribe to radio-pushed events
  7      CANCEL_NOTIFICATION
  8      GET_NOTIFICATION
  9      EVENT_NOTIFICATION      ← Radio-pushed event wrapper
 10      READ_SETTINGS           ← Send on connect. Returns full radio config struct.
 11      WRITE_SETTINGS          ← Write squelch, volume, dual-watch, power, etc.
 12      STORE_SETTINGS
 13      READ_RF_CH              ← Read a memory channel by index
 14      WRITE_RF_CH             ← Write a memory channel (re-read after to confirm)
 15      GET_IN_SCAN
 16      SET_IN_SCAN
 17      SET_REMOTE_DEVICE_ADDR
 18      GET_TRUSTED_DEVICE
 19      DEL_TRUSTED_DEVICE
 20      GET_HT_STATUS           ← Current freq, channel ID, TX/RX state
 21      SET_HT_ON_OFF
 22      GET_VOLUME
 23      SET_VOLUME              ← Set volume level directly
 24      RADIO_GET_STATUS        ← FM broadcast radio status (87–108 MHz)
 25      RADIO_SET_MODE          ← FM broadcast on/off
 26      RADIO_SEEK_UP           ← FM broadcast seek up
 27      RADIO_SEEK_DOWN         ← FM broadcast seek down
 28      RADIO_SET_FREQ          ← FM broadcast tune to frequency
 29      READ_ADVANCED_SETTINGS
 30      WRITE_ADVANCED_SETTINGS
 31      HT_SEND_DATA            ← Transmit AX.25/BSS packet over air
 32      SET_POSITION            ← Push phone GPS coordinates to radio
 33      READ_BSS_SETTINGS       ← Send on connect. Returns APRS/BSS config.
 34      WRITE_BSS_SETTINGS      ← Write APRS/BSS config
 35      FREQ_MODE_SET_PAR       ← ⭐ SET VFO frequency + modulation (USE THIS for tuning)
 36      FREQ_MODE_GET_STATUS    ← ⭐ GET current VFO frequency + modulation
 37      READ_RDA1846S_AGC
 38      WRITE_RDA1846S_AGC
 39      READ_FREQ_RANGE
 40      WRITE_DE_EMPH_COEFFS
 41      STOP_RINGING
 42      SET_TX_TIME_LIMIT
 43      SET_IS_DIGITAL_SIGNAL
 44      SET_HL                  ← High/low/medium TX power switch
 45      SET_DID                 ← BS_HT calls this SYNC_SETTINGS in MDC ACTION field
 46      SET_IBA
 47      GET_IBA
 48      SET_TRUSTED_DEVICE_NAME
 49      SET_VOC
 50      GET_VOC
 51      SET_PHONE_STATUS
 52      READ_RF_STATUS          ← Live telemetry: freq, battery %, GPS, TX/RX state
 53      PLAY_TONE
 54      GET_DID
 55      GET_PF                  ← Read PF1/PF2 programmable button assignments
 56      SET_PF                  ← Write PF1/PF2 button assignments
 57      RX_DATA                 ← Incoming AX.25 data packet
 58      WRITE_REGION_CH         ← Write channel to a specific group/slot
 59      WRITE_REGION_NAME       ← Write a group name
 60      SET_REGION              ← Switch active channel group
 61      SET_PP_ID
 62      GET_PP_ID
 63      READ_ADVANCED_SETTINGS2
 64      WRITE_ADVANCED_SETTINGS2
 65      UNLOCK
 66      DO_PROG_FUNC            ← Execute a programmable button function in software
 67      SET_MSG
 68      GET_MSG
 69      BLE_CONN_PARAM
 70      SET_TIME
 71      SET_APRS_PATH
 72      GET_APRS_PATH
 73      READ_REGION_NAME        ← Read a group name by index
 74      SET_DEV_ID
 75      GET_PF_ACTIONS          ← Get list of all available PF button actions
 76      GET_POSITION            ← Read radio's internal GPS position
```

---

## Notification Events (Radio → App)

Subscribed via `REGISTER_NOTIFICATION` (cmd 6). Delivered wrapped in `EVENT_NOTIFICATION` (cmd 9).

```
Ordinal  Name                     Notes
───────  ───────────────────────  ──────────────────────────────────────
  0      UNKNOWN
  1      HT_STATUS_CHANGED       ← Frequency or channel changed on radio
  2      DATA_RXD                ← Incoming AX.25/BSS packet received
  3      NEW_INQUIRY_DATA
  4      RESTORE_FACTORY_SETTINGS
  5      HT_CH_CHANGED           ← Channel number changed
  6      HT_SETTINGS_CHANGED     ← Settings changed on radio
  7      RINGING_STOPPED
  8      RADIO_STATUS_CHANGED    ← FM broadcast status changed
  9      USER_ACTION             ← BS_HT calls this SETTINGS_SYNCING_COMPLETE
 10      SYSTEM_EVENT
 11      BSS_SETTINGS_CHANGED
 12      DATA_TXD                ← Packet transmitted
 13      POSITION_CHANGE         ← GPS position changed
```

---

## Radio Capabilities (GET_DEV_INFO Response)

```csharp
public class RadioDevInfo
{
    public int  vendor_id;          // Manufacturer ID  (VR-N76: 1)
    public int  product_id;         // Radio model ID   (VR-N76: 259 = 0x103)
    public int  hw_ver;             // Hardware revision (VR-N76: 1)
    public int  soft_ver;           // Firmware version  (VR-N76: 146)
    public bool support_radio;      // Has FM broadcast radio
    public bool support_medium_power;
    public bool support_noaa;       // Has NOAA WX channels
    public bool gmrs;               // Is GMRS variant
    public bool support_vfo;        // Has VFO mode
    public bool support_dmr;        // Has DMR digital mode
    public int  region_count;       // Number of channel groups — do NOT hardcode
    public int  channel_count;      // Channels per group  — do NOT hardcode
    public int  freq_range_count;
}
```

> **Important:** OpenHT must read `Info.region_count` and `Info.channel_count` from the
> `GET_DEV_INFO` response. Do not hardcode `6 × 32`. Different radio models self-report
> different values.

---

## VFO Tuning

### ⭐ Use FREQ_MODE_SET_PAR (cmd 35) — NOT WRITE_SETTINGS

```
FREQ_MODE_SET_PAR payload (RfChannelFields proto):
  txFreq:      Hz as int32    (146.520 MHz → 146520000)
  rxFreq:      Hz as int32
  txSubAudio:  CTCSS Hz × 100 as int16, or 0 for none  (100.0 Hz → 10000)
  rxSubAudio:  CTCSS Hz × 100 as int16, or 0 for none
  bandwidth:   12500 = NFM narrow,  25000 = FM wide
  modulation:  0 = FM,  1 = AM,  2 = DMR
```

`WRITE_SETTINGS` (cmd 11) is for squelch, volume, dual-watch, power, etc. —
**not** for changing the active VFO frequency.

### Dual VFO / Dual Watch

```
vfo_x (2 bits): 1 = VFO1/Band A active,  2 = VFO2/Band B active
double_channel: 0 = single watch,  1+ = dual watch

To tune Band A: ensure vfo_x = 1, then send FREQ_MODE_SET_PAR
To tune Band B: set vfo_x = 2 via WRITE_SETTINGS, then send FREQ_MODE_SET_PAR
```

---

## Radio Settings Struct (Bit Layout)

From `HTCommander/RadioSettings.cs` — authoritative byte-level layout:

```
msg[5]:  channel_a high nibble (bits 7-4) | channel_b high nibble (bits 3-0)
msg[6]:  scan(7) | aghfp_call_mode(6) | double_channel[2](5-4) | squelch_level[4](3-0)
msg[7]:  tail_elim(7) | auto_relay_en(6) | auto_power_on(5) | keep_aghfp_link(4)
         | mic_gain[3](3-1) | tx_hold_time high bit(0)
msg[8]:  tx_hold_time[4](7-4) | tx_time_limit[5](4-0)
msg[9]:  local_speaker[2](7-6) | bt_mic_gain[3](5-3) | adaptive_response(2)
         | dis_tone(1) | power_saving_mode(0)
msg[10]: auto_power_off[4](7-4) | auto_share_loc_ch[5](4-0)
msg[11]: hm_speaker[2](7-6) | positioning_system[4](5-2) | time_offset high 2 bits(1-0)
msg[12]: time_offset low 4 bits(7-4) | use_freq_range_2(3) | ptt_lock(2)
         | leading_sync_bit_en(1) | pairing_at_power_on(0)
msg[13]: screen_timeout[5](7-3) | vfo_x[2](2-1) | imperial_unit(0)
msg[14]: channel_a low nibble(7-4) | channel_b low nibble(3-0)
msg[15]: wx_mode[2](7-6) | noaa_ch[4](5-2) | vfo1_tx_power_x[2](1-0)
msg[16]: vfo2_tx_power_x[2](7-6) | dis_digital_mute(5) | signaling_ecc_en(4) | ch_data_lock(3)
msg[17-20]: vfo1_mod_freq_x   ← VFO1/Band A packed frequency + modulation (4 bytes)
msg[21-24]: vfo2_mod_freq_x   ← VFO2/Band B packed frequency + modulation (4 bytes)
```

> `ToByteArray()` payload starts at `msg[5]`. Bytes 0–4 are the MDC frame header and must
> be stripped before treating remainder as protobuf payload.

---

## Channel Struct (25-Byte Wire Format)

From `HTCommander/RadioChannelInfo.cs`:

```
r[0]:     channel_id
r[1-4]:   tx_freq as int32 (Hz), high 2 bits = tx_mod  (int)tx_mod << 30 | tx_freq_hz
r[5-8]:   rx_freq as int32 (Hz), high 2 bits = rx_mod
r[9-10]:  tx_sub_audio as int16  (CTCSS: Hz × 100;  DCS: tone number;  None: 0)
r[11-12]: rx_sub_audio as int16
r[13]:    scan(7) | tx_at_max_power(6) | talk_around(5) | bandwidth_wide(4)
          | pre_de_emph_bypass(3) | sign(2) | tx_at_med_power(1) | tx_disable(0)
r[14]:    fixed_freq(7) | fixed_bandwidth(6) | fixed_tx_power(5) | mute(4)
r[15-24]: name as UTF-8, 10 bytes (NOT 8 — channel name limit is 10 chars)
```

**Key encoding:**
- Frequency: Hz as int32 (146.520 MHz → `146520000`)
- Modulation packed into top 2 bits of freq field
- CTCSS: Hz × 100 as int16 (88.5 Hz → `8850`, 100.0 Hz → `10000`)
- DCS: tone number as int16 (D047N → `47`)
- Bandwidth: `NARROW = 0` (bit clear), `WIDE = 1` (bit set) at `r[13]` bit 4
- Modulation values: `FM = 0`, `AM = 1`, `DMR = 2`
- Name: 10 bytes UTF-8, null-terminated — **10 chars max, not 8**

---

## Channel Group Management

```
SET_REGION (60)       → switch active channel group (0-indexed)
READ_REGION_NAME (73) → read a group name by index
WRITE_REGION_NAME (59) → write a group name
WRITE_REGION_CH (58)  → write a channel to a specific group/slot
READ_RF_CH (13)       → read a channel from currently active group
WRITE_RF_CH (14)      → write a channel to currently active group
```

After `SET_REGION`, re-read all channels with `UpdateChannels()` loop.  
After any `WRITE_RF_CH`, immediately re-read that channel to confirm write succeeded.

---

## FM Broadcast Radio (87–108 MHz)

Commands 24–28 control the built-in FM broadcast receiver. This is **completely separate**
from the ham radio VFO. The FM Radio tab must use these commands, **not** `FREQ_MODE_SET_PAR`.

```
RADIO_GET_STATUS (24) → get current FM radio state
RADIO_SET_MODE   (25) → enable/disable FM radio
RADIO_SEEK_UP    (26) → seek up to next station
RADIO_SEEK_DOWN  (27) → seek down to next station
RADIO_SET_FREQ   (28) → tune to specific FM broadcast frequency
```

---

## Programmable Buttons

```
GET_PF         (55) → read current PF1/PF2 button assignments
SET_PF         (56) → write new PF1/PF2 button assignments
GET_PF_ACTIONS (75) → get list of all available PF button actions
DO_PROG_FUNC   (66) → execute a programmed function directly in software
```

Factory defaults: PF1 short = Toggle FM Radio, PF1 long = Sub Channel PTT,
PF2 short = Power Level Switch, PF2 long = Toggle Monitor.

---

## GPS Integration

```dart
// Push phone GPS to radio (radio beacons using phone GPS when its own GPS has no fix)
SendCommand(RadioBasicCommand.SET_POSITION, gpsPayload);  // cmd 32

// Read radio's internal GPS
SendCommand(RadioBasicCommand.GET_POSITION, null);         // cmd 76

// Subscribe to radio GPS events
SendCommand(REGISTER_NOTIFICATION, POSITION_CHANGE);      // event ordinal 13
```

---

## PTT / TX Key — Current Status (⚠️ STUB)

**The Benshi MDC protocol has no confirmed TX key-up command in flutter_benlink.**

`RadioService.startTransmit()` and `stopTransmit()` are **stubs** that log a warning and
return false. The PTT button UI is fully implemented and functional. SCO audio routing
works correctly. The stubs will be promoted to real commands once the opcode is confirmed.

**To identify the PTT opcode:** capture an HCI snoop log from BS_HT while pressing PTT.
```
adb shell settings put global bt_hci_snoop_log_mode full
# press PTT on radio in BS_HT app
adb pull /sdcard/btsnoop_hci.log
# open in Wireshark, filter: btrfcomm, look for short packet ~2-5 bytes sent on PTT press
```

Candidate: `DO_PROG_FUNC` (cmd 66) with action = `Main-PTT` or `Sub-PTT`.
HTCommander source lists `Main-PTT` and `Sub-PTT` as available `GET_PF_ACTIONS` values.

---

## Bluetooth SCO Audio

SCO (Synchronous Connection-Oriented) is a separate Bluetooth audio profile from the
control channel. It is used for real-time voice audio (RX monitoring and TX microphone).

**Android implementation:** `MainActivity.kt`
- `BluetoothAdapter.ACTION_SCO_AUDIO_STATE_CHANGED` broadcast receiver
- `AudioManager.startBluetoothSco()` / `stopBluetoothSco()`
- SCO state machine: `off → connecting → connected → error`
- Dart callback via MethodChannel `com.openht.app/audio` → `audioStateChanged(state)`

**A2DP vs SCO:** A2DP is stereo audio (music). SCO is voice/mono. The radio must support
HFP or HSP profiles for SCO. Phone speaker fallback: `isSpeakerphoneOn = true`.

**MethodChannel methods:**
- `startAudio` / `stopAudio` → toggle SCO connection
- `startPtt` / `stopPtt` → stub, does not yet key radio TX

---

## CSV Channel Import/Export Formats

### Format 1 — CHIRP Compatible

```csv
Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power
0,W0ABC,146.520000,,,,,,,, NFM,,,5.0W
1,W0RPT,147.390000,+,0.600000,Tone,100.0,100.0,,,NFM,,,5.0W
```

### Format 2 — Native VGC (use this for OpenHT)

```csv
title,tx_freq,rx_freq,tx_sub_audio,rx_sub_audio,tx_power,bandwidth,scan,talk_around,pre_de_emph_bypass,sign,tx_dis,mute,rx_modulation,tx_modulation
W0ABC,146520000,146520000,0,0,H,12500,1,0,0,0,0,0,FM,FM
W0RPT,147990000,147390000,10000,10000,H,12500,1,0,0,0,0,0,FM,FM
```

Field encoding:
- Frequencies: Hz as integer (9 digits, zero-padded)
- CTCSS: Hz × 100 (`8850` = 88.5 Hz, `10000` = 100.0 Hz)
- DCS: tone number (`47` = D047N)
- Power: `H` = High (5W), `M` = Medium (3W), `L` = Low (1W)
- Bandwidth: `12500` = NFM narrow, `25000` = FM wide
- Modulation: `FM`, `AM`, `DMR`, `FO` (=FM)

---

## BSS Air Protocol (Messaging)

BSS is a proprietary Benshi/Baofeng binary protocol transmitted in AFSK frames.
Sent via `HT_SEND_DATA` (cmd 31) → AX.25 → over the air.

```
0x01                 BSS protocol indicator (always first byte)
[len][type][data]    series of TLV elements
                     Exception: if len = 0x85, next 2 bytes = message counter
```

Type codes:
```
0x20 = From      (callsign, source)
0x21 = To        (callsign, destination)
0x24 = Message   (UTF-8 text)
0x25 = Location  (13 bytes: Lat[4] + Lon[4] + Alt[2] + Speed[2] + Heading[1])
0x27 = LocationRequest
0x28 = CallRequest
```

---

## Known Wrong Approaches (Do Not Use)

Any code referencing these for VR-N76/UV-Pro/GA-5WB is **incorrect**:

| Wrong approach | Why it's wrong |
|---------------|----------------|
| CI-V protocol (`FE FE A4 E0...`) | Icom IC-705 only — completely different vendor |
| GAIA firmware update path | Not accessible via SPP; uses separate BT transport |
| Kotlin Fragments (`MapFragment.kt`, `WeatherFragment.kt`) | OpenHT is Flutter/Dart — no Fragments |
| `isDeviceReady` as write gate | Wrong flag — use `isReadyToUpdate` in flutter_benlink |
| Hardcoded `6 × 32` channel layout | Read `Info.region_count` × `Info.channel_count` from radio |
| `WRITE_SETTINGS` for VFO tuning | Use `FREQ_MODE_SET_PAR` (cmd 35) instead |
| Channel name limit of 8 chars | Actual limit is 10 chars per `RadioChannelInfo.cs` |

---

## Known Dart/Flutter Issues (Tracked)

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `WRITE_SETTINGS` → `INVALID_PARAMETER` | MDC header bytes `FF 01` in payload | Strip first 5 bytes in `ToByteArray()` |
| Mode buttons (FM/NFM/AM) inoperative | `WRITE_SETTINGS` used instead of `FREQ_MODE_SET_PAR` | Use cmd 35 for VFO mode changes |
| Squelch/Volume sliders no-op | Settings object not initialized before `copyWith()` | Guard on `_controller.settings != null` |
| Freq display stale on connect | `FREQ_MODE_GET_STATUS` not called after handshake | Call cmd 36 after connect sequence completes |
| Near Repeater Tune changes mode not freq | Channel written but `FREQ_MODE_SET_PAR` not called after | Call cmd 35 after channel write |
| CSV import shows success but no radio change | Import writes to SQLite cache, not to radio | Wire import completion to `writeChannelDirect()` loop |
| NOAA write fails 0/7 channels | Same `WRITE_RF_CH` serialization bug | Resolved by FF 01 header fix |
| PTT does not key radio TX | TX opcode unknown; `startTransmit()` is a stub | Capture HCI snoop log from BS_HT PTT press |

---

## RepeaterBook Integration

**Status:** API token pending (requested March 6, 2026 via `cyrus.field@owasp.org`)  
**Endpoint:** `https://www.repeaterbook.com/api/export.php?state_id=XX&frequency=146&mode=analog`  
**Note:** API is state-based, not lat/lon. Sort client-side by distance from GPS.  
**Fallback:** Content Provider (`content://com.zbm2.repeaterbook.RBContentProvider/repeaters`)
when RepeaterBook app is installed, plus bundled GPX files for offline use.

Bundled files in `assets/repeaters/`:
- `colorado_2m.gpx` — 140 repeaters
- `colorado_70cm.gpx` — 219 repeaters

---

*Last updated: March 2026 — Sources: BS_HT.apk (60,993 DEX strings), HTCommander C# source
(Ylianst, Apache 2.0, github.com/Ylianst/HTCommander), VR-N76 User Manual,
flutter_benlink Dart port analysis, live hardware testing on VR-N76 (KF0JKE)*
