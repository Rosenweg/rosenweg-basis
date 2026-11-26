#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Vorschau: so sehen die Android-Icons auf dem Startbildschirm aus.

    werkzeug/logo/startbildschirm.py --aus tafel.png <ordner>/<name> [<ordner>/<name> …]
    werkzeug/logo/startbildschirm.py --aus tafel.png ../calculator-rosenweg/assets/logo/rosenweg-rechner …

<ordner>/<name> zeigt auf die SVGs des Baukastens ohne Endung. Gezeigt wird das
adaptive icon (Rosenweg-Rot + Vordergrund, mit der Maske des Startbildschirms
zugeschnitten) auf hellem und dunklem Hintergrund, dazu die Designsymbole von
Android 13+ (monochrom, eingefaerbt) hell und dunkel. Die Beschriftung ist der
<title> des Logos. Raster und Groesse wie auf dem A15 (1080 px breit, 5 Spalten).
Benoetigt: rsvg-convert.
"""
import argparse
import base64
import html
import os
import re
import subprocess
import tempfile

SPALTEN, ZELLE, ICON, ZEILE = 5, 216, 144, 300
LAGE = 72 / 108          # sichtbarer Teil der 108-dp-Ebenen
ROT = "#D32F2F"
FELDER = [
    # titel, hintergrund, schrift, art, (designsymbol-grund, designsymbol-farbe)
    ("Hell", "#EEF0F4", "#1B1C22", "farbig", None),
    ("Dunkel", "#1B1C22", "#FFFFFF", "farbig", None),
    ("Designsymbole hell", "#EEF0F4", "#1B1C22", "mono", ("#FFDAD6", "#8C1D18")),
    ("Designsymbole dunkel", "#1B1C22", "#FFFFFF", "mono", ("#3B2B2A", "#FFB4AB")),
]


def png(svg, px, tmp):
    aus = os.path.join(tmp, f"{os.path.basename(svg)}-{px}.png")
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg, "-o", aus], check=True)
    with open(aus, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def stufe(basis, px):
    if px <= 40 and os.path.exists(basis + "-winzig.svg"):
        return basis + "-winzig.svg"
    if px <= 108 and os.path.exists(basis + "-klein.svg"):
        return basis + "-klein.svg"
    return basis + ".svg"


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--aus", required=True)
    a.add_argument("logos", nargs="+")
    o = a.parse_args()

    zeilen = (len(o.logos) + SPALTEN - 1) // SPALTEN
    fb, fh = SPALTEN * ZELLE, 90 + zeilen * ZEILE + 20
    ebene = round(ICON / LAGE)                       # 108 dp in Pixeln
    teile, defs = [], []
    with tempfile.TemporaryDirectory() as tmp:
        bilder = []
        for i, basis in enumerate(o.logos):
            basis = os.path.splitext(basis)[0] if basis.endswith(".svg") else basis
            with open(basis + ".svg") as f:
                titel = html.unescape(re.search(r"<title>(.*?)</title>", f.read(), re.S).group(1))
            # Detailstufe nach sichtbarer Groesse, wie erzeugen.sh
            vg = png(stufe(basis + "-vordergrund", ebene), ebene, tmp)
            mo = png(stufe(basis + "-monochrom", ebene), ebene, tmp)
            bilder.append((titel, vg, mo))
        # Maske des Startbildschirms (One UI: Squircle, hier als stark gerundetes Quadrat)
        defs.append(f'<clipPath id="form"><rect x="0" y="0" width="{ICON}" height="{ICON}" rx="{ICON * 0.3:.0f}"/></clipPath>')
        for j, (titel, vg, mo) in enumerate(bilder):
            defs.append(f'<mask id="m{j}" maskUnits="userSpaceOnUse" x="0" y="0" width="{ICON}" height="{ICON}">'
                        f'<image x="{(ICON - ebene) / 2:.1f}" y="{(ICON - ebene) / 2:.1f}" width="{ebene}" height="{ebene}" href="{mo}"/></mask>')
        for k, (name, grund, schrift, art, design) in enumerate(FELDER):
            ox, oy = (k % 2) * (fb + 24), (k // 2) * (fh + 24)
            teile.append(f'<g transform="translate({ox} {oy})"><rect width="{fb}" height="{fh}" rx="28" fill="{grund}"/>'
                         f'<text x="36" y="58" font-size="34" font-weight="600" fill="{schrift}">{name}</text>')
            for j, (titel, vg, mo) in enumerate(bilder):
                x = (j % SPALTEN) * ZELLE + (ZELLE - ICON) / 2
                y = 90 + (j // SPALTEN) * ZEILE
                d = (ICON - ebene) / 2
                if art == "farbig":
                    inhalt = (f'<rect width="{ICON}" height="{ICON}" fill="{ROT}"/>'
                              f'<image x="{d:.1f}" y="{d:.1f}" width="{ebene}" height="{ebene}" href="{vg}"/>')
                else:
                    inhalt = (f'<rect width="{ICON}" height="{ICON}" fill="{design[0]}"/>'
                              f'<rect width="{ICON}" height="{ICON}" fill="{design[1]}" mask="url(#m{j})"/>')
                teile.append(f'<g transform="translate({x:.1f} {y})"><g clip-path="url(#form)">{inhalt}</g></g>')
                worte = titel.split(" ", 1)
                for n, w in enumerate(worte):
                    teile.append(f'<text x="{(j % SPALTEN) * ZELLE + ZELLE / 2}" y="{y + ICON + 40 + n * 36}" font-size="30" '
                                 f'text-anchor="middle" fill="{schrift}">{html.escape(w)}</text>')
            teile.append("</g>")
    b, h = 2 * fb + 24, 2 * fh + 24
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{b}" height="{h}" viewBox="0 0 {b} {h}" '
           f'font-family="Roboto, Helvetica Neue, Arial, sans-serif"><rect width="{b}" height="{h}" fill="#FFFFFF"/>'
           f'<defs>{"".join(defs)}</defs>{"".join(teile)}</svg>')
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        quelle = f.name
    try:
        subprocess.run(["rsvg-convert", quelle, "-o", o.aus], check=True)
    finally:
        os.unlink(quelle)
    print(o.aus)


if __name__ == "__main__":
    main()
