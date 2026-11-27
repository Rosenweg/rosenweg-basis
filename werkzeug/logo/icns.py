#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""macOS-Symboldatei (.icns) aus PNGs, ohne iconutil (laeuft auch unter Linux).

    werkzeug/logo/icns.py <ziel.icns> <png-16> <png-32> <png-64> <png-128> <png-256> <png-512> <png-1024>

Die PNGs muessen genau diese Groessen haben (16, 32, 64, 128, 256, 512, 1024 px).
Eingetragen werden sie als die ueblichen Typen (1x und @2x), wie iconutil es tut.
"""
import struct
import sys

# Typ -> Kantenlaenge des PNG
TYPEN = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512),
         ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]


def groesse(daten):
    if daten[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("kein PNG")
    return struct.unpack(">II", daten[16:24])


def main():
    if len(sys.argv) != 9:
        raise SystemExit(__doc__)
    ziel, dateien = sys.argv[1], sys.argv[2:]
    pngs = {}
    for d in dateien:
        with open(d, "rb") as f:
            b = f.read()
        w, h = groesse(b)
        if w != h:
            raise SystemExit(f"{d}: nicht quadratisch")
        pngs[w] = b
    for s in (16, 32, 64, 128, 256, 512, 1024):
        if s not in pngs:
            raise SystemExit(f"PNG mit {s} px fehlt")
    teile = b"".join(t.encode() + struct.pack(">I", len(pngs[s]) + 8) + pngs[s] for t, s in TYPEN)
    with open(ziel, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(teile) + 8) + teile)


if __name__ == "__main__":
    main()
