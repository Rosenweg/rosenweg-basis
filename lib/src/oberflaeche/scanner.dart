// SPDX-License-Identifier: GPL-3.0-or-later
/// QR-Codes und Strichcodes lesen — auf jeder Plattform mit dem, was sie
/// kann (Muster aus rosenweg-salz, jetzt fuer alle Apps):
///
/// | Plattform | Kamera | Bild waehlen | Hand-Scanner / Eintippen |
/// |---|---|---|---|
/// | Android, iOS | ja (`mobile_scanner`) | ja | Eintippen |
/// | macOS | ja (`mobile_scanner`, eingebaute/USB-Kamera) | ja | ja |
/// | Linux, Windows | **nein** (kein Plugin) | ja, nur QR (zxing2) | ja |
///
/// Ein USB-Hand-Scanner verhaelt sich wie eine Tastatur (Zeichen, dann
/// Enter): das Eingabefeld hat sofort den Fokus, ein Scan genuegt.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' hide BarcodeFormat;

import '../plattform.dart';
import '../protokoll.dart';
import 'bausteine.dart';
import 'dateien_bausteine.dart';

/// Gibt es auf dieser Plattform eine Kamera zum Scannen?
bool get scannerMitKamera => RosenwegPlattform.istAndroid || RosenwegPlattform.istIos || (!kIsWeb && Platform.isMacOS);

/// Welche Codes gelesen werden.
enum CodeArt {
  /// Nur QR (Anmelde-QR, Raum-QR, Schilder).
  qr,

  /// QR und gaengige Strichcodes (EAN, Code 128/39, ITF).
  alle,
}

/// Code lesen. null = abgebrochen.
///
/// * [titel] oben in der Seite, [hinweis] als Erklaersatz ("Den QR-Code auf
///   dem Schild in den Rahmen halten.").
/// * [pruefen]: eigener Test des gelesenen Werts; liefert einen Satz, wenn
///   er nicht passt (die Kamera liest dann weiter, das Feld zeigt den Satz).
/// * [mindestLaenge]: kuerzere Werte (Lesefehler) werden ignoriert.
Future<String?> codeScannen(
  BuildContext context, {
  String titel = 'Code scannen',
  String? hinweis,
  CodeArt art = CodeArt.qr,
  String? Function(String wert)? pruefen,
  int mindestLaenge = 1,
  bool? kamera,
}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => (kamera ?? scannerMitKamera)
          ? KameraScanner(titel: titel, hinweis: hinweis, art: art, pruefen: pruefen, mindestLaenge: mindestLaenge)
          : CodeEingabe(titel: titel, hinweis: hinweis, pruefen: pruefen, mindestLaenge: mindestLaenge),
    ));

List<BarcodeFormat> _formate(CodeArt a) => a == CodeArt.qr
    ? const [BarcodeFormat.qrCode]
    : const [
        BarcodeFormat.qrCode, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE,
        BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.itf14, BarcodeFormat.dataMatrix,
      ];

/// QR-Code aus einem Bild lesen (reines Dart, alle Plattformen). null =
/// kein QR-Code gefunden.
Future<String?> qrAusBild(Uint8List bytes) => compute(_qrLesen, bytes);

String? _qrLesen(Uint8List bytes) {
  final b = img.decodeImage(bytes);
  if (b == null) return null;
  // Grosse Fotos verkleinern: schneller und oft sogar zuverlaessiger
  final lang = b.width > b.height ? b.width : b.height;
  final o = lang > 1600 ? img.copyResize(b, width: b.width * 1600 ~/ lang) : b;
  final px = o.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr).buffer.asInt32List();
  final quelle = RGBLuminanceSource(o.width, o.height, px);
  for (final binar in [HybridBinarizer(quelle), GlobalHistogramBinarizer(quelle)]) {
    try {
      return QRCodeReader().decode(BinaryBitmap(binar), hints: DecodeHints()..put(DecodeHintType.tryHarder)).text;
    } catch (_) {}
  }
  return null;
}

/// Bild waehlen und den QR-Code darin lesen; Meldung, wenn keiner drin ist.
Future<String?> codeAusBildWaehlen(BuildContext context) async {
  final d = await dateienWaehlen(context, arten: const [DateiArt.bilder]);
  if (d.isEmpty) return null;
  try {
    final w = await qrAusBild(d.first.bytes);
    if (w == null && context.mounted) zeigeMeldung(context, 'In diesem Bild ist kein lesbarer QR-Code.', fehler: true);
    return w;
  } catch (e) {
    Protokoll.schreiben('QR aus Bild', e);
    if (context.mounted) zeigeMeldung(context, 'Das Bild lässt sich nicht lesen.', fehler: true);
    return null;
  }
}

/// Kamera-Seite (Android, iOS, macOS) mit "Eintippen", "Bild wählen", Licht.
class KameraScanner extends StatefulWidget {
  const KameraScanner({super.key, required this.titel, this.hinweis, this.art = CodeArt.qr, this.pruefen, this.mindestLaenge = 1});
  final String titel;
  final String? hinweis;
  final CodeArt art;
  final String? Function(String)? pruefen;
  final int mindestLaenge;

