// SPDX-License-Identifier: GPL-3.0-or-later
/// Fotos in Formularen und Bilder von der API zeigen – auf allen fuenf
/// Plattformen mit derselben Bedienung:
///
/// | | Foto holen | Vorschau | Gross ansehen |
/// |---|---|---|---|
/// | Android, iOS | "Foto aufnehmen" (Kamera), "Aus Galerie" | ja | Antippen, Zoomen mit zwei Fingern |
/// | Linux, macOS, Windows | "Bild wählen" oder Bild hineinziehen | ja | Anklicken, Zoomen mit Mausrad |
///
/// Jedes Foto wird vor dem Hochladen verkleinert ([bildVerkleinern]): eine
/// Handy-Aufnahme mit 4–12 MB wird so zu 200–500 KB.
library;

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../netz/dateien.dart';
import '../plattform.dart';
import '../protokoll.dart';
import 'bausteine.dart';
import 'dateien_bausteine.dart';
import 'formular.dart';

/// Foto als Formularfeld: holen, Vorschau, ersetzen, entfernen.
///
/// ```dart
/// FotoFeld(titel: 'Foto', wert: foto, geaendert: (f) => setState(() => foto = f))
/// ```
class FotoFeld extends FormField<DateiDaten> {
  FotoFeld({
    super.key,
    String? name,
    String titel = 'Foto',
    DateiDaten? wert,
    required ValueChanged<DateiDaten?> geaendert,
    bool pflicht = false,
    String? hinweis,
    int maxKante = 1600,
    int qualitaet = 75,
  }) : super(
         initialValue: wert,
         validator: (v) => pflicht && v == null ? 'Bitte ein Foto hinzufügen.' : null,
         builder: (feld) => _FotoFeldInhalt(
           feld: feld,
           name: name,
           titel: pflicht ? '$titel *' : titel,
           hinweis: hinweis,
           geaendert: geaendert,
           maxKante: maxKante,
           qualitaet: qualitaet,
         ),
       );
}

class _FotoFeldInhalt extends StatefulWidget {
  const _FotoFeldInhalt({
    required this.feld,
    required this.name,
    required this.titel,
    required this.hinweis,
    required this.geaendert,
    required this.maxKante,
    required this.qualitaet,
  });
  final FormFieldState<DateiDaten> feld;
  final String? name;
  final String titel;
  final String? hinweis;
  final ValueChanged<DateiDaten?> geaendert;
  final int maxKante;
  final int qualitaet;

  @override
  State<_FotoFeldInhalt> createState() => _FotoFeldInhaltState();
}

class _FotoFeldInhaltState extends State<_FotoFeldInhalt> {
  bool _drueber = false;
  bool _arbeitet = false;

  void _setzen(DateiDaten? d) {
    widget.feld.didChange(d);
    formularSteuerungVon(context)?.markieren(widget.name);
    widget.geaendert(d);
  }

