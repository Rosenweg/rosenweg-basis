## 0.2.0 (unveröffentlicht)

- Stille Anmeldung mit dem Kerberos-Ticket der Sitzung (Linux-Stationen,
  Windows-Domäne): `RosenwegKonto.stillAnmelden()`, `StilleAnmeldung`,
  `KerberosTicket` (GSS-API / SSPI per FFI). Die Sitzung versucht sie beim
  Start, beim Knopf und nach widerrufenem Refresh-Token; sonst Browser wie
  bisher. Neue Abhängigkeit `ffi`; Linux-Paket braucht `libgssapi-krb5-2`.

## 0.1.0 (26.11.2026)

- Erste Fassung: Anmeldung (Authentik rosenweg-apps, PKCE; Desktop über
  localhost, Android über `<applicationId>:/anmeldung`), Schlüsselbund mit
  Rückfall ohne Secret Service, API-Client (JSON, 502/HTML, 429, 401 mit
  einmaligem Erneuern), Haus-Erkennung (TXT), Sitzung und Anmeldetor,
  Thema/Farben, Bausteine (Anmeldeschirm, Fehler, Über mit GPL, Abschnitt,
  Hinweis), Logo-Baukasten (Turm + Weg + Rose, App-Zeichen als Plakette).
- Schnittstelle zu Rosenweg Gerät für geteilte Telefone (Vorschlag
  `portal_anfrage`, dort noch nicht gebaut).
