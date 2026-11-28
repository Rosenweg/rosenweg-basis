# Web-Version der Apps (rosenweg4303.ch/app/<kurzname>/)

Jede Rosenweg-App gibt es auch als Seite im Browser. Sie ersetzt die alte
Seite der Website und gehört zu „fertig“. Es gibt **eine** Anmeldung für die
ganze Website: wer auf rosenweg4303.ch angemeldet ist, ist es auch in der
Web-App, und Abmelden in der App meldet auf der ganzen Website ab.

## Wie die Anmeldung funktioniert

Die Web-App liegt unter derselben Adresse wie die Website
(`https://rosenweg4303.ch/app/wetter/`, ebenso auf `isp.`). Sie hat deshalb
keinen eigenen Anmeldeschirm und keinen Client in Authentik.

- `web/index.html` lädt `/js/authentik-auth.js` der Website und verarbeitet die
  Rückkehr von der Anmeldung (`#auth=…`) **vor** dem Start von Flutter (sonst
  hält Flutter das Fragment für eine Seitenadresse).
- `WebKonto` (`lib/src/anmeldung/web_konto_web.dart`) ruft nur dieses Modul auf:
  `init` (Sitzung prüfen gegen `/api/auth/me`), `login`, `logout`, `getToken`.
  Die Schleifensperre, der stille Kerberos-Versuch an Stationen und die
  Bestätigungshinweise der Website gelten damit auch in der App.
- `RosenwegSitzung` nimmt im Browser (`kIsWeb`) diesen Weg:
  - Sitzung da → `Phase.bereit`.
  - keine Sitzung → Weiterleitung auf die Anmeldung der Website, danach zurück
    auf dieselbe Seite. Mit `ohneAnmeldung` (öffentlicher Teil) bleibt es bei
    diesem Teil, „Anmelden“ führt zur Website.
  - Abmelden → `/api/auth/logout` der Website, danach Startseite.
  - 401 der API → die Website prüft die Sitzung neu, sonst Anmeldung.
- Das Token ist das der Website-Sitzung (dasselbe Cookie auf `.rosenweg4303.ch`
  wie auf den alten Seiten). Rechte und Gruppen (auch für die Gruppenfarbe)
  kommen darum aus derselben Quelle, `GET /api/auth/me`.
- Auf anderen Adressen (`flutter run -d chrome`) fehlt das Modul: die App sagt
  das und bleibt unbenutzbar. Entwickeln geht mit `RosenwegSitzung(app,
  transport: Attrappe)` (Vorführdaten, wie in den Tests).

## Was im Web nicht gibt

Updater (die Website liefert die Version), Kerberos aus der App, USB-
Kartenleser, Schlüsselbund, lokale Benachrichtigungen und Hintergrundabfragen.
Die Bausteine der Basis schalten das mit `kIsWeb` ab. `dart:ffi` gibt es im
Browser nicht: Kerberos, PC/SC und die Windows-Registry liegen hinter
bedingten Importen (`*_ffi.dart` / `*_web.dart`); MQTT läuft über WebSocket
(`MqttBrowserClient`, `netz/mqtt_fabrik*.dart`).

### Plattform-Weichen in der eigenen App

- Kein `dart:io` (`Platform`, `File`, `Directory`) ohne `!kIsWeb`.
- Dateien speichern/öffnen: `dateiSpeichern`/`dateiTeilen` der Basis verwenden,
  nicht `File`. Hochladen mit `file_selector` und `Uint8List` (`readAsBytes`),
  nie mit Pfaden.
- Nichts, was `dart:ffi` braucht, in Dateien legen, die der Web-Build lädt:
  bedingter Import (`export 'x_ffi.dart' if (dart.library.js_interop) 'x_web.dart';`).
- Gespeichert wird im Browser nur über die Basis (`AppSpeicher` bleibt im
  Speicher; Geheimnisse gehören nicht in den Browser: die Anmeldung hat die
  Website).

## Bau und Release

