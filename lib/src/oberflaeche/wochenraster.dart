// SPDX-License-Identifier: GPL-3.0-or-later
/// Wochenraster: sieben Tage nebeneinander, Stunden untereinander, Termine
/// als Bloecke – fuer alles, was man stundenweise belegt (Waschkueche,
/// Raeume, Termine). Gebaut nach dem Kalender von waschkueche.html.
///
/// ```dart
/// WochenKopf(montag: montag, geaendert: (m) => setState(() => montag = m)),
/// Expanded(
///   child: Wochenraster<Reservation>(
///     montag: montag,
///     eintraege: [for (final r in liste) RasterEintrag(von: r.von, bis: r.bis, titel: r.name, art: ..., daten: r)],
///     leerGetippt: (zeit) => neueReservation(zeit),
///     eintragGetippt: (e) => zeigen(e.daten!),
///   ),
/// ),
/// ```
///
/// * Breiter als [Wochenraster.schmalAb]: alle sieben Tage. Schmaler (Handy):
///   ein Tag, darueber die sieben Tage zum Antippen.
/// * Tippen in eine freie Stelle liefert den Zeitpunkt, abgerundet auf
///   [Wochenraster.raster] Minuten.
/// * Rote Linie = jetzt (jede Minute nachgefuehrt); vergangene Tage grau.
/// * Beim Oeffnen steht die aktuelle Stunde oben (in der laufenden Woche).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'farben.dart';

/// Wie ein Block aussieht.
enum RasterArt {
  /// Eigener Termin (kraeftig).
  eigen,

  /// Termin von jemand anderem (zurueckhaltend).
  fremd,

  /// Gesperrt (z. B. Reinigung, Wartung) – grau.
  gesperrt,
}

/// Ein Block im [Wochenraster].
class RasterEintrag<T> {
  const RasterEintrag({
    required this.von,
    required this.bis,
    required this.titel,
    this.untertitel,
    this.art = RasterArt.fremd,
    this.daten,
  });

  /// Ortszeit.
  final DateTime von;
  final DateTime bis;
  final String titel;
  final String? untertitel;
  final RasterArt art;

  /// Was die App beim Antippen braucht.
  final T? daten;

  /// Laeuft gerade.
  bool laeuft(DateTime jetzt) => !jetzt.isBefore(von) && jetzt.isBefore(bis);
}

/// Montag 00:00 der Woche von [tag] (Ortszeit).
DateTime montagVon(DateTime tag) => DateTime(tag.year, tag.month, tag.day - (tag.weekday - DateTime.monday));

/// Kalenderwoche nach ISO 8601 (wie im Portal: „KW 48“).
int kalenderwoche(DateTime tag) {
  final d = DateTime.utc(tag.year, tag.month, tag.day);
  final donnerstag = d.add(Duration(days: DateTime.thursday - d.weekday));
  final erster = DateTime.utc(donnerstag.year, 1, 1);
  return donnerstag.difference(erster).inDays ~/ 7 + 1;
}

const wochentageKurz = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const wochentageLang = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

String _zwei(int n) => n.toString().padLeft(2, '0');

/// 08:05
String uhrText(DateTime z) => '${_zwei(z.hour)}:${_zwei(z.minute)}';

/// „Montag, 23.11.2026“
String tagLangText(DateTime z) => '${wochentageLang[z.weekday - 1]}, ${z.day}.${z.month}.${z.year}';