  @override
  State<KameraScanner> createState() => _KameraScannerState();
}

class _KameraScannerState extends State<KameraScanner> {
  late final _steuerung = MobileScannerController(formats: _formate(widget.art));
  bool _fertig = false;
  String? _falsch;

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  void _fertigMit(String w) {
    if (_fertig) return;
    final p = widget.pruefen?.call(w);
    if (p != null) {
      if (p != _falsch) setState(() => _falsch = p);
      return;
    }
    _fertig = true;
    Navigator.of(context).pop(w);
  }

  void _gelesen(BarcodeCapture c) {
    for (final b in c.barcodes) {
      final w = b.rawValue?.trim() ?? '';
      if (w.length >= widget.mindestLaenge) return _fertigMit(w);
    }
  }

  Future<void> _eintippen() async {
    final w = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => CodeEingabe(titel: widget.titel, pruefen: widget.pruefen, mindestLaenge: widget.mindestLaenge, mitBild: false),
    ));
    if (w != null && mounted) _fertigMit(w);
  }

  Future<void> _bild() async {
    final w = await codeAusBildWaehlen(context);
    if (w != null && mounted) _fertigMit(w);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel)),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _steuerung,
              onDetect: _gelesen,
              errorBuilder: (context, fehler) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      fehler.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Die App darf die Kamera nicht benutzen. Bitte in den Einstellungen erlauben – oder den Code eintippen.'
                          : 'Die Kamera lässt sich nicht öffnen. Bitte den Code eintippen oder ein Bild wählen.',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 260,
                  height: widget.art == CodeArt.qr ? 260 : 160,
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            if (widget.hinweis != null || _falsch != null)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Material(
                  color: (_falsch != null ? Theme.of(context).colorScheme.error : Colors.black).withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_falsch ?? widget.hinweis!, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _eintippen, icon: const Icon(Icons.keyboard), label: const Text('Eintippen')),
              OutlinedButton.icon(onPressed: _bild, icon: const Icon(Icons.image_outlined), label: const Text('Bild wählen')),
              IconButton.filledTonal(tooltip: 'Licht', onPressed: () => _steuerung.toggleTorch(), icon: const Icon(Icons.flashlight_on)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Ohne Kamera (Linux, Windows; oder "Eintippen"): Feld fuer Hand-Scanner
/// oder Tastatur, dazu "Bild wählen". Fokus sofort im Feld und nach jedem
/// Fehler wieder dort — ein Scan genuegt, ohne Maus.
class CodeEingabe extends StatefulWidget {
  const CodeEingabe({super.key, required this.titel, this.hinweis, this.pruefen, this.mindestLaenge = 1, this.mitBild = true});
  final String titel;
  final String? hinweis;
  final String? Function(String)? pruefen;
  final int mindestLaenge;
  final bool mitBild;

  @override
  State<CodeEingabe> createState() => _CodeEingabeState();
}

class _CodeEingabeState extends State<CodeEingabe> {
  final _feld = TextEditingController();
  final _fokus = FocusNode();
  String? _fehler;

  @override
  void dispose() {
    _feld.dispose();
    _fokus.dispose();
    super.dispose();
  }

  void _weiter([String? wert]) {
    final w = (wert ?? _feld.text).trim();
    String? f;
    if (w.length < widget.mindestLaenge) {
      f = 'Bitte den ganzen Code scannen oder eintippen.';
    } else {
      f = widget.pruefen?.call(w);
    }
    if (f != null) {
      setState(() => _fehler = f);
      _feld.selection = TextSelection(baseOffset: 0, extentOffset: _feld.text.length);
      _fokus.requestFocus();
      return;
    }
    Navigator.of(context).pop(w);
  }

  Future<void> _bild() async {
    final w = await codeAusBildWaehlen(context);
    if (w != null && mounted) {
      _feld.text = w;
      _weiter(w);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titel)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
            Icon(Icons.qr_code_scanner, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(widget.hinweis ?? 'Den Code mit dem Hand-Scanner lesen oder eintippen.', textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 24),
            TextField(
              key: const Key('code-feld'),
              controller: _feld,
              focusNode: _fokus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 22, letterSpacing: 1.2),
              decoration: InputDecoration(border: const OutlineInputBorder(), errorText: _fehler, errorMaxLines: 3),
              onChanged: (_) {
                if (_fehler != null) setState(() => _fehler = null);
              },
              // Fokus behalten (sonst landete der naechste Scan nirgends)
              onEditingComplete: () {},
              onSubmitted: (_) => _weiter(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('code-weiter'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _weiter,
              child: const Text('Weiter'),
            ),
            if (widget.mitBild) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _bild,
                icon: const Icon(Icons.image_outlined),
                label: const Text('QR-Code aus Bild lesen'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
