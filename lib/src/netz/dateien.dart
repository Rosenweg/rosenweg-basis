// SPDX-License-Identifier: GPL-3.0-or-later
/// Dateien hoch- und herunterladen mit dem Token der Anmeldung (Bearer),
/// mit Fortschritt. JSON-Anfragen gehen weiter ueber [RosenwegApi].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../protokoll.dart';
import 'api.dart';
import 'fehler.dart';

/// Eine Datei im Speicher (gewaehlt, fotografiert oder heruntergeladen).
class DateiDaten {
  DateiDaten({required this.name, required this.bytes, String? typ}) : typ = typ ?? dateiTypRaten(name);
  final String name;
  final Uint8List bytes;

  /// MIME-Typ, z. B. `application/pdf`.
  final String typ;
  int get groesse => bytes.length;

  @override
  String toString() => 'DateiDaten($name, $typ, ${groesseText(groesse)})';
}

/// Fortschritt: [fertig] von [gesamt] Bytes (gesamt null = unbekannt).
typedef Fortschritt = void Function(int fertig, int? gesamt);

/// `3,4 MB` (deutsch, eine Nachkommastelle).
String groesseText(int bytes) {
  if (bytes < 1024) return '$bytes Bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 100 ? 1 : 0).replaceAll('.', ',')} MB';
}

const _typen = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'eml': 'message/rfc822',
  'wav': 'audio/wav',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
};

/// MIME-Typ aus der Endung; unbekannt = `application/octet-stream`.
String dateiTypRaten(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? 'application/octet-stream' : (_typen[name.substring(i + 1).toLowerCase()] ?? 'application/octet-stream');
}

/// Dateiname aus `Content-Disposition` (auch `filename*=UTF-8''…`).
String? dateinameAusKopf(String? kopf) {
  if (kopf == null) return null;
  final stern = RegExp(r"filename\*\s*=\s*([^']*)''([^;]+)", caseSensitive: false).firstMatch(kopf);
  if (stern != null) {
    try {
      return Uri.decodeComponent(stern.group(2)!.trim());
    } catch (_) {}
  }
  final m = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(kopf);
  return m?.group(1)?.trim();
}

/// Dateiname fuer den Kopf `X-Filename`: ASCII unveraendert, sonst
/// URL-kodiert (Kopfzeilen duerfen keine Umlaute enthalten).
String kopfDateiname(String name) => RegExp(r'^[\x20-\x7e]*$').hasMatch(name) ? name : Uri.encodeComponent(name);

/// Datei-Transfer zur Haupt-API.
///
/// * [hochladen] **roh** (Standard, wie `/api/documents` und
///   `/api/vollmachten/:id/upload-signed`: Body = Datei, Content-Type der
///   Datei, Name im Kopf `X-Filename`) oder **multipart** (Formular mit
///   Feld [feld] und weiteren Feldern).
/// * [herunterladen] liest die ganze Datei in den Speicher, Name aus
///   `Content-Disposition`.
///
/// Bei 401 einmal das Token erneuern und nochmals (wie [HttpTransport]);
/// Fehler der API wie bei [RosenwegApi] ([ApiFehler] mit dem Text der API).
///
/// **Geteilte Telefone:** Rosenweg Geraet reicht nur JSON weiter. Herunterladen
/// geht dort stueckweise ueber [stueckweise] (`portal_bereich`, base64 in JSON,
/// Stuecke zu [stueckGroesse], Dateien bis [geteiltHoechstens]); Hochladen geht
/// dort noch nicht ([GeraetFehler] mit verstaendlichem Satz).
class RosenwegDateien {
  RosenwegDateien({
    required this.basis,
    required Zugangsquelle? zugang,
    http.Client? client,
    this.nichtAngemeldet,
    bool Function()? geteiltesTelefon,
    this.stueckweiseApi,
    this.zeit = const Duration(minutes: 10),
    this.kopfzeilen = const {},
  })  : _zugang = zugang, // ignore: prefer_initializing_formals
        _client = client ?? http.Client(),
        _geteilt = geteiltesTelefon ?? (() => false);

  final String basis;
  final Zugangsquelle? _zugang;
  final http.Client _client;
  final void Function()? nichtAngemeldet;
  final bool Function() _geteilt;

  /// Geteiltes Telefon: die API, ueber die [stueckweise] laeuft (ohne sie gibt
  /// es dort kein Herunterladen).
  final RosenwegApi? Function()? stueckweiseApi;

  /// Hoechstdauer je Transfer.
  final Duration zeit;

  /// Zusaetzliche Kopfzeilen fuer jede Anfrage.
  final Map<String, String> kopfzeilen;

  /// Stueck je Anfrage ueber Rosenweg Geraet (base64 bleibt unter der Binder-Grenze).
  static const stueckGroesse = 320 * 1024;

