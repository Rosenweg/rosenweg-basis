// SPDX-License-Identifier: GPL-3.0-or-later
/// Erinnerungen vor Terminen: die App sagt bei jedem Laden, welche sie
/// haben moechte ([Erinnerungen.abgleichen]); die Basis plant neue und
/// geaenderte ein und entfernt weggefallene (Termin geloescht, verschoben,
/// Erinnerung ausgeschaltet). Ohne eigene Buchhaltung: was geplant ist,
/// weiss das System ([Benachrichtigung.geplant]).
///
/// ```dart
/// await Erinnerungen.abgleichen(sitzung, [
///   for (final t in termine)
///     Erinnerung(schluessel: 'termin-${t.id}', wann: t.beginn.subtract(const Duration(hours: 1)),
///         titel: t.titel, text: 'Heute um 19:00 · Gemeinschaftsraum', ziel: 'termin/${t.id}'),
/// ]);
/// await Erinnerungen.alleEntfernen();   // z. B. beim Abmelden
/// ```
///
/// Geteilte Telefone: wie am eigenen Geraet. Beim Personenwechsel und Abmelden
/// entfernt [RosenwegSitzung] alle geplanten Erinnerungen ([alleEntfernen]), Rosenweg
/// Geraet loescht danach die App-Daten: keine Erinnerung der vorigen Person bleibt.
///
/// Gilt fuer alle *geplanten* Benachrichtigungen der App; sofort gezeigte
/// ([Benachrichtigung.zeigen]) bleiben unberuehrt. Linux: nur solange die
/// App laeuft (beim naechsten Start plant [abgleichen] neu).
library;

import 'benachrichtigung.dart';
import 'sitzung.dart';

class Erinnerung {
  const Erinnerung({required this.schluessel, required this.wann, required this.titel, required this.text, this.ziel});

  /// Fest je Erinnerung, z. B. `termin-42` (daraus die Id der Benachrichtigung).
  final String schluessel;
  final DateTime wann;
  final String titel;
  final String text;

  /// Beim Antippen ([Benachrichtigung.angetippt]).
  final String? ziel;

  int get id => Erinnerungen.idFuer(schluessel);
}

class Erinnerungen {
  Erinnerungen._();

  /// Android-Kanal (eigene Einstellung „Erinnerungen“ in den App-Einstellungen).
  static const kanal = 'erinnerungen';

  static int idFuer(String schluessel) => Benachrichtigung.idFuer('erinnerung:$schluessel');

  /// Plant [soll] (nur die in der Zukunft) und entfernt alle anderen
  /// geplanten Benachrichtigungen der App. Rueckgabe: Zahl der geplanten.
  /// [geteilt] wird nicht mehr gebraucht (geteilte Telefone planen wie alle).
  static Future<int> abgleichen(RosenwegSitzung? sitzung, Iterable<Erinnerung> soll, {@Deprecated('ohne Wirkung') bool? geteilt}) async {
    if (sitzung != null) await Benachrichtigung.einrichten(sitzung.app);
    final jetzt = DateTime.now();
    final kommend = {for (final e in soll) if (e.wann.isAfter(jetzt)) e.id: e};
    for (final id in await Benachrichtigung.geplant()) {
      if (!kommend.containsKey(id)) await Benachrichtigung.entfernen(id);
    }
    for (final e in kommend.values) {
      // gleiche Id ersetzt die fruehere (neue Zeit, neuer Text)
      await Benachrichtigung.planen(id: e.id, wann: e.wann, titel: e.titel, text: e.text, ziel: e.ziel, kanal: kanal);
    }
    return kommend.length;
  }

  /// Alle geplanten Erinnerungen der App entfernen (Abmelden, Personenwechsel).
  static Future<void> alleEntfernen() async {
    for (final id in await Benachrichtigung.geplant()) {
      await Benachrichtigung.entfernen(id);
    }
  }
}
