// SPDX-License-Identifier: GPL-3.0-or-later
/// Rosenweg-Karte IN der App lesen (nicht zum Anmelden): Karte anlernen,
/// nachschlagen, zuordnen. Gelesen wird nur die UID (wie UniFi Access).
///
/// | Plattform | Leser | wenn es nicht geht |
/// |---|---|---|
/// | Android | NFC des Handys (Reader-Modus) | „kein NFC“ bzw. „NFC ist ausgeschaltet“ + Knopf zu den Einstellungen |
/// | iOS | Core NFC, auf Knopfdruck | „kein NFC“ (auch ohne NFC-Berechtigung der App) |
/// | Linux, macOS, Windows | USB-NFC-Leser über PC/SC (z. B. ACR122U) | „kein Kartenleser angeschlossen“, erscheint von selbst, sobald einer steckt |
/// | Web | – | „lassen sich keine Karten lesen“ |
///
/// Wer will, darf die UID auch eintippen ([karteLesen] mit `eintippen: true`).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../anmeldung/kartenleser.dart';
import '../plattform.dart';

/// Karte lesen und die UID zurueckgeben (null = abgebrochen).
///
/// * [hinweis]: eigener Satz statt „Karte an den Leser halten“.
/// * [eintippen]: Knopf „Nummer eintippen“ (Seriennummer von Hand, z. B.
///   wenn kein Leser da ist).
/// * [pruefen]: eigener Test der UID; liefert einen Satz, wenn sie nicht
///   passt (dann wird weiter gelesen).
Future<String?> karteLesen(
  BuildContext context, {
  String titel = 'Karte lesen',
  String? hinweis,
  bool eintippen = false,
  String? Function(String uid)? pruefen,
  Kartenleser? leser,
}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => KarteLesenSeite(titel: titel, hinweis: hinweis, eintippen: eintippen, pruefen: pruefen, leser: leser),
    ));

/// Ganze Seite fuer [karteLesen].
class KarteLesenSeite extends StatefulWidget {
  const KarteLesenSeite({super.key, this.titel = 'Karte lesen', this.hinweis, this.eintippen = false, this.pruefen, this.leser});
  final String titel;
  final String? hinweis;
  final bool eintippen;
  final String? Function(String uid)? pruefen;
  final Kartenleser? leser;

  @override
  State<KarteLesenSeite> createState() => _KarteLesenSeiteState();
}

class _KarteLesenSeiteState extends State<KarteLesenSeite> {
  String? _falsch;
  bool _fertig = false;

  void _karte(String uid) {
    if (_fertig) return;
    final f = widget.pruefen?.call(uid);
    if (f != null) {
      setState(() => _falsch = f);
      return;
    }
    _fertig = true;
    Navigator.of(context).pop(uid);
  }

  Future<void> _eintippen() async {
    final u = await uidEintippen(context);
    if (u != null && mounted) _karte(u);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.titel)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              KartenleserBereich(leser: widget.leser, hinweis: widget.hinweis, beiKarte: _karte),
              if (_falsch != null) ...[
                const SizedBox(height: 16),
                Text(_falsch!, key: const Key('karte-falsch'), textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)),
              ],
              if (widget.eintippen) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _eintippen,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Nummer eintippen'),
                ),
              ],
            ]),
          ),
        ),
      );
}

/// Seriennummer (UID) von Hand: 8, 14 oder 20 Hex-Zeichen; Doppelpunkte und
/// Leerzeichen sind erlaubt. null = abgebrochen.
Future<String?> uidEintippen(BuildContext context) => showDialog<String>(context: context, builder: (_) => const _UidDialog());

class _UidDialog extends StatefulWidget {
  const _UidDialog();
  @override
  State<_UidDialog> createState() => _UidDialogState();
}

class _UidDialogState extends State<_UidDialog> {
  final _feld = TextEditingController();
  String? _fehler;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  void _ok() {
    final u = karteUidNormal(_feld.text);
    if (u == null) {
      setState(() => _fehler = 'Das ist keine Kartennummer. Sie hat 8, 14 oder 20 Zeichen (0–9, A–F), z. B. 04D4C227C22A81.');
      return;
    }
    Navigator.of(context).pop(u);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Kartennummer eintippen'),
        content: TextField(
          key: const Key('uid-feld'),
          controller: _feld,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Seriennummer (UID)', errorText: _fehler, errorMaxLines: 3),
          onSubmitted: (_) => _ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          FilledButton(key: const Key('uid-ok'), onPressed: _ok, child: const Text('Übernehmen')),
        ],
      );
}

