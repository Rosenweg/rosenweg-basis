// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

// Mittwoch, 25.11.2026, 10:20
final _jetzt = DateTime(2026, 11, 25, 10, 20);
final _montag = DateTime(2026, 11, 23);

List<RasterEintrag<int>> _eintraege() => [
      RasterEintrag(von: DateTime(2026, 11, 25, 9), bis: DateTime(2026, 11, 25, 11), titel: 'Erika Muster', art: RasterArt.eigen, daten: 1),
      RasterEintrag(von: DateTime(2026, 11, 23, 14), bis: DateTime(2026, 11, 23, 16, 30), titel: 'Max Beispiel', daten: 2),
      RasterEintrag(von: DateTime(2026, 11, 27, 7), bis: DateTime(2026, 11, 27, 8), titel: 'Reinigung', art: RasterArt.gesperrt, daten: 3),
      // andere Woche: nicht sichtbar
      RasterEintrag(von: DateTime(2026, 11, 30, 9), bis: DateTime(2026, 11, 30, 10), titel: 'Nächste Woche', daten: 4),
    ];

Future<void> _zeigen(WidgetTester t, Size g, {ValueChanged<DateTime>? leer, ValueChanged<RasterEintrag<int>>? eintrag, DateTime? montag}) async {
  t.view.physicalSize = g;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: rosenwegThema(Brightness.light),
    home: Scaffold(
      body: Wochenraster<int>(
        montag: montag ?? _montag,
        eintraege: _eintraege(),
        jetzt: () => _jetzt,
        leerGetippt: leer,
        eintragGetippt: eintrag,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('montagVon und Kalenderwoche', () {
    expect(montagVon(DateTime(2026, 11, 29, 23, 59)), DateTime(2026, 11, 23));
    expect(montagVon(DateTime(2026, 11, 23)), DateTime(2026, 11, 23));
    expect(montagVon(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    expect(kalenderwoche(DateTime(2026, 11, 23)), 48);
    expect(kalenderwoche(DateTime(2027, 1, 1)), 53);
    expect(kalenderwoche(DateTime(2027, 1, 4)), 1);
    expect(uhrText(DateTime(2026, 1, 1, 8, 5)), '08:05');
    expect(tagLangText(DateTime(2026, 11, 23)), 'Montag, 23.11.2026');
  });

  testWidgets('breit: sieben Tage, nur Eintraege dieser Woche', (t) async {
    await _zeigen(t, const Size(1000, 800));
    expect(find.byType(ChoiceChip), findsNothing);
    for (final tag in wochentageKurz) {
      expect(find.text(tag), findsOneWidget);
    }
    expect(find.text('09:00–11:00'), findsOneWidget);
    expect(find.text('14:00–16:30'), findsOneWidget);
    expect(find.text('07:00–08:00'), findsOneWidget);
    expect(find.text('Nächste Woche'), findsNothing);
  });

  testWidgets('schmal: ein Tag (heute), Tage zum Antippen', (t) async {
    await _zeigen(t, const Size(400, 800));
    expect(find.byType(ChoiceChip), findsNWidgets(7));
    expect(find.text('09:00–11:00'), findsOneWidget, reason: 'heute = Mittwoch');
    expect(find.text('14:00–16:30'), findsNothing);
    await t.tap(find.text('Mo 23.'));
    await t.pumpAndSettle();
    expect(find.text('14:00–16:30'), findsOneWidget);
    expect(find.text('09:00–11:00'), findsNothing);
  });

  testWidgets('Tippen: Eintrag bzw. freie Stelle (auf 15 Minuten abgerundet)', (t) async {
    RasterEintrag<int>? getippt;
    DateTime? frei;
    await _zeigen(t, const Size(400, 800), leer: (z) => frei = z, eintrag: (e) => getippt = e);
    await t.tap(find.text('09:00–11:00'));
    expect(getippt?.daten, 1);

    // freie Stelle: 12:40 auf der Hoehe (Standard 56 px/h, ab 06:00) → 12:30
    final spalte = t.getTopLeft(find.byType(Wochenraster<int>));
    final kopf = t.getBottomLeft(find.byType(Divider).first).dy;
    final scroll = t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).last).controller!.offset;
    final y = kopf + (12 + 40 / 60 - 6) * 56 - scroll;
    await t.tapAt(Offset(spalte.dx + 200, y));
    expect(frei, DateTime(2026, 11, 25, 12, 30));
  });

  testWidgets('Laufender Termin hat eine Beschreibung fuer Bildschirmleser', (t) async {
    final h = t.ensureSemantics();
    await _zeigen(t, const Size(1000, 800), eintrag: (_) {});
    expect(find.bySemanticsLabel(RegExp('Erika Muster, Mittwoch, 25.11.2026, 09:00–11:00, läuft gerade')), findsOneWidget);
    h.dispose();
  });

  testWidgets('WochenKopf blaettert und springt zu heute', (t) async {
    DateTime? neu;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: WochenKopf(montag: DateTime(2026, 12, 7), geaendert: (m) => neu = m, jetzt: () => _jetzt)),
    ));
    expect(find.text('KW 50 · 7.12.–13.12.2026'), findsOneWidget);
    await t.tap(find.byTooltip('Vorige Woche'));
    expect(neu, DateTime(2026, 11, 30));
    await t.tap(find.byTooltip('Nächste Woche'));
    expect(neu, DateTime(2026, 12, 14));
    await t.tap(find.text('Heute'));
    expect(neu, _montag);
  });
}
