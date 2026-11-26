// SPDX-License-Identifier: GPL-3.0-or-later
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
  setUpAll(() => Protokoll.nurKonsole = true);
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
}
