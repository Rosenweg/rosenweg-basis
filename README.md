<p align="center"><img src="assets/logo/rosenweg-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Basis</h1>
<p align="center">Gemeinsame Flutter-Basis aller Rosenweg-Apps – gleiche Anmeldung, gleiche API, gleiches Aussehen.</p>
<p align="center"><a href="#neue-app-anlegen">Neue App anlegen</a> · <a href="docs/bedienung.md">Anleitung</a></p>

## Inhalt

- [Überblick](#überblick)
- [Läuft auf](#läuft-auf)
- [Eine App in wenigen Zeilen](#eine-app-in-wenigen-zeilen)
- [Bedienung – gleich in allen Apps](#bedienung--gleich-in-allen-apps)
- [Bausteine für Apps (Rechte, Listen, Formulare, Scannen, Dateien, PDF)](#bausteine-für-apps)
- [Beispiel-App](#beispiel-app)
- [Was jede App einrichten muss](#was-jede-app-einrichten-muss)
- [Grenzen je Plattform](#grenzen-je-plattform)
- [Aufbau (öffentliche API)](#aufbau-öffentliche-api)
- [Anmeldung und Authentik](#anmeldung-und-authentik)
- [Geteilte Telefone](#geteilte-telefone)
- [Updates](#updates)
- [Logos](#logos)
- [Neue App anlegen](#neue-app-anlegen)
- [Prüfen und CI](#prüfen-und-ci)
- [Weitere Dokumente](#weitere-dokumente)
- [Lizenz](#lizenz)

## Überblick

Jede Portal-Funktion wird eine eigene Flutter-App mit eigenem Repo. Diese Basis sorgt dafür, dass sie sich alle gleich anmelden, gleich mit der Rosenweg-API reden und gleich aussehen – was `commons-rosenweg` (Modul `cloud`) für die Fossify-Forks ist.

Was drin ist:

- **Anmeldung** mit dem Rosenweg-Konto (Authentik `rosenweg-apps`, PKCE), danach 30 Tage still; an Stationen und Windows-Rechnern der Domäne per Kerberos ganz ohne Browser.
- **API-Client** mit verständlichen Fehlern (Server weg, zu viele Anfragen, keine Berechtigung, neu anmelden).
- **Geteilte Telefone:** Anfragen über Rosenweg Gerät, ohne eigenes Token.
- **Aussehen und Bausteine:** Thema, Farben, Anmeldeschirm, Fehler- und Ladeanzeige, „Über“ mit GPL.
- **Bausteine für Apps (0.6.0):** Rechte aus `auth/me` mit „nur sichtbar mit Recht X“ und Stufe der Anmeldung, Listen mit Suche/Filter/Cursor und Desktop-Tabelle, Formulare mit Fehlern der API am Feld, QR-/Strichcode-Scannen auf allen Plattformen, Dateien hoch- und herunterladen mit Fortschritt, PDF-Ansicht.
- **Logo-Baukasten** für alle App-Logos (Turm, Weg und Rose mit App-Zeichen).

Veröffentlicht bis v0.4.0; 0.5.0 (Updater) und 0.6.0 (Bausteine) sind unveröffentlicht – siehe [CHANGELOG.md](CHANGELOG.md).

## Läuft auf

| Plattform | Stand |
|---|---|
| Linux (Rosenweg OS, `.deb` vom PXE-Server) | ja; stille Anmeldung über GSS-API (`libgssapi-krb5-2`) |
| Android 8 und neuer (eigene Handys und geteilte Telefone) | ja; Android-Plugin `ch.rosenweg4303.basis`, minSdk 26; Anmeldeschirm aus commons-rosenweg (`ch.rosenweg4303:cloud` aus GitHub Packages, `mavenLocal()` als Rückfall) |
| Windows | Kerberos-Anmeldung über SSPI vorbereitet; Bausteine alle ausser Kamera |
| macOS | ja; Kamera-Scanner mit eingebauter/USB-Kamera |
| iOS 15 und neuer | ja; Karte per Core NFC, QR per VisionKit/Kamera (baut in CI, Verteilung offen) |

## Eine App in wenigen Zeilen

```dart
const app = RosenwegApp(
  kennung: 'ch.rosenweg4303.profil',      // applicationId = GTK-ID = Rücksprung-Schema
  name: 'Rosenweg Profil',
  ordner: 'rosenweg-profil',              // Paket, Logdatei, Schlüsselbund-Eintrag
  beschreibung: 'Deine Angaben im Rosenweg-Portal.',
  quelle: 'https://github.com/Rosenweg/rosenweg-profil',
  logo: AssetImage('assets/logo/rosenweg-profil-512.png'),
);

void main() => rosenwegStarten(app, (sitzung) => MeineSeite(api: sitzung.api));
```

`rosenwegStarten` richtet Logdatei und Fehlerfang ein, prüft die Anmeldung und zeigt bis dahin Warten, Anmeldeschirm oder Fehler. Die App sieht erst `sitzung.api`, wenn jemand angemeldet ist.

## Bedienung – gleich in allen Apps

| Situation | Verhalten |
|---|---|
| Anmelden | ein Knopf „Mit Rosenweg-Konto anmelden“, meist ohne Eingabe; während die Seite offen ist: Hinweis und „Abbrechen“ |
| Danach | still angemeldet, bis die letzte Browser-Anmeldung 30 Tage her ist |
| Station / Windows-Domäne | Anmeldung mit dem Kerberos-Ticket der Sitzung, ohne Browser; fragt Authentik etwas, kommt der Browser |
| Fehler | ganzer Satz mit „Nochmals“; ein kurzer Server-Neustart meldet niemanden ab |
| Heikle Aktionen (Passwort) | API antwortet `403 reauth`, die App bietet „Jetzt neu anmelden“ an und macht danach selbst weiter |
| Geteiltes Telefon | keine Anmeldung und kein „Abmelden“ in der App – das macht Rosenweg Gerät (Karte); wechselt die Person, baut sich die App neu |

Mehr: [docs/bedienung.md](docs/bedienung.md).

## Aufbau (öffentliche API)

| Teil | Klassen / Funktionen |
|---|---|
| Einstellungen | `RosenwegKonfig` (Authentik, Client, Scopes, API, Haus-DNS, 30-Tage-Regel), `RosenwegApp` |
| Anmeldung | `RosenwegKonto` (`anmelden`, `stillAnmelden`, `abmelden`, `zugangsToken` …), `AnmeldeFehler` |
| Stille Anmeldung | `StilleAnmeldung`, `KerberosTicket` (GSS-API / SSPI per FFI) |
| Rücksprung | `Anmeldeweg.fuer(...)`: `LocalhostAnmeldeweg` (Desktop), `SchemaAnmeldeweg` (Android) |
| Speicher | `Schluesselbund`: ein JSON-Eintrag in flutter_secure_storage, Rückfall „nur im Speicher“ |
| API | `RosenwegApi` (`get/put/post/delete`, `objekt`, `liste`), `HttpTransport` (Bearer, 401 → einmal erneuern, POST nie wiederholt), `GeraetTransport` (geteiltes Telefon) |
| Fehler | `ServerNichtErreichbar`, `ZuVieleAnfragen`, `ApiFehler`, `NichtAngemeldet`, `KeineBerechtigung`, `GeraetFehler` |
| Haus | `HausErkennung().imHaus()` – TXT `location.rosenweg4303.ch`; nur Hinweis, nie Sicherheit |
| Ablauf | `RosenwegSitzung` (`zugang` für eigene Dienste), `rosenwegStarten`, `RosenwegRahmen`, `AnmeldeTor` |
| Updates | `RosenwegAktualisierung`, `AktualisierungsLeiste`, `RosenwegStation.erkannt` |
| Aussehen | `rosenwegThema`, `RosenwegFarben` (Rot `#D32F2F`, Grundton `#8B1E3F`), deutsche Texte (de-CH) |
| Gerüst | `RosenwegGeruest` (Handy: Navigation unten; ab 840 px Seitenleiste links, Inhalt mittig begrenzt), `RosenwegSpalten` (zwei Spalten am Desktop), `RosenwegInhalt` (max. Breite), `Fensterklasse` (kompakt/mittel/breit/sehrBreit) |
| Bausteine | `AnmeldeSchirm`, `FehlerAnzeige`, `LadeAnzeige`, `Abschnitt`, `Hinweis`, `zeigeMeldung`, `frage`, `zeigeUeber`, `RosenwegLogo` |
| Rechte | `RosenwegRechte` (`sitzung.rechte`), `Rechte`, `Zugriff`, `Anmeldestufe`, `sitzung.darf(...)`, `NurMit`, `RechteBereich`, `KeineBerechtigungAnzeige`, `StufeNoetigAnzeige`, `mitBestaetigung` |
| Listen | `ListenSteuerung` (Server oder `.lokal`), `apiListe`, `seiteLesen`, `ListenFilter`, `ListenSortierung`, `RosenwegListe`, `ListenSpalte` |
| Formulare | `RosenwegFormular`, `FormularSteuerung`, `TextFeld`, `BetragFeld` (Rappen), `DatumFeld`, `ZeitFeld`, `AuswahlFeld`, `SchalterFeld`, `SuchAuswahlFeld`, `auswahlSuchen`, `Pruefen`, `loeschenBestaetigen`, `betragLesen/betragText`, `datumText`, `zeitText` |
| Scannen | `codeScannen`, `KameraScanner`, `CodeEingabe`, `qrAusBild`, `codeAusBildWaehlen`, `scannerMitKamera` |
| Dateien | `RosenwegDateien` (`sitzung.dateien`: `hochladen` roh/multipart, `herunterladen`), `DateiDaten`, `dateienWaehlen`, `fotoAufnehmen`, `bildVerkleinern`, `dateiSpeichern`, `dateiTeilen`, `DateiAblage`, `mitFortschritt`, `TransferAnzeige` |
| PDF | `PdfAnsicht`, `PdfSeite`, `pdfOeffnen` |
| Protokoll | `Protokoll.schreiben` – `~/.local/state/<ordner>/app.log`, nie Tokens |
| Android | Plugin `ch.rosenweg4303.basis`: Anmeldung über commons-rosenweg (`AndroidKonto`: Anmeldeschirm mit Karte oder Rosenweg-Konto, Token aus Kotlin), DNS-Server, Rosenweg Gerät (`ContentResolver.call`) |

Mehr: [docs/entwickeln.md](docs/entwickeln.md).

## Bausteine für Apps

Grundsatz: Was zwei Apps brauchen, steht hier – nicht in den Apps. Alle Beispiele laufen in der [Beispiel-App](#beispiel-app).

### Rechte

Quelle ist `GET /api/auth/me` (`user.permissions`: Seite → `read`/`write`, `user.groups`). Technik und Präsident dürfen alles – genau wie `requirePermission` der API. Die App blendet nur aus, was die API ohnehin ablehnen würde; entschieden wird immer auf dem Server.

```dart
if (sitzung.darf('reklamationen', Zugriff.schreiben)) …          // nach sitzung.rechte.laden()
NurMit(recht: 'reklamationen', zugriff: Zugriff.schreiben, kind: bearbeitenKnopf)   // sonst unsichtbar
NurMit(eines: ['stationen', 'noc'], kind: menuePunkt)                               // wie permAny im Menü
NurMit(recht: 'rechteverwaltung', stufe: Anmeldestufe.konto, hinweis: true, kind: RechteSeite())
await mitBestaetigung(context, () => api.post('/api/auth/change-password', {...}));
```

- `RosenwegRahmen` legt den `RechteBereich` selbst um die App; die Rechte werden beim ersten `NurMit` geladen und nach Abmelden, Personenwechsel (geteiltes Telefon) und Bestätigen neu geholt.
- `hinweis: true` (ganze Seiten): einheitlich „Keine Berechtigung – Wenn du sie brauchst, melde dich bei der Technik oder beim Ausschuss.“
- **Stufe der Anmeldung** (Plan 4.2.1): `karte` < `konto` < `konto-frisch`. Reicht sie nicht, zeigt `NurMit(..., hinweis: true)` „Rosenweg-Konto nötig“ mit Knopf „Mit Rosenweg-Konto anmelden“ (`sitzung.bestaetigen()`).
- `mitBestaetigung`: lehnt die API mit `403 {reauth: true}` oder `403 {stufe: …}` ab, fragt die App „Bitte bestätigen“, meldet frisch an und versucht es **einmal** nochmals.

**Vertrag mit der API (Stufen – baut die API, die Basis wertet schon aus):**

| Stelle | Feld | Werte |
|---|---|---|
| `GET /api/auth/me` | `user.anmeldung.stufe` (auch oben als `anmeldung.stufe` erlaubt) | `karte`, `konto`, `konto-frisch` |
| `GET /api/auth/me` | `user.anmeldung.frisch_bis` (optional) | ISO-Zeit; danach zählt `konto-frisch` nur als `konto` |
| 403 einer Route mit `verlangtKonto` | `stufe` | nötige Stufe, z. B. `konto` |
| 403 heikle Aktion | `reauth: true` | wie bisher |

**Rückfall**, solange die API keine Stufe liefert: die App schätzt aus ihrer eigenen Anmeldung – Karte, QR, Handy, geteiltes Telefon → `karte`; Rosenweg-Konto, Kerberos → `konto`; bis 5 Minuten nach `sitzung.bestaetigen()` → `konto-frisch`.

### Listen und Tabellen

```dart
final steuerung = ListenSteuerung<Meldung>(
  lader: apiListe(sitzung.api, '/api/reklamationen', schluessel: 'reklamationen', wandeln: Meldung.ausJson,
      parameter: (a) => {if (a.filter.contains('offen')) 'status': 'offen'}),
  filter: const [ListenFilter(id: 'offen', titel: 'Offen')],
  schluessel: (m) => m.id,
);
RosenwegListe<Meldung>(
  steuerung: steuerung,
  kachel: (_, m) => ListTile(title: Text(m.titel), subtitle: Text(m.haus)),         // Handy
  spalten: [ListenSpalte(id: 'titel', titel: 'Meldung', text: (m) => m.titel, sortierbar: true), …],  // Desktop
  antippen: (m) => …,
  mehrfachauswahl: true, auswahlAktionen: (_, auswahl) => [ … ],
)
```

| | Handy / schmales Fenster | Desktop (ab 840 px) |
|---|---|---|
| Darstellung | `kachel` je Eintrag | Tabelle mit Kopfzeile aus `spalten`, Zeilen zum Anklicken |
| Neu laden | nach unten ziehen | Knopf neben der Suche, F5, Strg/Cmd+R |
| Sortieren | – | Klick auf sortierbare Spalte (nochmals = umgekehrt) |
| Auswahl | lange drücken, dann tippen | Kästchen je Zeile |
| Weiterladen | automatisch am Ende; nach Fehler Knopf „Nochmals“ | gleich |

Suche mit Verzögerung (350 ms), Filter-Chips, „42 Einträge“, gleiche Leer-, Lade- und Fehleranzeige in allen Apps.

**Vertrag mit der API (Plan 4.2.4):** `GET …?limit=50&nach=<cursor>&q=<suche>&sort=<spalte>&richtung=auf|ab` → `{<liste>: [...], naechster: "<cursor>"|null, gesamt?: 123}`. Wo die API noch `limit/offset` kennt: `apiListe(..., blaettern: Blaettern.offset)`. Wo sie alles auf einmal liefert: `ListenSteuerung.lokal(alle: …, suchText: …, sortierer: …)` – Suche, Filter (`ListenFilter.passt`) und Sortierung dann in der App.

### Formulare

```dart
RosenwegFormular(
  speichern: () => sitzung.api.put('/api/me', {...}),
  felder: [
    TextFeld(name: 'email', titel: 'E-Mail', controller: email, pflicht: true, pruefen: Pruefen.email),
    BetragFeld(name: 'betrag', titel: 'Betrag', rappen: betrag, geaendert: (r) => betrag = r),
    DatumFeld(name: 'datum', titel: 'Datum', wert: datum, geaendert: …),
    SuchAuswahlFeld<Person>(name: 'person', titel: 'Person', suchen: (q) => …, text: (p) => p.name, geaendert: …),
  ],
)
```

- Prüft vor dem Speichern; Knopf zeigt „Wird gespeichert …“ und lässt sich nicht doppelt drücken; danach „Gespeichert.“.
- **Fehler der API am Feld:** antwortet die API mit `{error, feld: "email"}` oder `{error, felder: {email: "…"}}`, steht der Satz am Feld mit diesem `name`; sonst oben im Formular. Tippen im Feld nimmt den Fehler weg.
- **Ungespeicherte Änderungen:** Zurück fragt „Änderungen verwerfen?“. Strg/Cmd+S speichert.
- Beträge in **Rappen** (`int`): nimmt `12`, `12,50`, `1'234.50`, `CHF 12.–`; zeigt `1'234.50`.
- `loeschenBestaetigen(context, 'Meldung')` – roter Knopf, „Das lässt sich nicht rückgängig machen.“

### Kamera, QR und Strichcode

```dart
final code = await codeScannen(context, titel: 'Raum-QR', hinweis: 'Den QR-Code auf dem Schild in den Rahmen halten.',
    pruefen: (w) => w.startsWith('https://rosenweg4303.ch/raum/') ? null : 'Das ist kein Raum-Code.');
```

| Plattform | Kamera | Bild wählen | Hand-Scanner / Eintippen |
|---|---|---|---|
| Android, iOS | ja (`mobile_scanner`, Licht-Knopf) | ja | Eintippen |
| macOS | ja (eingebaute oder USB-Kamera) | ja | ja |
| Linux, Windows | **nein** – es gibt kein Kamera-Plugin | ja, **nur QR** (reines Dart, zxing2) | ja: Feld hat sofort den Fokus, Scanner tippt Zeichen + Enter |

`CodeArt.alle` liest mit der Kamera auch EAN, Code 128/39, ITF, DataMatrix (Salz-Säcke). Fotos für Meldungen: `fotoAufnehmen` (siehe Dateien). Die Anmeldung per QR (VisionKit auf iOS) bleibt im Anmeldeschirm.

### Dateien hoch- und herunterladen

```dart
final fotos = await dateienWaehlen(context, arten: [DateiArt.bilder], mehrere: true, hoechstens: 20 << 20);
final foto = await fotoAufnehmen(context);                       // Telefon: Kamera; Computer: Bild wählen; verkleinert auf 2000 px
await mitFortschritt(context, 'Foto wird hochgeladen',
    (f) => sitzung.dateien.hochladen('/api/reparatur/7/foto', foto!, multipart: true, feld: 'foto', fortschritt: f));
await sitzung.dateien.hochladen('/api/documents/Ordner/plan.pdf', datei, methode: 'PUT', inhaltstyp: 'application/octet-stream');
final pdf = await sitzung.dateien.herunterladen('/api/vollmachten/7/pdf');
await dateiSpeichern(context, pdf);                              // Computer: „Speichern unter“; Telefon: Teilen
DateiAblage(mehrere: true, mitFoto: true, gewaehlt: hochladen)   // Knopf + am Computer hineinziehen
```

- Token wie bei der API (`Authorization: Bearer`), bei 401 einmal erneuern, Fehler der API als `ApiFehler` mit dem Text der API.
- **Roh** (Standard): Body = Datei, `Content-Type` der Datei oder `inhaltstyp`, Name im Kopf `X-Filename` (Umlaute URL-kodiert). Die API nimmt je Route nur einen Typ an: `/api/documents` `application/octet-stream`, `upload-signed` `application/pdf`. **Multipart**: `multipart: true`, Feld `feld`, weitere `felder`.
- `bildVerkleinern`: lange Seite auf 2000 px, Drehung aus EXIF, JPEG 85 %, im eigenen Isolate.

| | Wählen | Foto | Speichern | Teilen |
|---|---|---|---|---|
| Linux | GTK-Dialog (ohne zenity) | Bild wählen | „Speichern unter“ | – (Speichern) |
| Windows | Explorer-Dialog | Bild wählen | „Speichern unter“ | Windows-Teilen |
| macOS | Finder-Dialog | Bild wählen | „Speichern unter“ | Teilen-Menü |
| Android | Dateiauswahl des Systems | Kamera | – (Teilen) | Teilen |
| iOS | Dateien-App | Kamera | – (Teilen → „In Dateien sichern“) | Teilen |

### PDF-Ansicht

```dart
pdfOeffnen(context, titel: 'Vollmacht', laden: () => sitzung.dateien.herunterladen('/api/vollmachten/7/pdf'));
PdfAnsicht(laden: …)     // eingebettet in eine eigene Seite
```

`pdfrx` (PDFium) auf allen fünf Plattformen: Blättern mit Wischen/Rad, Zoom (zwei Finger, Strg+Rad, Knöpfe, Strg/Cmd +/−), „Seite 2 von 5“ mit Vor/Zurück, Bild auf/ab, Pos1/Ende; in `PdfSeite` dazu Speichern und Teilen. Laden mit dem Token der Anmeldung, Fehler mit „Nochmals“.

## Beispiel-App

`example/` zeigt jeden Baustein so, wie eine echte App ihn benutzt – ohne Anmeldung und ohne Server (Vorführdaten in `example/lib/attrappe.dart`), auf allen fünf Plattformen:

```sh
cd example && flutter run -d macos        # oder linux, windows, ein Android-/iOS-Gerät
BEISPIEL_ZIEL=1 flutter run -d linux      # gleich mit Seite 1 (Liste) starten; 0 Rechte … 5 PDF
```

Seiten: Rechte (Rolle und Stufe umschalten), Liste (137 Meldungen, Cursor, Filter, Sortierung, Auswahl), Formular (Fehler der API am Feld ausprobieren), Scannen, Dateien (hochladen mit Fortschritt, PDF speichern), PDF. Die CI baut sie auf Linux, Android, macOS, iOS (ohne Signatur) und Windows.

## Was jede App einrichten muss

Die Basis bringt die Plugins mit; Berechtigungen stehen aber im Projekt der App (Muster: `example/`).

| Plattform | Eintrag | wofür |
|---|---|---|
| Android `AndroidManifest.xml` | `android.permission.CAMERA`, `<uses-feature android:name="android.hardware.camera" android:required="false"/>` | Scannen, Foto |
| iOS `Info.plist` | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` | Scannen, Foto, Bild wählen |
| macOS `Info.plist` | `NSCameraUsageDescription` | Scannen |
| macOS `*.entitlements` (beide) | `com.apple.security.network.client`, `com.apple.security.device.camera`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.downloads.read-write` | API, Kamera, Dateiauswahl, „Speichern unter“ |
| Windows (nur zum Bauen) | Entwicklermodus (Symlinks für PDFium, wie für alle Plugins) | pdfrx |
| iOS / macOS | Mindestens iOS 15 / macOS 12 (pdfrx) | PDF |

Ohne die Einträge stürzt nichts ab: Scanner und Dateiauswahl zeigen einen verständlichen Satz und bieten Eintippen bzw. Nochmals an.

## Grenzen je Plattform

- **Linux, Windows: keine Kamera.** `mobile_scanner` gibt es dort nicht. Ersatz: USB-Hand-Scanner (wie eine Tastatur), Eintippen, QR aus einem Bild (nur QR, keine Strichcodes). Stationen haben ohnehin keine Kamera.
- **Linux: kein Teilen-Menü** – `dateiTeilen` speichert dort.
- **Telefone: kein „Speichern unter“** – `dateiSpeichern` öffnet das Teilen-Menü (Android: z. B. in „Dateien“ ablegen; iOS: „In Dateien sichern“).
- **Geteilte Telefone: keine Dateien.** Rosenweg Gerät reicht nur JSON weiter; `sitzung.dateien` meldet „… geht auf geteilten Rosenweg-Telefonen noch nicht“. Für Fotos der Reparatur auf geteilten Telefonen braucht Rosenweg Gerät einen Datei-Weg (offen).
- **Drag & Drop** nur am Computer (Linux, macOS, Windows).
- **Grösse:** pdfrx (PDFium) und mobile_scanner (ML Kit auf Android, ohne Google-Dienste) machen jede App einige MB grösser, auch wenn sie PDF/Scanner nicht nutzt.

## Anmeldung und Authentik

| In Authentik (`rosenweg-apps`) | Wert |
|---|---|
| Rücksprung Desktop (Regex) | `^http://localhost:[0-9]+/anmeldung$` – einmal für alle Apps |
| Rücksprung Android (strikt) | `ch.rosenweg4303.<app>:/anmeldung` – je App |
| Bereiche | `openid email profile offline_access` |
| Refresh-Token | mindestens 30 Tage gültig |
| Zustimmung | implizit, sonst fällt die stille Anmeldung alle 4 Wochen auf den Browser zurück |
| Frische Anmeldung | `prompt=login` und `max_age=0` müssen durchgehen (Passwortwechsel) |

**Kerberos:** SPNEGO an die Authentik-Kerberos-Quelle, Ablauf über die Ablauf-API abschliessen, dann die gewohnte PKCE-Autorisierung ohne Browser. Ohne Ticket oder bei einer Rückfrage bleibt der Knopf.

**Haupt-API:** Die Apps schicken das Access-Token als `Authorization: Bearer …`. Die allgemeine Annahme solcher Tokens ist in der API noch in Arbeit (`requireUserLogin`, Frische-Prüfung für den Passwortwechsel).

**Anmeldeschirm:** wie auf Android blau mit Rosenweg-Siegel und drei Wegen – Rosenweg-Karte (iPhone per NFC, Computer per USB-Leser, nur wenn einer steckt), Rosenweg-Konto, QR-Code (iPhone scannt; der Computer zeigt einen, den das Handy bestätigt). Auf Android der native Schirm aus commons-rosenweg. Mehr: [docs/anmeldeschirm.md](docs/anmeldeschirm.md).

Mehr: [docs/authentik.md](docs/authentik.md).

## Geteilte Telefone

Gibt es auf Android den Provider `ch.rosenweg4303.telefon.anlage` (Rosenweg Gerät), meldet sich niemand in der App an. Alle Anfragen gehen per `call("portal_anfrage", <pfad>, …)` an Rosenweg Gerät (ab v236), von dort über die Telefonanlage an die Haupt-API – mit einem Token, das nur für diese eine Anfrage gilt.

| Stelle | prüft |
|---|---|
| Rosenweg Gerät | Signatur des Aufrufers (`ch.rosenweg4303.permission.ANLAGE`), Paket `ch.rosenweg4303.*`, Methode, Pfad, Grösse, höchstens 120 Anfragen je App und Minute |
| Telefonanlage | wer angemeldet ist und ob die App den Pfad darf (`portal_pfade`) |
| Haupt-API | Signatur, Frist, Methode und Pfad, Konto aktiv; nichts, was einen Ausweis ändert |

| Antwort | in der App |
|---|---|
| Methode unbekannt | „Rosenweg Gerät ist zu alt für diese App – bitte aktualisieren.“ |
| andere Signatur | „Rosenweg Gerät verweigert den Zugriff (andere Signatur?).“ |
| niemand angemeldet | „Bitte zuerst mit der Karte anmelden.“ |
| 403 / 429 | Pfad nicht freigegeben / zu viele Anfragen |

Die APKs müssen deshalb mit dem Rosenweg-Schlüssel signiert sein. Mehr: [docs/geteilte-telefone.md](docs/geteilte-telefone.md).

## Updates

Jede App mit `rosenwegStarten` aktualisiert sich selbst. Aus ist der Updater nur, wo jemand anderes aktualisiert.

| Wo | Wer aktualisiert |
|---|---|
| Android | Rosenweg Updater aus commons-rosenweg (`ch.rosenweg4303:updater`, im Android-Teil der Basis): eine Rosenweg-App prüft täglich für alle, Android fragt pro Installation |
| geteiltes Telefon | Rosenweg Gerät (Katalog), der Updater ist dort aus |
| Rosenweg-Station | os-stationen (`pakete/<app>/paket.conf`); der Updater ist aus, ohne Hinweis |
| Linux (eigener Rechner), macOS, Windows | `RosenwegAktualisierung`: Leiste „Neue Fassung … verfügbar“ → Laden, Grösse und SHA-256 prüfen → Windows: Installer starten; macOS: Disk-Image öffnen; Linux: `pkexec apt-get install` (sonst .deb in „Downloads“ mit Anleitung) |
| iOS | aus (keine Verteilung ausserhalb des App Store) |

Quelle: `https://pbx.rosenweg4303.ch/api/apps/index.json`, Liste `karten`, Eintrag mit `paket` = `RosenwegApp.kennung`. Neue Fassungen kommen dorthin aus der CI der App (Release-Tag, siehe Website `pbx/README.md`). Geprüft wird beim Start (nach 20 s) und alle 12 Stunden; Fehler bleiben im Protokoll.

Station heisst: `/etc/rosenweg-station/station-id` mit einer Station-ID **und** `/etc/rosenweg-station/station.json` – beides legt os-stationen an. „Linux“, „Debian“ oder ein installiertes .deb machen noch keine Station.

## Logos

`werkzeug/logo/` ist der Baukasten für alle App-Logos: das Rosenweg-Wappen vereinfacht (Turm, Weg, Rose auf Rot – der Turm allein wäre mit dem Wappen von Kaiseraugst zu verwechseln) und rechts unten das Zeichen der App in einer weissen Plakette.

| Stufe | Grösse |
|---|---|
| voll | ab 109 px |
| `-klein` | 41–108 px |
| `-winzig` | bis 40 px, Turm und Rose ohne Weg |

```sh
sh werkzeug/logo/erzeugen.sh ../rosenweg-profil rosenweg-profil "Rosenweg Profil" werkzeug/logo/zeichen/person.svg
sh werkzeug/logo/android-apps.sh ../fossify-rosenweg/calculator-rosenweg calculator-rosenweg
```

Für die Android-Apps (Fossify-Forks, Rosenweg Karten, Rosenweg Gerät, Rosenweg Kiosk) steht in `werkzeug/logo/android-apps.txt`, welche App welches Zeichen trägt; `android-apps.sh` schreibt Mipmaps, adaptive Icon und monochromes Designsymbol. Mehr: [docs/logos.md](docs/logos.md).

## Neue App anlegen

1. `flutter create --platforms=android,linux --org ch.rosenweg4303 --project-name rosenweg_<name> rosenweg-<name>`
2. applicationId/APPLICATION_ID auf `ch.rosenweg4303.<name>` setzen.
3. `rosenweg_basis` als git-Abhängigkeit mit festem Tag (z. B. `ref: v0.6.0`), lokal `pubspec_overrides.yaml` mit `path: ../rosenweg-basis`.
4. Zeichen zeichnen (`werkzeug/logo/zeichen/<name>.svg`, 400×400), `erzeugen.sh`.
5. Authentik: Rücksprung `ch.rosenweg4303.<name>:/anmeldung` eintragen.
6. `linux/paket/` aus rosenweg-profil kopieren und Namen ersetzen.
7. Desktop: Seiten mit `RosenwegGeruest` bauen und die kleinste Fenstergrösse 400×560 setzen (macOS `contentMinSize`, Linux `gtk_widget_set_size_request`, Windows `WM_GETMINMAXINFO`; Muster in rosenweg-salz).
8. Berechtigungen für Kamera und Dateien eintragen – siehe [Was jede App einrichten muss](#was-jede-app-einrichten-muss).

## Prüfen und CI

```sh
flutter analyze && flutter test
```

Dasselbe läuft bei jedem Push und PR in `.github/workflows/pruefen.yml` auf dem eigenen Runner (inkl. `example/`). `.github/workflows/beispiel.yml` baut die Beispiel-App auf allen fünf Plattformen (Linux und Android auf dem eigenen Runner, macOS/iOS und Windows bei GitHub) – so fällt auf, wenn ein Plugin auf einer Plattform nicht mehr baut. Keine Secrets nötig. Änderungen stehen in [CHANGELOG.md](CHANGELOG.md).

## Weitere Dokumente

| Datei | Inhalt |
|---|---|
| [docs/entwickeln.md](docs/entwickeln.md) | Beispiel, öffentliche API im Detail mit Herkunft |
| [docs/bedienung.md](docs/bedienung.md) | Bedienung, gleich in allen Apps |
| [docs/anmeldeschirm.md](docs/anmeldeschirm.md) | Anmeldeschirm je Plattform (Karte, Konto, QR), Karten-Sitzung, was die Apps einrichten |
| [docs/authentik.md](docs/authentik.md) | was in Authentik eingetragen sein muss, Kerberos |
| [docs/geteilte-telefone.md](docs/geteilte-telefone.md) | Schnittstelle zu Rosenweg Gerät, Personenwechsel |
| [docs/logos.md](docs/logos.md) | Logo-Baukasten |
| [docs/rosenweg-vm-umstellen.md](docs/rosenweg-vm-umstellen.md) | was rosenweg-vm für die Umstellung auf die Basis ändern müsste |

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE).
