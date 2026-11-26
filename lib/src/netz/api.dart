// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../plattform.dart';
import 'fehler.dart';
import 'json_anfrage.dart';

/// Woher ein Zugangs-Token kommt (RosenwegKonto; in Tests eine Attrappe).
abstract class Zugangsquelle {
  /// Gueltiges Access-Token, bei Bedarf erneuert; null = nicht angemeldet.
  Future<String?> zugangsToken();

  /// Die API hat das Token abgelehnt: im Speicher verwerfen, damit das
  /// naechste [zugangsToken] erneuert.
  void zugangUngueltig();
}

/// Wie eine Anfrage zur Haupt-API kommt.
///
/// - [HttpTransport]: direkt, mit dem Token der eigenen Anmeldung (eigene
///   Handys, Linux-Stationen, Laptops).
/// - [GeraetTransport]: auf geteilten Telefonen ueber Rosenweg Geraet, das die
///   am Telefon angemeldete Person kennt (docs/geteilte-telefone.md).
abstract class Transport {
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper});
}

class HttpTransport implements Transport {
  HttpTransport({required this.basis, required this.zugang, http.Client? client}) : client = client ?? http.Client();

  final String basis;
  final Zugangsquelle zugang;
  final http.Client client;

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    var token = await zugang.zugangsToken();
    if (token == null) throw NichtAngemeldet();
    var a = await _einmal(methode, pfad, koerper, token);
    if (a.status == 401) {
      // Abgelaufen oder widerrufen: einmal erneuern, dann ehrlich melden.
      zugang.zugangUngueltig();
      final neu = await zugang.zugangsToken();
      if (neu == null || neu == token) return a;
      token = neu;
      a = await _einmal(methode, pfad, koerper, token);
    }
    return a;
  }

  Future<ApiAntwort> _einmal(String methode, String pfad, Object? koerper, String token) => jsonAnfrage(
        client,
        'API $methode $pfad',
        () {
          final r = http.Request(methode, Uri.parse('$basis$pfad'))
            ..headers['Authorization'] = 'Bearer $token'
            ..headers['Accept'] = 'application/json';
          if (koerper != null) {
            r.headers['Content-Type'] = 'application/json; charset=utf-8';
            r.body = jsonEncode(koerper);
          }
          return r;
        },
        // POST legt an (Token, Schluessel): nie doppelt schicken.
        versuche: methode == 'POST' ? 1 : 3,
      );
}

/// Geteiltes Telefon: die Anfrage geht an Rosenweg Geraet
/// (`call("portal_anfrage", pfad, {methode, koerper, paket})`, AnlageProvider
/// ab v236), das sie ueber die Telefonanlage im Namen der am Telefon
/// angemeldeten Person an die API stellt. Die App sieht nie ein Token —
/// siehe docs/geteilte-telefone.md.
///
/// Jede Antwort traegt eine `sitzung`-Marke, die mit jeder An-/Abmeldung am
/// Telefon wechselt. Wechselt sie zwischen zwei Antworten, ruft der Transport
/// [personGewechselt] (die App laedt dann neu, statt Daten zweier Personen zu
/// mischen).
class GeraetTransport implements Transport {
  GeraetTransport(this.paket, {this.personGewechselt, GeraetRufen? rufen}) : _rufen = rufen ?? _standardRufen;
  final String paket;
  final void Function()? personGewechselt;
  final GeraetRufen _rufen;
  String? _sitzung;

  static const methodeName = 'portal_anfrage';

  static Future<Map<String, Object?>> _standardRufen(String pfad, Map<String, Object?> extras) =>
      RosenwegPlattform.geraetRufen(methodeName, arg: pfad, extras: extras);

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    final b = await _rufen(pfad, {
      'methode': methode,
      'koerper': koerper == null ? null : jsonEncode(koerper),
      'paket': paket,
    });
    final s = b['sitzung'];
    if (s is String && s.isNotEmpty) {
      final vorher = _sitzung;
      _sitzung = s;
      if (vorher != null && vorher != s) personGewechselt?.call();
    }
    return geraetAntwortLesen(b);
  }
}

