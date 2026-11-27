// SPDX-License-Identifier: GPL-3.0-or-later
/// Dateien waehlen, fotografieren, verkleinern, speichern und teilen — auf
/// allen fuenf Plattformen mit derselben Bedienung.
///
/// | | Waehlen | Foto | Speichern | Teilen | Oeffnen |
/// |---|---|---|---|---|---|
/// | Linux | GTK-Dialog | Bild waehlen | "Speichern unter" | – (Speichern) | Standard-App (xdg-open) |
/// | Windows | Explorer-Dialog | Bild waehlen | "Speichern unter" | Windows-Teilen | Standard-App |
/// | macOS | Finder-Dialog | Bild waehlen | "Speichern unter" | Teilen-Menue | Standard-App |
/// | Android | Dateiauswahl des Systems | Kamera | – (Teilen) | Teilen | passende App (sonst Teilen) |
/// | iOS | Dateien-App | Kamera | – (Teilen → "In Dateien sichern") | Teilen | – (Teilen) |
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../netz/dateien.dart';
import '../plattform.dart';
import '../protokoll.dart';
import 'bausteine.dart';

/// Welche Dateien gewaehlt werden duerfen.
class DateiArt {
  const DateiArt(this.titel, {this.endungen = const [], this.mimeTypen = const [], this.appleTypen = const []});
  final String titel;
  final List<String> endungen;
  final List<String> mimeTypen;

  /// Uniform Type Identifiers (macOS/iOS), z. B. `com.adobe.pdf`.
  final List<String> appleTypen;

  static const pdf = DateiArt('PDF', endungen: ['pdf'], mimeTypen: ['application/pdf'], appleTypen: ['com.adobe.pdf']);
  static const bilder = DateiArt('Bilder',
      endungen: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      mimeTypen: ['image/jpeg', 'image/png', 'image/webp', 'image/heic'],
      appleTypen: ['public.image']);
  static const dokumente = DateiArt('Dokumente',
      endungen: ['pdf', 'jpg', 'jpeg', 'png', 'docx', 'xlsx', 'odt', 'ods', 'txt'],
      appleTypen: ['com.adobe.pdf', 'public.image', 'public.content', 'public.text']);

  XTypeGroup get _gruppe => XTypeGroup(
        label: titel,
        extensions: endungen.isEmpty ? null : endungen,
        mimeTypes: mimeTypen.isEmpty ? null : mimeTypen,
        uniformTypeIdentifiers: appleTypen.isEmpty ? null : appleTypen,
      );
}

Future<DateiDaten> _lesen(XFile f) async =>
    DateiDaten(name: f.name, bytes: await f.readAsBytes(), typ: f.mimeType == null || f.mimeType!.isEmpty ? null : f.mimeType);

/// Datei(en) mit dem Dialog des Systems waehlen. Leer = abgebrochen.
/// [hoechstens] Bytes je Datei (sonst Meldung, Datei bleibt weg).
Future<List<DateiDaten>> dateienWaehlen(
  BuildContext context, {
  List<DateiArt> arten = const [],
  bool mehrere = false,
  int? hoechstens,
  String? titel,
}) async {
  final gruppen = [for (final a in arten) a._gruppe];
  final List<XFile> roh;
  try {
    if (mehrere) {
      roh = await openFiles(acceptedTypeGroups: gruppen, confirmButtonText: 'Wählen');
    } else {
      final f = await openFile(acceptedTypeGroups: gruppen, confirmButtonText: 'Wählen');
      roh = f == null ? const [] : [f];
    }
  } catch (e) {
    Protokoll.schreiben('Dateiauswahl', e);
    if (context.mounted) zeigeMeldung(context, 'Die Dateiauswahl lässt sich nicht öffnen.', fehler: true);
    return const [];
  }
  final d = [for (final f in roh) await _lesen(f)];
  if (!context.mounted) return d;
  return _pruefen(context, d, hoechstens);
}

List<DateiDaten> _pruefen(BuildContext context, List<DateiDaten> d, int? hoechstens) {
  if (hoechstens == null) return d;
  final zuGross = d.where((x) => x.groesse > hoechstens).toList();
  if (zuGross.isNotEmpty && context.mounted) {
    zeigeMeldung(
        context,
        '${zuGross.length == 1 ? '«${zuGross.first.name}» ist' : '${zuGross.length} Dateien sind'} zu gross '
        '(höchstens ${groesseText(hoechstens)}).',
        fehler: true);
  }
  return [for (final x in d) if (x.groesse <= hoechstens) x];
}

