# OpenHT — Architecture Reference

> This document maps the Flutter project structure, service layer, and key design patterns.  
> Claude Code: read this before making changes to understand where things live.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| App framework | Flutter (Dart) — Android target |
| State management | Provider (`ChangeNotifier`) |
| BT protocol | `flutter_benlink` (local package at `../flutter_benlink`) |
| BT audio | Android `AudioManager` SCO via MethodChannel |
| Maps | `flutter_map` + OpenStreetMap tiles |
| APRS | APRS-IS TCP socket |
| Storage | `shared_preferences` (settings), SQLite (channels cache) |
| GPS | `geolocator` package |

---

## Project Root

```
C:\Users\repin\AndroidStudioProjects\repins267-OpenHT\
C:\Projects\OpenHT\                                    (alternate path)
C:\Projects\flutter_benlink\                           (local package)
```

---

## Directory Structure

```
lib/
  main.dart                          App entry point, Provider setup, MultiProvider tree
  bluetooth/
    radio_service.dart               ← PRIMARY: RadioService ChangeNotifier (all BT ops)
  services/
    audio_service.dart               AudioService ChangeNotifier (SCO/PTT)
    freq_plan_service.dart           FreqPlanService (channel group plans)
    repeater_book_connect_service.dart  RepeaterBook content provider + GPX fallback
  screens/
    dashboard/
      dashboard_screen.dart          Main dashboard: freq display, PTT, quick actions
    near_repeaters/
      near_repeaters_screen.dart     Nearby repeater list + tune button
    aprs_map/
      aprs_map_screen.dart           APRS map, station markers, layer controls
    weather/
      weather_screen.dart            NOAA WX alert screen + WX1-7 tune buttons
    settings/
      settings_screen.dart           All settings UI (APRS, identity, freq plans, etc.)
      radio_debug_screen.dart        BT hex log, connection status, quick tune
      channel_manager_screen.dart    CSV import/export, group write
  widgets/
    radio_status_bar.dart            (planned) Persistent status bar across all tabs

android/
  app/src/main/kotlin/com/openht/app/
    MainActivity.kt                  Kotlin: BT SCO audio, MethodChannel bridge

assets/
  repeaters/
    colorado_2m.gpx                  140 bundled 2m repeaters (Colorado)
    colorado_70cm.gpx                219 bundled 70cm repeaters (Colorado)
  frequency_plans/
    PPARES_ElPaso.json               (or similar) PPARES/SKYWARN/RACES channel plan

docs/
  Bluetooth.md                       Protocol reference (THIS IS THE GROUND TRUTH)
  Channels.md                        Channel struct, CSV formats, group management
  Audio.md                           PTT and SCO audio architecture
  Architecture.md                    This file

../flutter_benlink/lib/
  radio_controller.dart              RadioController — wraps BT socket + command dispatch
  protocol/
    common.dart                      Enums: all commands, events, status codes
    rf_channel.dart                  RfChannel proto struct
    settings.dart                    RadioSettings proto struct
  benlink_connection.dart            RFCOMM socket management
```

---

## Service Layer

### RadioService (`lib/bluetooth/radio_service.dart`)

The central ChangeNotifier. All UI reads radio state from here. All BT writes go through here.

**Key state properties:**
```dart
bool isConnected          // true after GET_DEV_INFO response
bool isReadyToUpdate      // true when radio ready for writes (use this, NOT isDeviceReady)
double currentRxFreq      // current RX frequency in MHz (e.g. 146.5200)
int batteryPercent        // 0-100
RadioDevInfo deviceInfo   // vendor/product/hw/fw/channel_count
List<String> debugLog     // persistent hex log buffer (planned)
```

**Key methods:**
```dart
connect(BluetoothDevice)       // full handshake sequence
disconnect()
tuneToFrequency(double mhz)    // → FREQ_MODE_SET_PAR (cmd 35)
writeChannel(RadioChannel ch)  // → WRITE_RF_CH (cmd 14) + re-read confirm
writeNoaaGroup()               // write WX1-7 to group 4
writeRegionChannels(...)       // batch write to a group
setVolume(int level)           // → WRITE_SETTINGS
setSquelch(int level)          // → WRITE_SETTINGS
startTransmit()                // STUB — PTT not yet implemented
stopTransmit()                 // STUB
```

### AudioService (`lib/services/audio_service.dart`)

Manages BT SCO audio monitoring (RX). Communicates with Kotlin via MethodChannel.

