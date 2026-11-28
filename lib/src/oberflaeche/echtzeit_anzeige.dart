// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';

import '../netz/echtzeit.dart';
import 'diagramme.dart' show zeitpunktText;
import 'farben.dart';

/// Kleine Anzeige „live / veraltet / getrennt“ fuer eine [EchtzeitQuelle],
/// gleich in allen Apps: gruener Punkt = live, gelb = verbunden, aber seit
/// [veraltetNach] nichts Neues (oder nur gespeicherte, evtl. alte Werte),
/// grau = verbinde/getrennt, rot = kein Zugriff.
/// Antippen bei getrennt oder kein Zugriff: [EchtzeitQuelle.nochmals].
class EchtzeitAnzeige extends StatefulWidget {
  const EchtzeitAnzeige({
    super.key,
    required this.quelle,
    this.veraltetNach = const Duration(minutes: 5),
  });

  final EchtzeitQuelle quelle;
  final Duration veraltetNach;

  /// Text und Farbe zu einem Zustand (fuer eigene Anzeigen und Tests).
  static (String, Color) beschreiben(EchtzeitZustand z, Duration veraltetNach, ColorScheme f, {DateTime? jetzt}) {
    final l = z.letzteNachricht;
    final stand = l == null ? '' : ' · Stand ${zeitpunktText(l, jetzt: jetzt)}';
    return switch (z.stand) {
      EchtzeitStand.live when l == null => ('verbunden · wartet auf neue Werte', RosenwegFarben.warnung),
      EchtzeitStand.live when z.veraltet(veraltetNach, jetzt: jetzt) => ('veraltet$stand', RosenwegFarben.warnung),
      EchtzeitStand.live => ('live$stand', RosenwegFarben.gut),
      EchtzeitStand.verbinde => ('verbinde …', f.outline),
      EchtzeitStand.getrennt => ('getrennt$stand', f.outline),
      EchtzeitStand.keinZugriff => ('kein Zugriff', f.error),
      EchtzeitStand.geschlossen => ('beendet', f.outline),
    };
  }

  @override
  State<EchtzeitAnzeige> createState() => _EchtzeitAnzeigeState();
}

class _EchtzeitAnzeigeState extends State<EchtzeitAnzeige> {
  Timer? _uhr;

  @override
  void initState() {
    super.initState();
    // „veraltet“ entsteht ohne neue Nachricht: alle 30 s neu bewerten.
    _uhr = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EchtzeitZustand>(
        valueListenable: widget.quelle.zustand,
        builder: (context, z, _) {
          final f = Theme.of(context).colorScheme;
          final (text, farbe) = EchtzeitAnzeige.beschreiben(z, widget.veraltetNach, f);
          final tippen = z.stand == EchtzeitStand.getrennt || z.stand == EchtzeitStand.keinZugriff ? widget.quelle.nochmals : null;
          final inhalt = Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: farbe, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium)),
            if (tippen != null) ...[const SizedBox(width: 6), Icon(Icons.refresh, size: 16, color: f.primary)],
          ]);
          return Semantics(
            liveRegion: true,
            button: tippen != null,
            label: tippen != null ? '$text, antippen zum Verbinden' : text,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: tippen,
                borderRadius: BorderRadius.circular(16),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: inhalt),
              ),
            ),
          );
        },
      );
}
