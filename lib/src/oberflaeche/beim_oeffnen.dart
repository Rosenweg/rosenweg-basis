// SPDX-License-Identifier: GPL-3.0-or-later
/// "Abfrage beim Oeffnen" – solange es keine Push-Nachrichten fuer die Apps
/// gibt (kein ntfy, Entscheid Stefan 27.11.2026), fragt eine App selbst nach:
/// beim Start, wenn sie wieder in den Vordergrund kommt (Handy: zurueck aus
/// einer anderen App; Desktop: Fenster wieder aktiv) und auf Wunsch alle
/// paar Minuten, solange sie offen ist.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../protokoll.dart';

class BeimOeffnen extends StatefulWidget {
  const BeimOeffnen({
    super.key,
    required this.pruefen,
    required this.child,
    this.mindestAbstand = const Duration(minutes: 1),
    this.alle,
  });

  /// Nachfragen (Fehler werden nur protokolliert).
  final Future<void> Function() pruefen;
  final Widget child;

  /// Zurueck in den Vordergrund zaehlt erst nach so viel Zeit seit der
  /// letzten Abfrage (kein Sturm beim schnellen Hin und Her).
  final Duration mindestAbstand;

  /// Zusaetzlich regelmaessig, solange die App im Vordergrund ist (null = nein).
  final Duration? alle;

  @override
  State<BeimOeffnen> createState() => _BeimOeffnenState();
}

class _BeimOeffnenState extends State<BeimOeffnen> with WidgetsBindingObserver {
  DateTime? _zuletzt;
  bool _laeuft = false;
  Timer? _uhr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jetzt());
    _uhrStellen();
  }

  void _uhrStellen() {
    _uhr?.cancel();
    final a = widget.alle;
    _uhr = a == null ? null : Timer.periodic(a, (_) => _jetzt());
  }

  @override
  void didUpdateWidget(BeimOeffnen alt) {
    super.didUpdateWidget(alt);
    if (alt.alle != widget.alle) _uhrStellen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      final z = _zuletzt;
      if (z == null || DateTime.now().difference(z) >= widget.mindestAbstand) _jetzt();
      _uhrStellen();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _uhr?.cancel();
      _uhr = null;
    }
  }

  Future<void> _jetzt() async {
    if (_laeuft || !mounted) return;
    _laeuft = true;
    _zuletzt = DateTime.now();
    try {
      await widget.pruefen();
    } catch (e) {
      Protokoll.schreiben('Abfrage beim Öffnen', e);
    } finally {
      _laeuft = false;
    }
  }

  @override
  void dispose() {
    _uhr?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
