// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../aktualisierung.dart';

/// Schmale Leiste oben in jeder App (ueber [RosenwegRahmen]): erscheint nur,
/// wenn es eine neue Fassung gibt. Ein Knopf "Aktualisieren", einer
/// "Später" – mehr nicht. Waehrend des Ladens ein Balken, danach die
/// Anleitung bzw. der Fehler.
///
/// Liegt ueber dem Navigator (MaterialApp.builder): darum ohne Tooltip und
/// ohne SelectableText, die beide ein Overlay braeuchten.
class AktualisierungsLeiste extends StatelessWidget {
  const AktualisierungsLeiste({super.key, required this.aktualisierung, required this.child});
  final RosenwegAktualisierung aktualisierung;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: aktualisierung,
        builder: (context, _) {
          final a = aktualisierung;
          final zeigen = a.stand != AktualisierungsStand.nichts && !(a.spaeter && a.stand == AktualisierungsStand.verfuegbar);
          return Column(children: [
            if (zeigen) _leiste(context, a),
            Expanded(child: child),
          ]);
        },
      );

  Widget _leiste(BuildContext context, RosenwegAktualisierung a) {
    final f = Theme.of(context).colorScheme;
    final text = switch (a.stand) {
      AktualisierungsStand.verfuegbar => 'Neue Fassung ${a.neu?.version ?? ''} verfügbar.',
      AktualisierungsStand.laedt => 'Neue Fassung wird geladen …',
      _ => a.meldung ?? '',
    };
    return Material(
      color: a.stand == AktualisierungsStand.fehler ? f.errorContainer : f.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(a.stand == AktualisierungsStand.fehler ? Icons.error_outline : Icons.system_update_alt,
                  color: f.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: TextStyle(color: f.onSecondaryContainer))),
              if (a.stand == AktualisierungsStand.verfuegbar) ...[
                TextButton(onPressed: a.spaeterErinnern, child: const Text('Später')),
                const SizedBox(width: 4),
                FilledButton(onPressed: a.aktualisieren, child: const Text('Aktualisieren')),
              ],
              if (a.stand == AktualisierungsStand.fehler)
                TextButton(onPressed: a.aktualisieren, child: const Text('Nochmals')),
              if (a.stand == AktualisierungsStand.fehler || a.stand == AktualisierungsStand.installiert)
                TextButton(onPressed: a.ausblenden, child: const Text('Schliessen')),
            ]),
            if (a.stand == AktualisierungsStand.laedt)
              Padding(padding: const EdgeInsets.only(top: 8, right: 8), child: LinearProgressIndicator(value: a.fortschritt)),
          ]),
        ),
      ),
    );
  }
}
