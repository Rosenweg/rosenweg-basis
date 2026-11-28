// SPDX-License-Identifier: GPL-3.0-or-later
/// Abfrage im Hintergrund: die App fragt etwa alle 15 Minuten bei der API
/// nach und zeigt Neues als [Benachrichtigung] – auch wenn sie geschlossen
/// ist. Kein Push-Dienst (kein ntfy).
///
/// | Plattform | wie | Grenze |
/// |---|---|---|
/// | Android | WorkManager, periodisch (Minimum des Systems 15 min), nur mit Netz | Energiesparen kann es strecken |
/// | iOS | BGAppRefreshTask (`<kennung>.abfrage`, AppDelegate + Info.plist) | iOS entscheidet, wann – oft seltener, nach „App beenden“ gar nicht |
/// | macOS, Windows, Linux | nur solange die App laeuft ([BeimOeffnen] mit `alle:`) | – |
/// | geteilte Telefone | wie Android, mit der Person am Telefon (ueber Rosenweg Geraet); beim Personenwechsel und Abmelden raeumt [RosenwegSitzung] Aufgaben, Erinnerungen und Benachrichtigungen weg, Rosenweg Geraet loescht danach die App-Daten | – |
///
/// Einbau in eine App (main.dart):
///
/// ```dart
/// @pragma('vm:entry-point')
/// void hintergrund() => HintergrundAbfrage.ausfuehren(appAngaben, meineAbfrage);
///
/// Future<void> meineAbfrage(HintergrundKontext k) async {
///   final liste = await k.sitzung.api.objekt('/api/…');
///   … await Benachrichtigung.zeigen(…);
/// }
///
/// void main() {
///   HintergrundAbfrage.anmelden(appAngaben, hintergrund);
///   rosenwegStarten(appAngaben, …);
/// }
/// ```
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'benachrichtigung.dart';
import 'konfig.dart';
import 'protokoll.dart';
import 'sitzung.dart';
import 'speicher.dart';

/// Was eine Abfrage bekommt.
class HintergrundKontext {
  HintergrundKontext({required this.sitzung, required this.speicher, required this.imHintergrund});

  /// Angemeldete Sitzung (nur bestehende Anmeldung, nie ein Schirm).
  final RosenwegSitzung sitzung;

  /// Eigener Speicher der Abfrage (`hintergrund.json`, getrennt vom Speicher
  /// der Oberflaeche, siehe [AppSpeicher.app]).
  final AppSpeicher speicher;

  /// true = vom System gestartet (App geschlossen); false = die laufende
  /// App fragt selbst (Desktop, [BeimOeffnen]).
  final bool imHintergrund;
}

typedef Abfrage = Future<void> Function(HintergrundKontext kontext);

class HintergrundAbfrage {
  HintergrundAbfrage._();

  /// Name der Aufgabe = iOS-Kennung (`BGTaskSchedulerPermittedIdentifiers`).
  static String aufgabe(RosenwegApp app) => '${app.kennung}.abfrage';

  /// Gibt es eine Abfrage des Systems auf dieser Plattform? (Android, iOS)
  static bool get vomSystem => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Beim Start der App: Aufgabe beim System anmelden (Android, iOS); sonst
  /// nichts. [dispatcher] ist eine Funktion auf oberster Ebene mit
  /// `@pragma('vm:entry-point')`, die [ausfuehren] aufruft.
  static Future<void> anmelden(RosenwegApp app, void Function() dispatcher, {Duration alle = const Duration(minutes: 15)}) async {
    if (!vomSystem) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Workmanager().initialize(dispatcher);
      await Workmanager().registerPeriodicTask(
        aufgabe(app),
        aufgabe(app),
        frequency: alle,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      Protokoll.schreiben('Hintergrund: anmelden ging nicht', e);
    }
  }

  /// Beim Abmelden: keine Abfragen mehr.
  static Future<void> abmelden(RosenwegApp app) async {
    if (!vomSystem) return;
    try {
      await Workmanager().cancelByUniqueName(aufgabe(app));
    } catch (e) {
      Protokoll.schreiben('Hintergrund: abmelden', e);
    }
  }

  /// Im Dispatcher aufrufen: richtet Benachrichtigungen ein, meldet still an
  /// (ohne Anmeldung: nichts tun) und ruft [abfrage].
  static void ausfuehren(RosenwegApp app, Abfrage abfrage) {
    Workmanager().executeTask((aufgabe, daten) async {
      DartPluginRegistrant.ensureInitialized();
      await einmal(app, abfrage, imHintergrund: true);
      // true: auch bei Fehlern nicht wiederholen – die naechste Runde kommt ohnehin
      return true;
    });
  }

  /// Eine Runde (auch fuer die laufende App und Tests). [sitzung] = schon
  /// angemeldete Sitzung der laufenden App; sonst still anmelden.
  static Future<bool> einmal(RosenwegApp app, Abfrage abfrage, {RosenwegSitzung? sitzung, bool imHintergrund = false}) async {
    try {
      await Benachrichtigung.einrichten(app);
      final s = sitzung ?? RosenwegSitzung(app);
      if (sitzung == null && !await s.hintergrundStarten()) {
        Protokoll.schreiben('Hintergrund: nicht angemeldet – keine Abfrage');
        return false;
      }
      await abfrage(HintergrundKontext(sitzung: s, speicher: await AppSpeicher.app('hintergrund'), imHintergrund: imHintergrund));
      return true;
    } catch (e) {
      Protokoll.schreiben('Hintergrund: Abfrage', e);
      return false;
    }
  }
}
