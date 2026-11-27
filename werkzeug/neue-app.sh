#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================================
# werkzeug/neue-app.sh — neue Rosenweg-Flutter-App aus der Vorlage (vorlage/)
# ============================================================================
#   werkzeug/neue-app.sh [optionen] <name> "<Anzeigename>" <zeichen>
#   werkzeug/neue-app.sh telefonbuch "Rosenweg Telefonbuch" telefonbuch
#   werkzeug/neue-app.sh mail-freigabe "Rosenweg Mail-Freigabe" mail-freigabe \
#       --gruppe verwaltung --beschreibung "Mails der Verwaltung prüfen und freigeben."
#
#   <name>          kurz, Kleinbuchstaben/Ziffern/Bindestrich (mit oder ohne
#                   "rosenweg-"): Repo rosenweg-<name>, Dart-Paket rosenweg_<name>,
#                   Kennung ch.rosenweg4303.<name ohne Bindestriche>
#   <Anzeigename>   wie im Startmenue, z. B. "Rosenweg Waschküche"
#   <zeichen>       Fachgebiets-Zeichen: Name aus werkzeug/logo/zeichen/ oder Pfad
#                   zu einem SVG (viewBox 0 0 400 400, siehe docs/logos.md)
#
# Optionen:
#   --ziel <ordner>        wohin (Standard: neben rosenweg-basis, ../rosenweg-<name>)
#   --gruppe <g>           Farbe des Zeichens: bewohner (rot), verwaltung (blau),
#                          technik (gruen); Standard aus werkzeug/logo/flutter-apps.txt,
#                          sonst bewohner
#   --farben "<g> …"       weitere Gruppenfarben, wo die App fuer diese Gruppe etwas
#                          freischaltet (docs/gruppenfarbe.md), z. B. "verwaltung technik";
#                          Standard aus werkzeug/logo/flutter-apps.txt (Spalte 6), sonst keine
#   --beschreibung "<Satz>"  ein Satz fuer "Ueber", .deb, Startmenue, /apps
#   --kennung <k>          statt <name ohne Bindestriche> (ch.rosenweg4303.<k>)
#   --basis-ref <ref>      Stand von rosenweg_basis in pubspec.yaml (Standard: wie vorlage/)
#   --workflow-ref <ref>   Stand der Workflows aus rosenweg-basis (Standard: main)
#   --basis-lokal <pfad>   pubspec_overrides.yaml auf diese Basis (Entwicklung, CI)
#   --ohne-pub             kein 'flutter pub get' (sonst entsteht pubspec.lock)
#   --ohne-git             kein git-Repo, kein erster Commit
#   --repo                 ZUSAETZLICH das GitHub-Repo Rosenweg/rosenweg-<name>
#                          anlegen (privat) und main pushen. Ohne diesen Schalter
#                          passiert nichts auf GitHub.
#
# Danach druckt das Skript, was ausserhalb des Repos noch zu tun ist (Authentik,
# App-Register fuer /apps, Secrets, os-stationen). Ausfuehrlich: README.md,
# Abschnitt "Neue App anlegen".
# Benoetigt: python3, rsvg-convert, magick (ImageMagick 7), tar; flutter fuer pub get.
# ============================================================================
set -eu
HIER="$(cd "$(dirname "$0")" && pwd)"
BASIS="$(cd "$HIER/.." && pwd)"
VORLAGE="$BASIS/vorlage"

hilfe() { sed -n '4,41p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
fehler() { echo "FEHLER: $*" >&2; exit 1; }

ZIEL="" GRUPPE="" FARBEN="-" BESCHREIBUNG="" KENNUNG="" BASIS_REF="" WORKFLOW_REF=main
BASIS_LOKAL="" OHNE_PUB=0 OHNE_GIT=0 REPO=0
set -- "$@" --ende--
ARGS=""
while [ "$1" != --ende-- ]; do
  case "$1" in
    -h|--help) hilfe ;;
    --ziel) ZIEL="$2"; shift 2 ;;
    --gruppe) GRUPPE="$2"; shift 2 ;;
    --farben) FARBEN="$2"; shift 2 ;;
    --beschreibung) BESCHREIBUNG="$2"; shift 2 ;;
    --kennung) KENNUNG="$2"; shift 2 ;;
    --basis-ref) BASIS_REF="$2"; shift 2 ;;
    --workflow-ref) WORKFLOW_REF="$2"; shift 2 ;;
    --basis-lokal) BASIS_LOKAL="$(cd "$2" && pwd)"; shift 2 ;;
    --ohne-pub) OHNE_PUB=1; shift ;;
    --ohne-git) OHNE_GIT=1; shift ;;
    --repo) REPO=1; shift ;;
    -*) fehler "unbekannte Option $1 (--help)" ;;
    *) set -- "$@" "$1"; shift ;;
  esac
