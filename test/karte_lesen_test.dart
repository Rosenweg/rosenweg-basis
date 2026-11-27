// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Leser fuer Tests: Karten kommen ueber [auflegen].
class _TestLeser implements Kartenleser {
  _TestLeser({this.da = true, this.knopf = false});
  bool da;
  final bool knopf;
  final _karten = StreamController<String>.broadcast();
  int zuhoerer = 0;

  void auflegen(String uid) => _karten.add(uid);

  @override
  bool get aufKnopfdruck => knopf;

  @override
  Future<bool> verfuegbar() async => da;

  @override
  Stream<String> lauschen() {
    zuhoerer++;
    return _karten.stream;
  }

  @override
  Future<String?> einmalLesen() async => '04aabbcc';
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  test('UID vereinheitlichen: Gross, ohne Trennzeichen, 4/7/10 Byte', () {
    expect(karteUidNormal('04:d4:c2:27:c2:2a:81'), '04D4C227C22A81');
    expect(karteUidNormal(' 04 D4 C2 27 '), '04D4C227');
    expect(karteUidNormal('04-D4-C2-27-C2-2A-81-11-22-33'), '04D4C227C22A81112233');
    expect(karteUidNormal('04D4C2'), isNull);
    expect(karteUidNormal('04D4C22X'), isNull);
    expect(karteUidNormal(''), isNull);
  });

  test('Hindernisse: ohne Leser = Plattform, Leser ohne Karte = kein Leser', () async {
    expect(await kartenleserHindernis(null), KartenleserHindernis.plattform);
    expect(await kartenleserHindernis(_TestLeser(da: false)), KartenleserHindernis.keinLeser);
    expect(await kartenleserHindernis(_TestLeser()), isNull);
    final p = PcscKartenleser(oeffnen: () => null);
    expect(await kartenleserHindernis(p), KartenleserHindernis.keinPcsc);
  });

  testWidgets('karteLesen: Karte auflegen gibt die UID zurueck, Pruefung haelt falsche auf', (t) async {
    final l = _TestLeser();
    String? gelesen;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => FilledButton(
          onPressed: () async => gelesen = await karteLesen(c,
              leser: l, pruefen: (u) => u.startsWith('04') ? null : 'Diese Karte gehört nicht zum Rosenweg.'),
          child: const Text('Lesen'),
        ),
      ),
    ));
    await t.tap(find.text('Lesen'));
    await t.pumpAndSettle();
    expect(find.text('Karte an die Rückseite des Handys halten.'), findsOneWidget);
    expect(l.zuhoerer, 1);

    l.auflegen('AABBCCDD');
    await t.pump();
    await t.pump();
    expect(find.text('Diese Karte gehört nicht zum Rosenweg.'), findsOneWidget);

    l.auflegen('04:d4:c2:27');
    await t.pumpAndSettle();
    expect(gelesen, '04D4C227');
    // Timer der Seite ist mit der Seite weg
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('kein Leser: klare Meldung, erscheint er, wird gelesen', (t) async {
    final l = _TestLeser(da: false);
    final karten = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: KartenleserBereich(leser: l, beiKarte: karten.add, takt: const Duration(milliseconds: 100))),
    ));
    await t.pump();
    expect(find.text(KartenleserHindernis.keinLeser.text), findsOneWidget);
    expect(l.zuhoerer, 0);

    l.da = true;
    await t.pump(const Duration(milliseconds: 150));
    await t.pump();
    expect(find.byKey(const Key('kartenleser-bereit')), findsOneWidget);
    l.auflegen('04AABBCC');
    await t.pump();
    await t.pump();
    expect(karten, ['04AABBCC']);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('auf Knopfdruck (iOS): Knopf "Karte lesen"', (t) async {
    final l = _TestLeser(knopf: true);
    final karten = <String>[];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: KartenleserBereich(leser: l, beiKarte: karten.add))));
    await t.pump();
    await t.tap(find.text('Karte lesen'));
    await t.pump();
    expect(karten, ['04AABBCC']);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Nummer eintippen: falsche Nummer mit deutschem Satz, richtige wird uebernommen', (t) async {
    String? gelesen;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => FilledButton(
          onPressed: () async => gelesen = await karteLesen(c, leser: _TestLeser(da: false), eintippen: true),
          child: const Text('Lesen'),
        ),
      ),
    ));
    await t.tap(find.text('Lesen'));
    await t.pumpAndSettle();
    await t.tap(find.text('Nummer eintippen'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('uid-feld')), '12345');
    await t.tap(find.byKey(const Key('uid-ok')));
    await t.pump();
    expect(find.textContaining('keine Kartennummer'), findsOneWidget);
    await t.enterText(find.byKey(const Key('uid-feld')), '04 d4 c2 27 c2 2a 81');
    await t.tap(find.byKey(const Key('uid-ok')));
    await t.pumpAndSettle();
    expect(gelesen, '04D4C227C22A81');
  });
}