  /// Hoechstgroesse einer Datei am geteilten Telefon. Gleicher Wert wie
  /// `PORTAL_BINAER_MAX` der Telefonanlage (pbx/api/app.py): beide zusammen aendern.
  static const geteiltHoechstens = 20 * 1024 * 1024;

  static const geteiltText = 'Dateien hoch- oder herunterladen geht auf geteilten Rosenweg-Telefonen noch nicht. '
      'Bitte an einem eigenen Gerät oder an einer Station erledigen.';

  /// Datei hochladen; liefert das JSON der Antwort.
  ///
  /// [inhaltstyp] (nur roh): Content-Type statt des Typs der Datei — die
  /// API nimmt je Route nur einen an (`/api/documents`:
  /// `application/octet-stream`, `upload-signed`: `application/pdf`).
  Future<Object?> hochladen(
    String pfad,
    DateiDaten datei, {
    String methode = 'POST',
    String? inhaltstyp,
    bool multipart = false,
    String feld = 'datei',
    Map<String, String> felder = const {},
    Map<String, String> kopf = const {},
    Fortschritt? fortschritt,
  }) async {
    final a = await _mitToken('Hochladen $methode $pfad', (token) async {
      final uri = Uri.parse('$basis$pfad');
      final http.BaseRequest r;
      if (multipart) {
        final m = _FortschrittMultipart(methode, uri, fortschritt)
          ..fields.addAll(felder)
          ..files.add(http.MultipartFile.fromBytes(feld, datei.bytes, filename: datei.name, contentType: _mediaTyp(datei.typ)));
        r = m;
      } else {
        final s = http.StreamedRequest(methode, uri)
          ..headers['Content-Type'] = inhaltstyp ?? datei.typ
          ..headers['X-Filename'] = kopfDateiname(datei.name)
          ..contentLength = datei.groesse;
        r = s;
        // Stueckweise senden, damit der Fortschritt stimmt
        unawaited(() async {
          const stueck = 64 * 1024;
          final g = datei.groesse;
          fortschritt?.call(0, g);
          for (var i = 0; i < g; i += stueck) {
            final ende = i + stueck < g ? i + stueck : g;
            s.sink.add(datei.bytes.sublist(i, ende));
            fortschritt?.call(ende, g);
            await Future<void>.delayed(Duration.zero);
          }
          await s.sink.close();
        }());
      }
      r.headers
        ..addAll(kopfzeilen)
        ..addAll(kopf)
        ..['Authorization'] = 'Bearer $token'
        ..['Accept'] = 'application/json';
      final antwort = await _client.send(r).timeout(zeit);
      final text = utf8.decode(await antwort.stream.toBytes().timeout(zeit), allowMalformed: true);
      return (antwort.statusCode, _json(text), null as Uint8List?, antwort.headers);
    }, wiederholbar: false);
    return apiAntwortPruefen((status: a.$1, json: a.$2), nichtAngemeldet: nichtAngemeldet);
  }

  /// Datei herunterladen. [name] = Ersatz, wenn die API keinen nennt.
  Future<DateiDaten> herunterladen(String pfad, {String? name, Fortschritt? fortschritt}) async {
    if (_geteilt()) {
      final api = stueckweiseApi?.call();
      if (api == null) throw GeraetFehler(geteiltText);
      return stueckweise(api, pfad, name ?? Uri.parse(pfad).pathSegments.lastOrNull ?? 'datei', fortschritt: fortschritt);
    }
    final a = await _mitToken('Herunterladen $pfad', (token) async {
      final r = http.Request('GET', Uri.parse('$basis$pfad'))
        ..headers.addAll(kopfzeilen)
        ..headers['Authorization'] = 'Bearer $token';
      final antwort = await _client.send(r).timeout(zeit);
      final gesamt = antwort.contentLength;
      final teile = BytesBuilder(copy: false);
      var n = 0;
      fortschritt?.call(0, gesamt);
      await for (final t in antwort.stream.timeout(zeit)) {
        teile.add(t);
        n += t.length;
        fortschritt?.call(n, gesamt);
      }
      final bytes = teile.takeBytes();
      final ok = antwort.statusCode >= 200 && antwort.statusCode < 300;
      return (antwort.statusCode, ok ? null : _json(utf8.decode(bytes, allowMalformed: true)), ok ? bytes : null, antwort.headers);
    }, wiederholbar: true);
    if (a.$3 == null) {
      apiAntwortPruefen((status: a.$1, json: a.$2), nichtAngemeldet: nichtAngemeldet);
      throw ApiFehler(a.$1, 'Der Server hat die Anfrage abgelehnt (${a.$1}).');
    }
    final h = a.$4;
    final n = dateinameAusKopf(h['content-disposition']) ?? name ?? Uri.parse(pfad).pathSegments.lastOrNull ?? 'datei';
    final typ = h['content-type']?.split(';').first.trim();
    return DateiDaten(name: n, bytes: a.$3!, typ: typ == null || typ.isEmpty || typ == 'application/octet-stream' ? null : typ);
  }

