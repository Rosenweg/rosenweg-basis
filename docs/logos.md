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
