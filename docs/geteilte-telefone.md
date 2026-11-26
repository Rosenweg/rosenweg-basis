# Geteilte Telefone: Anmeldung über Rosenweg Gerät

Auf geteilten Telefonen meldet sich niemand in einer App an: die Person hält
ihre Karte ans Telefon, Rosenweg Gerät kennt sie, und alle Apps arbeiten in
ihrem Namen (wie Rosenweg Karten, `KartenActivity.java`, und das Cloud-Modul
von commons-rosenweg). Die Flutter-Apps machen es genauso.

## Wie die Basis das erkennt

`RosenwegSitzung.starten()` fragt auf Android, ob der Provider
`ch.rosenweg4303.telefon.anlage` (AnlageProvider in Rosenweg Gerät) da ist.
Wenn ja:

- keine eigene Anmeldung, kein „Abmelden“ in der App (`geteiltesTelefon = true`);
- alle API-Anfragen gehen über `GeraetTransport` an Rosenweg Gerät; die App
  sieht nie ein Token.

## Vorgeschlagene Methode im AnlageProvider (noch nicht gebaut)

```
call("portal_anfrage", <pfad>, {methode, koerper, paket})
  pfad     z. B. "/api/auth/me" (nur /api/…)
  methode  GET | PUT | POST | DELETE
  koerper  JSON als Text oder fehlt
  paket    applicationId der rufenden App (Protokoll, ggf. Freigabeliste)
→ {status: int, json: String}                   Antwort der Haupt-API, unverändert
→ {nicht_angemeldet: true}                      niemand am Telefon angemeldet
→ {fehler: String}                              Netz/Anlage, Satz für die Person
```

Rosenweg Gerät stellt die Anfrage mit dem Zugang der angemeldeten Person an
`https://rosenweg4303.ch` — derselbe Weg wie heute für die Anlage
(`Anlage.java`). Was die Basis bei anderen Antworten tut
(`geraetAntwortLesen` in `lib/src/netz/api.dart`):

| Antwort | in der App |
|---|---|
| leeres Bundle (Methode unbekannt) | „Rosenweg Gerät ist zu alt für diese App – bitte aktualisieren.“ |
| `SecurityException` | „Rosenweg Gerät verweigert den Zugriff (andere Signatur?).“ |
| `status` 401 / `nicht_angemeldet` | „Am Telefon ist niemand angemeldet. Bitte zuerst mit der Karte anmelden.“ |

## Voraussetzungen

- **Signatur:** `ch.rosenweg4303.permission.ANLAGE` ist `signature`. Die
  Flutter-APKs müssen mit dem Rosenweg-Schlüssel signiert sein (wie die
  Fossify-Forks). Der Bau dieses Repos signiert vorerst mit dem Debug-Schlüssel.
- **Wer darf was:** Rosenweg Gerät sollte Pfade nur durchreichen, nicht
  erweitern; die API prüft die Rechte der Person wie bei jeder Anfrage.
  Sinnvoll ist eine Freigabeliste je `paket` (z. B. Profil: `/api/auth/*`,
  `/api/me/*`, `/api/energie/meine-zaehler`, `/api/ssh/me*`).
- **Heikles am geteilten Telefon:** Passwortwechsel verlangt eine frische
  Anmeldung; am geteilten Telefon gibt es die nicht (`bestaetigen()` liefert
  false). Ebenso sollten API-Tokens dort eher nicht angelegt werden — zu
  entscheiden, ob Rosenweg Gerät `POST /api/me/tokens` und
  `/api/change-password` sperrt.
- Abmelden am Telefon (Karte) muss die Apps nicht benachrichtigen: jede
  Anfrage geht neu über Gerät; nach dem Abmelden kommt `nicht_angemeldet`.
