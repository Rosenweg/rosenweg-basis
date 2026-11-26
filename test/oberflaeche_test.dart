// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

const app = RosenwegApp(
  kennung: 'ch.rosenweg4303.test',
  name: 'Rosenweg Test',
  ordner: 'rosenweg-test',
  beschreibung: 'Eine Test-App.',
  quelle: 'https://github.com/Rosenweg/rosenweg-test',
);

class _Transport implements Transport {
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async => (status: 200, json: {'ok': true});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    Protokoll.nurKonsole = true;
    // Desktop-Weg (Browser); Android steht unten mit einer Attrappe von AndroidKonto
    RosenwegPlattform.plattformFuerTests = TargetPlatform.linux;
  });
  tearDownAll(() => RosenwegPlattform.plattformFuerTests = null);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('ohne Anmeldung: Anmeldeschirm mit einem Knopf', (t) async {
    final s = RosenwegSitzung(app, geraetDa: () async => false);
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    expect(s.phase, Phase.abgemeldet);
    expect(find.text('Rosenweg Test'), findsOneWidget);
    expect(find.text('Eine Test-App.'), findsOneWidget);
    expect(find.text('Mit Rosenweg-Konto anmelden'), findsOneWidget);
    expect(find.text('INHALT'), findsNothing);
  });

  testWidgets('geteiltes Telefon: direkt bereit, keine eigene Anmeldung', (t) async {
    final s = RosenwegSitzung(app, geraetDa: () async => true);
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    expect(s.geteiltesTelefon, isTrue);
    expect(s.api.transport, isA<GeraetTransport>());
    expect(find.text('INHALT'), findsOneWidget);
  });

  testWidgets('geteiltes Telefon: Personenwechsel baut die App neu (auch geoeffnete Seiten)', (t) async {
    final wechsel = StreamController<String>.broadcast();
    final s = RosenwegSitzung(app, geraetDa: () async => true, personWechsel: wechsel.stream);
    await t.pumpWidget(RosenwegRahmen(
        sitzung: s,
        inhalt: (_) => Builder(
            builder: (c) => TextButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const Text('SEITE'))),
                child: const Text('INHALT')))));
    await t.runAsync(s.starten);
    await t.pump();
    await t.tap(find.text('INHALT'));
    await t.pumpAndSettle();
    expect(find.text('SEITE'), findsOneWidget);
    wechsel.add('angemeldet');
    await t.pumpAndSettle();
    expect(s.personStand.value, 1);
    expect(find.text('SEITE'), findsNothing);
    expect(find.text('INHALT'), findsOneWidget);
    await wechsel.close();
  });

  testWidgets('eigenes Handy: Personenwechsel-Meldung aendert nichts', (t) async {
    final s = RosenwegSitzung(app, geraetDa: () async => false);
    s.personGewechselt();
    expect(s.personStand.value, 0);
  });

  testWidgets('fester Transport (Tests): bereit sobald angemeldet', (t) async {
    final s = RosenwegSitzung(app, transport: _Transport());
    expect(await s.api.get('/x'), {'ok': true});
  });

  testWidgets('Fehler: Text und Nochmals', (t) async {
    final s = RosenwegSitzung(app, geraetDa: () async => throw StateError('kaputt'));
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    expect(s.phase, Phase.fehler);
    expect(find.textContaining('kaputt'), findsOneWidget);
    expect(find.text('Nochmals'), findsOneWidget);
  });

  testWidgets('Ueber zeigt GPL und Quelltext', (t) async {
    PackageInfo.setMockInitialValues(
        appName: 'x', packageName: 'ch.rosenweg4303.test', version: '0.1.0', buildNumber: '1', buildSignature: '');
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => zeigeUeber(c, app), child: const Text('über'))),
    ));
    await t.tap(find.text('über'));
    await t.pumpAndSettle();
    expect(find.textContaining('GPL-3.0-or-later'), findsOneWidget);
    expect(find.textContaining('github.com/Rosenweg/rosenweg-test'), findsOneWidget);
    expect(find.textContaining('0.1.0 (1)'), findsOneWidget);
  });

  test('fehlerText: bekannte Fehler als Satz', () {
    expect(fehlerText(ServerNichtErreichbar()), contains('nicht erreichbar'));
    expect(fehlerText(ApiFehler(400, 'Ungültige STWEG')), 'Ungültige STWEG');
  });

  group('Android ohne Rosenweg Geraet: Anmeldeschirm von commons-rosenweg', () {
    testWidgets('nicht angemeldet: Schirm oeffnet sich gleich, danach bereit', (t) async {
      final a = _Android(angemeldetAm: false, schirmMeldetAn: true);
      final s = RosenwegSitzung(app, android: a, geraetDa: () async => false);
      await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
      await t.runAsync(s.starten);
      await t.pump();
      expect(a.schirmGeoeffnet, 1);
      expect(s.phase, Phase.bereit);
      expect(find.text('INHALT'), findsOneWidget);
    });

    testWidgets('schon angemeldet: kein Schirm, Token kommt aus Kotlin', (t) async {
      final a = _Android(angemeldetAm: true);
      final s = RosenwegSitzung(app, android: a, geraetDa: () async => false);
      await t.runAsync(s.starten);
      expect(a.schirmGeoeffnet, 0);
      expect(s.phase, Phase.bereit);
      expect(await (s.api.transport as HttpTransport).zugang.zugangsToken(), 'rw_app_x');
    });

    testWidgets('Schirm ohne Anmeldung verlassen: Knopf "Anmelden"', (t) async {
      final a = _Android(angemeldetAm: false, schirmMeldetAn: false);
      final s = RosenwegSitzung(app, android: a, geraetDa: () async => false);
      await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
      await t.runAsync(s.starten);
      await t.pump();
      expect(s.phase, Phase.abgemeldet);
      expect(find.text('Anmelden'), findsOneWidget);
      expect(find.text('Mit Rosenweg-Konto anmelden'), findsNothing);
    });

    testWidgets('Abmelden: nur diese App, Schirm wieder offen', (t) async {
      final a = _Android(angemeldetAm: true, schirmMeldetAn: false);
      final s = RosenwegSitzung(app, android: a, geraetDa: () async => false);
      await t.runAsync(s.starten);
      await t.runAsync(s.abmelden);
      expect(a.abgemeldet, isTrue);
      expect(a.schirmGeoeffnet, 1);
      expect(s.phase, Phase.abgemeldet);
    });
  });
}

/// Attrappe fuer den Kanal zu commons-rosenweg.
class _Android implements AndroidKonto {
  _Android({required this.angemeldetAm, this.schirmMeldetAn = true});
  bool angemeldetAm;
  final bool schirmMeldetAn;
  var schirmGeoeffnet = 0;
  var abgemeldet = false;
  @override
  String? name = 'Anna';
  @override
  String? email;
  @override
  bool mitKarte = true;
  @override
  Future<bool> get angemeldet async => angemeldetAm;
  @override
  Future<bool> anmeldeSchirm() async {
    schirmGeoeffnet++;
    angemeldetAm = schirmMeldetAn;
    return schirmMeldetAn;
  }

  @override
  Future<bool> bestaetigen() async => true;
  @override
  Future<void> abmelden() async {
    abgemeldet = true;
    angemeldetAm = false;
  }

  @override
  Future<String?> zugangsToken() async => angemeldetAm ? 'rw_app_x' : null;
  @override
  void zugangUngueltig() {}
}
