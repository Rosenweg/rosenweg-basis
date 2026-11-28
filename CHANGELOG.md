## 0.8.4 – Gruppenfarbe nach der angemeldeten Person

- **Gruppenfarbe nach der angemeldeten Person** (Entscheid Stefan
  28.11.2026, docs/gruppenfarbe.md): `RosenwegApp.gruppe` ist jetzt die
  Mindestfarbe. Mit `farbGruppen` (und optional `farbRechte`) nennt die App,
  wo sie mehr freischaltet: Technik/Präsident grün, Ausschuss/Verwaltung blau.
  `sitzung.farbe` (`GruppenFarbe`) setzt die Farbe aus `/api/auth/me`; Thema,
  Anmeldeschirm und das neue `FarbLogo` folgen live. Abmelden setzt auf die
  Mindestfarbe zurück, geteilte Telefone folgen der Person, die letzte Farbe
  wird gemerkt (kein Flackern beim Start).
- Thema in der Gruppenfarbe (`rosenwegThema(helligkeit, gruppe)`, Material 3
  `fidelity`) statt des festen Grundtons #8B1E3F.
- Startsymbol je Farbe: Android `activity-alias` `.Symbol<Farbe>`, umgeschaltet
  per `setComponentEnabledSetting` nur bei Wechsel (`Startsymbol.kt`); iOS
  alternate icons (`setAlternateIconName`); Desktop nur in der App.
- Logo-Baukasten: `FARBEN="verwaltung technik"` in `erzeugen.sh` /
  `app-symbole.sh` erzeugt Logos, Android- und iOS-Symbole je Farbe;
  `farben-einbauen.py` baut Aliasse und Xcode-Einstellung ein;
  `neue-app.sh --farben`, `flutter-apps.txt` Spalte 6; Android-Apps:
  `android-apps.txt` Spalte 7 (Messenger: Symbole fuer die Fossify-Aliasse
  `.Blue`/`.Teal`, commons `RosenwegGruppenFarbe`).

## 0.8.3 – Kalenderdatei, Erinnerungen, dateiOeffnen

Für Rosenweg Termine; allgemein für jede App mit Terminen (Waschküche,
Projekte, Handwerker). Baut auf 0.8.0 (Benachrichtigungen) auf.

- **`Kalenderdatei`** / **`KalenderTermin`**: Termine als .ics (RFC 5545)
  zum Teilen oder Öffnen in jedem Kalender – UTC, ganztags, Maskierung,
  Faltung nach 75 Bytes, `VALARM`; `dateinameAus(titel)`.
- **`Erinnerungen`**: `abgleichen(sitzung, [Erinnerung …])` plant kommende,
  ersetzt geänderte, entfernt weggefallene geplante Benachrichtigungen;
  `alleEntfernen()`. Nie auf geteilten Telefonen (entfernt dort alles).
- **`Benachrichtigung.geplant()`**: Ids der geplanten Benachrichtigungen;
  die Attrappe ersetzt jetzt wie das System eine gleiche Id.
- **`dateiOeffnen(context, datei)`**: mit der passenden App öffnen
  (Android ACTION_VIEW über einen FileProvider der Basis,
  `<applicationId>.rosenweg.dateien`, nur `cache/rosenweg-oeffnen/`;
  Desktop Standard-App; iOS Teilen). Android: `androidx.core` im Plugin.

## 0.8.2 – Diagramme und Echtzeit (MQTT)

Bausteine Diagramme und Echtzeit (Flutter-Plan Welle 2, Priorität B; Pilot
Rosenweg Wetter, danach Energie, ZEV, NOC, Anzeigen):

- **Diagramme** (`fl_chart`): `Verlaufsdiagramm` als Linie oder Balken mit
  Zeitachse (bis 36 h Uhrzeit, sonst Datum), runden Schritten auf der
  Wertachse, Lücken bei fehlenden Werten, Antippen = Zeit und Wert, Satz
  statt leerem Raster bei zu wenig Werten; `Kleinverlauf` für Kacheln;
  `ZeitraumWahl` mit `Zeitraum.kurz` (1 h … 7 T) und `Zeitraum.kalender`
  (Tag/Monat/Jahr); `Messreihe`/`Messpunkt`, `diagrammFarben`.
