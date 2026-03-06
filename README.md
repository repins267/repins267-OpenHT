# OpenHT

> Open-source Android controller for VGC / Benshi-protocol radios with Near Repeater, APRS map, Weather Monitoring, and Android Auto support.

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android-green.svg)]()
[![Radio: VR-N76 / VR-N7600](https://img.shields.io/badge/Radio-VR--N76%20%7C%20VR--N7600-orange.svg)]()

## 📱 Screenshots

<table>
  <tr>
    <td align="center"><b>Dashboard</b></td>
    <td align="center"><b>Frequency Control</b></td>
    <td align="center"><b>Near Repeater</b></td>
  </tr>
  <tr>
    <td><img src="assets/screenshots/OpenHT_Dashv1.png" width="220" alt="OpenHT Dashboard"/></td>
    <td><img src="assets/screenshots/OpenHT_DashFreqv1.png" width="220" alt="OpenHT Frequency Control"/></td>
    <td><img src="assets/screenshots/OpenHT_Repeatv1.png" width="220" alt="OpenHT Near Repeater"/></td>
  </tr>
  <tr>
    <td align="center"><b>APRS Map</b></td>
    <td align="center"><b>Spotter Network</b></td>
    <td align="center"></td>
  </tr>
  <tr>
    <td><img src="assets/screenshots/OpenHT_APRSv1.png" width="220" alt="OpenHT APRS Map"/></td>
    <td><img src="assets/screenshots/OpenHT_Spottterv1.png" width="220" alt="OpenHT Spotter Network"/></td>
    <td></td>
  </tr>
</table>

---

## Supported Radios

| Radio | Status |
|-------|--------|
| Vero VR-N76 | ✅ Primary test device |
| Vero VR-N7600 | ✅ Target hardware |
| Vero VR-N7500 | 🔬 Untested (protocol compatible) |
| BTech UV-Pro | 🔬 Untested (protocol compatible) |
| RadioOddity GA-5WB | 🔬 Untested (protocol compatible) |

---

## Why OpenHT?

The vendor **HT / BS HT** app works, but has significant gaps:

- No "Near Repeater" function — you can't quickly find and tune the closest open repeater
- No offline repeater database — useless without cell service
- No Android Auto integration — dangerous to use while driving
- No open APRS station map with POI markers
- No NOAA weather alerts or NWR auto-monitoring
- Closed source — no ability to fix bugs or extend features

OpenHT fills those gaps.

---

## Features

### ✅ Implemented

#### Radio Control
- **Bluetooth connection** to radio via RFCOMM (Bluetooth Classic)
- **VFO tuning** — push any frequency to Band A or Band B with FM + Wide forced
- **Channel write** — write named channels with CTCSS/DCS tones to any group/slot
- **Band B auto-tune** — tune Band B to NOAA Weather Radio or SKYWARN frequency on alert

#### Near Repeater
- GPS-based lookup of closest open repeaters
- 3-tier data fallback: RepeaterBook Content Provider (live) → imported GPX → bundled Colorado GPX
- Sort by distance, filter by band (2m / 70cm), FM-compatible filter
- One-tap tune: pushes frequency directly to radio via Bluetooth
- Batch write up to 32 nearest repeaters to radio Group 6
- Data source indicator (live / GPX / CO) shown in AppBar

#### APRS
- Live APRS station map with decoded packet markers on OpenStreetMap
- Station list with GPS-relative distance
- Beacon and iGate configuration (in Settings)
- Spotter Network overlay

#### Weather Monitoring
- **NOAA Weather Alerts** via NWS API — 5-minute background polling
- Push notifications for Extreme and Severe alerts (POST_NOTIFICATIONS permission)
- Client-side SAME code filtering — only alerts matching your county FIPS
- Alert deduplication — each alert ID notified only once per session
- **NWR Station list** — distance-sorted nearest Weather Radio transmitters
  - Live fetch from NOAA; silently falls back to bundled CO/KS stations when offline
- NWR auto-monitor — tunes Band B to nearest NWR transmitter

#### Emergency Auto-Tune
- Polls NWS every 60 seconds for Tornado and Severe Thunderstorm Warnings
- **Priority 1**: Auto-tunes to served-agency SKYWARN repeater from loaded frequency plan
- **Priority 2**: Falls back to nearest NWR transmitter matching the alerted county SAME code
- Frequency lock for 5 minutes with dismissable banner

#### Frequency Plans (Deploy Mode)
- JSON-based frequency plan format — define repeater/simplex/SKYWARN channels for a region
- Write an entire plan to a radio group (e.g., Group 3) with one tap, streaming progress
- FIPS-linked: emergency auto-tune looks up the plan by county FIPS code
- Bundled plan: `ppraa_el_paso.json` (El Paso County, CO — PPARES, SKYWARN, PPRAA, RACES, PUEBLO WX, NOAA WX)

#### Settings & Developer Tools
- Restructured settings: Weather Monitoring, APRS, Frequency Plans, Channels & Radio, Developer
- **Channel Manager** — browse, edit, and export radio channels as CSV
- **Radio Debug Terminal** — live HEX log of TX/RX bytes, manual tune/scan buttons

### 🚧 In Progress
- Android Auto UI (CarAppService declared; List template for repeater selection)
- Audio streaming over BT headset (requires libsbc bindings in flutter_benlink)
- Winlink / BBS integration (port from HtStation)
- BLE connection mode (in addition to RFCOMM)

### 📋 Planned
- Offline repeater DB download by state
- APRS beacon transmission (with callsign + smart beaconing)
- Additional regional frequency plans (submit a PR!)
- APK sideload without Play Store

---

## Architecture

```
lib/
├── main.dart                          # App entry, Provider setup, notifications init
├── bluetooth/
│   └── radio_service.dart             # Wraps flutter_benlink; VFO tune, channel write, Band B
├── models/
│   ├── repeater.dart
│   ├── nwr_station.dart               # NOAA Weather Radio transmitter model
│   └── weather_alert.dart             # NWS alert with SAME codes + id
├── services/
│   ├── gps_service.dart               # Continuous GPS tracking
│   ├── noaa_service.dart              # NWR stations + NWS alerts + polling + notifications
│   ├── weather_alert_controller.dart  # Emergency auto-tune (SKYWARN plan → NWR fallback)
│   ├── freq_plan_service.dart         # Load & write regional frequency plans (Stream<int>)
│   ├── repeaterbook_connect_service.dart  # RepeaterBook Content Provider bridge
│   └── repeater_cache.dart            # SQLite repeater cache
├── aprs/
│   ├── aprs_packet.dart               # APRS packet parser
│   └── aprs_service.dart              # Packet stream manager
└── screens/
    ├── dashboard/                     # Main radio status screen
    ├── near_repeater/                 # Near Repeater (3-tier data, batch write)
    ├── aprs_map/                      # APRS stations on OpenStreetMap
    ├── weather/                       # NWR stations + active alerts list
    └── settings/                      # Weather, APRS, Freq Plans, Channels, Developer
```

### Assets
```
assets/
├── repeaters/                         # Bundled CO repeater GPX (offline fallback)
├── transmitters/
│   └── test_transmitters.json         # Bundled NWR transmitters (CO + KS)
└── freq_plans/
    └── ppraa_el_paso.json             # El Paso County, CO frequency plan
```

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.10
- Android Studio / Android SDK (API 26+)
- Android device with Bluetooth (BT Classic / RFCOMM support)
- VGC radio paired to your Android device via system Bluetooth settings

### Build

```bash
git clone https://github.com/repins267/OpenHT.git
cd OpenHT
flutter pub get
flutter run
```

### Pairing your radio

1. Power on your VGC radio
2. Android **Settings → Bluetooth → Pair new device**
3. Radio will appear as **VR-N76**, **VR-N7600**, or similar
4. Pair it — you may need to do this **twice** (audio + data channels)
5. Open OpenHT → Settings → **Scan for Radio** → Connect

---

## Near Repeater Flow

```
GPS fix
  → Query RepeaterBook Content Provider (live, if RB app installed)
  → OR: load user-imported GPX file
  → OR: load bundled Colorado GPX (always available offline)
  → Display sorted list (distance, tone, FM filter, band)
  → Tap repeater → push VFO frequency to radio via Bluetooth
  → OR: "Write to Radio" → batch program Group 6 with top 32 results
```

---

## Weather Alert Flow

```
WeatherAlertController (60s poll)
  → NWS API: active alerts for GPS position
  → Match: Tornado Warning or Severe Thunderstorm Warning
  → Check SAME code against loaded frequency plans
      → Found SKYWARN channel? → Auto-tune Band A (Priority 1)
      → No plan? → NWR transmitter by SAME code → Auto-tune Band A (Priority 2)
  → Lock frequency 5 min, show dismissable banner

NoaaService (5 min poll — Weather tab)
  → NWS API: all active alerts for position
  → Filter by SAME code (user's county FIPS)
  → Push notification for Extreme / Severe alerts (deduped by alert ID)
```

---

## Frequency Plan Format

Plans live in `assets/freq_plans/<id>.json`:

```json
{
  "id": "ppraa_el_paso",
  "name": "PPRAA / El Paso County ARES",
  "fips": "008041",
  "channels": [
    { "slot": 0, "name": "PPARES",  "rx_mhz": 147.345, "tx_mhz": 146.745, "tone_hz": 107.2 },
    { "slot": 1, "name": "SKYWARN", "rx_mhz": 146.970, "tx_mhz": 146.370, "tone_hz": 100.0 }
  ]
}
```

`fips` must match the 6-digit county code used in NWS SAME codes.
The channel named `SKYWARN` is used for emergency auto-tune.

---

## Android Auto

OpenHT declares a `CarAppService` targeting the **Navigation** category.
Android Auto UI will use:

- **List template** — browse Near Repeater results while driving
- **Navigation template** — APRS map with POI markers

> ⚠️ Android Auto requires testing with the [Desktop Head Unit (DHU)](https://developer.android.com/training/cars/testing/dhu) emulator before deployment.

---

## Credits & Attribution

This project stands on the shoulders of:

| Project | Author | Role |
|---------|--------|------|
| [benlink](https://github.com/khusmann/benlink) | Kyle Husmann **KC3SLD** | Reverse-engineered the Benshi BT protocol |
| [flutter_benlink](https://github.com/SarahRoseLives/flutter_benlink) | SarahRoseLives | Dart/Flutter port of benlink |
| [aprs-parser](https://github.com/k0qed/aprs-parser) | Lee **K0QED** | APRS packet parsing |
| [HtStation](https://github.com/Ylianst/HtStation) | Ylianst | Node.js base station — architecture inspiration |
| [HTCommander](https://github.com/Ylianst/HTCommander) | Ylianst | Windows desktop client — feature reference |
| [RepeaterBook](https://www.repeaterbook.com) | RepeaterBook.com | Repeater database API |
| [NOAA / NWS](https://www.weather.gov) | NOAA | Weather alerts API and NWR transmitter data |

---

## License

Apache-2.0 — see [LICENSE](LICENSE)

> An amateur radio license is required to **transmit** using this software.  
> Get licensed: [arrl.org/getting-licensed](https://www.arrl.org/getting-licensed)

---

## Contributing

PRs welcome. Areas of highest value right now:

1. **Regional frequency plans** — add a JSON plan for your county/ARES group
2. **Android Auto** CarAppService full implementation
3. **APRS beacon TX** — smart beaconing with callsign config
4. **Audio streaming** — BT headset TX/RX (needs flutter_benlink libsbc bindings)
5. **Testing** with UV-Pro, GA-5WB, VR-N7500 hardware

Please open an issue before starting large features.

---

## 🔐 Why was this built?

Read the [Privacy & Security Audit](./PRIVACY_AUDIT.md) for details on vendor hardware tracking and our mitigation strategies.
