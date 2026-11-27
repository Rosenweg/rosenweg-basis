#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/logo/app-symbole.sh — alle Symbole einer Flutter-App (5 Plattformen)
# ============================================================================
#   werkzeug/logo/app-symbole.sh <app-wurzel> <name> "<Titel>" <zeichen.svg> [gruppe]
#   werkzeug/logo/app-symbole.sh ../rosenweg-telefonbuch rosenweg-telefonbuch \
#       "Rosenweg Telefonbuch" werkzeug/logo/zeichen/telefonbuch.svg bewohner
#
# Stil A2 wie rosenweg-vm: Turm, Weg (wo lesbar) und Rose, rechts unten das
# Zeichen der App; Farbe des Grundes nach Zielgruppe (bewohner = rot,
# verwaltung = blau, technik = gruen; baukasten.py --gruppe).
#
# Schreibt in die App (fehlt ein Plattform-Ordner, wird er uebersprungen):
#   assets/logo/<name>*.svg                      Quellen, drei Detailstufen (+ -macos, -vollflaeche)
#   assets/logo/<name>-512.png                   Anmeldeschirm, "Ueber", Linux-Fenster
#   assets/logo/<name>-klein.png                 Titelleiste (96 px)
#   assets/logo/<name>-192.png                   /apps (www: img/apps/<name>.png)
#   assets/logo/<name>.icns                      macOS (auch ohne Xcode: icns.py)
#   android/app/src/main/res/mipmap-*            Android, adaptive + monochrom (erzeugen.sh)
#   ios/Runner/Assets.xcassets/AppIcon.appiconset    iOS (vollflaechig, ohne Alpha)
#   macos/Runner/Assets.xcassets/AppIcon.appiconset  macOS (Apple-Raster mit Schatten)
#   windows/runner/resources/app_icon.ico        Windows (16…256 px)
#   macos/installer/hintergrund.svg/.png/@2x.png DMG-Fenster mit Logo und Titel
# Linux: die hicolor-Symbole (16…512 px) und das SVG rechnet das .deb beim
# Bau aus denselben SVGs (linux/paket/bauen.sh, gleiche Stufenregel).
#
# Detailstufe nach Pixelgroesse: bis 40 px -winzig, bis 108 px -klein, sonst voll.
# Benoetigt: python3, rsvg-convert (librsvg >= 2.52), magick (ImageMagick 7).
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 4 ] || { sed -n '4,7p' "$0"; exit 2; }
APP="$(cd "$1" && pwd)"; NAME="$2"; TITEL="$3"; ZEICHEN="$4"; GRUPPE="${5:-bewohner}"
for w in python3 rsvg-convert magick; do
  command -v "$w" >/dev/null || { echo "FEHLER: $w fehlt" >&2; exit 1; }
done

ALLE=1 GRUPPE="$GRUPPE" sh "$HIER/erzeugen.sh" "$APP" "$NAME" "$TITEL" "$ZEICHEN" >/dev/null
L="$APP/assets/logo"
GRUND="$(python3 "$HIER/baukasten.py" --grundfarbe "$GRUPPE")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
stufe() { # stufe <quelle ohne .svg> <groesse> -> SVG der passenden Detailstufe
  if [ "$2" -le 40 ]; then echo "$1-winzig.svg"; elif [ "$2" -le 108 ]; then echo "$1-klein.svg"; else echo "$1.svg"; fi
}
r() { rsvg-convert -w "$2" -h "$2" "$(stufe "$1" "$2")" -o "$3"; }

r "$L/$NAME" 96 "$L/$NAME-klein.png"
r "$L/$NAME" 192 "$L/$NAME-192.png"