- **Echtzeit über MQTT** (`mqtt_client`): `RosenwegMqtt` über den Broker der
  Anlage wie die Web-Seiten (`wss://mqtt.rosenweg4303.ch`, wahlweise 8883),
  Zugang fest (öffentlicher Lese-Benutzer) oder über `POST /api/mqtt/token`,
  Wiederverbinden mit Rückoff und Neu-Abonnieren, retained-Werte sofort,
  aber nicht als „live“ gezählt; `EchtzeitAnzeige` (live / wartet / veraltet
  / getrennt / kein Zugriff); `EchtzeitAttrappe` für Tests. Kein ntfy.
- Beispiel-App: Seite „Diagramm“.

## 0.8.1

- Wochenraster: `RasterArt.gesperrt` neutral grau mit Rand (vorher blass im
  Thema-Ton, kaum von fremden Terminen zu unterscheiden) – für die Sperrzeiten
  der Waschküche.
- Logo-Liste (`werkzeug/logo/flutter-apps.txt`): Repo der Mail-Freigabe heisst
  `rosenweg-mailfreigabe` (wie auf GitHub).

## 0.8.0 – Benachrichtigungen, Hintergrund, App-Links

Entscheid Stefan 27.11.2026: echte Benachrichtigungen, auch im Hintergrund,
ohne ntfy.

- **`Benachrichtigung`** (flutter_local_notifications): `einrichten`,
  `erlaubnisFragen`, `zeigen`, `planen` (Erinnerung zu einer Zeit, z. B.
  Waschküche 15 Minuten vor dem Start), `entfernen`, `angetippt`/`startZiel`
  (Antippen → Ziel in der App). Android, iOS, macOS, Windows; Linux sofort,
  geplant nur solange die App läuft.
- **`HintergrundAbfrage`** (workmanager): Android WorkManager etwa alle
  15 Minuten mit Netz, iOS BGAppRefreshTask `<kennung>.abfrage` (iOS
  entscheidet selbst, wann); Desktop nur in der laufenden App
  (`HintergrundAbfrage.einmal` aus `BeimOeffnen`). Meldet nur mit
  bestehender Anmeldung still an (`RosenwegSitzung.hintergrundStarten`), nie
  auf geteilten Telefonen (wechselnde Personen). Eigener Speicher
  `hintergrund.json` (`AppSpeicher.app('hintergrund')`).
- **`AppVerweise.strom`** (app_links): Android App Links / iOS Universal
  Links / Desktop-Verweise an die App.
- Android-Manifest der Basis: Empfänger für geplante Benachrichtigungen,
  `RECEIVE_BOOT_COMPLETED` (POST_NOTIFICATIONS bringt das Plugin).

**Jede App muss beim Wechsel auf diese Fassung** in
`android/app/build.gradle.kts` Core Library Desugaring einschalten
(`isCoreLibraryDesugaringEnabled = true` und
`coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`), sonst
bricht der Android-Bau ab. Vorlage und Beispiel haben es. Apps mit
`HintergrundAbfrage` auf iOS: AppDelegate und Info.plist wie im README.

## 0.7.1

- **macOS-Update über den Browser** (Test 27.11.2026 auf dem Mac): Ein
  Disk-Image, das die App in ihrer Sandbox lädt, bekommt die Quarantäne
  „created by an AppSandbox“; die daraus nach „Programme“ kopierte App liess
  sich danach nicht mehr öffnen (`exec/open not allowed`, Fehler -10810).
  Jetzt öffnet „Aktualisieren“ bzw. „Installieren“ auf dem Mac den Download
  im Browser (wie /apps); macOS prüft und fragt wie bei der ersten
  Installation.
- Geräte-Kennung fürs NOC: Rückfall auf eine zufällige Kennung im Ordner
  der App, wenn es keine Maschinen-ID gibt (z. B. macOS-Sandbox ohne
  `ioreg`).
- Abschnitt „Updates“ im Stil der neuen Update-Seite des Android-Updaters:
  Karte mit Logo, Fassung „alt → neu“, Statuszeile mit Ladebalken, grosser
  Knopf in der Gruppenfarbe.