bool _gleicherTag(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Kopfzeile zum Blaettern: „‹  KW 48 · 23.11.–29.11.2026  ›  Heute“.
class WochenKopf extends StatelessWidget {
  const WochenKopf({super.key, required this.montag, required this.geaendert, this.jetzt});

  final DateTime montag;

  /// Neuer Montag (vorige/naechste Woche, heute).
  final ValueChanged<DateTime> geaendert;

  /// Fuer Tests; sonst die Uhr.
  final DateTime Function()? jetzt;

  @override
  Widget build(BuildContext context) {
    final heute = (jetzt ?? DateTime.now)();
    final sonntag = DateTime(montag.year, montag.month, montag.day + 6);
    final dieseWoche = _gleicherTag(montagVon(heute), montag);
    final t = Theme.of(context).textTheme;
    return Row(children: [
      IconButton(
        tooltip: 'Vorige Woche',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => geaendert(DateTime(montag.year, montag.month, montag.day - 7)),
      ),
      Expanded(
        child: Text(
          'KW ${kalenderwoche(montag)} · ${montag.day}.${montag.month}.–${sonntag.day}.${sonntag.month}.${sonntag.year}',
          style: t.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      IconButton(
        tooltip: 'Nächste Woche',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => geaendert(DateTime(montag.year, montag.month, montag.day + 7)),
      ),
      TextButton(onPressed: dieseWoche ? null : () => geaendert(montagVon(heute)), child: const Text('Heute')),
    ]);
  }
}

/// Sieben Tage × Stunden mit Bloecken. Siehe Bibliothekskommentar oben.
class Wochenraster<T> extends StatefulWidget {
  const Wochenraster({
    super.key,
    required this.montag,
    required this.eintraege,
    this.vonStunde = 6,
    this.bisStunde = 22,
    this.stundenHoehe = 56,
    this.raster = 15,
    this.leerGetippt,
    this.eintragGetippt,
    this.schmalAb = 600,
    this.tag,
    this.tagGewaehlt,
    this.jetzt,
  }) : assert(0 <= vonStunde && vonStunde < bisStunde && bisStunde <= 24);

  /// Montag 00:00 der gezeigten Woche ([montagVon]).
  final DateTime montag;
  final List<RasterEintrag<T>> eintraege;

  /// Sichtbarer Bereich, volle Stunden (Standard 06–22 Uhr wie im Portal).
  final int vonStunde;
  final int bisStunde;
  final double stundenHoehe;

  /// Tippen in eine freie Stelle rundet auf so viele Minuten ab.
  final int raster;

  /// Freie Stelle angetippt (Zeitpunkt, abgerundet). null = nichts.
  final ValueChanged<DateTime>? leerGetippt;
  final ValueChanged<RasterEintrag<T>>? eintragGetippt;

  /// Unter dieser Breite nur ein Tag (Handy).
  final double schmalAb;

  /// Gezeigter Tag in der schmalen Ansicht (0 = Montag); null = selbst
  /// verwalten (heute bzw. Montag).
  final int? tag;
  final ValueChanged<int>? tagGewaehlt;

  /// Fuer Tests; sonst die Uhr.
  final DateTime Function()? jetzt;

  @override
  State<Wochenraster<T>> createState() => _WochenrasterState<T>();
}

class _WochenrasterState<T> extends State<Wochenraster<T>> {
  Timer? _uhr;
  late int _tag = widget.tag ?? _startTag();
  late final ScrollController _scroll = ScrollController(initialScrollOffset: _startOffset());

  DateTime get _jetzt => (widget.jetzt ?? DateTime.now)();

  int _startTag() {
    final j = _jetzt;
    return _gleicherTag(montagVon(j), widget.montag) ? j.weekday - 1 : 0;
  }

  double _startOffset() {
    final j = _jetzt;
    if (!_gleicherTag(montagVon(j), widget.montag)) return 0;
    final stunde = (j.hour - 1).clamp(widget.vonStunde, widget.bisStunde);
    return (stunde - widget.vonStunde) * widget.stundenHoehe;
  }

  @override
  void initState() {
    super.initState();
    // Jetzt-Linie jede Minute nachfuehren
    _uhr = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(Wochenraster<T> alt) {
    super.didUpdateWidget(alt);
    if (widget.tag != null) {
      _tag = widget.tag!;
    } else if (!_gleicherTag(alt.montag, widget.montag)) {
      _tag = _startTag();
    }
  }

  @override
  void dispose() {
    _uhr?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _tagWaehlen(int i) {
    if (widget.tag == null) setState(() => _tag = i);
    widget.tagGewaehlt?.call(i);
  }

  DateTime _tagNr(int i) => DateTime(widget.montag.year, widget.montag.month, widget.montag.day + i);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final schmal = c.maxWidth < widget.schmalAb;
        final tage = schmal ? [_tag] : [for (var i = 0; i < 7; i++) i];
        final jetzt = _jetzt;
        return Column(children: [
          if (schmal) _TagWahl(montag: widget.montag, gewaehlt: _tag, jetzt: jetzt, waehlen: _tagWaehlen),
          // schmal steht der Tag schon in der Tageswahl
          if (!schmal) _Kopf(tage: [for (final i in tage) _tagNr(i)], jetzt: jetzt),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: (widget.bisStunde - widget.vonStunde) * widget.stundenHoehe,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Stunden(von: widget.vonStunde, bis: widget.bisStunde, hoehe: widget.stundenHoehe),
                  for (final i in tage) Expanded(child: _Tag<T>(raster: widget, tag: _tagNr(i), jetzt: jetzt)),
                ]),
              ),
            ),
          ),
        ]);
      });
}

