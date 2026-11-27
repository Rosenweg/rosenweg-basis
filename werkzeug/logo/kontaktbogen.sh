#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/logo/kontaktbogen.sh — alle Logos der Flutter-Apps nebeneinander
# ============================================================================
#   sh werkzeug/logo/kontaktbogen.sh [ausgabe.png] [--pdf]
#   VORHANDEN=../logos sh werkzeug/logo/kontaktbogen.sh ~/Downloads/rosenweg-logos-kontaktbogen.png --pdf
#
# Liest flutter-apps.txt, baut jedes Logo mit baukasten.py (Zeichen und
# Gruppenfarbe aus der Tabelle) und setzt sie nach Zielgruppe geordnet in ein
# Raster: je Gruppe eine Ueberschrift mit Farbfeld, je App das Logo in 256 px
# (volle Fassung) und daneben in 48 px (-klein, wie im Startmenue) zur Pruefung
# der Lesbarkeit, darunter Name und Gruppe. Zum Schluss ein dunkler Streifen
# wie im Launcher (96 px, -klein). So laesst sich pruefen, ob die Apps
# nebeneinander (auf /apps, im Launcher, im Startmenue der Stationen)
# unterscheidbar bleiben.
#
#   VORHANDEN=<ordner>  liegt dort <repo>.svg, wird dieses Logo statt des
#                       Baukastens genommen (Rosenweg Stationen: docs/logo.svg
#                       aus os-stationen, Repo privat)
#   --pdf               zusaetzlich <ausgabe>.pdf
# Benoetigt: python3, rsvg-convert, magick (ImageMagick 7).
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
AUS="${1:-rosenweg-app-logos.png}"
PDF="${2:-}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SCHRIFT="" FETT=""
for f in /System/Library/Fonts/Supplemental/Arial.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; do
  [ -f "$f" ] && { SCHRIFT="$f"; break; }
done
for f in "/System/Library/Fonts/Supplemental/Arial Bold.ttf" /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf; do
  [ -f "$f" ] && { FETT="$f"; break; }
done
SCHRIFT="${SCHRIFT:-Helvetica}"; FETT="${FETT:-$SCHRIFT}"

SPALTEN=5 ZB=380 ZH=330 RAND=12
BREITE=$((SPALTEN * (ZB + RAND) + RAND))
HELL='#F4F5F7' DUNKEL='#1B1C22' TEXT='#202124' GRAU='#5F6368'

# Logos bauen: $T/<repo>.png (256), -48.png, -96.png
grep -v '^#' "$HIER/flutter-apps.txt" | while IFS='|' read -r repo titel zeichen gruppe _ ziel; do
  [ -n "$repo" ] || continue
  if [ -n "${VORHANDEN:-}" ] && [ -f "$VORHANDEN/$repo.svg" ]; then
    gross="$VORHANDEN/$repo.svg"; klein="$gross"
  else
    python3 "$HIER/baukasten.py" --name "$repo" --titel "$titel" --zeichen "$HIER/zeichen/$zeichen.svg" \
      --gruppe "$gruppe" --ziel "$T/svg" >/dev/null
    gross="$T/svg/$repo.svg"; klein="$T/svg/$repo-klein.svg"
  fi
  rsvg-convert -w 256 -h 256 "$gross" -o "$T/$repo.png"
  rsvg-convert -w 48 -h 48 "$klein" -o "$T/$repo-48.png"
  rsvg-convert -w 96 -h 96 "$klein" -o "$T/$repo-96.png"
  echo "${ziel:-$gruppe}|$repo|$titel|$gruppe" >> "$T/liste"
done

teile=""
n_gesamt=$(wc -l < "$T/liste" | tr -d ' ')
magick -size "${BREITE}x72" "xc:$HELL" -font "$FETT" -pointsize 28 -fill "$TEXT" \
  -annotate +$RAND+46 "Rosenweg-Apps: $n_gesamt Logos nach Zielgruppe" \
  -font "$SCHRIFT" -pointsize 15 -fill "$GRAU" \
  -gravity northeast -annotate +$RAND+30 "Nur der Grund wechselt je Gruppe; Turm, Rose, Weg und Plakette bleiben gleich" \
  "$T/kopf.png"
teile="$T/kopf.png"

