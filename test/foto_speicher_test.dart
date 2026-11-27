// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rosenweg_basis/rosenweg_basis.dart';

Uint8List _png(int b, int h) => Uint8List.fromList(img.encodePng(img.Image(width: b, height: h)));

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  test('AppSpeicher: Datei ueberlebt ein neues Oeffnen', () async {
    final ordner = await Directory.systemTemp.createTemp('rw-speicher');
    addTearDown(() => ordner.delete(recursive: true));
    final a = AppSpeicher.inOrdner(ordner);
    await a.schreiben('x', {'a': 1});
    await a.schreiben('y', 'text');
    await a.schreiben('y', null);
    final b = AppSpeicher.inOrdner(ordner);
    expect(await b.lesen('x'), {'a': 1});
    expect(await b.lesen('y'), isNull);
  });

  test('AppSpeicher: kaputte Datei = leer, kein Absturz', () async {
    final ordner = await Directory.systemTemp.createTemp('rw-speicher');
    addTearDown(() => ordner.delete(recursive: true));
    File('${ordner.path}/speicher.json').writeAsStringSync('{kaputt');
    final a = AppSpeicher.inOrdner(ordner);
    expect(await a.lesen('x'), isNull);
    await a.schreiben('x', 2);
    expect(await AppSpeicher.inOrdner(ordner).lesen('x'), 2);
  });

  test('Neuigkeiten: erstes Mal nichts, dann neue und geaenderte', () async {
    final n = Neuigkeiten(AppSpeicher.imSpeicher(), 'meine');
    expect(await n.vergleichen({'1': 'offen', '2': 'offen'}), isEmpty);
    expect(await n.vergleichen({'1': 'erledigt', '2': 'offen', '3': 'offen'}), ['1', '3']);
    expect(await n.vergleichen({'1': 'erledigt', '2': 'offen', '3': 'offen'}), isEmpty);
    // nur vergleichen, nicht merken
    expect(await n.vergleichen({'2': 'abgewiesen'}, merken: false), ['2']);
    expect(await n.vergleichen({'2': 'abgewiesen'}), ['2']);
    await n.vergessen();
    expect(await n.vergleichen({'9': 'offen'}), isEmpty);
  });

  testWidgets('BeimOeffnen: beim Start und nach Rueckkehr, nicht im Sturm', (t) async {
    var n = 0;
    await t.pumpWidget(BeimOeffnen(mindestAbstand: Duration.zero, pruefen: () async => n++, child: const SizedBox()));
    await t.pump();
    expect(n, 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(n, 2);

    // mit Mindestabstand: sofortige Rueckkehr zaehlt nicht
    var m = 0;
    await t.pumpWidget(BeimOeffnen(key: UniqueKey(), pruefen: () async => m++, child: const SizedBox()));
    await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(m, 1);
  });

  testWidgets('FotoFeld: Pflicht, Vorschau, Entfernen', (t) async {
    DateiDaten? foto;
    final form = GlobalKey<FormState>();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: FotoFeld(pflicht: true, wert: foto, geaendert: (f) => setState(() => foto = f)),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await t.pump();
    expect(find.text('Bitte ein Foto hinzufügen.'), findsOneWidget);
    // Telefon: Kamera und Galerie; Computer: Bild waehlen
    expect(find.text(kameraFuerFotos ? 'Foto aufnehmen' : 'Bild wählen'), findsOneWidget);
    expect(find.text('Aus Galerie'), kameraFuerFotos ? findsOneWidget : findsNothing);
  });

  testWidgets('FotoFeld mit Wert: Vorschau, Groesse, Entfernen leert', (t) async {
    DateiDaten? foto = DateiDaten(name: 'a.png', bytes: _png(40, 30));
    DateiDaten? gemeldet = foto;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FotoFeld(wert: foto, geaendert: (f) => setState(() => gemeldet = foto = f)),
          ),
        ),
      ),
    );
    expect(find.text('Entfernen'), findsOneWidget);
    expect(find.text(kameraFuerFotos ? 'Neu aufnehmen' : 'Anderes Bild'), findsOneWidget);
    await t.tap(find.text('Entfernen'));
    await t.pump();
    expect(gemeldet, isNull);
  });

  testWidgets('GeladenesBild: Fehler mit Nochmals, danach Bild', (t) async {
    var versuch = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GeladenesBild(
            laden: () async {
              versuch++;
              if (versuch == 1) throw ServerNichtErreichbar();
              return DateiDaten(name: 'f.png', bytes: _png(20, 20));
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Nochmals'), findsOneWidget);
    await t.tap(find.text('Nochmals'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });
}
