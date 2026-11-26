# rosenweg_basis

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
| Anmeldung | `RosenwegKonto` (`anmelden({bestaetigen})`, `abbrechen`, `zugangsToken`, `abmelden`, `ausstehendeAbschliessen`, `name/email/benutzername`), `AnmeldeFehler` | rosenweg-vm `rosenweg_konto.dart` |
| Rücksprung | `Anmeldeweg.fuer(...)`: `LocalhostAnmeldeweg` (Desktop, `http://localhost:<port>/anmeldung`), `SchemaAnmeldeweg` (Android, `<kennung>:/anmeldung`), `AnmeldungAbgebrochen` | rosenweg-vm `browser_anmeldung.dart` + commons-rosenweg |
| Speicher | `Schluesselbund(eintrag)`: ein JSON-Eintrag in flutter_secure_storage, Rückfall „nur im Speicher“ ohne Secret Service | rosenweg-vm `schluesselbund.dart` |
| API | `RosenwegApi` (`get/put/post/delete`, `objekt`, `liste`), `Transport` → `HttpTransport` (Bearer, 401 → einmal erneuern; POST nie wiederholt) / `GeraetTransport` (geteiltes Telefon), `jsonAnfrage` | rosenweg-vm `json_anfrage.dart` |
| Fehler | `ServerNichtErreichbar` (502/503/504 ohne JSON, HTML, Netz; mit Rückoff), `ZuVieleAnfragen` (429 + Retry-After), `ApiFehler` (Text aus `error`), `NichtAngemeldet` (401), `KeineBerechtigung` (403, `neuAnmelden` bei `reauth`), `GeraetFehler` | |
| Haus | `HausErkennung().imHaus()` — TXT `location.rosenweg4303.ch` = „Rosenweg GBT“ beim Resolver des Geräts; nur Hinweis, nie Sicherheit | rosenweg-vm `haus_erkennung.dart` |
| Ablauf | `RosenwegSitzung` (Phasen `pruefen/abgemeldet/anmelden/bereit/fehler`, `geteiltesTelefon`, `bestaetigen()` für heikle Aktionen), `rosenwegStarten`, `RosenwegRahmen`, `AnmeldeTor` | rosenweg-vm `app_zustand.dart` |
| Aussehen | `rosenwegThema`, `RosenwegFarben` (Rot `#D32F2F`, Dunkelrot, Grundton `#8B1E3F`), deutsche Flutter-Texte (de-CH) | |
| Bausteine | `AnmeldeSchirm`, `FehlerAnzeige`, `LadeAnzeige`, `Abschnitt` (Karte mit Titel), `Hinweis`, `zeigeMeldung`, `frage`, `fehlerText`, `zeigeUeber` (GPL, Quelltext, Lizenzen), `RosenwegLogo` | |
| Protokoll | `Protokoll.schreiben` — `~/.local/state/<ordner>/app.log`, nie Tokens | rosenweg-vm `protokoll.dart` |
| Android | Plugin `ch.rosenweg4303.basis`: Anmeldung über commons-rosenweg (`AndroidKonto`: Anmeldeschirm mit Karte oder Rosenweg-Konto, Token aus Kotlin; braucht `ch.rosenweg4303:cloud` aus mavenLocal, minSdk 26), DNS-Server, Rosenweg Gerät (`ContentResolver.call`) | commons-rosenweg `cloud` |

## Bedienung — gleich in allen Apps

- Ein Knopf „Mit Rosenweg-Konto anmelden“; meist ohne Eingabe, weil der
  Browser die Authentik-Sitzung kennt. Während die Seite offen ist:
  Hinweis und „Abbrechen“.
- Danach still angemeldet, bis die letzte Browser-Anmeldung 30 Tage her ist.
- Fehler als ganzer Satz mit „Nochmals“; ein kurzer Server-Neustart meldet
  niemanden ab.
- Heikle Aktionen (Passwort): die API antwortet `403 reauth`, die App bietet
  „Jetzt neu anmelden“ an und macht danach selbst weiter.
- Geteilte Telefone: keine eigene Anmeldung, kein „Abmelden“ in der App —
  das macht Rosenweg Gerät (Karte).

## Logos

`werkzeug/logo/`: Baukasten für alle App-Logos — das Rosenweg-Wappen
vereinfacht (Turm, Weg, Rose auf Rot; der Turm allein wäre mit dem Wappen von
Kaiseraugst zu verwechseln) und rechts unten das Zeichen der App in einer
weissen Plakette. Drei Detailstufen: voll (ab 109 px), `-klein` (41–108 px),
`-winzig` (bis 40 px, Turm und Rose ohne Weg). Siehe Kopf von
`werkzeug/logo/baukasten.py`.

```sh
sh werkzeug/logo/erzeugen.sh ../rosenweg-profil rosenweg-profil "Rosenweg Profil" werkzeug/logo/zeichen/person.svg
sh werkzeug/logo/vorschau.sh ~/Downloads/rosenweg-app-logos.png assets/logo/rosenweg ../rosenweg-profil/assets/logo/rosenweg-profil
```

`logos/rosenweg-vm/`: korrigiertes Logo für rosenweg-vm (Monitor als
Zeichen), dort noch nicht übernommen.

Android-Apps (Fossify-Forks, Rosenweg Karten, Rosenweg Gerät): welche App
welches Zeichen trägt, steht in `werkzeug/logo/android-apps.txt`. Jede App
ruft aus ihrem `assets/logo/erzeugen.sh` nur `android-apps.sh` auf; es schreibt
Mipmaps aller Dichten, adaptive icon und monochromes Designsymbol. Bei den
Fossify-Apps zeigen die 18 wählbaren Icon-Farben alle auf das Rosenweg-Icon.
`startbildschirm.py` zeigt die Icons wie auf dem Telefon (hell, dunkel,
Designsymbole); Stand: `logos/android-apps/startbildschirm.png`.

```sh
sh werkzeug/logo/android-apps.sh ../fossify-rosenweg/calculator-rosenweg calculator-rosenweg
python3 werkzeug/logo/startbildschirm.py --aus ~/Downloads/rosenweg-android-logos.png \
    ../fossify-rosenweg/calculator-rosenweg/assets/logo/rosenweg-rechner …
```

## Neue App anlegen

1. `flutter create --platforms=android,linux --org ch.rosenweg4303 --project-name rosenweg_<name> rosenweg-<name>`
2. applicationId/APPLICATION_ID auf `ch.rosenweg4303.<name>` setzen.
3. `rosenweg_basis` als git-Abhängigkeit, lokal `pubspec_overrides.yaml` mit `path: ../rosenweg-basis`.
4. Zeichen zeichnen (`werkzeug/logo/zeichen/<name>.svg`, 400×400), `erzeugen.sh`.
5. Authentik: Rücksprung `ch.rosenweg4303.<name>:/anmeldung` eintragen (docs/authentik.md).
6. `linux/paket/` aus rosenweg-profil kopieren und Namen ersetzen.

## Weiter

- [docs/authentik.md](docs/authentik.md) — was in Authentik eingetragen sein muss
- [docs/geteilte-telefone.md](docs/geteilte-telefone.md) — Schnittstelle zu Rosenweg Gerät
- [docs/rosenweg-vm-umstellen.md](docs/rosenweg-vm-umstellen.md) — was rosenweg-vm später ändern müsste

## Prüfen

```sh
flutter analyze && flutter test
```
