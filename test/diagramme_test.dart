// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

final _start = DateTime(2026, 11, 28, 0);

Messreihe _reihe({int n = 48, bool luecke = false}) => Messreihe(
      titel: 'Temperatur',
      einheit: '°C',
      punkte: [
        for (var i = 0; i < n; i++)
          Messpunkt(_start.add(Duration(minutes: 30 * i)), luecke && i >= 10 && i < 14 ? null : 2 + i / 10),
      ],
    );

Future<void> _zeigen(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(800, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: rosenwegThema(Brightness.light), home: Scaffold(body: Center(child: w))));
}

void main() {
  test('Messreihe: kleinster, groesster, letzter, Text', () {
    final r = _reihe(luecke: true);
    expect(r.gueltige.length, 44);
    expect(r.kleinster, 2);
    expect(r.groesster, closeTo(6.7, 1e-9));
    expect(r.text(r.letzter!.wert), '6.7 °C');
    expect(r.text(null), '–');
    expect(r.ausschnitt(_start, _start.add(const Duration(hours: 2))).punkte.length, 5);
    expect(const Messreihe(titel: 'x', punkte: []).leer, isTrue);
  });

  test('Achsen: schoener Schritt und Zeittexte', () {
    expect(schoenerSchritt(4.7, 4), 1);
    expect(schoenerSchritt(47, 4), 10);
    expect(schoenerSchritt(0.3, 4), closeTo(0.1, 1e-9));
    expect(schoenerSchritt(0.2, 4), closeTo(0.05, 1e-9));
    expect(zeitachseText(DateTime(2026, 11, 28, 14, 5), const Duration(hours: 24)), '14:05');
    expect(zeitachseText(DateTime(2026, 11, 28, 14, 5), const Duration(days: 7)), '28.11.');
    expect(zeitpunktText(DateTime(2026, 11, 27, 8, 0), jetzt: DateTime(2026, 11, 28)), '27.11. 08:00');
    expect(zeitpunktText(DateTime(2026, 11, 28, 8, 0), jetzt: DateTime(2026, 11, 28, 9)), '08:00');
  });

  testWidgets('Verlauf als Linie: Luecke bleibt offen, Bildschirmleser hoert Spanne', (t) async {
    await _zeigen(t, Verlaufsdiagramm(reihe: _reihe(luecke: true)));
    final c = t.widget<LineChart>(find.byType(LineChart));
    final spots = c.data.lineBarsData.single.spots;
    expect(spots.where((s) => s.isNull()).length, 1);
    expect(find.bySemanticsLabel(RegExp(r'Temperatur: 6.7 °C, zwischen 2.0 °C und 6.7 °C')), findsOneWidget);
  });

  testWidgets('Verlauf als Balken', (t) async {
    await _zeigen(t, Verlaufsdiagramm(reihe: _reihe(n: 12), art: DiagrammArt.balken, nullLinie: true));
    final c = t.widget<BarChart>(find.byType(BarChart));
    expect(c.data.barGroups.length, 12);
    expect(c.data.minY, 0);
  });

  testWidgets('zu wenig Werte: Satz statt leeres Raster', (t) async {
    await _zeigen(t, Verlaufsdiagramm(reihe: _reihe(n: 1)));
    expect(find.text('Keine Werte in diesem Zeitraum.'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    await _zeigen(t, Kleinverlauf(reihe: _reihe(n: 0)));
    expect(find.text('noch keine Werte'), findsOneWidget);
    await _zeigen(t, Kleinverlauf(reihe: _reihe()));
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('ZeitraumWahl meldet die Wahl', (t) async {
    Zeitraum? gewaehlt;
    await _zeigen(t, ZeitraumWahl(gewaehlt: Zeitraum.kurz[2], geaendert: (z) => gewaehlt = z));
    await t.tap(find.text('7 T'));
    expect(gewaehlt, Zeitraum.kurz.last);
    await _zeigen(t, ZeitraumWahl(werte: Zeitraum.kalender, gewaehlt: Zeitraum.kalender.first, geaendert: (_) {}));
    expect(find.text('Jahr'), findsOneWidget);
  });
}
