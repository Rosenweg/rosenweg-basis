// SPDX-License-Identifier: GPL-3.0-or-later
/// Logik fuer lange Listen: seitenweise laden (Cursor oder Offset), suchen,
/// filtern, sortieren, auswaehlen. Die Anzeige dazu ist [RosenwegListe].
///
/// Vertrag mit der API (Plan 4.2.4): `GET …?limit=50&nach=<cursor>` liefert
/// `{<eintraege>: [...], naechster: "<cursor>" | null, gesamt?: 123}`.
/// Wo die API noch `limit/offset` kennt: [Blaettern.offset]. Wo sie alles auf
/// einmal liefert: [ListenSteuerung.lokal] (Suche/Filter/Sortierung in der App).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'netz/api.dart';
import 'netz/fehler.dart';

/// Eine geladene Seite.
class ListenSeite<T> {
  const ListenSeite(this.eintraege, {this.naechster, this.gesamt});
  final List<T> eintraege;

  /// Marke fuer die naechste Seite; null = das war die letzte.
  final String? naechster;

  /// Anzahl aller Treffer, falls die API sie nennt.
  final int? gesamt;
}

/// Sortierung nach einer Spalte.
@immutable
class ListenSortierung {
  const ListenSortierung(this.spalte, {this.aufsteigend = true});
  final String spalte;
  final bool aufsteigend;
  ListenSortierung umgedreht() => ListenSortierung(spalte, aufsteigend: !aufsteigend);

  @override
  bool operator ==(Object other) => other is ListenSortierung && other.spalte == spalte && other.aufsteigend == aufsteigend;
  @override
  int get hashCode => Object.hash(spalte, aufsteigend);
}

/// Was der Lader holen soll.
@immutable
class ListenAnfrage {
  const ListenAnfrage({this.nach, this.suche = '', this.filter = const {}, this.sortierung, this.limit = 50});

  /// Marke aus [ListenSeite.naechster]; null = erste Seite.
  final String? nach;
  final String suche;

  /// Ids der eingeschalteten [ListenFilter].
  final Set<String> filter;
  final ListenSortierung? sortierung;
  final int limit;
}

typedef ListenLader<T> = Future<ListenSeite<T>> Function(ListenAnfrage anfrage);

/// Ein Filter-Chip ueber der Liste ("Offen", "Meine", …).
class ListenFilter<T> {
  const ListenFilter({required this.id, required this.titel, this.passt});
  final String id;
  final String titel;

  /// Nur fuer [ListenSteuerung.lokal]: gehoert der Eintrag dazu? Mehrere
  /// eingeschaltete Filter muessen alle passen.
  final bool Function(T eintrag)? passt;
}

/// Wie die API blaettert.
enum Blaettern {
  /// `nach=<cursor>`, Antwort mit `naechster` (Plan 4.2.4).
  cursor,

  /// `offset=<n>`; naechste Seite, solange eine volle Seite kam bzw. `gesamt`
  /// noch nicht erreicht ist.
  offset,
}

/// Lader fuer einen Listen-Endpunkt der Haupt-API.
///
/// ```dart
/// final lader = apiListe(api, '/api/reklamationen', schluessel: 'reklamationen',
///     wandeln: Reklamation.ausJson, parameter: (a) => {if (a.filter.contains('offen')) 'status': 'offen'});
/// ```
///
/// - [schluessel]: Feld mit der Liste in der Antwort (ohne: Antwort ist eine
///   Liste, oder das erste Listen-Feld).
/// - [suchParameter]: Name fuer den Suchtext (Standard `q`), leer = nicht senden.
/// - Sortierung: `sort=<spalte>&richtung=auf|ab`.
/// - [parameter]: weitere Parameter aus Filter/Sortierung; ueberschreiben
///   die obigen.
ListenLader<T> apiListe<T>(
  RosenwegApi api,
  String pfad, {
  required T Function(Map<String, dynamic> json) wandeln,
  String? schluessel,
  Blaettern blaettern = Blaettern.cursor,
  String suchParameter = 'q',
  Map<String, String> Function(ListenAnfrage anfrage)? parameter,
}) =>
    (a) async {
      final q = <String, String>{
        'limit': '${a.limit}',
        if (a.nach != null) blaettern == Blaettern.cursor ? 'nach' : 'offset': a.nach!,
        if (a.suche.isNotEmpty && suchParameter.isNotEmpty) suchParameter: a.suche,
        if (a.sortierung != null) ...{
          'sort': a.sortierung!.spalte,
          'richtung': a.sortierung!.aufsteigend ? 'auf' : 'ab',
        },
        ...?parameter?.call(a),
      };
      final uri = Uri.parse(pfad);
      final ziel = uri.replace(queryParameters: {...uri.queryParameters, ...q});
      final j = await api.get(ziel.toString());
      return seiteLesen(j, wandeln: wandeln, schluessel: schluessel, anfrage: a, blaettern: blaettern);
    };

