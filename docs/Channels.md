# OpenHT — Channel Programming Reference

> **Source:** HTCommander `RadioChannelInfo.cs` (Ylianst, Apache 2.0) + BS_HT APK decompilation  
> Confirmed against live VR-N76 hardware.

---

## Channel Memory Structure

The radio stores channels in **groups (regions)**. The number of groups and channels per group is
self-reported by the radio via `GET_DEV_INFO` — do NOT hardcode.

```
region_count  = Info.region_count    // number of channel groups
channel_count = Info.channel_count   // channels per group (VR-N76: 32)
total_slots   = region_count × channel_count
```

### Channel Groups (VR-N76 defaults)

| Group Index | Name | Purpose |
|-------------|------|---------|
| 0 | Group 1 | User channels |
| 1 | Group 2 | User channels |
| 2 | Group 3 | User channels (OpenHT writes PPARES/SKYWARN/RACES here) |
| 3 | Group 4 | User channels |
| 4 | NOAA Weather | WX1–WX7 standard weather frequencies |
| 5 | Near Repeaters | Written by OpenHT Near Repeaters tab |

> Group names and count are self-reported. Read with `READ_REGION_NAME` (cmd 73).

---

## Channel Wire Format (25 Bytes)

From `RadioChannelInfo.cs → ToByteArray()` — authoritative source:

```
Offset  Size  Field
──────  ────  ─────────────────────────────────────────────────────────────
r[0]    1     channel_id (0-indexed within current group)
r[1-4]  4     tx_freq as int32 (Hz), top 2 bits = tx_mod
              packed: (int)tx_mod << 30 | tx_freq_hz
r[5-8]  4     rx_freq as int32 (Hz), top 2 bits = rx_mod
              packed: (int)rx_mod << 30 | rx_freq_hz
r[9-10] 2     tx_sub_audio as int16  (CTCSS: Hz×100, DCS: number, None: 0)
r[11-12] 2    rx_sub_audio as int16  (CTCSS: Hz×100, DCS: number, None: 0)
r[13]   1     flags byte:
                bit 7: scan
                bit 6: tx_at_max_power
                bit 5: talk_around
                bit 4: bandwidth_wide  (0=NARROW/NFM, 1=WIDE/FM)
                bit 3: pre_de_emph_bypass
                bit 2: sign
                bit 1: tx_at_med_power
                bit 0: tx_disable
r[14]   1     flags byte:
                bit 7: fixed_freq
                bit 6: fixed_bandwidth
                bit 5: fixed_tx_power
                bit 4: mute
                bits 3-0: (unused)
r[15-24] 10   name as UTF-8, null-terminated, 10 bytes MAX (NOT 8)
```

**Exact C# decode from source:**
```csharp
channel_id  = msg[5];
tx_mod      = (RadioModulationType)(msg[6] >> 6);
tx_freq     = Utils.GetInt(msg, 6) & 0x3FFFFFFF;
rx_mod      = (RadioModulationType)(msg[10] >> 6);
rx_freq     = Utils.GetInt(msg, 10) & 0x3FFFFFFF;
tx_sub_audio = Utils.GetShort(msg, 14);
rx_sub_audio = Utils.GetShort(msg, 16);
bandwidth   = ((msg[18] & 0x10) != 0) ? WIDE : NARROW;
name_str    = UTF8.GetString(msg, 20, 10).Trim();  // 10 chars, NOT 8
```

> ⚠️ Note the wire format offset vs. raw message offset difference: the MDC packet
> adds a 5-byte header before the payload, so `msg[5]` is `r[0]` in the wire format above.

---

## Field Encoding

### Frequency
```
Hz as int32 — no decimal point
146.520 MHz → 146520000
147.390 MHz → 147390000
446.000 MHz → 446000000
```

### Modulation (top 2 bits of freq field)
```
FM  = 0    (most analog ham repeaters)
AM  = 1    (aircraft band)
DMR = 2    (digital — VR-N7600 only)
```

### Sub-Audio (CTCSS / DCS / None)
```
None:  0
CTCSS: tone_hz × 100 as int16
       88.5 Hz → 8850
       100.0 Hz → 10000
       127.3 Hz → 12730
       162.2 Hz → 16220
DCS:   tone number as int16
       D023N → 23
       D047N → 47
       D114N → 114
```

### Bandwidth
```
NARROW (NFM, 12.5 kHz) → bit 4 of r[13] = 0
WIDE   (FM,  25.0 kHz) → bit 4 of r[13] = 1
```