/// Gibt es eine Kamera fuer [fotoAufnehmen]? (Android, iOS)
bool get kameraFuerFotos => RosenwegPlattform.istAndroid || RosenwegPlattform.istIos;

/// Foto aufnehmen (Android/iOS: Kamera) bzw. am Computer ein Bild waehlen,
/// danach auf [maxKante] Pixel verkleinern ([bildVerkleinern]). null =
/// abgebrochen.
Future<DateiDaten?> fotoAufnehmen(BuildContext context, {int maxKante = 2000, int qualitaet = 85, bool ausGalerie = false}) async {
  DateiDaten? d;
  if (kameraFuerFotos) {
    try {
      final f = await ImagePicker().pickImage(
        source: ausGalerie ? ImageSource.gallery : ImageSource.camera,
        maxWidth: maxKante.toDouble(),
        maxHeight: maxKante.toDouble(),
        imageQuality: qualitaet,
      );
      if (f == null) return null;
      d = await _lesen(f);
    } catch (e) {
      Protokoll.schreiben('Kamera', e);
      if (context.mounted) zeigeMeldung(context, 'Die Kamera lässt sich nicht öffnen. Ist der Zugriff erlaubt?', fehler: true);
      return null;
    }
  } else {
    if (!context.mounted) return null;
    final l = await dateienWaehlen(context, arten: const [DateiArt.bilder]);
    if (l.isEmpty) return null;
    d = l.first;
  }
  return bildVerkleinern(d, maxKante: maxKante, qualitaet: qualitaet);
}

/// Bild auf hoechstens [maxKante] Pixel (lange Seite) verkleinern, Drehung
/// aus EXIF uebernehmen, als JPEG. Kleine Bilder und Nicht-Bilder bleiben
/// unveraendert. Laeuft in einem eigenen Isolate (blockiert die Oberflaeche
/// nicht).
Future<DateiDaten> bildVerkleinern(DateiDaten d, {int maxKante = 2000, int qualitaet = 85}) async {
  if (!d.typ.startsWith('image/') || d.typ == 'image/gif') return d;
  final r = await compute(_verkleinern, (d.bytes, maxKante, qualitaet));
  if (r == null) return d;
  final punkt = d.name.lastIndexOf('.');
  final name = '${punkt > 0 ? d.name.substring(0, punkt) : d.name}.jpg';
  return DateiDaten(name: name, bytes: r, typ: 'image/jpeg');
}

Uint8List? _verkleinern((Uint8List, int, int) a) {
  final (bytes, maxKante, qualitaet) = a;
  final b = img.decodeImage(bytes);
  if (b == null) return null;
  var o = img.bakeOrientation(b);
  final lang = o.width > o.height ? o.width : o.height;
  if (lang <= maxKante && bytes.length < 1500 * 1024) return null;
  if (lang > maxKante) {
    o = o.width >= o.height ? img.copyResize(o, width: maxKante) : img.copyResize(o, height: maxKante);
  }
  return img.encodeJpg(o, quality: qualitaet);
}

/// Speichern mit "Speichern unter" (Desktop); auf Telefonen das Teilen-Menue
/// (dort "In Dateien sichern" bzw. eine App waehlen). true = gespeichert
/// oder geteilt.
Future<bool> dateiSpeichern(BuildContext context, DateiDaten d) async {
  if (!RosenwegPlattform.istDesktop) return dateiTeilen(context, d);
  try {
    final ziel = await getSaveLocation(suggestedName: d.name, confirmButtonText: 'Speichern');
    if (ziel == null) return false;
    await File(ziel.path).writeAsBytes(d.bytes, flush: true);
    if (context.mounted) zeigeMeldung(context, 'Gespeichert: ${ziel.path}');
    return true;
  } catch (e) {
    Protokoll.schreiben('Speichern', e);
    if (context.mounted) zeigeMeldung(context, 'Speichern ging nicht: $e', fehler: true);
    return false;
  }
}

