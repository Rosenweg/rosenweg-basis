// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'verwaltet_registry.dart';

/// Ist die App eine VERWALTETE Installation, die jemand anderes aktualisiert
/// (Windows-Domaene per GPO)? Dann ist der Updater der App aus.
///
/// Hintergrund (Test win11-1, 27.11.2026): Auf den Domaenen-PCs erlaubt
/// AppLocker normalen Benutzern nur Programme aus `%PROGRAMFILES%` und
/// `%WINDIR%`. Eine Installation pro Person (`%LOCALAPPDATA%\Programs`) wird
/// geblockt, ebenso der Updater, der den Installer aus dem Profil startet.
/// Auf diesen PCs kommt die App per GPO mit `/ALLUSERS` nach
/// `C:\Program Files`, und Updates kommen ebenfalls per GPO.
///
/// Verwaltet ist eine Installation, wenn
///
/// - die laufende .exe unter `%ProgramFiles%`, `%ProgramW6432%`,
///   `%ProgramFiles(x86)%` oder `%WINDIR%` liegt (Installation fuer alle,
///   `/ALLUSERS`; der Installer bietet das nur auf der Befehlszeile an), oder
/// - die GPO den Schalter `Verwaltet` = 1 (DWORD oder Text) setzt, unter
///   `HKLM\Software\Policies\Rosenweg` oder `HKLM\Software\Rosenweg`.
///
/// Auf Linux und macOS gibt es (noch) keine verwaltete Installation:
/// Rosenweg-Stationen erkennt [RosenwegStation].
class RosenwegVerwaltet {
  RosenwegVerwaltet._();

  /// Registry-Schluessel (unter HKLM), in dieser Reihenfolge.
  static const schluessel = [r'Software\Policies\Rosenweg', r'Software\Rosenweg'];
  static const wert = 'Verwaltet';

  static String? _grund;
  static bool _bestimmt = false;

  /// Fuer Tests: fester Grund (null = nicht verwaltet) statt des Systems.
  @visibleForTesting
  static String? Function()? ersatz;

  /// true, wenn jemand anderes die App aktualisiert. Einmal bestimmt.
  static bool get erkannt => grund != null;

  /// Warum verwaltet (fuer das Protokoll), null = nicht verwaltet.
  static String? get grund {
    if (!_bestimmt) {
      _bestimmt = true;
      try {
        _grund = ersatz != null ? ersatz!() : (!kIsWeb && Platform.isWindows ? _windows() : null);
      } catch (_) {
        _grund = null;
      }
    }
    return _grund;
  }

  @visibleForTesting
  static void vergessen() {
    _bestimmt = false;
    _grund = null;
  }

  static String? _windows() {
    final ort = imProgrammOrdner(Platform.resolvedExecutable, Platform.environment);
    if (ort != null) return 'installiert unter $ort';
    for (final s in schluessel) {
      if (registrySchalter(s, wert)) return r'HKLM\' '$s\\$wert = 1';
    }
    return null;
  }

  /// Ordner fuer alle Benutzer, unter dem [exe] liegt, sonst null.
  /// Gross/klein und / bzw. \ zaehlen nicht.
  static String? imProgrammOrdner(String exe, Map<String, String> umgebung) {
    String norm(String p) {
      var n = p.replaceAll('/', r'\').toLowerCase();
      while (n.endsWith(r'\')) {
        n = n.substring(0, n.length - 1);
      }
      return n;
    }

    final e = norm(exe);
    for (final name in const ['ProgramFiles', 'ProgramW6432', 'ProgramFiles(x86)', 'windir', 'SystemRoot']) {
      // Windows-Umgebung ist gross/klein-unabhaengig; Dart liefert die Namen wie gesetzt.
      final v = umgebung.entries.where((x) => x.key.toLowerCase() == name.toLowerCase()).map((x) => x.value).firstOrNull;
      if (v == null || v.trim().isEmpty) continue;
      if (e.startsWith('${norm(v)}\\')) return v;
    }
    return null;
  }
}