### TX Power
```
High   → tx_at_max_power = true,  tx_at_med_power = false
Medium → tx_at_max_power = false, tx_at_med_power = true
Low    → tx_at_max_power = false, tx_at_med_power = false
```

---

## Reading Channels

```dart
// On connect, after GET_DEV_INFO gives us channel_count:
for (int i = 0; i < info.channelCount; i++) {
  controller.readChannel(i);  // READ_RF_CH (cmd 13)
}

// Switch group then re-read all:
controller.setRegion(groupIndex);  // SET_REGION (cmd 60)
for (int i = 0; i < info.channelCount; i++) {
  controller.readChannel(i);
}
```

---

## Writing Channels

### Single channel write (WRITE_RF_CH — cmd 14)
```dart
// Always re-read after write to confirm success:
final ok = await controller.writeChannel(channel);
if (ok) {
  await controller.readChannel(channel.channelId); // READ_RF_CH to confirm
}
```

**HTCommander pattern:**
```csharp
case RadioBasicCommand.WRITE_RF_CH:
    if (value[4] == 0)  // 0 = success
        SendCommand(RadioBasicCommand.READ_RF_CH, value[5]);  // confirm
    break;
```

### Write to specific group slot (WRITE_REGION_CH — cmd 58)
```dart
// Write channel to group 5 (Near Repeaters), slot 0:
controller.writeRegionChannel(groupIndex: 5, slotIndex: 0, channel: ch);
```

### Write group name (WRITE_REGION_NAME — cmd 59)
```dart
controller.writeRegionName(groupIndex: 5, name: "Near Rptrs");
```

---

## CSV Import/Export Formats

OpenHT supports two CSV formats. **Use Format 2 (Native VGC) for writing to radio.**

### Format 1 — CHIRP Compatible (export only)
```csv
Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power
0,W0ABC,146.520000,,,,,,,, NFM,,,5.0W
1,W0RPT,147.390000,+,0.600000,Tone,100.0,100.0,,,NFM,,,5.0W
```

### Format 2 — Native VGC (import/export, preferred)
```csv
title,tx_freq,rx_freq,tx_sub_audio,rx_sub_audio,tx_power,bandwidth,scan,talk_around,pre_de_emph_bypass,sign,tx_dis,mute,rx_modulation,tx_modulation
W0ABC,146520000,146520000,0,0,H,12500,1,0,0,0,0,0,FM,FM
W0RPT,147990000,147390000,10000,10000,H,12500,1,0,0,0,0,0,FM,FM
W0DCS,146500000,146500000,47,47,H,12500,1,0,0,0,0,0,FM,FM
```

Field reference:
```
tx_freq / rx_freq   Hz as integer (146520000 = 146.520 MHz)
tx_sub_audio        CTCSS: Hz×100 (10000=100.0Hz), DCS: number (47=D047N), 0=none
rx_sub_audio        same encoding as tx_sub_audio
tx_power            H=High(5W), M=Medium(3W), L=Low(1W)
bandwidth           12500=NFM narrow, 25000=FM wide
scan                0=off, 1=on
talk_around         0=off, 1=on
pre_de_emph_bypass  0=off, 1=on
sign                0=off, 1=on
tx_dis              0=enabled, 1=disabled
mute                0=off, 1=on
rx_modulation       FM, AM, DMR
tx_modulation       FM, AM, DMR
```

---

## Standard NOAA Weather Frequencies (Group 4 / "NOAA Weather")

These 7 channels are written by "Re-Write Group 5 with Standard WX freqs":

| Slot | Name | Frequency |
|------|------|-----------|
| 0 | WX1 | 162.550 MHz |
| 1 | WX2 | 162.400 MHz |
| 2 | WX3 | 162.475 MHz |
| 3 | WX4 | 162.425 MHz |
| 4 | WX5 | 162.450 MHz |
| 5 | WX6 | 162.500 MHz |
| 6 | WX7 | 162.525 MHz |

All NOAA channels: NFM (12500), no sub-audio, TX disabled, High power.

---

## Known Issues

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| NOAA write fails 0/7 | `WRITE_RF_CH` serialization bug (FF 01 in payload) | Strip MDC header from payload |
| CSV import "success" but no radio change | Import writes to SQLite cache, not radio | Wire import → `writeChannelDirect()` loop |
| Channel name truncated at 8 chars | Wrong limit hardcoded | Limit is 10 chars — change truncation |
| Group count hardcoded 6×32 | Ignores `Info.region_count` | Read from `GET_DEV_INFO` response |

---

*Source: HTCommander `RadioChannelInfo.cs` (Ylianst, Apache 2.0)*  
*Last updated: March 2026*
