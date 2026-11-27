// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../aktualisierung.dart';
import '../konfig.dart';
import '../protokoll.dart';
import '../sitzung.dart';
import 'aktualisierung_leiste.dart';
import 'anmeldeschirm.dart';
import 'bausteine.dart';
import 'farben.dart';
import 'rechte_bausteine.dart';

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
          Phase.abgemeldet || Phase.anmelden => Scaffold(body: RosenwegAnmeldeSchirm(sitzung: sitzung)),
          Phase.fehler => Scaffold(body: FehlerAnzeige(text: sitzung.fehler ?? '', nochmals: sitzung.starten)),
          Phase.bereit => RechteBereich(rechte: sitzung.rechte, child: Builder(builder: inhalt)),
        },
      );
}

/// MaterialApp mit Rosenweg-Thema (hell/dunkel nach System), Anmeldetor und
/// - wenn [aktualisierung] gesetzt ist - der Leiste "Neue Fassung verfügbar"
/// ([AktualisierungsLeiste], nur Linux ausserhalb der Stationen, macOS,
/// Windows; siehe [RosenwegAktualisierung]).
class RosenwegRahmen extends StatelessWidget {
  const RosenwegRahmen({super.key, required this.sitzung, required this.inhalt, this.aktualisierung});
  final RosenwegSitzung sitzung;
  final WidgetBuilder inhalt;
  final RosenwegAktualisierung? aktualisierung;

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
        builder: aktualisierung == null || !aktualisierung!.aktiv
            ? null
            : (context, kind) => AktualisierungsLeiste(aktualisierung: aktualisierung!, child: kind ?? const SizedBox()),
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
/// und sichtbar in der App, nie still beenden), prueft die Anmeldung, startet
/// den Updater ([RosenwegAktualisierung]; aus auf Stationen, Android, iOS)
/// und zeigt den Rahmen.
void rosenwegStarten(RosenwegApp app, Widget Function(RosenwegSitzung sitzung) inhalt,
    {RosenwegSitzung? sitzung, RosenwegAktualisierung? aktualisierung}) {
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
      final a = aktualisierung ?? RosenwegAktualisierung(app);
      a.starten();
      runApp(RosenwegRahmen(sitzung: s!, inhalt: (_) => inhalt(s!), aktualisierung: a));
    },
    (e, st) {
      Protokoll.schreiben('Unerwarteter Fehler', e, st);
      s?.unerwartet(e);
    },
  );
}
