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
| Android (eigene Handys und geteilte Telefone) | ja; Android-Plugin `ch.rosenweg4303.basis` |
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
| Ablauf | `RosenwegSitzung`, `rosenwegStarten`, `RosenwegRahmen`, `AnmeldeTor` |
| Aussehen | `rosenwegThema`, `RosenwegFarben` (Rot `#D32F2F`, Grundton `#8B1E3F`), deutsche Texte (de-CH) |
| Bausteine | `AnmeldeSchirm`, `FehlerAnzeige`, `LadeAnzeige`, `Abschnitt`, `Hinweis`, `zeigeMeldung`, `frage`, `zeigeUeber`, `RosenwegLogo` |
| Protokoll | `Protokoll.schreiben` – `~/.local/state/<ordner>/app.log`, nie Tokens |
| Android | Plugin: Rücksprung-Activity, DNS-Server, Rosenweg Gerät (`ContentResolver.call`) |

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

Für die Android-Apps (Fossify-Forks, Rosenweg Karten, Rosenweg Gerät) steht in `werkzeug/logo/android-apps.txt`, welche App welches Zeichen trägt; `android-apps.sh` schreibt Mipmaps, adaptive Icon und monochromes Designsymbol. Mehr: [docs/logos.md](docs/logos.md).

## Neue App anlegen

1. `flutter create --platforms=android,linux --org ch.rosenweg4303 --project-name rosenweg_<name> rosenweg-<name>`
2. applicationId/APPLICATION_ID auf `ch.rosenweg4303.<name>` setzen.
3. `rosenweg_basis` als git-Abhängigkeit mit festem Tag (z. B. `ref: v0.2.0`), lokal `pubspec_overrides.yaml` mit `path: ../rosenweg-basis`.
4. Zeichen zeichnen (`werkzeug/logo/zeichen/<name>.svg`, 400×400), `erzeugen.sh`.
5. Authentik: Rücksprung `ch.rosenweg4303.<name>:/anmeldung` eintragen.
6. `linux/paket/` aus rosenweg-profil kopieren und Namen ersetzen.

## Prüfen und CI

```sh
flutter analyze && flutter test
```

Dasselbe läuft bei jedem Push und PR in `.github/workflows/pruefen.yml` auf dem eigenen Runner. Keine Secrets nötig. Änderungen stehen in [CHANGELOG.md](CHANGELOG.md).

## Weitere Dokumente

| Datei | Inhalt |
|---|---|
| [docs/entwickeln.md](docs/entwickeln.md) | Beispiel, öffentliche API im Detail mit Herkunft |
| [docs/bedienung.md](docs/bedienung.md) | Bedienung, gleich in allen Apps |
| [docs/authentik.md](docs/authentik.md) | was in Authentik eingetragen sein muss, Kerberos |
| [docs/geteilte-telefone.md](docs/geteilte-telefone.md) | Schnittstelle zu Rosenweg Gerät, Personenwechsel |
| [docs/logos.md](docs/logos.md) | Logo-Baukasten |
| [docs/rosenweg-vm-umstellen.md](docs/rosenweg-vm-umstellen.md) | was rosenweg-vm für die Umstellung auf die Basis ändern müsste |

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE).
