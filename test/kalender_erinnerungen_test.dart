// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

class _Leer implements Transport {
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async => (status: 200, json: {'ok': true});
}

const _app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'Rosenweg Test', ordner: 'rosenweg-test', beschreibung: 'Test.');

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('Kalenderdatei', () {
    final jetzt = DateTime.utc(2026, 11, 28, 10);

    test('Termin mit Zeit: UTC, Ende = Beginn + 1 h, CRLF, Sonderzeichen maskiert', () {
      final t = Kalenderdatei.text([
        KalenderTermin(
          uid: 'stweg3-termin-42@rosenweg4303.ch',
          titel: 'Versammlung; Budget, Teil 2',
          beginn: DateTime.utc(2026, 12, 3, 18),
          ort: 'Gemeinschaftsraum\nHaus 9',
          beschreibung: r'Traktanden: C:\Liste',
          erinnerung: const Duration(hours: 1),
        ),
      ], name: 'STWEG 3', jetzt: jetzt);
      expect(t, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
      expect(t, endsWith('END:VCALENDAR\r\n'));
      expect(t.replaceAll('\r\n', '').contains('\n'), isFalse, reason: 'nur CRLF');
      final z = t.split('\r\n');
      expect(z, contains('UID:stweg3-termin-42@rosenweg4303.ch'));
      expect(z, contains('DTSTAMP:20261128T100000Z'));
      expect(z, contains('DTSTART:20261203T180000Z'));
      expect(z, contains('DTEND:20261203T190000Z'));
      expect(z, contains(r'SUMMARY:Versammlung\; Budget\, Teil 2'));
      expect(z, contains(r'LOCATION:Gemeinschaftsraum\nHaus 9'));
      expect(z, contains(r'DESCRIPTION:Traktanden: C:\\Liste'));
      expect(z, contains('X-WR-CALNAME:STWEG 3'));
      expect(z, containsAllInOrder(['BEGIN:VALARM', 'ACTION:DISPLAY', 'TRIGGER:-PT1H', 'END:VALARM']));
    });

    test('ganztags: DATE, Ende ist der Tag nach dem letzten Tag', () {
      final z = Kalenderdatei.text([
        KalenderTermin(uid: 'a', titel: 'Reinigung', beginn: DateTime(2026, 12, 31, 9), ganztags: true),
        KalenderTermin(uid: 'b', titel: 'Sanierung', beginn: DateTime(2027, 1, 4), ende: DateTime(2027, 1, 6), ganztags: true),
      ], jetzt: jetzt).split('\r\n');
      expect(z, containsAllInOrder(['DTSTART;VALUE=DATE:20261231', 'DTEND;VALUE=DATE:20270101']));
      expect(z, containsAllInOrder(['DTSTART;VALUE=DATE:20270104', 'DTEND;VALUE=DATE:20270107']));
    });

    test('lange Zeilen: nach 75 Bytes gefaltet, Umlaute nie zerschnitten', () {
      final titel = 'Eigentümerversammlung ' * 8;
      final t = Kalenderdatei.text([KalenderTermin(uid: 'x', titel: titel, beginn: DateTime.utc(2027))], jetzt: jetzt);
      for (final zeile in t.split('\r\n')) {
        expect(utf8.encode(zeile).length, lessThanOrEqualTo(75));
      }
      // entfalten ergibt wieder den Titel
      final entfaltet = t.replaceAll('\r\n ', '');
      expect(entfaltet, contains('SUMMARY:${titel.trimRight()}'));
    });

    test('datei: Typ text/calendar, Endung .ics; dateinameAus', () {
      final d = Kalenderdatei.datei([KalenderTermin(uid: 'x', titel: 'T', beginn: DateTime.utc(2027))], dateiname: 'versammlung');
      expect(d.name, 'versammlung.ics');
      expect(d.typ, 'text/calendar');
      expect(utf8.decode(d.bytes), contains('SUMMARY:T'));
      expect(Kalenderdatei.dateinameAus('Eigentümerversammlung 2027 (STWEG 3)'), 'eigentuemerversammlung-2027-stweg-3.ics');
      expect(Kalenderdatei.dateinameAus('🗓️'), 'termin.ics');
    });
  });

  group('Erinnerungen', () {
    setUp(() => Benachrichtigung.attrappe = []);
    tearDown(() => Benachrichtigung.attrappe = null);

    Erinnerung e(String s, Duration in_, [String titel = 'T']) =>
        Erinnerung(schluessel: s, wann: DateTime.now().add(in_), titel: titel, text: 'x', ziel: 'termin/$s');

    test('plant kommende, entfernt weggefallene, ersetzt geaenderte', () async {
      final s = RosenwegSitzung(_app, transport: _Leer());
      expect(await Erinnerungen.abgleichen(s, [e('1', const Duration(hours: 2)), e('2', const Duration(days: 3)), e('alt', -const Duration(minutes: 5))]), 2);
      expect(Benachrichtigung.attrappe!.map((x) => x.id).toSet(), {Erinnerungen.idFuer('1'), Erinnerungen.idFuer('2')});
      // 2 geloescht, 1 umbenannt, 3 neu
      expect(await Erinnerungen.abgleichen(s, [e('1', const Duration(hours: 2), 'Neu'), e('3', const Duration(hours: 5))]), 2);
      final a = Benachrichtigung.attrappe!;
      expect(a.map((x) => x.id).toSet(), {Erinnerungen.idFuer('1'), Erinnerungen.idFuer('3')});
      expect(a.firstWhere((x) => x.id == Erinnerungen.idFuer('1')).titel, 'Neu');
      expect(a.length, 2);
    });

    test('sofort gezeigte bleiben; alleEntfernen nimmt nur geplante', () async {
      await Benachrichtigung.zeigen(id: 99, titel: 'Jetzt', text: 'x');
      await Erinnerungen.abgleichen(null, [e('1', const Duration(hours: 2))]);
      await Erinnerungen.alleEntfernen();
      expect(Benachrichtigung.attrappe!.map((x) => x.id), [99]);
    });

    test('geteiltes Telefon: plant wie am eigenen Geraet', () async {
      final s = RosenwegSitzung(_app, transport: _Leer())..geteiltesTelefon = true;
      expect(await Erinnerungen.abgleichen(s, [e('1', const Duration(hours: 2))]), 1);
      expect(Benachrichtigung.attrappe, hasLength(1));
    });

    test('geteiltes Telefon: Personenwechsel entfernt Erinnerungen und Benachrichtigungen', () async {
      final s = RosenwegSitzung(_app, geraetDa: () async => true, personWechsel: const Stream.empty());
      await s.starten();
      expect(s.geteiltesTelefon, isTrue);
      await Erinnerungen.abgleichen(s, [e('1', const Duration(hours: 2))]);
      await Benachrichtigung.zeigen(id: 99, titel: 'Jetzt', text: 'x');
      expect(Benachrichtigung.attrappe, hasLength(2));
      final vorher = s.personStand.value;
      s.personGewechselt();
      for (var i = 0; i < 100 && s.personStand.value == vorher; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(s.personStand.value, vorher + 1);
      expect(Benachrichtigung.attrappe, isEmpty);
    });
  });
}
