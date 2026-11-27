// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'aktualisierung.dart';
import 'anmeldung/karten_sitzung.dart';
import 'anmeldung/rosenweg_konto.dart';
import 'anmeldung/ruecksprung.dart';
import 'netz/fehler.dart';

/// Ausnahme → ein ganzer deutscher Satz fuer die Person, dazu die
/// technischen Einzelheiten fuer "Details" (aufklappbar in [FehlerAnzeige]).
///
/// Die Fehler der Basis ([ApiFehler], [ServerNichtErreichbar],
/// [AnmeldeFehler], [KartenFehler] …) haben schon einen Satz als Text: der
/// wird gezeigt, ohne Details. Alles andere (StateError, FormatException …)
/// kam frueher roh auf den Schirm ("Bad state: Browser liess sich nicht
/// oeffnen", Test win11-1) - jetzt ein verstaendlicher Satz, der rohe Text
/// nur unter "Details".
({String text, String? details}) fehlerFuerPerson(Object e) {
  if (e is ServerNichtErreichbar ||
      e is ZuVieleAnfragen ||
      e is ApiFehler ||
      e is GeraetFehler ||
      e is AnmeldeFehler ||
      e is AnmeldungAbgebrochen ||
      e is BrowserNichtGeoeffnet ||
      e is KartenFehler ||
      e is AktualisierungsFehler) {
    return (text: '$e', details: null);
  }
  final details = '${e.runtimeType}: $e';
  if (e is SocketException || e is TimeoutException || e is HttpException || e is http.ClientException || e is HandshakeException) {
    return (
      text: 'Keine Verbindung zum Rosenweg-Server. Bitte die Netzverbindung prüfen und nochmals versuchen.',
      details: details,
    );
  }
  return (text: 'Etwas ist unerwartet schiefgegangen. Bitte nochmals versuchen.', details: details);
}
