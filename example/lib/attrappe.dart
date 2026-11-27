// SPDX-License-Identifier: GPL-3.0-or-later
// Vorfuehrdaten: eine kleine "API" in der App, damit das Beispiel ohne
// Anmeldung und ohne Server auf jeder Plattform laeuft.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

/// Was die Person im Beispiel einstellt (Rolle, Stufe der Anmeldung).
class Vorfuehrung {
  var technik = false;
  var stufe = 'karte';
  final meldungen = [
    for (var i = 1; i <= 137; i++)
      {
        'id': i,
        'titel': const ['Tür klemmt', 'Licht im Treppenhaus', 'Heizung kalt', 'Lift steht', 'Briefkasten defekt'][i % 5],
        'haus': 'Rosenweg ${const [1, 2, 4, 5, 9, 12, 17][i % 7]}',
        'status': i % 3 == 0 ? 'erledigt' : 'offen',
        'datum': DateTime(2026, 11, 27).subtract(Duration(days: i)).toIso8601String().substring(0, 10),
      },
  ];
  final hochgeladen = <String>[];

  Map<String, dynamic> authMe() => {
        'user': {
          'name': 'Anna Beispiel',
          'email': 'anna@example.ch',
          'groups': technik ? ['Technik'] : ['Bewohner'],
          'permissions': {'reklamationen': 'read', 'waschkueche': 'write'},
          'anmeldung': {'stufe': stufe},
        },
      };

  /// `/api/reklamationen?limit=&nach=&q=&status=` mit Cursor wie Plan 4.2.4.
  Map<String, dynamic> liste(Uri u) {
    final q = (u.queryParameters['q'] ?? '').toLowerCase();
    final status = u.queryParameters['status'];
    var l = meldungen
        .where((m) => q.isEmpty || '${m['titel']} ${m['haus']}'.toLowerCase().contains(q))
        .where((m) => status == null || m['status'] == status)
        .toList();
    final sort = u.queryParameters['sort'];
    if (sort != null) {
      l.sort((a, b) => '${a[sort]}'.compareTo('${b[sort]}'));
      if (u.queryParameters['richtung'] == 'ab') l = l.reversed.toList();
    }
    final ab = int.tryParse(u.queryParameters['nach'] ?? '') ?? 0;
    final limit = int.tryParse(u.queryParameters['limit'] ?? '') ?? 50;
    final seite = l.skip(ab).take(limit).toList();
    return {'reklamationen': seite, 'naechster': ab + seite.length < l.length ? '${ab + seite.length}' : null, 'gesamt': l.length};
  }
}

class VorfuehrTransport implements Transport {
  VorfuehrTransport(this.v);
  final Vorfuehrung v;

  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final u = Uri.parse(pfad);
    if (u.path == '/api/auth/me') return (status: 200, json: v.authMe());
    if (u.path == '/api/reklamationen') return (status: 200, json: v.liste(u));
    if (u.path == '/api/me' && methode == 'PUT') {
      final k = koerper as Map;
      if ('${k['email']}'.endsWith('@test')) {
        return (status: 400, json: {'error': 'Diese Adresse nimmt der Server nicht an.', 'feld': 'email'});
      }
      if (k['betrag'] is int && (k['betrag'] as int) > 100000) {
        return (status: 400, json: {'error': 'Höchstens CHF 1000.00 ohne Rückfrage.', 'feld': 'betrag'});
      }
      return (status: 200, json: {'ok': true});
    }
    if (u.path == '/api/personen') {
      final q = (u.queryParameters['q'] ?? '').toLowerCase();
      const alle = ['Anna Beispiel', 'Beat Muster', 'Carla Rossi', 'Daniel Huber', 'Eva Meier', 'Fritz Keller'];
      return (status: 200, json: [for (final n in alle) if (n.toLowerCase().contains(q)) n]);
    }
    return (status: 404, json: {'error': 'Nicht gefunden.'});
  }
}

class _Fest implements Zugangsquelle {
  @override
  Future<String?> zugangsToken() async => 'vorfuehrung';
  @override
  void zugangUngueltig() {}
}

/// Datei-Transfer gegen die Vorfuehr-"API": PDF herunterladen, Upload langsam
/// (damit der Fortschritt sichtbar ist).
RosenwegDateien vorfuehrDateien(Vorfuehrung v) => RosenwegDateien(
      basis: 'https://beispiel.invalid',
      zugang: _Fest(),
      client: MockClient.streaming((r, body) async {
        if (r.method == 'GET' && r.url.path == '/api/beispiel.pdf') {
          final pdf = beispielPdf();
          return http.StreamedResponse(Stream.fromIterable([pdf]), 200,
              contentLength: pdf.length,
              headers: {'content-type': 'application/pdf', 'content-disposition': 'inline; filename="rosenweg-beispiel.pdf"'});
        }
        if (r.url.path == '/api/upload') {
          var n = 0;
          await for (final t in body) {
            n += t.length;
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
          v.hochgeladen.add('${r.headers['X-Filename'] ?? 'datei'} ($n Bytes)');
          return http.StreamedResponse(Stream.value(utf8.encode('{"ok":true}')), 201);
        }
        return http.StreamedResponse(Stream.value(utf8.encode('{"error":"Nicht gefunden."}')), 404);
      }),
    );

/// Kleines PDF mit drei Seiten (ohne Zusatzpaket erzeugt).
Uint8List beispielPdf() {
  final objekte = <String>[];
  const seiten = 3;
  objekte.add('<< /Type /Catalog /Pages 2 0 R >>');
  final kinder = [for (var i = 0; i < seiten; i++) '${4 + i * 2} 0 R'].join(' ');
  objekte.add('<< /Type /Pages /Kids [$kinder] /Count $seiten >>');
  objekte.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < seiten; i++) {
    final text = 'BT /F1 28 Tf 72 720 Td (Rosenweg-Basis: PDF-Ansicht) Tj 0 -48 Td /F1 20 Tf (Seite ${i + 1} von $seiten) Tj ET';
    objekte.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>');
    objekte.add('<< /Length ${text.length} >>\nstream\n$text\nendstream');
  }
  final b = StringBuffer('%PDF-1.4\n');
  final stellen = <int>[];
  for (var i = 0; i < objekte.length; i++) {
    stellen.add(b.length);
    b.write('${i + 1} 0 obj\n${objekte[i]}\nendobj\n');
  }
  final xref = b.length;
  b.write('xref\n0 ${objekte.length + 1}\n0000000000 65535 f \n');
  for (final s in stellen) {
    b.write('${s.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer\n<< /Size ${objekte.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}
