// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../konfig.dart';
import '../netz/api.dart';
import '../netz/fehler.dart';
import '../netz/json_anfrage.dart';
import '../protokoll.dart';
import 'geraet_kennung.dart';
import 'geraete_schluessel.dart';
import 'schluesselbund.dart';

/// Wie eine Karten-Sitzung zustande kam (fuer die Anzeige "Angemeldet mit ...").
enum SitzungsArt {
  /// Rosenweg-Karte (UniFi Access) an den Leser bzw. ans iPhone gehalten.
  karte,

  /// Anmelde-QR aus dem Portal (/smartphones, "App auf eigenem Handy") gescannt.
  qr,

  /// Desktop zeigte einen QR, die Person hat ihn mit dem Handy im Portal bestaetigt.
  handy,
}

/// Code, den der Desktop als QR zeigt ("Mit dem Handy anmelden").
class HandyCode {
  HandyCode({required this.abholCode, required this.benutzerCode, required this.adresse, required this.bis, required this.intervall, required this.schluessel});

  /// Geheim; nur diese App holt damit die Sitzung ab.
  final String abholCode;

  /// Kurz und lesbar (z. B. "K7QM-3XRP"), steht unter dem QR und auf der Portalseite.
  final String benutzerCode;

  /// Inhalt des QR: Portalseite zum Bestaetigen.
  final String adresse;
  final DateTime bis;
  final Duration intervall;
  final GeraeteSchluessel schluessel;
}

/// Stand beim Abholen.
enum HandyStand { wartet, angemeldet, abgelehnt, abgelaufen }

/// Fehler mit einem Satz fuer die Person.
class KartenFehler implements Exception {
  KartenFehler(this.text, {this.status = 0});
  final String text;
  final int status;
  @override
  String toString() => text;
}

/// Anmeldung OHNE Browser fuer Desktop und iOS: Rosenweg-Karte, Anmelde-QR
/// oder "Mit dem Handy anmelden". Gegenstueck zu `KartenSitzung` in
/// commons-rosenweg (Android), gleicher Server (Website
/// api/routes/app-karte.js):
///
/// - Anmelden schickt UID bzw. QR-Token, App, Geraet und den oeffentlichen
///   [GeraeteSchluessel]; zurueck kommen Sitzungs-Id und ein Zugang
///   (`rw_app_...`, 15 Minuten, nur im Speicher).
/// - Erneuern: Herausforderung holen, mit dem Geraeteschluessel
///   unterschreiben. Gespeichert werden Sitzungs-Id und Schluessel im
///   Schluesselbund; die Karten-UID nie.
/// - Jede App hat ihre eigene Sitzung; Abmelden betrifft nur diese App.
///
/// Was diese Sitzung NICHT kann: Dienste, die ein Authentik-Token verlangen
/// (z. B. das vm-gateway von Rosenweg VM) - die Apps blenden dann Karte und
/// QR aus (`RosenwegApp.ohneBrowserWege: false`).
class KartenSitzung implements Zugangsquelle {
  KartenSitzung(this.app,
      {required Schluesselbund speicher, http.Client? client, DateTime Function()? jetzt, Future<String?> Function()? kennung})
      : _speicher = speicher, // ignore: prefer_initializing_formals
        _client = client ?? http.Client(),
        _jetzt = jetzt ?? DateTime.now,
        _kennung = kennung ?? GeraetKennung.lesen;

  final RosenwegApp app;
  final Schluesselbund _speicher;
  final http.Client _client;
  final DateTime Function() _jetzt;
  final Future<String?> Function() _kennung;

  String? name;
  String? email;
  SitzungsArt? art;

  String? _zugang;
  DateTime _zugangBis = DateTime.fromMillisecondsSinceEpoch(0);

  static const _sitzung = 'ks_sitzung';
  static const _schluessel = 'ks_schluessel';
  static const _name = 'ks_name';
  static const _email = 'ks_email';
  static const _art = 'ks_art';
  static const _zufall = 'geraet_zufall';

  /// Praefix des Anmelde-QR fuer Apps (geteilte Telefone: RWTEL1:, nicht austauschbar).
  static const qrPraefix = 'RWAPP1:';
  static const qrPraefixTelefon = 'RWTEL1:';

  String get _api => app.konfig.api;

  /// Gibt es eine Sitzung? Liest dabei Name, E-Mail und Art.
  Future<bool> get angemeldet async {
    if (await _speicher.lesen(_sitzung) == null) return false;
    name = await _speicher.lesen(_name);
    email = await _speicher.lesen(_email);
    art = SitzungsArt.values.asNameMap()[await _speicher.lesen(_art) ?? ''] ?? SitzungsArt.karte;
    return true;
  }

