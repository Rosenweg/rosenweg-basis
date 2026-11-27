// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

Map<String, dynamic> _me({Map<String, String> p = const {}, List<String> g = const [], Map<String, Object?>? anmeldung}) => {
      'user': {
        'email': 'a@b.ch',
        'name': 'Anna',
        'groups': g,
        'permissions': p,
        'anmeldung': ?anmeldung,
      },
    };

class _Fest implements Transport {
  _Fest(this.antwort);
  final Map<String, dynamic> Function() antwort;
  var anfragen = 0;
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    if (pfad == '/api/auth/me') anfragen++;
    return (status: 200, json: antwort());
  }
}

const _app = RosenwegApp(kennung: 'ch.rosenweg4303.test', name: 'Rosenweg Test', ordner: 'rosenweg-test', beschreibung: '');

Future<void> _zeigen(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(theme: rosenwegThema(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('Rechte aus auth/me', () {
    test('Seiten und Zugriff wie permissions der API', () {
      final r = Rechte.ausAuthMe(_me(p: {'reklamationen': 'write', 'energie-monitor': 'read', 'x': 'none'}));
      expect(r.darf('reklamationen', Zugriff.schreiben), isTrue);
      expect(r.darf('energie-monitor'), isTrue);
      expect(r.darf('energie-monitor', Zugriff.schreiben), isFalse);
      expect(r.darf('x'), isFalse);
      expect(r.darf('unbekannt'), isFalse);
      expect(r.darfEine(['unbekannt', 'energie-monitor']), isTrue);
      expect(r.email, 'a@b.ch');
      expect(r.alles, isFalse);
    });

    test('Technik und Praesident duerfen alles, auch Seiten ohne Eintrag', () {
      for (final g in ['Technik', 'präsident', 'Praesident']) {
        final r = Rechte.ausAuthMe(_me(g: [g]));
        expect(r.alles, isTrue, reason: g);
        expect(r.darf('ssh-zugriffsmatrix', Zugriff.schreiben), isTrue);
      }
      expect(Rechte.ausAuthMe(_me(g: ['Ausschuss'])).inGruppe('ausschuss'), isTrue);
    });

    test('Stufe von der API, sonst Ersatz aus der App', () {
      expect(Rechte.ausAuthMe(_me(), ersatzStufe: Anmeldestufe.konto).stufe, Anmeldestufe.konto);
      expect(Rechte.ausAuthMe(_me()).stufeVomServer, isFalse);
      final k = Rechte.ausAuthMe(_me(anmeldung: {'stufe': 'karte'}), ersatzStufe: Anmeldestufe.konto);
      expect(k.stufe, Anmeldestufe.karte);
      expect(k.stufeVomServer, isTrue);
      // auch oben in der Antwort statt in user
      final oben = Rechte.ausAuthMe({...(_me()), 'anmeldung': {'stufe': 'konto'}});
      expect(oben.stufe, Anmeldestufe.konto);
    });

    test('abgelaufene Frische zaehlt als Konto', () {
      final jetzt = DateTime.utc(2026, 11, 27, 12);
      final r = Rechte.ausAuthMe(_me(anmeldung: {'stufe': 'konto-frisch', 'frisch_bis': '2026-11-27T11:59:00Z'}), jetzt: jetzt);
      expect(r.stufe, Anmeldestufe.konto);
      final f = Rechte.ausAuthMe(_me(anmeldung: {'stufe': 'konto-frisch', 'frisch_bis': '2026-11-27T12:05:00Z'}), jetzt: jetzt);
      expect(f.stufe, Anmeldestufe.kontoFrisch);
      expect(f.stufeJetzt(DateTime.utc(2026, 11, 27, 12, 6)), Anmeldestufe.konto);
    });
  });

  group('RosenwegRechte', () {
    test('ein Laden fuer viele Aufrufe; verwerfen fragt neu', () async {
      var n = 0;
      final r = RosenwegRechte(laden: () async {
        n++;
        return _me(p: {'a': 'read'});
      });
      expect(r.darf('a'), isFalse);
      await Future.wait([r.laden(), r.laden(), r.laden()]);
      expect(n, 1);
      expect(r.darf('a'), isTrue);
      r.verwerfen();
      expect(r.darf('a'), isFalse);
      await r.laden();
      expect(n, 2);
    });

    test('Stufe erreichen: bestaetigen, dann neu laden', () async {
      var stufe = 'karte';
      var bestaetigt = 0;
      final r = RosenwegRechte(
        laden: () async => _me(anmeldung: {'stufe': stufe}),
        bestaetigen: () async {
          bestaetigt++;
          stufe = 'konto-frisch';
          return true;
        },
      );
      await r.laden();
      expect(r.hatStufe(Anmeldestufe.konto), isFalse);
      expect(await r.stufeErreichen(Anmeldestufe.konto), isTrue);
      expect(bestaetigt, 1);
      expect(r.hatStufe(Anmeldestufe.kontoFrisch), isTrue);
    });

    test('Fehler beim Laden wird gemerkt', () async {
      final r = RosenwegRechte(laden: () async => throw ServerNichtErreichbar());
      await expectLater(r.laden(), throwsA(isA<ServerNichtErreichbar>()));
      expect(r.fehler, isA<ServerNichtErreichbar>());
      expect(r.laedt, isFalse);
    });
  });

  test('KeineBerechtigung: Stufe und Feldfehler aus der Antwort', () {
    expect(KeineBerechtigung('x', {'error': 'x', 'stufe': 'konto'}).stufeNoetig, 'konto');
    expect(KeineBerechtigung('x', {'error': 'x'}).stufeNoetig, isNull);
    expect(ApiFehler(400, 'Ungültige E-Mail', {'error': 'Ungültige E-Mail', 'feld': 'email'}).feldFehler, {'email': 'Ungültige E-Mail'});
    expect(ApiFehler(400, 'x', {'felder': {'a': 'A fehlt', 'b': 3}}).feldFehler, {'a': 'A fehlt'});
    expect(ApiFehler(400, 'x', {'error': 'x'}).feldFehler, isEmpty);
  });

  group('NurMit', () {
    testWidgets('zeigt mit Recht, versteckt ohne, laedt selbst', (t) async {
      final r = RosenwegRechte(laden: () async => _me(p: {'a': 'write', 'b': 'read'}));
      await _zeigen(
        t,
        RechteBereich(
          rechte: r,
          child: const Column(children: [
            NurMit(recht: 'a', zugriff: Zugriff.schreiben, kind: Text('A')),
            NurMit(recht: 'b', zugriff: Zugriff.schreiben, kind: Text('B'), sonst: Text('B aus')),
            NurMit(recht: 'c', kind: Text('C')),
            NurMit(eines: ['c', 'b'], kind: Text('C oder B')),
          ]),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsNothing);
      expect(find.text('B aus'), findsOneWidget);
      expect(find.text('C'), findsNothing);
      expect(find.text('C oder B'), findsOneWidget);
    });

    testWidgets('ganze Seite: einheitlicher Hinweis', (t) async {
      final r = RosenwegRechte(laden: () async => _me());
      await _zeigen(t, NurMit(rechte: r, recht: 'rechteverwaltung', hinweis: true, kind: const Text('Seite')));
      expect(find.text('Keine Berechtigung'), findsOneWidget);
      expect(find.text(KeineBerechtigungAnzeige.standardText), findsOneWidget);
    });

    testWidgets('Karte reicht nicht: Knopf Rosenweg-Konto, danach sichtbar', (t) async {
      var stufe = 'karte';
      final r = RosenwegRechte(
        laden: () async => _me(g: ['Technik'], anmeldung: {'stufe': stufe}),
        bestaetigen: () async {
          stufe = 'konto';
          return true;
        },
      );
      await _zeigen(t, NurMit(rechte: r, recht: 'proxmox', stufe: Anmeldestufe.konto, hinweis: true, kind: const Text('Proxmox')));
      expect(find.text('Rosenweg-Konto nötig'), findsOneWidget);
      await t.tap(find.text('Mit Rosenweg-Konto anmelden'));
      await t.pumpAndSettle();
      expect(find.text('Proxmox'), findsOneWidget);
    });
  });

  testWidgets('mitBestaetigung: bei 403 reauth fragen, bestaetigen, einmal nochmals', (t) async {
    var versuche = 0;
    var bestaetigt = 0;
    final r = RosenwegRechte(
      laden: () async => _me(),
      bestaetigen: () async {
        bestaetigt++;
        return true;
      },
    );
    String? ergebnis;
    await _zeigen(
      t,
      Builder(
        builder: (c) => FilledButton(
          onPressed: () async {
            ergebnis = await mitBestaetigung(c, rechte: r, () async {
              versuche++;
              if (versuche == 1) throw KeineBerechtigung('Bitte neu anmelden', {'reauth': true});
              return 'ok';
            });
          },
          child: const Text('Los'),
        ),
      ),
    );
    await t.tap(find.text('Los'));
    await t.pumpAndSettle();
    expect(find.text('Bitte bestätigen'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Bestätigen'));
    await t.pumpAndSettle();
    expect(ergebnis, 'ok');
    expect(versuche, 2);
    expect(bestaetigt, 1);
  });

  testWidgets('Sitzung: Rahmen stellt Rechte bereit, neu nach Personenwechsel', (t) async {
    var gruppen = ['Bewohner'];
    final tr = _Fest(() => _me(g: gruppen, p: {'waschkueche': 'read'}));
    final s = RosenwegSitzung(_app, transport: tr);
    await t.pumpWidget(RosenwegRahmen(
      sitzung: s,
      inhalt: (_) => const Scaffold(
        body: Column(children: [
          NurMit(recht: 'waschkueche', kind: Text('Waschküche')),
          NurMit(recht: 'proxmox', kind: Text('Proxmox')),
        ]),
      ),
    ));
    await t.runAsync(s.starten);
    await t.pumpAndSettle();
    expect(find.text('Waschküche'), findsOneWidget);
    expect(find.text('Proxmox'), findsNothing);
    expect(s.darf('waschkueche'), isTrue);
    expect(tr.anfragen, 1);
    gruppen = ['Technik'];
    s.personStand.value++;
    await t.pumpAndSettle();
    expect(tr.anfragen, 2);
    expect(find.text('Proxmox'), findsOneWidget);
  });

  test('Stufe aus der Sitzung, wenn die API keine nennt', () {
    final s = RosenwegSitzung(_app, transport: _Fest(_me));
    expect(RosenwegRechte.stufeAusSitzung(s), Anmeldestufe.keine);
  });
}
