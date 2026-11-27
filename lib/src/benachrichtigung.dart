// SPDX-License-Identifier: GPL-3.0-or-later
/// Benachrichtigungen des Systems – ohne Push-Dienst (kein ntfy, Entscheid
/// Stefan 27.11.2026). Die App erzeugt sie selbst: aus der Abfrage im
/// Hintergrund ([HintergrundAbfrage]), aus der Abfrage, solange sie laeuft
/// ([BeimOeffnen]), oder geplant (Erinnerung zu einer Zeit).
///
/// | Plattform | sofort | geplant | Antippen oeffnet die App |
/// |---|---|---|---|
/// | Android 8+ | ja (ab Android 13 nach Erlaubnis) | ja (ungefaehr, auch nach Neustart) | ja |
/// | iOS | ja (nach Erlaubnis) | ja | ja |
/// | macOS | ja (nach Erlaubnis) | ja | ja |
/// | Windows | ja | ja | ja |
/// | Linux | ja (libnotify ueber D-Bus) | nur solange die App laeuft | ja |
///
/// [ziel] einer Benachrichtigung ist ein kurzer Text der App (z. B.
/// `meine/41`); beim Antippen kommt er ueber [angetippt] bzw. [startZiel].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdaten;
import 'package:timezone/timezone.dart' as tz;

import 'konfig.dart';
import 'protokoll.dart';

class Benachrichtigung {
  Benachrichtigung._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _angetippt = StreamController<String>.broadcast();
  static final _linuxUhren = <int, Timer>{};
  static Future<bool>? _bereit;
  static RosenwegApp? _app;

  /// Fuer Tests: statt des Plugins (zeigt nichts, merkt sich alles).
  @visibleForTesting
  static List<({int id, String titel, String text, String? ziel, DateTime? wann})>? attrappe;

  /// Ziele angetippter Benachrichtigungen, solange die App laeuft.
  static Stream<String> get angetippt => _angetippt.stream;

  /// Einmal beim Start (auch im Hintergrund-Isolate). Fragt nicht nach der
  /// Erlaubnis – das macht [erlaubnisFragen], wenn die Person es braucht.
  static Future<bool> einrichten(RosenwegApp app) {
    // Attrappe: nichts zwischenspeichern – ein in einem frueheren Widget-Test
    // (andere FakeAsync-Zone) erzeugtes Future wuerde dort nie fertig
    if (attrappe != null) {
      _app = app;
      return Future.value(true);
    }
    return _bereit ??= _einrichten(app);
  }

