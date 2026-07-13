#!/usr/bin/env python3
"""
custom_firmware.py — OpenHT firmware toolkit for the VR-N76 (CSR8670 DFU2 OTA).

STATUS OF THE CUSTOM-FIRMWARE UNLOCK (determined 2026-05-29):
  The DFU2 image carries a 132-byte block at file offset 0x77c that is a
  KEY-DEPENDENT cryptographic authentication value (signature / keyed-MAC):
    - across 10 images every one of its 132 bytes varies (0 constant offsets),
    - byte distribution is ~uniform random (107/256 distinct, max repeat 3),
    - it fully changes between v124->v125 even though their payloads differ by
      only ~15 bytes (rules out a per-partition hash table),
    - no MD5/SHA1/SHA256/CRC32 of any image region reproduces it.
  => It is NOT offline-recomputable. We CANNOT forge it without the signing key.

  Therefore this tool does NOT (and cannot) "compute the correct header."
  It implements everything that IS valid and recomputable:
    * apply / create BSDIFF40 patches against upgrade_base.bin (validated path),
    * edit the cleartext bootstrap region of the payload,
    * compute the DOWNLOAD-phase MD5 (the only app-side check; vs server metadata),
    * copy the signature block + APPUPFTR footer through UNCHANGED,
    * emit a single-byte "enforcement-test" image so you can empirically determine
      on the radio whether the signature is ENFORCED by the VM-Upgrade bootloader.

  The open-firmware go/no-go now reduces to ONE on-radio experiment (see make-test
  + capture_runbook.md Step F): push a payload-modified-but-signature-unchanged
  image and observe whether VM-Upgrade validation rejects it BEFORE commit.
    - If the radio ACCEPTS it  -> signature not enforced -> custom firmware is OPEN
      (use build-patch on arbitrary modified images).
    - If the radio REJECTS it  -> signature enforced -> need the key or a bootloader
      bypass; custom firmware stays locked.

Read-only on sources; writes only paths you pass on the CLI.
"""
import sys, os, struct, hashlib, argparse
import bsdiff4

DEFAULT_BASE = "upgrade_base.bin"  # extract from upgrade_base_v{N}.bin.zip (see docs/fieldnotes/vr-n76-firmware.md §7)
BLOCK_OFF, BLOCK_LEN = 0x77c, 132          # signature / keyed-MAC block
HDR_END = 0xA50C                            # DFU2 container header length
PAYLOAD_START = HDR_END                     # ARM payload begins here
# Cleartext bootstrap region (per Ghidra handoff): payload 0x0..~0x27000 is real code;
# above that is the CSR-compressed blob. Editing inside the compressed blob is unsafe.
BOOTSTRAP_SAFE_END = PAYLOAD_START + 0x26000

def md5hex(b): return hashlib.md5(b).hexdigest()

def parse(b):
    if b[:8] != b"APPUHDR2":
        raise ValueError("not a CSR DFU2 image (missing APPUHDR2 magic)")
    partlen = struct.unpack_from(">I", b, 0x32)[0]
    return {
        "size": len(b),
        "partlen": partlen,
        "header": (0, HDR_END),
        "sig_block": (BLOCK_OFF, BLOCK_OFF + BLOCK_LEN),
        "payload": (PAYLOAD_START, partlen),
        "footer": (partlen, len(b)),
    }

def cmd_report(args):
    b = open(args.image, "rb").read()
    p = parse(b)
    print(f"image      : {args.image}")
    print(f"size       : {p['size']}  md5(download-check)={md5hex(b)}")
    print(f"DFU2 header: 0x0..0x{HDR_END:x}")
    print(f"sig block  : 0x{BLOCK_OFF:x}..0x{BLOCK_OFF+BLOCK_LEN:x}  (132 B, KEY-DEPENDENT, not forgeable)")
    print(f"             {b[BLOCK_OFF:BLOCK_OFF+16].hex(' ')} ...")
    print(f"payload    : 0x{PAYLOAD_START:x}..0x{p['partlen']:x}")
    print(f"footer     : 0x{p['partlen']:x}..0x{p['size']:x}  (APPUPFTR, {p['size']-p['partlen']} B)")
    print(f"cleartext-editable bootstrap window: 0x{PAYLOAD_START:x}..0x{BOOTSTRAP_SAFE_END:x}")

def cmd_apply(args):
    base = open(args.base, "rb").read()
    patch = open(args.patch, "rb").read()
    out = bsdiff4.patch(base, patch)
    open(args.out, "wb").write(out)
    print(f"applied: {len(out)} B  md5={md5hex(out)} -> {args.out}")

