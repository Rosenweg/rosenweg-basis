#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# werkzeug/web-einrichten.sh — eine bestehende Rosenweg-Flutter-App auf die
# Web-Version unter rosenweg4303.ch/app/<kurzname>/ umstellen (docs/web.md).
#
#   werkzeug/web-einrichten.sh <app-ordner> [--kurz wetter] [--titel "Rosenweg Wetter"]
#
# Legt <app-ordner>/web/ aus vorlage/web an (index.html mit der Anmeldung der
# Website, manifest.json, Icons aus assets/logo/<ordner>-192/512.png) und
# schaltet `web: true` im .github/workflows/app.yml der App ein.
# Idempotent; ueberschreibt eine vorhandene web/index.html nur mit --erneuern.
set -euo pipefail

BASIS="$(cd "$(dirname "$0")/.." && pwd)"
APP=""; KURZ=""; TITEL=""; ERNEUERN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kurz)     KURZ=${2:?--kurz braucht einen Namen}; shift 2 ;;
    --titel)    TITEL=${2:?--titel braucht einen Namen}; shift 2 ;;
    --erneuern) ERNEUERN=1; shift ;;
    -h|--help)  sed -n '2,12p' "$0"; exit 0 ;;
    *)          APP=$1; shift ;;
  esac
done
[ -d "$APP" ] && [ -f "$APP/pubspec.yaml" ] || { echo "App-Ordner mit pubspec.yaml angeben (-h)" >&2; exit 2; }
APP=$(cd "$APP" && pwd)

dart=$(sed -n 's/^name:[[:space:]]*//p' "$APP/pubspec.yaml" | head -1 | tr -d '[:space:]')
ordner=${dart//_/-}                      # rosenweg-wetter
[ -n "$KURZ" ] || KURZ=${ordner#rosenweg-}
if [ -z "$TITEL" ] && [ -f "$APP/apps-eintrag.json" ]; then
  TITEL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$APP/apps-eintrag.json")
fi
[ -n "$TITEL" ] || TITEL="Rosenweg $(printf "%s" "$KURZ" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
[[ "$KURZ" =~ ^[a-z0-9-]+$ ]] || { echo "Kurzname nur a-z, 0-9, -" >&2; exit 2; }

if [ -f "$APP/web/index.html" ] && [ "$ERNEUERN" != 1 ]; then
  echo "web/index.html gibt es schon (--erneuern zum Ueberschreiben)"
else
  mkdir -p "$APP/web/icons"
  for f in index.html manifest.json; do
    sed -e "s/Rosenweg Vorlage/$TITEL/g" "$BASIS/vorlage/web/$f" > "$APP/web/$f"
  done
  for g in 192 512; do
    src="$APP/assets/logo/$ordner-$g.png"
    [ -f "$src" ] || src="$BASIS/vorlage/web/icons/Icon-$g.png"   # Notnagel: Logo der Vorlage
    cp "$src" "$APP/web/icons/Icon-$g.png"
  done
  cp "$APP/web/icons/Icon-192.png" "$APP/web/favicon.png"
  echo "web/ angelegt in $APP"
fi

wf="$APP/.github/workflows/app.yml"
if [ -f "$wf" ] && ! grep -Eq '^[[:space:]]+web:[[:space:]]*true' "$wf"; then
  # direkt hinter die Zeile "paket:" im with:-Block des Aufrufs
  python3 - "$wf" "$KURZ" "$ordner" <<'PY'
import re, sys
p, kurz, ordner = sys.argv[1:4]
s = open(p).read()
m = re.search(r'^(\s+)paket:.*\n', s, re.M)
if not m:
    sys.exit('Keine Zeile "paket:" in ' + p + ' - web: true von Hand eintragen')
ein = m.group(1)
zeile = f"{ein}web: true\n"
if kurz != ordner.removeprefix('rosenweg-'):
    zeile += f"{ein}web_name: {kurz}\n"
open(p, 'w').write(s[:m.end()] + zeile + s[m.end():])
print('app.yml: web: true eingetragen')
PY
fi
echo
echo "Noch von Hand:"
echo "  1. Die App im Browser pruefen:  flutter run -d chrome   (ohne /js/authentik-auth.js: Hinweis statt Anmeldung)"
echo "  2. Dateien und Ordner nur mit kIsWeb-Weiche (docs/web.md, Abschnitt Plattform-Weichen)"
echo "  3. Nach dem Release: scripts/rw-web-ausrollen.sh --app $KURZ  (Website-Repo)"
echo "  4. Menue-Eintrag auf https://rosenweg4303.ch/app/$KURZ/ in js/nav.js; die alte Seite erst nach Stefans OK entfernen"
