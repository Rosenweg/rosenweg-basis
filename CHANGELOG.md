## 0.6.0 (unveröffentlicht)

Welle 0 des Flutter-Plans: Bausteine, die fast jede Portal-App braucht
(Prio A), mit Beispiel-App `example/` für alle fünf Plattformen.

- **Rechte** (`rechte.dart`, `rechte_bausteine.dart`): `sitzung.rechte`
  lädt `GET /api/auth/me` (`permissions`, `groups`), Technik/Präsident
  dürfen alles wie `requirePermission`; `sitzung.darf(seite, zugriff)`,
  Widget `NurMit` (recht / eines / stufe, unsichtbar oder einheitlicher
  Hinweis „Keine Berechtigung“), `RechteBereich` legt `RosenwegRahmen` selbst
  an. Neu geladen nach Abmelden, Personenwechsel, Bestätigen.
  - **Stufe der Anmeldung** `karte` < `konto` < `konto-frisch` aus
    `user.anmeldung.stufe` (+ `frisch_bis`) – Feld liefert die API künftig
    (Plan 4.2.1); bis dahin Schätzung aus der eigenen Anmeldung.
    `StufeNoetigAnzeige` mit „Mit Rosenweg-Konto anmelden“.
  - `mitBestaetigung`: 403 mit `reauth` oder `stufe` → fragen, frisch
    anmelden, einmal nochmals. `KeineBerechtigung.stufeNoetig`.
  - `RosenwegSitzung.bestaetigtUm`.
- **Listen** (`liste.dart`, `liste_ansicht.dart`): `ListenSteuerung`
  (Cursor `nach`/`naechster` nach Plan 4.2.4, `Blaettern.offset`, oder
  `.lokal`), `apiListe`, `RosenwegListe`: Suche, Filter-Chips, Sortierung,
  Ziehen zum Neuladen, automatisch weiterladen, Mehrfachauswahl;
  Handy-Kacheln, ab 840 px Tabelle mit Kopfzeile; F5/Strg+R.
- **Formulare** (`formular.dart`): `RosenwegFormular` (Prüfen,
  Speichern-Zustand, Fehler der API am Feld über `feld`/`felder`, sonst oben;
  „Änderungen verwerfen?“, Strg/Cmd+S), Felder `TextFeld`, `BetragFeld`
  (Rappen), `DatumFeld`, `ZeitFeld`, `AuswahlFeld`, `SchalterFeld`,
  `SuchAuswahlFeld`; `Pruefen`, `loeschenBestaetigen`.
  `ApiFehler.feldFehler`.
- **Scannen** (`scanner.dart`): `codeScannen` – Kamera auf Android, iOS,
  macOS (`mobile_scanner`), sonst Feld für Hand-Scanner/Tastatur; überall
  „QR-Code aus Bild lesen“ (`qrAusBild`, zxing2, reines Dart). Muster aus
  rosenweg-salz.
- **Dateien** (`netz/dateien.dart`, `dateien_bausteine.dart`):
  `sitzung.dateien` (`RosenwegDateien`) lädt roh oder multipart hoch und
  herunter, Bearer-Token, 401 → einmal erneuern, Fortschritt; geteilte
  Telefone: verständlicher Fehler. `dateienWaehlen` (file_selector, Linux
  ohne zenity), `fotoAufnehmen` + `bildVerkleinern`, `dateiSpeichern`
  („Speichern unter“ bzw. Teilen), `dateiTeilen`, `DateiAblage` (Drag & Drop
  am Computer), `mitFortschritt`, `TransferAnzeige`.
- **PDF** (`pdf_ansicht.dart`): `PdfAnsicht`, `PdfSeite`, `pdfOeffnen`
  (pdfrx 3, alle fünf Plattformen; Seiten, Zoom, Tastatur, Speichern/Teilen).
- **Schlüsselbund unter Linux:** fragt vor dem ersten Zugriff den Secret
  Service (`busctl … ReadAlias default`); ohne Standard-Sammlung gleich
  „nur im Speicher“, statt dass libsecret „Neuen Schlüsselbund anlegen“
  öffnet. Aus rosenweg-vm (`PruefenderSpeicher`), jetzt für alle Apps.
- `apiAntwortPruefen` (gemeinsam für API und Dateien).
- CI: `example/` wird mitgeprüft; neuer Workflow `beispiel.yml` baut die
  Beispiel-App auf Linux, Android, macOS, iOS und Windows.
- Neue Abhängigkeiten: mobile_scanner, file_selector, image_picker,
  share_plus, pdfrx, desktop_drop, zxing2, image,
  http_parser. Apps brauchen Kamera-/Datei-Berechtigungen (README).

## 0.5.2

