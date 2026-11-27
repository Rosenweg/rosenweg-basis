# Anmeldeschirm

Derselbe Schirm wie auf Android (commons-rosenweg, Modul `anmeldeschirm`, und
Sperrbildschirm der geteilten Telefone): blauer Grund, Rosenweg-Siegel, oben
„<App> · zum Benutzen anmelden“, unten „Die Anmeldung gilt nur für <App>.“
Jede App meldet sich selbst an; Abmelden betrifft nur sie.

Die App muss nichts tun: `rosenwegStarten` → `RosenwegRahmen` → `AnmeldeTor`
zeigt `RosenwegAnmeldeSchirm`, solange niemand angemeldet ist. Für die
Einstellungen gibt es `AnmeldungKarte` (Abschnitt) und `zeigeAnmeldung(context,
sitzung)` (eigene Seite): angemeldet als, E-Mail, womit, „gilt nur für …“,
Abmelden – immer aus `sitzung.stand`, dem echten Stand.

## Je Plattform

| | Karte | Rosenweg-Konto | QR-Code |
|---|---|---|---|
| **Android** | nativer Schirm aus commons-rosenweg (NFC laufend) | Browser (Custom Tab) | Handy scannt den Portal-QR |
| **iOS** | Knopf „Rosenweg-Karte lesen“, Core NFC | Browserfenster in der App | „QR-Code scannen“ (VisionKit), Portal-QR |
| **Desktop** | USB-Leser (PC/SC), nur wenn einer steckt | Browser | **umgekehrt**: „Mit dem Handy anmelden“ |

Vor dem Schirm meldet die Sitzung still an, wo es geht: gespeichertes
Rosenweg-Konto (≤ 30 Tage), gespeicherte Karten-Sitzung, Kerberos-Ticket
(Linux-Stationen, Windows-Domäne). An Stationen erscheint der Schirm daher nie.

Warum so:

- **Android** bleibt nativ: ein Schirm für Kotlin- und Flutter-Apps, NFC im
  Reader-Modus läuft dort laufend, und Karten-Sitzung samt Schlüssel liegen im
  Android-Keystore.
- **iOS** liest NFC nur auf Knopfdruck mit eigenem Systemfenster – daher ein
  Knopf statt „Karte hinten ans Telefon halten“. Die Rosenweg-Karte (UniFi
  Access; ISO 14443-A, 7-Byte-UID von NXP „04…“, nach UniFi-Angaben MIFARE
  DESFire) liefert Core NFC als `NFCMiFareTag` (bzw. `NFCISO7816Tag`) mit
  `identifier` – derselbe Wert wie `Tag.getId()` auf Android; mehr braucht
  der Server nicht. **Am echten iPhone noch zu prüfen** (kein Gerät mit
  NFC-Berechtigung zur Hand).
- **Desktop** hat meist keine Kamera auf den Bildschirm und (Stand 27.11.2026)
  an den Stationen keinen Kartenleser (os-stationen kennt weder pcscd noch
  Leser). Deshalb zeigt der Computer den QR und das Handy bestätigt – wie beim
  Fernseher-Login (Geräte-Code). Steckt ein USB-NFC-Leser (ACR122U o. ä.),
  erscheint „Rosenweg-Karte auf den Kartenleser legen“ von selbst.

## Karten-, QR- und Handy-Sitzung (`KartenSitzung`)

Gleicher Server wie Android (Website `api/routes/app-karte.js`), gleiche Regeln:
eigene Sitzung je App und Gerät, Zugang `rw_app_…` 15 Minuten nur im Speicher,
30 Tage, höchstens 20 je Person, Mail bei neuem Gerät, im Portal unter
Profil → App-Anmeldungen sichtbar und abmeldbar.

- Schlüssel: EC P-256 (pointycastle), privater Teil im Schlüsselbund des
  Systems (nicht in Hardware wie auf Android), öffentlicher als SPKI an den
  Server. Erneuern: Herausforderung mit SHA256withECDSA (DER) unterschreiben.
- Geräte-Kennung: `sha256("rosenweg:<id>")` – Linux `/etc/machine-id`, macOS
  `IOPlatformUUID`, Windows `MachineGuid`, iOS `identifierForVendor`; alle
  Rosenweg-Apps eines Geräts gelten als ein Gerät.
- Endpunkte: `POST /api/apps/karte-anmelden`, `/api/apps/qr-anmelden`,
  `/api/apps/handy-code` + `/api/apps/handy-code/abholen`,
  `/api/apps/sitzung/erneuern`, `/api/apps/sitzung/abmelden`.

Apps, deren Dienste ein **Authentik-Token** brauchen, setzen
`RosenwegApp(ohneBrowser: false)`: dann bietet der Schirm nur das
Rosenweg-Konto an. Rosenweg VM braucht das seit 1.2.0 nicht mehr: der vm-gateway nimmt auch `rw_app_…` an (prüft sie über `GET /api/auth/me`); Token für eigene Dienste gibt `RosenwegSitzung.zugang`.

## Was die Apps einrichten müssen

**iOS** (`ios/Runner/Info.plist` bzw. `Runner.entitlements`):

```xml
<key>NFCReaderUsageDescription</key>
<string>Zum Anmelden mit der Rosenweg-Karte.</string>
<key>NSCameraUsageDescription</key>
<string>Zum Scannen des Anmelde-QR.</string>
```

```xml
<key>com.apple.developer.nfc.readersession.formats</key>
<array><string>TAG</string></array>
```

Die NFC-Berechtigung verlangt ein bezahltes Apple-Entwicklerkonto. Ohne sie
meldet das Plugin „kein NFC“ und der Schirm blendet die Karte aus; QR und
Konto gehen weiter. QR braucht iOS 16 (VisionKit).

**macOS** mit App-Sandbox: `com.apple.security.smartcard` (Kartenleser) und
`com.apple.security.network.client`. Ohne Smartcard-Recht gibt es einfach
keine Karte.

**Linux** (Paket): `Recommends: pcscd, libpcsclite1` – ohne sie keine Karte.

**Windows:** nichts; der Dienst „Smartcard“ läuft, sobald ein Leser steckt.