/// Antwort eines Listen-Endpunkts lesen (oeffentlich fuer Tests und eigene
/// Lader).
ListenSeite<T> seiteLesen<T>(
  Object? json, {
  required T Function(Map<String, dynamic> json) wandeln,
  String? schluessel,
  ListenAnfrage anfrage = const ListenAnfrage(),
  Blaettern blaettern = Blaettern.cursor,
}) {
  List<dynamic>? roh;
  Map<String, dynamic>? m;
  if (json is List) {
    roh = json;
  } else if (json is Map<String, dynamic>) {
    m = json;
    final s = schluessel;
    if (s != null) {
      if (json[s] is List) roh = json[s] as List;
    } else {
      roh = json.values.whereType<List<dynamic>>().firstOrNull;
    }
  }
  if (roh == null) throw ApiFehler(200, 'Unerwartete Antwort vom Server.', json);
  final eintraege = [for (final e in roh) if (e is Map<String, dynamic>) wandeln(e)];
  final g = m?['gesamt'] ?? m?['total'];
  final gesamt = g is int ? g : (g is String ? int.tryParse(g) : null);
  String? naechster;
  if (blaettern == Blaettern.cursor) {
    final n = m?['naechster'];
    naechster = n == null || n == '' ? null : '$n';
  } else {
    final bisher = int.tryParse(anfrage.nach ?? '') ?? 0;
    final weiter = bisher + roh.length;
    final mehr = gesamt != null ? weiter < gesamt : roh.length >= anfrage.limit;
    naechster = mehr && roh.isNotEmpty ? '$weiter' : null;
  }
  return ListenSeite(eintraege, naechster: naechster, gesamt: gesamt);
}

/// Zustand einer Liste. Mit [lader] blaettert der Server, mit
/// [ListenSteuerung.lokal] liegt alles in der App.
class ListenSteuerung<T> extends ChangeNotifier {
  ListenSteuerung({
    required ListenLader<T> lader,
    this.filter = const [],
    this.schluessel,
    this.limit = 50,
    this.suchVerzoegerung = const Duration(milliseconds: 350),
    ListenSortierung? sortierung,
    Set<String> filterAn = const {},
  })  : _lader = lader, // ignore: prefer_initializing_formals
        _alle = null,
        _suchText = null,
        _sortierer = const {},
        _sortierung = sortierung, // ignore: prefer_initializing_formals
        _filterAn = {...filterAn};

  /// Endpunkt liefert alles auf einmal: Suche in [suchText], Filter mit
  /// [ListenFilter.passt], Sortierung mit [sortierer] (Spalte → Vergleich).
  ListenSteuerung.lokal({
    required Future<List<T>> Function() alle,
    String Function(T eintrag)? suchText,
    Map<String, Comparator<T>> sortierer = const {},
    this.filter = const [],
    this.schluessel,
    ListenSortierung? sortierung,
    Set<String> filterAn = const {},
  })  : _lader = null,
        _alle = alle, // ignore: prefer_initializing_formals
        _suchText = suchText, // ignore: prefer_initializing_formals
        _sortierer = sortierer, // ignore: prefer_initializing_formals
        limit = 0,
        suchVerzoegerung = Duration.zero,
        _sortierung = sortierung, // ignore: prefer_initializing_formals
        _filterAn = {...filterAn};

