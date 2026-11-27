// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

const app = RosenwegApp(
  kennung: 'ch.rosenweg4303.test',
  name: 'Rosenweg Test',
  ordner: 'rosenweg-test',
  beschreibung: 'Eine Test-App.',
);

/// USB-Leser-Attrappe: Karten kommen ueber [auflegen].
class _Leser implements Kartenleser {
  bool da = true;
  final _karten = StreamController<String>.broadcast();
  void auflegen(String uid) => _karten.add(uid);
  @override
  bool get aufKnopfdruck => false;
  @override
  Future<bool> verfuegbar() async => da;
  @override
  Stream<String> lauschen() => _karten.stream;
  @override
  Future<String?> einmalLesen() => _karten.stream.first;
}

/// Server (Website api/routes/app-karte.js) als Attrappe. Prueft die
/// Unterschrift beim Erneuern wirklich.
class _Server {
  final anfragen = <String>[];
  String? schluessel;
  var handyBestaetigt = false;
  var abgemeldet = false;

  MockClient get client => MockClient((r) async {
        anfragen.add(r.url.path);
        final b = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
        http.Response j(int s, Object o) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});
        switch (r.url.path) {
          case '/api/apps/karte-anmelden':
            expect(b['app'], 'ch.rosenweg4303.test');
            expect((b['geraet'] as Map)['kennung'], matches(RegExp(r'^[0-9a-f]{64}$')));
            if (b['uid'] != '04D4C227C22A81') return j(403, {'error': 'Diese Karte ist nicht bekannt oder gesperrt.'});
            schluessel = b['schluessel'] as String;
            return j(200, {'ok': true, 'sitzung': 'ks_1', 'zugang': 'rw_app_a', 'expires_in': 900, 'name': 'Anna Muster', 'email': 'anna@x.ch'});
          case '/api/apps/handy-code':
            schluessel = b['schluessel'] as String;
            return j(200, {'abhol_code': 'geheim', 'benutzer_code': 'K7QM-3XRP', 'adresse': 'https://rosenweg4303.ch/app-anmelden#K7QM-3XRP', 'intervall': 1, 'expires_in': 300});
          case '/api/apps/handy-code/abholen':
            if (!handyBestaetigt) return j(202, {'status': 'wartet'});
            return j(200, {'ok': true, 'sitzung': 'ks_2', 'zugang': 'rw_app_h', 'expires_in': 900, 'name': 'Anna Muster', 'email': 'anna@x.ch'});
          case '/api/apps/sitzung/erneuern':
            if (b['unterschrift'] == null) return j(200, {'herausforderung': 'h1'});
            final ok = GeraeteSchluessel.pruefen(schluessel!, 'rw-app-sitzung-erneuern\n${b['sitzung']}\nh1', b['unterschrift'] as String);
            return ok ? j(200, {'ok': true, 'zugang': 'rw_app_neu', 'expires_in': 900}) : j(401, {'grund': 'unterschrift'});
          case '/api/apps/sitzung/abmelden':
            abgemeldet = r.headers['authorization'] == 'Bearer rw_app_neu' || r.headers['authorization'] == 'Bearer rw_app_a';
            return j(200, {'ok': true});
        }
        return j(404, {'error': 'unbekannt'});
      });
}

