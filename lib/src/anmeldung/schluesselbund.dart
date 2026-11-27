// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../protokoll.dart';

/// Alles, was eine App sicher speichert, in EINEM Eintrag (JSON):
/// Refresh-Token, Zeitpunkt der Browser-Anmeldung, offene PKCE-Anfrage.
///
/// Warum einer: Auf macOS fragt der Schluesselbund bei einer unsignierten
/// (Entwicklungs-)App pro Eintrag nach Erlaubnis.
///
/// Speicher je Plattform (flutter_secure_storage): Linux libsecret (Secret
/// Service), Android Keystore, macOS Schluesselbund, Windows
/// Anmeldeinformationen.
///
/// Aus rosenweg-vm lib/anmeldung/schluesselbund.dart, mit frei waehlbarem
/// Eintrag (eine App, ein Eintrag) und optionaler Uebernahme alter
/// Einzel-Eintraege.
class Schluesselbund {
  Schluesselbund(this.eintrag,
      {FlutterSecureStorage? speicher, this.alteEintraege = const {}, Future<bool> Function()? systemBereit})
      : _speicher = speicher ??
            const FlutterSecureStorage(
              // Ohne den Data-Protection-Schluesselbund: der braucht eine
              // signierte App mit Team-ID, was im Entwicklungsbau fehlt.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            ),
        // Nicht unter `flutter test` (dort ersetzt setMockInitialValues den Speicher)
        _systemBereit = systemBereit ??
            (speicher == null && Platform.isLinux && !Platform.environment.containsKey('FLUTTER_TEST')
                ? linuxSecretServiceBereit
                : null);

  /// Vor dem ersten Zugriff: darf der Schluesselbund des Systems benutzt
  /// werden, ohne dass er die Person etwas fragt? false = gleich
  /// [nurImSpeicher], ohne libsecret anzufassen. null = nicht pruefen
  /// (alle Plattformen ausser Linux).
  final Future<bool> Function()? _systemBereit;

  /// Linux: gibt es einen Schluesselbund, den libsecret ohne Rueckfrage
  /// benutzen kann? Gefragt wird der Secret Service selbst (`ReadAlias
  /// default`, Standard-API, egal ob gnome-keyring oder KeePassXC). Aus
  /// rosenweg-vm (`PruefenderSpeicher`, 1.1.x #28), jetzt fuer alle Apps.
  ///
  /// - kein Dienst: libsecret scheiterte ohnehin (so bisher auf den Stationen).
  /// - Dienst, aber keine Standard-Sammlung (`"/"`): libsecret wuerde beim
  ///   ersten Speichern ein Fenster "Neuen Schluesselbund anlegen" oeffnen und
  ///   nach einem Passwort fragen. Auf den Stationen ist das genau der Fall,
  ///   wenn der Anmelde-Schluesselbund nach einem Passwortwechsel im AD
  ///   beiseitegelegt wurde (os-stationen, schluesselbund-pruefen.sh); bei der
  ///   naechsten Anmeldung ist er wieder da. Bis dahin lieber nichts merken
  ///   als fragen.
  /// - busctl fehlt oder antwortet nicht rechtzeitig: libsecret selbst
  ///   entscheiden lassen.
  static Future<bool> linuxSecretServiceBereit() async {
    try {
      final r = await Process.run('busctl', [
        '--user', 'call', 'org.freedesktop.secrets', '/org/freedesktop/secrets',
        'org.freedesktop.Secret.Service', 'ReadAlias', 's', 'default',
      ]).timeout(const Duration(seconds: 5));
      if (r.exitCode != 0) {
        Protokoll.schreiben('Secret Service antwortet nicht: ${'${r.stderr}'.trim()}');
        return false;
      }
      return secretServiceAntwortBereit('${r.stdout}');
    } on ProcessException {
      return true;
    } on TimeoutException {
      return true;
    }
  }

  /// Ausgabe von `busctl … ReadAlias s default`: `o "/"` heisst "keine
  /// Standard-Sammlung" (oeffentlich fuer Tests).
  static bool secretServiceAntwortBereit(String ausgabe) => !ausgabe.trim().endsWith('"/"');

  /// Name des einen Eintrags, z. B. "rosenweg-profil".
  final String eintrag;

  /// Fruehere Einzel-Eintraege (neuer Schluessel -> alter Eintrag), die beim
  /// ersten Lesen uebernommen und geloescht werden. Fuer neue Apps leer;
  /// rosenweg-vm braeuchte hier seine alten rosenweg_*-Eintraege.
  final Map<String, String> alteEintraege;

  final FlutterSecureStorage _speicher;
  Map<String, String>? _werte;
  Future<Map<String, String>>? _laden;

  /// true, sobald der Schluesselbund des Systems versagt hat. Dann lebt alles
  /// nur noch im Speicher der App, bis sie endet.
  ///
  /// Linux: libsecret braucht einen Secret-Service-Dienst (gnome-keyring,
  /// KeePassXC) in der Sitzung. Auf den Rosenweg-Stationen laeuft keiner
  /// (desktop-test, 26.11.2026). Ohne diesen Rueckfall scheiterte dort schon
  /// das erste Lesen — und mit ihm die Anmeldung. So geht es weiter, nur ohne
  /// Erinnerung ueber das Programmende hinaus; die stille Anmeldung ueber die
  /// Browser-Sitzung bleibt davon unberuehrt.
  bool get nurImSpeicher => _nurImSpeicher;
  bool _nurImSpeicher = false;

  void _versagt(Object e) {
    if (!_nurImSpeicher) {
      Protokoll.schreiben('Schluesselbund des Systems nicht nutzbar, Werte nur bis Programmende', e);
    }
    _nurImSpeicher = true;
  }

  Future<Map<String, String>> _alle() => _laden ??= _ladenOderLeer();

  Future<Map<String, String>> _ladenOderLeer() async {
    try {
      return await _ladenUndUebernehmen();
    } catch (e) {
      _versagt(e);
      return _werte ??= <String, String>{};
    }
  }

  Future<Map<String, String>> _ladenUndUebernehmen() async {
    final bereit = _systemBereit;
    if (bereit != null && !await bereit()) {
      throw StateError('kein Schluesselbund, in den ohne Rueckfrage geschrieben werden kann');
    }
    final roh = await _speicher.read(key: eintrag);
    final werte = <String, String>{};
    if (roh != null) {
      try {
        (jsonDecode(roh) as Map<String, dynamic>).forEach((k, v) {
          if (v is String) werte[k] = v;
        });
      } catch (e) {
        Protokoll.schreiben('Schluesselbund-Eintrag unlesbar, wird neu angelegt', e);
      }
    }
    var uebernommen = false;
    for (final MapEntry(key: neu, value: alt) in alteEintraege.entries) {
      final v = await _speicher.read(key: alt);
      if (v == null) continue;
      werte.putIfAbsent(neu, () => v);
      uebernommen = true;
    }
    _werte = werte;
    if (uebernommen) {
      await _schreiben();
      for (final alt in alteEintraege.values) {
        await _speicher.delete(key: alt);
      }
      Protokoll.schreiben('Schluesselbund: alte Einzel-Eintraege in einen zusammengefuehrt');
    }
    return werte;
  }

  Future<void> _schreiben() async {
    if (_nurImSpeicher) return;
    final w = _werte ?? const {};
    try {
      if (w.isEmpty) {
        await _speicher.delete(key: eintrag);
      } else {
        await _speicher.write(key: eintrag, value: jsonEncode(w));
      }
    } catch (e) {
      _versagt(e);
    }
  }

  Future<String?> lesen(String schluessel) async => (await _alle())[schluessel];

  /// Mehrere Werte auf einmal setzen (null = entfernen); ein Schreibvorgang.
  Future<void> setzen(Map<String, String?> neu) async {
    final w = await _alle();
    neu.forEach((k, v) => v == null ? w.remove(k) : w[k] = v);
    await _schreiben();
  }
}
