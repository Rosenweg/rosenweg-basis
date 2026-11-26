// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

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

  /// Eine Zeile mit Zeitstempel. Wirft nie.
  static void schreiben(String text, [Object? fehler, StackTrace? stapel]) {
    final zeile = StringBuffer('${DateTime.now().toIso8601String()} $text');
    if (fehler != null) zeile.write(': $fehler');
    if (stapel != null) zeile.write('\n$stapel');
    try {
      stderr.writeln(zeile);
    } catch (_) {}
    final p = pfad;
    if (p == null) return;
    try {
      File(p).writeAsStringSync('$zeile\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
