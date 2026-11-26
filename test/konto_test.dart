// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

const app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'Test', ordner: 'rosenweg-test', beschreibung: 'Test');

/// Browser-Attrappe: merkt sich die Anmeldeadresse und antwortet wie Authentik.
class _Weg implements Anmeldeweg, Ruecksprung {
  _Weg(this.antwort);

  /// Aus der Anmeldeadresse die Ruecksprung-Adresse bauen (wie der Browser
  /// nach der Anmeldung).
  final Uri Function(Uri anmeldeseite) antwort;
  Uri? geoeffnet;
  Completer<Uri>? _haengt;

  @override
  String get adresse => 'http://localhost:4711/anmeldung';
  @override
  Future<Ruecksprung> vorbereiten() async => this;
  @override
  Future<Uri> warten(Uri url, {Duration zeit = const Duration(minutes: 5)}) async {
    geoeffnet = url;
    if (_haengt != null) return _haengt!.future;
    return antwort(url);
  }

  @override
  void abbrechen() => _haengt?.completeError(AnmeldungAbgebrochen());
}

Uri _mitCode(Uri seite) => Uri.parse('http://localhost:4711/anmeldung')
    .replace(queryParameters: {'code': 'c0de', 'state': seite.queryParameters['state']!});

http.Response _json(Object j, int s) => http.Response(jsonEncode(j), s, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Protokoll.nurKonsole = true);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// Authentik-Attrappe; [felder] sammelt die Formulare an /token/.
  MockClient authentik(List<Map<String, String>> felder, {int Function(Map<String, String>)? status}) => MockClient((r) async {
        if (r.url.path.endsWith('/userinfo/')) {
          return _json({'name': 'Erika Muster', 'email': 'erika@example.org', 'preferred_username': 'erika.muster'}, 200);
        }
        final f = Uri.splitQueryString(r.body);
        felder.add(f);
        final s = status?.call(f) ?? 200;
        if (s != 200) return _json({'error': 'invalid_grant'}, s);
        return _json({'access_token': 'at-${felder.length}', 'expires_in': 300, 'refresh_token': 'rt-${felder.length}'}, 200);
      });

  test('PKCE-Anmeldung: Challenge, Ruecksprung, Tausch, Speicher', () async {
    final felder = <Map<String, String>>[];
    final weg = _Weg(_mitCode);
    final k = RosenwegKonto(app, weg: weg, client: authentik(felder));
    expect(await k.angemeldet, isFalse);
    await k.anmelden();

    final q = weg.geoeffnet!.queryParameters;
    expect(weg.geoeffnet!.path, '/application/o/authorize/');
    expect(q['client_id'], 'rosenweg-apps');
    expect(q['redirect_uri'], weg.adresse);
    expect(q['scope'], contains('offline_access'));
    expect(q['code_challenge_method'], 'S256');
    expect(q.containsKey('prompt'), isFalse);

    final tausch = felder.single;
    expect(tausch['grant_type'], 'authorization_code');
    expect(tausch['code'], 'c0de');
    expect(tausch['redirect_uri'], weg.adresse);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(tausch['code_verifier']!)).bytes).replaceAll('=', '');
    expect(q['code_challenge'], challenge);

    expect(await k.angemeldet, isTrue);
    expect(await k.zugangsToken(), 'at-1');
    expect(k.name, 'Erika Muster');
    expect(k.benutzername, 'erika.muster');
    // Nur Refresh-Token und Zeitpunkt im Speicher, kein PKCE-Rest.
    final roh = jsonDecode((await const FlutterSecureStorage().read(key: 'rosenweg-test'))!) as Map;
    expect(roh.keys.toSet(), {'refresh_token', 'angemeldet_am'});
    expect(roh['refresh_token'], 'rt-1');
  });

  test('bestaetigen: Authentik fragt erneut (prompt=login, max_age=0)', () async {
    final weg = _Weg(_mitCode);
    await RosenwegKonto(app, weg: weg, client: authentik([])).anmelden(bestaetigen: true);
    expect(weg.geoeffnet!.queryParameters['prompt'], 'login');
    expect(weg.geoeffnet!.queryParameters['max_age'], '0');
  });

  test('falscher state: abgelehnt, nichts gespeichert', () async {
    final weg = _Weg((_) => Uri.parse('http://localhost:4711/anmeldung?code=x&state=fremd'));
    final k = RosenwegKonto(app, weg: weg, client: authentik([]));
    await expectLater(k.anmelden(), throwsA(isA<AnmeldeFehler>()));
    expect(await k.angemeldet, isFalse);
  });

  test('Abbruch in Authentik (error=access_denied)', () async {
    final weg = _Weg((_) => Uri.parse('http://localhost:4711/anmeldung?error=access_denied'));
    await expectLater(RosenwegKonto(app, weg: weg, client: authentik([])).anmelden(), throwsA(isA<AnmeldeFehler>()));
  });

  test('Knopf Abbrechen beendet das Warten', () async {
    final weg = _Weg(_mitCode).._haengt = Completer<Uri>();
    final k = RosenwegKonto(app, weg: weg, client: authentik([]));
    final f = k.anmelden();
    await Future<void>.delayed(Duration.zero);
    k.abbrechen();
    await expectLater(f, throwsA(isA<AnmeldungAbgebrochen>()));
  });

  test('Erneuern mit Refresh-Token, Access-Token im Speicher', () async {
    final felder = <Map<String, String>>[];
    var jetzt = DateTime.utc(2026, 11, 26, 12);
    final k = RosenwegKonto(app, weg: _Weg(_mitCode), client: authentik(felder), jetzt: () => jetzt);
    await k.anmelden();
    expect(await k.zugangsToken(), 'at-1');
    jetzt = jetzt.add(const Duration(minutes: 10)); // abgelaufen
    expect(await k.zugangsToken(), 'at-2');
    expect(felder.last['grant_type'], 'refresh_token');
    expect(felder.last['refresh_token'], 'rt-1');
  });

  test('nach 30 Tagen wieder durch den Browser', () async {
    var jetzt = DateTime.utc(2026, 11, 1);
    final k = RosenwegKonto(app, weg: _Weg(_mitCode), client: authentik([]), jetzt: () => jetzt);
    await k.anmelden();
    jetzt = jetzt.add(const Duration(days: 31));
    expect(await k.angemeldet, isFalse);
    expect(await k.zugangsToken(), isNull);
  });

  test('Refresh abgelehnt (widerrufen): abgemeldet', () async {
    final felder = <Map<String, String>>[];
    var jetzt = DateTime.utc(2026, 11, 26);
    final k = RosenwegKonto(app,
        weg: _Weg(_mitCode),
        client: authentik(felder, status: (f) => f['grant_type'] == 'refresh_token' ? 400 : 200),
        jetzt: () => jetzt);
    await k.anmelden();
    jetzt = jetzt.add(const Duration(hours: 1));
    expect(await k.zugangsToken(), isNull);
    expect(await k.angemeldet, isFalse);
  });

  test('Authentik kurz weg (502 HTML): Anmeldung bleibt', () async {
    var jetzt = DateTime.utc(2026, 11, 26);
    var weg = false;
    final c = MockClient((r) async {
      if (weg) return http.Response('<html>Bad Gateway</html>', 502);
      if (r.url.path.endsWith('/userinfo/')) return _json({}, 200);
      return _json({'access_token': 'a', 'expires_in': 300, 'refresh_token': 'r'}, 200);
    });
    final k = RosenwegKonto(app, weg: _Weg(_mitCode), client: c, jetzt: () => jetzt);
    await k.anmelden();
    weg = true;
    jetzt = jetzt.add(const Duration(hours: 1));
    await expectLater(k.zugangsToken(), throwsA(isA<ServerNichtErreichbar>()));
    expect(await k.angemeldet, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