  final ListenLader<T>? _lader;
  final Future<List<T>> Function()? _alle;
  final String Function(T)? _suchText;
  final Map<String, Comparator<T>> _sortierer;
  final List<ListenFilter<T>> filter;

  /// Eindeutiger Schluessel je Eintrag (fuer die Auswahl); ohne: der Eintrag selbst.
  final Object Function(T eintrag)? schluessel;
  final int limit;
  final Duration suchVerzoegerung;

  List<T> _eintraege = const [];
  List<T>? _geladenAlle;
  String? _naechster;
  int? _gesamt;
  bool _laedt = false;
  bool _laedtMehr = false;
  bool _einmalGeladen = false;
  Object? _fehler;
  Object? _fehlerMehr;
  String _suche = '';
  ListenSortierung? _sortierung;
  final Set<String> _filterAn;
  final Set<Object> _auswahl = {};
  int _runde = 0;
  Timer? _suchUhr;
  bool _weg = false;

  bool get istLokal => _alle != null;
  List<T> get eintraege => _eintraege;
  bool get laedt => _laedt;
  bool get laedtMehr => _laedtMehr;

  /// Schon einmal fertig geladen (sonst: grosse Lade-Anzeige).
  bool get einmalGeladen => _einmalGeladen;

  /// Fehler beim (Neu-)Laden; bei [fehlerMehr] bleibt die Liste stehen.
  Object? get fehler => _fehler;
  Object? get fehlerMehr => _fehlerMehr;
  bool get hatMehr => _naechster != null;

  /// Anzahl aller Treffer (lokal immer bekannt).
  int? get gesamt => _gesamt;
  String get suche => _suche;
  ListenSortierung? get sortierung => _sortierung;
  Set<String> get filterAn => Set.unmodifiable(_filterAn);
  bool get sucheOderFilter => _suche.isNotEmpty || _filterAn.isNotEmpty;

  Object _schluessel(T e) => schluessel?.call(e) ?? e as Object;

  /// Ausgewaehlte Eintraege (in der Reihenfolge der Liste).
  List<T> get ausgewaehlt => [for (final e in _eintraege) if (_auswahl.contains(_schluessel(e))) e];
  bool istAusgewaehlt(T e) => _auswahl.contains(_schluessel(e));
  bool get auswahlAktiv => _auswahl.isNotEmpty;

  void auswaehlen(T e, [bool? an]) {
    final k = _schluessel(e);
    final ja = an ?? !_auswahl.contains(k);
    ja ? _auswahl.add(k) : _auswahl.remove(k);
    notifyListeners();
  }

  void alleAuswaehlen() {
    _auswahl.addAll(_eintraege.map(_schluessel));
    notifyListeners();
  }

  void auswahlLeeren() {
    if (_auswahl.isEmpty) return;
    _auswahl.clear();
    notifyListeners();
  }

  /// Erste Seite (neu) laden; die bisherige Liste bleibt sichtbar, bis die
  /// neue da ist (Ziehen zum Neuladen).
  Future<void> neuLaden() async {
    final runde = ++_runde;
    _laedt = true;
    _fehler = null;
    _fehlerMehr = null;
    _melden();
    try {
      if (istLokal) {
        final alle = await _alle!();
        if (runde != _runde) return;
        _geladenAlle = [...alle];
        _lokalAnwenden();
      } else {
        final s = await _lader!(_anfrage(null));
        if (runde != _runde) return;
        _eintraege = s.eintraege;
        _naechster = s.naechster;
        _gesamt = s.gesamt;
      }
      _auswahl.removeWhere((k) => !_eintraege.any((e) => _schluessel(e) == k));
      _einmalGeladen = true;
    } catch (e) {
      if (runde != _runde) return;
      _fehler = e;
    } finally {
      if (runde == _runde) {
        _laedt = false;
        _melden();
      }
    }
  }

