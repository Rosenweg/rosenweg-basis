// SPDX-License-Identifier: GPL-3.0-or-later
/// Termine als Kalenderdatei (.ics, iCalendar RFC 5545) – zum Teilen oder
/// Oeffnen in jedem Kalender (Rosenweg Kalender, Nextcloud, Apple Kalender,
/// Outlook, Thunderbird, GNOME Kalender).
///
/// ```dart
/// final d = Kalenderdatei.datei([
///   KalenderTermin(uid: 'stweg3-42@rosenweg4303.ch', titel: 'Eigentümerversammlung',
///       beginn: DateTime(2026, 12, 3, 19), ort: 'Gemeinschaftsraum'),
/// ], dateiname: 'eigentuemerversammlung.ics');
/// await dateiOeffnen(context, d);   // oder dateiTeilen
/// ```
///
/// Gleiche [KalenderTermin.uid] = derselbe Termin: wer die Datei nach einer
/// Aenderung nochmals uebernimmt, aktualisiert den Termin (sofern der
/// Kalender das kann), statt einen zweiten anzulegen.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'netz/dateien.dart';

class KalenderTermin {
  const KalenderTermin({
    required this.uid,
    required this.titel,
    required this.beginn,
    this.ende,
    this.ganztags = false,
    this.ort,
    this.beschreibung,
    this.adresse,
    this.erinnerung,
    this.geaendert,
  });

  /// Weltweit eindeutig und je Termin fest, z. B. `stweg3-termin-42@rosenweg4303.ch`.
  final String uid;
  final String titel;

  /// Lokale Zeit oder UTC; in der Datei steht UTC (bei [ganztags] nur das Datum).
  final DateTime beginn;

  /// Ende; null = [Kalenderdatei.standardDauer] nach dem Beginn (ganztags: derselbe Tag).
  /// Ganztags: der letzte Tag (einschliesslich).
  final DateTime? ende;
  final bool ganztags;
  final String? ort;
  final String? beschreibung;

  /// Link zum Termin (z. B. Web-Seite der STWEG).
  final Uri? adresse;

  /// Erinnerung des Kalenders so lange vor dem Beginn (VALARM), null = keine.
  final Duration? erinnerung;

  /// Letzte Aenderung (LAST-MODIFIED), falls bekannt.
  final DateTime? geaendert;
}

class Kalenderdatei {
  Kalenderdatei._();

  static const typ = 'text/calendar';

  /// Dauer eines Termins ohne Ende.
  static const standardDauer = Duration(hours: 1);

