import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

Map<String, dynamic> _me({Map<String, String> p = const {}, List<String> g = const []}) => {
  'user': {'email': 'a@b.ch', 'name': 'Anna', 'groups': g, 'permissions': p},
};

Rechte _r({Map<String, String> p = const {}, List<String> g = const []}) => Rechte.ausAuthMe(_me(p: p, g: g));

class _Fest implements Transport {
  _Fest(this.antwort);
  final Map<String, dynamic> Function() antwort;
  @override
  Future<ApiAntwort> senden(String methode, String pfad, {Object? koerper}) async => (status: 200, json: antwort());
}

const _immerRot = RosenwegApp(
  kennung: 'ch.rosenweg4303.a',
  name: 'A',
  ordner: 'a',
  beschreibung: '',
  gruppe: RosenwegGruppe.bewohner,
);
const _dreiFarben = RosenwegApp(
  kennung: 'ch.rosenweg4303.b',
  name: 'B',
  ordner: 'rosenweg-b',
  beschreibung: '',
  gruppe: RosenwegGruppe.bewohner,
  farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},
);
const _mitRecht = RosenwegApp(
  kennung: 'ch.rosenweg4303.c',
  name: 'C',
  ordner: 'c',
  beschreibung: '',
  gruppe: RosenwegGruppe.bewohner,
  farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},
  farbRechte: {'waschküche-admin'},
);
const _nurTechnik = RosenwegApp(
  kennung: 'ch.rosenweg4303.d',
  name: 'D',
  ordner: 'd',
  beschreibung: '',
  gruppe: RosenwegGruppe.bewohner,
  farbGruppen: {RosenwegGruppe.technik},
);