- Android: `ch.rosenweg4303:cloud` 0.9.0 → **0.13.4** (commons-rosenweg). Der
  native Anmeldeschirm hat jetzt wie in den Kotlin-Apps „QR-Code scannen“
  (Karte – Konto – QR, wie der Sperrbildschirm von Rosenweg Gerät; QR von
  `rosenweg4303.ch/smartphones` → „App auf eigenem Handy“). Das Modul bringt
  `android.permission.CAMERA` und `uses-feature camera` (`required=false`) ins
  Manifest der App; gefragt wird erst beim Tippen, der Knopf erscheint nur mit
  Kamera. Schnittstelle für das Plugin unverändert (`RosenwegAnmeldung`,
  `RosenwegAnmeldeSchirm` mit `startActivityForResult`, `RESULT_OK` =
  angemeldet). Dart-Seite unverändert.
- `ch.rosenweg4303:updater` bleibt 0.1.4 (kommt jetzt auch über cloud mit).

## 0.5.1

Mängel aus dem Test auf win11-1 (Windows 11, Domänen-PC):

- `Protokoll.schreiben`: Windows-App ohne Konsole (Start übers Startmenü)
  schrieb nach einem ungültigen stderr; der Fehler kam asynchron
  (`FileSystemException: writeFrom failed`) am try/catch vorbei und setzte
  die App kurz auf „Fehler“. Jetzt: auf Windows nur mit Konsole, Pipe oder
  Datei; Fehler des Sinks werden überall abgefangen, danach schweigt stderr.
- Kartenleser: ins Protokoll nur noch ein Zustandswechsel (kein PC/SC,
  kein Leser, n Leser, Fehler) statt alle 3 s „Kartenleser: kein PC/SC“.
- Verständliche Fehler: `fehlerFuerPerson(e)` liefert einen deutschen Satz
  und die Technik getrennt; `FehlerAnzeige(details:)` bzw.
  `FehlerAnzeige.aus(e)` zeigt die Technik zugeklappt unter „Details“.
  `RosenwegSitzung.fehlerDetails`, `fehlerText` ohne rohe Ausnahmen.
  `BrowserNichtGeoeffnet` statt `StateError('Browser liess sich nicht oeffnen')`.
- Updater aus bei verwalteter Installation (`RosenwegVerwaltet`): .exe unter
  Program Files/Windows (Installation mit `/ALLUSERS`) oder GPO-Schalter
  `HKLM\Software\(Policies\)Rosenweg\Verwaltet` = 1. Sonst gilt die Regel
  unverändert.

## 0.5.0 (unveröffentlicht)

- **Updater für alle Flutter-Apps** (Regel Stefan: jede Rosenweg-App
  aktualisiert sich selbst; aus nur, wo andere aktualisieren).
  - Computer: `RosenwegAktualisierung` liest den Katalog
    `pbx.rosenweg4303.ch/api/apps/index.json` (`karten`, `paket` = Kennung),
    vergleicht mit der installierten Fassung, lädt nach einem Klick, prüft
    Grösse und SHA-256 und installiert: Windows Installer starten (App endet),
    macOS Disk-Image öffnen, Linux `pkexec apt-get install` (sonst .deb in
    „Downloads“ mit Anleitung). `AktualisierungsLeiste` oben in der App
    („Neue Fassung … verfügbar“ · Später · Aktualisieren); `rosenwegStarten`
    und `RosenwegRahmen(aktualisierung:)` binden sie ein.
  - Aus auf Rosenweg-Stationen (os-stationen bringt die Pakete), ohne
    Hinweis: `RosenwegStation.erkannt` (`/etc/rosenweg-station/station-id`
    und `station.json`; NICHT „Linux“/„Debian“ – eigene Debian-Rechner
    bekommen Updates). Aus auf iOS und in Entwicklungsbauten.
  - Android: `ch.rosenweg4303:updater` 0.1.4 direkt im Android-Teil (kennt
    VM, Salz, Profil; aus mit Rosenweg Gerät). Braucht commons-rosenweg mit
    Updater 0.1.4 (veröffentlicht mit dem nächsten Tag).
- `RosenwegSitzung.zugang` und `.nichtMehrAngemeldet()`: Token der aktiven
  Anmeldung für eigene Dienste einer App (rosenweg-vm: vm-gateway), mit
  demselben Verhalten bei 401 wie die Haupt-API.

## 0.4.0

- Gerüst für Handy und Desktop: `RosenwegGeruest` (AppBar; mit zwei oder
  mehr `GeruestZiel` unten eine NavigationBar, ab 840 px eine
  NavigationRail links, ab 1200 px beschriftet; Inhalt am Desktop mittig
  mit begrenzter Breite), `RosenwegSpalten` (ab 840 px zwei Spalten, sonst
  unverändert das Handy-Layout), `RosenwegInhalt` und `Fensterklasse`
  (600/840/1200 px nach Material 3). Unter 840 px ändert sich nichts.