  /// Inhalt der .ics-Datei (Zeilen mit CRLF, nach 75 Bytes gefaltet).
  /// [name]: Name des Kalenders fuer Programme, die ihn beim Einlesen zeigen.
  /// [jetzt] nur fuer Tests (DTSTAMP).
  static String text(List<KalenderTermin> termine, {String? name, DateTime? jetzt}) {
    final z = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Rosenweg//Rosenweg Apps//DE',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      if (name != null && name.isNotEmpty) 'X-WR-CALNAME:${_text(name)}',
    ];
    final stempel = _utc(jetzt ?? DateTime.now());
    for (final t in termine) {
      z
        ..add('BEGIN:VEVENT')
        ..add('UID:${_text(t.uid)}')
        ..add('DTSTAMP:$stempel');
      if (t.ganztags) {
        final von = DateTime(t.beginn.year, t.beginn.month, t.beginn.day);
        var bis = t.ende == null ? von : DateTime(t.ende!.year, t.ende!.month, t.ende!.day);
        if (bis.isBefore(von)) bis = von;
        z
          ..add('DTSTART;VALUE=DATE:${_datum(von)}')
          // DTEND ist bei ganztaegigen Terminen der Tag NACH dem letzten Tag
          ..add('DTEND;VALUE=DATE:${_datum(DateTime(bis.year, bis.month, bis.day + 1))}');
      } else {
        var ende = t.ende ?? t.beginn.add(standardDauer);
        if (ende.isBefore(t.beginn)) ende = t.beginn;
        z
          ..add('DTSTART:${_utc(t.beginn)}')
          ..add('DTEND:${_utc(ende)}');
      }
      z.add('SUMMARY:${_text(t.titel)}');
      if (t.ort != null && t.ort!.trim().isNotEmpty) z.add('LOCATION:${_text(t.ort!.trim())}');
      if (t.beschreibung != null && t.beschreibung!.trim().isNotEmpty) {
        z.add('DESCRIPTION:${_text(t.beschreibung!.trim())}');
      }
      if (t.adresse != null) z.add('URL:${t.adresse}');
      if (t.geaendert != null) z.add('LAST-MODIFIED:${_utc(t.geaendert!)}');
      final e = t.erinnerung;
      if (e != null) {
        z
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add('DESCRIPTION:${_text(t.titel)}')
          ..add('TRIGGER:-${_dauer(e)}')
          ..add('END:VALARM');
      }
      z.add('END:VEVENT');
    }
    z.add('END:VCALENDAR');
    return '${z.map(_falten).join('\r\n')}\r\n';
  }

  /// Als Datei zum Teilen/Oeffnen ([dateiTeilen], [dateiOeffnen]).
  static DateiDaten datei(List<KalenderTermin> termine, {String dateiname = 'termin.ics', String? name, DateTime? jetzt}) =>
      DateiDaten(
        name: dateiname.toLowerCase().endsWith('.ics') ? dateiname : '$dateiname.ics',
        bytes: Uint8List.fromList(utf8.encode(text(termine, name: name, jetzt: jetzt))),
        typ: typ,
      );

  /// Dateiname aus einem Titel: Kleinbuchstaben, Umlaute ausgeschrieben,
  /// sonst nur a–z, 0–9 und Bindestriche (z. B. `eigentuemerversammlung.ics`).
  static String dateinameAus(String titel) {
    var s = titel.toLowerCase();
    const ersatz = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss', 'é': 'e', 'è': 'e', 'à': 'a'};
    ersatz.forEach((a, b) => s = s.replaceAll(a, b));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.length > 60) s = s.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
    return '${s.isEmpty ? 'termin' : s}.ics';
  }

  static String _zwei(int n) => n.toString().padLeft(2, '0');
  static String _datum(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_zwei(d.month)}${_zwei(d.day)}';
  static String _utc(DateTime d) {
    final u = d.toUtc();
    return '${_datum(u)}T${_zwei(u.hour)}${_zwei(u.minute)}${_zwei(u.second)}Z';
  }

  static String _dauer(Duration d) {
    if (d.inMinutes <= 0) return 'PT0M';
    if (d.inMinutes % (24 * 60) == 0) return 'P${d.inDays}D';
    if (d.inMinutes % 60 == 0) return 'PT${d.inHours}H';
    return 'PT${d.inMinutes}M';
  }

  /// TEXT nach RFC 5545 3.3.11: \ ; , und Zeilenumbrueche.
  static String _text(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', r'\n');

  /// Zeilen ueber 75 Bytes (UTF-8) falten: CRLF + Leerzeichen, nie mitten
  /// in einem Zeichen.
  static String _falten(String zeile) {
    if (utf8.encode(zeile).length <= 75) return zeile;
    final teile = <String>[];
    final b = StringBuffer();
    var bytes = 0;
    var grenze = 75;
    for (final r in zeile.runes) {
      final z = String.fromCharCode(r);
      final n = utf8.encode(z).length;
      if (bytes + n > grenze) {
        teile.add(b.toString());
        b.clear();
        bytes = 0;
        grenze = 74; // Folgezeilen beginnen mit einem Leerzeichen
      }
      b.write(z);
      bytes += n;
    }
    if (b.isNotEmpty) teile.add(b.toString());
    return teile.join('\r\n ');
  }
}
