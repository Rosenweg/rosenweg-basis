// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

class _Leer implements Transport {
  final pfade = <String>[];
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    pfade.add(pfad);
    return (status: 200, json: {'ok': true});
  }
}

const _app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'Rosenweg Test', ordner: 'rosenweg-test', beschreibung: 'Test.');

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);
  setUp(() => Benachrichtigung.attrappe = []);

  test('zeigen und planen (Vergangenheit = nichts), entfernen', () async {
    await Benachrichtigung.einrichten(_app);
    await Benachrichtigung.zeigen(id: 1, titel: 'A', text: 'a', ziel: 'meine/1');
    await Benachrichtigung.planen(id: 2, wann: DateTime.now().add(const Duration(hours: 1)), titel: 'B', text: 'b');
    await Benachrichtigung.planen(id: 3, wann: DateTime.now().subtract(const Duration(minutes: 1)), titel: 'C', text: 'c');
    expect(Benachrichtigung.attrappe!.map((x) => x.id), [1, 2]);
    expect(Benachrichtigung.attrappe!.first.ziel, 'meine/1');
    await Benachrichtigung.entfernen(2);
    expect(Benachrichtigung.attrappe!.map((x) => x.id), [1]);
  });

  test('Windows-GUID und Ids sind stabil', () {
    final g = Benachrichtigung.windowsGuid('ch.rosenweg4303.reparatur');
    expect(g, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(Benachrichtigung.windowsGuid('ch.rosenweg4303.reparatur'), g);
    expect(Benachrichtigung.idFuer('meldung-41'), Benachrichtigung.idFuer('meldung-41'));
    expect(Benachrichtigung.idFuer('meldung-41'), isNot(Benachrichtigung.idFuer('meldung-42')));
    expect(Benachrichtigung.idFuer('x'), greaterThanOrEqualTo(0));
  });

  test('HintergrundAbfrage.einmal: mit Sitzung, Kontext mit eigenem Speicher', () async {
    final t = _Leer();
    final s = RosenwegSitzung(_app, transport: t);
    await s.starten();
    HintergrundKontext? k;
    final ok = await HintergrundAbfrage.einmal(_app, (x) async {
      k = x;
      await x.sitzung.api.get('/api/test');
      await Benachrichtigung.zeigen(id: 9, titel: 'Neu', text: 'Etwas ist neu.');
    }, sitzung: s);
    expect(ok, isTrue);
    expect(k!.imHintergrund, isFalse);
    expect(t.pfade, ['/api/test']);
    expect(Benachrichtigung.attrappe!.single.titel, 'Neu');
    expect(HintergrundAbfrage.aufgabe(_app), 'ch.rosenweg4303.test.abfrage');
  });

  test('HintergrundAbfrage.einmal: Fehler der Abfrage = false, kein Absturz', () async {
    final s = RosenwegSitzung(_app, transport: _Leer());
    await s.starten();
    expect(await HintergrundAbfrage.einmal(_app, (_) async => throw StateError('kaputt'), sitzung: s), isFalse);
  });

  test('hintergrundStarten mit festem Transport', () async {
    final s = RosenwegSitzung(_app, transport: _Leer());
    expect(await s.hintergrundStarten(), isTrue);
    expect(s.phase, Phase.bereit);
  });

  test('hintergrundStarten am geteilten Telefon: ueber Rosenweg Geraet', () async {
    final s = RosenwegSitzung(_app, geraetDa: () async => true);
    expect(await s.hintergrundStarten(), isTrue);
    expect(s.geteiltesTelefon, isTrue);
    expect(s.phase, Phase.bereit);
  });

  test('AppVerweise: Attrappe', () async {
    AppVerweise.attrappe = Stream.value(Uri.parse('https://pwa.rosenweg4303.ch/reparatur/?ort=abcd2345'));
    expect((await AppVerweise.strom.first).queryParameters['ort'], 'abcd2345');
    AppVerweise.attrappe = null;
  });
}
