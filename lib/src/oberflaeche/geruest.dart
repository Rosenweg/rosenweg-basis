// SPDX-License-Identifier: GPL-3.0-or-later
/// Gerüst fuer Handy und Desktop: dieselbe App passt sich der Fensterbreite
/// an. Auf dem Handy bleibt alles wie gewohnt (Navigation unten, Inhalt
/// ueber die ganze Breite); ab [Fensterklasse.breit] (840 px, Desktop,
/// Tablet quer) kommt die Navigation an den linken Rand und der Inhalt
/// steht mit begrenzter Breite in der Mitte, statt ueber 1920 px gestreckt.
library;

import 'package:flutter/material.dart';

/// Fensterklassen nach Material 3 (window size classes). Entscheidend ist die
/// Breite des Fensters, nicht das Geraet: ein schmales Desktop-Fenster
/// bekommt das Handy-Layout.
enum Fensterklasse {
  /// unter 600 px: Handy hochkant.
  kompakt,

  /// 600–839 px: Handy quer, kleines Tablet, schmales Fenster.
  mittel,

  /// 840–1199 px: Desktop, Tablet quer — Seitenleiste statt Navigation unten.
  breit,

  /// ab 1200 px: grosser Desktop — Seitenleiste mit Beschriftung.
  sehrBreit;

  static const mittelAb = 600.0;
  static const breitAb = 840.0;
  static const sehrBreitAb = 1200.0;

  static Fensterklasse ausBreite(double breite) => breite >= sehrBreitAb
      ? sehrBreit
      : breite >= breitAb
          ? breit
          : breite >= mittelAb
              ? mittel
              : kompakt;

  /// Klasse des aktuellen Fensters (MediaQuery).
  static Fensterklasse von(BuildContext context) => ausBreite(MediaQuery.sizeOf(context).width);

  /// Desktop-Layout: Seitenleiste, Spalten, begrenzte Breite.
  bool get istBreit => index >= breit.index;
}

/// Inhalt mit hoechstens [maxBreite], waagrecht in der Mitte. Auf dem Handy
/// (schmaler als [maxBreite]) aendert sich nichts.
class RosenwegInhalt extends StatelessWidget {
  const RosenwegInhalt({super.key, required this.child, this.maxBreite = RosenwegInhalt.standardBreite});
  final Widget child;
  final double maxBreite;

  /// Lesbare Breite fuer Listen und Formulare.
  static const standardBreite = 760.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        // Schmaler: genau wie ohne (Handy unveraendert).
        if (c.maxWidth <= maxBreite) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: maxBreite, height: c.hasBoundedHeight ? c.maxHeight : null, child: child),
        );
      });
}

/// Zwei Spalten ab [Fensterklasse.breit] (z. B. Aktionen links, Liste
/// rechts), darunter [schmal] — das unveraenderte Handy-Layout. Jede Spalte
/// scrollt selbst.
class RosenwegSpalten extends StatelessWidget {
  const RosenwegSpalten({
    super.key,
    required this.links,
    required this.rechts,
    required this.schmal,
    this.linksBreite = 360,
    this.maxBreite = 1280,
  });
  final Widget links;
  final Widget rechts;
  final Widget schmal;
  final double linksBreite;

  /// Beide Spalten zusammen hoechstens so breit, in der Mitte.
  final double maxBreite;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (!Fensterklasse.ausBreite(c.maxWidth).istBreit) return schmal;
        return RosenwegInhalt(
          maxBreite: maxBreite,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: linksBreite, child: links),
            const VerticalDivider(width: 1),
            Expanded(child: rechts),
          ]),
        );
      });
}

/// Ein Ziel der Hauptnavigation von [RosenwegGeruest].
class GeruestZiel {
  const GeruestZiel({required this.titel, required this.symbol, this.gewaehltSymbol, required this.seite});
  final String titel;
  final IconData symbol;
  final IconData? gewaehltSymbol;
  final WidgetBuilder seite;
}

/// Seite einer Rosenweg-App fuer Handy und Desktop:
///
/// * Handy (schmal): AppBar oben, mit zwei oder mehr [ziele] eine
///   NavigationBar unten — wie bisher.
/// * Desktop (ab 840 px): dieselbe AppBar, die Ziele als NavigationRail
///   links (ab 1200 px mit Beschriftung), der Inhalt mit hoechstens
///   [maxBreite] in der Mitte.
///
/// Ohne [ziele] (eine einzige Seite) steht [inhalt] im Gerüst; mit [ziele]
/// wird [inhalt] nicht gebraucht.
class RosenwegGeruest extends StatefulWidget {
  const RosenwegGeruest({
    super.key,
    required this.titel,
    this.logo,
    this.aktionen,
    this.ziele = const [],
    this.inhalt,
    this.maxBreite = RosenwegInhalt.standardBreite,
    this.knopf,
    this.anfangsZiel = 0,
  });

  final Widget titel;

  /// Links in der AppBar (z. B. das App-Logo).
  final Widget? logo;
  final List<Widget>? aktionen;
  final List<GeruestZiel> ziele;
  final Widget? inhalt;

  /// null = volle Breite (z. B. eigene [RosenwegSpalten]).
  final double? maxBreite;

  /// FloatingActionButton.
  final Widget? knopf;
  final int anfangsZiel;

  @override
  State<RosenwegGeruest> createState() => _RosenwegGeruestState();
}

class _RosenwegGeruestState extends State<RosenwegGeruest> {
  late int _ziel = widget.anfangsZiel;

  @override
  Widget build(BuildContext context) {
    final klasse = Fensterklasse.von(context);
    final ziele = widget.ziele;
    final mitNavigation = ziele.length >= 2;
    final i = _ziel.clamp(0, ziele.isEmpty ? 0 : ziele.length - 1);
    Widget seite = ziele.isEmpty ? (widget.inhalt ?? const SizedBox.shrink()) : Builder(key: ValueKey(i), builder: ziele[i].seite);
    final b = widget.maxBreite;
    if (b != null) seite = RosenwegInhalt(maxBreite: b, child: seite);

    final appBar = AppBar(
      leading: widget.logo == null ? null : Padding(padding: const EdgeInsets.all(8), child: widget.logo),
      title: widget.titel,
      actions: widget.aktionen,
    );
    void waehlen(int n) => setState(() => _ziel = n);

    if (klasse.istBreit && mitNavigation) {
      final lang = klasse == Fensterklasse.sehrBreit;
      return Scaffold(
        appBar: appBar,
        floatingActionButton: widget.knopf,
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NavigationRail(
            extended: lang,
            labelType: lang ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            selectedIndex: i,
            onDestinationSelected: waehlen,
            destinations: [
              for (final z in ziele)
                NavigationRailDestination(
                  icon: Icon(z.symbol),
                  selectedIcon: Icon(z.gewaehltSymbol ?? z.symbol),
                  label: Text(z.titel),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: seite),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      floatingActionButton: widget.knopf,
      body: seite,
      bottomNavigationBar: mitNavigation
          ? NavigationBar(
              selectedIndex: i,
              onDestinationSelected: waehlen,
              destinations: [
                for (final z in ziele)
                  NavigationDestination(
                    icon: Icon(z.symbol),
                    selectedIcon: Icon(z.gewaehltSymbol ?? z.symbol),
                    label: z.titel,
                  ),
              ],
            )
          : null,
    );
  }
}
