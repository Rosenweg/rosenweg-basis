// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_basis/src/anmeldung/kerberos.dart' show gssTokenAus, istNtlm, sspiZiel;

const app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'Test', ordner: 'rosenweg-test', beschreibung: 'Test');
const dienst = 'HTTP/authentik.rosenweg4303.ch@AD.ROSENWEG4303.CH';

class _Ticket implements KerberosTicket {
  _Ticket(this.wert);
  final String? wert;
  final gefragt = <String>[];
  @override
  Future<String?> token(String d, {Duration zeit = const Duration(seconds: 8)}) async {
    gefragt.add(d);
    return wert;
  }
}

/// Authentik 2026.5.3 nachgebaut, so wie es auf die Anfragen antwortet
/// (sources/kerberos/views.py, core/sources/flow_manager.py,
/// flows/views/executor.py, providers/oauth2/views/authorization.py).
class _Authentik {
  _Authentik({this.kerberosGilt = true, this.zustimmungFehlt = false, this.ablaufFragt});

  final bool kerberosGilt;

  /// Explizite Zustimmung, noch nicht gegeben (default-provider-authorization-explicit-consent).
  final bool zustimmungFehlt;

  /// Ablauf-API antwortet mit dieser Komponente statt weiterzuleiten.
  final String? ablaufFragt;

  final anfragen = <Uri>[];
  final kopfe = <Map<String, String>>[];
  bool angemeldet = false;
  bool planOffen = false;
  int ausfuehrungen = 0;

  StilleAntwort _weiter(String ziel, {List<Cookie> cookies = const [], Map<String, String> kopf = const {}}) =>
      StilleAntwort(302, kopf: {'location': ziel, ...kopf}, cookies: cookies);

  bool _sitzung(Map<String, String> k) => (k['Cookie'] ?? '').contains('authentik_session=s1');

  Future<StilleAntwort> holen(Uri url, Map<String, String> k) async {
    anfragen.add(url);
    kopfe.add(k);
    final p = url.path;
    if (p == '/source/kerberos/ad-kerberos/') {
      final cookie = [Cookie('authentik_session', 's1')..httpOnly = true];
      if (url.queryParameters['state'] == null) return _weiter('/source/kerberos/ad-kerberos/?state=abc', cookies: cookie);
      final auth = k['Authorization'];
      if (auth == null || !kerberosGilt) {
        return StilleAntwort(401, kopf: {'www-authenticate': 'Negotiate'}, text: '<html>SPNEGO authentication required</html>');
      }
      expect(auth, 'Negotiate dGlja2V0');
      planOffen = true;
      return _weiter('/if/flow/default-source-authentication/?', kopf: {'www-authenticate': 'Negotiate b2s='});
    }
    if (p == '/api/v3/flows/executor/default-source-authentication/') {
      expect(_sitzung(k), isTrue);
      expect(planOffen, isTrue);
      if (ablaufFragt != null) return StilleAntwort(200, text: jsonEncode({'component': ablaufFragt}));
      // Erst die im Speicher angehaengten Stufen (Umleitung auf sich selbst), dann fertig.
      if (ausfuehrungen++ == 0) return _weiter(url.toString().replaceFirst('https://authentik.rosenweg4303.ch', ''));
      angemeldet = true;
      return StilleAntwort(200, text: jsonEncode({'component': 'xak-flow-redirect', 'to': '/if/user/'}));
    }
    if (p == '/application/o/authorize/') {
      if (!_sitzung(k) || !angemeldet) {
        return _weiter('/flows/-/default/authentication/?next=${Uri.encodeQueryComponent(url.toString())}');
      }
      if (zustimmungFehlt) return _weiter('/if/flow/default-provider-authorization-explicit-consent/?');
      final q = url.queryParameters;
      return _weiter(Uri.parse(q['redirect_uri']!).replace(queryParameters: {'code': 'c0de', 'state': q['state']!}).toString());
    }
    if (p == '/api/v3/flows/executor/default-provider-authorization-explicit-consent/') {
      return StilleAntwort(200, text: jsonEncode({'component': 'ak-stage-consent'}));
    }
    if (p == '/flows/-/default/authentication/') {
      return _weiter('/if/flow/default-authentication-flow/?next=${Uri.encodeQueryComponent(url.queryParameters['next']!)}');
    }
    if (p == '/api/v3/flows/executor/default-authentication-flow/') {
      return StilleAntwort(200, text: jsonEncode({'component': 'ak-stage-identification'}));
    }
    return StilleAntwort(404, text: 'nicht nachgebaut: $p');
  }
}

