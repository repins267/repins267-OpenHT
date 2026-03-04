# OpenHT — Radio App Development Skill

OpenHT is a Flutter Android app for controlling the VR-N76 (Benshikj/VGC) handheld radio via
Bluetooth. It targets APRSdroid + HTCommander + HtStation feature parity.

---

## Critical Rules (read first)

- **FM-only radio** — The VR-N76 supports FM, NFM, AM, and DMR only. **Never suggest SSB, LSB,
  USB, CW, or any HF mode.** The hardware does not support them.
- **No RepeaterBook API** — RepeaterBook requires allowlist approval (returns 401). Repeater data
  comes from bundled GPX assets (`assets/repeaters/colorado_2m.gpx`,
  `assets/repeaters/colorado_70cm.gpx`). Do not add any live RepeaterBook network calls.
- **Auth key storage** — APRS auth keys use `flutter_secure_storage` (Android Keystore /
  `encryptedSharedPreferences`). If migrating to SQLCipher in future, keys go in an encrypted DB,
  not plain `sqflite` or `SharedPreferences`.
- **All radio writes go through `RadioService`** — never call `flutter_benlink` directly from UI
  widgets. `RadioService` owns all channel/settings write logic.

---

## Hardware Constraints (NEVER violate these)

### VR-N76 Radio Memory Layout
- 6 groups × 32 channels = 192 channels total
- Group index 0–5; channel ID = `groupIndex * 32 + channelIndex`
- **Group 4 (IDs 128–134)**: Reserved for NOAA WX channels (7 simplex freqs)
- **Group 5 (IDs 160–191)**: Reserved for Near Repeater auto-write (rolling 32-slot buffer)
- Channel name: max 10 chars in binary protocol, 8-char convention (`callsign + freq digits`)
- Writing is slow: 80 ms delay required between consecutive `writeChannel()` calls

### NOAA WX Frequencies (kHz)
162400, 162425, 162450, 162475, 162500, 162525, 162550
Labels: WX1–WX7. Write as: `txDisable: true`, `rxMod: ModulationType.fm`, `bandwidth: BandwidthType.narrow`

### Repeater Offsets
- 2 m band (< 300 MHz): ±0.6 MHz
- 70 cm band (≥ 400 MHz): ±5.0 MHz

### Repeater Data Source
- **Bundled GPX assets only** (no network): `assets/repeaters/colorado_2m.gpx`,
  `assets/repeaters/colorado_70cm.gpx`
- Parse with `xml` package: `XmlDocument.parse()`, `findAllElements('wpt')`
- Name format in GPX: `CALLSIGN OUTPUT_FREQ INPUT_FREQ+/- [CTCSS_HZ]`
- Tune via `radio.tuneToRepeaterGpx(outputFreqMhz, ctcssHz)` in `RadioService`
- **Do not add RepeaterBook API calls** — endpoint returns 401 without allowlist approval

---

## flutter_benlink API (the Bluetooth protocol library)

```dart
// lib is at path: ../flutter_benlink (local dep)
RadioController radio = ...;
radio.currentRxFreq           // double MHz
radio.currentChannel?.rxMod   // ModulationType (fm/am/dmr)
radio.currentChannel?.bandwidth // BandwidthType (narrow=NFM, wide=FM)
radio.settings?.squelchLevel  // int 0–15
radio.settings?.micGain       // int 0–7
radio.currentChannelId        // int (0 = VFO)
radio.setVfoFrequency(mhz)    // writes VFO channel 0
radio.writeSettings(s.copyWith(...))
radio.writeChannel(ch.copyWith(...))
radio.getAllChannels()         // List<Channel>, ~50ms/channel — SLOW
```

Channel fields: `channelId`, `rxFreq`, `txFreq`, `rxMod`, `txMod`, `bandwidth`,
`txSubAudio` (CTCSS Hz as double), `rxSubAudio`, `name` (String), `txDisable` (bool)

---

## Architecture

- **State management**: Provider / ChangeNotifier — always use `context.watch<T>()` in build,
  `context.read<T>()` in callbacks/async
- **Navigation**: `NavigationBar` + `IndexedStack` — **NOT** `TabBarView`/`DefaultTabController`
  - Tab indices: 0=Dashboard, 1=Repeaters, 2=APRS Map, 3=Weather, 4=Messages, 5=Settings
  - Navigate programmatically via `ValueChanged<int> onNavigate` callback passed to DashboardScreen
- **Persistence**: `SharedPreferences` for settings; `sqflite` SQLite for BBS + APRS messages
- **Secure storage**: `flutter_secure_storage` with `AndroidOptions(encryptedSharedPreferences:true)`
  for APRS auth keys — never store keys in SharedPreferences

---

## Key Services (all registered in `lib/main.dart` MultiProvider)

