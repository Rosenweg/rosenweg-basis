#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Zeichen fuer den Logo-Baukasten aus Material Symbols zusammensetzen.

Material Symbols (Google, Apache-2.0, https://github.com/google/material-design-icons)
im Stil "Rounded", gefuellt, Strichstaerke 600, 24 px:
    symbols/web/<name>/materialsymbolsrounded/<name>_wght600fill1_24px.svg

    werkzeug/logo/zeichen-zusammensetzen.py --ordner <material-svgs> --titel "Tür mit Schlüssel (Rosenweg Zutritt)" \\
        --haupt door_front --zusatz key > werkzeug/logo/zeichen/<name>.svg
    werkzeug/logo/zeichen-zusammensetzen.py --laden door_front key   # holt die SVGs nach material/ (Netz)

Ergebnis: SVG mit viewBox 0 0 400 400, wie der Baukasten es verlangt. Mit --zusatz sitzt
ein zweites, kleineres Symbol rechts unten; ein Rand in der Farbe der Plakette (weiss)
trennt es vom Hauptsymbol. Der Rand steht in style="…", weil der Baukasten fill/stroke-
Attribute entfernt (die Plakette ist in allen Fassungen weiss, auch in der monochromen
Maske, darum passt Weiss immer).
"""
import argparse
import os
import re
import sys
import urllib.request

QUELLE = "https://raw.githubusercontent.com/google/material-design-icons/master/symbols/web/{n}/materialsymbolsrounded/{n}_wght600fill1_24px.svg"


def pfade(ordner, name):
    with open(os.path.join(ordner, f"{name}.svg")) as f:
        s = f.read()
    d = re.findall(r'<path[^>]*\sd="([^"]+)"', s)
    if not d or 'viewBox="0 -960 960 960"' not in s:
        sys.exit(f"{name}: kein Material-Symbol (viewBox 0 -960 960 960)")
    return d


def gruppe(d, x, y, groesse, extra=""):
    k = groesse / 960
    inhalt = "".join(f'<path d="{p}"{extra}/>' for p in d)
    return f'<g transform="translate({x:.1f} {y:.1f}) scale({k:.5f}) translate(0 960)">{inhalt}</g>'


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--ordner", default="material")
    a.add_argument("--laden", nargs="+", metavar="NAME", help="Material-SVGs nach --ordner laden und beenden")
    a.add_argument("--titel")
    a.add_argument("--haupt")
    a.add_argument("--zusatz", help="zweites Symbol rechts unten")
    a.add_argument("--zusatz-groesse", type=float, default=220)
    a.add_argument("--rand", type=float, default=34, help="Breite des weissen Randes um das Zusatzsymbol")
    o = a.parse_args()

    if o.laden:
        os.makedirs(o.ordner, exist_ok=True)
        for n in o.laden:
            with urllib.request.urlopen(QUELLE.format(n=n)) as r, open(os.path.join(o.ordner, f"{n}.svg"), "wb") as f:
                f.write(r.read())
        return
    if not (o.titel and o.haupt):
        a.error("--titel und --haupt fehlen")

    teile = []
    quellen = [o.haupt]
    if o.zusatz:
        # Hauptsymbol etwas nach links oben, damit rechts unten Platz bleibt
        teile.append(gruppe(pfade(o.ordner, o.haupt), -14, -14, 400))
        g = o.zusatz_groesse
        x = y = 400 - g + 6
        rand = o.rand * 960 / g
        z = pfade(o.ordner, o.zusatz)
        teile.append(gruppe(z, x, y, g, f' style="fill:#fff;stroke:#fff;stroke-width:{rand:.0f};stroke-linejoin:round"'))
        teile.append(gruppe(z, x, y, g))
        quellen.append(o.zusatz)
    else:
        teile.append(gruppe(pfade(o.ordner, o.haupt), 0, 0, 400))

    print('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">')
    print(f"  <title>{o.titel}</title>")
    print(f"  <!-- Material Symbols Rounded ({', '.join(quellen)}), Apache-2.0, siehe werkzeug/logo/zeichen/LIZENZEN.md -->")
    for t in teile:
        print("  " + t)
    print("</svg>")


if __name__ == "__main__":
    main()
