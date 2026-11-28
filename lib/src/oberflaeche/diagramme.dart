// SPDX-License-Identifier: GPL-3.0-or-later
/// Diagramme fuer Messwerte ueber die Zeit (Wetter, Energie, ZEV, NOC) mit
/// `fl_chart`: Verlauf als Linie oder Balken mit Zeitachse, Kleinverlauf fuer
/// Kacheln, Zeitraum-Umschalter. Einheitlich in allen Apps: gleiche Farben,
/// Zeitachse auf Deutsch (14:00 bzw. 28.11.), Antippen zeigt Zeit und Wert,
/// Luecken in den Daten bleiben Luecken, zu wenig Werte = Leer-Zustand mit Satz.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Ein Messwert. [wert] null = keine Messung (wird zur Luecke).
@immutable
class Messpunkt {
  const Messpunkt(this.zeit, this.wert);
  final DateTime zeit;
  final double? wert;
}

/// Eine Messreihe: Name, Einheit, Farbe und Punkte (nach Zeit sortiert).
@immutable
class Messreihe {
  const Messreihe({
    required this.titel,
    required this.punkte,
    this.einheit = '',
    this.farbe,
    this.nachkommastellen = 1,
  });

  final String titel;
  final String einheit;

  /// null = erste Farbe aus [diagrammFarben].
  final Color? farbe;
  final int nachkommastellen;
  final List<Messpunkt> punkte;

  /// Punkte mit gueltigem Wert.
  List<Messpunkt> get gueltige => [
        for (final p in punkte)
          if (p.wert != null && p.wert!.isFinite) p,
      ];

  bool get leer => gueltige.length < 2;
  double? get kleinster => gueltige.isEmpty ? null : gueltige.map((p) => p.wert!).reduce(math.min);
  double? get groesster => gueltige.isEmpty ? null : gueltige.map((p) => p.wert!).reduce(math.max);
  Messpunkt? get letzter => gueltige.isEmpty ? null : gueltige.last;

  /// Wert mit Einheit, z. B. „4.2 °C“ („–“ fuer null).
  String text(double? v, {bool mitEinheit = true}) {
    if (v == null || !v.isFinite) return '–';
    final z = v.toStringAsFixed(nachkommastellen);
    return mitEinheit && einheit.isNotEmpty ? '$z $einheit' : z;
  }

  /// Nur Punkte zwischen [von] und [bis].
  Messreihe ausschnitt(DateTime von, DateTime bis) => Messreihe(
        titel: titel,
        einheit: einheit,
        farbe: farbe,
        nachkommastellen: nachkommastellen,
        punkte: [
          for (final p in punkte)
            if (!p.zeit.isBefore(von) && !p.zeit.isAfter(bis)) p,
        ],
      );
}

/// Farben fuer Messreihen, in hell und dunkel gut lesbar (wie wetter.html).
const diagrammFarben = <Color>[
  Color(0xFFEA580C), // orange
  Color(0xFF0284C7), // blau
  Color(0xFF65A30D), // gruen
  Color(0xFF9333EA), // violett
  Color(0xFFCA8A04), // gelb
  Color(0xFFDB2777), // pink
  Color(0xFF0D9488), // tuerkis
  Color(0xFFD32F2F), // Rosenweg-Rot
];

/// Ein waehlbarer Zeitraum („24 h“, „7 Tage“, „Monat“ …).
@immutable
class Zeitraum {
  const Zeitraum(this.titel, this.dauer, {this.lang});
  final String titel;
  final Duration dauer;

  /// Fuer Bildschirmleser und Tooltip, z. B. „letzte 24 Stunden“.
  final String? lang;

  /// Bis 7 Tage zurueck (Live-Messwerte: Wetter, Leistung).
  static const kurz = <Zeitraum>[
    Zeitraum('1 h', Duration(hours: 1), lang: 'letzte Stunde'),
    Zeitraum('6 h', Duration(hours: 6), lang: 'letzte 6 Stunden'),
    Zeitraum('24 h', Duration(hours: 24), lang: 'letzte 24 Stunden'),
    Zeitraum('3 T', Duration(days: 3), lang: 'letzte 3 Tage'),
    Zeitraum('7 T', Duration(days: 7), lang: 'letzte 7 Tage'),
  ];