const _randBreite = 48.0;

/// Tage zum Antippen (schmale Ansicht).
class _TagWahl extends StatelessWidget {
  const _TagWahl({required this.montag, required this.gewaehlt, required this.jetzt, required this.waehlen});
  final DateTime montag;
  final int gewaehlt;
  final DateTime jetzt;
  final ValueChanged<int> waehlen;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${wochentageKurz[i]} ${DateTime(montag.year, montag.month, montag.day + i).day}.'),
                selected: i == gewaehlt,
                avatar: _gleicherTag(DateTime(montag.year, montag.month, montag.day + i), jetzt)
                    ? const Icon(Icons.today, size: 16)
                    : null,
                showCheckmark: false,
                onSelected: (_) => waehlen(i),
              ),
            ),
        ]),
      );
}

/// Wochentag und Datum ueber den Spalten; heute hervorgehoben.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.tage, required this.jetzt});
  final List<DateTime> tage;
  final DateTime jetzt;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(children: [
      const SizedBox(width: _randBreite),
      for (final d in tage)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Text(wochentageKurz[d.weekday - 1], style: t.labelSmall?.copyWith(color: f.onSurfaceVariant)),
              const SizedBox(height: 2),
              _gleicherTag(d, jetzt)
                  ? CircleAvatar(
                      radius: 14,
                      backgroundColor: f.primary,
                      child: Text('${d.day}', style: t.labelLarge?.copyWith(color: f.onPrimary)),
                    )
                  : SizedBox(height: 28, child: Center(child: Text('${d.day}', style: t.labelLarge))),
            ]),
          ),
        ),
    ]);
  }
}

/// Stundenleiste links.
class _Stunden extends StatelessWidget {
  const _Stunden({required this.von, required this.bis, required this.hoehe});
  final int von;
  final int bis;
  final double hoehe;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return SizedBox(
      width: _randBreite,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var h = von; h < bis; h++)
          Positioned(
            top: (h - von) * hoehe + 2,
            right: 6,
            child: ExcludeSemantics(child: Text('${_zwei(h)}:00', style: s)),
          ),
      ]),
    );
  }
}

/// Eine Tagesspalte: Linien, freie Flaeche zum Antippen, Bloecke, Jetzt-Linie.
class _Tag<T> extends StatelessWidget {
  const _Tag({required this.raster, required this.tag, required this.jetzt});
  final Wochenraster<T> raster;
  final DateTime tag;
  final DateTime jetzt;

