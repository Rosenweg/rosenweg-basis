#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Logo-Baukasten der Rosenweg-Apps.

Jedes App-Logo zeigt das Rosenweg-Wappen in vereinfachter Form — Turm, Weg und
Rose auf Rosenweg-Rot (Vorbild: logo-rosenweg.png im Website-Repo) — und
rechts unten ein eigenes Zeichen der App in einem weissen Kreis (Plakette).
Der Turm allein reicht nicht: der ist leicht mit dem Wappen von Kaiseraugst
zu verwechseln (Stefan, 26.11.2026). Mindestens Turm und Rose sind immer da;
der Weg, wo er in der Groesse noch lesbar ist.

    werkzeug/logo/baukasten.py --name rosenweg-profil --titel "Rosenweg Profil" \\
        --zeichen werkzeug/logo/zeichen/person.svg --ziel assets/logo [--alle]

Drei Detailstufen (gewaehlt von erzeugen.sh nach Pixelgroesse):
    <name>.svg          ab 109 px: Turm mit Mauerfugen, Rose mit Blaettern, Weg
    <name>-klein.svg    41–108 px: Turm ohne Fugen, kraeftige Rose, Weg breit
    <name>-winzig.svg   bis 40 px: nur Turm und Rose, gross; Weg entfaellt

Je Stufe ausserdem:
    -vordergrund        Android adaptive icon, Vordergrund (rundes Wappen in der Sicherheitszone)
    -monochrom          Android 13+ Designsymbole, eine Farbe
mit --alle zusaetzlich (wie rosenweg-vm assets/logo):
    -macos              mit Rand nach macOS-Raster
    -vollflaeche        quadratisch ohne Rundung (iOS rundet selbst)

Ohne --zeichen: nur das Wappen, ohne Plakette (Logo der Basis selbst).

Das Zeichen ist ein SVG mit viewBox="0 0 400 400" und Formen OHNE eigene Farbe
(fill setzt der Baukasten; fill-rule bleibt). Kraeftige Formen, keine Haarlinien.

