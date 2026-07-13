#!/usr/bin/env python3
"""
firmware_enforcement_test.py
============================
Determine whether the VR-N76 radio's CSR GAIA VM-Upgrade bootloader ENFORCES the
132-byte signature found in the DFU2 container (VGC_firmware_comparison.md §6).

It pushes a firmware image to the radio over benlink's BT delivery path, drives the
VM-Upgrade handshake up to and INCLUDING the device-side validation, observes the
verdict, and then ABORTS — it NEVER sends UPDATE_TRANSFER_COMPLETE_RES, so the radio
does NOT reboot into / commit the test image. The transferred bytes land only in the
radio's INACTIVE flash bank and are discarded on abort; the running firmware is untouched.

WHAT THE VERDICT MEANS
----------------------
Input image = `custom_firmware.py make-test` output: one cleartext-bootstrap byte flipped,
signature block @0x77c + APPUPFTR footer left UNCHANGED (we cannot regenerate them).

  * PASS  (UPDATE_TRANSFER_COMPLETE_IND, no error):
        the radio accepted a payload-modified image whose signature/footer no longer match
        -> NO meaningful payload authentication -> CUSTOM FIRMWARE IS OPEN.
        (Then `custom_firmware.py build-patch` on arbitrary modified images is flashable;
         you'd recompute only the footer CSR-checksum + the download MD5.)

  * FAIL  (UPDATE_ERROR with an OEM-validation code):
        the radio rejected the modified image -> integrity/signature ENFORCED.
        Read the error code (see table) to learn WHICH check failed.

CSR UpgradeHostErrorCode table (the code in UPDATE_ERROR / printed by benlink's
UpdateError._missing_ to stderr for unmapped values):
  0x21  BATTERY_LOW                         (charge the radio and retry; not a verdict)
  0x22  INVALID_SYNC_ID                     (sync/md5_tail mismatch; not a verdict)
  0x30-0x33  BAD_LENGTH_* (parse/headers)   -> structural; image framing wrong
  0x34  BAD_LENGTH_SIGNATURE                -> a signature field IS expected/parsed
  0x38  OEM_VALIDATION_FAILED_HEADERS       \
  0x39  OEM_VALIDATION_FAILED_UPGRADE_HDR    |
  0x3A  OEM_VALIDATION_FAILED_PART_HEADER1   |  ENFORCED signature / OEM auth.
  0x3B  OEM_VALIDATION_FAILED_PART_HEADER2   |  Custom firmware needs the signing key,
  0x3C  OEM_VALIDATION_FAILED_PARTITION_DATA |  a bootloader bypass, or a downgrade to an
  0x3D  OEM_VALIDATION_FAILED_FOOTER         |  unsigned loader.  0x3C/0x3D are the ones
  0x3E  OEM_VALIDATION_FAILED_MEMORY        /   that cover the payload+footer we modified.
  0x81  SYNC_IS_DIFFERENT                   (resume/sync; not a verdict)

  Interpretation:
    0x38-0x3E  -> SIGNATURE/OEM auth ENFORCED  (the expected result if the image is signed)
    0x30-0x35  -> structural/checksum only; the CSR footer CRC may be recomputable (RE it)
    PASS       -> no payload auth; OPEN

PREREQUISITES
-------------
  * benlink installed and your BT delivery path already working (you confirmed Phase 1).
  * A make-test image:  python custom_firmware.py make-test <good.firmware> test.firmware
  * Charge the radio (avoid 0x21 BATTERY_LOW masking the result).

USAGE
-----
  python firmware_enforcement_test.py --mac AA:BB:CC:DD:EE:FF --image test.firmware
  # control run first (should PASS) — proves the harness + a genuine image validate:
  python firmware_enforcement_test.py --mac AA:BB:CC:DD:EE:FF --image 259.firmware --control
"""
from __future__ import annotations
import argparse, asyncio, hashlib, sys