  double _y(DateTime z) {
    // Minuten seit Tagesbeginn dieser Spalte (Ende am Folgetag = 24 Uhr)
    final minuten = z.isBefore(tag)
        ? 0
        : (_gleicherTag(z, tag) ? z.hour * 60 + z.minute : 24 * 60);
    final sichtbar = (minuten / 60).clamp(raster.vonStunde.toDouble(), raster.bisStunde.toDouble());
    return (sichtbar - raster.vonStunde) * raster.stundenHoehe;
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final morgen = DateTime(tag.year, tag.month, tag.day + 1);
    final vorbei = !morgen.isAfter(jetzt);
    final heute = _gleicherTag(tag, jetzt);
    final hoehe = (raster.bisStunde - raster.vonStunde) * raster.stundenHoehe;
    final bloecke = [
      for (final e in raster.eintraege)
        if (e.von.isBefore(morgen) && e.bis.isAfter(tag) && _y(e.bis) > _y(e.von)) e,
    ];
    return Container(
      decoration: BoxDecoration(
        color: vorbei ? f.onSurface.withValues(alpha: 0.04) : (heute ? f.primary.withValues(alpha: 0.03) : null),
        border: Border(left: BorderSide(color: f.outlineVariant)),
      ),
      child: Stack(children: [
        // Stunden- und Halbstundenlinien
        for (var h = raster.vonStunde; h < raster.bisStunde; h++) ...[
          Positioned(
            top: (h - raster.vonStunde) * raster.stundenHoehe,
            left: 0,
            right: 0,
            child: Divider(height: 1, color: f.outlineVariant),
          ),
          Positioned(
            top: (h - raster.vonStunde + 0.5) * raster.stundenHoehe,
            left: 0,
            right: 0,
            child: Divider(height: 1, color: f.outlineVariant.withValues(alpha: 0.35)),
          ),
        ],
        // freie Flaeche: Tippen = Zeitpunkt
        if (raster.leerGetippt != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final minuten = (raster.vonStunde * 60 + d.localPosition.dy / raster.stundenHoehe * 60).floor();
                final gerundet = (minuten ~/ raster.raster) * raster.raster;
                final max = raster.bisStunde * 60 - raster.raster;
                final m = gerundet.clamp(raster.vonStunde * 60, max);
                raster.leerGetippt!(DateTime(tag.year, tag.month, tag.day, m ~/ 60, m % 60));
              },
            ),
          ),
        for (final e in bloecke)
          Positioned(
            top: _y(e.von),
            height: (_y(e.bis) - _y(e.von)).clamp(20.0, hoehe),
            left: 2,
            right: 2,
            child: _Block<T>(eintrag: e, laeuft: e.laeuft(jetzt), getippt: raster.eintragGetippt),
          ),
        if (heute && jetzt.hour >= raster.vonStunde && jetzt.hour < raster.bisStunde)
          Positioned(
            top: _y(jetzt) - 1,
            left: 0,
            right: 0,
            child: IgnorePointer(child: Container(height: 2, color: f.error)),
          ),
      ]),
    );
  }
}

class _Block<T> extends StatelessWidget {
  const _Block({required this.eintrag, required this.laeuft, this.getippt});
  final RasterEintrag<T> eintrag;
  final bool laeuft;
  final ValueChanged<RasterEintrag<T>>? getippt;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final (grund, schrift) = switch (eintrag.art) {
      RasterArt.eigen => (f.primary, f.onPrimary),
      RasterArt.fremd => (f.secondaryContainer, f.onSecondaryContainer),
      RasterArt.gesperrt => (f.surfaceContainerHighest, f.onSurfaceVariant),
    };
    final zeit = '${uhrText(eintrag.von)}–${uhrText(eintrag.bis)}';
    return Semantics(
      button: getippt != null,
      label: '${eintrag.titel}, ${tagLangText(eintrag.von)}, $zeit${laeuft ? ', läuft gerade' : ''}',
      excludeSemantics: true,
      child: Material(
        color: grund,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: laeuft ? const BorderSide(color: RosenwegFarben.gut, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: getippt == null ? null : () => getippt!(eintrag),
          child: LayoutBuilder(
            builder: (context, c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ClipRect(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(zeit, maxLines: 1, overflow: TextOverflow.clip, style: t.labelSmall?.copyWith(color: schrift, fontWeight: FontWeight.w600)),
                  if (c.maxHeight >= 34)
                    Text(eintrag.titel, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: schrift)),
                  if (c.maxHeight >= 50 && eintrag.untertitel != null)
                    Text(eintrag.untertitel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: schrift.withValues(alpha: 0.8))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