/// Liest Karten, solange er sichtbar ist, und zeigt dabei, was zu tun ist
/// oder warum es gerade nicht geht. Jede neu aufgelegte Karte kommt einmal
/// an [beiKarte] (dieselbe Karte erst wieder nach Wegnehmen).
///
/// Ohne Leser prueft er alle [takt] nochmals (Leser eingesteckt, NFC
/// eingeschaltet) und liest dann von selbst.
class KartenleserBereich extends StatefulWidget {
  const KartenleserBereich({
    super.key,
    required this.beiKarte,
    this.leser,
    this.hinweis,
    this.aktiv = true,
    this.takt = const Duration(seconds: 2),
  });

  final void Function(String uid) beiKarte;

  /// null = [Kartenleser.fuerApp].
  final Kartenleser? leser;
  final String? hinweis;

  /// false: nicht lesen (z. B. waehrend eine Anfrage laeuft).
  final bool aktiv;
  final Duration takt;

  @override
  State<KartenleserBereich> createState() => _KartenleserBereichState();
}

class _KartenleserBereichState extends State<KartenleserBereich> with WidgetsBindingObserver {
  late final Kartenleser? _leser = widget.leser ?? Kartenleser.fuerApp();
  KartenleserHindernis? _hindernis;
  bool _geprueft = false;
  bool _liestIos = false;
  StreamSubscription<String>? _abo;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pruefen();
    _timer = Timer.periodic(widget.takt, (_) => _pruefen());
  }

  @override
  void didUpdateWidget(KartenleserBereich alt) {
    super.didUpdateWidget(alt);
    if (alt.aktiv != widget.aktiv) _lauschenAnpassen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // zurueck aus den NFC-Einstellungen: gleich nochmals schauen
    if (s == AppLifecycleState.resumed) _pruefen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _abo?.cancel();
    super.dispose();
  }

  Future<void> _pruefen() async {
    KartenleserHindernis? h;
    try {
      h = await kartenleserHindernis(_leser);
    } catch (_) {
      h = KartenleserHindernis.keinLeser;
    }
    if (!mounted) return;
    if (h != _hindernis || !_geprueft) {
      setState(() {
        _hindernis = h;
        _geprueft = true;
      });
    }
    _lauschenAnpassen();
  }

  void _lauschenAnpassen() {
    final l = _leser;
    final soll = widget.aktiv && _geprueft && _hindernis == null && l != null && !l.aufKnopfdruck;
    if (soll && _abo == null) {
      _abo = l.lauschen().listen(_karte, onError: (_) {});
    } else if (!soll && _abo != null) {
      _abo!.cancel();
      _abo = null;
    }
  }

  void _karte(String uid) {
    final u = karteUidNormal(uid) ?? uid.toUpperCase();
    if (mounted && widget.aktiv) widget.beiKarte(u);
  }

  Future<void> _iosLesen() async {
    setState(() => _liestIos = true);
    try {
      final u = await _leser!.einmalLesen();
      if (u != null) _karte(u);
    } finally {
      if (mounted) setState(() => _liestIos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (!_geprueft) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final h = _hindernis;
    if (h != null) {
      return Column(key: const Key('kartenleser-hindernis'), mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contactless_outlined, size: 72, color: f.outline),
        const SizedBox(height: 16),
        Text(h.text, textAlign: TextAlign.center, style: t.titleMedium),
        if (h == KartenleserHindernis.nfcAus) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: RosenwegPlattform.nfcEinstellungen,
            icon: const Icon(Icons.settings),
            label: const Text('NFC-Einstellungen öffnen'),
          ),
        ],
      ]);
    }
    final l = _leser!;
    final satz = widget.hinweis ??
        (RosenwegPlattform.istAndroid
            ? 'Karte an die Rückseite des Handys halten.'
            : RosenwegPlattform.istIos
                ? 'Auf „Karte lesen“ tippen und die Karte oben an die Rückseite des iPhones halten.'
                : 'Karte auf den Kartenleser legen.');
    return Column(key: const Key('kartenleser-bereit'), mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.contactless, size: 96, color: widget.aktiv ? f.primary : f.outline),
      const SizedBox(height: 16),
      Text(satz, textAlign: TextAlign.center, style: t.titleLarge),
      if (l.aufKnopfdruck) ...[
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: widget.aktiv && !_liestIos ? _iosLesen : null,
          icon: const Icon(Icons.contactless),
          label: const Text('Karte lesen'),
        ),
      ],
    ]);
  }
}