`web: true` im Aufruf von `app.yml` (Vorlage hat es schon). Der Job `web` baut
wie Linux (gleiche Runner, gleiche Bedingungen):

```
flutter build web --release --base-href /app/<kurzname>/
```

Kurzname = `app` ohne `rosenweg-` (Eingang `web_name` zum Überschreiben). Er
hängt `?v=<version>-<laufnummer>` an `flutter_bootstrap.js` und `main.dart.js`
und legt `rosenweg-web.json` (App, Version, Commit) dazu. Ergebnis:
`<app>-web.tar.gz` am Release (und in `SHA256SUMS`).

CanvasKit (Zeichenmotor, rund 16 MB) wird nur einmal ausgeliefert: der Job
setzt `canvasKitBaseUrl` in `flutter_bootstrap.js` auf
`/app/canvaskit/<flutter-version>/` und lässt nur die Dateien im Archiv, die der
Renderer lädt. Ohne diese Angabe holte der Browser sie bei Google
(`www.gstatic.com`). Der Wasm-Renderer (`--wasm`, skwasm) wäre mit gut 3 MB
kleiner, braucht aber neuere Browser und für volle Geschwindigkeit
Cross-Origin-Isolation; der HTML-Renderer ist in Flutter nicht mehr enthalten.
Darum bleibt es bei CanvasKit.

**Schriften ohne Google:** Die Engine holt Roboto und Ersatzschriften (Symbole,
Emoji, andere Schriften) sonst von `fonts.gstatic.com`; das gäbe die
IP-Adressen der Bewohner an Google. Darum setzt der Job `fontFallbackBaseUrl:
"fonts/"` (relativ zur Seite, also `/app/<name>/fonts/`), und die App liefert
`web/fonts/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2` selbst mit (Roboto,
Apache-Lizenz, `web/fonts/roboto/LICENSE.txt`; kommt mit
`werkzeug/web-einrichten.sh` aus `vorlage/web/fonts`). Der Job bricht ab, wenn die
Datei fehlt. Was nicht mitgeliefert ist (seltene Zeichen, Emoji), erscheint als
leeres Kästchen statt von Google geladen zu werden: kommt so ein Zeichen vor,
die passende Datei (Pfad steht in der Fehlermeldung der Konsole, `404 …/fonts/…`)
nach `vorlage/web/fonts` legen.

## Ausrollen (Website-Repo)

```
scripts/rw-web-ausrollen.sh --app wetter                 # neuestes Release
scripts/rw-web-ausrollen.sh --app wetter --tag v1.0.1    # eine Version
scripts/rw-web-ausrollen.sh --app wetter --datei x.tar.gz
scripts/rw-web-ausrollen.sh --app wetter --zurueck       # vorige Fassung
```

Es entpackt das Archiv nach `/var/www/rosenweg/app/<kurzname>/` auf fe-www und
fe-isp, prüft das Ergebnis und hält die vorige Fassung für den Rückweg. nginx
liefert `/app/` mit `no-cache` (Dateien werden bei jedem Aufruf per ETag
geprüft; nach einem Update bleibt keine alte Version hängen).

## Eine weitere App umstellen

1. Basis-Version mit Web (`rosenweg_basis` ≥ 0.9.0) in `pubspec.yaml`.
2. `werkzeug/web-einrichten.sh <app-ordner>` (legt `web/` an, schaltet
   `web: true` ein), von Hand: `--kurz`, wenn der Kurzname vom Repo abweicht.
3. Eigenen Code auf Web prüfen (Weichen oben): `flutter build web --release
   --base-href /app/<kurzname>/` muss laufen und die App im Browser
   (`flutter run -d chrome` mit Vorführdaten) benutzbar sein.
4. PR; nach dem Release `scripts/rw-web-ausrollen.sh --app <kurzname>`.
5. Im Website-Repo `js/nav.js`: Menüeintrag auf
   `https://rosenweg4303.ch/app/<kurzname>/`. Die alte Seite bleibt liegen,
   bis Stefan sie freigibt.