/// Teilen-Menue des Systems (Android, iOS, macOS, Windows). Linux hat keins:
/// dort "Speichern unter".
Future<bool> dateiTeilen(BuildContext context, DateiDaten d, {String? text}) async {
  if (Platform.isLinux) return dateiSpeichern(context, d);
  final box = context.findRenderObject() as RenderBox?;
  try {
    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(d.bytes, name: d.name, mimeType: d.typ)],
      fileNameOverrides: [d.name],
      text: text,
      // iPad/macOS: Menue an der Stelle des Knopfs
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
    return r.status != ShareResultStatus.dismissed;
  } catch (e) {
    Protokoll.schreiben('Teilen', e);
    if (context.mounted) zeigeMeldung(context, 'Teilen ging nicht: $e', fehler: true);
    return false;
  }
}

/// Mit der passenden App oeffnen, z. B. eine .ics-Datei im Kalender (dort
/// "Termin hinzufuegen"), ein PDF im Betrachter. Die Datei liegt dazu kurz
/// im Cache-Ordner `rosenweg-oeffnen/` der App.
///
/// Android: ACTION_VIEW ueber den FileProvider der Basis; gibt es keine App
/// fuer den Typ, das Teilen-Menue. iOS kennt kein "Oeffnen mit" fuer eigene
/// Dateien: dort das Teilen-Menue. Desktop: Standard-App des Systems.
/// true = geoeffnet (bzw. geteilt).
Future<bool> dateiOeffnen(BuildContext context, DateiDaten d) async {
  if (Platform.isIOS) return dateiTeilen(context, d);
  try {
    final datei = await _zumOeffnen(d);
    final bool ok;
    if (Platform.isAndroid) {
      ok = await RosenwegPlattform.kanal.invokeMethod<bool>('dateiOeffnen', {'pfad': datei.path, 'typ': d.typ}) ?? false;
    } else {
      ok = await launchUrl(Uri.file(datei.path));
    }
    if (ok) return true;
    if (!context.mounted) return false;
    if (Platform.isAndroid) return await dateiTeilen(context, d);
    zeigeMeldung(context, 'Keine App für ${d.name} gefunden – bitte speichern.', fehler: true);
    return await dateiSpeichern(context, d);
  } catch (e) {
    Protokoll.schreiben('Öffnen', e);
    if (context.mounted) zeigeMeldung(context, 'Öffnen ging nicht: $e', fehler: true);
    return false;
  }
}

/// Schreibt [d] nach `<Cache>/rosenweg-oeffnen/<zufall>/<name>`; aeltere
/// Dateien dort (ab einem Tag) raeumt es dabei weg.
Future<File> _zumOeffnen(DateiDaten d) async {
  final ordner = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}rosenweg-oeffnen');
  await ordner.create(recursive: true);
  try {
    final grenze = DateTime.now().subtract(const Duration(days: 1));
    for (final alt in ordner.listSync()) {
      if (alt.statSync().modified.isBefore(grenze)) alt.deleteSync(recursive: true);
    }
  } catch (_) {}
  final einzeln = Directory('${ordner.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}');
  await einzeln.create();
  final name = d.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final f = File('${einzeln.path}${Platform.pathSeparator}${name.isEmpty ? 'datei' : name}');
  await f.writeAsBytes(d.bytes, flush: true);
  return f;
}

/// Fortschritt eines Transfers als Wert fuer [TransferAnzeige].
class TransferStand extends ValueNotifier<(int, int?)> {
  TransferStand() : super((0, null));

  /// Als [Fortschritt] fuer [RosenwegDateien].
  void call(int fertig, int? gesamt) => value = (fertig, gesamt);
}

