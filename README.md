<p align="center"><img src="assets/logo/rosenweg-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Basis</h1>
<p align="center">Gemeinsame Flutter-Basis aller Rosenweg-Apps – gleiche Anmeldung, gleiche API, gleiches Aussehen.</p>
<p align="center"><a href="#neue-app-anlegen">Neue App anlegen</a> · <a href="docs/bedienung.md">Anleitung</a></p>

## Inhalt

- [Überblick](#überblick)
- [Läuft auf](#läuft-auf)
- [Eine App in wenigen Zeilen](#eine-app-in-wenigen-zeilen)
- [Bedienung – gleich in allen Apps](#bedienung--gleich-in-allen-apps)
- [Bausteine für Apps (Rechte, Listen, Formulare, Scannen, Karte lesen, Dateien, PDF, Diagramme, Echtzeit)](#bausteine-für-apps)
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
- **Bausteine für Apps (0.6.0):** Rechte aus `auth/me` mit „nur sichtbar mit Recht X“ und Stufe der Anmeldung, Listen mit Suche/Filter/Cursor und Desktop-Tabelle, Formulare mit Fehlern der API am Feld, QR-/Strichcode-Scannen auf allen Plattformen, Rosenweg-Karte in der App lesen (NFC am Handy, USB-Leser über PC/SC am Computer), Dateien hoch- und herunterladen mit Fortschritt, PDF-Ansicht.
- **Logo-Baukasten** für alle App-Logos (Turm, Weg und Rose mit App-Zeichen).

Getaggt bis v0.6.1; 0.6.2 („Nach Updates suchen“, Versionsstand ans NOC) folgt – siehe [CHANGELOG.md](CHANGELOG.md).

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
| Rechte | `RosenwegRechte` (`sitzung.rechte`), `Rechte`, `Zugriff`, `Anmeldestufe`, `sitzung.darf(...)`, `NurMit`, `RechteBereich`, `KeineBerechtigungAnzeige`, `StufeNoetigAnzeige`, `mitBestaetigung`, `BestaetigungPerEmail` + `zeigeEmailBestaetigung` (202 „Bestätigung per E-Mail“ bei heiklen Aktionen mit der Karte) |
| Listen | `ListenSteuerung` (Server oder `.lokal`), `apiListe`, `seiteLesen`, `ListenFilter`, `ListenSortierung`, `RosenwegListe`, `ListenSpalte` |
| Formulare | `RosenwegFormular`, `FormularSteuerung`, `TextFeld`, `BetragFeld` (Rappen), `DatumFeld`, `ZeitFeld`, `AuswahlFeld`, `SchalterFeld`, `SuchAuswahlFeld`, `auswahlSuchen`, `Pruefen`, `loeschenBestaetigen`, `betragLesen/betragText`, `datumText`, `zeitText` |
| Scannen | `codeScannen`, `KameraScanner`, `CodeEingabe`, `qrAusBild`, `codeAusBildWaehlen`, `scannerMitKamera` |
| Karte lesen | `karteLesen`, `KarteLesenSeite`, `KartenleserBereich`, `Kartenleser.fuerApp`, `AndroidKartenleser`, `kartenleserHindernis`, `karteUidNormal`, `uidEintippen` |
| Dateien | `RosenwegDateien` (`sitzung.dateien`: `hochladen` roh/multipart, `herunterladen`), `DateiDaten`, `dateienWaehlen`, `fotoAufnehmen`, `bildVerkleinern`, `dateiSpeichern`, `dateiTeilen`, `dateiOeffnen`, `DateiAblage`, `mitFortschritt`, `TransferAnzeige` |
| PDF | `PdfAnsicht`, `PdfSeite`, `pdfOeffnen` |
| Kalender | `Wochenraster` (7 Tage × Stunden, Handy: ein Tag mit Tageswahl; Tippen in freie Stelle = Zeitpunkt), `RasterEintrag`, `RasterArt` (eigen/fremd/gesperrt), `WochenKopf` (KW, blättern, Heute), `montagVon`, `kalenderwoche`, `uhrText`, `tagLangText`; `Kalenderdatei` (.ics), `KalenderTermin` |
| Erinnerungen | `Erinnerungen` (`abgleichen`, `alleEntfernen`), `Erinnerung`; darunter `Benachrichtigung` (`geplant` …) |
| Protokoll | `Protokoll.schreiben` – `~/.local/state/<ordner>/app.log`, nie Tokens |
| Android | Plugin `ch.rosenweg4303.basis`: Anmeldung über commons-rosenweg (`AndroidKonto`: Anmeldeschirm mit Karte, Rosenweg-Konto oder QR-Code, Token aus Kotlin), DNS-Server, Rosenweg Gerät (`ContentResolver.call`), Karte lesen in der App (`NfcKarte`: Reader-Modus mit dem `Kartenleser` aus commons-rosenweg `anmeldeschirm`) |

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

### Rosenweg-Karte lesen (in der App)

Für Apps, die Karten anlernen oder nachschlagen (Rosenweg Karten, Zutritt). Gelesen wird nur die UID, wie `nfc_id` in UniFi Access (`04D4C227C22A81`). Anmelden mit der Karte macht weiterhin der Anmeldeschirm.

```dart
// eine Karte, dann zurück (null = abgebrochen)
final uid = await karteLesen(context, titel: 'Karte anlernen', eintippen: true);

// laufend lesen, solange sichtbar (z. B. Station: Karte auflegen → nachschlagen)
KartenleserBereich(beiKarte: (uid) => nachschlagen(uid), aktiv: !laedt);
```

| Plattform | Leser | Meldung, wenn es nicht geht |
|---|---|---|
| Android | NFC des Handys (Reader-Modus solange sichtbar) | „Dieses Gerät hat kein NFC …“ bzw. „NFC ist ausgeschaltet …“ mit Knopf zu den Einstellungen |
| iOS | Core NFC auf Knopfdruck „Karte lesen“ | „kein NFC“ (auch ohne Developer-Programm/NFC-Berechtigung) |
| Linux, macOS, Windows | USB-NFC-Leser über PC/SC (z. B. ACR122U) | „Kein Kartenleser angeschlossen …“ bzw. „Der Dienst für Kartenleser fehlt (PC/SC) …“; steckt jemand einen ein, liest er von selbst |
| Web | – | „Auf diesem Gerät lassen sich keine Rosenweg-Karten lesen.“ |

`eintippen: true` bietet „Nummer eintippen“ (8, 14 oder 20 Hex-Zeichen, Doppelpunkte erlaubt; `karteUidNormal`). Dieselbe Karte meldet der Leser erst wieder, nachdem sie weg war.

### Dateien hoch- und herunterladen

```dart
final fotos = await dateienWaehlen(context, arten: [DateiArt.bilder], mehrere: true, hoechstens: 20 << 20);
final foto = await fotoAufnehmen(context);                       // Telefon: Kamera; Computer: Bild wählen; verkleinert auf 2000 px
await mitFortschritt(context, 'Foto wird hochgeladen',
    (f) => sitzung.dateien.hochladen('/api/reparatur/7/foto', foto!, multipart: true, feld: 'foto', fortschritt: f));
await sitzung.dateien.hochladen('/api/documents/Ordner/plan.pdf', datei, methode: 'PUT', inhaltstyp: 'application/octet-stream');
final pdf = await sitzung.dateien.herunterladen('/api/vollmachten/7/pdf');
await dateiSpeichern(context, pdf);                              // Computer: „Speichern unter“; Telefon: Teilen
await dateiOeffnen(context, ics);                                // mit der passenden App (z. B. .ics im Kalender)
DateiAblage(mehrere: true, mitFoto: true, gewaehlt: hochladen)   // Knopf + am Computer hineinziehen
```

- Token wie bei der API (`Authorization: Bearer`), bei 401 einmal erneuern, Fehler der API als `ApiFehler` mit dem Text der API.
- **Roh** (Standard): Body = Datei, `Content-Type` der Datei oder `inhaltstyp`, Name im Kopf `X-Filename` (Umlaute URL-kodiert). Die API nimmt je Route nur einen Typ an: `/api/documents` `application/octet-stream`, `upload-signed` `application/pdf`. **Multipart**: `multipart: true`, Feld `feld`, weitere `felder`.
- `bildVerkleinern`: lange Seite auf 2000 px, Drehung aus EXIF, JPEG 85 %, im eigenen Isolate.

| | Wählen | Foto | Speichern | Teilen | Öffnen |
|---|---|---|---|---|---|
| Linux | GTK-Dialog (ohne zenity) | Bild wählen | „Speichern unter“ | – (Speichern) | Standard-App (xdg-open) |
| Windows | Explorer-Dialog | Bild wählen | „Speichern unter“ | Windows-Teilen | Standard-App |
| macOS | Finder-Dialog | Bild wählen | „Speichern unter“ | Teilen-Menü | Standard-App |
| Android | Dateiauswahl des Systems | Kamera | – (Teilen) | Teilen | passende App (FileProvider der Basis), sonst Teilen |
| iOS | Dateien-App | Kamera | – (Teilen → „In Dateien sichern“) | Teilen | – (Teilen) |

### Termine als Kalenderdatei, Erinnerungen

```dart
final ics = Kalenderdatei.datei([
  KalenderTermin(uid: 'stweg3-termin-42@rosenweg4303.ch', titel: 'Eigentümerversammlung',
      beginn: DateTime(2026, 12, 3, 19), ort: 'Gemeinschaftsraum', erinnerung: const Duration(hours: 1)),
], dateiname: Kalenderdatei.dateinameAus('Eigentümerversammlung'));
await dateiOeffnen(context, ics);        // oder dateiTeilen

await Erinnerungen.abgleichen(sitzung, [  // bei jedem Laden: was soll geplant sein?
  Erinnerung(schluessel: 'termin-42', wann: beginn.subtract(const Duration(hours: 1)),
      titel: 'Eigentümerversammlung', text: 'Heute 19:00 · Gemeinschaftsraum', ziel: 'termin/42'),
]);
await Erinnerungen.alleEntfernen();      // beim Abmelden
```

- `Kalenderdatei` (RFC 5545): UTC-Zeiten, ganztags als Datum (Ende = Tag danach), Text maskiert, Zeilen nach 75 Bytes gefaltet, optional `VALARM`. Gleiche `uid` = derselbe Termin (nochmals übernehmen aktualisiert ihn, wo der Kalender das kann). Ohne Ende: 1 Stunde.
- `Erinnerungen.abgleichen` plant die kommenden, ersetzt geänderte und entfernt alle anderen **geplanten** Benachrichtigungen der App (sofort gezeigte bleiben); merkt sich nichts selbst (`Benachrichtigung.geplant`). Android-Kanal „Erinnerungen“. **Geteilte Telefone: nie** – dort entfernt es alles und plant nichts. Linux: nur solange die App läuft.

### Fotos in Formularen, Bilder von der API

```dart
FotoFeld(titel: 'Foto', wert: foto, geaendert: (f) => setState(() => foto = f))   // im RosenwegFormular
GeladenesBild(laden: () => sitzung.dateien.herunterladen('/api/reklamationen/7/foto'))
bildZeigen(context, bytes, titel: 'Foto')                                          // Vollbild mit Zoom
```

- `FotoFeld`: Telefon „Foto aufnehmen“ + „Aus Galerie“, Computer „Bild wählen“ oder Bild hineinziehen; Vorschau mit Grösse, „Entfernen“; verkleinert vor dem Hochladen (Standard 1600 px, JPEG 75 %). `pflicht`, Fehler der API am Feld und „ungespeicherte Änderungen“ wie die anderen Felder.
- `GeladenesBild`: lädt mit der Anmeldung, Antippen = gross; Fehler als Satz mit „Nochmals“.

### Abfrage beim Öffnen (statt Push)

```dart
BeimOeffnen(pruefen: _nachfragen, alle: const Duration(minutes: 5), child: …)
final neu = await Neuigkeiten(await AppSpeicher.app(), 'meine').vergleichen({for (final m in liste) '${m.id}': m.status});
```

- `BeimOeffnen`: fragt beim Start, nach der Rückkehr in den Vordergrund (frühestens nach `mindestAbstand`) und auf Wunsch regelmässig, solange die App vorne ist.
- `AppSpeicher`: kleine JSON-Datei für nicht geheime Werte (`getApplicationSupportDirectory`), sonst nur im Speicher. Geheimnisse gehören in den Schlüsselbund.
- `Neuigkeiten`: merkt sich je Liste den Stand (`id → status`) und liefert, was seitdem neu ist oder sich geändert hat; beim ersten Mal nichts.

### Benachrichtigungen und Abfrage im Hintergrund

```dart
@pragma('vm:entry-point')
void hintergrund() => HintergrundAbfrage.ausfuehren(appAngaben, abfrage);   // oberste Ebene in main.dart

Future<void> abfrage(HintergrundKontext k) async {            // Hintergrund und laufende App
  final neu = await Neuigkeiten(k.speicher, 'meine').vergleichen({...});
  for (final id in neu) await Benachrichtigung.zeigen(id: Benachrichtigung.idFuer('m-$id'), titel: …, text: …, ziel: 'meine/$id');
}

void main() {
  HintergrundAbfrage.anmelden(appAngaben, hintergrund);       // Android, iOS; sonst nichts
  rosenwegStarten(appAngaben, …);
}
// Desktop: BeimOeffnen(alle: 5 min, pruefen: () => HintergrundAbfrage.einmal(app, abfrage, sitzung: s))
await Benachrichtigung.planen(id: …, wann: start.subtract(const Duration(minutes: 15)), titel: 'Waschküche', text: '…');
Benachrichtigung.angetippt.listen((ziel) => …);  await Benachrichtigung.startZiel();
AppVerweise.strom.listen((uri) => …);            // App Links
```

| Plattform | Abfrage | Benachrichtigung |
|---|---|---|
| Android | WorkManager, ~15 min, mit Netz | sofort und geplant; Erlaubnis ab Android 13 (`erlaubnisFragen`) |
| iOS | BGAppRefreshTask (iOS entscheidet) | nach Erlaubnis |
| macOS, Windows | nur solange die App läuft | ja |
| Linux | nur solange die App läuft | sofort; geplant nur solange die App läuft |
| geteilte Telefone | nie | – |

Pflicht je App: Android Core Library Desugaring (siehe CHANGELOG). iOS mit
Hintergrund: `import workmanager_apple`, in `AppDelegate`
`WorkmanagerPlugin.setPluginRegistrantCallback { GeneratedPluginRegistrant.register(with: $0) }`
und `WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "<kennung>.abfrage", earliestBeginInSeconds: 900)`;
Info.plist `BGTaskSchedulerPermittedIdentifiers` = `<kennung>.abfrage`, `UIBackgroundModes` = `fetch`.

App Links (Android): Intent-Filter mit `android:autoVerify="true"` im Manifest der App und
`/.well-known/assetlinks.json` auf dem Web-Server mit Paket und SHA-256 des Rosenweg-Schlüssels.
iOS Universal Links brauchen die Team-ID (Apple Developer Program) – bis dahin öffnet iOS die Web-Seite.

### PDF-Ansicht

```dart
pdfOeffnen(context, titel: 'Vollmacht', laden: () => sitzung.dateien.herunterladen('/api/vollmachten/7/pdf'));
PdfAnsicht(laden: …)     // eingebettet in eine eigene Seite
```

`pdfrx` (PDFium) auf allen fünf Plattformen: Blättern mit Wischen/Rad, Zoom (zwei Finger, Strg+Rad, Knöpfe, Strg/Cmd +/−), „Seite 2 von 5“ mit Vor/Zurück, Bild auf/ab, Pos1/Ende; in `PdfSeite` dazu Speichern und Teilen. Laden mit dem Token der Anmeldung, Fehler mit „Nochmals“.

### Diagramme

```dart
final reihe = Messreihe(titel: 'Temperatur', einheit: '°C', punkte: [Messpunkt(zeit, 4.2), …]);
ZeitraumWahl(gewaehlt: z, geaendert: (neu) => …)                 // 1 h … 7 T (Zeitraum.kurz) oder Tag/Monat/Jahr (Zeitraum.kalender)
Verlaufsdiagramm(reihe: reihe, von: jetzt.subtract(z.dauer), bis: jetzt)
Verlaufsdiagramm(reihe: verbrauch, art: DiagrammArt.balken, nullLinie: true)
Kleinverlauf(reihe: reihe)                                       // ohne Achsen, für Kacheln
```

- `fl_chart` auf allen fünf Plattformen. Zeitachse bis 36 h mit Uhrzeit, darüber mit Datum; Wertachse mit runden Schritten (1, 2, 5, 10 …).
- Antippen bzw. Darüberfahren zeigt „27.11. 14:32 · 4.2 °C“. Bildschirmleser hören „Temperatur: 4.2 °C, zwischen 1.8 °C und 6.0 °C“.
- `null`-Werte und grosse Abstände (dreifacher üblicher Abstand, mindestens 15 min) bleiben Lücken statt gerader Linien.
- Weniger als zwei Werte: ein Satz (`leerText`) statt eines leeren Rasters.
- Farben `diagrammFarben` (in hell und dunkel lesbar); `Messreihe` rechnet kleinster/grösster/letzter Wert und Text mit Einheit.

### Echtzeit (MQTT)

```dart
final mqtt = RosenwegMqtt(MqttZugang.ueberApi(sitzung.api));          // Zugang der Person (POST /api/mqtt/token)
final mqtt = RosenwegMqtt(MqttZugang.fest('wetter-public', '…'));      // öffentlicher Lese-Benutzer aus dem Web-Code
mqtt.abonnieren('wetter/r9/#').listen((n) => werte[n.feld] = n.text); // n.zahl, n.json, n.behalten
EchtzeitAnzeige(quelle: mqtt, veraltetNach: const Duration(minutes: 5))
mqtt.schliessen();                                                     // in dispose
```

- Derselbe Broker und Weg wie die Web-Seiten: `wss://mqtt.rosenweg4303.ch` (WebSocket mit TLS, 443), wahlweise MQTT über TLS (`adresse: 'mqtt.rosenweg4303.ch', port: 8883`). Kein ntfy.
- Verbindet sich selbst wieder (2 s, 4 s … 60 s) und abonniert alles neu; wird der Zugang abgelehnt, holt `ueberApi` einmal einen neuen, danach „kein Zugriff“. `nochmals()` versucht es sofort (Knopf, App wieder vorne).
- Gespeicherte Werte (retained) kommen gleich beim Abonnieren, auch für spätere Abos; sie zählen aber nicht als „live“, weil sie alt sein können. `EchtzeitAnzeige`: grün „live · Stand 14:32“, gelb „wartet auf neue Werte“ bzw. „veraltet“, grau „verbinde …“/„getrennt“ (antippen = nochmals), rot „kein Zugriff“.
- Karten-, QR- und Handy-Sitzungen (`rw_app_…`) bekommen von der API keinen MQTT-Zugang; für öffentliche Daten den festen Lese-Benutzer nehmen.
- Tests und Attrappe ohne Broker: `EchtzeitAttrappe({'thema': 'wert'})`, `senden(…)`, `standSetzen(…)`. Seiten sollten `EchtzeitQuelle` annehmen, nicht `RosenwegMqtt`.

## Beispiel-App

`example/` zeigt jeden Baustein so, wie eine echte App ihn benutzt – ohne Anmeldung und ohne Server (Vorführdaten in `example/lib/attrappe.dart`), auf allen fünf Plattformen:

```sh
cd example && flutter run -d macos        # oder linux, windows, ein Android-/iOS-Gerät
BEISPIEL_ZIEL=1 flutter run -d linux      # gleich mit Seite 1 (Liste) starten; 0 Rechte … 5 PDF
```

Seiten: Rechte (Rolle und Stufe umschalten), Liste (137 Meldungen, Cursor, Filter, Sortierung, Auswahl), Formular (Fehler der API am Feld ausprobieren), Scannen, Dateien (hochladen mit Fortschritt, PDF speichern), PDF, Diagramm (Verlauf mit Zeitraum, Balken, Kleinverlauf, Echtzeit-Anzeige mit erfundenen Live-Werten). Die CI baut sie auf Linux, Android, macOS, iOS (ohne Signatur) und Windows.

## Was jede App einrichten muss

Die Basis bringt die Plugins mit; Berechtigungen stehen aber im Projekt der App (Muster: `example/`).

| Plattform | Eintrag | wofür |
|---|---|---|
| Android `AndroidManifest.xml` | `android.permission.CAMERA`, `<uses-feature android:name="android.hardware.camera" android:required="false"/>` (bringt seit 0.5.2 auch commons-rosenweg mit); NFC bringt die Basis mit | Scannen, Foto, Karte |
| iOS `Info.plist` | `NFCReaderUsageDescription` (+ Entitlement „NFC Tag Reading“, braucht das Apple Developer Program) | Karte lesen |
| macOS `*.entitlements` (beide) | `com.apple.security.smartcard` | USB-Kartenleser (PC/SC) |
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
| Windows-PC der Domäne (verwaltet) | GPO mit Installer `/VERYSILENT /ALLUSERS`; der Updater ist aus, ohne Hinweis (`RosenwegVerwaltet`) |
| Linux (eigener Rechner), macOS, Windows | `RosenwegAktualisierung`: Leiste „Neue Fassung … verfügbar“ → Laden, Grösse und SHA-256 prüfen → Windows: Installer starten; macOS: Disk-Image öffnen; Linux: `pkexec apt-get install` (sonst .deb in „Downloads“ mit Anleitung) |
| iOS | aus (keine Verteilung ausserhalb des App Store) |

Quelle: `https://pbx.rosenweg4303.ch/api/apps/index.json`, Liste `karten`, Eintrag mit `paket` = `RosenwegApp.kennung`. Neue Fassungen kommen dorthin aus der CI der App (Release-Tag, siehe Website `pbx/README.md`). Geprüft wird beim Start (nach 20 s) und alle 12 Stunden; Fehler bleiben im Protokoll.

Station heisst: `/etc/rosenweg-station/station-id` mit einer Station-ID **und** `/etc/rosenweg-station/station.json` – beides legt os-stationen an. „Linux“, „Debian“ oder ein installiertes .deb machen noch keine Station.

Verwaltet (Windows) heisst: die App läuft aus `%ProgramFiles%`/`%WINDIR%` (Installation für alle mit `/ALLUSERS`) **oder** die GPO setzt `Verwaltet` = 1 (DWORD oder Text) unter `HKLM\Software\Policies\Rosenweg` bzw. `HKLM\Software\Rosenweg`. Grund: AppLocker auf den Domänen-PCs lässt normale Benutzer nur Programme aus `%PROGRAMFILES%` und `%WINDIR%` starten – eine Installation pro Person und der Installer, den der Updater aus dem Profil startet, werden dort geblockt. **Auf Domänen-PCs darum nur per GPO mit `/ALLUSERS` verteilen**, auch die Updates.

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
sh werkzeug/logo/app-symbole.sh ../rosenweg-telefonbuch rosenweg-telefonbuch "Rosenweg Telefonbuch" werkzeug/logo/zeichen/telefonbuch.svg bewohner
sh werkzeug/logo/kontaktbogen.sh ~/Downloads/rosenweg-app-logos.png
```

Flutter-Apps: `werkzeug/logo/flutter-apps.txt` legt für alle 39 Apps (Karten ist in Zutritt aufgegangen) Zeichen und Zielgruppe fest (Farbe des Zeichens: Bewohner rot, Verwaltung blau, Technik grün; Rosenweg Stationen trägt unverändert das Logo von os-stationen). `app-symbole.sh` schreibt alle Plattform-Symbole einer App, `kontaktbogen.sh` setzt alle Logos nebeneinander zum Vergleichen. Neue Zeichen aus Material Symbols (Apache-2.0): `werkzeug/logo/zeichen-zusammensetzen.py`; Herkunft: `werkzeug/logo/zeichen/LIZENZEN.md`.

Für die Android-Apps (Fossify-Forks, Rosenweg Karten, Rosenweg Gerät, Rosenweg Kiosk) steht in `werkzeug/logo/android-apps.txt`, welche App welches Zeichen trägt; `android-apps.sh` schreibt Mipmaps, adaptive Icon und monochromes Designsymbol. Mehr: [docs/logos.md](docs/logos.md).

## Neue App anlegen

Jede Portal-Funktion wird eine eigene App (Plan „Alle Portal-Funktionen als Flutter-Apps“). Damit nicht jede App Anmeldung, Plattform-Ordner, Installer, Logo und CI neu erfindet, gibt es die **App-Vorlage** `vorlage/` und das Skript `werkzeug/neue-app.sh`.

### Was die Vorlage mitbringt

`vorlage/` ist selbst eine baubare App („Rosenweg Vorlage“, Kennung `ch.rosenweg4303.vorlage`), abgeleitet aus rosenweg-salz, rosenweg-profil und rosenweg-vm:

| Teil | Inhalt |
|---|---|
| Start | `rosenwegStarten`: Logdatei, Fehlerfang, Anmeldeschirm der Basis (Karte, QR, Konto; Station still per Kerberos; geteiltes Telefon über Rosenweg Gerät), Updater |
| Seiten | `RosenwegGeruest` mit zwei Bereichen (Handy: unten, ab 840 px: Leiste links), Menü „Anmeldung“, „Über“, „Abmelden“ (nicht auf geteilten Telefonen), Beispiel-API-Aufruf mit Laden/Fehler/Nochmals |
| Deutsch | de-CH, auch Flutters eigene Dialoge (aus `RosenwegRahmen`) |
| Attrappe | `lib/attrappe.dart`, `--dart-define=RW_ATTRAPPE=1`: ohne Server; Widget-Tests Handy/Desktop/Fehler; Bildschirmfotos mit `RW_FOTO=…` |
| Fenster | kleinste Grösse 400×560 auf Linux, macOS, Windows |
| Linux | `linux/paket/bauen.sh` → `.deb` (Debian 13, `/opt/<app>`, hicolor-Symbole, Starter `ch.rosenweg4303.<k>.desktop`), `im-container.sh` für den Bau-Container, `paket.conf` = Vorlage für os-stationen `pakete/<app>/` (PXE-Server) |
| Android | Signatur über `SIGNING_*` (Org-Secrets), minSdk 26, adaptive + monochrome Symbole |
| Windows | Inno-Setup-Installer pro Person ohne Adminrechte (`windows/installer/<app>.iss`, eigene AppId je App) |
| macOS | `macos/installer/bauen.sh`: App (ad hoc oder Developer ID, Notarisierung wenn Secrets da) + DMG mit eigenem Hintergrund |
| iOS | baut ohne Signatur |
| CI | `.github/workflows/app.yml` und `apps.yml` rufen die wiederverwendbaren Workflows dieser Basis |
| /apps | `apps-eintrag.json` für das App-Register, `assets/logo/<app>-192.png` |

### Anlegen

```sh
cd rosenweg-basis
werkzeug/neue-app.sh telefonbuch "Rosenweg Telefonbuch" telefonbuch
werkzeug/neue-app.sh mail-freigabe "Rosenweg Mail-Freigabe" mail-freigabe \
    --gruppe verwaltung --beschreibung "Mails der Verwaltung prüfen und freigeben."
```

| Argument / Option | Bedeutung |
|---|---|
| `<name>` | kurz, z. B. `mail-freigabe` → Repo `rosenweg-mail-freigabe`, Dart `rosenweg_mail_freigabe`, Kennung `ch.rosenweg4303.mailfreigabe` (ohne Bindestrich: Java-Paket und Rücksprung-Schema `ch.rosenweg4303.mailfreigabe:/anmeldung`) |
| `"<Anzeigename>"` | wie im Startmenü; Umlaute gehen (Dateinamen werden zu `ae/oe/ue`, Windows-Quelltext bekommt `\u`-Folgen, das Inno-Skript ein BOM, die macOS-Programmdatei heisst wie das Dart-Paket) |
| `<zeichen>` | Name aus `werkzeug/logo/zeichen/` (alle 41 Apps aus `werkzeug/logo/flutter-apps.txt` haben eines) oder Pfad zu einem SVG |
| `--gruppe` | Farbe des Zeichens: `bewohner` rot, `verwaltung` blau, `technik` grün; Vorgabe aus `flutter-apps.txt` |
| `--beschreibung` | ein Satz für „Über“, Paketbeschreibung, Startmenü, /apps |
| `--ziel <ordner>` | Standard: neben der Basis (`../rosenweg-<name>`) |
| `--basis-ref`, `--workflow-ref` | Stand von `rosenweg_basis` in `pubspec.yaml` (Standard wie in `vorlage/`, derzeit `v0.8.8`) und der Workflows (Standard `main`) |
| `--basis-lokal <pfad>` | `pubspec_overrides.yaml` auf eine lokale Basis (dann wird `pubspec.lock` nicht committet) |
| `--ohne-pub`, `--ohne-git` | kein `flutter pub get` / kein erster Commit |
| `--repo` | **zusätzlich** `Rosenweg/rosenweg-<name>` auf GitHub anlegen (privat) und `main` pushen – ohne den Schalter geschieht nichts auf GitHub |

Das Skript kopiert die Vorlage, ersetzt alle Namen (es bricht ab, wenn ein Platzhalter übrig bleibt), erzeugt alle Symbole (`werkzeug/logo/app-symbole.sh`), legt `git` mit einem ersten Commit an und druckt die Schritte ausserhalb des Repos.

### Danach (einmal je App)

1. **Authentik** (`rosenweg-apps`): Rücksprung `ch.rosenweg4303.<k>:/anmeldung` (strikt) eintragen – Desktop braucht nichts (`localhost`-Regex gilt für alle).
2. **GitHub**: Repo anlegen (oder `--repo`), dann
   - Org-Secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` für das Repo freigeben (ohne: Debug-Signatur, kein Release),
   - kein `BASIS_TOKEN` und keine Runner-Gruppe: rosenweg-basis ist öffentlich, alle Jobs laufen auf GitHub-Runnern (`ubuntu-latest`, das `.deb` im Container `debian:13`; `windows-latest`, `macos-latest`). Eigene Runner nie, auch nicht für Releases.
3. **/apps**: `apps-eintrag.json` in `apps-register.json` (Rosenweg/Website, Abschnitt `apps`) übernehmen, `assets/logo/<app>-192.png` als `img/apps/<app>.png` ins Website-Repo. Ohne Register-Eintrag nimmt die Anlage keine Releases an.
4. **Android-Updater**: der Rosenweg Updater (commons-rosenweg `updater`) kennt die Pakete der Flutter-Apps; neue Kennung dort ergänzen, sonst prüft auf Handys mit nur Flutter-Apps niemand.
5. **Stationen**: in `.github/workflows/app.yml` `stationen_seite` auf die Web-Seite setzen, die die App auf den Stationen ersetzt (Kennung aus `/api/stations/<id>/apps`), und die Org-Secrets `PAKETE_APP_ID`, `PAKETE_APP_KEY` (GitHub App „Rosenweg Pakete“) für das Repo freigeben. Dann öffnet jedes Release selbst einen PR in os-stationen (`pakete/<app>/paket.conf`, beim ersten Mal aus `linux/paket/paket.conf`); os-stationen lädt das .deb mit dem Label `paket-update` auf den PXE-Server. Mergen von Hand. Ohne App: wie bisher von Hand kopieren und eintragen.
6. Inhalt bauen (`lib/seiten/`, `lib/attrappe.dart`, `docs/anleitung.md`) aus den [Bausteinen für Apps](#bausteine-für-apps), Bedienung auf Handy **und** Station prüfen.
7. Berechtigungen für Kamera, NFC und Dateien eintragen – siehe [Was jede App einrichten muss](#was-jede-app-einrichten-muss) (die Vorlage hat sie schon).

### Bau und Release (wiederverwendbare Workflows)

| Workflow (hier) | Aufgabe |
|---|---|
| `.github/workflows/app.yml` | `workflow_call`: Version lesen → Linux (analyze, test, `.deb`) und Android (APK, Signatur und Paketname geprüft) immer; Windows (Installer + Rauchtest), macOS (DMG), iOS (unsigniert) bei öffentlichem Repo immer, bei privatem nur für ein Release, von Hand oder mit `alle_plattformen`; alles auf GitHub-Runnern; Signier-Secrets nur bei Push auf main bzw. Tag `v*` (bei PR Debug-Signatur); bei `veroeffentlichen` und **neuem** Tag `v<version>`: GitHub-Release, sobald Linux und Android durch sind; Windows, macOS und iOS laden ihre Dateien danach ins bestehende Release (Job `nachtrag`, auch wenn eine davon scheitert – das Release bleibt, der Text nennt fehlende Plattformen und warum), `SHA256SUMS` über alles, dann `apps.yml` der App für den Tag starten |
| `.github/workflows/app-apps.yml` | `workflow_call`: Dateien des Release-Tags an /apps (Action `Rosenweg/Website/.github/actions/apps-release`, GitHub-OIDC) |
| `.github/workflows/vorlage.yml` | prüft hier selbst: `neue-app.sh` (Probe mit Bindestrich und Umlaut, analyze + test) und die Vorlage gegen diesen Stand der Basis: bei PR/Push Linux und Android, alle fünf Plattformen nur von Hand (`gh workflow run vorlage.yml --ref <zweig>`) |

In der App: PR → CI; Merge auf `main` mit erhöhter `version:` → Release und /apps; ohne neue Version nur CI. Kein Tag von Hand nötig.

rosenweg-basis ist öffentlich: andere Repos rufen die Workflows ohne weitere Freigabe auf. Die Aufrufer reichen Secrets einzeln und nur bei Push auf main weiter (kein `secrets: inherit`), siehe `vorlage/.github/workflows/app.yml`.

### Grenzen je Plattform

| Plattform | Grenze |
|---|---|
| iOS | nur Bau ohne Signatur; Verteilen, Core NFC und Push brauchen das Apple Developer Program; /apps kennt kein iOS |
| macOS | ohne Developer-ID-Zertifikat ad hoc signiert, Gatekeeper fragt beim ersten Start; Secrets `MACOS_*`/`NOTAR_*` schalten Signatur und Notarisierung ein |
| Windows | ohne Zertifikat unsigniert (SmartScreen fragt einmal); `WINDOWS_ZERTIFIKAT_*` signiert App und Installer |
| Linux | `.deb` nur Debian 13/amd64; Kamera (`mobile_scanner`) und WebView fehlen unter Linux – Desktop-Ersatz vorsehen |
| Android | Release nur mit dem Rosenweg-Schlüssel; Updater nur, wenn commons-rosenweg die Kennung kennt |

## Prüfen und CI

```sh
flutter analyze && flutter test
```

Dasselbe läuft bei jedem Push und PR in `.github/workflows/pruefen.yml` auf einem GitHub-Runner (inkl. `example/`). `.github/workflows/beispiel.yml` baut die Beispiel-App auf allen fünf Plattformen, ebenfalls auf GitHub-Runnern – so fällt auf, wenn ein Plugin auf einer Plattform nicht mehr baut. Keine Secrets nötig. Änderungen stehen in [CHANGELOG.md](CHANGELOG.md).

**Neue Fassung an die Apps:** Ein Tag `v*` startet `.github/workflows/abhaengige.yml`: jedes Repo der Organisation, das `rosenweg_basis` als Git-Abhängigkeit nutzt, bekommt einen PR „rosenweg_basis vX.Y.Z“ (`ref`, `pubspec.lock`, Patch-Version der App); hier die Vorlage. Die Apps werden gefunden, nicht aufgezählt. Ablauf und Zugang (GitHub-App bzw. Token): commons-rosenweg `.github/abhaengige/README.md`.

## Weitere Dokumente

| Datei | Inhalt |
|---|---|
| [docs/entwickeln.md](docs/entwickeln.md) | Beispiel, öffentliche API im Detail mit Herkunft |
| [docs/bedienung.md](docs/bedienung.md) | Bedienung, gleich in allen Apps |
| [docs/anmeldeschirm.md](docs/anmeldeschirm.md) | Anmeldeschirm je Plattform (Karte, Konto, QR), Karten-Sitzung, was die Apps einrichten |
| [docs/authentik.md](docs/authentik.md) | was in Authentik eingetragen sein muss, Kerberos |
| [docs/geteilte-telefone.md](docs/geteilte-telefone.md) | Schnittstelle zu Rosenweg Gerät, Personenwechsel |
| [docs/logos.md](docs/logos.md) | Logo-Baukasten |
| [docs/gruppenfarbe.md](docs/gruppenfarbe.md) | Farbe nach der angemeldeten Person: Thema, Logo, Startsymbol |
| [docs/rosenweg-vm-umstellen.md](docs/rosenweg-vm-umstellen.md) | was rosenweg-vm für die Umstellung auf die Basis ändern müsste |

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE).
