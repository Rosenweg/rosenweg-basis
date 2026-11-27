// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Logdatei der App, damit Fehler nicht still verschwinden.
///
/// - Linux:   `$XDG_STATE_HOME/<ordner>/app.log` (sonst `~/.local/state/…`)
/// - macOS:   `~/Library/Logs/<ordner>/app.log`
/// - Windows: `%LOCALAPPDATA%\<ordner>\app.log`
/// - Telefone: temporaerer Ordner der App
///
/// Nie Tokens, Passwoerter oder personenbezogene Inhalte hineinschreiben;
/// Status und Pfad genuegen. Die Datei wird bei ueber 1 MB beim Start einmal
/// nach app.log.1 verschoben. (Aus rosenweg-vm lib/protokoll.dart.)
class Protokoll {
  Protokoll._();

  static String _ordner = 'rosenweg-app';
  static String? _pfad;
  static bool _bestimmt = false;

  /// Einmal beim Start (rosenwegStarten setzt es).
  static void einrichten(String ordner) {
    _ordner = ordner;
    _pfad = null;
    _bestimmt = false;
  }

  /// Nur fuer Tests: keine Datei, nur stderr.
  static bool nurKonsole = false;

  static String? get pfad {
    if (nurKonsole) return null;
    if (!_bestimmt) {
      _pfad = _bestimmen();
      _bestimmt = true;
    }
    return _pfad;
  }

  static String? _bestimmen() {
    try {
      final env = Platform.environment;
      final home = env['HOME'] ?? '';
      final String ordner;
      if (Platform.isMacOS && home.isNotEmpty) {
        ordner = '$home/Library/Logs/$_ordner';
      } else if (Platform.isLinux && home.isNotEmpty) {
        ordner = '${env['XDG_STATE_HOME'] ?? '$home/.local/state'}/$_ordner';
      } else if (Platform.isWindows && (env['LOCALAPPDATA'] ?? '').isNotEmpty) {
        ordner = '${env['LOCALAPPDATA']}\\$_ordner';
      } else {
        ordner = '${Directory.systemTemp.path}/$_ordner';
      }
      Directory(ordner).createSync(recursive: true);
      final datei = File('$ordner${Platform.pathSeparator}app.log');
      if (datei.existsSync() && datei.lengthSync() > 1024 * 1024) {
        datei.renameSync('${datei.path}.1');
      }
      return datei.path;
    } catch (_) {
      return null;
    }
  }

  /// Nur fuer Tests: statt stderr (z. B. ein IOSink, dessen Schreiben
  /// asynchron scheitert) und Mithoeren der Zeilen.
  @visibleForTesting
  static IOSink Function()? konsoleFuerTests;
  @visibleForTesting
  static void Function(String zeile)? mithoeren;
  @visibleForTesting
  static bool? windowsFuerTests;

  /// Konsole: null = noch nicht bestimmt, sonst der Sink oder "keine".
  static IOSink? _konsole;
  static bool _konsoleBestimmt = false;

  /// Fuer Tests: Konsole neu bestimmen.
  @visibleForTesting
  static void konsoleVergessen() {
    _konsole = null;
    _konsoleBestimmt = false;
  }

  /// stderr nur, wo es eine gibt. Windows-Apps ohne Konsole (Start ueber das
  /// Startmenue) haben einen ungueltigen stderr-Handle; das Schreiben
  /// scheitert dort ASYNCHRON (`FileSystemException: writeFrom failed`), am
  /// try/catch vorbei, und landete als "unerwarteter Fehler" in der App
  /// (Test win11-1, 27.11.2026). Darum: auf Windows nur mit Konsole, Pipe
  /// oder Datei; und ueberall die Fehler des Sinks abfangen und danach
  /// schweigen.
  static IOSink? get _konsoleOderNichts {
    if (_konsoleBestimmt) return _konsole;
    _konsoleBestimmt = true;
    IOSink? k;
    try {
      if (konsoleFuerTests != null) {
        k = konsoleFuerTests!();
      } else if (windowsFuerTests ?? Platform.isWindows) {
        final art = stdioType(stderr);
        k = art == StdioType.terminal || art == StdioType.pipe || art == StdioType.file ? stderr : null;
      } else {
        k = stderr;
      }
    } catch (_) {
      k = null;
    }
    if (k != null) {
      final sink = k;
      // Fehler des Sinks (auch spaetere) nie unbehandelt lassen.
      unawaited(sink.done.then<void>((_) {}, onError: (Object _) {
        if (identical(_konsole, sink)) _konsole = null;
      }));
    }
    return _konsole = k;
  }

  /// Eine Zeile mit Zeitstempel. Wirft nie, auch nicht spaeter.
  static void schreiben(String text, [Object? fehler, StackTrace? stapel]) {
    final zeile = StringBuffer('${DateTime.now().toIso8601String()} $text');
    if (fehler != null) zeile.write(': $fehler');
    if (stapel != null) zeile.write('\n$stapel');
    mithoeren?.call('$zeile');
    try {
      _konsoleOderNichts?.writeln(zeile);
    } catch (_) {
      _konsole = null;
    }
    final p = pfad;
    if (p == null) return;
    try {
      File(p).writeAsStringSync('$zeile\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