  /// Naechste Seite anhaengen (am Ende der Liste oder Knopf "Weitere laden").
  Future<void> mehrLaden() async {
    final n = _naechster;
    if (n == null || _laedtMehr || _laedt || istLokal) return;
    final runde = _runde;
    _laedtMehr = true;
    _fehlerMehr = null;
    _melden();
    try {
      final s = await _lader!(_anfrage(n));
      if (runde != _runde) return;
      _eintraege = [..._eintraege, ...s.eintraege];
      _naechster = s.naechster;
      _gesamt = s.gesamt ?? _gesamt;
    } catch (e) {
      if (runde != _runde) return;
      _fehlerMehr = e;
    } finally {
      if (runde == _runde) {
        _laedtMehr = false;
        _melden();
      }
    }
  }

  /// Suchtext; laedt (verzoegert) neu bzw. filtert lokal sofort.
  void suchen(String text) {
    final t = text.trim();
    if (t == _suche) return;
    _suche = t;
    _suchUhr?.cancel();
    if (istLokal) {
      _lokalAnwenden();
      _melden();
    } else {
      _melden();
      _suchUhr = Timer(suchVerzoegerung, neuLaden);
    }
  }

  void filterUmschalten(String id) {
    _filterAn.contains(id) ? _filterAn.remove(id) : _filterAn.add(id);
    _geaendert();
  }

  /// Nach [spalte] sortieren; nochmals dieselbe Spalte = umgekehrt.
  void sortieren(String spalte) {
    final s = _sortierung;
    _sortierung = s != null && s.spalte == spalte ? s.umgedreht() : ListenSortierung(spalte);
    _geaendert();
  }

  /// Kann nach [spalte] sortiert werden? (lokal: nur mit Vergleich)
  bool sortierbar(String spalte) => !istLokal || _sortierer.containsKey(spalte);

  /// Einen Eintrag ersetzen (nach dem Bearbeiten), ohne neu zu laden.
  void ersetzen(T alt, T neu) {
    final k = _schluessel(alt);
    _eintraege = [for (final e in _eintraege) _schluessel(e) == k ? neu : e];
    final a = _geladenAlle;
    if (a != null) _geladenAlle = [for (final e in a) _schluessel(e) == k ? neu : e];
    _melden();
  }

  /// Einen Eintrag entfernen (nach dem Loeschen), ohne neu zu laden.
  void entfernen(T eintrag) {
    final k = _schluessel(eintrag);
    _eintraege = [for (final e in _eintraege) if (_schluessel(e) != k) e];
    _geladenAlle?.removeWhere((e) => _schluessel(e) == k);
    _auswahl.remove(k);
    if (_gesamt != null && !istLokal) _gesamt = _gesamt! - 1;
    if (istLokal) _gesamt = _eintraege.length;
    _melden();
  }

  void _geaendert() {
    if (istLokal) {
      _lokalAnwenden();
      _melden();
    } else {
      neuLaden();
    }
  }

  ListenAnfrage _anfrage(String? nach) =>
      ListenAnfrage(nach: nach, suche: _suche, filter: {..._filterAn}, sortierung: _sortierung, limit: limit);

  void _lokalAnwenden() {
    final alle = _geladenAlle ?? const [];
    final s = _suche.toLowerCase();
    final aktiv = [for (final f in filter) if (_filterAn.contains(f.id) && f.passt != null) f];
    final text = _suchText;
    var l = [
      for (final e in alle)
        if ((s.isEmpty || text == null || text(e).toLowerCase().contains(s)) && aktiv.every((f) => f.passt!(e))) e
    ];
    final so = _sortierung;
    final vergleich = so == null ? null : _sortierer[so.spalte];
    if (so != null && vergleich != null) {
      l = [...l]..sort((a, b) => so.aufsteigend ? vergleich(a, b) : vergleich(b, a));
    }
    _eintraege = l;
    _naechster = null;
    _gesamt = l.length;
  }

  void _melden() {
    if (!_weg) notifyListeners();
  }

  @override
  void dispose() {
    _weg = true;
    _suchUhr?.cancel();
    super.dispose();
  }
}
