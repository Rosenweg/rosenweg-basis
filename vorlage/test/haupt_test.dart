// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_vorlage/app.dart';
import 'package:rosenweg_vorlage/attrappe.dart';
import 'package:rosenweg_vorlage/seiten/haupt.dart';

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  Future<Attrappe> zeigen(WidgetTester t, Size groesse) async {
    t.view.physicalSize = groesse;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = Attrappe();
    final s = RosenwegSitzung(appAngaben, transport: a);
    await s.starten();
    await t.pumpWidget(RosenwegRahmen(sitzung: s, inhalt: (_) => Haupt(sitzung: s)));
    await t.pumpAndSettle();
    return a;
  }

  testWidgets('Handy: Navigation unten, Konto laedt /api/auth/me', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.textContaining('Willkommen'), findsOneWidget);
    await t.tap(find.text('Mein Konto'));
    await t.pumpAndSettle();
    expect(find.text('erika.muster@example.org'), findsOneWidget);
    expect(a.anfragen.any((r) => r.pfad == '/api/auth/me'), isTrue);
  });

  testWidgets('Desktop (Station): Leiste links', (t) async {
    await zeigen(t, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Fehler zeigt Nochmals und laedt neu', (t) async {
    final a = await zeigen(t, const Size(412, 860));
    a.erzwungen['GET /api/auth/me'] = (status: 503, json: {'error': 'Wartung'});
    await t.tap(find.text('Mein Konto'));
    await t.pumpAndSettle();
    expect(find.text('Nochmals'), findsOneWidget);
    await t.tap(find.text('Nochmals'));
    await t.pumpAndSettle();
    expect(find.text('erika.muster@example.org'), findsOneWidget);
  });

  test('Kennung, Ordner und Logo passen zusammen', () {
    expect(appAngaben.kennung, matches(RegExp(r'^ch\.rosenweg4303\.[a-z][a-z0-9]*$')));
    expect(appAngaben.ordner, startsWith('rosenweg-'));
    expect(File('assets/logo/${appAngaben.ordner}-512.png').existsSync(), isTrue);
    expect(File('assets/logo/${appAngaben.ordner}-klein.png').existsSync(), isTrue);
  });
}