StilleAnmeldung _still(_Authentik a, {String? ticket = 'dGlja2V0', _Ticket? t}) => StilleAnmeldung(
      authentik: Uri.parse('https://authentik.rosenweg4303.ch/'),
      quelle: 'ad-kerberos',
      dienst: dienst,
      ticket: t ?? _Ticket(ticket),
      holen: a.holen,
    );

Uri _autorisierung() => Uri.parse('https://authentik.rosenweg4303.ch/application/o/authorize/').replace(queryParameters: {
      'response_type': 'code',
      'client_id': 'rosenweg-apps',
      'redirect_uri': RosenwegKonto.stillerRuecksprung,
      'state': 'st',
    });

http.Response _json(Object j, int s) => http.Response(jsonEncode(j), s, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Protokoll.nurKonsole = true);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('StilleAnmeldung', () {
    test('Kerberos → Ablauf → Autorisierung → Code, ohne Browser', () async {
      final a = _Authentik();
      final t = _Ticket('dGlja2V0');
      final r = await _still(a, t: t).ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung);
      expect(r, isNotNull);
      expect(r!.queryParameters, {'code': 'c0de', 'state': 'st'});
      expect(t.gefragt, [dienst]);
      // Die Anmeldeseite (/if/flow/…) wird nie geholt, nur die API dahinter.
      expect(a.anfragen.where((u) => u.path.startsWith('/if/')), isEmpty);
      // Das Token geht nur an die Kerberos-Quelle, nirgends sonst hin.
      for (var i = 0; i < a.anfragen.length; i++) {
        if (a.kopfe[i].containsKey('Authorization')) expect(a.anfragen[i].path, '/source/kerberos/ad-kerberos/');
      }
      expect(a.kopfe.where((k) => k.containsKey('Authorization')).length, 1);
      // Der Ruecksprung selbst wird nicht aufgerufen.
      expect(a.anfragen.where((u) => u.host == 'localhost'), isEmpty);
    });

    test('kein Ticket: null, kein Token gesendet', () async {
      final a = _Authentik();
      final s = _still(a, ticket: null);
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
      expect(s.grund, contains('kein Kerberos-Ticket'));
      expect(a.anfragen.where((u) => u.path.contains('authorize')), isEmpty);
    });

    test('Ticket abgelehnt: null nach genau einem Versuch', () async {
      final a = _Authentik(kerberosGilt: false);
      final s = _still(a);
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
      expect(s.grund, 'Kerberos-Ticket abgelehnt');
      expect(a.kopfe.where((k) => k.containsKey('Authorization')).length, 1);
    });

    test('Zustimmung noetig: null (dann Browser)', () async {
      final a = _Authentik(zustimmungFehlt: true);
      final s = _still(a);
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
      expect(s.grund, contains('ak-stage-consent'));
    });

    test('Ablauf fragt (z. B. zweiter Faktor): null', () async {
      final a = _Authentik(ablaufFragt: 'ak-stage-authenticator-validate');
      final s = _still(a);
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
      expect(s.grund, contains('ak-stage-authenticator-validate'));
    });

    test('fremdes Ziel wird nicht verfolgt, Cookies nur fuer Authentik', () async {
      final gesehen = <Uri>[];
      final s = StilleAnmeldung(
        authentik: Uri.parse('https://authentik.rosenweg4303.ch/'),
        quelle: 'ad-kerberos',
        dienst: dienst,
        ticket: _Ticket('x'),
        holen: (u, k) async {
          gesehen.add(u);
          return StilleAntwort(302, kopf: {'location': 'https://boese.example/'}, cookies: [Cookie('authentik_session', 's1')]);
        },
      );
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
      expect(s.grund, 'Weiterleitung zu fremdem Ziel');
      expect(gesehen.every((u) => u.host == 'authentik.rosenweg4303.ch'), isTrue);
    });

    test('Netzfehler: null statt Ausnahme', () async {
      final s = StilleAnmeldung(
        authentik: Uri.parse('https://authentik.rosenweg4303.ch/'),
        quelle: 'ad-kerberos',
        dienst: dienst,
        ticket: _Ticket('x'),
        holen: (u, k) async => throw const SocketException('weg'),
      );
      expect(await s.ausfuehren(_autorisierung(), RosenwegKonto.stillerRuecksprung), isNull);
    });
  });

  group('RosenwegKonto.stillAnmelden', () {
    MockClient tokenStelle(List<Map<String, String>> felder) => MockClient((r) async {
          if (r.url.path.endsWith('/userinfo/')) return _json({'name': 'Erika Muster', 'preferred_username': 'erika.muster'}, 200);
          felder.add(Uri.splitQueryString(r.body));
          return _json({'access_token': 'at', 'expires_in': 300, 'refresh_token': 'rt'}, 200);
        });

    test('tauscht den Code mit PKCE und gilt als frische Anmeldung', () async {
      final felder = <Map<String, String>>[];
      final a = _Authentik();
      final k = RosenwegKonto(app, client: tokenStelle(felder), still: () => _still(a));
      expect(await k.stillAnmelden(), isTrue);
      expect(await k.angemeldet, isTrue);
      expect(k.benutzername, 'erika.muster');
      final f = felder.single;
      expect(f['grant_type'], 'authorization_code');
      expect(f['redirect_uri'], RosenwegKonto.stillerRuecksprung);
      expect(f['code_verifier'], isNotEmpty);
      final auth = a.anfragen.firstWhere((u) => u.path == '/application/o/authorize/');
      expect(auth.queryParameters['code_challenge_method'], 'S256');
      expect(auth.queryParameters.containsKey('prompt'), isFalse);
      expect(await k.zugangsToken(), 'at');
    });

    test('ohne stille Anmeldung (Telefon, macOS): false, nichts angefragt', () async {
      final felder = <Map<String, String>>[];
      final k = RosenwegKonto(app, client: tokenStelle(felder), still: () => null);
      expect(await k.stillAnmelden(), isFalse);
      expect(felder, isEmpty);
    });
  });

  group('RosenwegSitzung', () {
    test('Start ohne gespeicherte Anmeldung: still angemeldet, kein Knopf', () async {
      final a = _Authentik();
      final s = RosenwegSitzung(app,
          konto: RosenwegKonto(app, client: MockClient((r) async => _json({'access_token': 'at', 'refresh_token': 'rt'}, 200)), still: () => _still(a)),
          geraetDa: () async => false);
      await s.starten();
      expect(s.phase, Phase.bereit);
    });

    test('Start ohne Ticket: Knopf wie bisher', () async {
      final a = _Authentik();
      final s = RosenwegSitzung(app,
          konto: RosenwegKonto(app, client: MockClient((r) async => _json({}, 400)), still: () => _still(a, ticket: null)),
          geraetDa: () async => false);
      await s.starten();
      expect(s.phase, Phase.abgemeldet);
    });
  });

  group('Kerberos-Bausteine', () {
    test('NTLM wird erkannt (Windows faellt nicht still auf NTLM zurueck)', () {
      expect(istNtlm(Uint8List.fromList('xxNTLMSSP\u0000\u0001'.codeUnits)), isTrue);
      expect(istNtlm(Uint8List.fromList([0x60, 0x82, 0x6b, 0x72, 0x62])), isFalse);
    });

    test('SSPI-Ziel ohne Realm', () {
      expect(sspiZiel(dienst), 'HTTP/authentik.rosenweg4303.ch');
    });

    test('GSS-API dieses Rechners: kein Absturz, ohne Ticket kein Token', () {
      final lib = Platform.isMacOS
          ? '/System/Library/Frameworks/GSS.framework/GSS'
          : Platform.isLinux
              ? 'libgssapi_krb5.so.2'
              : null;
      if (lib == null) return;
      final e = gssTokenAus(lib, dienst);
      // Mit Ticket (Station, kinit) gaebe es ein Token; sonst einen Grund.
      expect(e.token != null || e.grund.isNotEmpty, isTrue);
      expect(gssTokenAus('/nicht/da/libgssapi.so', dienst).grund, contains('fehlt'));
    });
  });
}
