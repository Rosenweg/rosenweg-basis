# Logos

`werkzeug/logo/`: Baukasten für alle App-Logos — das Rosenweg-Wappen
vereinfacht (Turm, Weg, Rose auf Rot; der Turm allein wäre mit dem Wappen von
Kaiseraugst zu verwechseln) und rechts unten das Zeichen der App in einer
weissen Plakette. Drei Detailstufen: voll (ab 109 px), `-klein` (41–108 px),
`-winzig` (bis 40 px, Turm und Rose ohne Weg). Siehe Kopf von
`werkzeug/logo/baukasten.py`.

```sh
sh werkzeug/logo/erzeugen.sh ../rosenweg-profil rosenweg-profil "Rosenweg Profil" werkzeug/logo/zeichen/person.svg
sh werkzeug/logo/vorschau.sh ~/Downloads/rosenweg-app-logos.png assets/logo/rosenweg ../rosenweg-profil/assets/logo/rosenweg-profil
```

`logos/rosenweg-vm/`: Logo für rosenweg-vm (Monitor als Zeichen), dort
übernommen (ab Version 1.0.1).

Android-Apps (Fossify-Forks, Rosenweg Karten, Rosenweg Gerät, Rosenweg Kiosk): welche App
welches Zeichen trägt, steht in `werkzeug/logo/android-apps.txt`. Jede App
ruft aus ihrem `assets/logo/erzeugen.sh` nur `android-apps.sh` auf; es schreibt
Mipmaps aller Dichten, adaptive icon und monochromes Designsymbol. Bei den
Fossify-Apps zeigen die 18 wählbaren Icon-Farben alle auf das Rosenweg-Icon.
`startbildschirm.py` zeigt die Icons wie auf dem Telefon (hell, dunkel,
Designsymbole); Stand: `logos/android-apps/startbildschirm.png`.

```sh
sh werkzeug/logo/android-apps.sh ../fossify-rosenweg/calculator-rosenweg calculator-rosenweg
python3 werkzeug/logo/startbildschirm.py --aus ~/Downloads/rosenweg-android-logos.png \
    ../fossify-rosenweg/calculator-rosenweg/assets/logo/rosenweg-rechner …
```

## Flutter-Apps (alle Plattformen)

`werkzeug/logo/flutter-apps.txt`: alle 39 Apps aus dem Flutter-Plan (Karten ist in Zutritt aufgegangen) mit Zeichen,
Zielgruppe und Kennung. Die Zielgruppe färbt das Zeichen (`baukasten.py --gruppe`):
`bewohner` rot (wie bisher), `verwaltung` blau, `technik` grün. Rosenweg Stationen
nutzt das Zeichen von os-stationen und ergibt genau dessen `docs/logo.svg`.

```sh
sh werkzeug/logo/app-symbole.sh ../rosenweg-zutritt rosenweg-zutritt "Rosenweg Zutritt" werkzeug/logo/zeichen/zutritt.svg technik
sh werkzeug/logo/kontaktbogen.sh ~/Downloads/rosenweg-app-logos.png        # [--einfarbig]
```

`app-symbole.sh` schreibt Android (Mipmaps, adaptive, monochrom), iOS-AppIcon
(vollflächig ohne Alpha), macOS-AppIcon und `.icns` (`icns.py`, auch unter Linux),
Windows-`.ico`, `assets/logo/<app>-192.png` für /apps, das 512er-PNG und den
DMG-Hintergrund (`dmg-hintergrund.svg`). Linux-hicolor rechnet das `.deb` selbst.

Neue Zeichen aus Material Symbols (Rounded, gefüllt, Stärke 600, Apache-2.0):

```sh
python3 werkzeug/logo/zeichen-zusammensetzen.py --laden door_front key
python3 werkzeug/logo/zeichen-zusammensetzen.py --titel "Tür mit Schlüssel (Rosenweg Zutritt)" \
    --haupt door_front --zusatz key > werkzeug/logo/zeichen/<name>.svg
```

Ein Zusatzsymbol sitzt rechts unten mit weissem Rand (`style="fill:#fff"`, weil der
Baukasten `fill`-Attribute entfernt; die Plakette ist in allen Fassungen weiss).
