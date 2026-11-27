// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

const _app = RosenwegApp(kennung: 'ch.rosenweg4303.salz', name: 'Rosenweg Salz', ordner: 'rosenweg-salz', beschreibung: '');
final _katalog = Uri.parse(RosenwegAktualisierung.standardKatalog);

Map<String, Object?> _index({String version = '1.3.0', String sha = 'ab', int groesse = 3}) => {
      'apps': [],
      'karten': [
        {
          'app': 'salz',
          'paket': 'ch.rosenweg4303.salz',
          'downloads': [
            {'plattform': 'android', 'version': '9.9.9', 'sha256': 'x' * 64, 'url': '/api/apps/ch.rosenweg4303.salz.apk'},
            {
              'plattform': 'linux-deb',
              'version': version,
              'sha256': sha.length == 64 ? sha : sha.padRight(64, '0'),
              'groesse': groesse,
              'url': '/api/apps/datei/salz/linux-deb',
            },
          ],
        },
      ],
    };

void main() {
  group('istNeuer', () {
    test('Stellen numerisch, Build-Nummer zaehlt nicht', () {
      expect(istNeuer('1.10.0', '1.9.3'), isTrue);
      expect(istNeuer('1.2.0', '1.2.0'), isFalse);
      expect(istNeuer('1.2', '1.2.0'), isFalse);
      expect(istNeuer('1.2.1', '1.2.0+7'), isTrue);
      expect(istNeuer('1.2.0+9', '1.2.0+3'), isFalse);
      expect(istNeuer('1.1.0', '1.2.0'), isFalse);
    });
  });

  group('fassungImKatalog', () {
    test('findet Paket und Plattform, Adresse relativ zur Anlage', () {
      final f = fassungImKatalog(_index(), 'ch.rosenweg4303.salz', 'linux-deb', basis: _katalog)!;
      expect(f.version, '1.3.0');
      expect(f.url.toString(), 'https://pbx.rosenweg4303.ch/api/apps/datei/salz/linux-deb');
      expect(f.dateiname('rosenweg-salz'), 'rosenweg-salz-1.3.0.deb');
    });
    test('fehlende Plattform, fremdes Paket, kaputte Angaben: nichts', () {
      expect(fassungImKatalog(_index(), 'ch.rosenweg4303.salz', 'windows', basis: _katalog), isNull);
      expect(fassungImKatalog(_index(), 'ch.rosenweg4303.vm', 'linux-deb', basis: _katalog), isNull);
      expect(fassungImKatalog({'karten': 'x'}, 'ch.rosenweg4303.salz', 'linux-deb', basis: _katalog), isNull);
      final i = _index();
      ((i['karten'] as List).first as Map)['downloads'] = [
        {'plattform': 'linux-deb', 'version': '2.0.0', 'sha256': 'kurz', 'url': '/api/apps/datei/salz/linux-deb'},
        // fremde Adresse wird nie geladen
      ];
      expect(fassungImKatalog(i, 'ch.rosenweg4303.salz', 'linux-deb', basis: _katalog), isNull);
      ((i['karten'] as List).first as Map)['downloads'] = [
        {'plattform': 'linux-deb', 'version': '2.0.0', 'sha256': '0' * 64, 'url': 'https://boese.example/x.deb'},
      ];
      expect(fassungImKatalog(i, 'ch.rosenweg4303.salz', 'linux-deb', basis: _katalog), isNull);
    });
  });

  test('Pruefsumme und Groesse muessen stimmen', () {
    final f = NeueFassung(version: '1', sha256: 'a' * 64, groesse: 10, url: _katalog);
    expect(pruefsummeStimmt(ist: 'A' * 64, istGroesse: 10, soll: f), isTrue);
    expect(pruefsummeStimmt(ist: 'a' * 64, istGroesse: 9, soll: f), isFalse);
    expect(pruefsummeStimmt(ist: 'b' * 64, istGroesse: 10, soll: f), isFalse);
  });

  group('RosenwegAktualisierung', () {
    test('neuere Fassung im Katalog: verfuegbar; gleiche: nichts', () async {
      final client = MockClient((r) async => http.Response(jsonEncode(_index()), 200));
      final a = RosenwegAktualisierung(_app, client: client, aktiv: true, plattform: 'linux-deb', installiert: () async => '1.2.0');
      await a.pruefen();
      expect(a.stand, AktualisierungsStand.verfuegbar);
      expect(a.neu!.version, '1.3.0');

      final b = RosenwegAktualisierung(_app, client: client, aktiv: true, plattform: 'linux-deb', installiert: () async => '1.3.0');
      await b.pruefen();
      expect(b.stand, AktualisierungsStand.nichts);
    });

    test('Katalog nicht erreichbar: still, kein Hinweis', () async {
      final client = MockClient((r) async => http.Response('<html>', 502));
      final a = RosenwegAktualisierung(_app, client: client, aktiv: true, plattform: 'linux-deb', installiert: () async => '1.0.0');
      await a.pruefen();
      expect(a.stand, AktualisierungsStand.nichts);
    });

    test('falsche Pruefsumme: Datei geloescht, Fehler, nichts installiert', () async {
      final inhalt = utf8.encode('abc');
      final client = MockClient((r) async => r.url.path.endsWith('index.json')
          ? http.Response(jsonEncode(_index(sha: 'f' * 64)), 200)
          : http.Response.bytes(inhalt, 200));
      final a = RosenwegAktualisierung(_app, client: client, aktiv: true, plattform: 'linux-deb', installiert: () async => '1.0.0');
      await a.pruefen();
      await a.aktualisieren();
      expect(a.stand, AktualisierungsStand.fehler);
      expect(a.meldung, contains('Prüfsumme'));
      expect(a.datei, isNull);
      final rest = Directory('${Directory.systemTemp.path}/rosenweg-aktualisierung/rosenweg-salz/rosenweg-salz-1.3.0.deb');
      expect(File(rest.path).existsSync(), isFalse);
    });

    test('richtige Pruefsumme: Datei bleibt (Installieren hier nicht ausgefuehrt)', () async {
      final inhalt = utf8.encode('abc');
      final sha = sha256.convert(inhalt).toString();
      // Plattform ohne Installationsweg: nur laden und pruefen
      final i = _index(sha: sha);
      (((i['karten'] as List).first as Map)['downloads'] as List).add(
          {'plattform': 'test', 'version': '1.3.0', 'sha256': sha, 'groesse': 3, 'url': '/api/apps/datei/salz/test'});
      final b = RosenwegAktualisierung(_app,
          client: MockClient((r) async => r.url.path.endsWith('index.json') ? http.Response(jsonEncode(i), 200) : http.Response.bytes(inhalt, 200)),
          aktiv: true,
          plattform: 'test',
          installiert: () async => '1.0.0');
      await b.pruefen();
      await b.aktualisieren();
      expect(b.stand, isNot(AktualisierungsStand.fehler));
      expect(b.datei!.readAsBytesSync(), inhalt);
      b.datei!.deleteSync();
    });

    test('aus: prueft nie', () async {
      var gefragt = 0;
      final a = RosenwegAktualisierung(_app,
          client: MockClient((r) async {
            gefragt++;
            return http.Response(jsonEncode(_index()), 200);
          }),
          aktiv: false,
          plattform: 'linux-deb',
          installiert: () async => '1.0.0');
      await a.pruefen();
      expect(gefragt, 0);
      expect(a.stand, AktualisierungsStand.nichts);
    });
  });

  group('RosenwegStation', () {
    late Directory wurzel;
    setUp(() {
      wurzel = Directory.systemTemp.createTempSync('station');
      RosenwegStation.wurzelFuerTests = wurzel.path;
      RosenwegStation.linuxFuerTests = true;
      RosenwegStation.vergessen();
    });
    tearDown(() {
      RosenwegStation.wurzelFuerTests = null;
      RosenwegStation.linuxFuerTests = null;
      RosenwegStation.vergessen();
      wurzel.deleteSync(recursive: true);
    });

    void anlegen(String pfad, String inhalt) => (File('${wurzel.path}$pfad')..createSync(recursive: true)).writeAsStringSync(inhalt);

    test('normales Debian (nichts von os-stationen): keine Station', () {
      expect(RosenwegStation.erkannt, isFalse);
    });
    test('Station-ID und Konfiguration: Station', () {
      anlegen(RosenwegStation.kennungDatei, 'desktop-verwaltung\n');
      anlegen(RosenwegStation.konfigDatei, '{}');
      expect(RosenwegStation.erkannt, isTrue);
      expect(RosenwegStation.kennung, 'desktop-verwaltung');
    });
    test('nur eins von beiden oder leere ID: keine Station', () {
      anlegen(RosenwegStation.kennungDatei, 'desktop-verwaltung');
      expect(RosenwegStation.erkannt, isFalse);
      RosenwegStation.vergessen();
      anlegen(RosenwegStation.kennungDatei, '  ');
      anlegen(RosenwegStation.konfigDatei, '{}');
      expect(RosenwegStation.erkannt, isFalse);
    });
    test('nicht Linux: nie Station', () {
      anlegen(RosenwegStation.kennungDatei, 'x1');
      anlegen(RosenwegStation.konfigDatei, '{}');
      RosenwegStation.linuxFuerTests = false;
      expect(RosenwegStation.erkannt, isFalse);
    });
    test('Station: Updater aus, auch in Release-Bauten', () {
      anlegen(RosenwegStation.kennungDatei, 'desktop-verwaltung');
      anlegen(RosenwegStation.konfigDatei, '{}');
      expect(RosenwegStation.erkannt, isTrue);
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'linux-deb', station: RosenwegStation.erkannt, release: true), isFalse);
    });
    test('eigener Linux-Rechner, macOS, Windows: an; Android/iOS (plattform null): aus', () {
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'linux-deb', station: false, release: true), isTrue);
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'windows', station: false, release: true), isTrue);
      expect(RosenwegAktualisierung.laeuftHier(plattform: null, station: false, release: true), isFalse);
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'macos', station: false, release: false), isFalse);
    });
  });

  testWidgets('Leiste: nur mit neuer Fassung, "Später" blendet aus', (tester) async {
    final client = MockClient((r) async => http.Response(jsonEncode(_index()), 200));
    final a = RosenwegAktualisierung(_app, client: client, aktiv: true, plattform: 'linux-deb', installiert: () async => '1.2.0');
    await tester.pumpWidget(MaterialApp(
      builder: (context, kind) => AktualisierungsLeiste(aktualisierung: a, child: kind!),
      home: const Scaffold(body: Text('Inhalt')),
    ));
    expect(find.text('Aktualisieren'), findsNothing);
    await tester.runAsync(a.pruefen);
    await tester.pump();
    expect(find.text('Neue Fassung 1.3.0 verfügbar.'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await tester.pump();
    expect(find.text('Aktualisieren'), findsNothing);
    expect(find.text('Inhalt'), findsOneWidget);
  });
}
