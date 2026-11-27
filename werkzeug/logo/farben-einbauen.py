#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Startsymbol je Gruppenfarbe in eine Flutter-App einbauen (docs/gruppenfarbe.md).

    python3 werkzeug/logo/farben-einbauen.py <app-wurzel> --standard bewohner --farben verwaltung technik

Android (android/app/src/main/AndroidManifest.xml):
    MAIN/LAUNCHER wandert von .MainActivity auf je eine activity-alias pro Farbe:
    .SymbolBewohner (Standardfarbe, eingeschaltet, @mipmap/ic_launcher),
    .SymbolVerwaltung / .SymbolTechnik (aus, @mipmap/ic_launcher_<farbe>).
    Umgeschaltet wird zur Laufzeit von rosenweg_basis (Startsymbol.kt).
iOS (ios/Runner.xcodeproj/project.pbxproj):
    ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "AppIcon-<farbe> …" neben
    ASSETCATALOG_COMPILER_APPICON_NAME; die Symbole schreibt app-symbole.sh (FARBEN=…).

Laeuft beliebig oft (ersetzt den eigenen Block). Ohne --farben: baut den Block aus und
gibt MAIN/LAUNCHER an .MainActivity zurueck.
"""
import argparse
import os
import re
import sys

GRUPPEN = ("bewohner", "verwaltung", "technik")
ANFANG = "<!-- rosenweg-gruppenfarbe: Startsymbol je Gruppenfarbe (rosenweg-basis docs/gruppenfarbe.md) -->"
ENDE = "<!-- /rosenweg-gruppenfarbe -->"
LAUNCHER = re.compile(
    r"\n?[ \t]*<intent-filter>\s*<action android:name=\"android\.intent\.action\.MAIN\"\s*/>\s*"
    r"<category android:name=\"android\.intent\.category\.LAUNCHER\"\s*/>\s*</intent-filter>"
)


def alias(g, standard, aktivitaet):
    icon = "@mipmap/ic_launcher" if g == standard else f"@mipmap/ic_launcher_{g}"
    an = "true" if g == standard else "false"
    return (
        f'        <activity-alias\n'
        f'            android:name=".Symbol{g.capitalize()}"\n'
        f'            android:targetActivity="{aktivitaet}"\n'
        f'            android:icon="{icon}"\n'
        f'            android:enabled="{an}"\n'
        f'            android:exported="true">\n'
        f'            <intent-filter>\n'
        f'                <action android:name="android.intent.action.MAIN"/>\n'
        f'                <category android:name="android.intent.category.LAUNCHER"/>\n'
        f'            </intent-filter>\n'
        f'        </activity-alias>\n'
    )


def manifest(pfad, standard, farben, aktivitaet):
    s = open(pfad, encoding="utf-8").read()
    s = re.sub(r"\n?[ \t]*" + re.escape(ANFANG) + r".*?" + re.escape(ENDE) + r"\n?", "\n", s, flags=re.S)
    m = re.search(r'<activity\b[^>]*android:name="' + re.escape(aktivitaet) + r'"[^>]*>.*?</activity>', s, re.S)
    if not m:
        sys.exit(f"{pfad}: {aktivitaet} nicht gefunden")
    akt = m.group(0)
    if farben:
        neu_akt = LAUNCHER.sub("", akt)
        bloecke = "".join(alias(g, standard, aktivitaet) for g in [standard] + [f for f in farben if f != standard])
        einschub = f"\n        {ANFANG}\n{bloecke}        {ENDE}"
        s = s[: m.start()] + neu_akt + einschub + s[m.end():]
    elif not LAUNCHER.search(akt):
        filt = (
            "\n            <intent-filter>\n"
            '                <action android:name="android.intent.action.MAIN"/>\n'
            '                <category android:name="android.intent.category.LAUNCHER"/>\n'
            "            </intent-filter>\n        </activity>"
        )
        s = s[: m.start()] + akt[: -len("</activity>")].rstrip() + filt + s[m.end():]
    open(pfad, "w", encoding="utf-8").write(s)


def xcode(pfad, standard, farben):
    s = open(pfad, encoding="utf-8").read()
    s = re.sub(r"\n[ \t]*ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = [^;]*;", "", s)
    namen = " ".join(f"AppIcon-{g}" for g in farben if g != standard)
    if namen:
        s = re.sub(
            r"(\n([ \t]*)ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;)",
            lambda m: f'{m.group(1)}\n{m.group(2)}ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "{namen}";',
            s,
        )
    open(pfad, "w", encoding="utf-8").write(s)


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("app")
    a.add_argument("--standard", choices=GRUPPEN, required=True)
    a.add_argument("--farben", nargs="*", choices=GRUPPEN, default=[])
    a.add_argument("--aktivitaet", default=".MainActivity")
    o = a.parse_args()
    farben = [f for f in o.farben if f != o.standard]
    m = os.path.join(o.app, "android/app/src/main/AndroidManifest.xml")
    if os.path.exists(m):
        manifest(m, o.standard, farben, o.aktivitaet)
        print(f"Android: {m}")
    x = os.path.join(o.app, "ios/Runner.xcodeproj/project.pbxproj")
    if os.path.exists(x):
        xcode(x, o.standard, farben)
        print(f"iOS: {x}")


if __name__ == "__main__":
    main()
