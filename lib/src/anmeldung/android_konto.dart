// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/services.dart';

import '../konfig.dart';
import '../netz/api.dart';
import '../netz/fehler.dart';
import '../plattform.dart';

/// Anmeldung auf Android-Handys OHNE Rosenweg Geraet (Stefan 26.11.2026):
/// nicht in Dart, sondern ueber commons-rosenweg (Modul `cloud`), wie in den
/// Kotlin-Apps. So ist der Anmeldeschirm ueberall derselbe - wie der
/// Sperrbildschirm der geteilten Telefone: Rosenweg-Karte hinten ans Telefon
/// halten oder "Mit Rosenweg-Konto anmelden" - und wird nur einmal gepflegt.
///
/// Token, Karten-Sitzung (Schluessel im Android-Keystore) und Browser-
/// Anmeldung liegen in Kotlin (RosenwegAnmeldung, KartenSitzung). Dart sieht
/// nur das kurzlebige Zugangs-Token fuer die API. Jede App meldet sich selbst
/// an. Auf dem Desktop bleibt [RosenwegKonto] (Browser, Kerberos).
abstract class AndroidKonto implements Zugangsquelle {
  /// Angemeldet (Browser oder Karte)? Liest dabei Name und E-Mail.
  Future<bool> get angemeldet;

  String? get name;
  String? get email;

  /// Mit der Karte angemeldet (nicht im Browser)?
  bool get mitKarte;

  /// Anmeldeschirm von commons-rosenweg zeigen; true = angemeldet.
  /// "Zurueck" auf dem Schirm schliesst die App (wie in den Kotlin-Apps).
  Future<bool> anmeldeSchirm();

  /// Frische Browser-Anmeldung (prompt=login) fuer heikle Aktionen; true = bestaetigt.
  Future<bool> bestaetigen();

  /// Nur diese App abmelden (beide Wege).
  Future<void> abmelden();
}

/// Kanal zum Android-Teil (RosenwegBasisPlugin.kt), der commons-rosenweg ruft.
class AndroidKontoKanal implements AndroidKonto {
  AndroidKontoKanal({MethodChannel? kanal, this.bestaetigenHoechstens = const Duration(minutes: 5), this.gruppe})
      : _kanal = kanal ?? RosenwegPlattform.kanal;

  final MethodChannel _kanal;
  final Duration bestaetigenHoechstens;

  /// Gruppe der App ([RosenwegApp.gruppe]) fuer die Farbe des nativen
  /// Anmeldeschirms; null = dessen Standard (blau bzw. Ressource der App).
  final RosenwegGruppe? gruppe;

  @override
  String? name;
  @override
  String? email;
  @override
  bool mitKarte = false;

  @override
  Future<bool> get angemeldet async {
    final m = await _kanal.invokeMapMethod<String, Object?>('kontoStand') ?? const {};
    name = m['name'] as String?;
    email = m['email'] as String?;
    mitKarte = m['mitKarte'] == true;
    return m['angemeldet'] == true;
  }

  @override
  Future<String?> zugangsToken() async {
    try {
      return await _kanal.invokeMethod<String>('zugangsToken');
    } on PlatformException catch (e) {
      // Server nur gerade nicht erreichbar: die Anmeldung bleibt.
      if (e.code == 'netz') throw ServerNichtErreichbar();
      rethrow;
    }
  }

  @override
  void zugangUngueltig() => _kanal.invokeMethod<void>('zugangUngueltig');

  @override
  Future<bool> anmeldeSchirm() async {
    final ok = await _kanal.invokeMethod<bool>('anmeldeSchirm', {if (gruppe != null) 'gruppe': gruppe!.name}) ?? false;
    if (ok) await angemeldet;
    return ok;
  }

  @override
  Future<bool> bestaetigen() async {
    final vorher = await _kanal.invokeMethod<int>('angemeldetUm') ?? 0;
    await _kanal.invokeMethod<void>('bestaetigen');
    // Der Browser meldet sich ueber RosenwegAnmeldungActivity (commons) zurueck;
    // erkennbar am neuen Zeitpunkt der Anmeldung.
    final bis = DateTime.now().add(bestaetigenHoechstens);
    while (DateTime.now().isBefore(bis)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if ((await _kanal.invokeMethod<int>('angemeldetUm') ?? 0) > vorher) return true;
    }
    return false;
  }

  @override
  Future<void> abmelden() async {
    name = email = null;
    mitKarte = false;
    await _kanal.invokeMethod<void>('abmelden');
  }
}
