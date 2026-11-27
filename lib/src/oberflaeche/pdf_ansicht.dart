// SPDX-License-Identifier: GPL-3.0-or-later
/// PDF anzeigen auf allen fuenf Plattformen (pdfrx, PDFium), geladen mit dem
/// Token der Anmeldung ([RosenwegDateien.herunterladen]).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../netz/dateien.dart';
import 'bausteine.dart';
import 'dateien_bausteine.dart';

/// PDF als ganze Seite oeffnen (AppBar mit Seitenzahl, Zoom, Speichern,
/// Teilen).
///
/// ```dart
/// pdfOeffnen(context, titel: 'Vollmacht', laden: () => sitzung.dateien.herunterladen('/api/vollmachten/7/pdf'));
/// ```
Future<void> pdfOeffnen(BuildContext context, {required String titel, required Future<DateiDaten> Function() laden}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfSeite(titel: titel, laden: laden)));

/// Seite mit [PdfAnsicht] und Knoepfen in der AppBar.
class PdfSeite extends StatefulWidget {
  const PdfSeite({super.key, required this.titel, required this.laden});
  final String titel;
  final Future<DateiDaten> Function() laden;

  @override
  State<PdfSeite> createState() => _PdfSeiteState();
}

class _PdfSeiteState extends State<PdfSeite> {
  final _ansicht = GlobalKey<PdfAnsichtState>();
  DateiDaten? _datei;

  @override
  Widget build(BuildContext context) {
    final d = _datei;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titel),
        actions: [
          if (d != null) ...[
            IconButton(tooltip: 'Verkleinern', onPressed: () => _ansicht.currentState?.verkleinern(), icon: const Icon(Icons.zoom_out)),
            IconButton(tooltip: 'Vergrössern', onPressed: () => _ansicht.currentState?.vergroessern(), icon: const Icon(Icons.zoom_in)),
            Builder(
              builder: (c) => IconButton(
                tooltip: 'Speichern',
                onPressed: () => dateiSpeichern(c, d),
                icon: const Icon(Icons.download),
              ),
            ),
            Builder(
              builder: (c) => IconButton(tooltip: 'Teilen', onPressed: () => dateiTeilen(c, d), icon: const Icon(Icons.share)),
            ),
          ],
        ],
      ),
      body: PdfAnsicht(key: _ansicht, laden: widget.laden, geladen: (d) => setState(() => _datei = d)),
    );
  }
}

/// PDF im Layout einer Seite. Laedt mit [laden] (zeigt Fortschritt und
/// Fehler mit "Nochmals"), dann Blaettern per Wischen/Rad, Zoom mit zwei
/// Fingern bzw. Strg+Rad, unten "Seite 2 von 5" mit Vor/Zurueck.
/// Tastatur: Bild auf/ab, Pfeile, Pos1/Ende, Strg+Plus/Minus.
class PdfAnsicht extends StatefulWidget {
  const PdfAnsicht({super.key, this.laden, this.daten, this.name = 'dokument.pdf', this.geladen})
      : assert(laden != null || daten != null, 'laden oder daten angeben');

  final Future<DateiDaten> Function()? laden;

  /// Schon geladene Bytes (statt [laden]).
  final Uint8List? daten;
  final String name;
  final ValueChanged<DateiDaten>? geladen;

  @override
  State<PdfAnsicht> createState() => PdfAnsichtState();
}

class PdfAnsichtState extends State<PdfAnsicht> {
  final _steuerung = PdfViewerController();
  DateiDaten? _datei;
  Object? _fehler;
  int? _seite;
  int? _seiten;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() {
      _fehler = null;
      _datei = null;
    });
    try {
      final d = widget.daten != null ? DateiDaten(name: widget.name, bytes: widget.daten!, typ: 'application/pdf') : await widget.laden!();
      if (!mounted) return;
      setState(() => _datei = d);
      widget.geladen?.call(d);
    } catch (e) {
      if (mounted) setState(() => _fehler = e);
    }
  }

  void vergroessern() {
    if (_steuerung.isReady) _steuerung.zoomUp();
  }

  void verkleinern() {
    if (_steuerung.isReady) _steuerung.zoomDown();
  }

  void _gehe(int seite) {
    final n = _seiten;
    if (!_steuerung.isReady || n == null) return;
    _steuerung.goToPage(pageNumber: seite.clamp(1, n));
  }

  @override
  Widget build(BuildContext context) {
    final f = _fehler;
    if (f != null) return FehlerAnzeige(text: fehlerText(f), nochmals: _laden);
    final d = _datei;
    if (d == null) return const LadeAnzeige(text: 'PDF wird geladen …');
    final s = _seite ?? 1;
    final n = _seiten;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _gehe(s + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _gehe(s - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _gehe(1),
        const SingleActivator(LogicalKeyboardKey.end): () => _gehe(n ?? 1),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): vergroessern,
        const SingleActivator(LogicalKeyboardKey.add, control: true): vergroessern,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): verkleinern,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): vergroessern,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): verkleinern,
      },
      child: Focus(
        autofocus: true,
        child: Column(children: [
          Expanded(
            child: PdfViewer.data(
              d.bytes,
              sourceName: d.name,
              controller: _steuerung,
              params: PdfViewerParams(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                onViewerReady: (doc, c) => setState(() {
                  _seiten = doc.pages.length;
                  _seite = c.pageNumber ?? 1;
                }),
                onPageChanged: (p) {
                  if (p != null && p != _seite) setState(() => _seite = p);
                },
                errorBannerBuilder: (context, fehler, _, _) =>
                    FehlerAnzeige(titel: 'PDF lässt sich nicht anzeigen', text: 'Die Datei ist beschädigt oder kein PDF.'),
              ),
            ),
          ),
          if (n != null && n > 1)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(tooltip: 'Vorherige Seite', onPressed: s > 1 ? () => _gehe(s - 1) : null, icon: const Icon(Icons.chevron_left)),
                  Text('Seite $s von $n'),
                  IconButton(tooltip: 'Nächste Seite', onPressed: s < n ? () => _gehe(s + 1) : null, icon: const Icon(Icons.chevron_right)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
