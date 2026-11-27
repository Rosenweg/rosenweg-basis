// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:io';

/// Laeuft die App auf einer Rosenweg-Station (os-stationen)?
///
/// Die EINE Stelle dafuer in der Basis. Auf Stationen bringt os-stationen
/// die Pakete (auch die .deb der Flutter-Apps, `pakete/<app>/paket.conf`);
/// dort ist der Updater der App aus, ohne Hinweis (Stefan 27.11.2026).
///
/// Erkannt wird die Station an dem, was os-stationen beim Einrichten
/// hinterlegt (`install.sh`, `lib/config.sh`):
///
/// - `/etc/rosenweg-station/station-id` mit einer Station-ID (z. B.
///   `desktop-verwaltung`) und
/// - `/etc/rosenweg-station/station.json` (aufgeloeste Konfiguration).
///
/// Beide muessen da sein. NICHT massgebend sind "Linux", "Debian" oder ein
/// installiertes .deb: Bewohner mit eigenem Debian-Rechner bekommen dasselbe
/// .deb von /apps, und dort muss der Updater laufen.
class RosenwegStation {
  RosenwegStation._();

  static const ordner = '/etc/rosenweg-station';
  static const kennungDatei = '$ordner/station-id';
  static const konfigDatei = '$ordner/station.json';

  /// Station-IDs, wie os-stationen sie vergibt (Kleinbuchstaben, Ziffern,
  /// Bindestrich).
  static final _kennung = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  static bool? _gemerkt;

  /// Nur fuer Tests: Wurzel statt `/` (z. B. ein temporaerer Ordner) und
  /// Plattform. null = echtes System.
  static String? wurzelFuerTests;
  static bool? linuxFuerTests;

  /// true nur auf einer echten Rosenweg-Station. Einmal bestimmt, dann
  /// gemerkt (aendert sich nicht, solange die App laeuft).
  static bool get erkannt => _gemerkt ??= _bestimmen();

  /// Station-ID oder null (keine Station).
  static String? get kennung => erkannt ? _lesen(kennungDatei) : null;

  /// Fuer Tests: neu bestimmen.
  static void vergessen() => _gemerkt = null;

  static bool _bestimmen() {
    if (!(linuxFuerTests ?? Platform.isLinux)) return false;
    final id = _lesen(kennungDatei);
    if (id == null || !_kennung.hasMatch(id)) return false;
    try {
      return File(_pfad(konfigDatei)).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _pfad(String p) => '${wurzelFuerTests ?? ''}$p';

  static String? _lesen(String p) {
    try {
      final f = File(_pfad(p));
      if (!f.existsSync()) return null;
      final t = f.readAsStringSync().trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }
}