for g in bewohner:Alle_Bewohner verwaltung:Ausschuss_/_Hausverwaltung technik:Technik_/_Admin; do
  gr=${g%%:*}; name=$(echo "${g#*:}" | tr _ ' ')
  farbe="$(python3 "$HIER/baukasten.py" --grundfarbe "$gr")"
  grep "^$gr|" "$T/liste" > "$T/l-$gr" || continue
  anzahl=$(wc -l < "$T/l-$gr" | tr -d ' ')
  magick -size "${BREITE}x70" "xc:$HELL" -fill "$farbe" -draw "roundrectangle $RAND,14 $((RAND + 44)),58 8,8" \
    -font "$FETT" -pointsize 24 -fill "$TEXT" -annotate +$((RAND + 60))+46 "$name" \
    -font "$SCHRIFT" -pointsize 17 -fill "$GRAU" -gravity northeast \
    -annotate +$RAND+30 "Grund $farbe  ·  $anzahl Apps" "$T/k-$gr.png"
  zellen=""
  while IFS='|' read -r _ repo titel lgruppe; do
    zusatz=""
    [ "$lgruppe" != "$gr" ] && zusatz=" (Logo von os-stationen)"
    magick -size "${ZB}x${ZH}" xc:white \
      "$T/$repo.png" -geometry +14+12 -compose over -composite \
      "$T/$repo-48.png" -geometry +$((14 + 256 + 34))+116 -composite \
      -font "$SCHRIFT" -pointsize 12 -fill "$GRAU" -annotate +$((14 + 256 + 34 + 4))+182 "48 px" \
      -font "$FETT" -pointsize 18 -fill "$TEXT" -annotate +14+292 "$titel" \
      -font "$SCHRIFT" -pointsize 14 -fill "$GRAU" -annotate +14+316 "$name$zusatz" \
      "$T/z-$repo.png"
    zellen="$zellen $T/z-$repo.png"
  done < "$T/l-$gr"
  # shellcheck disable=SC2086
  magick montage $zellen -tile ${SPALTEN}x -geometry "${ZB}x${ZH}+$((RAND / 2))+$((RAND / 2))" \
    -background "$HELL" "$T/r-$gr.png"
  magick "$T/r-$gr.png" -gravity center -background "$HELL" -extent "${BREITE}x" "$T/r-$gr.png"
  teile="$teile $T/k-$gr.png $T/r-$gr.png"
done

# Dunkler Streifen wie im Launcher: alle Logos in 96 px, nach Gruppe
LZ=140 LSP=$((BREITE / LZ))
launcher=""
for gr in bewohner verwaltung technik; do
  while IFS='|' read -r _ repo titel _; do
    kurz=$(echo "$titel" | sed 's/^Rosenweg //')
    magick -size "${LZ}x150" "xc:$DUNKEL" "$T/$repo-96.png" -geometry +22+10 -composite \
      -font "$SCHRIFT" -pointsize 13 -fill '#FFFFFF' -gravity north -annotate +0+116 "$kurz" "$T/d-$repo.png"
    launcher="$launcher $T/d-$repo.png"
  done < "$T/l-$gr"
done
# shellcheck disable=SC2086
magick montage $launcher -tile ${LSP}x -geometry "${LZ}x150+0+0" -background "$DUNKEL" "$T/launcher.png"
magick "$T/launcher.png" -gravity center -background "$DUNKEL" -extent "${BREITE}x" "$T/launcher.png"
magick -size "${BREITE}x56" "xc:$DUNKEL" -font "$FETT" -pointsize 22 -fill '#FFFFFF' \
  -annotate +$RAND+38 "Launcher, dunkler Hintergrund (96 px)" "$T/dk.png"
magick -size "${BREITE}x20" "xc:$HELL" "$T/luecke.png"
magick -size "${BREITE}x16" "xc:$DUNKEL" "$T/dfuss.png"

# shellcheck disable=SC2086
magick $teile "$T/luecke.png" "$T/dk.png" "$T/launcher.png" "$T/dfuss.png" -append "$T/bogen.png"
magick "$T/bogen.png" +repage -depth 8 "PNG24:$AUS"
[ "$PDF" = --pdf ] && magick "$AUS" -units PixelsPerInch -density 200 "${AUS%.png}.pdf"
echo "$AUS"
