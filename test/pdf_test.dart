// SPDX-License-Identifier: GPL-3.0-or-later
// Das Zeichnen selbst (PDFium) laeuft nicht im Testlauf ohne Geraet; geprueft
// werden Laden, Fehler und Knoepfe. Echtes Anzeigen: example/ auf jeder
// Plattform (CI baut es).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  testWidgets('Laden fehlgeschlagen: Satz und Nochmals, zweiter Versuch laedt neu', (t) async {
    var n = 0;
    await t.pumpWidget(MaterialApp(
      home: PdfSeite(
        titel: 'Vollmacht',
        laden: () async {
          n++;
          throw KeineBerechtigung('Keine Berechtigung');
        },
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Vollmacht'), findsOneWidget);
    expect(find.text('Keine Berechtigung'), findsOneWidget);
    // Ohne Datei keine Knoepfe zum Speichern/Teilen
    expect(find.byTooltip('Speichern'), findsNothing);
    await t.tap(find.text('Nochmals'));
    await t.pumpAndSettle();
    expect(n, 2);
  });

  testWidgets('waehrend des Ladens: Hinweis', (t) async {
    await t.pumpWidget(MaterialApp(home: PdfSeite(titel: 'X', laden: () => Future<DateiDaten>.delayed(const Duration(seconds: 1), () => throw ServerNichtErreichbar()))));
    await t.pump();
    expect(find.text('PDF wird geladen …'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.textContaining('nicht erreichbar'), findsOneWidget);
  });
}