from benlink.command import CommandConnection, UnknownProtocolMessage
from benlink.firmware import FirmwareBundle, UpdateInfo
from benlink.firmware_updater import FirmwareUpdater, _msg_vm_control
from benlink.protocol.command.bt_notification import BtEventNotificationBody, BtEventType
from benlink.protocol.command.vm import (
    VmControlType, VmuPacketType,
    VmControlUpdateData, VmControlUpdateIsValidationDoneReq,
    UpdateStartCfmCode, UpdateState,
)

CHUNK_TIMEOUT = 60.0
VALIDATION_TIMEOUT = 120.0


def load_bundle(path: str) -> FirmwareBundle:
    data = open(path, "rb").read()
    # update_info is only used for download bookkeeping; placeholders are fine for flashing.
    b = FirmwareBundle(data=data, update_info=UpdateInfo(patch_url="local", base_url="local"))
    print(f"[bundle] {path}: {b.size} bytes  md5={b.md5}  md5_tail={b.md5_tail.hex()}")
    return b


async def push_and_get_verdict(conn: CommandConnection, bundle: FirmwareBundle) -> tuple[str, object]:
    """
    Drive VM-Upgrade through validation, then ABORT (never TRANSFER_COMPLETE_RES).
    Returns ('PASS', None) | ('FAIL', error_obj) | ('INCONCLUSIVE', reason).
    """
    u = FirmwareUpdater(conn, bundle)
    fw = bundle.data
    total = len(fw)

    await u._step_register_bt_notification()
    await u._step_vm_connect()

    update_state = await u._step_sync(bundle.md5_tail)
    print(f"[sync] UPDATE_SYNC_CFM update_state={update_state.name}", file=sys.stderr)

    cfm = await u._step_start()
    print(f"[start] UPDATE_START_CFM code={cfm.name}", file=sys.stderr)
    if cfm == UpdateStartCfmCode.GOTO_NEXT_STATE:
        await u._step_abort(); await u._step_vm_disconnect()
        return ("INCONCLUSIVE", "radio already mid-update (GOTO_NEXT_STATE); power-cycle and retry")

    try:
        if update_state == UpdateState.TRANSFER_COMPLETE:
            print("[data] SYNC already TRANSFER_COMPLETE — skipping data loop", file=sys.stderr)
        else:
            await u._step_data_start()
            offset = 0
            while offset < total:
                req = await u._wait_vmu(VmuPacketType.UPDATE_DATA_BYTES_REQ, timeout=CHUNK_TIMEOUT)
                offset += req.n_bytes_skip
                chunk = fw[offset: offset + req.n_bytes_requested]
                if not chunk:
                    raise RuntimeError(f"device asked for bytes past EOF at offset {offset}")
                is_last = (offset + len(chunk) >= total)
                await u._send(_msg_vm_control(
                    VmControlType.UPDATE_DATA,
                    VmControlUpdateData(is_final_fragment=is_last, data=chunk),
                    n_bytes_payload=1 + len(chunk),
                ))
                offset += len(chunk)
                if offset % (32 * 1024) < req.n_bytes_requested:
                    print(f"[data] {offset}/{total} bytes", file=sys.stderr)

        # ---- validation watch: PASS vs FAIL, never commit ----
        verdict = await _watch_validation(conn, u)
        return verdict
    finally:
        # SAFETY: discard the staged image in the inactive bank; do NOT reboot/commit.
        print("[safe] sending UPDATE_ABORT_REQ + VM_DISCONNECT (no commit, no reboot)", file=sys.stderr)
        await u._step_abort()
        await u._step_vm_disconnect()


