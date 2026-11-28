// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:rosenweg_basis/rosenweg_basis.dart';

class _Zugang implements Zugangsquelle {
  _Zugang(this.tokens);
  final List<String> tokens;
  @override
  Future<String?> zugangsToken() async => tokens.isEmpty ? null : tokens.first;
  @override
  void zugangUngueltig() => tokens.removeAt(0);
}

http.StreamedResponse _antwort(int status, List<int> body, {Map<String, String> kopf = const {}}) =>
    http.StreamedResponse(Stream.fromIterable([body]), status, contentLength: body.length, headers: kopf);

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);
  final daten = DateiDaten(name: 'Rechnung März.pdf', bytes: Uint8List.fromList(List.generate(200 * 1024, (i) => i % 256)));

  test('Hilfen: Typ, Groesse, Dateiname aus dem Kopf', () {
    expect(daten.typ, 'application/pdf');
    expect(dateiTypRaten('foto.JPG'), 'image/jpeg');
    expect(dateiTypRaten('ohne'), 'application/octet-stream');
    expect(groesseText(512), '512 Bytes');
    expect(groesseText(3 * 1024 * 1024 + 400 * 1024), '3,4 MB');
    expect(dateinameAusKopf('attachment; filename="a b.pdf"'), 'a b.pdf');
    expect(dateinameAusKopf("attachment; filename=x.pdf; filename*=UTF-8''M%C3%A4rz.pdf"), 'März.pdf');
    expect(dateinameAusKopf(null), isNull);
    expect(kopfDateiname('plan.pdf'), 'plan.pdf');
    expect(kopfDateiname('März.pdf'), 'M%C3%A4rz.pdf');
  });

  test('roh hochladen: Bearer, Typ, Name, ganzer Inhalt, Fortschritt', () async {
    late http.BaseRequest gesehen;
    late List<int> body;
    final c = MockClient.streaming((r, s) async {
      gesehen = r;
      body = await s.toBytes();
      return _antwort(201, utf8.encode('{"ok":true}'), kopf: {'content-type': 'application/json'});
    });
    final stand = <int>[];
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t1']), client: c);
    final j = await d.hochladen('/api/documents/Ordner/x.pdf', daten,
        methode: 'PUT', inhaltstyp: 'application/octet-stream', fortschritt: (f, g) => stand.add(f));
    expect(j, {'ok': true});
    expect(gesehen.method, 'PUT');
    expect(gesehen.url.toString(), 'https://api/api/documents/Ordner/x.pdf');
    expect(gesehen.headers['Authorization'], 'Bearer t1');
    expect(gesehen.headers['Content-Type'], 'application/octet-stream');
    expect(gesehen.headers['X-Filename'], 'Rechnung%20M%C3%A4rz.pdf');
    expect(body, daten.bytes);
    expect(stand.first, 0);
    expect(stand.last, daten.groesse);
    expect(stand.length, greaterThan(3));
  });

  test('multipart hochladen mit Feldern', () async {
    late String text;
    late http.BaseRequest gesehen;
    final c = MockClient.streaming((r, s) async {
      gesehen = r;
      text = latin1.decode(await s.toBytes());
      return _antwort(200, utf8.encode('{"id":7}'));
    });
    int? letzter;
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), client: c);
    final j = await d.hochladen('/api/reparatur/foto', DateiDaten(name: 'a.jpg', bytes: Uint8List.fromList([1, 2, 3])),
        multipart: true, feld: 'foto', felder: {'titel': 'Tür'}, fortschritt: (f, _) => letzter = f);
    expect(j, {'id': 7});
    expect(gesehen.headers['content-type'], startsWith('multipart/form-data'));
    expect(text, contains('name="foto"; filename="a.jpg"'));
    expect(text, contains('content-type: image/jpeg'));
    expect(text, contains('name="titel"'));
    expect(letzter, gesehen.contentLength);
  });

  test('401: Token erneuern und einmal nochmals', () async {
    final tokens = <String?>[];
    final c = MockClient.streaming((r, s) async {
      await s.drain<void>();
      tokens.add(r.headers['Authorization']);
      return r.headers['Authorization'] == 'Bearer alt' ? _antwort(401, utf8.encode('{"error":"x"}')) : _antwort(200, utf8.encode('{}'));
    });
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['alt', 'neu']), client: c);
    await d.hochladen('/api/x', daten);
    expect(tokens, ['Bearer alt', 'Bearer neu']);
  });

  test('Fehler der API wie bei RosenwegApi', () async {
    var abgemeldet = 0;
    final c = MockClient.streaming((r, s) async {
      await s.drain<void>();
      return switch (r.url.path) {
        '/api/verboten' => _antwort(403, utf8.encode('{"error":"Keine Berechtigung"}')),
        '/api/gross' => _antwort(413, utf8.encode('{"error":"Datei zu gross"}')),
        '/api/weg' => _antwort(401, utf8.encode('{}')),
        _ => _antwort(502, utf8.encode('<html>Bad Gateway</html>')),
      };
    });
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), client: c, nichtAngemeldet: () => abgemeldet++);
    await expectLater(d.hochladen('/api/verboten', daten), throwsA(isA<KeineBerechtigung>()));
    await expectLater(d.hochladen('/api/gross', daten), throwsA(predicate((e) => e is ApiFehler && e.text == 'Datei zu gross')));
    await expectLater(d.herunterladen('/api/502'), throwsA(isA<ServerNichtErreichbar>()));
    await expectLater(d.herunterladen('/api/weg'), throwsA(isA<NichtAngemeldet>()));
    expect(abgemeldet, 1);
  });

  test('herunterladen: Bytes, Name, Typ, Fortschritt', () async {
    final pdf = utf8.encode('%PDF-1.4 …');
    final c = MockClient.streaming((r, s) async {
      expect(r.headers['Authorization'], 'Bearer t');
      return _antwort(200, pdf, kopf: {'content-type': 'application/pdf', 'content-disposition': 'inline; filename="vollmacht-7.pdf"'});
    });
    int? gesamt;
    final d = await RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), client: c)
        .herunterladen('/api/vollmachten/7/pdf', fortschritt: (f, g) => gesamt = g);
    expect(d.bytes, pdf);
    expect(d.name, 'vollmacht-7.pdf');
    expect(d.typ, 'application/pdf');
    expect(gesamt, pdf.length);
  });

  test('geteiltes Telefon: verstaendlicher Fehler, keine Anfrage', () async {
    var n = 0;
    final c = MockClient.streaming((r, s) async {
      n++;
      return _antwort(200, []);
    });
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), client: c, geteiltesTelefon: () => true);
    await expectLater(d.herunterladen('/api/x'), throwsA(predicate((e) => e is GeraetFehler && e.text == RosenwegDateien.geteiltText)));
    expect(n, 0);
  });

  test('geteiltes Telefon: Hochladen in Stuecken, Kopf nur im ersten', () async {
    final stuecke = <Map<String, Object?>>[];
    final bytes = <int>[];
    final d = RosenwegDateien(
      basis: 'https://api',
      zugang: _Zugang(['t']),
      geteiltesTelefon: () => true,
      geteiltHochladen: (m, p, teil, stueck) async {
        stuecke.add({'m': m, 'p': p, ...teil});
        bytes.addAll(base64Decode(stueck));
        final letzt = teil['nr'] == (teil['anzahl'] as int) - 1;
        return (status: letzt ? 201 : 202, json: letzt ? {'ok': true} : {'teil': teil['nr']});
      },
    );
    final gross = DateiDaten(name: 'Rechnung März.pdf', bytes: Uint8List.fromList(List.generate(RosenwegDateien.hochStueck * 2 + 5, (i) => i % 251)));
    final fort = <int>[];
    final r = await d.hochladen('/api/documents/x/a.pdf', gross, fortschritt: (f, g) => fort.add(f));
    expect(r, {'ok': true});
    expect(stuecke.map((e) => e['nr']), [0, 1, 2]);
    expect(stuecke.every((e) => e['m'] == 'POST' && e['anzahl'] == 3 && e['gesamt'] == gross.groesse && e['id'] == stuecke.first['id']), isTrue);
    expect(stuecke.first['kopf'], containsPair('x_filename', 'Rechnung%20M%C3%A4rz.pdf'));
    expect(stuecke[1].containsKey('kopf'), isFalse);
    expect(bytes, gross.bytes);
    expect(fort.last, gross.groesse);
  });

  test('geteiltes Telefon: zu gross zum Hochladen', () async {
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), geteiltesTelefon: () => true, geteiltHochladen: (m, p, t, s) async => (status: 200, json: null));
    final x = DateiDaten(name: 'a.bin', bytes: Uint8List(1));
    expect(RosenwegDateien.geteiltHoechstens, 64 * 1024 * 1024);
    // ohne Rueckruf: verstaendlicher Fehler
    final o = RosenwegDateien(basis: 'https://api', zugang: _Zugang(['t']), geteiltesTelefon: () => true);
    await expectLater(o.hochladen('/api/x', x), throwsA(predicate((e) => e is GeraetFehler && e.text == RosenwegDateien.geteiltText)));
    await d.hochladen('/api/x', x);
  });

  test('ohne Anmeldung: NichtAngemeldet', () async {
    final d = RosenwegDateien(basis: 'https://api', zugang: _Zugang([]), client: MockClient((_) async => http.Response('', 200)));
    await expectLater(d.herunterladen('/api/x'), throwsA(isA<NichtAngemeldet>()));
  });

  test('Bild verkleinern: lange Seite, JPEG, kleine Bilder unveraendert', () async {
    final gross = DateiDaten(name: 'foto.png', bytes: img.encodePng(img.Image(width: 3000, height: 1500)));
    final k = await bildVerkleinern(gross, maxKante: 1000);
    expect(k.name, 'foto.jpg');
    expect(k.typ, 'image/jpeg');
    final b = img.decodeJpg(k.bytes)!;
    expect((b.width, b.height), (1000, 500));
    final klein = DateiDaten(name: 'k.png', bytes: img.encodePng(img.Image(width: 200, height: 100)));
    expect(identical(await bildVerkleinern(klein), klein), isTrue);
    final pdf = DateiDaten(name: 'a.pdf', bytes: Uint8List(10));
    expect(identical(await bildVerkleinern(pdf), pdf), isTrue);
  });

  testWidgets('TransferAnzeige', (t) async {
    final s = TransferStand();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: TransferAnzeige(stand: s, titel: 'Hochladen'))));
    s(512 * 1024, 2 * 1024 * 1024);
    await t.pump();
    expect(find.text('512 KB von 2,0 MB'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(0.25, 0.001));
  });
}
