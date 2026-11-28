// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

void main() {
  test('mqttThemaPasst: + eine Ebene, # der Rest', () {
    expect(mqttThemaPasst('wetter/r9/#', 'wetter/r9/outdoortemp'), isTrue);
    expect(mqttThemaPasst('wetter/r9/#', 'wetter/r9'), isTrue);
    expect(mqttThemaPasst('wetter/+/outdoortemp', 'wetter/r9/outdoortemp'), isTrue);
    expect(mqttThemaPasst('wetter/+/outdoortemp', 'wetter/r9/info/x'), isFalse);
    expect(mqttThemaPasst('wetter/r9/rain', 'wetter/r9/rain_piezo'), isFalse);
    expect(mqttThemaPasst('energy/#', 'wetter/r9/rain'), isFalse);
  });

  test('MqttNachricht: Feld, Zahl, JSON', () {
    final n = MqttNachricht('wetter/r9/pressureabs', ' 991.7 ', zeit: DateTime(2026));
    expect(n.feld, 'pressureabs');
    expect(n.zahl, 991.7);
    expect(MqttNachricht('a/b', '{"x":1}', zeit: DateTime(2026)).json, {'x': 1});
    expect(MqttNachricht('a/b', 'WNW', zeit: DateTime(2026)).zahl, isNull);
  });

  test('Attrappe: gespeicherte Werte sofort, neue danach; nur neue zaehlen als live', () async {
    final e = EchtzeitAttrappe({'wetter/r9/outdoortemp': '4.2', 'display/emergency': '{}'});
    final erhalten = <String>[];
    final sub = e.abonnieren('wetter/r9/#').listen((n) => erhalten.add('${n.feld}=${n.text}${n.behalten ? ' R' : ''}'));
    await Future<void>.delayed(Duration.zero);
    expect(erhalten, ['outdoortemp=4.2 R']);
    expect(e.zustand.value.stand, EchtzeitStand.live);
    expect(e.zustand.value.letzteNachricht, isNull, reason: 'retained kann alt sein');

    e.senden('wetter/r9/outdoortemp', '4.3');
    e.senden('energy/r9/x', '1'); // anderes Thema: nicht in diesem Abo
    await Future<void>.delayed(Duration.zero);
    expect(erhalten, ['outdoortemp=4.2 R', 'outdoortemp=4.3']);
    expect(e.zustand.value.letzteNachricht, isNotNull);
    expect(e.zustand.value.veraltet(const Duration(minutes: 5)), isFalse);
    expect(e.zustand.value.veraltet(const Duration(minutes: 5), jetzt: DateTime.now().add(const Duration(minutes: 6))), isTrue);

    // spaeteres Abo bekommt den letzten Stand
    final spaet = await e.abonnieren('wetter/r9/outdoortemp').first;
    expect(spaet.text, '4.3');
    await sub.cancel();
    await e.schliessen();
    expect(e.zustand.value.stand, EchtzeitStand.geschlossen);
  });

  test('MqttZugang.fest liefert den festen Benutzer', () async {
    final a = await const MqttZugang.fest('leser', 'geheim').holen();
    expect(a.benutzer, 'leser');
  });

  testWidgets('EchtzeitAnzeige: wartet, live, veraltet, getrennt mit Nochmals', (t) async {
    final e = EchtzeitAttrappe({'wetter/r9/rain': '0'});
    final sub = e.abonnieren('wetter/r9/#').listen((_) {});
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: EchtzeitAnzeige(quelle: e)))));
    await t.pump();
    expect(find.text('verbunden · wartet auf neue Werte'), findsOneWidget);

    e.senden('wetter/r9/rain', '0.4');
    await t.pump();
    expect(find.textContaining('live · Stand '), findsOneWidget);

    e.standSetzen(EchtzeitStand.getrennt);
    await t.pump();
    expect(find.textContaining('getrennt'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await t.tap(find.byType(EchtzeitAnzeige));
    await t.pump();
    expect(find.textContaining('live'), findsOneWidget);

    final f = ColorScheme.fromSeed(seedColor: Colors.red);
    final z = EchtzeitZustand(EchtzeitStand.live, letzteNachricht: DateTime(2026, 11, 28, 9, 5));
    expect(EchtzeitAnzeige.beschreiben(z, const Duration(minutes: 5), f, jetzt: DateTime(2026, 11, 28, 9, 30)).$1, 'veraltet · Stand 09:05');
    await t.pumpWidget(const SizedBox());
    unawaited(sub.cancel());
    unawaited(e.schliessen());
  });
}
