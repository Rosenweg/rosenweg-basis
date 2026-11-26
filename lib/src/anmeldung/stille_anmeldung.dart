// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'kerberos.dart';

/// Eine HTTP-Antwort, wie die stille Anmeldung sie braucht.
class StilleAntwort {
  StilleAntwort(this.status, {this.kopf = const {}, this.cookies = const [], this.text = ''});
  final int status;

  /// Kopfzeilen, Namen klein geschrieben.
  final Map<String, String> kopf;
  final List<Cookie> cookies;
  final String text;
}

/// GET ohne automatisches Folgen von Weiterleitungen; fuer Tests ersetzbar.
typedef StillesHolen = Future<StilleAntwort> Function(Uri url, Map<String, String> kopf);

/// Anmeldung bei Authentik mit dem Kerberos-Ticket der Sitzung, ganz ohne
/// Browser und ohne Eingabe:
///
/// 1. `GET /source/kerberos/<quelle>/` (Kerberos-Quelle `ad-kerberos`):
///    Authentik verlangt "Negotiate", die App schickt das SPNEGO-Token
///    ([KerberosTicket]). Danach steht ein Ablauf an
///    (`default-source-authentication`, nur "Anmelden").
/// 2. Diesen Ablauf ueber die Ablauf-API (`/api/v3/flows/executor/<ablauf>/`)
///    abschliessen, wie es die Anmeldeseite im Browser auch tut. Jetzt hat
///    das Cookie-Glas eine angemeldete Authentik-Sitzung.
/// 3. Die gewohnte PKCE-Autorisierung (`/application/o/authorize/?...`) mit
///    dieser Sitzung. Authentik antwortet mit der Weiterleitung auf die
///    Ruecksprung-Adresse samt `code` — die App liest sie nur, niemand
///    lauscht dort.
///
/// Sobald Authentik etwas fragen will (Passwort, Zustimmung, zweiter
/// Faktor, Fehlerseite), bricht sie ab und gibt null: dann bleibt die
/// gewohnte Anmeldung im Browser. Cookies leben nur in diesem Objekt und
/// verschwinden mit ihm; nichts davon wird gespeichert oder protokolliert.
class StilleAnmeldung {
  StilleAnmeldung({
    required this.authentik,
    required this.quelle,
    required this.dienst,
    KerberosTicket? ticket,
    StillesHolen? holen,
    this.zeit = const Duration(seconds: 20),
  })  : _ticket = ticket ?? KerberosTicket.system(),
        _holen = holen ?? _httpHolen;

  /// Wurzel von Authentik, z. B. `https://authentik.rosenweg4303.ch`.
  final Uri authentik;

  /// Slug der Kerberos-Quelle, z. B. `ad-kerberos`.
  final String quelle;

  /// Kerberos-Principal von Authentik (SPNEGO), z. B.
  /// `HTTP/authentik.rosenweg4303.ch@AD.ROSENWEG4303.CH`.
  final String dienst;

  /// Hoechstens so lange insgesamt (Ticket + alle Anfragen).
  final Duration zeit;

  final KerberosTicket _ticket;
  final StillesHolen _holen;
  final _glas = <String, String>{};

  /// Warum der letzte Versuch nicht ging (fuer das Protokoll, ohne Geheimnisse).
  String grund = '';

  static const _hoechstensSchritte = 25;

  /// Fuehrt die Anmeldung fuer [autorisierung] (volle authorize-Adresse mit
  /// PKCE und state) durch. Ergebnis: die Ruecksprung-Adresse mit `code`
  /// (oder `error`), oder null = nicht still moeglich.
  Future<Uri?> ausfuehren(Uri autorisierung, String rueckAdresse) async {
    try {
      return await _ablauf(autorisierung, rueckAdresse).timeout(zeit);
    } on TimeoutException {
      grund = 'Zeit um';
      return null;
    } catch (e) {
      grund = 'Fehler: ${e.runtimeType}';
      return null;
    }
  }

  Future<Uri?> _ablauf(Uri autorisierung, String rueck) async {
    final spnego = authentik.replace(path: '/source/kerberos/$quelle/');
    // Schritt 1+2: an Authentik anmelden.
    final angemeldet = await _folgen(spnego, rueck, kerberos: true);
    if (angemeldet == null) return null;
    if (angemeldet is _Ziel) {
      grund = 'unerwartet: Ruecksprung schon bei der Anmeldung';
      return null;
    }
    // Schritt 3: autorisieren.
    final r = await _folgen(autorisierung, rueck, kerberos: false);
    if (r is _Ziel) return r.url;
    if (r != null) grund = 'Autorisierung endete ausserhalb des Ablaufs';
    return null;
  }

