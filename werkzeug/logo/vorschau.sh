#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Vorschau-Tafel: jedes Logo in 16/32/48/128/512 px, auf hellem und dunklem Grund.
#   werkzeug/logo/vorschau.sh <ausgabe.png> <ordner>/<name> [<ordner>/<name> …]
# <ordner>/<name> zeigt auf die SVGs ohne Endung, z. B. ../rosenweg-profil/assets/logo/rosenweg-profil
# Benoetigt: rsvg-convert, magick (ImageMagick 7).
set -eu
AUS="$1"; shift
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
r() { q="$1.svg"; if [ "$2" -le 40 ]; then q="$1-winzig.svg"; elif [ "$2" -le 108 ]; then q="$1-klein.svg"; fi
      rsvg-convert -w "$2" -h "$2" "$q" -o "$3"; }
zeilen=""
i=0
for basis in "$@"; do
  for grund in '#F4F4F4' '#202124'; do
    i=$((i+1)); teile=""
    for s in 16 32 48 128 512; do r "$basis" $s "$T/$i-$s.png"; teile="$teile $T/$i-$s.png"; done
    # shellcheck disable=SC2086
    magick -background "$grund" $teile -gravity west -splice 24x0 +append -gravity center -extent "%[fx:w+24]x560" "$T/z$i.png"
    zeilen="$zeilen $T/z$i.png"
  done
done
# shellcheck disable=SC2086
magick $zeilen -background '#F4F4F4' -append "$AUS"
echo "$AUS"
