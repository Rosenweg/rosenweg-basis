// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../aktualisierung.dart';
import '../plattform.dart';
import 'bausteine.dart';

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

/// Abschnitt "Updates" fuer die gemeinsamen Einstellungen (in [zeigeAnmeldung],
/// also im Konto-Menue jeder App): installierte Fassung und der Knopf
/// "Nach Updates suchen" mit sichtbarem Ergebnis.
///
/// - Android: Rosenweg Updater aus commons-rosenweg (eigene Seite mit
///   "Aktuell" / "Neue Fassung X - Installieren" / Fehler).
/// - Linux, macOS, Windows: [RosenwegAktualisierung.jetztPruefen], bei einer
///   neuen Fassung "Installieren".
/// - Stationen, verwaltete Installationen, iOS, Entwicklungsbau: nur der
///   Hinweis, wer aktualisiert (kein Knopf).
class AktualisierungKarte extends StatefulWidget {
  const AktualisierungKarte({super.key, this.aktualisierung, this.android});

  /// Standard: [RosenwegAktualisierung.zuletzt] (von [rosenwegStarten]).
  final RosenwegAktualisierung? aktualisierung;

  /// Fuer Tests: Android-Weg erzwingen bzw. ausschalten (Standard: Plattform).
  final bool? android;

  @override
  State<AktualisierungKarte> createState() => _AktualisierungKarteState();
}

class _AktualisierungKarteState extends State<AktualisierungKarte> {
  PruefErgebnis? _ergebnis;
  bool _sucht = false;

  RosenwegAktualisierung? get _a => widget.aktualisierung ?? RosenwegAktualisierung.zuletzt;
  bool get _android => widget.android ?? RosenwegPlattform.istAndroid;

  Future<void> _suchen() async {
    if (_android) {
      await RosenwegPlattform.updaterPruefen();
      return;
    }
    final a = _a;
    if (a == null) return;
    setState(() => _sucht = true);
    final e = await a.jetztPruefen();
    if (!mounted) return;
    setState(() {
      _sucht = false;
      _ergebnis = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    final aus = !_android && (a == null || !a.aktiv);
    final kinder = <Widget>[];
    if (aus) {
      kinder.add(Text(a?.ausGrund ?? 'Für diese App gibt es hier keine Updates über die App.',
          key: const Key('aktualisierung-aus'), style: t.bodyMedium?.copyWith(color: f.onSurfaceVariant)));
    } else {
      final e = _ergebnis;
      if (e != null) {
        kinder.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              switch (e.art) {
                PruefArt.aktuell => Icons.check_circle_outline,
                PruefArt.neu => Icons.system_update_alt,
                PruefArt.fehler => Icons.error_outline,
                _ => Icons.info_outline,
              },
              color: e.art == PruefArt.fehler ? f.error : f.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(e.text, key: const Key('aktualisierung-ergebnis'), style: t.bodyMedium)),
        ]));
        kinder.add(const SizedBox(height: 12));
      }
      kinder.add(Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('nach-updates-suchen'),
          icon: _sucht
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: const Text('Nach Updates suchen'),
          onPressed: _sucht ? null : _suchen,
        ),
        if (e?.art == PruefArt.neu && a != null)
          FilledButton.icon(
            key: const Key('aktualisierung-installieren'),
            icon: const Icon(Icons.download),
            label: Text('Installieren (${e!.neu!.version})'),
            onPressed: () async {
              await a.aktualisieren();
              if (!mounted) return;
              setState(() => _ergebnis = PruefErgebnis.aus(a.meldung ?? 'Wird installiert …'));
            },
          ),
      ]));
    }
    return Abschnitt(titel: 'Updates', symbol: Icons.system_update_alt, kind: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kinder));
  }
}