async def _watch_validation(conn, updater) -> tuple[str, object]:
    """Poll IS_VALIDATION_DONE_REQ; resolve to PASS / FAIL(error)."""
    loop = asyncio.get_event_loop()
    deadline = loop.time() + VALIDATION_TIMEOUT
    while loop.time() < deadline:
        await updater._send(_msg_vm_control(
            VmControlType.UPDATE_IS_VALIDATION_DONE_REQ,
            VmControlUpdateIsValidationDoneReq(),
            n_bytes_payload=0,
        ))
        q: asyncio.Queue = asyncio.Queue()

        def _h(radio_msg):
            if not isinstance(radio_msg, UnknownProtocolMessage):
                return
            body = radio_msg.message.body
            if not isinstance(body, BtEventNotificationBody) or body.bt_event_type != BtEventType.VMU_PACKET:
                return
            vmu = body.bt_event
            if vmu.vmu_packet_type in (
                VmuPacketType.UPDATE_TRANSFER_COMPLETE_IND,
                VmuPacketType.UPDATE_IS_VALIDATION_DONE_CFM,
                VmuPacketType.UPDATE_ERROR,
            ):
                q.put_nowait(vmu)

        remove = conn._add_message_handler(_h)
        try:
            vmu = await asyncio.wait_for(q.get(), timeout=10.0)
        except asyncio.TimeoutError:
            continue
        finally:
            remove()

        if vmu.vmu_packet_type == VmuPacketType.UPDATE_TRANSFER_COMPLETE_IND:
            return ("PASS", None)
        if vmu.vmu_packet_type == VmuPacketType.UPDATE_ERROR:
            # vmu.msg is VmControlUpdateError; raw unmapped codes are printed by
            # UpdateError._missing_ to stderr. Surface whatever we parsed.
            return ("FAIL", getattr(vmu.msg, "update_error", vmu.msg))
        # IS_VALIDATION_DONE_CFM == still validating; poll again
        await asyncio.sleep(1.0)
    return ("INCONCLUSIVE", "validation timed out")


async def main():
    ap = argparse.ArgumentParser(description="VR-N76 firmware signature-enforcement test (safe, no commit).")
    ap.add_argument("--mac", required=True, help="radio BT MAC, e.g. AA:BB:CC:DD:EE:FF")
    ap.add_argument("--image", required=True, help="firmware image to push (make-test output, or genuine for --control)")
    ap.add_argument("--channel", default="auto", help="RFCOMM channel (default auto; set int if SDP discovery fails)")
    ap.add_argument("--control", action="store_true", help="this is a genuine image; expect PASS")
    args = ap.parse_args()

    bundle = load_bundle(args.image)
    ch = args.channel if args.channel == "auto" else int(args.channel)

    # NOTE: this mirrors your working Phase-1 connect. If your setup differs, swap in
    # however you obtain a connected CommandConnection.
    conn = CommandConnection.new_rfcomm(args.mac, channel=ch)
    await conn.connect()
    print(f"[conn] connected to {args.mac}")
    try:
        verdict, info = await push_and_get_verdict(conn, bundle)
    finally:
        await conn.disconnect()

    print("\n================ VERDICT ================")
    if verdict == "PASS":
        if args.control:
            print("PASS (control): harness OK — a genuine image validates. Now run WITHOUT --control on the make-test image.")
        else:
            print("PASS: radio accepted a payload-MODIFIED image with a STALE signature.")
            print("  => signature/integrity NOT enforced => CUSTOM FIRMWARE IS OPEN.")
            print("  Next: build-patch arbitrary modified images; recompute footer CSR-CRC + download MD5.")
    elif verdict == "FAIL":
        print(f"FAIL: radio REJECTED the modified image. error={info!r}")
        print("  Check the code against the table at the top of this file:")
        print("   0x38-0x3E => OEM signature/auth ENFORCED (needs key/bypass/downgrade).")
        print("   0x30-0x35 => structural/checksum only (CSR footer CRC may be recomputable).")
        print("   (also watch stderr for benlink's 'Unknown value for UpdateError: <raw>' line.)")
    else:
        print(f"INCONCLUSIVE: {info}")
    print("Safe: no UPDATE_TRANSFER_COMPLETE_RES was sent; radio did not reboot/commit.")

if __name__ == "__main__":
    asyncio.run(main())