  /// Tag, Monat, Jahr (Verbrauch: Energie, ZEV).
  static const kalender = <Zeitraum>[
    Zeitraum('Tag', Duration(days: 1), lang: 'letzter Tag'),
    Zeitraum('Monat', Duration(days: 31), lang: 'letzter Monat'),
    Zeitraum('Jahr', Duration(days: 366), lang: 'letztes Jahr'),
  ];

  @override
  bool operator ==(Object other) => other is Zeitraum && other.titel == titel && other.dauer == dauer;
  @override
  int get hashCode => Object.hash(titel, dauer);
}

/// Umschalter fuer [Zeitraum]e (Knopfleiste, eine Wahl).
class ZeitraumWahl extends StatelessWidget {
  const ZeitraumWahl({super.key, required this.gewaehlt, required this.geaendert, this.werte = Zeitraum.kurz});
  final List<Zeitraum> werte;
  final Zeitraum gewaehlt;
  final ValueChanged<Zeitraum> geaendert;

  @override
  Widget build(BuildContext context) => SegmentedButton<Zeitraum>(
        showSelectedIcon: false,
        segments: [
          for (final z in werte) ButtonSegment(value: z, label: Text(z.titel), tooltip: z.lang),
        ],
        selected: {gewaehlt},
        onSelectionChanged: (s) => geaendert(s.first),
      );
}

enum DiagrammArt { linie, balken }

/// Zeitachse beschriften: bis 36 h Uhrzeit, sonst Datum.
String zeitachseText(DateTime t, Duration spanne) {
  String zz(int n) => n.toString().padLeft(2, '0');
  return spanne <= const Duration(hours: 36) ? '${zz(t.hour)}:${zz(t.minute)}' : '${zz(t.day)}.${zz(t.month)}.';
}

/// Zeitpunkt fuer Hinweise: „14:32“ heute, sonst „27.11. 14:32“.
String zeitpunktText(DateTime t, {DateTime? jetzt}) {
  final j = jetzt ?? DateTime.now();
  String zz(int n) => n.toString().padLeft(2, '0');
  final uhr = '${zz(t.hour)}:${zz(t.minute)}';
  if (t.year == j.year && t.month == j.month && t.day == j.day) return uhr;
  return '${zz(t.day)}.${zz(t.month)}.${t.year == j.year ? '' : t.year} $uhr';
}

/// Abstand der Teilstriche auf der Zeitachse (etwa 4–7 Beschriftungen).
Duration zeitSchritt(Duration spanne) {
  const h = Duration(hours: 1), t = Duration(days: 1);
  if (spanne <= h) return const Duration(minutes: 15);
  if (spanne <= h * 3) return const Duration(minutes: 30);
  if (spanne <= h * 6) return h;
  if (spanne <= h * 12) return h * 3;
  if (spanne <= h * 36) return h * 6;
  if (spanne <= t * 10) return t;
  if (spanne <= t * 60) return t * 7;
  return t * 30;
}

/// Schoene Schrittweite fuer die Wertachse (1, 2, 5, 10 …).
double schoenerSchritt(double spanne, int anzahl) {
  final roh = (spanne <= 0 ? 1 : spanne) / math.max(1, anzahl);
  final g = math.pow(10, (math.log(roh) / math.ln10).floor()).toDouble();
  final n = roh / g;
  return (n < 1.5 ? 1 : n < 3 ? 2 : n < 7 ? 5 : 10) * g;
}

/// Verlauf einer [Messreihe] mit Zeit- und Wertachse.
///
/// ```dart
/// Verlaufsdiagramm(reihe: Messreihe(titel: 'Temperatur', einheit: '°C', punkte: …))
/// Verlaufsdiagramm(reihe: verbrauch, art: DiagrammArt.balken, von: anfang, bis: ende)
/// ```
/// - [von]/[bis]: sichtbarer Bereich (Standard: erste bis letzte Messung).
/// - [luecke]: so weit auseinander liegende Punkte werden nicht verbunden
///   (Standard: das Dreifache des ueblichen Abstands, mindestens 15 min).
/// - weniger als zwei Werte: [leerText] statt eines leeren Rasters.
class Verlaufsdiagramm extends StatelessWidget {
  const Verlaufsdiagramm({
    super.key,
    required this.reihe,
    this.art = DiagrammArt.linie,
    this.von,
    this.bis,
    this.hoehe = 240,
    this.luecke,
    this.nullLinie = false,
    this.leerText = 'Keine Werte in diesem Zeitraum.',
  });

