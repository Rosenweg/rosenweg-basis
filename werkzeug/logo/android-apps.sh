#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/logo/android-apps.sh — Logo einer Rosenweg-Android-App nach Tabelle
# ============================================================================
#   werkzeug/logo/android-apps.sh <app-wurzel> <repo>
#   werkzeug/logo/android-apps.sh ../calculator-rosenweg calculator-rosenweg
#
# Liest Name, Titel, Zeichen, Art und Gruppe aus android-apps.txt und ruft erzeugen.sh
# mit dem passenden res-Ordner auf. Jede App hat dafuer assets/logo/erzeugen.sh,
# das nur dieses Skript aufruft; Zeichen und Zeichnung bleiben hier in der Basis.
# Fastlane-Symbol (fastlane/metadata/android/*/images/icon.png) wird mit ersetzt.
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 2 ] || { sed -n '6,7p' "$0"; exit 2; }
APP="$(cd "$1" && pwd)"; REPO="$2"
ZEILE="$(grep "^$REPO|" "$HIER/android-apps.txt")" || { echo "$REPO fehlt in android-apps.txt" >&2; exit 1; }
NAME="$(echo "$ZEILE" | cut -d'|' -f2)"
TITEL="$(echo "$ZEILE" | cut -d'|' -f3)"
ZEICHEN="$HIER/zeichen/$(echo "$ZEILE" | cut -d'|' -f4).svg"
ART="$(echo "$ZEILE" | cut -d'|' -f5)"
GRUPPE="$(echo "$ZEILE" | cut -d'|' -f6)"; GRUPPE="${GRUPPE:-bewohner}"; export GRUPPE
case "$ART" in
  fossify) ANDROID_RES=app/src/main/res FOSSIFY_FARBEN=1 sh "$HIER/erzeugen.sh" "$APP" "$NAME" "$TITEL" "$ZEICHEN" ;;
  kotlin)  ANDROID_RES=app/src/main/res sh "$HIER/erzeugen.sh" "$APP" "$NAME" "$TITEL" "$ZEICHEN" ;;
  flutter) sh "$HIER/erzeugen.sh" "$APP" "$NAME" "$TITEL" "$ZEICHEN" ;;
  *) echo "unbekannte Art: $ART" >&2; exit 1 ;;
esac
for f in "$APP"/fastlane/metadata/android/*/images/icon.png; do
  [ -f "$f" ] && cp "$APP/assets/logo/$NAME-512.png" "$f"
done
exit 0
