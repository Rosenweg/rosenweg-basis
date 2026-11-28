// SPDX-License-Identifier: GPL-3.0-or-later
/// Farbe der App nach der angemeldeten Person (Stefan 28.11.2026): Technik
/// und Praesident gruen, Ausschuss und Verwaltung blau, sonst rot – aber nur,
/// soweit die App fuer sie etwas freischaltet ([RosenwegApp.farbGruppen]).
///
/// * Nach der Anmeldung aus den Rechten (`/api/auth/me`, [RosenwegRechte]).
/// * Abmelden: zurueck auf die Standardfarbe ([RosenwegApp.gruppe]).
/// * Geteilte Telefone: folgt der Person am Telefon (die Rechte laden nach
///   jedem Personenwechsel neu).
/// * Die letzte Farbe wird gemerkt ([AppSpeicher]); der Start zeigt sie
///   sofort, ohne Flackern.
/// * Startsymbol: Android (activity-alias je Farbe) und iOS (alternate icons)
///   wechseln nur, wenn sich die Farbe wirklich aendert. Desktop: nur in der
///   App.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'konfig.dart';
import 'plattform.dart';
import 'protokoll.dart';
import 'rechte.dart';
import 'sitzung.dart';
import 'speicher.dart';

/// Gruppen, die Blau bekommen, wenn die App keine [RosenwegApp.farbRechte]
/// nennt: alle Ausschuesse und Verwaltungen (je STWEG und die alte globale).
bool istAusschussOderVerwaltung(String gruppe) {
  final g = gruppe.toLowerCase();
  return g == 'verwaltung' || g == 'ausschuss' || RegExp(r'^(stweg\d+|meg)-(ausschuss|verwaltung)$').hasMatch(g);
}

/// Farbe fuer [rechte] in [app]; null-Rechte = Standardfarbe.
RosenwegGruppe gruppeAusRechten(RosenwegApp app, Rechte? rechte) {
  final standard = app.standardGruppe;
  final r = rechte;
  if (r == null) return standard;
  final f = app.farbGruppen;
  final gruen = r.alles || r.darfEine(app.farbRechteTechnik);
  if (f.contains(RosenwegGruppe.technik) && gruen) return standard.max(RosenwegGruppe.technik);
  if (f.contains(RosenwegGruppe.verwaltung)) {
    final blau = app.farbRechte.isEmpty ? r.gruppen.any(istAusschussOderVerwaltung) : r.darfEine(app.farbRechte);
    if (blau) return standard.max(RosenwegGruppe.verwaltung);
  }
  return standard;
}

/// Die aktuelle Farbe einer Sitzung ([RosenwegSitzung.farbe]); Widgets
/// lauschen mit `ValueListenableBuilder`.
class GruppenFarbe extends ValueNotifier<RosenwegGruppe> {
  GruppenFarbe(this.sitzung, {AppSpeicher? speicher, Future<bool> Function(RosenwegGruppe neu)? symbolSetzen})
    : _speicher = speicher, // ignore: prefer_initializing_formals
      _symbolSetzen = symbolSetzen, // ignore: prefer_initializing_formals
      super(sitzung.app.standardGruppe) {
    sitzung.addListener(_pruefen);
    sitzung.rechte.addListener(_pruefen);
  }

  final RosenwegSitzung sitzung;
  AppSpeicher? _speicher;
  final Future<bool> Function(RosenwegGruppe neu)? _symbolSetzen;

  static const _schluessel = 'gruppenfarbe';

  RosenwegApp get _app => sitzung.app;

  /// Vergibt die App ueberhaupt andere Farben als die Standardfarbe?
  bool get wechselt => _app.farbGruppen.any((g) => g.index > _app.standardGruppe.index);

  /// Zuletzt gemerkte Farbe uebernehmen (vor dem ersten Bild,
  /// [rosenwegStarten]): kein Aufblitzen der Standardfarbe beim Start.
  Future<void> erinnern() async {
    if (!wechselt) return;
    try {
      final s = _speicher ??= await AppSpeicher.app();
      final g = RosenwegGruppe.ausName('${await s.lesen(_schluessel) ?? ''}');
      if (g != null && _app.farbGruppen.contains(g) && sitzung.phase == Phase.pruefen) value = g;
    } catch (e) {
      Protokoll.schreiben('Gruppenfarbe: gemerkte Farbe nicht lesbar', e);
    }
  }

  void _pruefen() {
    if (!wechselt) return;
    switch (sitzung.phase) {
      case Phase.abgemeldet || Phase.anmelden:
        _setzen(_app.standardGruppe);
      case Phase.bereit:
        final r = sitzung.rechte;
        final stand = r.stand;
        if (stand != null) {
          _setzen(gruppeAusRechten(_app, stand));
        } else if (!r.laedt && r.fehler == null) {
          // Die App laedt die Rechte vielleicht erst spaeter (oder nie): die
          // Farbe braucht sie jetzt. Bis sie da sind, bleibt die bisherige.
          scheduleMicrotask(() {
            if (sitzung.phase == Phase.bereit && !r.geladen && !r.laedt) {
              unawaited(r.laden().then((_) {}, onError: (_) {}));
            }
          });
        }
      case Phase.pruefen || Phase.fehler:
        break; // bisherige Farbe behalten (gemerkt oder zuletzt gesetzt)
    }
  }

  void _setzen(RosenwegGruppe g) {
    if (g == value) return;
    Protokoll.schreiben('Gruppenfarbe ${value.name} -> ${g.name}');
    value = g;
    unawaited(_merken(g));
  }

  Future<void> _merken(RosenwegGruppe g) async {
    try {
      final s = _speicher ??= await AppSpeicher.app();
      final vorher = RosenwegGruppe.ausName('${await s.lesen(_schluessel) ?? ''}') ?? _app.standardGruppe;
      await s.schreiben(_schluessel, g.name);
      // Startsymbol nur bei echtem Wechsel gegenueber dem zuletzt gesetzten
      if (vorher != g) await (_symbolSetzen ?? _standardSymbol)(g);
    } catch (e) {
      Protokoll.schreiben('Gruppenfarbe: merken/Startsymbol ging nicht', e);
    }
  }

  Future<bool> _standardSymbol(RosenwegGruppe g) =>
      RosenwegPlattform.startsymbolSetzen(g.name, standard: _app.standardGruppe.name);

  @override
  void dispose() {
    sitzung.removeListener(_pruefen);
    sitzung.rechte.removeListener(_pruefen);
    super.dispose();
  }
}
