// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

class _Fest implements Transport {
  _Fest(this.antwort);
  final Object? Function(String pfad) antwort;
  final pfade = <String>[];
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async {
    pfade.add(pfad);
    return (status: 200, json: antwort(pfad));
  }
}

typedef _E = ({int id, String name});
_E _wandeln(Map<String, dynamic> j) => (id: j['id'] as int, name: j['name'] as String);

/// 120 Eintraege, Seiten zu [limit], Cursor = Index.
ListenLader<_E> _server({void Function(ListenAnfrage)? gesehen, Object? fehlerAb}) => (a) async {
      gesehen?.call(a);
      final ab = int.tryParse(a.nach ?? '') ?? 0;
      if (fehlerAb != null && ab > 0) throw ServerNichtErreichbar();
      final alle = [for (var i = 0; i < 120; i++) (id: i, name: 'Eintrag $i')]
          .where((e) => a.suche.isEmpty || e.name.contains(a.suche))
          .toList();
      final s = alle.skip(ab).take(a.limit).toList();
      final weiter = ab + s.length;
      return ListenSeite(s, naechster: weiter < alle.length ? '$weiter' : null, gesamt: alle.length);
    };

Future<void> _zeigen(WidgetTester t, Size g, Widget w) async {
  t.view.physicalSize = g;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: rosenwegThema(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('seiteLesen', () {
    test('Cursor: Liste unter Schluessel, naechster, gesamt', () {
      final s = seiteLesen(
        {'reklamationen': [{'id': 1, 'name': 'a'}], 'naechster': 'abc', 'gesamt': 9},
        wandeln: _wandeln,
        schluessel: 'reklamationen',
      );
      expect(s.eintraege.single.name, 'a');
      expect(s.naechster, 'abc');
      expect(s.gesamt, 9);
      expect(seiteLesen({'eintraege': <Object>[], 'naechster': null}, wandeln: _wandeln).naechster, isNull);
    });

    test('Offset: weiter, solange volle Seite bzw. gesamt nicht erreicht', () {
      final voll = [for (var i = 0; i < 10; i++) {'id': i, 'name': '$i'}];
      expect(seiteLesen(voll, wandeln: _wandeln, blaettern: Blaettern.offset, anfrage: const ListenAnfrage(limit: 10)).naechster, '10');
      expect(
          seiteLesen(voll.take(3).toList(), wandeln: _wandeln, blaettern: Blaettern.offset, anfrage: const ListenAnfrage(limit: 10))
              .naechster,
          isNull);
      expect(
          seiteLesen({'rows': voll, 'total': 20},
                  wandeln: _wandeln, blaettern: Blaettern.offset, anfrage: const ListenAnfrage(nach: '10', limit: 10))
              .naechster,
          isNull);
    });

    test('unerwartete Antwort: ApiFehler', () {
      expect(() => seiteLesen('x', wandeln: _wandeln), throwsA(isA<ApiFehler>()));
    });

    test('apiListe baut die Adresse', () async {
      final tr = _Fest((_) => {'eintraege': <Object>[], 'naechster': null});
      final l = apiListe(RosenwegApi(tr), '/api/x?art=1', wandeln: _wandeln, parameter: (a) => {if (a.filter.contains('offen')) 'status': 'offen'});
      await l(const ListenAnfrage(nach: 'c1', suche: 'Müller', filter: {'offen'}, limit: 20));
      final u = Uri.parse(tr.pfade.single);
      expect(u.path, '/api/x');
      expect(u.queryParameters, {'art': '1', 'limit': '20', 'nach': 'c1', 'q': 'Müller', 'status': 'offen'});
      final o = apiListe(RosenwegApi(tr), '/api/y', wandeln: _wandeln, blaettern: Blaettern.offset);
      await o(const ListenAnfrage(nach: '50', sortierung: ListenSortierung('name', aufsteigend: false)));
      expect(Uri.parse(tr.pfade.last).queryParameters, {'limit': '50', 'offset': '50', 'sort': 'name', 'richtung': 'ab'});
    });
  });

  group('ListenSteuerung', () {
    test('Server: erste Seite, mehr laden, Suche laedt neu', () async {
      final anfragen = <ListenAnfrage>[];
      final s = ListenSteuerung<_E>(lader: _server(gesehen: anfragen.add), limit: 50, suchVerzoegerung: Duration.zero);
      await s.neuLaden();
      expect(s.eintraege.length, 50);
      expect(s.hatMehr, isTrue);
      await s.mehrLaden();
      await s.mehrLaden();
      expect(s.eintraege.length, 120);
      expect(s.hatMehr, isFalse);
      s.suchen('Eintrag 11');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(anfragen.last.suche, 'Eintrag 11');
      expect(s.eintraege.map((e) => e.id), [11, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119]);
    });

    test('Fehler beim Weiterladen: Liste bleibt', () async {
      final s = ListenSteuerung<_E>(lader: _server(fehlerAb: true));
      await s.neuLaden();
      await s.mehrLaden();
      expect(s.eintraege.length, 50);
      expect(s.fehlerMehr, isA<ServerNichtErreichbar>());
    });

    test('lokal: suchen, filtern, sortieren, auswaehlen, entfernen', () async {
      final s = ListenSteuerung<_E>.lokal(
        alle: () async => [(id: 1, name: 'Bern'), (id: 2, name: 'Basel'), (id: 3, name: 'Aarau')],
        suchText: (e) => e.name,
        filter: [ListenFilter(id: 'b', titel: 'Mit B', passt: (e) => e.name.startsWith('B'))],
        sortierer: {'name': (a, b) => a.name.compareTo(b.name)},
        schluessel: (e) => e.id,
      );
      await s.neuLaden();
      expect(s.gesamt, 3);
      s.sortieren('name');
      expect(s.eintraege.map((e) => e.name), ['Aarau', 'Basel', 'Bern']);
      s.sortieren('name');
      expect(s.eintraege.first.name, 'Bern');
      s.filterUmschalten('b');
      expect(s.eintraege.length, 2);
      s.suchen('ase');
      expect(s.eintraege.single.name, 'Basel');
      s.suchen('');
      s.alleAuswaehlen();
      expect(s.ausgewaehlt.length, 2);
      s.entfernen(s.eintraege.first);
      expect(s.ausgewaehlt.length, 1);
      expect(s.gesamt, 1);
      expect(s.sortierbar('name'), isTrue);
      expect(s.sortierbar('id'), isFalse);
    });
  });

  group('RosenwegListe', () {
    final spalten = [
      ListenSpalte<_E>(id: 'name', titel: 'Name', text: (e) => e.name, sortierbar: true, flex: 3),
      ListenSpalte<_E>(id: 'id', titel: 'Nr.', text: (e) => '${e.id}', rechts: true),
    ];

    testWidgets('Handy: Kacheln, keine Tabellenkopfzeile, antippen', (t) async {
      _E? getippt;
      final s = ListenSteuerung<_E>(lader: _server());
      await _zeigen(
        t,
        const Size(400, 800),
        RosenwegListe<_E>(steuerung: s, spalten: spalten, kachel: (_, e) => ListTile(title: Text(e.name)), antippen: (e) => getippt = e),
      );
      expect(find.byType(ListTile), findsWidgets);
      expect(find.text('Nr.'), findsNothing);
      expect(find.text('120 Einträge'), findsOneWidget);
      await t.tap(find.text('Eintrag 0'));
      expect(getippt?.id, 0);
    });

    testWidgets('Desktop: Tabelle mit Kopf, Sortieren per Klick, Neu laden', (t) async {
      final anfragen = <ListenAnfrage>[];
      final s = ListenSteuerung<_E>(lader: _server(gesehen: anfragen.add));
      await _zeigen(t, const Size(1280, 800), RosenwegListe<_E>(steuerung: s, spalten: spalten, kachel: (_, e) => Text(e.name)));
      expect(find.text('Nr.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(anfragen.last.sortierung, const ListenSortierung('name'));
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      final vorher = anfragen.length;
      await t.tap(find.byTooltip('Neu laden (F5)'));
      await t.pumpAndSettle();
      expect(anfragen.length, vorher + 1);
    });

    testWidgets('am Ende weiterladen', (t) async {
      final s = ListenSteuerung<_E>(lader: _server(), limit: 30);
      await _zeigen(t, const Size(400, 800), RosenwegListe<_E>(steuerung: s, kachel: (_, e) => ListTile(title: Text(e.name))));
      expect(s.eintraege.length, 30);
      await t.drag(find.byType(ListView), const Offset(0, -3000));
      await t.pumpAndSettle();
      expect(s.eintraege.length, greaterThan(30));
    });

    testWidgets('leer und Fehler', (t) async {
      final leer = ListenSteuerung<_E>.lokal(alle: () async => []);
      await _zeigen(t, const Size(400, 800), RosenwegListe<_E>(steuerung: leer, kachel: (_, e) => Text(e.name), leerText: 'Keine Meldungen.'));
      expect(find.text('Keine Meldungen.'), findsOneWidget);

      final kaputt = ListenSteuerung<_E>(lader: (_) async => throw ServerNichtErreichbar());
      await _zeigen(t, const Size(400, 800), RosenwegListe<_E>(steuerung: kaputt, kachel: (_, e) => Text(e.name)));
      expect(find.text('Das hat nicht geklappt'), findsOneWidget);
      expect(find.text('Nochmals'), findsOneWidget);
    });

    testWidgets('Mehrfachauswahl am Handy: lange druecken, Leiste mit Aktion', (t) async {
      List<_E>? geloescht;
      final s = ListenSteuerung<_E>(lader: _server(), schluessel: (e) => e.id);
      await _zeigen(
        t,
        const Size(400, 800),
        RosenwegListe<_E>(
          steuerung: s,
          mehrfachauswahl: true,
          kachel: (_, e) => ListTile(title: Text(e.name)),
          auswahlAktionen: (_, a) => [IconButton(tooltip: 'Löschen', onPressed: () => geloescht = a, icon: const Icon(Icons.delete))],
        ),
      );
      await t.longPress(find.text('Eintrag 1'));
      await t.pump();
      await t.tap(find.text('Eintrag 2'));
      await t.pump();
      expect(find.text('2 ausgewählt'), findsOneWidget);
      await t.tap(find.byTooltip('Löschen'));
      expect(geloescht?.map((e) => e.id), [1, 2]);
    });
  });
}