- Android: updater 0.1.8 / cloud 0.13.8 – neue Update-Seite (Gruppenfarbe,
  je App eine Karte, hell/dunkel, Ränder), Recht „Unbekannte Apps
  installieren“ vorher prüfen (auch nach Prozess-Ende zurück zur Seite),
  Play-Protect-Ablehnung mit Anleitung und „Nochmals versuchen“,
  Benachrichtigung „wartet auf Bestätigung“, Installationen über die
  Session-ID (Befunde A37).

## 0.7.0

- **Wochenraster** (Kalender-Raster für Belegungen; zuerst für Rosenweg
  Waschküche, gebaut nach dem Kalender von `waschkueche.html`):
  `Wochenraster<T>` zeigt eine Woche mit Stunden (Standard 06–22 Uhr) und
  Blöcken (`RasterEintrag`: von, bis, Titel, Art `eigen`/`fremd`/`gesperrt`,
  `daten`). Breiter als 600 px alle sieben Tage, schmaler ein Tag mit den
  sieben Tagen zum Antippen darüber. Tippen in eine freie Stelle liefert den
  Zeitpunkt (abgerundet auf 15 Minuten), Tippen auf einen Block den Eintrag.
  Rote Linie = jetzt (jede Minute nachgeführt), vergangene Tage grau, ein
  laufender Termin grün umrandet; beim Öffnen steht die aktuelle Stunde
  oben. Bildschirmleser hören je Block „Titel, Tag, Zeit“.
- `WochenKopf`: „‹ KW 48 · 23.11.–29.11.2026 › Heute“.
- Hilfen: `montagVon`, `kalenderwoche` (ISO 8601), `uhrText`, `tagLangText`,
  `wochentageKurz`, `wochentageLang`.

## 0.6.3

Bausteine aus Rosenweg Reparatur (Flutter-Plan: Kamera, Upload, Benachrichtigungen):

- **`FotoFeld`** (`foto_feld.dart`): Foto als Formularfeld – Telefon „Foto
  aufnehmen“ und „Aus Galerie“, Computer „Bild wählen“ oder hineinziehen;
  Vorschau, Grösse, „Entfernen“; vor dem Hochladen verkleinert (1600 px,
  JPEG 75 %). Arbeitet mit `RosenwegFormular` (Pflicht, Fehler am Feld,
  „Änderungen verwerfen?“). Neu `formularSteuerungVon(context)` für eigene
  Felder.
- **`GeladenesBild`**, **`bildZeigen`**: Bild mit der Anmeldung laden,
  Antippen = Vollbild mit Zoom; Fehler mit „Nochmals“.
- **Abfrage beim Öffnen** (Push ohne ntfy, Entscheid Stefan 27.11.2026):
  `BeimOeffnen` fragt beim Start, nach der Rückkehr in den Vordergrund und
  auf Wunsch regelmässig; `AppSpeicher` (nicht geheime Werte als JSON im
  Ordner für App-Daten, sonst nur im Speicher) und `Neuigkeiten` (was ist
  seit dem letzten Blick neu oder anders).
- `path_provider` als direkte Abhängigkeit (war schon über pdfrx da).
- Vorlage bleibt auf `ref: v0.6.2`, bis der Tag v0.6.3 steht.

## 0.6.2

- **„Nach Updates suchen“** (Stefan 27.11.2026: Updater nie durchgetestet):
  Abschnitt `AktualisierungKarte` auf der Seite „Anmeldung“
  (`zeigeAnmeldung`, Konto-Menü jeder App) – ohne Änderung in den Apps.
  - Android: `RosenwegPlattform.updaterPruefen()` → `RosenwegUpdater.jetztPruefen`
    aus commons-rosenweg (eigene Seite: „Aktuell“, „Neue Fassung X –
    Installieren“, Fehler im Klartext).
  - Linux, macOS, Windows: `RosenwegAktualisierung.jetztPruefen()` →
    `PruefErgebnis` (aktuell / neu / fehler / aus) mit Satz für die Person
    (`RosenwegAktualisierung.klartext`), bei neuer Fassung „Installieren“.
  - Stationen, verwaltete Installationen, iOS, Entwicklungsbau: nur der
    Hinweis, wer aktualisiert (`ausGrund`), kein Knopf.
  - `RosenwegAktualisierung.zuletzt`: der Updater der laufenden App.
