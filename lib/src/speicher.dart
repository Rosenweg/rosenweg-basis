// SPDX-License-Identifier: GPL-3.0-or-later
/// Kleiner Ablageort der App fuer nicht geheime Werte (zuletzt gesehener
/// Stand, gewaehlte Ansicht …), damit eine App beim naechsten Oeffnen weiss,
/// was neu ist. Geheimnisse gehoeren in den Schluesselbund, nie hierher.
///
/// Eine JSON-Datei `speicher.json` im Ordner fuer App-Daten
/// (`getApplicationSupportDirectory`: Linux `~/.local/share/<kennung>`,
/// Windows `%APPDATA%\…`, macOS/iOS `Application Support`, Android
/// `files`). Geht die Datei nicht (Tests, schreibgeschuetzt), bleibt alles im
/// Speicher – die App laeuft weiter, sie vergisst nur beim Beenden.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'protokoll.dart';

class AppSpeicher {
  AppSpeicher._(this._datei);

  /// Nur im Speicher (Tests, Attrappe).
  AppSpeicher.imSpeicher() : _datei = null {
    _werte = {};
  }

  /// Datei in einem bestimmten Ordner (Tests).
  AppSpeicher.inOrdner(Directory ordner) : _datei = File('${ordner.path}${Platform.pathSeparator}speicher.json');

  static AppSpeicher? _app;

  /// Der Speicher der laufenden App (einmal angelegt).
  static Future<AppSpeicher> app() async {
    final a = _app;
    if (a != null) return a;
    File? datei;
    try {
      final d = await getApplicationSupportDirectory();
      await d.create(recursive: true);
      datei = File('${d.path}${Platform.pathSeparator}speicher.json');
    } catch (e) {
      Protokoll.schreiben('Speicher: kein Ordner fuer App-Daten, nur im Speicher', e);
    }
    return _app = AppSpeicher._(datei);
  }

  final File? _datei;
  Map<String, Object?>? _werte;
  Future<void> _schreibt = Future.value();

  Future<Map<String, Object?>> _laden() async {
    final w = _werte;
    if (w != null) return w;
    var neu = <String, Object?>{};
    try {
      final d = _datei;
      if (d != null && await d.exists()) {
        final j = jsonDecode(await d.readAsString());
        if (j is Map) neu = j.cast<String, Object?>();
      }
    } catch (e) {
      Protokoll.schreiben('Speicher: Datei unlesbar, beginne leer', e);
    }
    return _werte ??= neu;
  }

  /// Wert lesen (JSON: Zahl, Text, Liste, Map, bool) oder null.
  Future<Object?> lesen(String schluessel) async => (await _laden())[schluessel];

  /// Wert setzen (null = entfernen). Schreibt die Datei der Reihe nach.
  Future<void> schreiben(String schluessel, Object? wert) async {
    final w = await _laden();
    if (wert == null) {
      w.remove(schluessel);
    } else {
      w[schluessel] = wert;
    }
    final d = _datei;
    if (d == null) return;
    final text = jsonEncode(w);
    _schreibt = _schreibt.then((_) async {
      try {
        final tmp = File('${d.path}.neu');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(d.path);
      } catch (e) {
        Protokoll.schreiben('Speicher: schreiben ging nicht', e);
      }
    });
    await _schreibt;
  }
}

/// Was hat sich seit dem letzten Blick geaendert? Fuer "Abfrage beim
/// Oeffnen" statt Push: die App laedt ihre Liste, uebergibt je Eintrag einen
/// Stand (z. B. `id → status`) und bekommt die Eintraege, die neu sind oder
/// einen anderen Stand haben als beim letzten Mal.
///
/// ```dart
/// final n = Neuigkeiten(await AppSpeicher.app(), 'meine-meldungen');
/// final geaendert = await n.vergleichen({for (final m in meldungen) '${m.id}': m.status});
/// ```
///
/// Beim allerersten Mal (noch nichts gemerkt) gilt nichts als neu – sonst
/// waere nach dem Einrichten alles "neu".
class Neuigkeiten {
  Neuigkeiten(this.speicher, this.schluessel);
  final AppSpeicher speicher;
  final String schluessel;

  String get _k => 'neuigkeiten:$schluessel';

  /// Vergleicht [jetzt] mit dem gemerkten Stand und merkt sich [jetzt].
  /// Liefert die Schluessel, die neu sind oder sich geaendert haben.
  /// [merken] false: nur vergleichen (z. B. solange die Person die Liste
  /// noch nicht gesehen hat).
  Future<List<String>> vergleichen(Map<String, String> jetzt, {bool merken = true}) async {
    final vorher = await speicher.lesen(_k);
    final alt = vorher is Map ? vorher.map((k, v) => MapEntry('$k', '$v')) : null;
    if (merken) await speicher.schreiben(_k, jetzt);
    if (alt == null) return const [];
    return [
      for (final e in jetzt.entries)
        if (alt[e.key] != e.value) e.key,
    ];
  }

  /// Gemerkten Stand vergessen.
  Future<void> vergessen() => speicher.schreiben(_k, null);
}
