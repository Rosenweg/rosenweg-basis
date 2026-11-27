// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

void main() {
  test('Desktop: Ruecksprung auf localhost liefert code und state', () async {
    late Uri geoeffnet;
    final weg = LocalhostAnmeldeweg(oeffnen: (u) async {
      geoeffnet = u;
      return true;
    });
    final r = await weg.vorbereiten();
    expect(r.adresse, matches(RegExp(r'^http://localhost:[0-9]+/anmeldung$')));
    final warten = r.warten(Uri.parse('https://authentik.example/authorize/'));
    // Der "Browser" folgt der Weiterleitung von Authentik.
    final c = HttpClient();
    final antwort = await (await c.getUrl(Uri.parse('${r.adresse}?code=abc&state=s1'))).close();
    expect(antwort.statusCode, 200);
    c.close();
    final u = await warten;
    expect(geoeffnet.host, 'authentik.example');
    expect(u.queryParameters, {'code': 'abc', 'state': 's1'});
  });

  test('Desktop: Favicon und fremde Pfade zaehlen nicht', () async {
    final r = await const LocalhostAnmeldeweg(oeffnen: _ja).vorbereiten();
    final warten = r.warten(Uri.parse('https://a/'), zeit: const Duration(seconds: 2));
    final c = HttpClient();
    final port = Uri.parse(r.adresse).port;
    await (await c.getUrl(Uri.parse('http://localhost:$port/favicon.ico?code=x'))).close();
    await (await c.getUrl(Uri.parse('${r.adresse}?error=access_denied'))).close();
    c.close();
    expect((await warten).queryParameters['error'], 'access_denied');
  });

  test('Desktop: Abbrechen schliesst den Port', () async {
    final r = await const LocalhostAnmeldeweg(oeffnen: _ja).vorbereiten();
    final warten = r.warten(Uri.parse('https://a/'));
    r.abbrechen();
    await expectLater(warten, throwsA(isA<AnmeldungAbgebrochen>()));
    final c = HttpClient();
    await expectLater(c.getUrl(Uri.parse(r.adresse)).then((q) => q.close()), throwsA(isA<SocketException>()));
    c.close();
  });

  test('Android: Schema-Ruecksprung kommt ueber den Kanal', () async {
    final ankunft = StreamController<String>.broadcast();
    final r = SchemaRuecksprung('ch.rosenweg4303.test:/anmeldung', _ja, ankunft.stream);
    final warten = r.warten(Uri.parse('https://a/'));
    ankunft.add('ch.rosenweg4303.test:/anmeldung?code=z&state=q');
    final u = await warten;
    expect(u.scheme, 'ch.rosenweg4303.test');
    expect(u.queryParameters['code'], 'z');
    await ankunft.close();
  });

  test('Browser laesst sich nicht oeffnen: klare Meldung', () async {
    final r = await LocalhostAnmeldeweg(oeffnen: (_) async => false).vorbereiten();
    await expectLater(r.warten(Uri.parse('https://a/')), throwsA(isA<BrowserNichtGeoeffnet>()));
  });
}

Future<bool> _ja(Uri _) async => true;
