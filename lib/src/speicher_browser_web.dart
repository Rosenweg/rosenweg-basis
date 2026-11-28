// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:web/web.dart' as web;

/// localStorage dieser Seite (`rosenweg-app:<name>`). Nur nicht geheime Werte
/// (siehe AppSpeicher). Geht es nicht (privates Fenster, gesperrt), bleibt der
/// Speicher fuer diese Sitzung im Arbeitsspeicher.
String? browserLesen(String schluessel) {
  try {
    return web.window.localStorage.getItem(schluessel);
  } catch (_) {
    return null;
  }
}

void browserSchreiben(String schluessel, String text) {
  try {
    web.window.localStorage.setItem(schluessel, text);
  } catch (_) {}
}
