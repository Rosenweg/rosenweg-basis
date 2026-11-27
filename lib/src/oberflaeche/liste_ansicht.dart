// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../liste.dart';
import 'bausteine.dart';
import 'geruest.dart';

/// Eine Spalte der Desktop-Tabelle von [RosenwegListe].
class ListenSpalte<T> {
  const ListenSpalte({
    required this.id,
    required this.titel,
    this.text,
    this.zelle,
    this.flex = 1,
    this.breite,
    this.sortierbar = false,
    this.rechts = false,
  }) : assert(text != null || zelle != null, 'text oder zelle angeben');

  /// Fuer die Sortierung ([ListenSteuerung.sortieren]).
  final String id;
  final String titel;
  final String Function(T eintrag)? text;
  final Widget Function(BuildContext context, T eintrag)? zelle;
  final int flex;

  /// Feste Breite statt [flex].
  final double? breite;
  final bool sortierbar;

  /// Rechtsbuendig (Betraege, Zahlen).
  final bool rechts;
}

/// Liste fuer Handy und Desktop mit Suche, Filter-Chips, Ziehen zum
/// Neuladen, "Weitere laden" und Mehrfachauswahl.
///
/// * Handy / schmales Fenster: [kachel] je Eintrag (meist ein `ListTile`
///   ohne eigenes `onTap` — Tippen ruft [antippen]); lange druecken waehlt
///   aus, wenn [mehrfachauswahl].
/// * Desktop (ab 840 px) mit [spalten]: Tabelle mit Kopfzeile (Klick auf
///   sortierbare Spalten sortiert), Zeilen zum Anklicken, Kaestchen zur
///   Auswahl; F5 oder Strg+R laedt neu, Knopf "Neu laden" neben der Suche.
///
/// Laedt beim ersten Anzeigen selbst. Leere Liste, Fehler, Laden sehen in
/// allen Apps gleich aus.
class RosenwegListe<T> extends StatefulWidget {
  const RosenwegListe({
    super.key,
    required this.steuerung,
    required this.kachel,
    this.spalten = const [],
    this.antippen,
    this.mitSuche = true,
    this.suchHinweis = 'Suchen',
    this.mehrfachauswahl = false,
    this.auswahlAktionen,
    this.leerText = 'Noch keine Einträge.',
    this.nichtsGefundenText = 'Nichts gefunden. Suche oder Filter ändern.',
    this.leerSymbol = Icons.inbox_outlined,
    this.kopf,
    this.zaehler = true,
  });

  final ListenSteuerung<T> steuerung;
  final Widget Function(BuildContext context, T eintrag) kachel;
  final List<ListenSpalte<T>> spalten;
  final void Function(T eintrag)? antippen;
  final bool mitSuche;
  final String suchHinweis;
  final bool mehrfachauswahl;

  /// Knoepfe in der Auswahl-Leiste (z. B. Loeschen); bekommen die Auswahl.
  final List<Widget> Function(BuildContext context, List<T> auswahl)? auswahlAktionen;
  final String leerText;
  final String nichtsGefundenText;
  final IconData leerSymbol;

  /// Ueber der Liste, unter der Suche (z. B. ein Hinweis).
  final Widget? kopf;

  /// "42 Einträge" unter der Suche.
  final bool zaehler;

  @override
  State<RosenwegListe<T>> createState() => _RosenwegListeState<T>();
}

class _RosenwegListeState<T> extends State<RosenwegListe<T>> {
  final _suche = TextEditingController();
  final _scroll = ScrollController();

  ListenSteuerung<T> get _s => widget.steuerung;

  @override
  void initState() {
    super.initState();
    _suche.text = _s.suche;
    _scroll.addListener(_amEnde);
    if (!_s.einmalGeladen && !_s.laedt) _s.neuLaden();
  }

  @override
  void didUpdateWidget(RosenwegListe<T> alt) {
    super.didUpdateWidget(alt);
    if (alt.steuerung != widget.steuerung) {
      _suche.text = _s.suche;
      if (!_s.einmalGeladen && !_s.laedt) _s.neuLaden();
    }
  }