  /// Rosenweg-Karte einloesen. UID als Hex (wie UniFi Access, z. B. 04D4C227C22A81).
  Future<void> mitKarte(String uid) => _anmelden('/api/apps/karte-anmelden', {'uid': uid}, SitzungsArt.karte);

  /// Gescannten Anmelde-QR ("RWAPP1:...") einloesen.
  Future<void> mitQr(String inhalt) {
    final t = inhalt.trim();
    if (t.startsWith(qrPraefixTelefon)) {
      throw KartenFehler('Das ist der QR für geteilte Telefone. Wähle auf rosenweg4303.ch/smartphones „App auf eigenem Handy“.');
    }
    if (!t.startsWith(qrPraefix)) {
      throw KartenFehler('Das ist kein Rosenweg-Anmelde-QR. Öffne rosenweg4303.ch/smartphones und wähle „App auf eigenem Handy“.');
    }
    return _anmelden('/api/apps/qr-anmelden', {'token': t}, SitzungsArt.qr);
  }

  Future<Map<String, Object?>> _geraet() async {
    var kennung = await _kennung();
    if (kennung == null) {
      var z = await _speicher.lesen(_zufall);
      if (z == null) {
        final r = Random.secure();
        z = List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await _speicher.setzen({_zufall: z});
      }
      kennung = GeraetKennung.ausZufall(z);
    }
    return {'kennung': kennung, 'name': await GeraetKennung.name(), 'plattform': GeraetKennung.plattform()};
  }

  Future<Map<String, Object?>> _koerper(GeraeteSchluessel s) async => {
        'app': app.kennung,
        'app_name': app.name,
        'schluessel': s.oeffentlich,
        'geraet': await _geraet(),
      };

  Future<void> _anmelden(String pfad, Map<String, Object?> was, SitzungsArt a) async {
    final s = GeraeteSchluessel.erzeugen();
    final antwort = await _post(pfad, {...was, ...await _koerper(s)});
    final j = antwort.json;
    if (antwort.status != 200 || j is! Map || j['sitzung'] is! String) {
      throw KartenFehler(_fehlertext(j, 'Anmelden fehlgeschlagen (${antwort.status})'), status: antwort.status);
    }
    await _uebernehmen(j.cast<String, Object?>(), s, a);
    Protokoll.schreiben('Angemeldet (${a.name})');
  }

  Future<void> _uebernehmen(Map<String, Object?> j, GeraeteSchluessel s, SitzungsArt a) async {
    _zugangSetzen(j);
    name = j['name'] as String?;
    email = j['email'] as String?;
    art = a;
    await _speicher.setzen({
      _sitzung: j['sitzung'] as String,
      _schluessel: s.privat,
      _name: name,
      _email: email,
      _art: a.name,
    });
  }

