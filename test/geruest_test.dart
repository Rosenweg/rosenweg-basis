// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

Future<void> zeigen(WidgetTester t, Size groesse, Widget w) async {
  t.view.physicalSize = groesse;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: rosenwegThema(Brightness.light), home: w));
  await t.pumpAndSettle();
}

const ziele = [
  GeruestZiel(titel: 'Lager', symbol: Icons.inventory_2_outlined, seite: _seite1),
  GeruestZiel(titel: 'Buchungen', symbol: Icons.list_alt, seite: _seite2),
];
Widget _seite1(BuildContext _) => const Text('SEITE 1');
Widget _seite2(BuildContext _) => const Text('SEITE 2');

void main() {
  test('Fensterklassen nach Breite', () {
    expect(Fensterklasse.ausBreite(400), Fensterklasse.kompakt);
    expect(Fensterklasse.ausBreite(600), Fensterklasse.mittel);
    expect(Fensterklasse.ausBreite(839), Fensterklasse.mittel);
    expect(Fensterklasse.ausBreite(840), Fensterklasse.breit);
    expect(Fensterklasse.ausBreite(1920), Fensterklasse.sehrBreit);
    expect(Fensterklasse.mittel.istBreit, isFalse);
    expect(Fensterklasse.breit.istBreit, isTrue);
  });

  testWidgets('Handy: Navigation unten, Wechsel per Tipp', (t) async {
    await zeigen(t, const Size(400, 800), const RosenwegGeruest(titel: Text('App'), ziele: ziele));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('SEITE 1'), findsOneWidget);
    await t.tap(find.text('Buchungen'));
    await t.pumpAndSettle();
    expect(find.text('SEITE 2'), findsOneWidget);
  });

  testWidgets('Desktop: Seitenleiste links, ab 1200 px mit Beschriftung', (t) async {
    await zeigen(t, const Size(1000, 700), const RosenwegGeruest(titel: Text('App'), ziele: ziele));
    expect(find.byType(NavigationBar), findsNothing);
    expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
    await t.tap(find.text('Buchungen'));
    await t.pumpAndSettle();
    expect(find.text('SEITE 2'), findsOneWidget);

    await zeigen(t, const Size(1920, 1080), const RosenwegGeruest(titel: Text('App'), ziele: ziele));
    expect(t.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
  });

  testWidgets('eine Seite: keine Navigation, Inhalt am Desktop hoechstens 760 px breit', (t) async {
    const k = Key('inhalt');
    await zeigen(t, const Size(1920, 1080),
        const RosenwegGeruest(titel: Text('App'), inhalt: SizedBox.expand(key: k)));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(t.getSize(find.byKey(k)).width, RosenwegInhalt.standardBreite);

    await zeigen(t, const Size(400, 800), const RosenwegGeruest(titel: Text('App'), inhalt: SizedBox.expand(key: k)));
    expect(t.getSize(find.byKey(k)).width, 400);
  });

  testWidgets('Spalten nur ab 840 px, sonst das Handy-Layout', (t) async {
    const w = RosenwegSpalten(links: Text('LINKS'), rechts: Text('RECHTS'), schmal: Text('SCHMAL'));
    await zeigen(t, const Size(1280, 800), const Scaffold(body: w));
    expect(find.text('LINKS'), findsOneWidget);
    expect(find.text('RECHTS'), findsOneWidget);
    expect(find.text('SCHMAL'), findsNothing);
    await zeigen(t, const Size(800, 800), const Scaffold(body: w));
    expect(find.text('SCHMAL'), findsOneWidget);
    expect(find.text('LINKS'), findsNothing);
  });

  testWidgets('Dialoge am Desktop hoechstens 560 px breit', (t) async {
    await zeigen(t, const Size(1920, 1080), const Scaffold(body: SizedBox()));
    showDialog<void>(
      context: t.element(find.byType(Scaffold)),
      builder: (_) => AlertDialog(title: const Text('Titel'), content: Text('lang ' * 400)),
    );
    await t.pumpAndSettle();
    final karte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first;
    expect(t.getSize(karte).width, 560);
  });
}