  @override
  void dispose() {
    _suche.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _amEnde() {
    // Nach einem Fehler nur noch per Knopf (sonst endlose Wiederholung)
    if (!_scroll.hasClients || _s.fehlerMehr != null) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 400) _s.mehrLaden();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f5): _s.neuLaden,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): _s.neuLaden,
          const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _s.neuLaden,
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: _s,
            builder: (context, _) => LayoutBuilder(builder: (context, c) {
              final tabelle = widget.spalten.isNotEmpty && Fensterklasse.ausBreite(c.maxWidth).istBreit;
              // Nach dem Bauen: passt alles auf den Schirm, gleich weiterladen
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _s.hatMehr) _amEnde();
              });
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_s.auswahlAktiv) _auswahlLeiste(context) else _sucheUndFilter(context, tabelle),
                ?widget.kopf,
                if (tabelle) _kopfzeile(context),
                Expanded(child: _inhalt(context, tabelle)),
              ]);
            }),
          ),
        ),
      );

  Widget _sucheUndFilter(BuildContext context, bool desktop) {
    final f = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final g = _s.gesamt ?? (_s.hatMehr ? null : _s.eintraege.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.mitSuche || desktop)
          Row(children: [
            if (widget.mitSuche)
              Expanded(
                child: TextField(
                  controller: _suche,
                  onChanged: _s.suchen,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.suchHinweis,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _suche.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche leeren',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _suche.clear();
                              _s.suchen('');
                            },
                          ),
                  ),
                ),
              )
            else
              const Spacer(),
            if (desktop) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Neu laden (F5)',
                onPressed: _s.laedt ? null : _s.neuLaden,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ]),
        if (_s.filter.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final fi in _s.filter)
              FilterChip(
                label: Text(fi.titel),
                selected: _s.filterAn.contains(fi.id),
                onSelected: (_) => _s.filterUmschalten(fi.id),
              ),
          ]),
        ],
        if (widget.zaehler && _s.einmalGeladen && g != null) ...[
          const SizedBox(height: 6),
          Text(g == 1 ? '1 Eintrag' : '$g Einträge', style: t.bodySmall?.copyWith(color: f.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _auswahlLeiste(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final a = _s.ausgewaehlt;
    return Material(
      color: f.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          IconButton(tooltip: 'Auswahl aufheben', onPressed: _s.auswahlLeeren, icon: const Icon(Icons.close)),
          Expanded(child: Text('${a.length} ausgewählt', style: TextStyle(color: f.onSecondaryContainer))),
          TextButton(onPressed: _s.alleAuswaehlen, child: const Text('Alle')),
          ...?widget.auswahlAktionen?.call(context, a),
        ]),
      ),
    );
  }

  Widget _kopfzeile(BuildContext context) {
    final t = Theme.of(context).textTheme.labelLarge;
    final f = Theme.of(context).colorScheme;
    final so = _s.sortierung;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: f.outlineVariant))),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 44,
      child: Row(children: [
        if (widget.mehrfachauswahl) const SizedBox(width: 48),
        for (final sp in widget.spalten)
          _breite(
            sp,
            InkWell(
              onTap: sp.sortierbar && _s.sortierbar(sp.id) ? () => _s.sortieren(sp.id) : null,
              child: Row(mainAxisAlignment: sp.rechts ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
                Flexible(child: Text(sp.titel, style: t, overflow: TextOverflow.ellipsis)),
                if (so?.spalte == sp.id)
                  Icon(so!.aufsteigend ? Icons.arrow_upward : Icons.arrow_downward, size: 16, semanticLabel: so.aufsteigend ? 'aufsteigend' : 'absteigend'),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _breite(ListenSpalte<T> sp, Widget kind) {
    final innen = Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: kind);
    return sp.breite != null ? SizedBox(width: sp.breite, child: innen) : Expanded(flex: sp.flex, child: innen);
  }

  Widget _inhalt(BuildContext context, bool tabelle) {
    final s = _s;
    if (!s.einmalGeladen) {
      if (s.fehler != null) return FehlerAnzeige(text: fehlerText(s.fehler!), nochmals: s.neuLaden);
      return const LadeAnzeige();
    }
    final e = s.eintraege;
    final Widget liste;
    if (e.isEmpty) {
      final leer = _Leer(
        symbol: s.sucheOderFilter ? Icons.search_off : widget.leerSymbol,
        text: s.sucheOderFilter ? widget.nichtsGefundenText : widget.leerText,
      );
      // Auch leer ziehbar (neu laden)
      liste = LayoutBuilder(
        builder: (context, c) => ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          SizedBox(height: c.maxHeight, child: leer),
        ]),
      );
    } else {
      final ende = s.hatMehr || s.fehlerMehr != null;
      liste = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: e.length + (ende ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == e.length) return _fuss(context);
          return tabelle ? _zeile(context, e[i], i) : _kachel(context, e[i]);
        },
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.laedt) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
      if (s.fehler != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Hinweis('Neu laden ging nicht: ${fehlerText(s.fehler!)}', art: HinweisArt.fehler),
        ),
      Expanded(child: RefreshIndicator(onRefresh: s.neuLaden, child: liste)),
    ]);
  }

  Widget _fuss(BuildContext context) {
    final s = _s;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: s.fehlerMehr != null
            ? Column(children: [
                Text(fehlerText(s.fehlerMehr!), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: s.mehrLaden, icon: const Icon(Icons.refresh), label: const Text('Nochmals')),
              ])
            : s.laedtMehr
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(onPressed: s.mehrLaden, child: const Text('Weitere laden')),
      ),
    );
  }

  void _tippen(T e) {
    if (_s.auswahlAktiv && widget.mehrfachauswahl) {
      _s.auswaehlen(e);
    } else {
      widget.antippen?.call(e);
    }
  }

  Widget _kachel(BuildContext context, T e) {
    final gewaehlt = _s.istAusgewaehlt(e);
    final k = widget.kachel(context, e);
    return Material(
      color: gewaehlt ? Theme.of(context).colorScheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: widget.antippen == null && !_s.auswahlAktiv ? null : () => _tippen(e),
        onLongPress: widget.mehrfachauswahl ? () => _s.auswaehlen(e) : null,
        child: k,
      ),
    );
  }

  Widget _zeile(BuildContext context, T e, int i) {
    final f = Theme.of(context).colorScheme;
    final gewaehlt = _s.istAusgewaehlt(e);
    return Material(
      color: gewaehlt ? f.secondaryContainer : (i.isOdd ? f.surfaceContainerLowest : Colors.transparent),
      child: InkWell(
        onTap: widget.antippen == null && !_s.auswahlAktiv ? null : () => _tippen(e),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: f.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(children: [
            if (widget.mehrfachauswahl)
              SizedBox(width: 48, child: Checkbox(value: gewaehlt, onChanged: (v) => _s.auswaehlen(e, v ?? false))),
            for (final sp in widget.spalten)
              _breite(
                sp,
                Align(
                  alignment: sp.rechts ? Alignment.centerRight : Alignment.centerLeft,
                  child: sp.zelle?.call(context, e) ?? Text(sp.text!(e), overflow: TextOverflow.ellipsis, maxLines: 2),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Leer extends StatelessWidget {
  const _Leer({required this.symbol, required this.text});
  final IconData symbol;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(symbol, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ]),
        ),
      );
}
