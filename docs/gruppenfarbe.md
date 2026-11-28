# Gruppenfarbe nach der angemeldeten Person

Entscheid Stefan, 28.11.2026: Die Farbe einer App (Thema, Anmeldeschirm, Logo
in der App, Startsymbol) richtet sich nach der Person, **soweit die App für sie
etwas freischaltet**. Massgebend ist also die freigeschaltete Funktion, nicht die
Gruppe allein.

| Farbe | Wer | Bedingung in der App |
|---|---|---|
| Grün #2E6B4F | Technik, Präsident | `farbGruppen` enthält `technik` und `Rechte.alles` |
| Blau #1E3A8A | Ausschuss, Verwaltung | `farbGruppen` enthält `verwaltung`, dazu: mit `farbRechte` eines dieser Seitenrechte (mind. lesen), ohne `farbRechte` eine Gruppe `stwegN-`/`meg-ausschuss`, `stwegN-`/`meg-verwaltung` oder `verwaltung` |
| Rot #D62828 | alle anderen | – |

Die höhere Farbe gilt. Nie unter die Mindestfarbe `gruppe`. Quelle sind die
echten Rechte aus `GET /api/auth/me` ([`RosenwegRechte`](../lib/src/rechte.dart)).

## In der App

```dart
const appAngaben = RosenwegApp(
  …
  gruppe: RosenwegGruppe.bewohner,                                     // Mindestfarbe
  farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},   // wo die App mehr freischaltet
  farbRechte: {'reklamationen'},                                       // optional: Blau nach Seitenrecht
);

RosenwegGeruest(logo: FarbLogo(sitzung: sitzung, klein: true), …)     // Logo wechselt live
```

Den Rest macht die Basis ([`GruppenFarbe`](../lib/src/gruppenfarbe.dart),
`sitzung.farbe`):

- **Nach der Anmeldung** lädt sie die Rechte, falls die App das nicht schon
  selbst tut, und setzt die Farbe. Thema (`rosenwegThema(…, gruppe)`),
  Anmeldeschirm und `FarbLogo` folgen live. Das Thema blendet weich über.
- **Abmelden:** zurück auf die Mindestfarbe. Der Anmeldeschirm steht also
  immer in der Standardfarbe der App.
- **Geteilte Telefone:** Nach jedem Personenwechsel laden die Rechte neu, die
  Farbe folgt der Person am Telefon.
- **Kein Flackern:** Die letzte Farbe steht in `speicher.json` (`AppSpeicher`).
  `rosenwegStarten` liest sie vor dem ersten Bild. Bis die Rechte geladen sind,
  bleibt sie stehen.
- **Startsymbol:** wechselt nur, wenn sich die gemerkte Farbe ändert.

## Logos und Startsymbole

`assets/logo/erzeugen.sh` der App:

```sh
GRUPPE=bewohner
FARBEN="verwaltung technik"
FARBEN="$FARBEN" sh "$BASIS/werkzeug/logo/app-symbole.sh" . rosenweg-x "Rosenweg X" assets/logo/zeichen/x.svg "$GRUPPE"
python3 "$BASIS/werkzeug/logo/farben-einbauen.py" . --standard "$GRUPPE" --farben $FARBEN
```

Je weitere Farbe entstehen:

- `assets/logo/<app>-<farbe>-512.png` und `-klein.png`. Beide gehören in
  `pubspec.yaml` unter `assets`.
- Android: `ic_launcher_<farbe>` (Mipmaps, adaptive mit eigener Grundfarbe
  `rosenweg_icon_<farbe>`).
- iOS: `Assets.xcassets/AppIcon-<farbe>.appiconset` (eine Grösse, 1024).

`farben-einbauen.py` (läuft beliebig oft):

- **Android:** MAIN/LAUNCHER wandert von `.MainActivity` auf je eine
  `activity-alias` `.SymbolBewohner`, `.SymbolVerwaltung` und `.SymbolTechnik`.
  Nur die Mindestfarbe ist im Manifest eingeschaltet. Zur Laufzeit schaltet
  `Startsymbol.kt` per `PackageManager.setComponentEnabledSetting(…,
  DONT_KILL_APP)` um: zuerst die neue ein, dann die anderen aus.
- **iOS:** `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` im Xcode-Projekt.
  Zur Laufzeit `setAlternateIconName` (die Mindestfarbe ist das Haupt-Symbol).
- **Desktop** (Linux, macOS, Windows): nur in der App; das Symbol bleibt.

`werkzeug/neue-app.sh --farben "verwaltung technik"` erledigt alles für neue
Apps. Der Standard kommt aus `werkzeug/logo/flutter-apps.txt`, Spalte 6.

### Bekannte Eigenheiten

- **Android-Launcher:** Ein Alias-Wechsel lässt manche Launcher kurz neu laden
  (Symbol verschwindet und kommt in der neuen Farbe wieder). Eine
  **Verknüpfung auf dem Startbildschirm kann dabei verschwinden**, weil sie auf
  die alte Alias zeigte. In der App-Liste bleibt die App immer. Darum schaltet
  die Basis nur bei einem echten Wechsel um, nicht bei jedem Start.
- **iOS:** Das System zeigt bei jedem Symbolwechsel selbst kurz den Hinweis
  „Das Symbol für … wurde geändert“. Das lässt sich nicht abschalten.
- Auf geteilten Telefonen wechselt das Startsymbol mit jeder Person, deren
  Farbe sich unterscheidet.

## Welche App welche Farben vergibt

Stand 28.11.2026 (Liste und Entscheid: Stefan):

| App | Mindestfarbe | farbGruppen | farbRechte |
|---|---|---|---|
| Rosenweg Reparatur | bewohner | verwaltung, technik | reklamationen |
| Rosenweg Termine | bewohner | verwaltung, technik | – |
| Rosenweg Unterlagen | bewohner | verwaltung, technik | dokumente (abgeleitet: wer irgendwo in der Ablage schreibt) |
| Rosenweg ZEV | bewohner | verwaltung, technik | – (Ausschuss/Verwaltung einer STWEG mit ZEV) |
| Rosenweg Waschküche | bewohner | verwaltung, technik | waschküche-admin |
| Rosenweg Mein Telefon | bewohner | technik | – |
| Rosenweg Salz | bewohner | technik | – |
| Profil, VM, Wetter | bewohner | – (immer rot) | |
| Zutritt, Mail-Freigabe | technik | – (immer grün) | |

Kotlin-Apps: gleiche Logik in commons-rosenweg (cloud). Wechseln tut nur
Rosenweg Messenger. Die anderen Fossify-Apps bleiben rot; Gerät, Kiosk und
Karten bleiben grün.
