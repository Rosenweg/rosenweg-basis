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

## Stille Anmeldung mit Kerberos (Stationen, Windows-Domäne)

Wer an einer Rosenweg-OS-Station (Domänenanmeldung, sssd) oder an einem
Windows-Rechner der Domäne angemeldet ist, hat ein Kerberos-Ticket. Damit
meldet `RosenwegKonto.stillAnmelden()` die App **ohne Browser und ohne
Eingabe** an (`lib/src/anmeldung/stille_anmeldung.dart`):

1. `GET /source/kerberos/ad-kerberos/` → `401 Negotiate` → dieselbe Adresse mit
   `Authorization: Negotiate <SPNEGO-Token>` für
   `HTTP/authentik.rosenweg4303.ch@AD.ROSENWEG4303.CH`
   (Linux: GSS-API `libgssapi_krb5.so.2`; Windows: SSPI `secur32.dll`,
   NTLM-Rückfall wird verworfen).
2. Den Ablauf `default-source-authentication` über die Ablauf-API
   (`/api/v3/flows/executor/…`) abschliessen → angemeldete Sitzung, Cookies
   nur im Speicher.
3. Die gewohnte PKCE-Autorisierung mit `redirect_uri=http://localhost:0/anmeldung`
   (passt auf die Desktop-Regel); den Code liest die App aus der Weiterleitung.

Fragt Authentik irgendetwas (Passwort, Zustimmung, zweiter Faktor) oder gibt
es kein Ticket, endet sie mit `false` und es bleibt der Knopf (Browser).
`bestaetigen: true` (Passwortwechsel) geht nie still.

Wann: beim Start ohne gültiges Refresh-Token, beim Knopf „Anmelden“ (zuerst)
und wenn ein Refresh-Token widerrufen ist. Auf den Stationen ohne Secret
Service lebt das Refresh-Token nur im Speicher; nach Programmende meldet das
Ticket wieder still an. Abmelden an der Station löscht das Ticket — danach
geht nichts mehr still.

**Voraussetzungen in Authentik** (Website-Repo `scripts/authentik-apps-sso.sh`):

- `rosenweg-apps` mit **impliziter** Zustimmung — sonst fragt Authentik alle
  4 Wochen nach Zustimmung, und die stille Anmeldung fällt auf den Browser zurück.
- Die Kerberos-Quelle braucht keine Änderung (Benutzerzuordnung
  `username_link`: AD-Kontoname = Authentik-Benutzername).

**Paket:** Linux-`.deb` braucht `libgssapi-krb5-2` (per `dlopen`, darum nicht
von `dpkg-shlibdeps` gefunden) — in `linux/paket/bauen.sh` zu `DEPENDS`.
