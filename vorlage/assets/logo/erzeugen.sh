#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Logo "Rosenweg Vorlage" aus dem Logo-Baukasten von rosenweg-basis: Wappen
# (Turm, Weg, Rose) und rechts unten die Plakette mit dem Zeichen der App
# (assets/logo/zeichen/vorlage.svg), Farbe des Zeichens nach Zielgruppe.
# Schreibt alle Symbole: Android (adaptive, monochrom), iOS, macOS (+ .icns),
# Windows (.ico), Linux (SVG; die hicolor-PNGs rechnet linux/paket/bauen.sh),
# /apps (assets/logo/rosenweg-vorlage-192.png) und den DMG-Hintergrund.
# Aufruf aus dem Repo-Wurzelverzeichnis:
#   sh assets/logo/erzeugen.sh [pfad/zu/rosenweg-basis]
set -eu
BASIS="${1:-../rosenweg-basis}"
GRUPPE=bewohner
# Weitere Gruppenfarben (RosenwegApp.farbGruppen in lib/app.dart), z. B. "verwaltung technik":
# Logos, Android-Startsymbole (activity-alias) und iOS alternate icons je Farbe
FARBEN=""
FARBEN="$FARBEN" sh "$BASIS/werkzeug/logo/app-symbole.sh" . rosenweg-vorlage "Rosenweg Vorlage" assets/logo/zeichen/vorlage.svg "$GRUPPE"
python3 "$BASIS/werkzeug/logo/farben-einbauen.py" . --standard "$GRUPPE" --farben $FARBEN >/dev/null
