// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../aktualisierung.dart';
import '../plattform.dart';
import 'anmeldeschirm.dart' show AnmeldeFarben;
import 'bausteine.dart';
import 'farben.dart';

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
/// also im Konto-Menue jeder App) - gestaltet wie die Update-Seite des
/// Android-Updaters (commons-rosenweg 0.1.8): Karte mit Logo, Name,
/// "installiert -> neu", Statuszeile (wartet / laedt mit Balken / installiert /
/// Fehler) und grossem Knopf in der Gruppenfarbe der App.
///
/// - Android: Rosenweg Updater aus commons-rosenweg (eigene Seite, prueft dort
///   auch das Recht "Unbekannte Apps installieren" und Play Protect).
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
    final dunkel = Theme.of(context).brightness == Brightness.dark;
    final gruppe = AnmeldeFarben.fuer(a?.app.gruppe).grund;
    final gruppeSchrift = dunkel ? Color.lerp(gruppe, Colors.white, 0.5)! : gruppe;
    return Abschnitt(
      titel: 'Updates',
      symbol: Icons.system_update_alt,
      kind: a == null && !_android
          ? Text('Für diese App gibt es hier keine Updates über die App.',
              key: const Key('aktualisierung-aus'), style: Theme.of(context).textTheme.bodyMedium)
          : a == null
              ? _knoepfe(context, null, gruppe)
              : ListenableBuilder(
                  listenable: a,
                  builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _zeile(context, a, gruppeSchrift),
                    const SizedBox(height: 12),
                    if (!_android && !a.aktiv)
                      Text(a.ausGrund, key: const Key('aktualisierung-aus'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))
                    else
                      _knoepfe(context, a, gruppe),
                  ]),
                ),
    );
  }

  /// Eine Zeile wie auf der Android-Seite: Logo, Name, Fassung, Status.
  Widget _zeile(BuildContext context, RosenwegAktualisierung a, Color gruppeSchrift) {
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    final gut = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF81C784) : RosenwegFarben.gut;
    final e = _ergebnis;
    final neu = a.neu?.version ?? e?.neu?.version;
    final fassung = a.installiert == null ? '' : (neu == null ? a.installiert! : '${a.installiert}  →  $neu');
    final (String status, Color farbe) = switch (a.stand) {
      AktualisierungsStand.laedt => ('Lädt … ${((a.fortschritt ?? 0) * 100).round()} %', gruppeSchrift),
      AktualisierungsStand.installiert => ('✓ ${a.meldung ?? 'Installiert'}', gut),
      AktualisierungsStand.fehler => ('✕ ${a.meldung ?? 'Nicht installiert'}', f.error),
      _ => switch (e?.art) {
          PruefArt.aktuell => ('✓ Aktuell', gut),
          PruefArt.neu => ('Neue Fassung bereit', gruppeSchrift),
          PruefArt.fehler => ('✕ ${e!.text}', f.error),
          _ => ('', f.onSurfaceVariant),
        },
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: f.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: f.outlineVariant),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: a.app.logo != null
              ? Image(image: a.app.logo!, width: 48, height: 48)
              : Icon(Icons.apps, size: 48, color: gruppeSchrift),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.app.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (fassung.isNotEmpty) Text(fassung, style: t.bodyMedium?.copyWith(color: f.onSurfaceVariant)),
            if (status.isNotEmpty) Text(status, key: const Key('aktualisierung-ergebnis'), style: t.bodyMedium?.copyWith(color: farbe)),
            if (a.stand == AktualisierungsStand.laedt)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(value: a.fortschritt, color: gruppeSchrift, minHeight: 6,
                    borderRadius: BorderRadius.circular(3)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _knoepfe(BuildContext context, RosenwegAktualisierung? a, Color gruppe) {
    final e = _ergebnis;
    final installieren = e?.art == PruefArt.neu && a != null && a.stand != AktualisierungsStand.laedt &&
        a.stand != AktualisierungsStand.installiert;
    final stil = FilledButton.styleFrom(
      backgroundColor: gruppe,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(52),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      shape: const StadiumBorder(),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (installieren)
        FilledButton.icon(
          key: const Key('aktualisierung-installieren'),
          style: stil,
          icon: const Icon(Icons.download),
          label: Text('Installieren (${e!.neu!.version})'),
          onPressed: () => a.aktualisieren(),
        )
      else
        FilledButton.icon(
          key: const Key('nach-updates-suchen'),
          style: stil,
          icon: _sucht
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh),
          label: const Text('Nach Updates suchen'),
          onPressed: _sucht ? null : _suchen,
        ),
      if (installieren) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder()),
          onPressed: _sucht ? null : _suchen,
          child: const Text('Nochmals suchen'),
        ),
      ],
    ]);
  }
}
