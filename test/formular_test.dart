// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

Future<void> _zeigen(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(800, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: rosenwegThema(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('Betraege', () {
    test('lesen', () {
      expect(betragLesen('12'), 1200);
      expect(betragLesen('12.5'), 1250);
      expect(betragLesen('12,50'), 1250);
      expect(betragLesen("1'234.05"), 123405);
      expect(betragLesen('1’234.05'), 123405);
      expect(betragLesen('CHF 12.–'), 1200);
      expect(betragLesen('Fr. 3.20'), 320);
      expect(betragLesen('-4.10'), -410);
      expect(betragLesen('12.345'), isNull);
      expect(betragLesen('abc'), isNull);
      expect(betragLesen(''), isNull);
    });

    test('schreiben', () {
      expect(betragText(0), '0.00');
      expect(betragText(5), '0.05');
      expect(betragText(123405), "1'234.05");
      expect(betragText(100000000), "1'000'000.00");
      expect(betragText(-410), '-4.10');
    });

    test('Datum und Zeit', () {
      expect(datumText(DateTime(2026, 3, 7)), '07.03.2026');
      expect(zeitText(const TimeOfDay(hour: 9, minute: 5)), '09:05');
    });
  });

  test('Pruefen', () {
    expect(Pruefen.pflicht(' '), isNotNull);
    expect(Pruefen.pflicht('x'), isNull);
    expect(Pruefen.email('a@b.ch'), isNull);
    expect(Pruefen.email('a@b'), isNotNull);
    expect(Pruefen.email(''), isNull);
    expect(Pruefen.hoechstens(3)('abcd'), isNotNull);
    expect(Pruefen.alle([Pruefen.pflicht, Pruefen.email])(''), 'Bitte ausfüllen.');
  });

  testWidgets('Pflichtfeld leer: nicht speichern, Fehler am Feld', (t) async {
    var gespeichert = 0;
    await _zeigen(t, RosenwegFormular(speichern: () async => gespeichert++, felder: const [TextFeld(name: 'name', titel: 'Name', pflicht: true)]));
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(gespeichert, 0);
    expect(find.text('Bitte ausfüllen.'), findsOneWidget);
  });

  testWidgets('Speichern: Kreisel, danach Meldung', (t) async {
    final fertig = <void Function()>[];
    await _zeigen(
      t,
      RosenwegFormular(
        speichern: () {
          final f = Future<void>.delayed(const Duration(milliseconds: 100));
          fertig.add(() {});
          return f;
        },
        felder: const [TextFeld(name: 'name', titel: 'Name', anfangswert: 'Anna')],
      ),
    );
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pump();
    expect(find.text('Wird gespeichert …'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 150));
    await t.pumpAndSettle();
    expect(find.text('Gespeichert.'), findsOneWidget);
    expect(fertig, hasLength(1));
  });

  testWidgets('API lehnt ab: Text am Feld bzw. oben', (t) async {
    var runde = 0;
    await _zeigen(
      t,
      RosenwegFormular(
        speichern: () async {
          runde++;
          if (runde == 1) throw ApiFehler(400, 'Ungültige E-Mail', {'error': 'Ungültige E-Mail', 'feld': 'email'});
          throw ApiFehler(409, 'Jemand anderes hat das gerade geändert.', {'error': 'Jemand anderes hat das gerade geändert.'});
        },
        felder: const [TextFeld(name: 'email', titel: 'E-Mail', anfangswert: 'a@b.ch')],
      ),
    );
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(find.text('Ungültige E-Mail'), findsOneWidget);
    expect(find.text('Bitte die markierten Felder prüfen.'), findsOneWidget);
    // Tippen im Feld nimmt den Fehler der API weg
    await t.enterText(find.byType(TextFormField), 'c@d.ch');
    await t.pump();
    expect(find.text('Ungültige E-Mail'), findsNothing);
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(find.text('Jemand anderes hat das gerade geändert.'), findsOneWidget);
  });

  testWidgets('ungespeicherte Aenderungen: Zurueck fragt', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => FilledButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(),
              body: RosenwegFormular(speichern: () async {}, felder: const [TextFeld(name: 'x', titel: 'X')]),
            ),
          )),
          child: const Text('Öffnen'),
        ),
      ),
    ));
    await t.tap(find.text('Öffnen'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'neu');
    await t.pump();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    await t.tap(find.text('Abbrechen'));
    await t.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Verwerfen'));
    await t.pumpAndSettle();
    expect(find.text('Öffnen'), findsOneWidget);
  });

  testWidgets('BetragFeld meldet Rappen, prueft Eingabe', (t) async {
    int? rappen;
    await _zeigen(t, RosenwegFormular(speichern: () async {}, felder: [BetragFeld(name: 'b', titel: 'Betrag', geaendert: (r) => rappen = r)]));
    await t.enterText(find.byType(TextFormField), "1'250,5");
    expect(rappen, 125050);
    await t.enterText(find.byType(TextFormField), '12.345');
    await t.tap(find.byKey(const Key('formular-speichern')));
    await t.pumpAndSettle();
    expect(find.text('Bitte einen Betrag wie 12.50 eingeben.'), findsOneWidget);
  });

  testWidgets('Auswahl mit Suche', (t) async {
    String? gewaehlt;
    await _zeigen(
      t,
      RosenwegFormular(speichern: () async {}, felder: [
        SuchAuswahlFeld<String>(
          name: 'person',
          titel: 'Person',
          text: (s) => s,
          suchen: (q) async => ['Anna Muster', 'Beat Beispiel'].where((n) => n.toLowerCase().contains(q.toLowerCase())).toList(),
          geaendert: (p) => gewaehlt = p,
        ),
      ]),
    );
    await t.tap(find.byIcon(Icons.search));
    await t.pumpAndSettle();
    expect(find.text('Beat Beispiel'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'beat');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.text('Anna Muster'), findsNothing);
    await t.tap(find.text('Beat Beispiel'));
    await t.pumpAndSettle();
    expect(gewaehlt, 'Beat Beispiel');
    expect(find.text('Beat Beispiel'), findsOneWidget);
  });

  testWidgets('loeschenBestaetigen', (t) async {
    bool? ja;
    await _zeigen(
      t,
      Builder(builder: (c) => TextButton(onPressed: () async => ja = await loeschenBestaetigen(c, 'Meldung'), child: const Text('x'))),
    );
    await t.tap(find.text('x'));
    await t.pumpAndSettle();
    expect(find.text('Meldung löschen?'), findsOneWidget);
    await t.tap(find.text('Löschen'));
    await t.pumpAndSettle();
    expect(ja, isTrue);
  });
}
