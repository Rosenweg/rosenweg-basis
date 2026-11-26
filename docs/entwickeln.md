# Für Entwickler

Gemeinsame Flutter-Basis für alle Rosenweg-Funktions-Apps — was
`commons-rosenweg` (Modul `cloud`, `RosenwegAnmeldung.kt`) für die
Fossify-Forks ist. Jede Portal-Funktion wird eine eigene App mit eigenem Repo,
für **Linux** (Rosenweg OS, `.deb` vom PXE-Server) und **Android** (eigene
Handys und geteilte Telefone). Die Basis sorgt dafür, dass sie sich alle
gleich anmelden, gleich mit der API reden und gleich aussehen.

Lizenz: GPL-3.0-or-later (wie rosenweg-vm).

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

`rosenwegStarten` richtet Logdatei und Fehlerfang ein, prüft die Anmeldung
und zeigt bis dahin Warten, Anmeldeschirm oder Fehler. Die App sieht erst
`sitzung.api`, wenn jemand angemeldet ist.

## Aufbau (öffentliche API)

| Teil | Klassen / Funktionen | Herkunft |
|---|---|---|
| Einstellungen | `RosenwegKonfig` (Authentik, Client `rosenweg-apps`, Scopes, API, Haus-DNS, 30-Tage-Regel), `RosenwegApp` | rosenweg-vm `konfig.dart` |
| Anmeldung | `RosenwegKonto` (`anmelden({bestaetigen})`, `stillAnmelden()`, `abbrechen`, `zugangsToken`, `abmelden`, `ausstehendeAbschliessen`, `name/email/benutzername`), `AnmeldeFehler` | rosenweg-vm `rosenweg_konto.dart` |
| Stille Anmeldung | `StilleAnmeldung`, `KerberosTicket` (Linux GSS-API, Windows SSPI, per FFI): SPNEGO an die Authentik-Kerberos-Quelle, dann PKCE ohne Browser | neu in 0.2.0 |
| Rücksprung | `Anmeldeweg.fuer(...)`: `LocalhostAnmeldeweg` (Desktop, `http://localhost:<port>/anmeldung`), `SchemaAnmeldeweg` (Android, `<kennung>:/anmeldung`), `AnmeldungAbgebrochen` | rosenweg-vm `browser_anmeldung.dart` + commons-rosenweg |
| Speicher | `Schluesselbund(eintrag)`: ein JSON-Eintrag in flutter_secure_storage, Rückfall „nur im Speicher“ ohne Secret Service | rosenweg-vm `schluesselbund.dart` |
| API | `RosenwegApi` (`get/put/post/delete`, `objekt`, `liste`), `Transport` → `HttpTransport` (Bearer, 401 → einmal erneuern; POST nie wiederholt) / `GeraetTransport` (geteiltes Telefon, über `portal_anfrage` von Rosenweg Gerät), `jsonAnfrage` | rosenweg-vm `json_anfrage.dart` |
| Fehler | `ServerNichtErreichbar` (502/503/504 ohne JSON, HTML, Netz; mit Rückoff), `ZuVieleAnfragen` (429 + Retry-After), `ApiFehler` (Text aus `error`), `NichtAngemeldet` (401), `KeineBerechtigung` (403, `neuAnmelden` bei `reauth`), `GeraetFehler` | |
| Haus | `HausErkennung().imHaus()` — TXT `location.rosenweg4303.ch` = „Rosenweg GBT“ beim Resolver des Geräts; nur Hinweis, nie Sicherheit | rosenweg-vm `haus_erkennung.dart` |
| Ablauf | `RosenwegSitzung` (Phasen `pruefen/abgemeldet/anmelden/bereit/fehler`, `geteiltesTelefon`, `personStand`, `bestaetigen()` für heikle Aktionen), `rosenwegStarten`, `RosenwegRahmen`, `AnmeldeTor` | rosenweg-vm `app_zustand.dart` |
| Aussehen | `rosenwegThema`, `RosenwegFarben` (Rot `#D32F2F`, Dunkelrot, Grundton `#8B1E3F`), deutsche Flutter-Texte (de-CH) | |
| Bausteine | `AnmeldeSchirm`, `FehlerAnzeige`, `LadeAnzeige`, `Abschnitt` (Karte mit Titel), `Hinweis`, `zeigeMeldung`, `frage`, `fehlerText`, `zeigeUeber` (GPL, Quelltext, Lizenzen), `RosenwegLogo` | |
| Protokoll | `Protokoll.schreiben` — `~/.local/state/<ordner>/app.log`, nie Tokens | rosenweg-vm `protokoll.dart` |
| Android | Plugin `ch.rosenweg4303.basis`: Anmeldung über commons-rosenweg (`AndroidKonto`: Anmeldeschirm mit Karte oder Rosenweg-Konto, Token aus Kotlin; braucht `ch.rosenweg4303:cloud` aus GitHub Packages oder mavenLocal, minSdk 26), DNS-Server, Rosenweg Gerät (`ContentResolver.call`) | commons-rosenweg `cloud` |

## Neue App anlegen

1. `flutter create --platforms=android,linux --org ch.rosenweg4303 --project-name rosenweg_<name> rosenweg-<name>`
2. applicationId/APPLICATION_ID auf `ch.rosenweg4303.<name>` setzen.
3. `rosenweg_basis` als git-Abhängigkeit mit festem Tag (z. B. `ref: v0.2.0`), lokal `pubspec_overrides.yaml` mit `path: ../rosenweg-basis`.
4. Zeichen zeichnen (`werkzeug/logo/zeichen/<name>.svg`, 400×400), `erzeugen.sh`.
5. Authentik: Rücksprung `ch.rosenweg4303.<name>:/anmeldung` eintragen (docs/authentik.md).
6. `linux/paket/` aus rosenweg-profil kopieren und Namen ersetzen.

## Prüfen

```sh
flutter analyze && flutter test
```

Dasselbe läuft bei jedem Push und PR in `.github/workflows/pruefen.yml`
auf dem eigenen Runner. Änderungen stehen in [CHANGELOG.md](../CHANGELOG.md).

## Weiter

- [docs/authentik.md](authentik.md) — was in Authentik eingetragen sein muss
- [docs/geteilte-telefone.md](geteilte-telefone.md) — Schnittstelle zu Rosenweg Gerät
- [docs/rosenweg-vm-umstellen.md](rosenweg-vm-umstellen.md) — was rosenweg-vm später ändern müsste

- [bedienung.md](bedienung.md) — Bedienung, gleich in allen Apps
- [logos.md](logos.md) — Logo-Baukasten