def cmd_build_patch(args):
    """Create a VALID BSDIFF40 patch (base -> modified_image). This half always works."""
    base = open(args.base, "rb").read()
    img = open(args.image, "rb").read()
    patch = bsdiff4.diff(base, img)
    open(args.out, "wb").write(patch)
    # round-trip verify
    rt = bsdiff4.patch(base, patch)
    ok = (rt == img)
    print(f"patch: {len(patch)} B -> {args.out}")
    print(f"round-trip apply == image: {ok}  (image md5={md5hex(img)})")
    if not ok:
        print("ERROR: round-trip mismatch", file=sys.stderr); sys.exit(2)
    print("NOTE: this patch is byte-exact for the app's apply step, but the radio will")
    print("      still validate the embedded signature on flash. See make-test / Step F.")

def cmd_make_test(args):
    """
    Produce an enforcement-test image: flip ONE byte in the cleartext bootstrap,
    leaving the 132-byte signature block + APPUPFTR footer UNCHANGED, and report the
    new download-MD5. Pushing this to the radio answers 'is the signature enforced?'.
    """
    b = bytearray(open(args.image, "rb").read())
    p = parse(bytes(b))
    off = args.offset
    if not (PAYLOAD_START <= off < BOOTSTRAP_SAFE_END):
        print(f"refusing: offset 0x{off:x} is outside the safe cleartext bootstrap "
              f"window 0x{PAYLOAD_START:x}..0x{BOOTSTRAP_SAFE_END:x}", file=sys.stderr)
        sys.exit(2)
    if BLOCK_OFF <= off < BLOCK_OFF+BLOCK_LEN or off >= p["partlen"]:
        print("refusing: offset hits the signature block or footer", file=sys.stderr); sys.exit(2)
    old = b[off]; b[off] ^= 0xFF
    open(args.out, "wb").write(b)
    print(f"flipped byte @0x{off:x}: 0x{old:02x} -> 0x{b[off]:02x}")
    print(f"signature block @0x{BLOCK_OFF:x}: UNCHANGED (cannot be regenerated)")
    print(f"download-phase MD5 of test image (advertise this as FirmwareInfo.md5): {md5hex(bytes(b))}")
    print(f"wrote {args.out}")
    print("\nEnforcement test (SAFE: CSR VM-Upgrade validates BEFORE commit/reboot):")
    print("  1. Serve/MITM CheckFirmwareUpdateResult so FirmwareInfo.md5 == the value above.")
    print("  2. Let the app push this image via VM-Upgrade (capture_runbook.md Step F).")
    print("  3. Observe the radio's validation result (UpgradeHost* ACK/NAK) BEFORE confirming commit.")
    print("     ACCEPT => signature NOT enforced => custom firmware OPEN.")
    print("     REJECT => signature enforced => need key/bootloader-bypass.")
    print("  Do NOT confirm the final commit unless validation passes.")

def cmd_forge(args):
    raise SystemExit(
        "forge-signature: NOT POSSIBLE. The 132-byte block @0x77c is a key-dependent "
        "signature/MAC (full avalanche, no recomputable relation to content hashes). "
        "Forging it requires the OEM signing key. Run 'make-test' to determine whether "
        "the radio even enforces it.")

def main():
    ap = argparse.ArgumentParser(description="OpenHT VR-N76 firmware toolkit (CSR DFU2).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("report", help="describe a DFU2 image's structure + checks")
    r.add_argument("image"); r.set_defaults(func=cmd_report)

    a = sub.add_parser("apply", help="apply a BSDIFF40 patch to a base")
    a.add_argument("--base", default=DEFAULT_BASE); a.add_argument("patch"); a.add_argument("out")
    a.set_defaults(func=cmd_apply)

    bp = sub.add_parser("build-patch", help="create a valid BSDIFF40 patch base->modified image")
    bp.add_argument("--base", default=DEFAULT_BASE); bp.add_argument("image"); bp.add_argument("out")
    bp.set_defaults(func=cmd_build_patch)

    mt = sub.add_parser("make-test", help="flip one cleartext byte for the signature-enforcement test")
    mt.add_argument("image"); mt.add_argument("out")
    mt.add_argument("--offset", type=lambda x: int(x, 0), default=PAYLOAD_START + 0x1000)
    mt.set_defaults(func=cmd_make_test)

    fg = sub.add_parser("forge-signature", help="(impossible — explains why)")
    fg.set_defaults(func=cmd_forge)

    args = ap.parse_args(); args.func(args)

if __name__ == "__main__":
    main()
