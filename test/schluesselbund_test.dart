// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Wie libsecret ohne Secret-Service-Dienst (Station ohne gnome-keyring).
class _OhneDienst extends FlutterSecureStorage {
  const _OhneDienst();
  static PlatformException get _fehler =>
      PlatformException(code: 'Libsecret error', message: 'Failed to unlock the keyring');
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions,
          LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) =>
      Future.error(_fehler);
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions,
          AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions,
          AppleOptions? mOptions, WindowsOptions? wOptions}) =>
      Future.error(_fehler);
  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions,
          LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) =>
      Future.error(_fehler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const roh = FlutterSecureStorage();

  test('alte Einzel-Eintraege werden in einen uebernommen und geloescht', () async {
    FlutterSecureStorage.setMockInitialValues({
      'rosenweg_refresh_token': 'rt1',
      'rosenweg_angemeldet_am': '2026-11-26T12:47:07Z',
      'rosenweg_geraet': 'abc',
    });
    final s = Schluesselbund('rosenweg_vm', speicher: roh, alteEintraege: const {
      'refresh_token': 'rosenweg_refresh_token',
      'angemeldet_am': 'rosenweg_angemeldet_am',
      'geraet': 'rosenweg_geraet',
    });
    expect(await s.lesen('refresh_token'), 'rt1');
    expect(await s.lesen('geraet'), 'abc');
    final alle = await roh.readAll();
    expect(alle.keys, ['rosenweg_vm']);
    expect(jsonDecode(alle['rosenweg_vm']!), {
      'refresh_token': 'rt1',
      'angemeldet_am': '2026-11-26T12:47:07Z',
      'geraet': 'abc',
    });
  });

  test('setzen und entfernen in einem Eintrag; leer = Eintrag weg', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = Schluesselbund('rosenweg-test', speicher: roh);
    await s.setzen({'refresh_token': 'x', 'angemeldet_am': 'y'});
    expect((await roh.readAll()).keys, ['rosenweg-test']);
    await s.setzen({'refresh_token': null, 'angemeldet_am': null});
    expect(await roh.readAll(), isEmpty);
    expect(await Schluesselbund('rosenweg-test', speicher: roh).lesen('refresh_token'), isNull);
  });

  test('ohne Schluesselbund-Dienst: Werte bleiben im Speicher, kein Fehler', () async {
    final s = Schluesselbund('rosenweg-test', speicher: const _OhneDienst());
    expect(await s.lesen('refresh_token'), isNull);
    expect(s.nurImSpeicher, isTrue);
    await s.setzen({'refresh_token': 'x', 'geraet': 'g'});
    expect(await s.lesen('refresh_token'), 'x');
    await s.setzen({'refresh_token': null});
    expect(await s.lesen('refresh_token'), isNull);
    expect(await s.lesen('geraet'), 'g');
  });

  group('Secret Service (Linux)', () {
    test('kein Schluesselbund ohne Rueckfrage: nur im Speicher, libsecret unberuehrt', () async {
      var gefragt = 0;
      // _OhneDienst wuerde bei jedem Zugriff scheitern; er darf gar nicht gefragt werden
      final s = Schluesselbund('rosenweg-test', speicher: const _OhneDienst(), systemBereit: () async {
        gefragt++;
        return false;
      });
      expect(await s.lesen('refresh_token'), isNull);
      await s.setzen({'refresh_token': 'rt'});
      expect(await s.lesen('refresh_token'), 'rt');
      expect(s.nurImSpeicher, isTrue);
      expect(gefragt, 1);
    });

    test('bereit: normal speichern', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final s = Schluesselbund('rosenweg-test', speicher: roh, systemBereit: () async => true);
      await s.setzen({'a': '1'});
      expect(s.nurImSpeicher, isFalse);
      expect(await Schluesselbund('rosenweg-test', speicher: roh).lesen('a'), '1');
    });

    test('Antwort von busctl lesen', () {
      expect(Schluesselbund.secretServiceAntwortBereit('o "/"\n'), isFalse);
      expect(Schluesselbund.secretServiceAntwortBereit('o "/org/freedesktop/secrets/collection/login"'), isTrue);
    });
  });
}