done
shift  # --ende--
[ $# -eq 3 ] || hilfe 2
KURZ="${1#rosenweg-}"; TITEL="$2"; ZEICHEN="$3"

printf '%s' "$KURZ" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' \
  || fehler "Name '$KURZ': nur Kleinbuchstaben, Ziffern, einzelne Bindestriche (z. B. mail-freigabe)"
[ "$KURZ" != vorlage ] || fehler "'vorlage' ist der Platzhalter der Vorlage selbst"
[ -n "$TITEL" ] || fehler "Anzeigename fehlt"
REPO_NAME="rosenweg-$KURZ"

# Vorschlaege aus der Logo-Tabelle (Plan 1e)
ZEILE="$(grep -v '^#' "$HIER/logo/flutter-apps.txt" | grep "^$REPO_NAME|" || true)"
if [ -n "$ZEILE" ]; then
  [ -n "$GRUPPE" ] || GRUPPE="$(echo "$ZEILE" | cut -d'|' -f4)"
  [ -n "$KENNUNG" ] || KENNUNG="$(echo "$ZEILE" | cut -d'|' -f5)"
  [ "$FARBEN" != - ] || FARBEN="$(echo "$ZEILE" | cut -d'|' -f6 | tr ',' ' ')"
fi
[ "$FARBEN" != - ] || FARBEN=""
for g in $FARBEN; do
  case "$g" in verwaltung|technik) ;; *) fehler "--farben: verwaltung und/oder technik" ;; esac
done
GRUPPE="${GRUPPE:-bewohner}"
case "$GRUPPE" in bewohner|verwaltung|technik) ;; *) fehler "--gruppe: bewohner, verwaltung oder technik" ;; esac
KENNUNG="${KENNUNG:-$(printf '%s' "$KURZ" | tr -d -)}"
# Kennung = applicationId = Ruecksprung-Schema (ch.rosenweg4303.<k>:/anmeldung):
# keine Bindestriche (Java-Paket), keine Unterstriche (URI-Schema)
printf '%s' "$KENNUNG" | grep -Eq '^[a-z][a-z0-9]*$' || fehler "Kennung '$KENNUNG': nur Kleinbuchstaben und Ziffern"
BESCHREIBUNG="${BESCHREIBUNG:-$TITEL.}"

if [ -f "$ZEICHEN" ]; then ZQ="$(cd "$(dirname "$ZEICHEN")" && pwd)/$(basename "$ZEICHEN")"
elif [ -f "$HIER/logo/zeichen/$ZEICHEN.svg" ]; then ZQ="$HIER/logo/zeichen/$ZEICHEN.svg"
else fehler "Zeichen '$ZEICHEN' nicht gefunden (werkzeug/logo/zeichen/ oder Pfad zu einem SVG)"; fi
grep -q 'viewBox="0 0 400 400"' "$ZQ" || fehler "$ZQ: braucht viewBox=\"0 0 400 400\""
ZNAME="$(basename "$ZQ" .svg)"

ZIEL="${ZIEL:-$(dirname "$BASIS")}"
mkdir -p "$ZIEL"
APP="$(cd "$ZIEL" && pwd)/$REPO_NAME"
[ ! -e "$APP" ] || fehler "$APP gibt es schon"
for w in python3 rsvg-convert magick tar; do command -v "$w" >/dev/null || fehler "$w fehlt"; done
if [ -z "$BASIS_REF" ]; then
  BASIS_REF="$(sed -n '/rosenweg-basis.git/,/ref:/s/^[[:space:]]*ref:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$VORLAGE/pubspec.yaml")"
fi

echo "== $TITEL: $APP"
echo "   Repo $REPO_NAME, Dart rosenweg_$(printf '%s' "$KURZ" | tr - _), Kennung ch.rosenweg4303.$KENNUNG, Zeichen $ZNAME ($GRUPPE${FARBEN:+; Farben $FARBEN})"

# 1. Vorlage kopieren (ohne Bau- und Werkzeugreste)
mkdir -p "$APP"
(cd "$VORLAGE" && tar -cf - --exclude ./.dart_tool --exclude ./build --exclude ./pubspec_overrides.yaml \
   --exclude ./pubspec.lock --exclude ./.flutter-plugins --exclude ./.flutter-plugins-dependencies \
   --exclude ./linux/paket/arbeit --exclude ./linux/paket/out --exclude ./ios/Pods --exclude ./macos/Pods \
   --exclude '*/ephemeral' --exclude ./android/.gradle --exclude ./android/local.properties \
   --exclude ./ios/Flutter/Generated.xcconfig --exclude ./macos/Flutter/ephemeral .) | (cd "$APP" && tar -xf -)

