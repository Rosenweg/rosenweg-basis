// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

const _app = RosenwegApp(kennung: 'ch.rosenweg4303.salz', name: 'Rosenweg Salz', ordner: 'rosenweg-salz', beschreibung: '');

Map<String, Object?> _index(String version) => {
      'apps': [],
      'karten': [
        {
          'paket': 'ch.rosenweg4303.salz',
          'downloads': [
            {'plattform': 'linux-deb', 'version': version, 'sha256': 'a' * 64, 'groesse': 3, 'url': '/api/apps/datei/salz/linux-deb'},
          ],
        },
      ],
    };

RosenwegAktualisierung _mit(http.Client c, {String installiert = '1.2.0', bool aktiv = true}) => RosenwegAktualisierung(_app,
    client: c, aktiv: aktiv, plattform: 'linux-deb', installiert: () async => installiert, geraetKennung: () async => 'g' * 64);

void main() {
  group('jetztPruefen', () {
    test('aktuell', () async {
      final a = _mit(MockClient((r) async => http.Response(jsonEncode(_index('1.2.0')), 200)));
      final e = await a.jetztPruefen();
      expect(e.art, PruefArt.aktuell);
      expect(e.text, contains('Rosenweg Salz 1.2.0'));
    });
    test('neue Fassung', () async {
      final a = _mit(MockClient((r) async => http.Response(jsonEncode(_index('1.3.0')), 200)));
      final e = await a.jetztPruefen();
      expect(e.art, PruefArt.neu);
      expect(e.neu!.version, '1.3.0');
      expect(a.stand, AktualisierungsStand.verfuegbar);
    });
    test('Fehler im Klartext', () async {
      final a = _mit(MockClient((r) async => http.Response('kaputt', 502)));
      final e = await a.jetztPruefen();
      expect(e.art, PruefArt.fehler);
      expect(e.text, contains('Fehler 502'));
      final b = _mit(MockClient((r) async => http.Response('<html>', 200)));
      expect((await b.jetztPruefen()).text, contains('unlesbare Antwort'));
    });
    test('aus (Station, verwaltet, Entwicklungsbau): nur Hinweis', () async {
      final a = _mit(MockClient((r) async => throw StateError('darf nicht fragen')), aktiv: false);
      final e = await a.jetztPruefen();
      expect(e.art, PruefArt.aus);
      expect(e.text, isNotEmpty);
    });
  });

  test('Versionsstand ans NOC: Geraet gehasht, Paket, Version, Plattform', () async {
    Map<String, Object?>? gemeldet;
    final a = _mit(MockClient((r) async {
      if (r.url.path == '/api/apps/stand') {
        gemeldet = jsonDecode(r.body) as Map<String, Object?>;
        return http.Response('{"ok":true}', 200);
      }
      return http.Response(jsonEncode(_index('1.2.0')), 200);
    }), installiert: '1.2.0+7');
    await a.standMelden();
    expect(gemeldet!['geraet'], 'g' * 64);
    expect(gemeldet!['plattform'], 'linux-deb');
    expect(gemeldet!['apps'], [
      {'paket': 'ch.rosenweg4303.salz', 'version': '1.2.0'},
    ]);
    expect(gemeldet!.keys, isNot(contains('email')));
  });

  testWidgets('Knopf "Nach Updates suchen" zeigt das Ergebnis und "Installieren"', (t) async {
    final a = _mit(MockClient((r) async => http.Response(jsonEncode(_index('1.3.0')), 200)));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AktualisierungKarte(aktualisierung: a, android: false))));
    expect(find.text('Nach Updates suchen'), findsOneWidget);
    await t.tap(find.byKey(const Key('nach-updates-suchen')));
    await t.pumpAndSettle();
    expect(find.textContaining('Neue Fassung 1.3.0'), findsOneWidget);
    expect(find.text('Installieren (1.3.0)'), findsOneWidget);
  });

  test('macOS: neue Fassung im Browser laden, nicht in der Sandbox', () async {
    Uri? geoeffnet;
    var geladen = false;
    final i = {
      'karten': [
        {
          'paket': 'ch.rosenweg4303.salz',
          'downloads': [
            {'plattform': 'macos', 'version': '1.3.0', 'sha256': 'a' * 64, 'groesse': 3, 'url': '/api/apps/datei/salz/macos'},
          ],
        },
      ],
    };
    final a = RosenwegAktualisierung(_app,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/macos')) geladen = true;
          return http.Response(jsonEncode(i), 200);
        }),
        aktiv: true,
        plattform: 'macos',
        installiert: () async => '1.2.0',
        geraetKennung: () async => null,
        imBrowserOeffnen: (u) async {
          geoeffnet = u;
          return true;
        });
    expect((await a.jetztPruefen()).art, PruefArt.neu);
    await a.aktualisieren();
    expect(geoeffnet.toString(), 'https://pbx.rosenweg4303.ch/api/apps/datei/salz/macos');
    expect(geladen, isFalse);
    expect(a.stand, AktualisierungsStand.installiert);
    expect(a.meldung, contains('Browser'));
  });

  testWidgets('aus: kein Knopf, nur wer aktualisiert', (t) async {
    final a = _mit(MockClient((r) async => http.Response('', 500)), aktiv: false);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AktualisierungKarte(aktualisierung: a, android: false))));
    expect(find.byKey(const Key('nach-updates-suchen')), findsNothing);
    expect(find.byKey(const Key('aktualisierung-aus')), findsOneWidget);
  });
}