  Future<void> _holen({bool galerie = false}) async {
    setState(() => _arbeitet = true);
    try {
      final d = await fotoAufnehmen(
        context,
        maxKante: widget.maxKante,
        qualitaet: widget.qualitaet,
        ausGalerie: galerie,
      );
      if (d != null && mounted) _setzen(d);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _abgelegt(DropDoneDetails details) async {
    setState(() => _drueber = false);
    final f = details.files
        .where((x) => DateiArt.bilder.endungen.contains(x.name.split('.').last.toLowerCase()))
        .firstOrNull;
    if (f == null) {
      zeigeMeldung(context, 'Bitte ein Bild (JPG, PNG, WebP, HEIC) hineinziehen.', fehler: true);
      return;
    }
    setState(() => _arbeitet = true);
    try {
      final roh = DateiDaten(name: f.name, bytes: await f.readAsBytes());
      final d = await bildVerkleinern(roh, maxKante: widget.maxKante, qualitaet: widget.qualitaet);
      if (mounted) _setzen(d);
    } catch (e) {
      Protokoll.schreiben('Foto ablegen', e);
      if (mounted) zeigeMeldung(context, 'Das Bild lässt sich nicht lesen.', fehler: true);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final s = formularSteuerungVon(context);
    final aus = _arbeitet || (s?.speichert ?? false);
    final wert = widget.feld.value;
    final telefon = kameraFuerFotos;
    final knoepfe = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (telefon) ...[
          FilledButton.tonalIcon(
            onPressed: aus ? null : () => _holen(),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(wert == null ? 'Foto aufnehmen' : 'Neu aufnehmen'),
          ),
          OutlinedButton.icon(
            onPressed: aus ? null : () => _holen(galerie: true),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Aus Galerie'),
          ),
        ] else
          FilledButton.tonalIcon(
            onPressed: aus ? null : () => _holen(),
            icon: const Icon(Icons.image_outlined),
            label: Text(wert == null ? 'Bild wählen' : 'Anderes Bild'),
          ),
        if (wert != null)
          TextButton.icon(
            onPressed: aus ? null : () => _setzen(null),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Entfernen'),
          ),
      ],
    );
    final inhalt = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.titel, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (wert != null) ...[
          GestureDetector(
            onTap: () => bildZeigen(context, wert.bytes, titel: widget.titel.replaceAll(' *', '')),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                wert.bytes,
                height: 180,
                fit: BoxFit.cover,
                semanticLabel: 'Vorschau des Fotos',
                errorBuilder: (_, _, _) => _KeineVorschau(datei: wert),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(groesseText(wert.groesse), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
        ] else if (!telefon) ...[
          Text('Bild hierher ziehen oder', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
        if (_arbeitet) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
        knoepfe,
        if (widget.feld.errorText != null || s?.feldFehlerVon(widget.name) != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.feld.errorText ?? s!.feldFehlerVon(widget.name)!, style: TextStyle(color: f.error)),
          )
        else if (widget.hinweis != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.hinweis!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
    final rahmen = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _drueber ? f.primaryContainer : null,
        border: Border.all(color: _drueber ? f.primary : f.outlineVariant, width: _drueber ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: inhalt,
    );
    if (!RosenwegPlattform.istDesktop) return rahmen;
    return DropTarget(
      enable: !aus,
      onDragEntered: (_) => setState(() => _drueber = true),
      onDragExited: (_) => setState(() => _drueber = false),
      onDragDone: _abgelegt,
      child: rahmen,
    );
  }
}

class _KeineVorschau extends StatelessWidget {
  const _KeineVorschau({required this.datei});
  final DateiDaten datei;
  @override
  Widget build(BuildContext context) => Container(
    height: 80,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.image_not_supported_outlined),
        const SizedBox(width: 8),
        Flexible(child: Text('${datei.name} (keine Vorschau)')),
      ],
    ),
  );
}

/// Bild gross zeigen (Vollbild, zoomen, Escape/Zurueck schliesst).
Future<void> bildZeigen(BuildContext context, Uint8List bytes, {String titel = 'Foto'}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(titel), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.memory(bytes, semanticLabel: titel)),
      ),
    ),
  ),
);

/// Bild von der API (mit Anmeldung) laden und zeigen; Antippen = gross.
///
/// ```dart
/// GeladenesBild(laden: () => sitzung.dateien.herunterladen('/api/reklamationen/7/foto'))
/// ```
///
/// Laedt einmal je Widget; Fehler zeigt es als kurzen Satz statt des Bildes
/// (z. B. auf geteilten Telefonen, wo Dateien noch nicht gehen).
class GeladenesBild extends StatefulWidget {
  const GeladenesBild({super.key, required this.laden, this.hoehe = 200, this.titel = 'Foto'});
  final Future<DateiDaten> Function() laden;
  final double hoehe;
  final String titel;

  @override
  State<GeladenesBild> createState() => _GeladenesBildState();
}

class _GeladenesBildState extends State<GeladenesBild> {
  late Future<DateiDaten> _f = widget.laden();

  @override
  Widget build(BuildContext context) => FutureBuilder<DateiDaten>(
    future: _f,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) {
        return SizedBox(
          height: widget.hoehe,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      final d = s.data;
      if (d == null || !d.typ.startsWith('image/')) {
        return Row(
          children: [
            const Icon(Icons.broken_image_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(s.hasError ? fehlerText(s.error!) : 'Foto lässt sich nicht anzeigen.')),
            TextButton(
              onPressed: () => setState(() {
                _f = widget.laden();
              }),
              child: const Text('Nochmals'),
            ),
          ],
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => bildZeigen(context, d.bytes, titel: widget.titel),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              d.bytes,
              height: widget.hoehe,
              fit: BoxFit.contain,
              semanticLabel: widget.titel,
              errorBuilder: (_, _, _) => const Text('Foto lässt sich nicht anzeigen.'),
            ),
          ),
        ),
      );
    },
  );
}
