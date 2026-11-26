# Bedienung — gleich in allen Apps

So verhalten sich alle Apps, die auf rosenweg-basis aufbauen.

- Ein Knopf „Mit Rosenweg-Konto anmelden“; meist ohne Eingabe, weil der
  Browser die Authentik-Sitzung kennt. Während die Seite offen ist:
  Hinweis und „Abbrechen“.
- Danach still angemeldet, bis die letzte Browser-Anmeldung 30 Tage her ist.
- An Linux-Stationen und Windows-Rechnern der Domäne meldet die App sich
  mit dem Kerberos-Ticket der Sitzung an, ganz ohne Browser (beim Start,
  beim Knopf und nach widerrufenem Token). Fragt Authentik etwas oder fehlt
  das Ticket, kommt der Browser wie oben. Das Linux-Paket braucht dafür
  `libgssapi-krb5-2`; Einrichtung in [docs/authentik.md](authentik.md).
- Fehler als ganzer Satz mit „Nochmals“; ein kurzer Server-Neustart meldet
  niemanden ab.
- Heikle Aktionen (Passwort): die API antwortet `403 reauth`, die App bietet
  „Jetzt neu anmelden“ an und macht danach selbst weiter.
- Geteilte Telefone: keine eigene Anmeldung, kein „Abmelden“ in der App —
  das macht Rosenweg Gerät (Karte). Die Anfragen gehen über Rosenweg Gerät
  (`portal_anfrage`, ab v236) und die Telefonanlage; die App sieht kein Token.
  Wechselt die Person am Telefon, baut `RosenwegRahmen` die ganze App neu.
