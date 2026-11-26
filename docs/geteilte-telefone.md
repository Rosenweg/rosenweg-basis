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

## Die Methode im AnlageProvider (Rosenweg Gerät ab v236)

```
call("portal_anfrage", <pfad>, {methode, koerper, paket})
  pfad     z. B. "/api/salz/lager" (nur /api/…, keine Punkt-Segmente, kein %2F/%2E)
  methode  GET | PUT | POST | DELETE
  koerper  JSON als Text oder fehlt (höchstens 256 KiB)
  paket    applicationId der App (nur Protokoll: Gerät nimmt das Paket vom Aufrufer)
→ {status: int, json: String, sitzung: String}   Antwort der Haupt-API (höchstens 512 KiB)
→ {nicht_angemeldet: true}                      niemand am Telefon angemeldet
→ {fehler: String}                              Netz/Anlage, Satz für die Person
```

Der Weg:

```
App ─call()─▶ Rosenweg Gerät ─POST /api/telefon/portal (Gerätezugang)─▶ PBX-API (CT 220)
    ─Bearer <Token für genau diese Anfrage>─▶ Haupt-API
```

- **Gerät** prüft: Signatur des Aufrufers (Berechtigung `ANLAGE` und die
  Signatur der UID), Paket `ch.rosenweg4303.*`, Methode, Pfadform, Grösse,
  höchstens 120 Anfragen je App und Minute. Ein Token hat Gerät nicht.
- **PBX-API** prüft: wer am Telefon angemeldet ist und ob die App den Pfad
  darf (Config `portal_pfade`, siehe Website `pbx/README.md`; Standard:
  Salz `/api/salz/`, alle Apps `GET /api/auth/me` und `GET /api/me`). Sie
  stellt ein Token für genau diese Anfrage aus (60 s, einmal) und behält es.
- **Haupt-API** (`authMiddleware`, `lib/anlagetoken.js`) prüft Signatur,
  Frist, Methode+Pfad, Konto aktiv, und sperrt wie bei Zugangstoken alles,
  was einen Ausweis ändert (Passwort, Tokens, Passkeys …).

Was die Basis aus den Antworten macht (`geraetAntwortLesen` in
`lib/src/netz/api.dart`):

| Antwort | in der App |
|---|---|
| leeres Bundle (Methode unbekannt) | „Rosenweg Gerät ist zu alt für diese App – bitte aktualisieren.“ |
| `SecurityException` | „Rosenweg Gerät verweigert den Zugriff (andere Signatur?).“ |
| `status` 401 / `nicht_angemeldet` | „Am Telefon ist niemand angemeldet. Bitte zuerst mit der Karte anmelden.“ |
| `status` 403 | Pfad für diese App nicht freigegeben (oder Recht der Person fehlt) |
| `status` 429 | „Zu viele Anfragen“ |

## Personenwechsel

Meldet sich am Telefon jemand ab oder eine andere Person an, baut die Basis
die ganze App neu (`RosenwegSitzung.personStand`, `RosenwegRahmen`): offene
Seiten und ihr Zustand sind weg, die Daten kommen neu. Zwei Auslöser:

- die Broadcasts `ch.rosenweg4303.ANGEMELDET` / `ABGEMELDET`, die Gerät beim
  An- und Abmelden an jede Katalog-App schickt (nur von Absendern mit
  `ANLAGE`, `android/…/GeraetPerson.kt`);
- die Marke `sitzung` jeder Antwort: wechselt sie, war jemand anderes da.

Beim Abmelden versteckt Gerät die Katalog-Apps ohnehin und löscht ihre Daten
(`persoenlich`); der Neuaufbau deckt die Apps ab, die sichtbar bleiben.

## Voraussetzungen

- **Signatur:** `ch.rosenweg4303.permission.ANLAGE` ist `signature`. Die
  Flutter-APKs müssen mit dem Rosenweg-Schlüssel signiert sein (wie die
  Fossify-Forks und Rosenweg Gerät); ein Debug-Bau bekommt eine
  `SecurityException`. /apps und der Release-Weg nehmen ohnehin nur
  Rosenweg-signierte APKs an.
- **Katalog:** die App muss im App-Katalog der geteilten Telefone stehen
  (rosenweg4303.ch/smartphones), mit den Gruppen, die sie sehen dürfen.
- **Heikles am geteilten Telefon:** Passwortwechsel verlangt eine frische
  Anmeldung; am geteilten Telefon gibt es die nicht (`bestaetigen()` liefert
  false). Tokens, Passkeys und Passwort sperrt die Haupt-API für diesen Weg.
