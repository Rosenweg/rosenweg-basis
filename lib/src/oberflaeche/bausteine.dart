// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../konfig.dart';
import '../netz/fehler.dart';
import '../protokoll.dart';
import 'farben.dart';

/// Logo der App in runder Ecke, wie auf dem Startbildschirm.
class RosenwegLogo extends StatelessWidget {
  const RosenwegLogo(this.app, {super.key, this.groesse = 96});
  final RosenwegApp app;
  final double groesse;

  @override
  Widget build(BuildContext context) =>
      Image(image: app.logoOderTurm, width: groesse, height: groesse, filterQuality: FilterQuality.medium, semanticLabel: app.name);
}

/// Fehler gross und verstaendlich, mit "Nochmals".
class FehlerAnzeige extends StatelessWidget {
  const FehlerAnzeige({super.key, required this.text, this.nochmals, this.titel = 'Das hat nicht geklappt'});
  final String text;
  final String titel;
  final VoidCallback? nochmals;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Mitte(children: [
      Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: 16),
      Text(titel, style: t.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      SelectableText(text, style: t.bodyMedium, textAlign: TextAlign.center),
      if (nochmals != null) ...[
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: nochmals, icon: const Icon(Icons.refresh), label: const Text('Nochmals')),
      ],
    ]);
  }
}

/// Lade-Anzeige mit optionalem Text.
class LadeAnzeige extends StatelessWidget {
  const LadeAnzeige({super.key, this.text});
  final String? text;
  @override
  Widget build(BuildContext context) => _Mitte(children: [
        const CircularProgressIndicator(),
        if (text != null) ...[const SizedBox(height: 16), Text(text!, textAlign: TextAlign.center)],
      ]);
}

class _Mitte extends StatelessWidget {
  const _Mitte({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );
}

/// Ein Abschnitt einer Seite: Karte mit Titel, optional Symbol, Erklaersatz
/// und Inhalt. So sehen alle Apps gleich aus wie die Karten im Portal.
class Abschnitt extends StatelessWidget {
  const Abschnitt({super.key, required this.titel, this.symbol, this.erklaerung, required this.kind, this.aktion});
  final String titel;
  final IconData? symbol;
  final String? erklaerung;
  final Widget kind;

  /// Knopf rechts im Titel (z. B. "+ Nummer").
  final Widget? aktion;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (symbol != null) ...[Icon(symbol, color: f.onSurfaceVariant), const SizedBox(width: 8)],
            Expanded(child: Text(titel, style: t.titleMedium)),
            ?aktion,
          ]),
          if (erklaerung != null) ...[
            const SizedBox(height: 4),
            Text(erklaerung!, style: t.bodySmall?.copyWith(color: f.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          kind,
        ]),
      ),
    );
  }
}

/// Kurze Meldung unten. [fehler] als Ausnahme: deren Text wird gezeigt
/// (alle Fehler der Basis haben einen ganzen Satz als Text).
void zeigeMeldung(BuildContext context, String text, {bool fehler = false}) {
  final f = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? f.error : null,
      duration: Duration(seconds: fehler ? 6 : 3),
    ));
}

/// Ausnahme → Satz fuer die Person. Unbekanntes kommt ins Protokoll.
String fehlerText(Object e) {
  if (e is ApiFehler || e is ServerNichtErreichbar || e is ZuVieleAnfragen || e is GeraetFehler) return '$e';
  Protokoll.schreiben('Unerwarteter Fehler', e);
  return 'Unerwarteter Fehler: $e';
}

/// Ja/Nein-Frage; true = bestaetigt.
Future<bool> frage(BuildContext context, String titel, String text, {String ja = 'Ja', bool gefaehrlich = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titel),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: gefaehrlich ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          child: Text(ja),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// "Ueber": Name, Version, GPL, Quelltext, Lizenzen der Fremdpakete.
Future<void> zeigeUeber(BuildContext context, RosenwegApp app) async {
  String? version;
  try {
    final i = await PackageInfo.fromPlatform();
    version = '${i.version} (${i.buildNumber})';
  } catch (_) {}
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: app.name,
    applicationVersion: version,
    applicationIcon: RosenwegLogo(app, groesse: 56),
    applicationLegalese: 'Rosenweg 4303 · GNU General Public License, Version 3 oder später (GPL-3.0-or-later).',
    children: [
      const SizedBox(height: 16),
      Text(app.beschreibung),
      const SizedBox(height: 12),
      const Text('Dieses Programm ist freie Software: Sie dürfen es weitergeben und verändern, '
          'unter den Bedingungen der GPL, Version 3 oder später. Es kommt ohne jede Gewährleistung.'),
      if (app.quelle != null) ...[
        const SizedBox(height: 12),
        SelectableText('Quelltext: ${app.quelle}'),
      ],
    ],
  );
}

/// Farbiger Hinweis-Kasten (gut/warnung/fehler/info), wie die Meldungen im Portal.
class Hinweis extends StatelessWidget {
  const Hinweis(this.text, {super.key, this.art = HinweisArt.info});
  final String text;
  final HinweisArt art;
  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final (farbe, symbol) = switch (art) {
      HinweisArt.gut => (RosenwegFarben.gut, Icons.check_circle_outline),
      HinweisArt.warnung => (RosenwegFarben.warnung, Icons.warning_amber),
      HinweisArt.fehler => (f.error, Icons.error_outline),
      HinweisArt.info => (f.primary, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.08),
        border: Border.all(color: farbe.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(symbol, color: farbe, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

enum HinweisArt { info, gut, warnung, fehler }