  /// Folgt Weiterleitungen und Ablauf-Schritten, bis
  /// - die Ruecksprung-Adresse erreicht ist ([_Ziel]),
  /// - ein Ziel ausserhalb der Anmeldung erreicht ist ([_Fertig], z. B.
  ///   `/if/user/` nach der Kerberos-Anmeldung), oder
  /// - Authentik etwas fragen will / ein Fehler kommt (null, [grund]).
  Future<_Ende?> _folgen(Uri start, String rueck, {required bool kerberos}) async {
    var url = start;
    var tokenGeschickt = false;
    String? negotiate;
    for (var i = 0; i < _hoechstensSchritte; i++) {
      final a = await _holen(url, {
        'Accept': 'application/json, text/html;q=0.9',
        'Cookie': ?_cookieKopf(url),
        if (negotiate != null) 'Authorization': 'Negotiate $negotiate',
      });
      negotiate = null;
      _merken(url, a.cookies);

      if (a.status == 401 && kerberos && _verlangtNegotiate(a) && _istSpnego(url)) {
        if (tokenGeschickt) {
          grund = 'Kerberos-Ticket abgelehnt';
          return null;
        }
        negotiate = await _ticket.token(dienst);
        if (negotiate == null) {
          grund = 'kein Kerberos-Ticket (${kerberosLetzterGrund.isEmpty ? 'nicht in der Domaene' : kerberosLetzterGrund})';
          return null;
        }
        tokenGeschickt = true;
        continue; // gleiche Adresse, jetzt mit Token
      }

      String? weiter;
      if (a.status >= 300 && a.status < 400) {
        weiter = a.kopf['location'];
        if (weiter == null) {
          grund = 'Weiterleitung ohne Ziel';
          return null;
        }
      } else if (a.status == 200 && _istAblaufApi(url)) {
        final j = _json(a.text);
        final komponente = j?['component'];
        if (komponente == 'xak-flow-redirect' && j?['to'] is String) {
          weiter = j!['to'] as String;
        } else {
          // ak-stage-identification, -password, -consent, ak-stage-access-denied …
          grund = 'Authentik fragt nach: ${komponente ?? 'unbekannt'}';
          return null;
        }
      } else {
        grund = 'Antwort ${a.status} auf ${url.path}';
        return null;
      }

      final ziel = url.resolve(weiter);
      if (_istRuecksprung(ziel, rueck)) return _Ziel(ziel);
      if (ziel.host != authentik.host || ziel.scheme != authentik.scheme) {
        grund = 'Weiterleitung zu fremdem Ziel';
        return null;
      }
      final ablauf = _ablaufAusOberflaeche(ziel);
      if (ablauf != null) {
        url = ablauf;
      } else if (_gehoertZurAnmeldung(ziel)) {
        url = ziel;
      } else {
        // Ziel ausserhalb der Anmeldung (z. B. /if/user/): angemeldet.
        return kerberos ? _Fertig() : null;
      }
    }
    grund = 'zu viele Schritte';
    return null;
  }

  bool _istSpnego(Uri u) => u.path == '/source/kerberos/$quelle/';
  bool _istAblaufApi(Uri u) => u.path.startsWith('/api/v3/flows/executor/');

  static bool _verlangtNegotiate(StilleAntwort a) =>
      (a.kopf['www-authenticate'] ?? '').toLowerCase().startsWith('negotiate');

  static bool _istRuecksprung(Uri ziel, String rueck) {
    final r = Uri.parse(rueck);
    return ziel.scheme == r.scheme && ziel.host == r.host && ziel.port == r.port && ziel.path == r.path;
  }

  /// `/if/flow/<ablauf>/?…` ist die Anmeldeseite (Javascript) — die App
  /// spricht stattdessen die API dahinter, mit derselben Abfrage.
  Uri? _ablaufAusOberflaeche(Uri u) {
    final m = RegExp(r'^/if/flow/([A-Za-z0-9_-]+)/?$').firstMatch(u.path);
    if (m == null) return null;
    return u.replace(path: '/api/v3/flows/executor/${m[1]}/', queryParameters: {'query': u.query});
  }

  bool _gehoertZurAnmeldung(Uri u) =>
      u.path.startsWith('/application/o/authorize') ||
      u.path.startsWith('/api/v3/flows/executor/') ||
      u.path.startsWith('/flows/') ||
      u.path.startsWith('/source/kerberos/');

  static Map<String, dynamic>? _json(String t) {
    try {
      final j = jsonDecode(t);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  // Cookie-Glas: nur fuer den Authentik-Host, nur im Speicher.
  void _merken(Uri url, List<Cookie> cookies) {
    if (url.host != authentik.host) return;
    for (final c in cookies) {
      if (c.value.isEmpty || (c.maxAge != null && c.maxAge! <= 0)) {
        _glas.remove(c.name);
      } else {
        _glas[c.name] = c.value;
      }
    }
  }

  String? _cookieKopf(Uri url) {
    if (url.host != authentik.host || _glas.isEmpty) return null;
    return _glas.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

sealed class _Ende {}

class _Ziel extends _Ende {
  _Ziel(this.url);
  final Uri url;
}

class _Fertig extends _Ende {}

Future<StilleAntwort> _httpHolen(Uri url, Map<String, String> kopf) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final r = await c.getUrl(url);
    r.followRedirects = false;
    kopf.forEach(r.headers.set);
    final a = await r.close();
    final text = await a.transform(utf8.decoder).join();
    final k = <String, String>{};
    a.headers.forEach((n, w) => k[n.toLowerCase()] = w.join(', '));
    return StilleAntwort(a.statusCode, kopf: k, cookies: a.cookies, text: text);
  } finally {
    c.close(force: true);
  }
}