# 2. Namen, Kennung, Texte ersetzen; Dateien umbenennen
python3 - "$APP" "$KURZ" "$KENNUNG" "$TITEL" "$BESCHREIBUNG" "$ZNAME" "$GRUPPE" "$BASIS_REF" "$WORKFLOW_REF" "$FARBEN" <<'PY'
import os, re, sys, uuid
app, kurz, kennung, titel, beschreibung, zname, gruppe, basis_ref, wf_ref, farben = sys.argv[1:]
farben = [f for f in farben.split() if f != gruppe]
repo = f"rosenweg-{kurz}"
dart = "rosenweg_" + kurz.replace("-", "_")
umlaute = {"ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss", "é": "e", "è": "e"}
datei = "".join(umlaute.get(c, c) for c in titel)
datei = re.sub(r"[^A-Za-z0-9]+", "-", datei).strip("-")
VORLAGE_SATZ = "Gerüst für neue Rosenweg-Apps: Anmeldung, Seiten, Updater."
ersetzen = [
    ("ch.rosenweg4303.vorlage", f"ch.rosenweg4303.{kennung}"),
    ("rosenweg-vorlage", repo),
    ("rosenweg_vorlage", dart),
    ("Rosenweg-Vorlage", datei),
    ("Rosenweg Vorlage", titel),
    (VORLAGE_SATZ, beschreibung),
    ("zeichen/vorlage.svg", f"zeichen/{zname}.svg"),
    ("{{0D0C2A6E-7E1B-4B7A-9C1F-5A2E8F3B7C40}", "{{" + str(uuid.uuid4()).upper() + "}"),
]
# 2a. Dateien und Ordner umbenennen (tiefste zuerst)
for wurzel, ordner, dateien in os.walk(app, topdown=False):
    for n in dateien + ordner:
        neu = n.replace("rosenweg-vorlage", repo).replace("ch.rosenweg4303.vorlage", f"ch.rosenweg4303.{kennung}")
        if neu != n:
            os.rename(os.path.join(wurzel, n), os.path.join(wurzel, neu))
k_alt = os.path.join(app, "android/app/src/main/kotlin/ch/rosenweg4303/vorlage")
os.rename(k_alt, os.path.join(os.path.dirname(k_alt), kennung))
# 2b. Inhalte (nur Textdateien)
for wurzel, _, dateien in os.walk(app):
    if ".git" in wurzel.split(os.sep):
        continue
    for n in dateien:
        p = os.path.join(wurzel, n)
        try:
            s = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        t = s
        for a, b in ersetzen:
            t = t.replace(a, b)
        if n == "pubspec.yaml":
            # einziges "ref:" in pubspec.yaml: der Stand von rosenweg_basis
            t = re.sub(r"(\n\s+ref: )\S+", lambda m: m.group(1) + basis_ref, t, count=1)
        if n in ("app.yml", "apps.yml") and "/.github/workflows" in wurzel:
            t = t.replace("/.github/workflows/app.yml@main", f"/.github/workflows/app.yml@{wf_ref}")
            t = t.replace("/.github/workflows/app-apps.yml@main", f"/.github/workflows/app-apps.yml@{wf_ref}")
        if n == "apps-eintrag.json":
            # Schluessel im Register = kurzer Name; Technik-Apps in der Gruppe "Technik" auf /apps
            t = t.replace('"app": "vorlage"', f'"app": "{kurz}"')
            t = t.replace('"technik": false', f'"technik": {"true" if gruppe == "technik" else "false"}')
        if n == "app.dart" and wurzel == os.path.join(app, "lib"):
            # Farbe des Anmeldeschirms = Gruppe des Logos
            t = t.replace("gruppe: RosenwegGruppe.bewohner", f"gruppe: RosenwegGruppe.{gruppe}")
            if farben:
                t = t.replace("farbGruppen: {},", "farbGruppen: {" + ", ".join(f"RosenwegGruppe.{f}" for f in farben) + "},")
        if n == "erzeugen.sh":
            t = t.replace("GRUPPE=bewohner", f"GRUPPE={gruppe}")
            t = t.replace('FARBEN=""', f'FARBEN="{" ".join(farben)}"')
        if n == "pubspec.yaml" and farben and wurzel == app:
            # Logos der weiteren Gruppenfarben (FarbLogo)
            zeilen = "".join(f"    - assets/logo/{repo}-{f}-512.png\n    - assets/logo/{repo}-{f}-klein.png\n" for f in farben)
            t = t.replace(f"    - assets/logo/{repo}-klein.png\n", f"    - assets/logo/{repo}-klein.png\n" + zeilen)
        if n == "main.cpp" and not titel.isascii():
            # MSVC liest die Quelle ohne BOM nicht als UTF-8: Umlaute als \u-Folgen
            esc = "".join(c if c.isascii() else f"\\u{ord(c):04x}" for c in titel)
            t = t.replace(f'L"{titel}"', f'L"{esc}"')
        if t != s or (n.endswith(".iss") and not titel.isascii()):
            # Inno Setup liest UTF-8 nur mit BOM
            bom = "﻿" if n.endswith(".iss") and not titel.isascii() and not t.startswith("﻿") else ""
            open(p, "w", encoding="utf-8").write(bom + t)