- `rosenwegThema`: Dialoge höchstens 560 px breit.

## 0.3.0

- **Anmeldeschirm wie auf Android** (`RosenwegAnmeldeSchirm`, ersetzt den
  alten `AnmeldeSchirm`; der Name bleibt als Alias): blau, Rosenweg-Siegel,
  „<App> · zum Benutzen anmelden“, „Die Anmeldung gilt nur für <App>.“
  - iOS: Rosenweg-Karte per Core NFC (Knopf), QR-Code per VisionKit,
    Rosenweg-Konto im Browserfenster der App. Neuer iOS-Teil des Plugins
    (CocoaPods und Swift Package Manager).
  - Desktop: Karte über USB-NFC-Leser (PC/SC per FFI; ohne Leser
    ausgeblendet), Rosenweg-Konto, „Mit dem Handy anmelden“ (Computer zeigt
    QR, Handy bestätigt im Portal; Website `/app-anmelden`).
  - Android unverändert: nativer Schirm aus commons-rosenweg.
- `KartenSitzung`: Karten-, QR- und Handy-Sitzung für Desktop und iOS
  (Gerätschlüssel EC P-256, Erneuern mit Unterschrift), gleicher Server wie
  commons-rosenweg. `RosenwegSitzung.karte`, `.stand` (`Anmeldestand`,
  `AnmeldeArt`), `.ohneBrowserAngemeldet()`.
- `AnmeldungKarte` / `zeigeAnmeldung`: Anmeldung in den Einstellungen mit
  echtem Stand (angemeldet als, womit, gilt nur für diese App, Abmelden).
- `RosenwegApp(ohneBrowser: false)` für Apps, die ein Authentik-Token
  brauchen (Rosenweg VM): nur Rosenweg-Konto.
- Konto und Karte teilen sich EINEN Schlüsselbund-Eintrag.
- Neue Abhängigkeiten: `pointycastle`, `qr_flutter`.

## 0.2.0 (unveröffentlicht)

- Android ohne Rosenweg Gerät: Anmeldung über commons-rosenweg (`cloud`
  0.9.0) statt in Dart. `AndroidKonto`/`AndroidKontoKanal` zeigen
  den gemeinsamen Anmeldeschirm `RosenwegAnmeldeSchirm`, derselbe wie der
  Sperrbildschirm der geteilten Telefone: Rosenweg-Karte oder
  Rosenweg-Konto, die Karte allein ohne PIN. Token und Karten-Sitzung liegen
  in Kotlin; jede App meldet sich selbst an. Die Sitzung öffnet den Schirm
  beim Start und nach „Abmelden“ selbst.
  - Das Plugin braucht `ch.rosenweg4303:cloud` aus mavenLocal und **minSdk 26**.
  - Den Rücksprung `<applicationId>:/anmeldung` nimmt jetzt
    `RosenwegAnmeldungActivity` aus commons an; die eigene `RuecksprungActivity`
    ist weg.
  - Wer in einer Flutter-App unter Android schon angemeldet war, meldet sich
    einmal neu an.
  - Auf dem Desktop bleibt alles wie bisher.

- Stille Anmeldung mit dem Kerberos-Ticket der Sitzung (Linux-Stationen,
  Windows-Domäne): `RosenwegKonto.stillAnmelden()`, `StilleAnmeldung`,
  `KerberosTicket` (GSS-API / SSPI per FFI). Die Sitzung versucht sie beim
  Start, beim Knopf und nach widerrufenem Refresh-Token; sonst Browser wie
  bisher. Neue Abhängigkeit `ffi`; Linux-Paket braucht `libgssapi-krb5-2`.
- Geteilte Telefone: `portal_anfrage` ist in Rosenweg Gerät gebaut (ab v236,
  über die Telefonanlage). `GeraetTransport` liest die Sitzungsmarke; bei
  einem Personenwechsel (Marke oder Broadcast `ANGEMELDET`/`ABGEMELDET` von
  Gerät) baut `RosenwegRahmen` die ganze App neu (`personStand`).

## 0.1.0 (26.11.2026)

- Erste Fassung: Anmeldung (Authentik rosenweg-apps, PKCE; Desktop über
  localhost, Android über `<applicationId>:/anmeldung`), Schlüsselbund mit
  Rückfall ohne Secret Service, API-Client (JSON, 502/HTML, 429, 401 mit
  einmaligem Erneuern), Haus-Erkennung (TXT), Sitzung und Anmeldetor,
  Thema/Farben, Bausteine (Anmeldeschirm, Fehler, Über mit GPL, Abschnitt,
  Hinweis), Logo-Baukasten (Turm + Weg + Rose, App-Zeichen als Plakette).
- Schnittstelle zu Rosenweg Gerät für geteilte Telefone (Vorschlag
  `portal_anfrage`, dort noch nicht gebaut).
