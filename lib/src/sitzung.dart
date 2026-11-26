// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/foundation.dart';

import 'anmeldung/rosenweg_konto.dart';
import 'anmeldung/ruecksprung.dart';
import 'konfig.dart';
import 'netz/api.dart';
import 'plattform.dart';
import 'protokoll.dart';

enum Phase {
  /// Start: gespeicherte Anmeldung pruefen.
  pruefen,

  /// Keine (oder eine ueber 30 Tage alte) Anmeldung: Knopf "Anmelden".
  abgemeldet,

  /// Anmeldeseite ist im Browser offen.
  anmelden,

  /// Angemeldet; die App zeigt ihren Inhalt.
  bereit,

  /// Etwas ging schief; Text in [RosenwegSitzung.fehler], Knopf "Nochmals".
  fehler,
}

/// Der Anmelde-Ablauf einer App an einer Stelle.
///
///   Telefon mit Rosenweg Geraet (geteilt) → Anfragen ueber Geraet, keine eigene Anmeldung
///   sonst → Rosenweg-Konto (still, wenn <= 30 Tage) → bereit
///
/// Die App liest [api] und baut ihre Seiten; [AnmeldeTor] zeigt davor
/// Anmeldeschirm, Warten und Fehler.
class RosenwegSitzung extends ChangeNotifier {
  RosenwegSitzung(this.app, {RosenwegKonto? konto, Transport? transport, Future<bool> Function()? geraetDa})
      : konto = konto ?? RosenwegKonto(app),
        _transport = transport, // ignore: prefer_initializing_formals
        _geraetDa = geraetDa ?? _standardGeraetDa;

  final RosenwegApp app;
  final RosenwegKonto konto;
  final Transport? _transport;
  final Future<bool> Function() _geraetDa;

  static Future<bool> _standardGeraetDa() async => RosenwegPlattform.istAndroid && await RosenwegPlattform.geraetDa();

  Phase phase = Phase.pruefen;
  String? fehler;

  /// Geteiltes Telefon: Rosenweg Geraet meldet an und ab, nicht die App.
  bool geteiltesTelefon = false;

  late RosenwegApi api = _apiFuer(_transport ?? HttpTransport(basis: app.konfig.api, zugang: konto));

  RosenwegApi _apiFuer(Transport t) => RosenwegApi(t, nichtAngemeldet: _nichtMehrAngemeldet);

  void _setzen(Phase p, [String? f]) {
    if (p != phase || f != null) Protokoll.schreiben('Phase ${p.name}${f != null ? ' — $f' : ''}');
    phase = p;
    fehler = f;
    notifyListeners();
  }

  Future<void> starten() async {
    try {
      _setzen(Phase.pruefen);
      if (_transport != null) {
        // Fester Transport (Tests, Vorfuehrdaten): keine Anmeldung noetig.
        _setzen(Phase.bereit);
        return;
      }
      if (await _geraetDa()) {
        geteiltesTelefon = true;
        api = _apiFuer(GeraetTransport(app.kennung));
        _setzen(Phase.bereit);
        return;
      }
      if (await konto.ausstehendeAbschliessen() || await konto.angemeldet) {
        _setzen(Phase.bereit);
      } else {
        _setzen(Phase.abgemeldet);
      }
    } catch (e) {
      _setzen(Phase.fehler, '$e');
    }
  }

  /// Knopf "Mit Rosenweg-Konto anmelden".
  Future<void> anmelden() async {
    try {
      _setzen(Phase.anmelden);
      await konto.anmelden();
      _setzen(Phase.bereit);
    } on AnmeldungAbgebrochen {
      _setzen(Phase.abgemeldet);
    } catch (e) {
      _setzen(Phase.fehler, '$e');
    }
  }

  /// Knopf "Abbrechen" waehrend die Anmeldeseite offen ist.
  void abbrechen() => konto.abbrechen();

  /// Frische Anmeldung fuer heikle Aktionen (API: 403 mit `reauth`). Die
  /// App bleibt dabei sichtbar; true = bestaetigt.
  Future<bool> bestaetigen() async {
    if (geteiltesTelefon) return false;
    try {
      await konto.anmelden(bestaetigen: true);
      return true;
    } on AnmeldungAbgebrochen {
      return false;
    }
  }

  Future<void> abmelden() async {
    if (geteiltesTelefon) return;
    await konto.abmelden();
    _setzen(Phase.abgemeldet);
  }

  void _nichtMehrAngemeldet() {
    if (geteiltesTelefon) return; // Geraet entscheidet; die App zeigt die Meldung
    if (phase == Phase.bereit) {
      konto.abmelden();
      _setzen(Phase.abgemeldet);
    }
  }

  /// Nicht aufgefangener Fehler (rosenwegStarten): sichtbar machen statt
  /// still weiterlaufen. Den Pfad der Logdatei mit anzeigen.
  void unerwartet(Object e) {
    final p = Protokoll.pfad;
    _setzen(Phase.fehler, '$e${p != null ? '\n\nEinzelheiten: $p' : ''}');
  }
}