Die Turm-Pfade (turm.pfad, turm-klein.pfad) stammen aus rosenweg-vm
assets/logo (A2, Turm aus dem Original-Wappen).
"""
import argparse
import math
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))

FARBEN = dict(
    grund="#D32F2F",      # Hintergrund (Logo-Rot)
    huegel="#9E1B1B",     # dunklerer Huegel unter Turm und Weg
    rand="#3E0B0B",       # Umrisse (Weg, Rose, Blaetter)
    turm="#FFFFFF",
    weg="#FFFFFF",
    rose="#F25A5A",       # heller als der Grund, damit sie sich abhebt
    stiel="#2E7D32",
    blatt="#43A047",
    plakette="#FFFFFF",
    zeichen="#D32F2F",
)

# Monochrom: alles, was sichtbar sein soll, weiss; Umrisse und Grund schwarz.
# Das Ganze wird als Maske benutzt (Luminanz = Deckkraft).
MASKE = dict(grund="#000", huegel="#000", rand="#000", turm="#fff", weg="#fff", rose="#fff",
             stiel="#fff", blatt="#fff", plakette="#fff", zeichen="#000")

TURM_X0, TURM_Y0, TURM_B, TURM_H = 18, 17, 242, 342

# Je Stufe: Lage des Turms, Rose, Weg, Linienstaerken. Koordinaten im 1024er-Feld.
STUFEN = {
    "": dict(turm="turm.pfad", tk=1.45, tx=120, ty=170, rose=(735, 330, 118), rand=14,
             weg=True, wegb=78, blatt=(70, 34), stielb=22, kelch=True, fugen=True),
    "-klein": dict(turm="turm-klein.pfad", tk=1.5, tx=105, ty=150, rose=(740, 330, 140), rand=22,
                   weg=True, wegb=104, blatt=(82, 42), stielb=34, kelch=False, fugen=False),
    "-winzig": dict(turm="turm-klein.pfad", tk=1.95, tx=60, ty=150, rose=(760, 360, 185), rand=30,
                    weg=False, wegb=0, blatt=(100, 54), stielb=48, kelch=False, fugen=False),
}

# Mit Plakette wird das Wappen etwas kleiner nach links oben geschoben.
MIT_PLAKETTE = "translate(24 14) scale(0.83)"
PLAKETTE = dict(x=772, y=782, r=190, spalt=24, zeichen=270)
PLAKETTE_WINZIG = dict(x=790, y=800, r=200, spalt=28, zeichen=300)


def pfad(name):
    with open(os.path.join(HIER, name)) as f:
        return f.read().strip()


def zeichen_lesen(datei):
    with open(datei) as f:
        s = f.read()
    m = re.search(r"<svg[^>]*>(.*)</svg>", s, re.S)
    if not m:
        sys.exit(f"{datei}: kein <svg>…</svg>")
    if 'viewBox="0 0 400 400"' not in s:
        sys.exit(f'{datei}: braucht viewBox="0 0 400 400"')
    inhalt = re.sub(r"<title>.*?</title>", "", m.group(1), flags=re.S)
    inhalt = re.sub(r'\s(fill|stroke)="[^"]*"', "", inhalt)
    return inhalt.strip()


def rosenkopf(cx, cy, r, n=6, tiefe=0.10):
    """Bluetenumriss: Kreis mit n Wellen."""
    pkte = []
    for i in range(73):
        t = 2 * math.pi * i / 72
        rr = r * (1 + tiefe * math.cos(n * t))
        pkte.append(f"{cx + rr * math.cos(t):.1f} {cy + rr * math.sin(t):.1f}")
    return "M" + " L".join(pkte) + "Z"


def wappen(st, f):
    """Turm, Weg, Rose (ohne Hintergrund). f = Farbtabelle."""
    t = []
    k, tx, ty = st["tk"], st["tx"], st["ty"]
    ox, oy = tx - TURM_X0 * k, ty - TURM_Y0 * k
    tor_x = ox + 143.5 * k
    fuss = oy + 359 * k
    # Huegel und Weg; reichen ueber den Rand hinaus, abgeschnitten wird aussen
    t.append(f'<path fill="{f["huegel"]}" d="M-300 {fuss - 20:.0f} L-20 {fuss - 40:.0f} C 200 {fuss - 110:.0f} 430 {fuss - 90:.0f} 620 {fuss - 20:.0f} '
             f'C 800 {fuss + 40:.0f} 920 {fuss:.0f} 1044 {fuss - 50:.0f} L1400 {fuss - 80:.0f} V1400 H-300 Z"/>')
    if st["weg"]:
        w = (f'M{tor_x:.0f} {fuss - 10:.0f} C {tor_x + 30:.0f} {fuss + 90:.0f} {tor_x + 250:.0f} {fuss + 60:.0f} '
             f'{tor_x + 260:.0f} {fuss + 150:.0f} C {tor_x + 270:.0f} {fuss + 240:.0f} {tor_x + 60:.0f} {fuss + 270:.0f} '
             f'{tor_x + 40:.0f} 1060 L{tor_x + 30:.0f} 1400')
        b = st["wegb"]
        t.append(f'<path d="{w}" fill="none" stroke="{f["rand"]}" stroke-width="{b + 2 * st["rand"] * 0.8:.0f}"/>')
        t.append(f'<path d="{w}" fill="none" stroke="{f["weg"]}" stroke-width="{b}"/>')
    # Turm
    t.append(f'<g transform="translate({ox:.1f} {oy:.1f}) scale({k})"><path fill="{f["turm"]}" '
             f'fill-rule="evenodd" d="{pfad(st["turm"])}"/></g>')
    # Rose: Stiel, Blaetter, Bluete
    cx, cy, r = st["rose"]
    sb, rand = st["stielb"], st["rand"]
    stiel_unten = (cx - 50, min(cy + r + 300, 1000))
    t.append(f'<path d="M{cx} {cy + r * 0.8:.0f} C {cx + 10} {cy + r + 120:.0f} {cx - 40} {cy + r + 170:.0f} '
             f'{stiel_unten[0]} {stiel_unten[1]:.0f}" fill="none" stroke="{f["rand"]}" stroke-width="{sb + rand * 0.8:.0f}" stroke-linecap="round"/>')
    t.append(f'<path d="M{cx} {cy + r * 0.8:.0f} C {cx + 10} {cy + r + 120:.0f} {cx - 40} {cy + r + 170:.0f} '
             f'{stiel_unten[0]} {stiel_unten[1]:.0f}" fill="none" stroke="{f["stiel"]}" stroke-width="{sb}" stroke-linecap="round"/>')
    bx, by = st["blatt"]
    for (lx, ly, w) in ((cx - 95, cy + r + 110, -28), (cx + 70, cy + r + 150, 24)):
        t.append(f'<ellipse cx="{lx:.0f}" cy="{ly:.0f}" rx="{bx}" ry="{by}" transform="rotate({w} {lx:.0f} {ly:.0f})" '
                 f'fill="{f["blatt"]}" stroke="{f["rand"]}" stroke-width="{rand * 0.7:.0f}"/>')
    t.append(f'<path d="{rosenkopf(cx, cy, r)}" fill="{f["rose"]}" stroke="{f["rand"]}" stroke-width="{rand}" stroke-linejoin="round"/>')
    # Innere Blaetter als Bogen/Spirale
    if st["kelch"]:
        for rr, a0, a1 in ((0.68, 200, 470), (0.42, 20, 300), (0.18, 150, 420)):
            t.append(bogen(cx, cy, r * rr, a0, a1, f["rand"], rand * 0.85))
    else:
        t.append(bogen(cx, cy, r * 0.5, 160, 430, f["rand"], rand))
    return t


def bogen(cx, cy, r, a0, a1, farbe, breite):
    p0 = (cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
    p1 = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    gross = 1 if (a1 - a0) % 360 > 180 else 0
    return (f'<path d="M{p0[0]:.1f} {p0[1]:.1f} A{r:.1f} {r:.1f} 0 {gross} 1 {p1[0]:.1f} {p1[1]:.1f}" '
            f'fill="none" stroke="{farbe}" stroke-width="{breite:.0f}" stroke-linecap="round"/>')


def plakette(p, zeichen, f):
    s = p["zeichen"] / 400
    x, y = p["x"] - p["zeichen"] / 2, p["y"] - p["zeichen"] / 2
    return [
        f'<circle cx="{p["x"]}" cy="{p["y"]}" r="{p["r"] + p["spalt"]}" fill="{f["grund"]}"/>',
        f'<circle cx="{p["x"]}" cy="{p["y"]}" r="{p["r"]}" fill="{f["plakette"]}"/>',
        f'<g transform="translate({x:.1f} {y:.1f}) scale({s:.4f})" fill="{f["zeichen"]}">{zeichen}</g>',
    ]


def bild(stufe, zeichen, f, form="rund", hintergrund=True):
    """Inhalt (ohne <svg>) eines Logos. form: rund | quadrat | kreis."""
    st = STUFEN[stufe]
    clip = {"rund": '<rect width="1024" height="1024" rx="224"/>',
            "quadrat": '<rect width="1024" height="1024"/>',
            "kreis": '<circle cx="512" cy="512" r="512"/>'}[form]
    teile = [f'<defs><clipPath id="feld">{clip}</clipPath></defs>', '<g clip-path="url(#feld)">']
    if hintergrund:
        teile.append(f'<rect width="1024" height="1024" fill="{f["grund"]}"/>')
    w = wappen(st, f)
    if zeichen is None:
        teile += w
    else:
        teile.append(f'<g transform="{MIT_PLAKETTE}">' + "".join(w) + "</g>")
    teile.append('</g>')
    # Plakette ausserhalb des Zuschnitts: im runden Vordergrund ragt sie sonst angeschnitten heraus.
    if zeichen is not None:
        teile += plakette(PLAKETTE_WINZIG if stufe == "-winzig" else PLAKETTE, zeichen, f)
    return teile


def svg(titel, teile, rahmen=None):
    inhalt = "\n  ".join(teile)
    if rahmen:
        inhalt = f'<g transform="{rahmen}">\n  {inhalt}\n  </g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
            f'  <title>{titel}</title>\n  {inhalt}\n</svg>\n')


ADAPTIV = "translate(512 512) scale(0.64) translate(-512 -512)"
MACOS = "translate(512 512) scale(0.805) translate(-512 -512)"


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--name", required=True)
    a.add_argument("--titel", required=True)
    a.add_argument("--zeichen")
    a.add_argument("--ziel", required=True)
    a.add_argument("--alle", action="store_true", help="auch -macos und -vollflaeche")
    o = a.parse_args()

    z = zeichen_lesen(o.zeichen) if o.zeichen else None
    os.makedirs(o.ziel, exist_ok=True)
    for stufe in STUFEN:
        dateien = {
            f"{o.name}{stufe}.svg": svg(o.titel, bild(stufe, z, FARBEN)),
            # Adaptive icon: Android legt das Rot dahinter und schneidet rund/
            # eckig zu; das Wappen sitzt als Kreis in der Sicherheitszone.
            f"{o.name}-vordergrund{stufe}.svg": svg(f"{o.titel} (Android adaptive icon, Vordergrund)",
                                                   bild(stufe, z, FARBEN, form="kreis", hintergrund=False), ADAPTIV),
            f"{o.name}-monochrom{stufe}.svg": svg(
                f"{o.titel} (Android monochrom)",
                ['<defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
                 '<rect width="1024" height="1024" fill="#000"/>' + "".join(bild(stufe, z, MASKE, form="kreis", hintergrund=False))
                 + '</mask></defs>', '<rect width="1024" height="1024" fill="#FFFFFF" mask="url(#m)"/>'], ADAPTIV),
        }
        if o.alle:
            dateien[f"{o.name}-macos{stufe}.svg"] = svg(f"{o.titel} (macOS)", bild(stufe, z, FARBEN), MACOS)
            dateien[f"{o.name}-vollflaeche{stufe}.svg"] = svg(f"{o.titel} (vollflaechig)", bild(stufe, z, FARBEN, form="quadrat"))
        for n, text in dateien.items():
            with open(os.path.join(o.ziel, n), "w") as f:
                f.write(text)
            print(os.path.join(o.ziel, n))


if __name__ == "__main__":
    main()
