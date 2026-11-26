<p align="center"><img src="assets/logo/rosenweg-512.png" width="96" alt="Logo"></p>
<h1 align="center">Rosenweg Basis</h1>
<p align="center">Gemeinsame Flutter-Basis aller Rosenweg-Apps – gleiche Anmeldung, gleiche API, gleiches Aussehen.</p>
<p align="center"><a href="docs/entwickeln.md#neue-app-anlegen">Neue App anlegen</a> · <a href="docs/bedienung.md">Bedienung</a> · <a href="docs/entwickeln.md">Für Entwickler</a></p>

## Was drin ist

- Anmeldung mit dem Rosenweg-Konto, still für 30 Tage, an Stationen per Kerberos.
- API-Zugang mit verständlichen Fehlern, auch über die geteilten Telefone.
- Rosenweg-Aussehen und fertige Bausteine (Anmeldeschirm, Fehler, Laden, Über).
- Logo-Baukasten für alle App-Logos (Turm, Weg, Rose) – siehe [docs/logos.md](docs/logos.md).
- Eine neue App braucht nur wenige Zeilen.

## Läuft auf

Linux und Android.

## Entwickeln

Flutter-Paket `rosenweg_basis`, in den Apps als git-Abhängigkeit mit festem Tag.
`flutter analyze && flutter test` – Aufbau, Beispiel und neue Apps stehen in
[docs/entwickeln.md](docs/entwickeln.md), Änderungen in [CHANGELOG.md](CHANGELOG.md).

## Lizenz

GPL-3.0-or-later, siehe [LICENSE](LICENSE).
