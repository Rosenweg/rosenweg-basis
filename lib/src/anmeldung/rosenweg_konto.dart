// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../konfig.dart';
import '../netz/api.dart';
import '../netz/json_anfrage.dart';
import '../plattform.dart';
import '../protokoll.dart';
import 'ruecksprung.dart';
import 'schluesselbund.dart';

/// Anmeldung mit dem Rosenweg-Konto (Authentik "rosenweg-apps", PKCE S256).
///
/// Gespeichert wird nur das Refresh-Token (und wann die Person zuletzt im
/// Browser war), im sicheren Speicher des Systems. Das Access-Token lebt nur
/// im Speicher. Kein Passwort, kein Client-Geheimnis. Nie Tokens loggen.
///
/// Aus rosenweg-vm lib/anmeldung/rosenweg_konto.dart; dazu:
/// - Android-Ruecksprung `<kennung>:/anmeldung` (wie commons-rosenweg),
///   samt Abschluss nach einem Neustart der App ([ausstehendeAbschliessen]);
/// - [anmelden] mit `bestaetigen: true` fuer Aktionen, die eine frische
///   Anmeldung verlangen (Passwortwechsel: API antwortet 403 `reauth`).
class RosenwegKonto implements Zugangsquelle {
  RosenwegKonto(
    this.app, {
    Schluesselbund? speicher,
    Anmeldeweg? weg,
    http.Client? client,
    DateTime Function()? jetzt,
  })  : _speicher = speicher ?? Schluesselbund(app.ordner),
        _weg = weg ?? Anmeldeweg.fuer(app.telefonRuecksprung),
        _client = client ?? http.Client(),
        _jetzt = jetzt ?? DateTime.now;

  final RosenwegApp app;
  final Schluesselbund _speicher;
  final Anmeldeweg _weg;
  final http.Client _client;
  final DateTime Function() _jetzt;

  RosenwegKonfig get _k => app.konfig;

  String? _zugang;
  DateTime _zugangBis = DateTime.fromMillisecondsSinceEpoch(0);
  Ruecksprung? _offen;

  /// Fuer die Anzeige (userinfo); kann fehlen.
  String? name;
  String? email;
  String? benutzername;

  static const _rt = 'refresh_token';
  static const _am = 'angemeldet_am';
  static const _pkce = 'pkce';

  /// Speichert der Schluesselbund nur bis Programmende (Linux ohne Secret Service)?
  bool get nurImSpeicher => _speicher.nurImSpeicher;

