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