| Service | Notes |
|---------|-------|
| `RadioService` | BT connect/disconnect; `tuneToFrequency()`, `writeNoaaGroup()`, `writeNearRepeaterChannel()` |
| `GpsService` | `setHighFrequency()` on radio connect, `setLowFrequency()` on disconnect |
| `AprsService` | Packet aggregator; `_lastHeard` map dedup by `fullCallsign`; max 200 packets |
| `AprsIsService` | APRS-IS TCP: `noam.aprs2.net:14580`; `sendLine()`; auto-reconnect 30s |
| `AprsAuthService` | HMAC-SHA256 sign/verify; `load()` on init; `signMessage()`, `verifyMessage()`, `stripTag()` |
| `AprsMessageService` | SQLite `aprs_messages.db`; `open()` on init; `handleIncomingPacket()`, `createOutgoing()` |
| `IgateService` | iGate forwarding; `init()` on start |
| `NoaaService` | NWR stations + weather alerts |
| `BbsService` | Winlink BBS SQLite inbox; `init()` on start |
| `KissTncService` | Static encode/decode; `buildAprsFrame()` for AX.25 — no init needed |
| `MapTileService` | Static URL templates; `MapTileSource` enum (openStreetMap/openTopoMap/satellite) |

---

## APRS Protocol Rules

### APRS-IS passcode (standard hash)
```dart
int computeAprsPasscode(String callsign) {
  final base = callsign.split('-').first.toUpperCase();
  int hash = 0x73e2;
  for (int i = 0; i < base.length; i += 2) {
    hash ^= base.codeUnitAt(i) << 8;
    if (i + 1 < base.length) hash ^= base.codeUnitAt(i + 1);
  }
  return hash & 0x7FFF;
}
```

### APRS message format (TNC2)
```
FROM>APRS,PATH::DEST     :body text{msgid}
```
- Addressee padded to 9 chars with spaces
- Message ID: 3-digit zero-padded int, increments per session
- Ack: `FROM>APRS,PATH::DEST     :ackMSGID`
- Auth tag: `{XXXXXXXX}` appended to body (8 uppercase hex chars, HMAC-SHA256 truncated)

### APRS message body limit
67 characters (before auth tag). Enforce in UI with char counter.

---

## Map Tiles

| Source | URL template | Note |
|--------|-------------|------|
| OpenStreetMap | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Standard |
| OpenTopoMap | `https://tile.opentopomap.org/{z}/{x}/{y}.png` | Standard |
| ESRI Satellite | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` | **y/x reversed!** |

Tile cache stored in: `{appDocumentsDir}/tile_cache/{source.name}/z/x/y.png`

---

## SharedPreferences Keys (complete list)

```
callsign            — String  (e.g. "KF0JKE")
same_code           — String  (6-digit FIPS county code)
spotter_app_id      — String  (default: "4f2e07d475ae4")
igate_enabled       — bool
vfo_step_khz        — double  (5.0, 12.5, or 25.0)
aprs_ssid           — int     (0–15, default 7)
aprs_passcode       — int     (auto-computed)
aprs_server         — String  (default: "rotate.aprs2.net")
aprs_filter_km      — int     (default: 50)
aprs_path           — String  (e.g. "WIDE1-1,WIDE2-1")
aprs_symbol_table   — String  ("/" or "\")
aprs_symbol_char    — String  (single char)
aprs_digital_mode   — bool
aprs_share_loc_interval — String  ("0","5","10","15","30","60")
aprs_digital_channel — int
aprs_bss_mode       — bool
aprs_beacon_comment — String  (max 43 chars)
aprs_smart_beaconing — bool
aprs_beacon_interval_min — int
aprs_digipeater     — bool
aprs_digi_ttl       — int     (0–8)
aprs_digi_max_hops  — int     (0–8)
map_tile_source     — String  (MapTileSource.name)
js8_enabled         — bool
js8_speed           — String  ("15","10","6" = tx window seconds)
js8_grid            — String  (4-char Maidenhead)
js8_heartbeat       — bool
js8_heartbeat_interval — int  (minutes)
js8_relay           — bool
js8_relay_ttl       — int
js8_store_forward   — bool
js8_audio_offset    — int     (Hz, default 1500)
```

---

## Known Pitfalls

- `LatLngBounds` in flutter_map v6: use `.west/.north/.east/.south` (not `westLng` etc.)
- Socket UTF-8: cast socket to `Stream<List<int>>` before `utf8.decoder.transform()`
- GPS adaptive: guard with `_radioWasConnected` bool to avoid spurious GPS-mode switches
- APRS-IS socket `done` future: call `_socket!.done.catchError(...)` immediately after connect
- ESRI satellite tiles: URL order is `{z}/{y}/{x}` not `{z}/{x}/{y}` — easy bug
- `AprsMessageService.open()` is async — call without await in Provider `create:` (fire-and-forget is OK; DB is ready before first widget interaction)
- Channel write: always `await Future.delayed(const Duration(milliseconds: 80))` between writes
- `flutter_benlink` `getAllChannels()` is ~50 ms/channel — never call on the main thread without a loading state

---

## Build

```bash
# Analyze (target: 0 warnings, 0 errors)
flutter analyze --no-pub

# Debug build + install
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Flutter SDK path on this machine
C:\Projects\flutter2\bin\flutter.bat
```

Current baseline: **75 info issues, 0 warnings, 0 errors** (all `prefer_const_constructors` style hints)
