// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:zxing2/qrcode.dart' show Encoder, ErrorCorrectionLevel;

/// QR-Code als PNG (weiss, mit Ruhezone), wie ein Bildschirmfoto davon.
Uint8List _qrBild(String text, {int massstab = 6}) {
  final m = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  const rand = 4;
  final b = img.Image(width: (m.width + 2 * rand) * massstab, height: (m.height + 2 * rand) * massstab);
  img.fill(b, color: img.ColorRgb8(255, 255, 255));
  for (var x = 0; x < m.width; x++) {
    for (var y = 0; y < m.height; y++) {
      if (m.get(x, y) == 1) {
        img.fillRect(b,
            x1: (x + rand) * massstab,
            y1: (y + rand) * massstab,
            x2: (x + rand + 1) * massstab - 1,
            y2: (y + rand + 1) * massstab - 1,
            color: img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return img.encodePng(b);
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  test('QR-Code aus einem Bild lesen (Linux/Windows ohne Kamera)', () async {
    expect(await qrAusBild(_qrBild('https://rosenweg4303.ch/raum/R9-UG-03')), 'https://rosenweg4303.ch/raum/R9-UG-03');
    // grosses Foto: wird vor dem Lesen verkleinert
    expect(await qrAusBild(_qrBild('rw-anmeldung:abc123', massstab: 60)), 'rw-anmeldung:abc123');
  });

  test('kein QR-Code oder kein Bild: null', () async {
    final leer = img.Image(width: 200, height: 200);
    img.fill(leer, color: img.ColorRgb8(255, 255, 255));
    expect(await qrAusBild(img.encodePng(leer)), isNull);
    expect(await qrAusBild(Uint8List.fromList([1, 2, 3])), isNull);
  });

  testWidgets('ohne Kamera: Eingabe wie USB-Scanner (Text + Enter), mit Pruefung', (t) async {
    String? gelesen;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => FilledButton(
          onPressed: () async => gelesen = await codeScannen(c,
              kamera: false,
              titel: 'Raum-QR',
              mindestLaenge: 4,
              pruefen: (w) => w.startsWith('R') ? null : 'Das ist kein Raum-Code.'),
          child: const Text('Scannen'),
        ),
      ),
    ));
    await t.tap(find.text('Scannen'));
    await t.pumpAndSettle();
    expect(find.text('Raum-QR'), findsOneWidget);
    expect(find.text('QR-Code aus Bild lesen'), findsOneWidget);
    // Feld hat sofort den Fokus: direkt "scannen"
    await t.enterText(find.byKey(const Key('code-feld')), 'ab');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.text('Bitte den ganzen Code scannen oder eintippen.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('code-feld')), 'X-12345');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.text('Das ist kein Raum-Code.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('code-feld')), 'R9-UG-03');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(gelesen, 'R9-UG-03');
  });

  test('Kamera nur auf Android, iOS, macOS', () {
    // Testlauf auf Linux/macOS-Host: Wert passt zur Host-Plattform; hier nur,
    // dass der Getter ohne Plugin funktioniert.
    expect(scannerMitKamera, isA<bool>());
  });
}
