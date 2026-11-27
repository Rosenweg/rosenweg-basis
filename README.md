<p align="center"><img src="assets/logo/rosenweg-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Basis</h1>
<p align="center">Gemeinsame Flutter-Basis aller Rosenweg-Apps – gleiche Anmeldung, gleiche API, gleiches Aussehen.</p>
<p align="center"><a href="#neue-app-anlegen">Neue App anlegen</a> · <a href="docs/bedienung.md">Anleitung</a></p>

## Inhalt

- [Überblick](#überblick)
- [Läuft auf](#läuft-auf)
- [Eine App in wenigen Zeilen](#eine-app-in-wenigen-zeilen)
- [Bedienung – gleich in allen Apps](#bedienung--gleich-in-allen-apps)
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
- **Logo-Baukasten** für alle App-Logos (Turm, Weg und Rose mit App-Zeichen).

Version 0.1.0 (26.11.2026); 0.2.0 mit Kerberos-Anmeldung und Personenwechsel ist unveröffentlicht – siehe [CHANGELOG.md](CHANGELOG.md).

## Läuft auf

| Plattform | Stand |
|---|---|
| Linux (Rosenweg OS, `.deb` vom PXE-Server) | ja; stille Anmeldung über GSS-API (`libgssapi-krb5-2`) |
| Android 8 und neuer (eigene Handys und geteilte Telefone) | ja; Android-Plugin `ch.rosenweg4303.basis`, minSdk 26; Anmeldeschirm aus commons-rosenweg (`ch.rosenweg4303:cloud` aus GitHub Packages, `mavenLocal()` als Rückfall) |
| Windows | Kerberos-Anmeldung über SSPI vorbereitet |

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
| Protokoll | `Protokoll.schreiben` – `~/.local/state/<ordner>/app.log`, nie Tokens |
| Android | Plugin `ch.rosenweg4303.basis`: Anmeldung über commons-rosenweg (`AndroidKonto`: Anmeldeschirm mit Karte oder Rosenweg-Konto, Token aus Kotlin), DNS-Server, Rosenweg Gerät (`ContentResolver.call`) |

Mehr: [docs/entwickeln.md](docs/entwickeln.md).

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

Flutter-Apps: `werkzeug/logo/flutter-apps.txt` legt für alle 41 Apps Zeichen und Zielgruppe fest (Farbe des Zeichens: Bewohner rot, Verwaltung blau, Technik grün; Rosenweg Stationen trägt unverändert das Logo von os-stationen). `app-symbole.sh` schreibt alle Plattform-Symbole einer App, `kontaktbogen.sh` setzt alle Logos nebeneinander zum Vergleichen. Neue Zeichen aus Material Symbols (Apache-2.0): `werkzeug/logo/zeichen-zusammensetzen.py`; Herkunft: `werkzeug/logo/zeichen/LIZENZEN.md`.

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
| `--basis-ref`, `--workflow-ref` | Stand von `rosenweg_basis` in `pubspec.yaml` (Standard wie in `vorlage/`, derzeit `v0.5.0`) und der Workflows (Standard `main`) |
| `--basis-lokal <pfad>` | `pubspec_overrides.yaml` auf eine lokale Basis (dann wird `pubspec.lock` nicht committet) |
| `--ohne-pub`, `--ohne-git` | kein `flutter pub get` / kein erster Commit |
| `--repo` | **zusätzlich** `Rosenweg/rosenweg-<name>` auf GitHub anlegen (privat) und `main` pushen – ohne den Schalter geschieht nichts auf GitHub |

Das Skript kopiert die Vorlage, ersetzt alle Namen (es bricht ab, wenn ein Platzhalter übrig bleibt), erzeugt alle Symbole (`werkzeug/logo/app-symbole.sh`), legt `git` mit einem ersten Commit an und druckt die Schritte ausserhalb des Repos.

### Danach (einmal je App)

1. **Authentik** (`rosenweg-apps`): Rücksprung `ch.rosenweg4303.<k>:/anmeldung` (strikt) eintragen – Desktop braucht nichts (`localhost`-Regex gilt für alle).
2. **GitHub**: Repo anlegen (oder `--repo`), dann
   - Org-Secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` für das Repo freigeben (ohne: Debug-Signatur, kein Release),
   - kein `BASIS_TOKEN` und keine Runner-Gruppe: rosenweg-basis ist öffentlich, alle Jobs laufen auf GitHub-Runnern (`ubuntu-latest`, das `.deb` im Container `debian:13`; `windows-latest`, `macos-latest`). Eigene Runner nie, auch nicht für Releases.
3. **/apps**: `apps-eintrag.json` in `APPS_REGISTER` (Rosenweg/Website `pbx/api/app.py`) übernehmen, `assets/logo/<app>-192.png` als `img/apps/<app>.png` ins Website-Repo. Ohne Register-Eintrag nimmt die Anlage keine Releases an.
4. **Android-Updater**: der Rosenweg Updater (commons-rosenweg `updater`) kennt die Pakete der Flutter-Apps; neue Kennung dort ergänzen, sonst prüft auf Handys mit nur Flutter-Apps niemand.
5. **Stationen**: nach dem ersten Release `linux/paket/paket.conf` als `pakete/<app>/paket.conf` (mit `hochladen.sh`) in os-stationen, Version und Prüfsumme eintragen.
6. Inhalt bauen (`lib/seiten/`, `lib/attrappe.dart`, `docs/anleitung.md`), Bedienung auf Handy **und** Station prüfen.

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

Dasselbe läuft bei jedem Push und PR in `.github/workflows/pruefen.yml` auf einem GitHub-Runner. Keine Secrets nötig. Änderungen stehen in [CHANGELOG.md](CHANGELOG.md).

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