# iOS: vollflaechig ohne Alpha (iOS rundet selbst), Hintergrund in der Gruppenfarbe
I="$APP/ios/Runner/Assets.xcassets/AppIcon.appiconset"
if [ -d "$I" ]; then
  ios() { r "$L/$NAME-vollflaeche" "$2" "$T/i.png"
          magick "$T/i.png" -background "$GRUND" -alpha remove -alpha off "$I/$1"; }
  ios Icon-App-20x20@1x.png 20;  ios Icon-App-20x20@2x.png 40;  ios Icon-App-20x20@3x.png 60
  ios Icon-App-29x29@1x.png 29;  ios Icon-App-29x29@2x.png 58;  ios Icon-App-29x29@3x.png 87
  ios Icon-App-40x40@1x.png 40;  ios Icon-App-40x40@2x.png 80;  ios Icon-App-40x40@3x.png 120
  ios Icon-App-60x60@2x.png 120; ios Icon-App-60x60@3x.png 180
  ios Icon-App-76x76@1x.png 76;  ios Icon-App-76x76@2x.png 152
  ios Icon-App-83.5x83.5@2x.png 167; ios Icon-App-1024x1024@1x.png 1024
fi

# macOS: Form nach Apple-Raster (824er Feld auf 1024, -macos.svg) plus Schlagschatten
# wie in Apples Vorlage (Muster rosenweg-vm/-salz assets/logo/desktop-symbole.sh).
mac() {
  q=$(stufe "$L/$NAME-macos" "$1")
  sed -e 's|<g transform="translate(512 512) scale(0.805)|<defs><filter id="rw-schatten" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="10" flood-color="#000" flood-opacity="0.3"/></filter></defs><g filter="url(#rw-schatten)"><g transform="translate(512 512) scale(0.805)|' \
      -e 's|</svg>|</g></svg>|' "$q" > "$T/mac.svg"
  rsvg-convert -w "$1" -h "$1" "$T/mac.svg" -o "$2"
}
for s in 16 32 64 128 256 512 1024; do mac $s "$T/mac_$s.png"; done
python3 "$HIER/icns.py" "$L/$NAME.icns" "$T"/mac_16.png "$T"/mac_32.png "$T"/mac_64.png \
  "$T"/mac_128.png "$T"/mac_256.png "$T"/mac_512.png "$T"/mac_1024.png
M="$APP/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if [ -d "$M" ]; then
  for s in 16 32 64 128 256 512 1024; do cp "$T/mac_$s.png" "$M/app_icon_$s.png"; done
fi

# Windows: .ico mit allen ueblichen Groessen
W="$APP/windows/runner/resources"
if [ -d "$W" ]; then
  for s in 16 24 32 48 64 128 256; do r "$L/$NAME" $s "$T/w$s.png"; done
  magick "$T/w16.png" "$T/w24.png" "$T/w32.png" "$T/w48.png" "$T/w64.png" "$T/w128.png" "$T/w256.png" "$W/app_icon.ico"
fi

# DMG-Hintergrund: Logo (-klein) und Titel in die Vorlage
D="$APP/macos/installer"
if [ -d "$D" ]; then
  python3 - "$HIER/dmg-hintergrund.svg" "$L/$NAME-klein.svg" "$TITEL" "$D/hintergrund.svg" <<'PY'
import re, sys
vorlage, logo, titel, ziel = sys.argv[1:]
s = open(vorlage, encoding="utf-8").read()
l = open(logo, encoding="utf-8").read()
inhalt = re.search(r"<svg[^>]*>(.*)</svg>", l, re.S).group(1)
inhalt = re.sub(r"<title>.*?</title>", "", inhalt, flags=re.S).strip()
titel = titel.replace("&", "&amp;").replace("<", "&lt;")
s = s.replace("{{LOGO}}", inhalt).replace("{{TITEL}}", titel)
open(ziel, "w", encoding="utf-8").write(s)
PY
  rsvg-convert -w 640 -h 420 "$D/hintergrund.svg" -o "$D/hintergrund.png"
  rsvg-convert -w 1280 -h 840 "$D/hintergrund.svg" -o "$D/hintergrund@2x.png"
fi
echo "Symbole $NAME ($GRUPPE): $L"