  final Messreihe reihe;
  final DiagrammArt art;
  final DateTime? von;
  final DateTime? bis;
  final double hoehe;
  final Duration? luecke;

  /// Wertachse bei 0 beginnen (Verbrauch, Regen) statt beim kleinsten Wert.
  final bool nullLinie;
  final String leerText;

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final farbe = reihe.farbe ?? diagrammFarben.first;
    final g = reihe.gueltige;
    if (g.length < 2) {
      return SizedBox(
        height: hoehe,
        child: Center(
          child: Text(leerText, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: f.onSurfaceVariant)),
        ),
      );
    }
    final x0 = (von ?? g.first.zeit).millisecondsSinceEpoch.toDouble();
    var x1 = (bis ?? g.last.zeit).millisecondsSinceEpoch.toDouble();
    if (x1 - x0 < 60000) x1 = x0 + 60000;
    final spanne = Duration(milliseconds: (x1 - x0).round());
    var lo = reihe.kleinster!, hi = reihe.groesster!;
    if (nullLinie) lo = math.min(0, lo);
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final schritt = schoenerSchritt(hi - lo, 4);
    final ylo = (lo / schritt).floor() * schritt, yhi = (hi / schritt).ceil() * schritt;
    final xSchritt = zeitSchritt(spanne).inMilliseconds.toDouble();
    // Teilstriche auf runde Ortszeit (00:00, 06:00 …) statt auf UTC-Vielfache
    final t0 = DateTime.fromMillisecondsSinceEpoch(x0.round());
    final mitternacht = DateTime(t0.year, t0.month, t0.day).millisecondsSinceEpoch.toDouble();
    final achse = t.labelSmall?.copyWith(color: f.onSurfaceVariant);
    final raster = FlGridData(
      drawVerticalLine: true,
      horizontalInterval: schritt,
      verticalInterval: xSchritt,
      getDrawingHorizontalLine: (_) => FlLine(color: f.outlineVariant.withValues(alpha: 0.6), strokeWidth: 1),
      getDrawingVerticalLine: (_) => FlLine(color: f.outlineVariant.withValues(alpha: 0.35), strokeWidth: 1),
    );
    Widget wertTitel(double v, TitleMeta m) => SideTitleWidget(
          meta: m,
          child: Text(_zahl(v, schritt), style: achse),
        );
    Widget zeitTitel(double v, TitleMeta m) {
      return SideTitleWidget(
        meta: m,
        fitInside: SideTitleFitInsideData.fromTitleMeta(m),
        child: Text(zeitachseText(DateTime.fromMillisecondsSinceEpoch(v.round()), spanne), style: achse),
      );
    }

    final titel = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(showTitles: true, reservedSize: 44, interval: schritt, getTitlesWidget: wertTitel),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: xSchritt,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: zeitTitel,
        ),
      ),
    );
    final rahmen = FlBorderData(
      show: true,
      border: Border(left: BorderSide(color: f.outline), bottom: BorderSide(color: f.outline)),
    );
    String hinweis(double x, double y) =>
        '${zeitpunktText(DateTime.fromMillisecondsSinceEpoch(x.round()))}\n${reihe.text(y)}';
    final hinweisStil = t.bodySmall!.copyWith(color: f.onInverseSurface, fontWeight: FontWeight.w600);

    final Widget diagramm;
    if (art == DiagrammArt.balken) {
      final breite = math.max(2.0, math.min(18.0, 600 / g.length * 0.6));
      diagramm = BarChart(BarChartData(
        minY: ylo,
        maxY: yhi,
        gridData: raster.copyWith(drawVerticalLine: false),
        borderData: rahmen,
        titlesData: titel.copyWith(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) {
                final i = v.round();
                final jede = math.max(1, (g.length / 4).ceil());
                if (i < 0 || i >= g.length || i % jede != 0) return const SizedBox.shrink();
                return SideTitleWidget(meta: m, child: Text(zeitachseText(g[i].zeit, spanne), style: achse));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => f.inverseSurface,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (gruppe, _, stab, _) => BarTooltipItem(
              hinweis(g[gruppe.x].zeit.millisecondsSinceEpoch.toDouble(), stab.toY),
              hinweisStil,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < g.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: g[i].wert!,
                fromY: 0 < ylo ? ylo : 0,
                color: farbe,
                width: breite,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ]),
        ],
      ));
    } else {
      diagramm = LineChart(LineChartData(
        baselineX: mitternacht,
        minX: x0,
        maxX: x1,
        minY: ylo,
        maxY: yhi,
        clipData: const FlClipData.all(),
        gridData: raster,
        borderData: rahmen,
        titlesData: titel,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => f.inverseSurface,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (s) => [for (final p in s) LineTooltipItem(hinweis(p.x, p.y), hinweisStil)],
          ),
        ),
        lineBarsData: [_linie(reihe.punkte, farbe, luecke)],
      ));
    }
    return Semantics(
      label: '${reihe.titel}: ${reihe.text(g.last.wert)}, '
          'zwischen ${reihe.text(reihe.kleinster)} und ${reihe.text(reihe.groesster)}',
      child: ExcludeSemantics(
        child: SizedBox(height: hoehe, child: Padding(padding: const EdgeInsets.only(right: 12, top: 8), child: diagramm)),
      ),
    );
  }
}