PY

# Rest pruefen: kein Platzhalter darf uebrig bleiben
REST="$(grep -rIl -e 'rosenweg-vorlage' -e 'rosenweg_vorlage' -e 'ch\.rosenweg4303\.vorlage' -e 'Rosenweg Vorlage' "$APP" || true)"
[ -z "$REST" ] || fehler "Platzhalter uebrig in: $REST"

# 3. Logo: Zeichen hinein, alle Symbole neu
L="$APP/assets/logo"
find "$L" -maxdepth 1 -type f ! -name erzeugen.sh -exec rm -f {} +
rm -f "$L/zeichen/vorlage.svg"
mkdir -p "$L/zeichen"
cp "$ZQ" "$L/zeichen/$ZNAME.svg"
FARBEN="$FARBEN" sh "$HIER/logo/app-symbole.sh" "$APP" "$REPO_NAME" "$TITEL" "$L/zeichen/$ZNAME.svg" "$GRUPPE"
# Startsymbol je Gruppenfarbe: activity-alias (Android), alternate icons (iOS)
python3 "$HIER/logo/farben-einbauen.py" "$APP" --standard "$GRUPPE" --farben $FARBEN >/dev/null
if grep -q 'Material Symbols' "$L/zeichen/$ZNAME.svg"; then
  printf '%s\n' "Zeichen: Material Symbols (Google), Apache-2.0 – siehe rosenweg-basis werkzeug/logo/zeichen/LIZENZEN.md" > "$L/zeichen/LIZENZ.txt"
fi

# 4. Basis lokal (Entwicklung) und pub get
if [ -n "$BASIS_LOKAL" ]; then
  printf 'dependency_overrides:\n  rosenweg_basis:\n    path: %s\n' "$BASIS_LOKAL" > "$APP/pubspec_overrides.yaml"
fi
if [ "$OHNE_PUB" = 0 ] && command -v flutter >/dev/null; then
  (cd "$APP" && flutter pub get >/dev/null) || echo "WARNUNG: flutter pub get ging nicht - spaeter von Hand."
fi

# 5. git
if [ "$OHNE_GIT" = 0 ]; then
  STAND="$(git -C "$BASIS" rev-parse --short=12 HEAD 2>/dev/null || echo unbekannt)"
  # Mit --basis-lokal zeigt pubspec.lock auf den lokalen Pfad: nicht committen
  (cd "$APP" && git init -q -b main && git add -A && { [ -z "$BASIS_LOKAL" ] || git reset -q -- pubspec.lock; } \
     && git commit -q -m "$TITEL: neu aus der App-Vorlage (rosenweg-basis $STAND)" && echo "== erster Commit auf main")
fi

# 6. GitHub (nur mit --repo)
if [ "$REPO" = 1 ]; then
  [ "$OHNE_GIT" = 0 ] || fehler "--repo braucht git (ohne --ohne-git)"
  command -v gh >/dev/null || fehler "gh fehlt"
  echo "== GitHub: Rosenweg/$REPO_NAME (privat)"
  (cd "$APP" && gh repo create "Rosenweg/$REPO_NAME" --private --source . --push \
     --description "$TITEL – $BESCHREIBUNG")
  # Alle Jobs laufen auf GitHub-Runnern; in keine Runner-Gruppe aufnehmen.
fi

cat <<EOF

Fertig: $APP

Noch zu tun (README.md der Basis, Abschnitt "Neue App anlegen"):
  1. Authentik, Anbieter rosenweg-apps: Ruecksprung  ch.rosenweg4303.$KENNUNG:/anmeldung  (strikt)
  2. GitHub (falls nicht mit --repo): Repo Rosenweg/$REPO_NAME anlegen, main pushen
  3. Secrets: Org-Secrets ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
     ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD fuer das Repo freigeben (kein BASIS_TOKEN:
     rosenweg-basis ist oeffentlich). Alles laeuft auf GitHub-Runnern, nie eigene;
     privat kosten sie Minuten, oeffentlich nicht.
  4. /apps: apps-eintrag.json in Rosenweg/Website apps-register.json (Abschnitt apps),
     assets/logo/$REPO_NAME-192.png als www img/apps/$REPO_NAME.png
  5. Stationen: linux/paket/paket.conf nach os-stationen pakete/$REPO_NAME/ (nach dem ersten Release)
  6. Version in pubspec.yaml erhoehen und mergen = erstes Release (alle Plattformen)
EOF
