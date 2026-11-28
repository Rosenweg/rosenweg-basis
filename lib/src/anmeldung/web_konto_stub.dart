// SPDX-License-Identifier: GPL-3.0-or-later
import '../netz/api.dart';

/// Nur im Browser benutzbar (web_konto_web.dart). Hier nur, damit der Code
/// auf allen Plattformen uebersetzt; wird ausserhalb von Web nie erzeugt.
class WebKonto implements Zugangsquelle {
  WebKonto();

  String? name;
  String? email;

  Future<bool> pruefen() => throw UnsupportedError('Nur im Browser');
  Future<bool> anmelden({bool erneut = false, bool automatisch = false}) => throw UnsupportedError('Nur im Browser');
  Future<void> abmelden() => throw UnsupportedError('Nur im Browser');

  @override
  Future<String?> zugangsToken() => throw UnsupportedError('Nur im Browser');

  @override
  void zugangUngueltig() {}
}
