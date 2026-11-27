// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/painting.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Angaben der App fuer rosenweg_basis.
///
/// kennung = applicationId (Android) = Bundle-ID (iOS/macOS) = GTK-ID (Linux)
/// = Schema des Ruecksprungs (ch.rosenweg4303.vorlage:/anmeldung, in Authentik
/// bei rosenweg-apps eintragen) = Paket im App-Katalog (/apps, Updater).
const appAngaben = RosenwegApp(
  kennung: 'ch.rosenweg4303.vorlage',
  name: 'Rosenweg Vorlage',
  ordner: 'rosenweg-vorlage',
  beschreibung: 'Gerüst für neue Rosenweg-Apps: Anmeldung, Seiten, Updater.',
  quelle: 'https://github.com/Rosenweg/rosenweg-vorlage',
  logo: AssetImage('assets/logo/rosenweg-vorlage-512.png'),
  // Farbe des Anmeldeschirms wie der Logo-Grund (assets/logo/erzeugen.sh GRUPPE);
  // neue-app.sh setzt sie aus werkzeug/logo/flutter-apps.txt
  gruppe: RosenwegGruppe.bewohner,
  // Hoehere Farben nur, wo die App fuer diese Gruppe etwas freischaltet
  // (docs/gruppenfarbe.md), z. B. {RosenwegGruppe.verwaltung, RosenwegGruppe.technik};
  // dazu FARBEN in assets/logo/erzeugen.sh. neue-app.sh --farben setzt beides.
  farbGruppen: {},
);

/// --dart-define=RW_ATTRAPPE=1: ohne Anmeldung und ohne Server, mit
/// erfundenen Vorfuehrdaten (Entwicklung, Bildschirmfotos, Tests).
const attrappe = bool.fromEnvironment('RW_ATTRAPPE');