- **Versionsstand ans NOC**: bei jeder Prüfung (und auf Stationen bzw.
  verwalteten PCs einmal nach dem Start) `POST
  https://pbx.rosenweg4303.ch/api/apps/stand` mit Gerät (SHA-256 der
  Maschinen-ID), Paket, Version, Plattform – keine Personendaten.
- Android: cloud 0.13.6 (Anmeldeschirm in Gruppenfarbe wirkt damit), updater
  0.1.6 (eigene Meldungsnummer statt 4303, WorkManager-Start nach den
  ContentProvidern aus 0.1.5).

## 0.6.1

- **Anmeldeschirm in der Gruppenfarbe der App** (Stefan 27.11.2026): Grund
  wie der Logo-Grund (`baukasten.py --gruppe`) – Bewohner rot `#D62828`,
  Ausschuss/Verwaltung blau `#1E3A8A`, Technik grün `#2E6B4F`. Neu
  `RosenwegGruppe` und `RosenwegApp.gruppe` (null = blau wie bisher);
  `AnmeldePalette` (blau/rot/grün) und `AnmeldeFarben.fuer(gruppe)`. Helle
  Schrift, Meldungen und die weisse Schrift auf den Knöpfen erreichen auf
  allen drei Gründen mindestens 4.5:1 (WCAG AA, Test
  `anmelde_farben_test.dart`); auf Rot und Grün sind die Knöpfe dunkler als
  der Grund. Logo, Texte, Knöpfe und Aufbau bleiben gleich.
  - Android: die Gruppe geht als Argument `gruppe` an den nativen Schirm von
    commons-rosenweg (Extra `ch.rosenweg4303.cloud.GRUPPE`, wirkt ab cloud
    0.13.6; mit älterer cloud bleibt er blau).
  - Vorlage: `gruppe: RosenwegGruppe.bewohner` in `lib/app.dart`;
    `neue-app.sh` setzt sie aus `werkzeug/logo/flutter-apps.txt` bzw.
    `--gruppe`. Vorlage auf `ref: v0.6.1`.
  - Knöpfe des Schirms nehmen die Schriftfamilie des Themas.
  - Bildschirmfotos: `RW_BILDER=<ordner> flutter test test/anmelde_farben_test.dart`.

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
- **Karte lesen in der App** (`karte_lesen.dart`, Android `NfcKarte.kt`):
  `karteLesen`, `KartenleserBereich` (liest laufend, solange sichtbar),
  `Kartenleser.fuerApp()` – Android NFC im Reader-Modus mit dem `Kartenleser`
  aus commons-rosenweg `anmeldeschirm` (neu `AndroidKartenleser`), iOS Core
  NFC, Desktop PC/SC (USB-Leser wie ACR122U). Klare Sätze, wenn es nicht geht
  (`kartenleserHindernis`: kein NFC, NFC aus mit Knopf zu den Einstellungen,
  kein PC/SC, kein Leser, Web). `karteUidNormal`, `uidEintippen`.
  Android-Manifest der Basis: `NFC`, `uses-feature nfc required=false`.
- **Karte wie Schlüssel:** antwortet die API mit 202 `{bestaetigung: 'email'}`
  (heikle Admin-Aktion mit Karte, QR oder Handy; api/lib/kartenadmin.js),
  wirft `apiAntwortPruefen` jetzt `BestaetigungPerEmail` (Hinweis, Ablauf,
  maskierte Adresse) statt still „Erfolg“ zu melden; `zeigeEmailBestaetigung`
  zeigt es, `RosenwegFormular` tut das selbst.
- Formular: `gespeichert: () => Navigator.pop(…)` fragte „Änderungen
  verwerfen?“, weil `canPop` erst nach dem nächsten Bau stimmte – jetzt geht
  die Seite ohne Frage zu.
- **Vorlage** (`vorlage/`): Bereich „Einträge“ aus Liste, Formular und Rechte
  (`lib/seiten/eintraege.dart`, Attrappe dazu, Test); Berechtigungen für
  Kamera und Dateien (Android, iOS, macOS); `rosenweg_basis` `ref: v0.6.0`.
- CI: `example/` wird mitgeprüft; `beispiel.yml` baut die Beispiel-App auf
  Linux (Container debian:13), Android, macOS, iOS und Windows – alles auf
  GitHub-Runnern (öffentliches Repo), Android ohne `continue-on-error`.
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