/// Kleiner Verlauf ohne Achsen (fuer Kacheln und Listen).
class Kleinverlauf extends StatelessWidget {
  const Kleinverlauf({super.key, required this.reihe, this.hoehe = 56, this.leerText = 'noch keine Werte'});
  final Messreihe reihe;
  final double hoehe;
  final String leerText;

  @override
  Widget build(BuildContext context) {
    final g = reihe.gueltige;
    if (g.length < 2) {
      return SizedBox(
        height: hoehe,
        child: Center(
          child: Text(leerText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    var lo = reihe.kleinster!, hi = reihe.groesster!;
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    return ExcludeSemantics(
      child: SizedBox(
        height: hoehe,
        child: LineChart(LineChartData(
          minY: lo,
          maxY: hi,
          minX: g.first.zeit.millisecondsSinceEpoch.toDouble(),
          maxX: g.last.zeit.millisecondsSinceEpoch.toDouble(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [_linie(reihe.punkte, reihe.farbe ?? diagrammFarben.first, null, breite: 2)],
        )),
      ),
    );
  }
}

/// Punkte zu einer Linie; Luecken (null-Werte, grosse Abstaende) bleiben offen.
LineChartBarData _linie(List<Messpunkt> punkte, Color farbe, Duration? luecke, {double breite = 2.5}) {
  final spots = <FlSpot>[];
  final g = luecke ?? _ueblicheLuecke(punkte);
  DateTime? vorher;
  for (final p in punkte) {
    final v = p.wert;
    if (v == null || !v.isFinite) {
      if (spots.isNotEmpty && spots.last != FlSpot.nullSpot) spots.add(FlSpot.nullSpot);
      continue;
    }
    if (vorher != null && p.zeit.difference(vorher) > g && spots.isNotEmpty && spots.last != FlSpot.nullSpot) {
      spots.add(FlSpot.nullSpot);
    }
    spots.add(FlSpot(p.zeit.millisecondsSinceEpoch.toDouble(), v));
    vorher = p.zeit;
  }
  return LineChartBarData(
    spots: spots,
    color: farbe,
    barWidth: breite,
    isCurved: false,
    isStrokeCapRound: true,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(show: true, color: farbe.withValues(alpha: 0.15)),
  );
}

/// Dreifacher mittlerer Abstand (Median), mindestens 15 Minuten.
Duration _ueblicheLuecke(List<Messpunkt> punkte) {
  if (punkte.length < 3) return const Duration(days: 3650);
  final d = <int>[for (var i = 1; i < punkte.length; i++) punkte[i].zeit.difference(punkte[i - 1].zeit).inMilliseconds]..sort();
  final m = d[d.length ~/ 2];
  return Duration(milliseconds: math.max(m * 3, 15 * 60 * 1000));
}

String _zahl(double v, double schritt) {
  final stellen = schritt >= 1 ? 0 : (-(math.log(schritt) / math.ln10).floor()).clamp(0, 3);
  return v.toStringAsFixed(stellen);
}
