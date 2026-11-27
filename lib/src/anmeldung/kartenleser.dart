// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../plattform.dart';
import '../protokoll.dart';
import 'pcsc.dart';

/// Rosenweg-Karte lesen (UniFi Access, dieselbe wie fuer die Tueren). Gelesen
/// wird nur die Seriennummer (UID als Hex, z. B. 04D4C227C22A81) - die nfc_id
/// in UniFi Access; wie `Kartenleser` im Modul anmeldeschirm von
/// commons-rosenweg.
///
/// - Desktop: USB-NFC-Leser ueber PC/SC ([PcscKartenleser]). Ohne Leser wird
///   die Karte auf dem Anmeldeschirm gar nicht erst angeboten; steckt jemand
///   einen ein, erscheint sie (alle paar Sekunden geprueft).
/// - iOS: Core NFC ([IosKartenleser]); iOS liest nur auf Knopfdruck mit
///   seinem eigenen Hinweisfenster, nicht laufend im Hintergrund.
abstract class Kartenleser {
  /// Kann jetzt gelesen werden (Leser da, NFC vorhanden)?
  Future<bool> verfuegbar();

  /// true: Lesen braucht einen Knopf ([einmalLesen], iOS). false: [lauschen]
  /// liefert laufend Karten (Desktop).
  bool get aufKnopfdruck;

  /// Desktop: jede neu aufgelegte Karte einmal (UID).
  Stream<String> lauschen();

  /// iOS: einmal lesen; null = abgebrochen.
  Future<String?> einmalLesen();

  /// Fuer Tests: statt des echten Lesers (null = kein Leser moeglich).
  @visibleForTesting
  static Kartenleser? Function()? ersatz;

  /// Der passende Leser fuer diese Plattform, null = keiner moeglich (Android
  /// liest im commons-Schirm selbst).
  static Kartenleser? fuerPlattform() {
    if (ersatz != null) return ersatz!();
    if (RosenwegPlattform.istIos) return IosKartenleser();
    if (RosenwegPlattform.istDesktop) return PcscKartenleser();
    return null;
  }
}

class PcscKartenleser implements Kartenleser {
  PcscKartenleser({Pcsc? Function()? oeffnen, this.takt = const Duration(milliseconds: 400)}) : _oeffnen = oeffnen ?? Pcsc.oeffnen;

  final Pcsc? Function() _oeffnen;
  final Duration takt;
  Pcsc? _pcsc;
  bool _versucht = false;

  /// Zuletzt protokollierter Zustand. Der Anmeldeschirm fragt alle paar
  /// Sekunden; ins Protokoll kommt nur ein WECHSEL (vorher stand dort alle
  /// 3 s "Kartenleser: kein PC/SC", Test win11-1).
  String? _zuletzt;

  void _melden(String zustand, [Object? fehler]) {
    final neu = fehler == null ? zustand : '$zustand: $fehler';
    if (neu == _zuletzt) return;
    _zuletzt = neu;
    Protokoll.schreiben(neu);
  }

  Pcsc? get _dienst {
    if (_pcsc == null && !_versucht) {
      _versucht = true;
      _pcsc = _oeffnen();
      if (_pcsc == null) _melden('Kartenleser: kein PC/SC');
    }
    return _pcsc;
  }

  @override
  bool get aufKnopfdruck => false;

  @override
  Future<bool> verfuegbar() async {
    try {
      // pcscd kann nach dem Einstecken des ersten Lesers erst starten: ohne
      // Dienst spaeter nochmals versuchen
      if (_pcsc == null) _versucht = false;
      final p = _dienst;
      if (p == null) return false;
      final n = p.leser().length;
      _melden(n == 0 ? 'Kartenleser: PC/SC da, kein Leser' : 'Kartenleser: $n Leser');
      return n > 0;
    } catch (e) {
      _melden('Kartenleser', e);
      return false;
    }
  }

  @override
  Stream<String> lauschen() {
    late StreamController<String> c;
    Timer? t;
    String? liegt; // UID der Karte, die gerade aufliegt (nur einmal melden)
    void schauen(Timer _) {
      final p = _dienst;
      if (p == null) return;
      String? jetzt;
      try {
        for (final l in p.leser()) {
          jetzt = p.uid(l);
          if (jetzt != null) break;
        }
      } catch (e) {
        _melden('Kartenleser', e);
      }
      if (jetzt != null && jetzt != liegt) c.add(jetzt);
      liegt = jetzt;
    }

    c = StreamController<String>(
      onListen: () => t = Timer.periodic(takt, schauen),
      onCancel: () => t?.cancel(),
    );
    return c.stream;
  }

  @override
  Future<String?> einmalLesen() => lauschen().first;
}

class IosKartenleser implements Kartenleser {
  @override
  bool get aufKnopfdruck => true;

  @override
  Future<bool> verfuegbar() => RosenwegPlattform.iosNfcDa();

  @override
  Stream<String> lauschen() => const Stream.empty();

  @override
  Future<String?> einmalLesen() => RosenwegPlattform.iosKarteLesen('Halte die Rosenweg-Karte oben an die Rückseite des iPhones.');
}
