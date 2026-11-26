// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../protokoll.dart';
import 'fehler.dart';

/// Antwort mit Status und gelesenem JSON (null bei leerem Text).
typedef ApiAntwort = ({int status, Object? json});

/// Schickt eine Anfrage und liest JSON.
///
/// - 429 → [ZuVieleAnfragen] (mit Retry-After).
/// - HTML/Nicht-JSON, 502/503/504 ohne JSON-Fehlertext, Verbindungsfehler,
///   Zeitueberschreitung → bis zu [versuche] Mal mit Rueckoff (2 s, 4 s, …),
///   danach [ServerNichtErreichbar]. So meldet ein kurzer Neustart des
///   Servers niemanden ab und zeigt keine HTML-Fehlerseite als "Fehler".
/// - 502/503/504 MIT JSON `{error: …}` kommt von der API selbst (z. B.
///   "Energy-Collector nicht erreichbar") und wird wie jede andere Antwort
///   zurueckgegeben — nicht wiederholt.
///
/// Status und Rohtext (gekuerzt) nur ins Protokoll — nie bei 2xx, damit
/// keine Tokens oder Personendaten im Log landen.
///
/// [bauen] baut die Anfrage jedes Mal neu (eine gesendete http.Request laesst
/// sich nicht nochmals senden). Nicht idempotente Anfragen (POST) mit
/// `versuche: 1` schicken. Aus rosenweg-vm lib/netz/json_anfrage.dart.
Future<ApiAntwort> jsonAnfrage(
  http.Client client,
  String quelle,
  http.BaseRequest Function() bauen, {
  int versuche = 3,
  Duration zeit = const Duration(seconds: 30),
  Duration rueckoff = const Duration(seconds: 2),
}) async {
  for (var n = 1;; n++) {
    String grund;
    try {
      final a = await http.Response.fromStream(await client.send(bauen()).timeout(zeit)).timeout(zeit);
      final status = a.statusCode;
      if (status == 429) {
        final ra = int.tryParse(a.headers['retry-after'] ?? '');
        Protokoll.schreiben('$quelle: 429 (Retry-After: ${ra ?? '-'})');
        throw ZuVieleAnfragen(ra == null ? null : Duration(seconds: ra));
      }
      final text = utf8.decode(a.bodyBytes, allowMalformed: true);
      Object? json;
      var lesbar = true;
      if (text.trim().isNotEmpty) {
        try {
          json = jsonDecode(text);
        } on FormatException {
          lesbar = false;
        }
      }
      final gateway = status == 502 || status == 503 || status == 504;
      final mitFehlertext = json is Map && json['error'] is String;
      if (lesbar && (!gateway || mitFehlertext)) return (status: status, json: json);
      final roh = text.length > 300 ? '${text.substring(0, 300)} …' : text;
      grund = 'Status $status, ${lesbar ? 'JSON' : 'kein JSON'}: ${roh.replaceAll(RegExp(r'\s+'), ' ')}';
    } on SocketException catch (e) {
      grund = 'Verbindung: ${e.message}';
    } on HttpException catch (e) {
      grund = 'HTTP: ${e.message}';
    } on http.ClientException catch (e) {
      grund = 'HTTP: ${e.message}';
    } on HandshakeException catch (e) {
      grund = 'TLS: ${e.message}';
    } on TimeoutException {
      grund = 'Zeitueberschreitung';
    }
    Protokoll.schreiben('$quelle: Server nicht erreichbar (Versuch $n/$versuche) — $grund');
    if (n >= versuche) throw ServerNichtErreichbar();
    await Future<void>.delayed(rueckoff * (1 << (n - 1)));
  }
}
