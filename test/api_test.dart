// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

class _Zugang implements Zugangsquelle {
  _Zugang(this.tokens);
  final List<String?> tokens;
  var ungueltig = 0;
  @override
  Future<String?> zugangsToken() async => tokens.isEmpty ? null : tokens.first;
  @override
  void zugangUngueltig() {
    ungueltig++;
    if (tokens.isNotEmpty) tokens.removeAt(0);
  }
}

http.Response _json(Object j, int status, {Map<String, String> kopf = const {}}) =>
    http.Response(jsonEncode(j), status, headers: {'content-type': 'application/json', ...kopf});

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('jsonAnfrage', () {
    Future<ApiAntwort> los(MockClient c, {String methode = 'GET', int versuche = 3}) =>
        jsonAnfrage(c, 'Test', () => http.Request(methode, Uri.parse('https://x/api')),
            versuche: versuche, rueckoff: Duration.zero);

    test('200 mit JSON', () async {
      final a = await los(MockClient((_) async => _json({'ok': true}, 200)));
      expect(a.status, 200);
      expect(a.json, {'ok': true});
    });

    test('502 als HTML-Seite: wiederholt, dann ServerNichtErreichbar', () async {
      var n = 0;
      final c = MockClient((_) async {
        n++;
        return http.Response('<html><body>502 Bad Gateway</body></html>', 502);
      });
      await expectLater(los(c), throwsA(isA<ServerNichtErreichbar>()));
      expect(n, 3);
    });

    test('HTML bei 200 (Anmeldeseite statt API): nicht erreichbar', () async {
      await expectLater(
          los(MockClient((_) async => http.Response('<!doctype html>', 200)), versuche: 1), throwsA(isA<ServerNichtErreichbar>()));
    });

    test('erst 503, dann 200: zweiter Versuch gilt', () async {
      var n = 0;
      final a = await los(MockClient((_) async => ++n == 1 ? http.Response('', 503) : _json([1, 2], 200)));
      expect(a.json, [1, 2]);
    });

    test('502 mit JSON-Fehler der API: zurueckgeben, nicht wiederholen', () async {
      var n = 0;
      final a = await los(MockClient((_) async {
        n++;
        return _json({'error': 'Energy-Collector nicht erreichbar'}, 502);
      }));
      expect(a.status, 502);
      expect(n, 1);
    });

    test('429 mit Retry-After', () async {
      final c = MockClient((_) async => _json({'error': 'x'}, 429, kopf: {'retry-after': '90'}));
      await expectLater(
          los(c),
          throwsA(isA<ZuVieleAnfragen>()
              .having((e) => e.warten, 'warten', const Duration(seconds: 90))
              .having((e) => '$e', 'text', contains('90 Sekunden'))));
    });

    test('Verbindungsfehler: nicht erreichbar', () async {
      final c = MockClient((_) async => throw http.ClientException('weg'));
      await expectLater(los(c, versuche: 2), throwsA(isA<ServerNichtErreichbar>()));
    });
  });

  group('RosenwegApi ueber HTTP', () {
    test('Bearer-Token, JSON-Koerper, Antwort', () async {
      late http.Request gesehen;
      final c = MockClient((r) async {
        gesehen = r;
        return _json({'user': {'name': 'A'}}, 200);
      });
      final api = RosenwegApi(HttpTransport(basis: 'https://portal', zugang: _Zugang(['t1']), client: c));
      final j = await api.put('/api/auth/profile', {'name': 'A'});
      expect(j, {'user': {'name': 'A'}});
      expect(gesehen.method, 'PUT');
      expect(gesehen.url.toString(), 'https://portal/api/auth/profile');
      expect(gesehen.headers['Authorization'], 'Bearer t1');
      expect(jsonDecode(gesehen.body), {'name': 'A'});
    });

    test('Fehlertext aus "error"', () async {
      final api = RosenwegApi(HttpTransport(
          basis: 'https://p', zugang: _Zugang(['t']), client: MockClient((_) async => _json({'error': 'Ungültige STWEG'}, 400))));
      await expectLater(api.put('/x', {}),
          throwsA(isA<ApiFehler>().having((e) => e.status, 'status', 400).having((e) => e.text, 'text', 'Ungültige STWEG')));
    });

    test('403 mit reauth: KeineBerechtigung.neuAnmelden', () async {
      final api = RosenwegApi(HttpTransport(
          basis: 'https://p',
          zugang: _Zugang(['t']),
          client: MockClient((_) async => _json({'error': 'Bitte neu anmelden', 'reauth': true}, 403))));
      await expectLater(api.post('/api/change-password', {'new_password': 'x'}),
          throwsA(isA<KeineBerechtigung>().having((e) => e.neuAnmelden, 'neuAnmelden', isTrue)));
    });

    test('401: einmal mit erneuertem Token, dann gilt die zweite Antwort', () async {
      final tokens = <String>[];
      final c = MockClient((r) async {
        tokens.add(r.headers['Authorization']!);
        return r.headers['Authorization'] == 'Bearer alt' ? _json({'error': 'x'}, 401) : _json({'ok': 1}, 200);
      });
      final z = _Zugang(['alt', 'neu']);
      final api = RosenwegApi(HttpTransport(basis: 'https://p', zugang: z, client: c));
      expect(await api.get('/api/me'), {'ok': 1});
      expect(tokens, ['Bearer alt', 'Bearer neu']);
      expect(z.ungueltig, 1);
    });

    test('401 bleibt: NichtAngemeldet und Rueckruf', () async {
      var gerufen = 0;
      final api = RosenwegApi(
          HttpTransport(basis: 'https://p', zugang: _Zugang(['a']), client: MockClient((_) async => _json({}, 401))),
          nichtAngemeldet: () => gerufen++);
      await expectLater(api.get('/api/me'), throwsA(isA<NichtAngemeldet>()));
      expect(gerufen, 1);
    });

    test('ohne Token gar nicht erst fragen', () async {
      var n = 0;
      final api = RosenwegApi(HttpTransport(
          basis: 'https://p', zugang: _Zugang([]), client: MockClient((_) async => _json({}, 200 + 0 * n++))));
      await expectLater(api.get('/api/me'), throwsA(isA<NichtAngemeldet>()));
      expect(n, 0);
    });

    test('POST wird bei 502 nicht wiederholt', () async {
      var n = 0;
      final api = RosenwegApi(HttpTransport(
          basis: 'https://p',
          zugang: _Zugang(['t']),
          client: MockClient((_) async {
            n++;
            return http.Response('<html>502</html>', 502);
          })));
      await expectLater(api.post('/api/me/tokens', {'name': 'x'}), throwsA(isA<ServerNichtErreichbar>()));
      expect(n, 1);
    });

    test('objekt/liste pruefen die Form', () async {
      final api = RosenwegApi(HttpTransport(
          basis: 'https://p', zugang: _Zugang(['t']), client: MockClient((_) async => _json([1], 200))));
      expect(await api.liste('/x'), [1]);
      await expectLater(api.objekt('/x'), throwsA(isA<ApiFehler>()));
    });
  });

  group('Rosenweg Geraet (geteiltes Telefon)', () {
    test('Antwort mit Status und JSON', () {
      final a = geraetAntwortLesen({'status': 200, 'json': '{"user":{"name":"B"}}'});
      expect(a.status, 200);
      expect(a.json, {'user': {'name': 'B'}});
    });

    test('niemand angemeldet', () {
      expect(() => geraetAntwortLesen({'nicht_angemeldet': true}), throwsA(isA<NichtAngemeldet>()));
    });

    test('leeres Bundle: Geraet zu alt', () {
      expect(() => geraetAntwortLesen({}), throwsA(isA<GeraetFehler>().having((e) => '$e', 'text', contains('zu alt'))));
    });

    test('andere Signatur', () {
      expect(() => geraetAntwortLesen({'fehler_art': 'signatur'}),
          throwsA(isA<GeraetFehler>().having((e) => '$e', 'text', contains('Signatur'))));
    });

    test('GeraetTransport: Pfad und Extras wie in Rosenweg Geraet (AnlageProvider portal_anfrage)', () async {
      final gesehen = <(String, Map<String, Object?>)>[];
      final t = GeraetTransport('ch.rosenweg4303.salz', rufen: (pfad, extras) async {
        gesehen.add((pfad, extras));
        return {'status': 201, 'json': '{"ok":true}', 'sitzung': 'a1'};
      });
      final a = await t.senden('POST', '/api/salz/buchungen', koerper: {'saecke': 1});
      expect(a.status, 201);
      expect(gesehen.single.$1, '/api/salz/buchungen');
      expect(gesehen.single.$2, {'methode': 'POST', 'koerper': '{"saecke":1}', 'paket': 'ch.rosenweg4303.salz'});
    });

    test('GeraetTransport: andere Sitzungsmarke = Personenwechsel, erste und gleiche nicht', () async {
      var marke = 'a1';
      var wechsel = 0;
      final t = GeraetTransport('ch.rosenweg4303.salz',
          personGewechselt: () => wechsel++, rufen: (_, _) async => {'status': 200, 'json': '{}', 'sitzung': marke});
      await t.senden('GET', '/api/salz/lager');
      await t.senden('GET', '/api/salz/lager');
      expect(wechsel, 0);
      marke = 'b2';
      await t.senden('GET', '/api/salz/lager');
      expect(wechsel, 1);
    });

    test('Geraet: Pfad fuer diese App nicht freigegeben (403 der Anlage)', () async {
      final api = RosenwegApi(GeraetTransport('ch.rosenweg4303.salz',
          rufen: (_, _) async => {'status': 403, 'json': '{"error":"Diese App darf das auf geteilten Telefonen nicht"}'}));
      await expectLater(api.get('/api/admin'), throwsA(isA<KeineBerechtigung>()));
    });

    test('HTML statt JSON vom Geraet weitergereicht', () {
      expect(() => geraetAntwortLesen({'status': 502, 'json': '<html>'}), throwsA(isA<ServerNichtErreichbar>()));
    });
  });

  test('202 bestaetigung email: BestaetigungPerEmail mit Hinweis, Ablauf und Adresse', () {
    final j = {
      'bestaetigung': 'email',
      'id': 'kb_1',
      'ablauf': '2026-11-27T18:15:00.000Z',
      'email': 'e…@example.org',
      'hinweis': 'Bitte bestätige in der E-Mail, die wir dir an e…@example.org geschickt haben.',
    };
    try {
      apiAntwortPruefen((status: 202, json: j));
      fail('keine Ausnahme');
    } on BestaetigungPerEmail catch (e) {
      expect(e.text, contains('e…@example.org'));
      expect(e.id, 'kb_1');
      expect(e.ablauf, isNotNull);
      expect(fehlerFuerPerson(e).details, isNull);
    }
    // gewoehnliches 202 bleibt Erfolg
    expect(apiAntwortPruefen((status: 202, json: {'ok': true})), {'ok': true});
  });
}
