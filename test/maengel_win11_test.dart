// SPDX-License-Identifier: GPL-3.0-or-later
// Maengel aus dem Test auf win11-1 (Windows 11, Domaenen-PC), 27.11.2026.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';
import 'package:rosenweg_basis/src/anmeldung/pcsc.dart';

/// stderr ohne Konsole: das Schreiben scheitert erst spaeter (asynchron).
class _KaputteKonsole implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> s) async {
    await s.drain<void>();
    throw const FileSystemException('writeFrom failed', '', OSError('Das Handle ist ungültig.', 6));
  }

  @override
  Future<void> close() async {}
}

class _Pcsc implements Pcsc {
  _Pcsc(this.namen);
  List<String> namen;
  @override
  List<String> leser() => namen;
  @override
  String? uid(String leser) => null;
  @override
  void schliessen() {}
}

void main() {
  group('Protokoll ohne Konsole (Mangel 1)', () {
    tearDown(() {
      Protokoll.konsoleFuerTests = null;
      Protokoll.windowsFuerTests = null;
      Protokoll.konsoleVergessen();
      Protokoll.nurKonsole = false;
    });

    test('asynchroner Schreibfehler von stderr bleibt im Protokoll, kein unbehandelter Fehler', () async {
      Protokoll.nurKonsole = true;
      Protokoll.konsoleFuerTests = () => IOSink(_KaputteKonsole());
      Protokoll.konsoleVergessen();
      final unbehandelt = <Object>[];
      await runZonedGuarded(() async {
        Protokoll.schreiben('eins');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        Protokoll.schreiben('zwei'); // Sink ist zu: still, kein Wurf
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (e, _) => unbehandelt.add(e));
      expect(unbehandelt, isEmpty);
    });

    test('Zeilen werden trotzdem weiter protokolliert', () async {
      Protokoll.nurKonsole = true;
      Protokoll.konsoleFuerTests = () => IOSink(_KaputteKonsole());
      Protokoll.konsoleVergessen();
      final zeilen = <String>[];
      Protokoll.mithoeren = zeilen.add;
      addTearDown(() => Protokoll.mithoeren = null);
      Protokoll.schreiben('Start');
      expect(zeilen.single, endsWith(' Start'));
    });
  });

  group('Kartenleser: Protokoll nur bei Wechsel (Mangel 2)', () {
    late List<String> zeilen;
    setUp(() {
      Protokoll.nurKonsole = true;
      zeilen = [];
      Protokoll.mithoeren = zeilen.add;
    });
    tearDown(() => Protokoll.mithoeren = null);

    test('ohne PC/SC: einmal "kein PC/SC", nicht bei jeder Abfrage', () async {
      final l = PcscKartenleser(oeffnen: () => null);
      for (var i = 0; i < 10; i++) {
        expect(await l.verfuegbar(), isFalse);
      }
      expect(zeilen.where((z) => z.contains('Kartenleser')).length, 1);
    });

    test('Leser eingesteckt und gezogen: je eine Zeile', () async {
      final p = _Pcsc([]);
      final l = PcscKartenleser(oeffnen: () => p);
      await l.verfuegbar();
      await l.verfuegbar();
      p.namen = ['ACS ACR122U'];
      expect(await l.verfuegbar(), isTrue);
      await l.verfuegbar();
      p.namen = [];
      await l.verfuegbar();
      expect(zeilen.where((z) => z.contains('Kartenleser')).length, 3);
    });
  });

  group('verstaendliche Fehler mit Details (Mangel 6)', () {
    test('Basis-Fehler: Satz ohne Details', () {
      final f = fehlerFuerPerson(BrowserNichtGeoeffnet());
      expect(f.text, contains('Browser'));
      expect(f.text, contains('öffnen'));
      expect(f.details, isNull);
    });

    test('roher StateError: deutscher Satz, Technik nur in Details', () {
      final f = fehlerFuerPerson(StateError('kaputt'));
      expect(f.text, isNot(contains('Bad state')));
      expect(f.details, contains('kaputt'));
    });

    test('Netzfehler: Satz zur Verbindung', () {
      final f = fehlerFuerPerson(const SocketException('weg'));
      expect(f.text, contains('Verbindung'));
      expect(f.details, contains('weg'));
    });

    testWidgets('FehlerAnzeige: Details aufklappbar', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: FehlerAnzeige.aus(StateError('innen'), nochmals: () {}))));
      expect(find.textContaining('Bad state'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
      await t.tap(find.text('Details'));
      await t.pumpAndSettle();
      expect(find.textContaining('innen'), findsOneWidget);
    });
  });

  group('verwaltete Installation: Updater aus (Mangel 8)', () {
    tearDown(() {
      RosenwegVerwaltet.ersatz = null;
      RosenwegVerwaltet.vergessen();
    });

    test('unter Program Files (ALLUSERS) = verwaltet, im Profil nicht', () {
      const env = {'ProgramFiles': r'C:\Program Files', 'PROGRAMFILES(X86)': r'C:\Program Files (x86)', 'windir': r'C:\Windows'};
      expect(RosenwegVerwaltet.imProgrammOrdner(r'C:\Program Files\Rosenweg Virtuelle Computer\rosenweg_vm.exe', env),
          r'C:\Program Files');
      expect(RosenwegVerwaltet.imProgrammOrdner(r'c:/program files (x86)/Rosenweg/x.exe', env), isNotNull);
      expect(RosenwegVerwaltet.imProgrammOrdner(r'C:\Users\a\AppData\Local\Programs\Rosenweg Virtuelle Computer\rosenweg_vm.exe', env),
          isNull);
      // "C:\Program Files Extra" ist nicht "C:\Program Files"
      expect(RosenwegVerwaltet.imProgrammOrdner(r'C:\Program Files Extra\x.exe', env), isNull);
    });

    test('Regel: verwaltet = aus, sonst wie bisher', () {
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'windows', station: false, verwaltet: true, release: true), isFalse);
      expect(RosenwegAktualisierung.laeuftHier(plattform: 'windows', station: false, verwaltet: false, release: true), isTrue);
    });

    test('Erkennung fliesst in "aktiv" ein', () {
      RosenwegVerwaltet.ersatz = () => r'HKLM\Software\Rosenweg\Verwaltet = 1';
      RosenwegVerwaltet.vergessen();
      const app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'T', ordner: 't', beschreibung: '.');
      final a = RosenwegAktualisierung(app, plattform: 'windows');
      expect(RosenwegVerwaltet.erkannt, isTrue);
      expect(a.aktiv, isFalse);
    });
  });
}