  /// Datei in Stuecken ueber den JSON-Weg (Rosenweg Geraet, `portal_bereich`):
  /// je Stueck `{binaer: {daten (base64), von, bis, gesamt, typ, name}}`.
  static Future<DateiDaten> stueckweise(RosenwegApi api, String pfad, String name, {Fortschritt? fortschritt}) async {
    final teile = BytesBuilder(copy: false);
    final trenner = pfad.contains('?') ? '&' : '?';
    var von = 0;
    int? gesamt;
    String? typ;
    String? kopfName;
    do {
      final j = await api.objekt('$pfad${trenner}portal_bereich=$von-${von + stueckGroesse - 1}');
      final b = j['binaer'];
      if (b is! Map) throw ApiFehler(200, 'Unerwartete Antwort vom Server.', j);
      final daten = base64Decode('${b['daten'] ?? ''}');
      gesamt = (b['gesamt'] as num?)?.toInt() ?? daten.length;
      if (gesamt > geteiltHoechstens) {
        throw GeraetFehler('Die Datei ist zu gross für ein geteiltes Telefon (höchstens ${geteiltHoechstens ~/ (1024 * 1024)} MB). '
            'Bitte an einem eigenen Gerät oder an einer Station öffnen.');
      }
      typ ??= b['typ'] as String?;
      kopfName ??= dateinameAusKopf('${b['name'] ?? ''}');
      if (daten.isEmpty) break;
      teile.add(daten);
      von += daten.length;
      fortschritt?.call(von, gesamt);
    } while (von < gesamt);
    final t = typ == null || typ.isEmpty || typ == 'application/octet-stream' ? null : typ;
    return DateiDaten(name: kopfName ?? name, bytes: teile.takeBytes(), typ: t);
  }

  Object? _json(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Token holen, senden, bei 401 einmal erneuern. Netzfehler →
  /// [ServerNichtErreichbar]; 429 → [ZuVieleAnfragen].
  Future<(int, Object?, Uint8List?, Map<String, String>)> _mitToken(
    String quelle,
    Future<(int, Object?, Uint8List?, Map<String, String>)> Function(String token) senden, {
    required bool wiederholbar,
  }) async {
    if (_geteilt()) throw GeraetFehler(geteiltText);
    final z = _zugang;
    var token = await z?.zugangsToken();
    if (z == null || token == null) {
      nichtAngemeldet?.call();
      throw NichtAngemeldet();
    }
    for (var versuch = 1;; versuch++) {
      final (int, Object?, Uint8List?, Map<String, String>) a;
      try {
        a = await senden(token!);
      } on SocketException catch (e) {
        Protokoll.schreiben('$quelle: Verbindung — ${e.message}');
        throw ServerNichtErreichbar();
      } on http.ClientException catch (e) {
        Protokoll.schreiben('$quelle: HTTP — ${e.message}');
        throw ServerNichtErreichbar();
      } on TimeoutException {
        Protokoll.schreiben('$quelle: Zeitueberschreitung');
        throw ServerNichtErreichbar();
      }
      if (a.$1 == 429) {
        final ra = int.tryParse(a.$4['retry-after'] ?? '');
        throw ZuVieleAnfragen(ra == null ? null : Duration(seconds: ra));
      }
      if (a.$1 == 502 || a.$1 == 503 || a.$1 == 504) {
        final j = a.$2;
        if (!(j is Map && j['error'] is String)) {
          Protokoll.schreiben('$quelle: Status ${a.$1} ohne JSON');
          throw ServerNichtErreichbar();
        }
      }
      // Ein Upload wird nach 401 auch nochmals geschickt: der Server hat ihn
      // ohne gueltiges Token gar nicht angenommen.
      if (a.$1 == 401 && versuch == 1) {
        z.zugangUngueltig();
        final neu = await z.zugangsToken();
        if (neu != null && neu != token) {
          token = neu;
          continue;
        }
      }
      if (a.$1 >= 400) Protokoll.schreiben('$quelle: Status ${a.$1}');
      return a;
    }
  }
}

MediaType? _mediaTyp(String typ) {
  try {
    return MediaType.parse(typ);
  } catch (_) {
    return null;
  }
}

/// Multipart mit Fortschritt beim Senden.
class _FortschrittMultipart extends http.MultipartRequest {
  _FortschrittMultipart(super.method, super.url, this.fortschritt);
  final Fortschritt? fortschritt;

  @override
  http.ByteStream finalize() {
    final s = super.finalize();
    final f = fortschritt;
    if (f == null) return s;
    final gesamt = contentLength;
    var n = 0;
    f(0, gesamt);
    return http.ByteStream(s.map((t) {
      n += t.length;
      f(n, gesamt);
      return t;
    }));
  }
}
