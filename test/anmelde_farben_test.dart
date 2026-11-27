// SPDX-License-Identifier: GPL-3.0-or-later
//
// Anmeldeschirm in der Gruppenfarbe der App (Stefan 27.11.2026).
//
// Bildschirmfotos (rot, blau, gruen) in einen Ordner schreiben:
//   RW_BILDER=~/Downloads flutter test test/anmelde_farben_test.dart
// Schrift dafuer: RW_SCHRIFT=<ttf> (Standard Arial von macOS; sonst Ahem-Kaestchen).
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

RosenwegApp appMit(RosenwegGruppe? g) => RosenwegApp(
      kennung: 'ch.rosenweg4303.test',
      name: 'Rosenweg Salz',
      ordner: 'rosenweg-test',
      beschreibung: 'Eine Test-App.',
      gruppe: g,
    );

class _IosLeser implements Kartenleser {
  @override
  bool get aufKnopfdruck => true;
  @override
  Future<bool> verfuegbar() async => true;
  @override
  Stream<String> lauschen() => const Stream.empty();
  @override
  Future<String?> einmalLesen() async => null;
}

double _kanal(double c) => c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
double _leucht(Color f) => 0.2126 * _kanal(f.r) + 0.7152 * _kanal(f.g) + 0.0722 * _kanal(f.b);
double kontrast(Color a, Color b) {
  final x = _leucht(a), y = _leucht(b);
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Protokoll.nurKonsole = true);
  tearDown(() => RosenwegPlattform.plattformFuerTests = null);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Gruppe -> Farben wie das Logo; ohne Angabe blau', () {
    expect(AnmeldeFarben.fuer(RosenwegGruppe.bewohner).grund, const Color(0xFFD62828));
    expect(AnmeldeFarben.fuer(RosenwegGruppe.verwaltung).grund, const Color(0xFF1E3A8A));
    expect(AnmeldeFarben.fuer(RosenwegGruppe.technik).grund, const Color(0xFF2E6B4F));
    expect(AnmeldeFarben.fuer(null), same(AnmeldePalette.blau));
    expect(AnmeldePalette.blau.grund, AnmeldeFarben.blau);
    expect(RosenwegGruppe.ausName(' Technik '), RosenwegGruppe.technik);
    expect(RosenwegGruppe.ausName('ausschuss'), isNull);
  });

  test('lesbar nach WCAG AA (mindestens 4.5:1)', () {
    for (final p in [AnmeldePalette.blau, AnmeldePalette.rot, AnmeldePalette.gruen]) {
      for (final f in [Colors.white, p.hell, p.fehler, p.ok, p.warnung]) {
        expect(kontrast(f, p.grund), greaterThanOrEqualTo(4.5), reason: '$f auf ${p.grund}');
      }
      for (final k in [p.knopf, p.knopfDunkel]) {
        expect(kontrast(Colors.white, k), greaterThanOrEqualTo(4.5), reason: 'weiss auf $k');
      }
    }
  });

  test('Android: Gruppe geht an den nativen Schirm (Argument "gruppe")', () async {
    const kanal = MethodChannel('rosenweg_basis_test');
    final aufrufe = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kanal, (c) async {
      aufrufe.add(c);
      return c.method == 'anmeldeSchirm' ? false : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kanal, null));
    await AndroidKontoKanal(kanal: kanal, gruppe: RosenwegGruppe.bewohner).anmeldeSchirm();
    await AndroidKontoKanal(kanal: kanal).anmeldeSchirm();
    expect(aufrufe[0].arguments, {'gruppe': 'bewohner'});
    expect(aufrufe[1].arguments, anyOf(isNull, isEmpty));
  });

  final bilder = Platform.environment['RW_BILDER'];
  for (final (gruppe, datei) in [
    (RosenwegGruppe.bewohner, 'rot'),
    (null, 'blau'),
    (RosenwegGruppe.technik, 'gruen'),
  ]) {
    testWidgets('Schirm in ${gruppe?.name ?? 'Standard'}: Grund und Knoepfe', (t) async {
      RosenwegPlattform.plattformFuerTests = TargetPlatform.iOS;
      if (bilder != null) {
        final schrift = Platform.environment['RW_SCHRIFT'] ?? '/System/Library/Fonts/Supplemental/Arial.ttf';
        final fett = schrift.replaceFirst('Arial.ttf', 'Arial Bold.ttf');
        await t.runAsync(() async {
          for (final familie in ['Arial']) {
            final l = FontLoader(familie)..addFont(File(schrift).readAsBytes().then(ByteData.sublistView));
            if (File(fett).existsSync()) l.addFont(File(fett).readAsBytes().then(ByteData.sublistView));
            await l.load();
          }
        });
      }
      t.view.physicalSize = const Size(412 * 2.5, 892 * 2.5);
      t.view.devicePixelRatio = 2.5;
      addTearDown(t.view.reset);
      final a = appMit(gruppe);
      final speicher = Schluesselbund(a.ordner);
      final s = RosenwegSitzung(a,
          speicher: speicher,
          konto: RosenwegKonto(a, speicher: speicher, still: () => null),
          karte: KartenSitzung(a,
              speicher: speicher, client: MockClient((_) async => http.Response('{}', 404)), kennung: () async => 'a' * 64),
          geraetDa: () async => false);
      final schluessel = GlobalKey();
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: bilder != null ? 'Arial' : null),
        home: Scaffold(body: RepaintBoundary(key: schluessel, child: RosenwegAnmeldeSchirm(sitzung: s, leser: _IosLeser(), qrScannerDa: true))),
      ));
      for (var i = 0; i < 5; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }

      final p = AnmeldeFarben.fuer(gruppe);
      final grund = t.widget<ColoredBox>(find.descendant(of: find.byType(RosenwegAnmeldeSchirm), matching: find.byType(ColoredBox)).first);
      expect(grund.color, p.grund);
      Color knopf(String text) =>
          t.widget<FilledButton>(find.ancestor(of: find.text(text), matching: find.byType(FilledButton))).style!.backgroundColor!.resolve({})!;
      expect(knopf('Mit Rosenweg-Konto anmelden'), p.knopf);
      expect(knopf('QR-Code scannen'), p.knopfDunkel);
      expect(knopf('Rosenweg-Karte lesen'), p.knopfDunkel);
      final kopf = t.widget<Text>(find.text('Rosenweg Salz · zum Benutzen anmelden'));
      expect(kopf.style!.color, p.hell);

      if (bilder != null) {
        // Siegel (Bild-Asset) wirklich dekodieren lassen
        await t.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
        await t.pump();
        final bild = await t.runAsync(() async {
          final r = schluessel.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final i = await r.toImage(pixelRatio: 2.5);
          return (await i.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        });
        File('$bilder/anmeldeschirm-$datei.png').writeAsBytesSync(bild!);
      }
    });
  }
}