  static Future<bool> _einrichten(RosenwegApp app) async {
    _app = app;
    if (attrappe != null || kIsWeb) return true;
    try {
      tzdaten.initializeTimeZones();
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: const DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
          macOS: const DarwinInitializationSettings(
              requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
          linux: const LinuxInitializationSettings(defaultActionName: 'Öffnen'),
          windows: WindowsInitializationSettings(appName: app.name, appUserModelId: app.kennung, guid: windowsGuid(app.kennung)),
        ),
        onDidReceiveNotificationResponse: (r) {
          final z = r.payload;
          if (z != null && z.isNotEmpty) _angetippt.add(z);
        },
      );
      return ok ?? true;
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung: einrichten ging nicht', e);
      return false;
    }
  }

  /// Ziel der Benachrichtigung, mit der die App gestartet wurde (einmalig).
  static Future<String?> startZiel() async {
    if (attrappe != null || kIsWeb) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      final z = d?.didNotificationLaunchApp == true ? d?.notificationResponse?.payload : null;
      return z == null || z.isEmpty ? null : z;
    } catch (e) {
      return null;
    }
  }

  /// Erlaubnis holen (Android 13+, iOS, macOS); andere Plattformen: true.
  static Future<bool> erlaubnisFragen() async {
    if (attrappe != null || kIsWeb) return true;
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            true;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true, badge: true) ??
            false;
      }
      if (Platform.isMacOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true, badge: true) ??
            false;
      }
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung: Erlaubnis', e);
      return false;
    }
    return true;
  }

  static NotificationDetails _details(String? kanal) {
    final app = _app;
    final k = kanal ?? 'meldungen';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        '${app?.kennung ?? 'rosenweg'}.$k',
        kanal == null ? 'Meldungen' : _kanalName(k),
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
      linux: const LinuxNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  static String _kanalName(String k) => k.isEmpty ? 'Meldungen' : '${k[0].toUpperCase()}${k.substring(1)}';

  /// Sofort zeigen. Gleiche [id] ersetzt eine fruehere (z. B. je Meldung).
  /// [kanal]: Android-Kanal (eigene Einstellung je Art, z. B. `erinnerungen`).
  static Future<void> zeigen({
    required int id,
    required String titel,
    required String text,
    String? ziel,
    String? kanal,
  }) async {
    final a = attrappe;
    if (a != null) {
      a
        ..removeWhere((x) => x.id == id) // gleiche Id ersetzt, wie im System
        ..add((id: id, titel: titel, text: text, ziel: ziel, wann: null));
      return;
    }
    if (kIsWeb) return;
    try {
      await _plugin.show(id: id, title: titel, body: text, notificationDetails: _details(kanal), payload: ziel);
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung zeigen', e);
    }
  }

  /// Zu einer Zeit zeigen (Erinnerung). Liegt [wann] in der Vergangenheit,
  /// passiert nichts. Android: ungefaehr (ohne Erlaubnis fuer exakte
  /// Wecker, wenige Minuten Spiel). Linux: nur solange die App laeuft.
  static Future<void> planen({
    required int id,
    required DateTime wann,
    required String titel,
    required String text,
    String? ziel,
    String? kanal,
  }) async {
    if (!wann.isAfter(DateTime.now())) return;
    final a = attrappe;
    if (a != null) {
      a
        ..removeWhere((x) => x.id == id)
        ..add((id: id, titel: titel, text: text, ziel: ziel, wann: wann));
      return;
    }
    if (kIsWeb) return;
    if (Platform.isLinux) {
      _linuxUhren.remove(id)?.cancel();
      _linuxUhren[id] = Timer(wann.difference(DateTime.now()), () {
        _linuxUhren.remove(id);
        zeigen(id: id, titel: titel, text: text, ziel: ziel, kanal: kanal);
      });
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(wann.toUtc(), tz.UTC),
        notificationDetails: _details(kanal),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: titel,
        body: text,
        payload: ziel,
      );
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung planen', e);
    }
  }

  /// Ids der geplanten, noch nicht gezeigten Benachrichtigungen dieser App
  /// (Linux: die, die in der laufenden App warten).
  static Future<Set<int>> geplant() async {
    final a = attrappe;
    if (a != null) return {for (final x in a) if (x.wann != null) x.id};
    if (kIsWeb) return {};
    if (Platform.isLinux) return _linuxUhren.keys.toSet();
    try {
      return {for (final r in await _plugin.pendingNotificationRequests()) r.id};
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung: geplante lesen', e);
      return {};
    }
  }

  /// Gezeigte oder geplante Benachrichtigung entfernen.
  static Future<void> entfernen(int id) async {
    attrappe?.removeWhere((x) => x.id == id);
    _linuxUhren.remove(id)?.cancel();
    if (attrappe != null || kIsWeb) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      Protokoll.schreiben('Benachrichtigung entfernen', e);
    }
  }

  /// Feste GUID je App fuer Windows (aus der Kennung, damit sie bei jedem
  /// Start gleich bleibt).
  static String windowsGuid(String kennung) {
    final h = sha1.convert(utf8.encode('rosenweg-benachrichtigung:$kennung')).toString();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-5${h.substring(13, 16)}-a${h.substring(17, 20)}-${h.substring(20, 32)}';
  }

  /// Stabile Zahl je Text (z. B. `meldung-41`) fuer [zeigen]/[planen].
  static int idFuer(String text) => sha1.convert(utf8.encode(text)).bytes.take(4).fold<int>(0, (a, b) => (a << 8) | b) & 0x7fffffff;
}
