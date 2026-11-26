# rosenweg-vm auf rosenweg_basis umstellen (später)

rosenweg-vm ist nicht geändert worden. Was ein Umbau dort hiesse:

| rosenweg-vm heute | in der Basis | Umbau |
|---|---|---|
| `lib/konfig.dart` (`Konfig`) | `RosenwegKonfig` + `RosenwegApp` | `const vmApp = RosenwegApp(kennung: 'ch.rosenweg4303.vm', ordner: 'rosenweg-vm', …)`; `Konfig.api`/`authentik` → `vmApp.konfig.…` |
| `lib/protokoll.dart` | `Protokoll` | Achtung Ordner: vm schreibt nach `~/Library/Logs/Rosenweg Virtuelle Computer` (macOS) bzw. `%LOCALAPPDATA%\Rosenweg Virtuelle Computer`; die Basis nimmt `ordner` (`rosenweg-vm`). Entweder hinnehmen oder `ordner` je Plattform. |
| `lib/anmeldung/schluesselbund.dart` | `Schluesselbund` | `Schluesselbund('rosenweg_vm', alteEintraege: {'refresh_token': 'rosenweg_refresh_token', 'angemeldet_am': 'rosenweg_angemeldet_am', 'geraet': 'rosenweg_geraet'})` — gleicher Eintrag, niemand muss sich neu anmelden. Die Geräte-Kennung (`geraet`) bleibt Sache der vm-App (`Schluesselbund.lesen/setzen`). |
| `lib/anmeldung/rosenweg_konto.dart` | `RosenwegKonto` | gleiches Verhalten (30 Tage, Refresh, 502 meldet nicht ab); `RosenwegKonto(vmApp, speicher: obiger Schluesselbund)`. |
| `lib/anmeldung/browser_anmeldung.dart` | `Anmeldeweg` | entfällt; Android-Anmeldung kommt damit gleich mit (`ch.rosenweg4303.vm:/anmeldung` in Authentik eintragen, steht dort schon als „später“). |
| `lib/netz/json_anfrage.dart` (dart:io HttpClient) | `jsonAnfrage` (package:http) | Aufrufe in `netzlage.dart`/`gateway.dart` auf `http.Request` umstellen oder `RosenwegApi`+`HttpTransport` für `/api/apps/tunnel` nehmen. Unterschied: 502/503/504 **mit** JSON-`error` wird in der Basis nicht wiederholt, sondern zurückgegeben. Der Gateway-Client (im Tunnel) braucht einen eigenen `http.Client` über den Tunnel-Proxy. |
| `lib/netz/haus_erkennung.dart` | `HausErkennung` | Methodenkanal `ch.rosenweg4303.vm/netz` (MainActivity.kt) entfällt, das Plugin liefert `dnsServer`. `endpunktWaehlen` bleibt in vm (`netzlage.dart`). |
| `lib/app_zustand.dart` (Phasen) | `RosenwegSitzung` + `AnmeldeTor` | vm hat zusätzliche Phasen (`tunnel`, `liste`); entweder `AnmeldeTor` + eigener Zustand danach (Phase `bereit` = Tunnel aufbauen), oder AppZustand behält seine Phasen und nutzt nur `RosenwegKonto`. Empfehlung: erstes. |
| `main.dart` (Fehlerfang, Lebenslauf) | `rosenwegStarten` | Fehlerfang aus der Basis; das Abmelden des Tunnels beim Schliessen (`AppLifecycleListener`) bleibt in vm. `RwTunnel.absturzdatei` vor `runApp` — dafür bräuchte `rosenwegStarten` einen Haken (`vorStart`), noch nicht vorhanden. |
| `oberflaeche/start_seite.dart` (Anmeldeknopf, Fehler) | `AnmeldeSchirm`, `FehlerAnzeige`, `zeigeUeber` | Texte angleichen; „Über“ mit GPL aus der Basis. |
| `ThemeData(colorSchemeSeed: 0xFF8B1E3F)` | `rosenwegThema` | gleicher Grundton. |
| `assets/logo/` (A2, nur Turm) | `logos/rosenweg-vm/` | Dateien übernehmen (SVG, PNG, `android-res/`), `assets/logo/erzeugen.sh` und `linux/paket/bauen.sh` auf die drei Stufen (`-winzig` ≤ 40 px, `-klein` ≤ 108 px) umstellen; macOS/iOS/Windows-Icons aus `-macos`/`-vollflaeche`. |
| Android `MainActivity.kt` (Kanal netz) | Plugin | Kanal entfernen. |
| `pubspec.yaml` | | `rosenweg_basis` (git, Tag) statt `crypto`, `url_launcher`, `flutter_secure_storage` direkt. |
| Tests `schluesselbund_test`, `json_anfrage_test`, `haus_erkennung_test` | gleiche Tests in der Basis | in vm löschen; `endpunktWaehlen`-Tests bleiben. |

Reihenfolge: Basis taggen (`v0.1.0`) → vm: Konto/Schlüsselbund/Protokoll
tauschen (gleiches Verhalten, Tests grün) → Oberfläche → Logo.
