// SPDX-License-Identifier: GPL-3.0-or-later
// Fehler, die eine App der Person zeigen kann. Der Text (toString) ist
// immer ein ganzer deutscher Satz, ohne Technik.

/// Server (API, Authentik) gerade nicht erreichbar: Neustart, 502/503/504 vom
/// Webserver, HTML statt JSON, Verbindung abgebrochen.
class ServerNichtErreichbar implements Exception {
  @override
  String toString() => 'Der Rosenweg-Server ist gerade nicht erreichbar – bitte gleich nochmals versuchen.';
}

/// 429: zu viele Anfragen; [warten] aus Retry-After, falls angegeben.
class ZuVieleAnfragen implements Exception {
  ZuVieleAnfragen(this.warten);
  final Duration? warten;
  @override
  String toString() {
    final w = warten;
    if (w == null) return 'Zu viele Anfragen – bitte etwas später nochmals versuchen.';
    if (w.inSeconds < 120) return 'Zu viele Anfragen – bitte in ${w.inSeconds} Sekunden nochmals versuchen.';
    return 'Zu viele Anfragen – bitte in ${(w.inSeconds / 60).ceil()} Minuten nochmals versuchen.';
  }
}

/// Antwort der API mit Fehlerstatus. [text] ist das Feld `error` der Antwort
/// (so liefert es api/server.js), sonst ein allgemeiner Satz.
class ApiFehler implements Exception {
  ApiFehler(this.status, this.text, [this.json]);
  final int status;
  final String text;

  /// Ganze Antwort, z. B. fuer `hint` oder `reauth`.
  final Object? json;

  /// Zusatzfeld der Antwort, falls vorhanden.
  String? feld(String name) {
    final j = json;
    return j is Map && j[name] is String ? j[name] as String : null;
  }

  /// Fehler zu einzelnen Formularfeldern, falls die API sie nennt:
  /// `felder: {name: "Text"}` oder `feld: "name"` (dann gilt `error` fuer
  /// dieses Feld). Leer, wenn die API nur einen allgemeinen Text schickt —
  /// [RosenwegFormular] zeigt ihn dann oben im Formular.
  Map<String, String> get feldFehler {
    final j = json;
    if (j is! Map) return const {};
    final f = j['felder'];
    if (f is Map) {
      return {for (final e in f.entries) if (e.value is String) '${e.key}': e.value as String};
    }
    final eins = j['feld'];
    if (eins is String && eins.isNotEmpty) return {eins: text};
    return const {};
  }

  @override
  String toString() => text;
}

/// 401 oder keine (gueltige) Anmeldung mehr.
class NichtAngemeldet extends ApiFehler {
  NichtAngemeldet([String text = 'Bitte wieder mit dem Rosenweg-Konto anmelden.', Object? json]) : super(401, text, json);
}

/// 403: angemeldet, aber nicht berechtigt (oder `reauth: true`: frische
/// Anmeldung noetig, z. B. fuer den Passwortwechsel).
class KeineBerechtigung extends ApiFehler {
  KeineBerechtigung(String text, [Object? json]) : super(403, text, json);

  bool get neuAnmelden {
    final j = json;
    return j is Map && j['reauth'] == true;
  }

  /// Die Route verlangt eine hoehere Stufe der Anmeldung (API-Middleware
  /// `verlangtKonto`, Plan 4.2.1): `stufe: "konto"` oder `"konto-frisch"`
  /// in der 403-Antwort. null = gewoehnliches "keine Berechtigung".
  String? get stufeNoetig {
    final j = json;
    final s = j is Map ? j['stufe'] : null;
    return s is String && s.isNotEmpty ? s : null;
  }
}

/// 202 `{bestaetigung: 'email', id, ablauf, email, hinweis}`: Die Aktion war
/// mit einer Karten-, QR- oder Handy-Sitzung heikel (api/lib/kartenadmin.js,
/// „Karte wie Schlüssel“) und laeuft erst, wenn die Person den Link in der
/// E-Mail bestaetigt. Nichts ist passiert – die App zeigt das
/// ([zeigeEmailBestaetigung]) statt „Gespeichert.“.
class BestaetigungPerEmail extends ApiFehler {
  BestaetigungPerEmail(Object? json)
      : super(202, _hinweis(json), json);

  static String _hinweis(Object? j) {
    final h = j is Map ? j['hinweis'] : null;
    if (h is String && h.isNotEmpty) return h;
    return 'Bitte bestätige die Aktion in der E-Mail, die wir dir geschickt haben.';
  }

  /// Kennung der wartenden Aktion (`kb_…`).
  String? get id => feld('id');

  /// Maskierte Adresse, an die die Mail ging (`e…@example.org`).
  String? get email => feld('email');

  /// Bis wann der Link gilt.
  DateTime? get ablauf => DateTime.tryParse(feld('ablauf') ?? '')?.toLocal();

  /// Antwort der API ist eine solche Rueckfrage?
  static bool ist(int status, Object? json) => status == 202 && json is Map && json['bestaetigung'] == 'email';
}

/// Rosenweg Geraet (geteiltes Telefon) kann die Anfrage nicht weiterreichen.
class GeraetFehler implements Exception {
  GeraetFehler(this.text);
  final String text;
  @override
  String toString() => text;
}

/// Der Browser fuer die Anmeldung liess sich nicht oeffnen (kein
/// Standard-Browser, gesperrt).
class BrowserNichtGeoeffnet implements Exception {
  @override
  String toString() => 'Der Browser für die Anmeldung liess sich nicht öffnen. '
      'Bitte einen Standard-Browser einrichten und nochmals versuchen.';
}
