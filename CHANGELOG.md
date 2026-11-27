## 0.3.0 (unveröffentlicht)

- Gerüst für Handy und Desktop: `RosenwegGeruest` (AppBar; mit zwei oder
  mehr `GeruestZiel` unten eine NavigationBar, ab 840 px eine
  NavigationRail links, ab 1200 px beschriftet; Inhalt am Desktop mittig
  mit begrenzter Breite), `RosenwegSpalten` (ab 840 px zwei Spalten, sonst
  unverändert das Handy-Layout), `RosenwegInhalt` und `Fensterklasse`
  (600/840/1200 px nach Material 3). Unter 840 px ändert sich nichts.
- `rosenwegThema`: Dialoge höchstens 560 px breit.

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
