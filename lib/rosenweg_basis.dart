// SPDX-License-Identifier: GPL-3.0-or-later
/// Gemeinsame Basis der Rosenweg-Funktions-Apps (Flutter: Linux, macOS, Windows, Android, iOS).
///
/// Eine App braucht im Kern zwei Dinge:
///
/// ```dart
/// const app = RosenwegApp(
///   kennung: 'ch.rosenweg4303.profil',
///   name: 'Rosenweg Profil',
///   ordner: 'rosenweg-profil',
///   beschreibung: 'Deine Angaben im Rosenweg-Portal.',
///   quelle: 'https://github.com/Rosenweg/rosenweg-profil',
///   logo: AssetImage('assets/logo/rosenweg-profil-512.png'),
/// );
///
/// void main() => rosenwegStarten(app, (sitzung) => MeineSeite(api: sitzung.api));
/// ```
///
/// Siehe README.md fuer den Aufbau und docs/ fuer Authentik und geteilte
/// Telefone.
library;

export 'src/aktualisierung.dart';
export 'src/anmeldung/android_konto.dart';
export 'src/anmeldung/geraete_schluessel.dart';
export 'src/anmeldung/karten_sitzung.dart';
export 'src/anmeldung/kartenleser.dart';
export 'src/anmeldung/rosenweg_konto.dart' show RosenwegKonto, AnmeldeFehler;
export 'src/anmeldung/ruecksprung.dart';
export 'src/anmeldung/kerberos.dart' show KerberosTicket, KeinKerberos;
export 'src/anmeldung/schluesselbund.dart' show Schluesselbund;
export 'src/anmeldung/stille_anmeldung.dart';
export 'src/fehler_fuer_person.dart';
export 'src/gruppenfarbe.dart';
export 'src/konfig.dart';
export 'src/liste.dart';
export 'src/netz/api.dart';
export 'src/netz/dateien.dart';
export 'src/netz/fehler.dart';
export 'src/netz/haus_erkennung.dart' show HausErkennung, systemDnsServer, resolvConfLesen, txtAbfragen, dnsFrage, dnsTxtLesen;
export 'src/netz/json_anfrage.dart';
export 'src/oberflaeche/aktualisierung_leiste.dart';
export 'src/oberflaeche/anmeldeschirm.dart';
export 'src/oberflaeche/bausteine.dart';
export 'src/oberflaeche/beim_oeffnen.dart';
export 'src/oberflaeche/dateien_bausteine.dart';
export 'src/oberflaeche/farben.dart';
export 'src/oberflaeche/formular.dart';
export 'src/oberflaeche/foto_feld.dart';
export 'src/oberflaeche/geruest.dart';
export 'src/oberflaeche/karte_lesen.dart';
export 'src/oberflaeche/liste_ansicht.dart';
export 'src/oberflaeche/pdf_ansicht.dart';
export 'src/oberflaeche/rahmen.dart';
export 'src/oberflaeche/rechte_bausteine.dart';
export 'src/oberflaeche/scanner.dart';
export 'src/oberflaeche/wochenraster.dart';
export 'src/plattform.dart' show RosenwegPlattform;
export 'src/protokoll.dart';
export 'src/rechte.dart';
export 'src/sitzung.dart';
export 'src/speicher.dart';
export 'src/station.dart';
export 'src/verwaltet.dart';