/// Balken mit "1,2 MB von 3,4 MB".
class TransferAnzeige extends StatelessWidget {
  const TransferAnzeige({super.key, required this.stand, this.titel});
  final TransferStand stand;
  final String? titel;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<(int, int?)>(
        valueListenable: stand,
        builder: (context, v, _) {
          final (fertig, gesamt) = v;
          final anteil = gesamt == null || gesamt == 0 ? null : (fertig / gesamt).clamp(0.0, 1.0);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (titel != null) ...[Text(titel!), const SizedBox(height: 8)],
            LinearProgressIndicator(value: anteil),
            const SizedBox(height: 6),
            Text(
              gesamt == null ? groesseText(fertig) : '${groesseText(fertig)} von ${groesseText(gesamt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]);
        },
      );
}

/// Fuehrt einen Transfer mit Fortschritts-Dialog aus (nicht schliessbar,
/// bis er fertig ist). Fehler gehen an den Aufrufer.
///
/// ```dart
/// final j = await mitFortschritt(context, 'Foto wird hochgeladen',
///     (f) => sitzung.dateien.hochladen('/api/reparatur/7/foto', foto, multipart: true, fortschritt: f));
/// ```
Future<T> mitFortschritt<T>(BuildContext context, String titel, Future<T> Function(Fortschritt fortschritt) transfer) async {
  final stand = TransferStand();
  final nav = Navigator.of(context);
  var offen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(content: TransferAnzeige(stand: stand, titel: titel)),
    ),
  ).whenComplete(() => offen = false);
  try {
    return await transfer(stand.call);
  } finally {
    if (offen) nav.pop();
    stand.dispose();
  }
}

/// Feld zum Ablegen von Dateien: Knopf "Datei wählen", am Desktop zusaetzlich
/// Dateien aus dem Dateimanager hineinziehen (Drag & Drop).
class DateiAblage extends StatefulWidget {
  const DateiAblage({
    super.key,
    required this.gewaehlt,
    this.arten = const [],
    this.mehrere = false,
    this.hoechstens,
    this.text = 'Datei wählen',
    this.mitFoto = false,
  });
  final void Function(List<DateiDaten> dateien) gewaehlt;
  final List<DateiArt> arten;
  final bool mehrere;
  final int? hoechstens;
  final String text;

  /// Zusaetzlich Knopf "Foto aufnehmen" (Telefone: Kamera).
  final bool mitFoto;

  @override
  State<DateiAblage> createState() => _DateiAblageState();
}

class _DateiAblageState extends State<DateiAblage> {
  bool _drueber = false;

  bool _passt(String name) {
    final e = [for (final a in widget.arten) ...a.endungen];
    if (e.isEmpty) return true;
    final i = name.lastIndexOf('.');
    return i >= 0 && e.contains(name.substring(i + 1).toLowerCase());
  }

  Future<void> _waehlen() async {
    final d = await dateienWaehlen(context, arten: widget.arten, mehrere: widget.mehrere, hoechstens: widget.hoechstens);
    if (d.isNotEmpty) widget.gewaehlt(d);
  }

  Future<void> _foto() async {
    final d = await fotoAufnehmen(context);
    if (d != null) widget.gewaehlt([d]);
  }

  Future<void> _abgelegt(DropDoneDetails details) async {
    setState(() => _drueber = false);
    final roh = [for (final f in details.files) if (_passt(f.name)) f];
    if (roh.length < details.files.length && mounted) {
      zeigeMeldung(context, 'Diese Art Datei passt hier nicht.', fehler: true);
    }
    if (roh.isEmpty) return;
    final d = [for (final f in widget.mehrere ? roh : roh.take(1)) await _lesen(f)];
    if (!mounted) return;
    final ok = _pruefen(context, d, widget.hoechstens);
    if (ok.isNotEmpty) widget.gewaehlt(ok);
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final desktop = RosenwegPlattform.istDesktop;
    final knoepfe = Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
      FilledButton.tonalIcon(onPressed: _waehlen, icon: const Icon(Icons.attach_file), label: Text(widget.text)),
      if (widget.mitFoto && kameraFuerFotos)
        FilledButton.tonalIcon(onPressed: _foto, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Foto aufnehmen')),
    ]);
    if (!desktop) return knoepfe;
    return DropTarget(
      onDragEntered: (_) => setState(() => _drueber = true),
      onDragExited: (_) => setState(() => _drueber = false),
      onDragDone: _abgelegt,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _drueber ? f.primaryContainer : f.surfaceContainerLow,
          border: Border.all(color: _drueber ? f.primary : f.outlineVariant, width: _drueber ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.upload_file, size: 36, color: f.primary),
          const SizedBox(height: 8),
          Text(widget.mehrere ? 'Dateien hierher ziehen oder' : 'Datei hierher ziehen oder', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          knoepfe,
        ]),
      ),
    );
  }
}