  static String _zufall(int n) {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(n, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  /// Gibt es eine (hoechstens 30 Tage alte) Anmeldung?
  Future<bool> get angemeldet async {
    if (await _speicher.lesen(_rt) == null) return false;
    if (await _zuAlt()) {
      await abmelden();
      return false;
    }
    return true;
  }

  Future<bool> _zuAlt() async {
    final am = DateTime.tryParse(await _speicher.lesen(_am) ?? '');
    return am == null || _jetzt().difference(am) > _k.anmeldungHoechstensAlt;
  }

  /// Browser-Anmeldung. Meist ohne Eingabe, weil Authentik im Browser die
  /// Sitzung schon kennt. [bestaetigen]: Authentik fragt erneut nach dem
  /// Ausweis (prompt=login, max_age=0).
  Future<void> anmelden({bool bestaetigen = false}) async {
    final verifier = _zufall(48);
    final state = _zufall(24);
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final rueck = await _weg.vorbereiten();
    _offen = rueck;
    // Auf Telefonen kann Android die App beenden, waehrend der Browser offen
    // ist. Dann braucht der naechste Start Verifier und State, um die
    // Anmeldung abzuschliessen (ausstehendeAbschliessen).
    await _speicher.setzen({
      _pkce: jsonEncode({'verifier': verifier, 'state': state, 'rueck': rueck.adresse}),
    });
    final url = Uri.parse('${_k.authentik}/authorize/').replace(queryParameters: {
      'response_type': 'code',
      'client_id': _k.clientId,
      'redirect_uri': rueck.adresse,
      'scope': _k.scopes,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      if (bestaetigen) 'prompt': 'login',
      if (bestaetigen) 'max_age': '0',
    });
    try {
      final antwort = await rueck.warten(url);
      await _abschliessen(antwort, verifier: verifier, state: state, rueck: rueck.adresse);
    } finally {
      _offen = null;
      await _speicher.setzen({_pkce: null});
    }
  }

  /// Knopf "Abbrechen" waehrend die Anmeldeseite offen ist.
  void abbrechen() => _offen?.abbrechen();

  /// Android: kam der Ruecksprung, waehrend die App beendet war? Dann jetzt
  /// abschliessen. true = dabei angemeldet. Auf Desktops immer false.
  Future<bool> ausstehendeAbschliessen() async {
    if (!RosenwegPlattform.istAndroid) return false;
    final u = await RosenwegPlattform.ruecksprungAusstehend();
    final roh = await _speicher.lesen(_pkce);
    if (u == null || roh == null) return false;
    try {
      final p = jsonDecode(roh) as Map<String, dynamic>;
      await _abschliessen(Uri.parse(u),
          verifier: p['verifier'] as String, state: p['state'] as String, rueck: p['rueck'] as String);
      return true;
    } finally {
      await _speicher.setzen({_pkce: null});
    }
  }

  Future<void> _abschliessen(Uri antwort, {required String verifier, required String state, required String rueck}) async {
    final q = antwort.queryParameters;
    if (q['error'] != null || q['code'] == null) throw AnmeldeFehler('Anmeldung abgebrochen');
    if (q['state'] != state) throw AnmeldeFehler('Anmeldung abgelaufen, bitte nochmals');
    final j = await _token({
      'grant_type': 'authorization_code',
      'code': q['code']!,
      'redirect_uri': rueck,
      'client_id': _k.clientId,
      'code_verifier': verifier,
    });
    if (j == null) throw AnmeldeFehler('Rosenweg-Anmeldung fehlgeschlagen');
    await _uebernehmen(j);
    await _speicher.setzen({_am: _jetzt().toUtc().toIso8601String()});
    await _profil();
    Protokoll.schreiben('Angemeldet');
  }

  /// Gueltiges Access-Token; erneuert es bei Bedarf. null = nicht angemeldet.
  @override
  Future<String?> zugangsToken() async {
    if (_zugang != null && _jetzt().isBefore(_zugangBis.subtract(const Duration(minutes: 1)))) {
      return _zugang;
    }
    final rt = await _speicher.lesen(_rt);
    if (rt == null) return null;
    if (await _zuAlt()) {
      await abmelden();
      return null;
    }
    final j = await _token({'grant_type': 'refresh_token', 'refresh_token': rt, 'client_id': _k.clientId});
    if (j == null) {
      // Widerrufen oder abgelaufen: ehrlich abmelden statt still weiterprobieren.
      await abmelden();
      return null;
    }
    await _uebernehmen(j);
    if (name == null) await _profil();
    return _zugang;
  }

  @override
  void zugangUngueltig() {
    _zugang = null;
    _zugangBis = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> abmelden() async {
    zugangUngueltig();
    name = email = benutzername = null;
    await _speicher.setzen({_rt: null, _am: null, _pkce: null});
  }

  Future<void> _uebernehmen(Map<String, dynamic> j) async {
    _zugang = j['access_token'] as String;
    _zugangBis = _jetzt().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 300));
    final rt = j['refresh_token'] as String?;
    if (rt != null) await _speicher.setzen({_rt: rt});
  }

  Future<void> _profil() async {
    try {
      final a = await jsonAnfrage(_client, 'Authentik userinfo', () {
        return http.Request('GET', Uri.parse('${_k.authentik}/userinfo/'))
          ..headers['Authorization'] = 'Bearer $_zugang';
      }, versuche: 1);
      final u = a.json;
      if (a.status == 200 && u is Map<String, dynamic>) {
        name = u['name'] as String?;
        email = u['email'] as String?;
        benutzername = u['preferred_username'] as String?;
      }
    } catch (_) {
      // Nur fuer die Anzeige; ohne Namen geht alles weiter.
    }
  }

  /// Token-Endpunkt von Authentik. null = abgelehnt (abgelaufen, widerrufen).
  /// Ist Authentik nur gerade nicht erreichbar (502, HTML, Netz), wirft
  /// [jsonAnfrage] — dann bleibt die Anmeldung gespeichert, statt dass ein
  /// kurzer Neustart des Servers die Person abmeldet.
  Future<Map<String, dynamic>?> _token(Map<String, String> felder) async {
    final a = await jsonAnfrage(_client, 'Authentik Token', () {
      return http.Request('POST', Uri.parse('${_k.authentik}/token/'))
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8'
        ..body = Uri(queryParameters: felder).query;
    });
    if (a.status == 200 && a.json is Map<String, dynamic>) return a.json as Map<String, dynamic>;
    // Token nie protokollieren; Status genuegt.
    Protokoll.schreiben('Authentik Token: abgelehnt (Status ${a.status})');
    return null;
  }
}

class AnmeldeFehler implements Exception {
  AnmeldeFehler(this.text);
  final String text;
  @override
  String toString() => text;
}
