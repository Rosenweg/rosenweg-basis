// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Der Android-Teil der Basis (android/…/RosenwegBasisPlugin.kt) hinter einer
/// kleinen Schnittstelle, damit Tests ihn ersetzen koennen.
///
/// Auf Linux/Desktop gibt es ihn nicht; dort liefern die Methoden "nichts"
/// (leere Liste, false, null), ohne zu werfen.
class RosenwegPlattform {
  RosenwegPlattform._();

  static const kanal = MethodChannel('ch.rosenweg4303.basis');

  static final _ruecksprung = StreamController<String>.broadcast();
  static bool _lauscht = false;

  /// Ruecksprung-Adressen von Authentik (Android, `<kennung>:/anmeldung?...`).
  static Stream<String> get ruecksprung {
    if (!_lauscht) {
      _lauscht = true;
      kanal.setMethodCallHandler((call) async {
        if (call.method == 'ruecksprung' && call.arguments is String) {
          _ruecksprung.add(call.arguments as String);
        }
        return null;
      });
    }
    return _ruecksprung.stream;
  }

  /// Ruecksprung, der ankam, bevor Dart lauschte (App war beendet). Einmalig.
  static Future<String?> ruecksprungAusstehend() => _rufen<String>('ruecksprungAusstehend');

  /// DNS-Server des aktiven Netzes (nur Android).
  static Future<List<String>> dnsServer() async {
    try {
      return await kanal.invokeListMethod<String>('dnsServer') ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Rosenweg Geraet installiert? (geteiltes Telefon, nur Android)
  static Future<bool> geraetDa() async => await _rufen<bool>('geraetDa') ?? false;

  /// ContentResolver.call auf content://ch.rosenweg4303.telefon.anlage.
  /// Antwort: Inhalt des Bundles; bei Ausnahmen {fehler_art: signatur|nicht_installiert|unbekannt}.
  static Future<Map<String, Object?>> geraetRufen(String methode, {String? arg, Map<String, Object?>? extras}) async {
    final m = await kanal.invokeMapMethod<String, Object?>('geraetRufen', {
      'methode': methode,
      'arg': arg,
      'extras': extras,
    });
    return m ?? const {};
  }

  static Future<T?> _rufen<T>(String methode) async {
    try {
      return await kanal.invokeMethod<T>(methode);
    } on MissingPluginException {
      return null;
    }
  }

  /// Fuer Tests: Plattform-Weiche.
  @visibleForTesting
  static TargetPlatform? plattformFuerTests;

  static bool get istAndroid =>
      (plattformFuerTests ?? defaultTargetPlatform) == TargetPlatform.android && !kIsWeb;
}
