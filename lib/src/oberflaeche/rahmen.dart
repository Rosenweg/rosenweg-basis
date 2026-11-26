// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../konfig.dart';
import '../protokoll.dart';
import '../sitzung.dart';
import 'bausteine.dart';
import 'farben.dart';

/// Zeigt je nach Phase der Sitzung Warten, Anmeldeschirm, Fehler — oder,
/// sobald angemeldet, den Inhalt der App ([inhalt]).
class AnmeldeTor extends StatelessWidget {
  const AnmeldeTor({super.key, required this.sitzung, required this.inhalt});
  final RosenwegSitzung sitzung;
  final WidgetBuilder inhalt;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: sitzung,
        builder: (context, _) => switch (sitzung.phase) {
          Phase.pruefen => const Scaffold(body: LadeAnzeige()),
          Phase.abgemeldet || Phase.anmelden => Scaffold(body: AnmeldeSchirm(sitzung: sitzung)),
          Phase.fehler => Scaffold(body: FehlerAnzeige(text: sitzung.fehler ?? '', nochmals: sitzung.starten)),
          Phase.bereit => inhalt(context),
        },
      );
}

/// MaterialApp mit Rosenweg-Thema (hell/dunkel nach System) und Anmeldetor.
class RosenwegRahmen extends StatelessWidget {
  const RosenwegRahmen({super.key, required this.sitzung, required this.inhalt});
  final RosenwegSitzung sitzung;
  final WidgetBuilder inhalt;

  // Personenwechsel am geteilten Telefon: neuer Schluessel = neue App (auch
  // geoeffnete Seiten und ihr Zustand sind weg), die Daten kommen neu.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: sitzung.personStand,
        builder: (context, stand, _) => _app(stand),
      );

  Widget _app(int stand) => MaterialApp(
        key: ValueKey(stand),
        title: sitzung.app.name,
        debugShowCheckedModeBanner: false,
        theme: rosenwegThema(Brightness.light),
        darkTheme: rosenwegThema(Brightness.dark),
        locale: const Locale('de', 'CH'),
        supportedLocales: const [Locale('de', 'CH'), Locale('de')],
        // Deutsche Texte auch in Flutters eigenen Dialogen (Lizenzen,
        // Datumswahl, Kopieren/Einfuegen).
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AnmeldeTor(sitzung: sitzung, inhalt: inhalt),
      );
}

/// Einstieg jeder App:
///
/// ```dart
/// void main() => rosenwegStarten(profilApp, (sitzung) => ProfilSeite(sitzung: sitzung));
/// ```
///
/// Richtet die Logdatei ein, faengt alle nicht aufgefangenen Fehler (Logdatei
/// und sichtbar in der App, nie still beenden), prueft die Anmeldung und
/// zeigt den Rahmen.
void rosenwegStarten(RosenwegApp app, Widget Function(RosenwegSitzung sitzung) inhalt, {RosenwegSitzung? sitzung}) {
  Protokoll.einrichten(app.ordner);
  RosenwegSitzung? s;
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      Protokoll.schreiben('Start ${app.name} (${kDebugMode ? 'Debug' : 'Release'})');
      FlutterError.onError = (d) {
        FlutterError.presentError(d);
        Protokoll.schreiben('Flutter-Fehler', d.exception, d.stack);
      };
      PlatformDispatcher.instance.onError = (e, st) {
        Protokoll.schreiben('Unerwarteter Fehler', e, st);
        s?.unerwartet(e);
        return true;
      };
      s = sitzung ?? RosenwegSitzung(app);
      s!.starten();
      runApp(RosenwegRahmen(sitzung: s!, inhalt: (_) => inhalt(s!)));
    },
    (e, st) {
      Protokoll.schreiben('Unerwarteter Fehler', e, st);
      s?.unerwartet(e);
    },
  );
}
