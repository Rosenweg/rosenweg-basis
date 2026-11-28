// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Der Android-Teil der Basis (android/…/RosenwegBasisPlugin.kt) hinter einer
/// kleinen Schnittstelle, damit Tests ihn ersetzen koennen.
///
/// Auf iOS gibt es einen kleinen Teil (ios/Classes): Karte per Core NFC, QR
/// per VisionKit, Geraetekennung.
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

  // ── Karte lesen auf Android (android/…/NfcKarte.kt) ──

  static const _karteKanal = EventChannel('ch.rosenweg4303.basis/karte');

  /// NFC dieses Android-Geraets: 'fehlt', 'aus' oder 'an'.
  static Future<String> nfcStand() async => await _rufen<String>('nfcStand') ?? 'fehlt';

  /// NFC-Einstellungen des Systems oeffnen (NFC einschalten).
  static Future<void> nfcEinstellungen() => _rufen<void>('nfcEinstellungen');

  /// "Nach Updates suchen" auf Android: Rosenweg Updater aus commons-rosenweg
  /// (RosenwegUpdater.jetztPruefen) zeigt das Ergebnis selbst an. false, wenn
  /// es den Android-Teil nicht gibt.
  static Future<bool> updaterPruefen() async => await _rufen<bool>('updaterPruefen') ?? false;

  /// Jede aufgelegte Karte einmal (UID als Hex); solange jemand zuhoert, ist
  /// der Reader-Modus an.
  static Stream<String> karten() => _karteKanal.receiveBroadcastStream().where((e) => e is String).cast<String>();

  // ── iOS-Teil (ios/Classes/RosenwegBasisPlugin.swift) ──

  /// identifierForVendor (gleich fuer alle Rosenweg-Apps auf diesem iPhone).
  static Future<String?> iosGeraetKennung() => _rufen<String>('geraetKennung');

  /// Name des Geraets ("iPhone", seit iOS 16 ohne den Namen der Person).
  static Future<String?> iosGeraetName() => _rufen<String>('geraetName');

  /// Kann dieses iPhone Karten lesen (Core NFC, App mit NFC-Berechtigung)?
  static Future<bool> iosNfcDa() async => await _rufen<bool>('nfcDa') ?? false;

  /// Karte lesen: iOS zeigt seinen eigenen Hinweis ("Halte dein iPhone an die
  /// Karte"). UID als Hex, null = abgebrochen oder keine Karte.
  static Future<String?> iosKarteLesen(String hinweis) async {
    try {
      return await kanal.invokeMethod<String>('karteLesen', {'hinweis': hinweis});
    } on MissingPluginException {
      return null;
    }
  }

  /// Kann dieses iPhone QR-Codes scannen (VisionKit, iOS 16+)?
  static Future<bool> iosQrDa() async => await _rufen<bool>('qrDa') ?? false;

  /// Kamera mit QR-Erkennung (VisionKit) als eigenes Fenster; Inhalt des
  /// ersten QR-Codes, null = abgebrochen.
  static Future<String?> iosQrScannen() => _rufen<String>('qrScannen');

  /// Startsymbol in der Gruppenfarbe [gruppe] (`bewohner`/`verwaltung`/
  /// `technik`, [GruppenFarbe]). Android: schaltet die activity-alias
  /// `.Symbol<Gruppe>` der App um (docs/gruppenfarbe.md); iOS: alternate
  /// icon `AppIcon-<gruppe>`, [standard] = das Haupt-Symbol. true = gewechselt;
  /// false = schon so, nicht vorhanden oder Desktop.
  static Future<bool> startsymbolSetzen(String gruppe, {required String standard}) async {
    if (!istAndroid && !istIos) return false;
    try {
      return await kanal.invokeMethod<bool>('startsymbolSetzen', {'gruppe': gruppe, 'standard': standard}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Startsymbol: ${e.message}');
      return false;
    }
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

  static bool get istIos => (plattformFuerTests ?? defaultTargetPlatform) == TargetPlatform.iOS && !kIsWeb;

  /// Linux, macOS, Windows.
  static bool get istDesktop => !kIsWeb && !istAndroid && !istIos;
}