  void _zugangSetzen(Map<String, Object?> j) {
    _zugang = j['zugang'] as String?;
    _zugangBis = _jetzt().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 900));
  }

  // ── "Mit dem Handy anmelden" (Desktop zeigt QR, Handy bestaetigt im Portal) ──

  /// Neuen Code holen. Der Schluessel entsteht jetzt; der Server merkt sich
  /// den oeffentlichen Teil bis zur Bestaetigung.
  Future<HandyCode> handyCodeHolen() async {
    final s = GeraeteSchluessel.erzeugen();
    final a = await _post('/api/apps/handy-code', await _koerper(s));
    final j = a.json;
    if (a.status != 200 || j is! Map || j['abhol_code'] is! String) {
      throw KartenFehler(_fehlertext(j, 'Kein Anmeldecode (${a.status})'), status: a.status);
    }
    return HandyCode(
      abholCode: j['abhol_code'] as String,
      benutzerCode: '${j['benutzer_code'] ?? ''}',
      adresse: '${j['adresse'] ?? ''}',
      bis: _jetzt().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 300)),
      intervall: Duration(seconds: (j['intervall'] as num?)?.toInt() ?? 3),
      schluessel: s,
    );
  }

  /// Einmal nachfragen, ob die Person den Code bestaetigt hat.
  Future<HandyStand> handyCodeAbholen(HandyCode c) async {
    if (_jetzt().isAfter(c.bis)) return HandyStand.abgelaufen;
    final a = await _post('/api/apps/handy-code/abholen', {'abhol_code': c.abholCode});
    final j = a.json is Map ? (a.json as Map).cast<String, Object?>() : const <String, Object?>{};
    switch (a.status) {
      case 200 when j['sitzung'] is String:
        await _uebernehmen(j, c.schluessel, SitzungsArt.handy);
        Protokoll.schreiben('Angemeldet (Handy bestaetigt)');
        return HandyStand.angemeldet;
      case 202:
        return HandyStand.wartet;
      case 403:
        return HandyStand.abgelehnt;
      case 404 || 410:
        return HandyStand.abgelaufen;
      default:
        throw KartenFehler(_fehlertext(j, 'Anmelden fehlgeschlagen (${a.status})'), status: a.status);
    }
  }

  // ── Zugang ──

  @override
  Future<String?> zugangsToken() async {
    if (_zugang != null && _jetzt().isBefore(_zugangBis.subtract(const Duration(minutes: 1)))) return _zugang;
    final id = await _speicher.lesen(_sitzung);
    if (id == null) return null;
    final privat = await _speicher.lesen(_schluessel);
    if (privat == null) return _weg('Schluessel fehlt');
    final j = await _erneuern(id, privat);
    if (j == null) return _weg('Sitzung am Server beendet');
    _zugangSetzen(j);
    return _zugang;
  }

  /// Zwei Schritte: Herausforderung, Unterschrift. null = Sitzung beendet
  /// (widerrufen, Karte entzogen, abgelaufen); wirft, wenn nur das Netz fehlt.
  Future<Map<String, Object?>?> _erneuern(String id, String privat) async {
    final h = await _post('/api/apps/sitzung/erneuern', {'sitzung': id});
    if (h.status == 401) return null;
    final hj = h.json;
    if (h.status != 200 || hj is! Map || hj['herausforderung'] is! String) {
      if (h.status == 503) throw ServerNichtErreichbar();
      throw KartenFehler(_fehlertext(hj, 'Erneuern fehlgeschlagen (${h.status})'), status: h.status);
    }
    final herausforderung = hj['herausforderung'] as String;
    final unterschrift = GeraeteSchluessel.unterschreiben(privat, 'rw-app-sitzung-erneuern\n$id\n$herausforderung');
    final a = await _post('/api/apps/sitzung/erneuern', {'sitzung': id, 'herausforderung': herausforderung, 'unterschrift': unterschrift});
    if (a.status == 401) return null;
    if (a.status == 503) throw ServerNichtErreichbar();
    if (a.status != 200 || a.json is! Map) throw KartenFehler(_fehlertext(a.json, 'Erneuern fehlgeschlagen (${a.status})'), status: a.status);
    return (a.json as Map).cast<String, Object?>();
  }

  Future<String?> _weg(String warum) async {
    Protokoll.schreiben('Karten-Sitzung: $warum');
    await _vergessen();
    return null;
  }

  Future<void> _vergessen() async {
    zugangUngueltig();
    name = email = null;
    art = null;
    await _speicher.setzen({_sitzung: null, _schluessel: null, _name: null, _email: null, _art: null});
  }

  @override
  void zugangUngueltig() {
    _zugang = null;
    _zugangBis = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Nur diese App abmelden: hier sofort, am Server so gut es geht (ohne
  /// Schluessel laesst sich die Sitzung ohnehin nicht mehr erneuern).
  Future<void> abmelden() async {
    final id = await _speicher.lesen(_sitzung);
    if (id == null) return;
    final privat = await _speicher.lesen(_schluessel);
    var token = _zugang != null && _jetzt().isBefore(_zugangBis.subtract(const Duration(seconds: 10))) ? _zugang : null;
    await _vergessen();
    try {
      token ??= privat == null ? null : (await _erneuern(id, privat))?['zugang'] as String?;
      if (token != null) await _post('/api/apps/sitzung/abmelden', const {}, token: token);
    } catch (e) {
      Protokoll.schreiben('Abmelden am Server nicht moeglich', e);
    }
  }

  // ── Netz ──

  Future<ApiAntwort> _post(String pfad, Map<String, Object?> koerper, {String? token}) => jsonAnfrage(
        _client,
        'Anmeldung $pfad',
        () {
          final r = http.Request('POST', Uri.parse('$_api$pfad'))
            ..headers['Content-Type'] = 'application/json; charset=utf-8'
            ..headers['Accept'] = 'application/json'
            ..body = jsonEncode(koerper);
          if (token != null) r.headers['Authorization'] = 'Bearer $token';
          return r;
        },
        versuche: 1,
      );

  static String _fehlertext(Object? j, String sonst) => j is Map && j['error'] is String ? j['error'] as String : sonst;
}
