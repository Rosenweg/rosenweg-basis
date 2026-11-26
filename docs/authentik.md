# Authentik für die Rosenweg-Apps

Nichts davon ist durch diese Basis eingerichtet worden.

**Anwendung „rosenweg-apps“** (öffentlicher Client, PKCE S256; schon da für
commons-rosenweg, Rosenweg Telefon, rosenweg-vm) → Anbieter → Weiterleitungs-URIs:

| Modus | Adresse | Für |
|---|---|---|
| Regex | `^http://localhost:[0-9]+/anmeldung$` | alle Desktop-Apps (Linux) — einmal für alle, schon für rosenweg-vm nötig |
| Strikt | `ch.rosenweg4303.profil:/anmeldung` | Rosenweg Profil auf Android |
| Strikt | `ch.rosenweg4303.<app>:/anmeldung` | je weitere Flutter-App auf Android |

- Bereiche: `openid email profile offline_access`.
- Refresh-Token-Gültigkeit ≥ 30 Tage (die Apps fragen nach 30 Tagen selbst
  wieder über den Browser).
- `prompt=login` und `max_age=0` müssen durchgehen: damit holt die App eine
  frische Anmeldung für den Passwortwechsel (`RosenwegKonto.anmelden(bestaetigen: true)`).

## Haupt-API

Die Apps schicken das Access-Token von `rosenweg-apps` als
`Authorization: Bearer …` an `https://rosenweg4303.ch/api/…`. Die API nimmt
solche Tokens zurzeit noch nicht allgemein an (in Arbeit, `api/lib/auth.js`).
Besonders zu prüfen:

- `requireUserLogin` (Tokens, SSH) — muss App-Tokens als Benutzer-Anmeldung gelten lassen.
- `POST /api/change-password` prüft die Frische über die Tabelle `sessions`
  (Website-Sitzung). Für App-Tokens bräuchte es eine andere Frische-Prüfung,
  z. B. `auth_time` im Token (mit `max_age=0` neu gesetzt) ≤ 15 Minuten.
  Bis dahin antwortet die API der App mit `403 reauth`, und auch die
  Neuanmeldung hilft nicht.