/// `portal_anfrage` an Rosenweg Geraet (in Tests eine Attrappe).
typedef GeraetRufen = Future<Map<String, Object?>> Function(String pfad, Map<String, Object?> extras);

/// Bundle von Rosenweg Geraet → Antwort (oeffentlich fuer Tests).
ApiAntwort geraetAntwortLesen(Map<String, Object?> b) {
  switch (b['fehler_art']) {
    case 'signatur':
      throw GeraetFehler('Rosenweg Gerät verweigert den Zugriff (andere Signatur?).');
    case 'nicht_installiert':
      throw GeraetFehler('Rosenweg Gerät ist nicht installiert.');
    case 'unbekannt':
      throw GeraetFehler('Rosenweg Gerät: ${b['fehler'] ?? 'unbekannter Fehler'}');
  }
  if (b['nicht_angemeldet'] == true) {
    throw NichtAngemeldet('Am Telefon ist niemand angemeldet. Bitte zuerst mit der Karte anmelden.');
  }
  final status = b['status'];
  if (status is int) {
    final roh = b['json'];
    Object? json;
    if (roh is String && roh.trim().isNotEmpty) {
      try {
        json = jsonDecode(roh);
      } on FormatException {
        throw ServerNichtErreichbar();
      }
    }
    if (status == 429) throw ZuVieleAnfragen(null);
    return (status: status, json: json);
  }
  if (b['fehler'] is String) throw GeraetFehler(b['fehler'] as String);
  // Leeres Bundle: Rosenweg Geraet kennt die Methode nicht (zu alt).
  throw GeraetFehler('Rosenweg Gerät ist zu alt für diese App – bitte Rosenweg Gerät aktualisieren.');
}

/// Client der Haupt-API. Liefert bei 2xx das gelesene JSON und wirft sonst
/// [ApiFehler] (401 [NichtAngemeldet], 403 [KeineBerechtigung]),
/// [ServerNichtErreichbar], [ZuVieleAnfragen] oder [GeraetFehler].
class RosenwegApi {
  RosenwegApi(this.transport, {this.nichtAngemeldet});

  final Transport transport;

  /// Wird bei 401 gerufen, bevor [NichtAngemeldet] geworfen wird — so kann
  /// die Sitzung zurueck zum Anmeldeschirm, egal wo die Anfrage herkam.
  final void Function()? nichtAngemeldet;

  Future<Object?> anfrage(String methode, String pfad, {Object? koerper}) async {
    final ApiAntwort a;
    try {
      a = await transport.senden(methode, pfad, koerper: koerper);
    } on NichtAngemeldet {
      nichtAngemeldet?.call();
      rethrow;
    }
    if (a.status >= 200 && a.status < 300) return a.json;
    final j = a.json;
    final text = j is Map && j['error'] is String && (j['error'] as String).isNotEmpty
        ? j['error'] as String
        : 'Der Server hat die Anfrage abgelehnt (${a.status}).';
    if (a.status == 401) {
      nichtAngemeldet?.call();
      throw NichtAngemeldet('Bitte wieder mit dem Rosenweg-Konto anmelden.', j);
    }
    if (a.status == 403) throw KeineBerechtigung(text, j);
    throw ApiFehler(a.status, text, j);
  }

  Future<Object?> get(String pfad) => anfrage('GET', pfad);
  Future<Object?> put(String pfad, Object? koerper) => anfrage('PUT', pfad, koerper: koerper);
  Future<Object?> post(String pfad, [Object? koerper]) => anfrage('POST', pfad, koerper: koerper);
  Future<Object?> delete(String pfad, [Object? koerper]) => anfrage('DELETE', pfad, koerper: koerper);

  /// GET, Antwort muss ein JSON-Objekt sein.
  Future<Map<String, dynamic>> objekt(String pfad) async {
    final j = await get(pfad);
    if (j is Map<String, dynamic>) return j;
    throw ApiFehler(200, 'Unerwartete Antwort vom Server.', j);
  }

  /// GET, Antwort muss eine JSON-Liste sein.
  Future<List<dynamic>> liste(String pfad) async {
    final j = await get(pfad);
    if (j is List) return j;
    throw ApiFehler(200, 'Unerwartete Antwort vom Server.', j);
  }
}
