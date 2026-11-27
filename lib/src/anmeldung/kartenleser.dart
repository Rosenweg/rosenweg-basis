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

  /// Der passende Leser fuer den Anmeldeschirm, null = keiner moeglich
  /// (Android liest im commons-Schirm selbst).
  static Kartenleser? fuerPlattform() {
    if (ersatz != null) return ersatz!();
    if (RosenwegPlattform.istIos) return IosKartenleser();
    if (RosenwegPlattform.istDesktop) return PcscKartenleser();
    return null;
  }

  /// Der passende Leser, um IN der App Karten zu lesen (Karten anlernen,
  /// nachschlagen; [karteLesen], [KartenleserBereich]): Android ueber NFC
  /// ([AndroidKartenleser]), iOS Core NFC, Desktop PC/SC. null = Web.
  static Kartenleser? fuerApp() {
    if (ersatz != null) return ersatz!();
    if (RosenwegPlattform.istAndroid) return AndroidKartenleser();
    return fuerPlattform();
  }
}

/// Warum gerade keine Karte gelesen werden kann – als Satz fuer die Person,
/// null = bereit. Fuer [KartenleserBereich]; eigene Leser (Tests) liefern den
/// allgemeinen Satz.
Future<KartenleserHindernis?> kartenleserHindernis(Kartenleser? l) async {
  if (l == null) return KartenleserHindernis.plattform;
  if (l is AndroidKartenleser) {
    return switch (await RosenwegPlattform.nfcStand()) {
      'an' => null,
      'aus' => KartenleserHindernis.nfcAus,
      _ => KartenleserHindernis.keinNfc,
    };
  }
  if (await l.verfuegbar()) return null;
  if (l is IosKartenleser) return KartenleserHindernis.keinNfc;
  if (l is PcscKartenleser) return l.dienstDa ? KartenleserHindernis.keinLeser : KartenleserHindernis.keinPcsc;
  return KartenleserHindernis.keinLeser;
}

/// Gruende, weshalb [kartenleserHindernis] nicht bereit meldet.
enum KartenleserHindernis {
  /// Web oder unbekannte Plattform.
  plattform('Auf diesem Gerät lassen sich keine Rosenweg-Karten lesen.'),

  /// Android/iOS ohne NFC (oder iOS-App ohne NFC-Berechtigung).
  keinNfc('Dieses Gerät hat kein NFC und kann keine Karten lesen.'),

  /// Android: NFC ist ausgeschaltet.
  nfcAus('NFC ist ausgeschaltet. Bitte in den Einstellungen einschalten.'),

  /// Desktop: kein PC/SC-Dienst (Linux: pcscd fehlt oder laeuft nicht).
  keinPcsc('Der Dienst für Kartenleser fehlt (PC/SC). Unter Linux das Paket pcscd installieren.'),

  /// Desktop: PC/SC da, aber kein Leser eingesteckt.
  keinLeser('Kein Kartenleser angeschlossen. Bitte einen USB-NFC-Leser (z. B. ACR122U) einstecken.');

  const KartenleserHindernis(this.text);
  final String text;
}

/// UID einer Karte vereinheitlichen: Grossbuchstaben, ohne Leer- und
/// Trennzeichen (wie UniFi Access `nfc_id`). null = keine gueltige UID
/// (4, 7 oder 10 Byte, also 8, 14 oder 20 Hex-Zeichen).
String? karteUidNormal(String roh) {
  final u = roh.replaceAll(RegExp(r'[\s:\-]'), '').toUpperCase();
  if (!RegExp(r'^[0-9A-F]+$').hasMatch(u)) return null;
  if (u.length != 8 && u.length != 14 && u.length != 20) return null;
  return u;
}

/// Android: NFC des Handys (Reader-Modus, android/…/NfcKarte.kt) – derselbe
/// Leser wie im Anmeldeschirm von commons-rosenweg, aber in der App.
class AndroidKartenleser implements Kartenleser {
  @override
  bool get aufKnopfdruck => false;

  @override
  Future<bool> verfuegbar() async => await RosenwegPlattform.nfcStand() == 'an';

  @override
  Stream<String> lauschen() => RosenwegPlattform.karten();

  @override
  Future<String?> einmalLesen() => lauschen().first;
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

  /// Gibt es den PC/SC-Dienst (nach dem ersten [verfuegbar])?
  bool get dienstDa => _pcsc != null;

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