void main() {
  setUpAll(() => Protokoll.nurKonsole = true);

  group('Farbe nach freigeschalteter Funktion', () {
    test('ohne farbGruppen immer die Standardfarbe', () {
      expect(gruppeAusRechten(_immerRot, _r(g: ['technik'])), RosenwegGruppe.bewohner);
      expect(gruppeAusRechten(_immerRot, _r(g: ['stweg3-ausschuss'])), RosenwegGruppe.bewohner);
    });

    test('Technik und Praesident gruen, Ausschuss und Verwaltung blau, sonst rot', () {
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['technik'])), RosenwegGruppe.technik);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['Präsident'])), RosenwegGruppe.technik);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['r9-eigentuemer', 'stweg3-ausschuss'])), RosenwegGruppe.verwaltung);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['meg-ausschuss'])), RosenwegGruppe.verwaltung);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['stweg6-verwaltung'])), RosenwegGruppe.verwaltung);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['meg-verwaltung'])), RosenwegGruppe.verwaltung);
      expect(gruppeAusRechten(_dreiFarben, _r(g: ['r9-bewohner', 'stweg3-eigentuemer'])), RosenwegGruppe.bewohner);
      expect(gruppeAusRechten(_dreiFarben, null), RosenwegGruppe.bewohner);
    });

    test('mit farbRechte zaehlt das Seitenrecht, nicht die Gruppe', () {
      expect(gruppeAusRechten(_mitRecht, _r(g: ['stweg3-ausschuss'])), RosenwegGruppe.bewohner);
      expect(
        gruppeAusRechten(_mitRecht, _r(g: ['stweg3-verwaltung'], p: {'waschküche-admin': 'read'})),
        RosenwegGruppe.verwaltung,
      );
      expect(gruppeAusRechten(_mitRecht, _r(g: ['x'], p: {'waschküche-admin': 'none'})), RosenwegGruppe.bewohner);
      expect(gruppeAusRechten(_mitRecht, _r(g: ['technik'])), RosenwegGruppe.technik);
    });

    test('nur Technik: Ausschuss bleibt rot', () {
      expect(gruppeAusRechten(_nurTechnik, _r(g: ['stweg3-ausschuss'])), RosenwegGruppe.bewohner);
      expect(gruppeAusRechten(_nurTechnik, _r(g: ['technik'])), RosenwegGruppe.technik);
    });

    test('mit farbRechteTechnik gruen nach Seitenrecht (Rosenweg Energie)', () {
      const energie = RosenwegApp(
        kennung: 'e',
        name: 'E',
        ordner: 'e',
        beschreibung: '',
        gruppe: RosenwegGruppe.bewohner,
        farbGruppen: {RosenwegGruppe.verwaltung, RosenwegGruppe.technik},
        farbRechte: {'energie-stweg'},
        farbRechteTechnik: {'energie-config'},
      );
      // energie-config lesen genuegt fuer Gruen
      expect(gruppeAusRechten(energie, _r(g: ['x'], p: {'energie-config': 'read'})), RosenwegGruppe.technik);
      // gruen schlaegt blau
      expect(
        gruppeAusRechten(energie, _r(g: ['stweg3-verwaltung'], p: {'energie-stweg': 'read', 'energie-config': 'read'})),
        RosenwegGruppe.technik,
      );
      expect(
        gruppeAusRechten(energie, _r(g: ['stweg3-verwaltung'], p: {'energie-stweg': 'read'})),
        RosenwegGruppe.verwaltung,
      );
      // automatisches energie-monitor (jeder mit Zaehler) bleibt rot, ebenso Zaehler-Technik
      expect(
        gruppeAusRechten(energie, _r(g: ['r9-eigentuemer'], p: {'energie-monitor': 'read', 'zaehler-technik': 'read'})),
        RosenwegGruppe.bewohner,
      );
      expect(gruppeAusRechten(energie, _r(g: ['technik'])), RosenwegGruppe.technik);
      // ohne farbGruppen technik nuetzt das Recht nichts
      expect(gruppeAusRechten(_mitRecht, _r(g: ['x'], p: {'energie-config': 'read'})), RosenwegGruppe.bewohner);
    });

    test('nie unter die Mindestfarbe', () {
      const gruen = RosenwegApp(
        kennung: 'x',
        name: 'X',
        ordner: 'x',
        beschreibung: '',
        gruppe: RosenwegGruppe.technik,
        farbGruppen: {RosenwegGruppe.verwaltung},
      );
      expect(gruppeAusRechten(gruen, _r(g: ['stweg3-ausschuss'])), RosenwegGruppe.technik);
    });

    test('Logo je Farbe', () {
      expect(
        (_dreiFarben.logoFuer(RosenwegGruppe.technik, klein: true) as AssetImage).assetName,
        'assets/logo/rosenweg-b-technik-klein.png',
      );
      expect(
        (_dreiFarben.logoFuer(RosenwegGruppe.verwaltung) as AssetImage).assetName,
        'assets/logo/rosenweg-b-verwaltung-512.png',
      );
      expect(
        (_dreiFarben.logoFuer(RosenwegGruppe.bewohner, klein: true) as AssetImage).assetName,
        'assets/logo/rosenweg-b-klein.png',
      );
    });
  });

  testWidgets('Sitzung: Farbe nach Anmeldung, Personenwechsel, zurueck beim Abmelden', (t) async {
    RosenwegPlattform.plattformFuerTests = TargetPlatform.linux;
    addTearDown(() => RosenwegPlattform.plattformFuerTests = null);
    var gruppen = ['technik'];
    final s = RosenwegSitzung(_dreiFarben, transport: _Fest(() => _me(g: gruppen)));
    await t.pumpWidget(
      RosenwegRahmen(
        sitzung: s,
        inhalt: (_) => const Scaffold(body: Text('drin')),
      ),
    );
    expect(s.farbe.value, RosenwegGruppe.bewohner);
    await t.runAsync(s.starten);
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(s.phase, Phase.bereit);
    expect(s.farbe.value, RosenwegGruppe.technik);
    final thema = Theme.of(t.element(find.text('drin')));
    expect(
      thema.colorScheme.primary,
      isNot(rosenwegThema(Brightness.light, RosenwegGruppe.bewohner).colorScheme.primary),
    );

    gruppen = ['stweg3-ausschuss'];
    s.personStand.value++;
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(s.farbe.value, RosenwegGruppe.verwaltung);

    await t.runAsync(s.abmelden);
    await t.pumpAndSettle();
    expect(s.farbe.value, RosenwegGruppe.bewohner);
  });
}
