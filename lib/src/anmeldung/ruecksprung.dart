// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../plattform.dart';

/// Wie die Anmeldeseite von Authentik zur App zurueckfindet.
///
/// - Desktop (Linux, Windows, macOS): ein kurzlebiger Port auf localhost
///   (Authentik: Regex `^http://localhost:[0-9]+/anmeldung$`). Der Port kommt
///   vom Betriebssystem, sonst liesse sich die App kein zweites Mal oeffnen.
/// - Android: eigenes Schema `<applicationId>:/anmeldung` (Authentik: strikt,
///   je App ein Eintrag), wie RosenwegAnmeldung in commons-rosenweg. Die
///   RuecksprungActivity des Plugins reicht die Adresse an Dart.
abstract class Anmeldeweg {
  /// Bereitet den Empfang vor und nennt die Ruecksprung-Adresse.
  Future<Ruecksprung> vorbereiten();

  /// Der passende Weg fuer diese Plattform.
  static Anmeldeweg fuer(String telefonRuecksprung) =>
      RosenwegPlattform.istAndroid ? SchemaAnmeldeweg(telefonRuecksprung) : const LocalhostAnmeldeweg();
}

abstract class Ruecksprung {
  /// redirect_uri fuer Authentik.
  String get adresse;

  /// Oeffnet [url] im Browser und wartet auf die Antwort (hoechstens [zeit]).
  /// Wirft [AnmeldungAbgebrochen], wenn [abbrechen] gerufen wurde.
  Future<Uri> warten(Uri url, {Duration zeit = const Duration(minutes: 5)});

  /// Knopf "Abbrechen": Warten beenden, Port schliessen.
  void abbrechen();
}

class AnmeldungAbgebrochen implements Exception {
  @override
  String toString() => 'Anmeldung abgebrochen';
}

/// Oeffnet eine Adresse im Browser; fuer Tests ersetzbar.
typedef BrowserOeffnen = Future<bool> Function(Uri url);

Future<bool> _browser(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

// ── Desktop ────────────────────────────────────────────────────────────────

class LocalhostAnmeldeweg implements Anmeldeweg {
  const LocalhostAnmeldeweg({this.pfad = '/anmeldung', this.oeffnen = _browser});
  final String pfad;
  final BrowserOeffnen oeffnen;

  @override
  Future<Ruecksprung> vorbereiten() async {
    // IPv4 und, wenn moeglich, IPv6 auf demselben Port: "localhost" loest der
    // Browser je nach System zuerst nach ::1 auf.
    final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpServer? v6;
    try {
      v6 = await HttpServer.bind(InternetAddress.loopbackIPv6, v4.port, v6Only: true);
    } catch (_) {
      v6 = null;
    }
    return LocalhostRuecksprung._(v4, v6, 'http://localhost:${v4.port}$pfad', oeffnen);
  }
}

class LocalhostRuecksprung implements Ruecksprung {
  LocalhostRuecksprung._(this._v4, this._v6, this.adresse, this._oeffnen) {
    for (final s in [_v4, if (_v6 != null) _v6]) {
      s.listen(_annehmen);
    }
  }

  final HttpServer _v4;
  final HttpServer? _v6;
  final BrowserOeffnen _oeffnen;
  @override
  final String adresse;
  final _ergebnis = Completer<Uri>();

  static const _antwortSeite = '''<!doctype html><html lang="de"><head><meta charset="utf-8">
<title>Angemeldet</title></head>
<body style="font-family:sans-serif;text-align:center;padding:4em">
<h1>Angemeldet</h1><p>Sie k&ouml;nnen dieses Fenster schliessen und zur App zur&uuml;ckkehren.</p>
<script>setTimeout(function(){window.close()},1500)</script>
</body></html>''';

  void _annehmen(HttpRequest r) {
    final q = r.uri.queryParameters;
    if (!_ergebnis.isCompleted && r.uri.path == Uri.parse(adresse).path && (q.containsKey('code') || q.containsKey('error'))) {
      _ergebnis.complete(r.uri);
    }
    r.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_antwortSeite);
    r.response.close();
  }

  @override
  Future<Uri> warten(Uri url, {Duration zeit = const Duration(minutes: 5)}) async {
    try {
      if (!await _oeffnen(url)) throw StateError('Browser liess sich nicht oeffnen');
      return await _ergebnis.future.timeout(zeit, onTimeout: () => throw AnmeldungAbgebrochen());
    } finally {
      await _v4.close(force: true);
      await _v6?.close(force: true);
    }
  }

  @override
  void abbrechen() {
    if (!_ergebnis.isCompleted) _ergebnis.completeError(AnmeldungAbgebrochen());
  }
}

// ── Android ────────────────────────────────────────────────────────────────

class SchemaAnmeldeweg implements Anmeldeweg {
  const SchemaAnmeldeweg(this.adresse, {this.oeffnen = _browser});
  final String adresse;
  final BrowserOeffnen oeffnen;

  @override
  Future<Ruecksprung> vorbereiten() async => SchemaRuecksprung(adresse, oeffnen, RosenwegPlattform.ruecksprung);
}

class SchemaRuecksprung implements Ruecksprung {
  SchemaRuecksprung(this.adresse, this._oeffnen, Stream<String> ankunft) {
    _abo = ankunft.listen((u) {
      final uri = Uri.tryParse(u);
      if (uri != null && !_ergebnis.isCompleted) _ergebnis.complete(uri);
    });
  }

  @override
  final String adresse;
  final BrowserOeffnen _oeffnen;
  late final StreamSubscription<String> _abo;
  final _ergebnis = Completer<Uri>();

  @override
  Future<Uri> warten(Uri url, {Duration zeit = const Duration(minutes: 5)}) async {
    try {
      if (!await _oeffnen(url)) throw StateError('Browser liess sich nicht oeffnen');
      return await _ergebnis.future.timeout(zeit, onTimeout: () => throw AnmeldungAbgebrochen());
    } finally {
      await _abo.cancel();
    }
  }

  @override
  void abbrechen() {
    if (!_ergebnis.isCompleted) _ergebnis.completeError(AnmeldungAbgebrochen());
  }
}
