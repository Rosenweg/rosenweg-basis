#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/logo/kontaktbogen.sh — alle Logos der Flutter-Apps nebeneinander
# ============================================================================
#   sh werkzeug/logo/kontaktbogen.sh [ausgabe.png] [--einfarbig]
#   sh werkzeug/logo/kontaktbogen.sh ~/Downloads/rosenweg-app-logos.png
#
# Liest flutter-apps.txt, baut jedes Logo mit baukasten.py (Zeichen und
# Gruppenfarbe aus der Tabelle) und setzt sie in ein Raster: je App gross
# (160 px, volle Fassung), wie im Startmenue (48 px, -klein) und winzig
# (24 px, -winzig), darunter der Name. So laesst sich pruefen, ob die Apps
# nebeneinander (auf /apps, im Launcher, im Startmenue der Stationen)
# unterscheidbar bleiben. --einfarbig: alle Zeichen rot (ohne Gruppenfarbe).
# Benoetigt: python3, rsvg-convert, magick (ImageMagick 7).
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
AUS="${1:-rosenweg-app-logos.png}"
EINFARBIG="${2:-}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SCHRIFT=""
for f in /System/Library/Fonts/Supplemental/Arial.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; do
  [ -f "$f" ] && { SCHRIFT="$f"; break; }
done
i=0
grep -v '^#' "$HIER/flutter-apps.txt" | while IFS='|' read -r repo titel zeichen gruppe kennung; do
  [ -n "$repo" ] || continue
  i=$((i+1)); n=$(printf '%02d' $i)
  [ "$EINFARBIG" = --einfarbig ] && gruppe=bewohner
  python3 "$HIER/baukasten.py" --name "$repo" --titel "$titel" --zeichen "$HIER/zeichen/$zeichen.svg" \
    --gruppe "$gruppe" --ziel "$T/svg" >/dev/null
  rsvg-convert -w 160 -h 160 "$T/svg/$repo.svg" -o "$T/g.png"
  rsvg-convert -w 48 -h 48 "$T/svg/$repo-klein.svg" -o "$T/m.png"
  rsvg-convert -w 24 -h 24 "$T/svg/$repo-winzig.svg" -o "$T/k.png"
  magick -background none "$T/m.png" "$T/k.png" -gravity center -append "$T/mk.png"
  # shellcheck disable=SC2086
  magick -background '#FFFFFF' "$T/g.png" "$T/mk.png" -gravity center +append -extent 290x170 \
    ${SCHRIFT:+-font "$SCHRIFT"} -pointsize 15 -fill '#202124' -gravity south \
    -splice 0x30 -annotate +0+6 "$titel" "$T/z$n.png"
done
# shellcheck disable=SC2046
magick montage $(ls "$T"/z*.png | sort) -tile 6x -geometry 290x200+6+6 -background '#ECEFF1' "$T/raster.png"
# shellcheck disable=SC2086
magick "$T/raster.png" -background '#ECEFF1' ${SCHRIFT:+-font "$SCHRIFT"} -pointsize 20 -fill '#202124' -gravity north \
  -splice 0x56 -annotate +0+16 "Rosenweg-Apps: $(grep -vc '^#' "$HIER/flutter-apps.txt") Logos (Zeichen rot = Bewohner, blau = Verwaltung, grün = Technik)" "$AUS"
echo "$AUS"
