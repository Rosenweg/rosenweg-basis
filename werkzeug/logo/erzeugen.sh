#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/logo/erzeugen.sh — App-Logo aus dem Baukasten, samt Plattform-Icons
# ============================================================================
#   werkzeug/logo/erzeugen.sh <app-wurzel> <name> "<Titel>" [zeichen.svg]
#   werkzeug/logo/erzeugen.sh ../rosenweg-profil rosenweg-profil "Rosenweg Profil" \
#       werkzeug/logo/zeichen/person.svg
#
# Schreibt in die App:
#   assets/logo/<name>*.svg               Quellen (baukasten.py), drei Detailstufen
#   assets/logo/<name>-512.png            fuer die App (Anmeldeschirm, Ueber) und Linux
#   android/app/src/main/res/mipmap-*/    ic_launcher, _foreground, _monochrome
#   android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
#   android/app/src/main/res/values/rosenweg_icon.xml
#
# Umgebung:
#   ANDROID_RES=<pfad>   anderer res-Ordner (Kotlin-Apps: app/src/main/res)
#   FOSSIFY_FARBEN=1     Fossify-Apps: die 18 waehlbaren Icon-Farben
#                        (R.mipmap.ic_launcher_red …, Aktivitaets-Aliase)
#                        zeigen alle auf das eine Rosenweg-Icon
#   ALLE=1, GROESSEN=1   siehe unten
#   GRUPPE=<gruppe>      Farbe des Zeichens (bewohner, verwaltung, technik; baukasten.py)
# Flutter-Apps mit allen Plattformen: app-symbole.sh (ruft dieses Skript auf).
# Die Linux-Symbole (hicolor 16…512) rechnet das Paket selbst aus den SVGs
# (linux/paket/bauen.sh) nach derselben Regel (logo_quelle unten).
#
# Detailstufe nach Pixelgroesse: bis 40 px -winzig (Turm + Rose, ohne Weg),
# bis 108 px -klein, darueber die volle Fassung.
# Benoetigt: python3, rsvg-convert (librsvg), awk.
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 3 ] || { sed -n '4,7p' "$0"; exit 2; }
APP="$(cd "$1" && pwd)"; NAME="$2"; TITEL="$3"; ZEICHEN="${4:-}"

L="$APP/assets/logo"
mkdir -p "$L"
if [ -n "$ZEICHEN" ]; then
  python3 "$HIER/baukasten.py" --name "$NAME" --titel "$TITEL" --zeichen "$ZEICHEN" --ziel "$L" ${ALLE:+--alle} \
    ${GRUPPE:+--gruppe "$GRUPPE"} >/dev/null
else
  python3 "$HIER/baukasten.py" --name "$NAME" --titel "$TITEL" --ziel "$L" ${ALLE:+--alle} >/dev/null
fi

# r <quelle ohne .svg> <groesse> <ziel>
r() {
  q="$1.svg"
  if [ "$2" -le 40 ]; then q="$1-winzig.svg"; elif [ "$2" -le 108 ]; then q="$1-klein.svg"; fi
  rsvg-convert -w "$2" -h "$2" "$q" -o "$3"
}

r "$L/$NAME" 512 "$L/$NAME-512.png"

A="${ANDROID_RES:-$APP/android/app/src/main/res}"
case "$A" in /*) ;; *) A="$APP/$A" ;; esac
if [ -n "${ANDROID_RES:-}" ] || [ -d "$APP/android/app" ]; then
  for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
    n=${d%%:*}; f=${d##*:}
    mkdir -p "$A/mipmap-$n"
    r "$L/$NAME" "$(awk "BEGIN{print int(48*$f)}")" "$A/mipmap-$n/ic_launcher.png"
    # Vordergrund: sichtbar sind nur ~2/3 der 108 dp; Stufe nach sichtbarer Groesse.
    r "$L/$NAME-vordergrund" "$(awk "BEGIN{print int(108*$f)}")" "$A/mipmap-$n/ic_launcher_foreground.png"
    r "$L/$NAME-monochrom" "$(awk "BEGIN{print int(108*$f)}")" "$A/mipmap-$n/ic_launcher_monochrome.png"
  done
  mkdir -p "$A/mipmap-anydpi-v26" "$A/values"
  cat > "$A/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- Erzeugt von rosenweg-basis werkzeug/logo/erzeugen.sh -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/rosenweg_icon_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
EOF
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<!-- Erzeugt von rosenweg-basis werkzeug/logo/erzeugen.sh -->'
    echo '<resources>'
    echo '    <color name="rosenweg_icon_background">#D32F2F</color>'
    if [ -n "${FOSSIFY_FARBEN:-}" ]; then
      echo '    <!-- Fossify: waehlbare Icon-Farben; alle zeigen auf das Rosenweg-Icon -->'
      for c in red pink purple deep_purple indigo blue light_blue cyan teal light_green lime \
               yellow amber orange deep_orange brown blue_grey grey_black; do
        echo "    <item name=\"ic_launcher_$c\" type=\"mipmap\">@mipmap/ic_launcher</item>"
      done
    fi
    echo '</resources>'
  } > "$A/values/rosenweg_icon.xml"
fi

# Alle ueblichen Groessen als PNG (fuer Ablage/Vorschau): GROESSEN=1 erzeugen.sh …
if [ -n "${GROESSEN:-}" ]; then
  mkdir -p "$L/png"
  for s in 16 22 24 32 48 64 96 128 256 512 1024; do r "$L/$NAME" $s "$L/png/$NAME-$s.png"; done
fi
echo "Logo $NAME: $L"