/// Falsche Zeit in kleinen Schritten vorruecken (Zeitgeber, Antworten der Attrappe).
/// Wechselt mit echter Zeit ab: der Schluesselbund (Kanal-Attrappe) antwortet
/// ausserhalb der falschen Zeit.
Future<void> laufen(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 50 + 1; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    Protokoll.nurKonsole = true;
    RosenwegPlattform.plattformFuerTests = TargetPlatform.macOS;
  });
  tearDownAll(() => RosenwegPlattform.plattformFuerTests = null);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => Kartenleser.ersatz = null);

  test('Geraeteschluessel: SPKI P-256, Unterschrift DER, pruefbar', () {
    final k = GeraeteSchluessel.erzeugen();
    expect(base64Decode(k.oeffentlich).length, 91);
    final u = GeraeteSchluessel.unterschreiben(k.privat, 'rw-app-sitzung-erneuern\nks_1\nabc');
    expect(base64Decode(u).first, 0x30);
    expect(GeraeteSchluessel.pruefen(k.oeffentlich, 'rw-app-sitzung-erneuern\nks_1\nabc', u), isTrue);
    expect(GeraeteSchluessel.pruefen(k.oeffentlich, 'anders', u), isFalse);
  });

  RosenwegSitzung sitzung(_Server server) {
    final speicher = Schluesselbund(app.ordner);
    return RosenwegSitzung(app,
        speicher: speicher,
        konto: RosenwegKonto(app, speicher: speicher, still: () => null),
        karte: KartenSitzung(app, speicher: speicher, client: server.client, kennung: () async => 'a' * 64),
        geraetDa: () async => false);
  }

  testWidgets('Desktop mit USB-Leser: Karte auflegen meldet an, Stand "Rosenweg-Karte"', (t) async {
    final leser = _Leser();
    Kartenleser.ersatz = () => leser;
    final server = _Server();
    final s = sitzung(server);
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    await laufen(t, 50);
    await t.pump();
    expect(find.text('Rosenweg-Karte\nauf den Kartenleser legen'), findsOneWidget);

    leser.auflegen('04D4C227C22A81');
    await laufen(t, 100);
    await t.pump();
    expect(find.textContaining('Rosenweg-Karte prüfen'), findsOneWidget);
    await laufen(t, 2000);
    expect(s.phase, Phase.bereit);
    expect(find.text('INHALT'), findsOneWidget);
    expect(s.stand.art, AnmeldeArt.karte);
    expect(s.stand.name, 'Anna Muster');

    // Zugang abgelaufen: erneuern mit Unterschrift
    s.karte!.zugangUngueltig();
    expect(await t.runAsync(() => s.karte!.zugangsToken()), 'rw_app_neu');

    // Anmeldung in den Einstellungen: echter Stand
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AnmeldungKarte(sitzung: s))));
    expect(find.text('Rosenweg-Karte'), findsOneWidget);
    expect(find.text('anna@x.ch'), findsOneWidget);
    expect(find.text('Abmelden'), findsOneWidget);

    await t.runAsync(s.abmelden);
    expect(server.abgemeldet, isTrue);
    expect(s.phase, Phase.abgemeldet);
    expect(await t.runAsync(() => s.karte!.angemeldet), isFalse);
  });

  testWidgets('Karte unbekannt: roter Schritt mit Grund, dann zurueck', (t) async {
    final leser = _Leser();
    Kartenleser.ersatz = () => leser;
    final s = sitzung(_Server());
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await laufen(t, 50);
    await t.pump();
    leser.auflegen('DEADBEEF');
    await laufen(t, 100);
    await t.pump();
    expect(find.textContaining('nicht bekannt oder gesperrt'), findsOneWidget);
    await t.pump(const Duration(seconds: 9));
    expect(find.text('Mit Rosenweg-Konto anmelden'), findsOneWidget);
    expect(s.phase, Phase.abgemeldet);
  });

  testWidgets('Desktop: "Mit dem Handy anmelden" zeigt QR und Code, nach Bestaetigung angemeldet', (t) async {
    Kartenleser.ersatz = () => null;
    final server = _Server();
    final s = sitzung(server);
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    expect(find.textContaining('Kartenleser'), findsNothing);
    await t.tap(find.text('Mit dem Handy anmelden'));
    await laufen(t, 100);
    await t.pump();
    expect(find.text('K7QM-3XRP'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    await laufen(t, 1100);
    await t.pump();
    expect(s.phase, Phase.abgemeldet);
    server.handyBestaetigt = true;
    await laufen(t, 1100);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(s.phase, Phase.bereit);
    expect(s.stand.art, AnmeldeArt.handy);
  });

  testWidgets('App nur mit Konto (ohneBrowser: false): weder Karte noch QR', (t) async {
    Kartenleser.ersatz = () => _Leser();
    const vm = RosenwegApp(kennung: 'ch.rosenweg4303.vm', name: 'Rosenweg VM', ordner: 'rosenweg-vm-test', beschreibung: '', ohneBrowser: false);
    final s = RosenwegSitzung(vm, geraetDa: () async => false);
    expect(s.karte, isNull);
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => const Text('INHALT')));
    await t.runAsync(s.starten);
    await t.pump();
    expect(find.text('Mit Rosenweg-Konto anmelden'), findsOneWidget);
    expect(find.text('Mit dem Handy anmelden'), findsNothing);
    expect(find.textContaining('Kartenleser'), findsNothing);
  });

  testWidgets('iOS: Karte und QR auf Knopfdruck', (t) async {
    RosenwegPlattform.plattformFuerTests = TargetPlatform.iOS;
    addTearDown(() => RosenwegPlattform.plattformFuerTests = TargetPlatform.macOS);
    final s = sitzung(_Server());
    await t.runAsync(s.starten);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: RosenwegAnmeldeSchirm(sitzung: s, leser: _IosLeser(), qrScannerDa: true))));
    await laufen(t, 50);
    await t.pump();
    expect(find.text('Rosenweg-Karte lesen'), findsOneWidget);
    expect(find.text('QR-Code scannen'), findsOneWidget);
    expect(find.text('Mit dem Handy anmelden'), findsNothing);
  });
}

class _IosLeser extends _Leser {
  @override
  bool get aufKnopfdruck => true;
}

