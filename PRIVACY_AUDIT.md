# 🛡️ Privacy & Security Audit

The development of **OpenHT** was prompted by a deep-dive security analysis of the proprietary vendor application (**BS HT**). As a cybersecurity professional and radio operator, I identified several high-risk behaviors that compromise user data sovereignty.

## The "Vendor Gap" vs. The OpenHT Standard

| Risk Factor | Vendor App (Proprietary) | **OpenHT (Open Source)** |
| :--- | :--- | :--- |
| **Hardware ID** | **High Risk.** Uses Java reflection to harvest the permanent, non-redacted Bluetooth MAC address. | **None.** Uses standard Android Bluetooth APIs with zero hardware identifier tracking. |
| **Data Residency** | **Opaque.** Frequently calls \pc.benshikj.com\ (Alibaba Cloud) to sync device and location data. | **Transparent.** Connects only to community-standard APRS-IS and RepeaterBook endpoints. |
| **SDK Bloat** | **High.** Integrated with Tencent (QQ/WeChat) SDKs known for background device fingerprinting. | **Zero.** No third-party social media SDKs or hidden tracking libraries. |
| **Network Enrollment** | **Mandatory.** Automatically enrolls your radio as a node in a proprietary Chinese linking network. | **Opt-in.** You choose which networks (APRS, Winlink) to join and when. |

## Technical Findings

Our decompilation and Logcat analysis revealed the following "under-the-hood" behaviors in the vendor's ecosystem:

* **Bypassing Android Privacy:** The vendor app targets the internal Android system interfaces to bypass standard Bluetooth redaction. This allows them to create a "Forever ID" for your radio hardware that survives app uninstalls or phone factory resets.
* **Shadow Linking (AFSK Relay):** The vendor's protocol files reveal an \AFSK = 3\ message type. This architecture allows the app to digitize over-the-air audio and relay it to foreign servers, potentially turning your local transceiver into an unannounced internet gateway.
* **Encrypted Local Data:** Analysis of the vendor's RepeaterBook implementation shows a 14MB encrypted SQLCipher database. **OpenHT** moves away from this "black box" approach by using open GPX/CSV formats and transparent API tokens.

## Our Privacy Promise

**OpenHT** is built on the principle that a radio is a tool, not a data sensor. 

1.  We do not collect, store, or transmit your radio's MAC address.
2.  Your GPS location is used locally for "Near Repeater" calculations and only transmitted when you explicitly enable **APRS Beaconing**.
3.  All source code is peer-reviewable to ensure no "phone home" logic is introduced.