```dart
ScoState state     // off / connecting / connected / error
toggleAudio()      // calls startAudio or stopAudio
startPtt()         // STUB — sends MethodChannel call, Kotlin stub logs warning
stopPtt()          // STUB
```

### flutter_benlink (`../flutter_benlink/`)

The protocol library. OpenHT depends on this as a local package.

**Critical facts:**
- Write gate is `isReadyToUpdate` — NOT `isDeviceReady`
- Known Dart port gaps documented in `docs/Bluetooth.md`
- `common.dart` has been patched: `SETTINGS_SYNCING_COMPLETE(9)`, `FREQ_MODE_SET_PAR(35)`, etc.

---

## Provider Tree (`main.dart`)

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => RadioService()),
    ChangeNotifierProvider(create: (_) => AudioService()),
    ChangeNotifierProvider(create: (_) => FreqPlanService()),
  ],
  child: MaterialApp(...)
)
```

Screens access services via:
```dart
final radio = context.watch<RadioService>();    // rebuilds on change
final radio = context.read<RadioService>();     // one-time read, no rebuild
```

---

## MethodChannel Bridge (Dart ↔ Kotlin)

Channel name: `com.openht.app/audio`

```
Dart → Kotlin (method calls):
  startAudio   → AudioManager.startBluetoothSco()
  stopAudio    → AudioManager.stopBluetoothSco()
  startPtt     → stub (logs warning)
  stopPtt      → stub

Kotlin → Dart (event callbacks):
  audioStateChanged({state: "connected"|"disconnected"|"error"})
```

---

## Navigation Structure

```
Scaffold with BottomNavigationBar (5 tabs):
  0: Dashboard        (dashboard_screen.dart)
  1: Near Repeaters   (near_repeaters_screen.dart)
  2: APRS Map         (aprs_map_screen.dart)
  3: Weather          (weather_screen.dart)
  4: Settings         (settings_screen.dart)
```

Settings screen uses nested navigation (ListTile → push new screen) for:
- Channel & Group Manager
- JS8Call Settings
- Radio Debug

---

## Connection Sequence (Required Order)

See `docs/Bluetooth.md` for full detail. Summary:

```
1. connect() → RFCOMM to SPP UUID
2. GET_DEV_INFO (cmd 4, arg=3)
3. READ_SETTINGS (cmd 10)
4. READ_BSS_SETTINGS (cmd 33)
5. RequestPowerStatus
6. ← GET_DEV_INFO response → isReadyToUpdate = true
7. REGISTER_NOTIFICATION HT_STATUS_CHANGED
8. ← READ_SETTINGS response
9. ← READ_BSS_SETTINGS response
   [radio ready for writes]
10. FREQ_MODE_GET_STATUS (cmd 36) → sync dashboard freq display
```

---

## ADB Test Commands

```bash
# Device ID
adb devices
# → 57230DLCQ0025Z

# Install
cd C:\Projects\OpenHT
flutter build apk --debug
adb -s 57230DLCQ0025Z install build/app/outputs/flutter-apk/app-debug.apk

# Screenshot
adb -s 57230DLCQ0025Z shell screencap -p /sdcard/ss.png
adb -s 57230DLCQ0025Z pull /sdcard/ss.png screenshots/$(date +%Y%m%d_%H%M%S).png

# Logcat (filter OpenHT)
adb -s 57230DLCQ0025Z logcat -s flutter

# HCI snoop log (for BT debugging)
adb shell settings put global bt_hci_snoop_log_mode full
# ... reproduce issue ...
adb pull /sdcard/btsnoop_hci.log
```

---

## RepeaterBook Data Sources

OpenHT uses a three-tier fallback for repeater data:

```
1. RepeaterBook API (pending token — requested March 6, 2026)
   https://www.repeaterbook.com/api/export.php?state_id=XX
   Note: state-based not lat/lon — sort client-side by GPS distance

2. Content Provider (when RepeaterBook Android app is installed)
   content://com.zbm2.repeaterbook.RBContentProvider/repeaters
   No permissions required (exposed without protection)

3. Bundled GPX files (always available offline)
   assets/repeaters/colorado_2m.gpx    (140 repeaters)
   assets/repeaters/colorado_70cm.gpx  (219 repeaters)
```

---

## Key External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_benlink` | local | Benshi MDC protocol |
| `provider` | latest | State management |
| `flutter_map` | latest | OSM map tiles |
| `geolocator` | latest | Phone GPS |
| `shared_preferences` | latest | Settings persistence |
| `permission_handler` | latest | BT/location permissions |

---

*Last updated: March 2026*
