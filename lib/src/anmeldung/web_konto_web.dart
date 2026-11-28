// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../netz/api.dart';
import '../protokoll.dart';

@JS('AuthentikAuth')
external JSObject? get _auth;

/// Web-Version der Apps: es gibt nur EINE Anmeldung, die der Website.
///
/// Die App liegt unter derselben Adresse wie die Website (rosenweg4303.ch/app/…)
/// und laedt `/js/authentik-auth.js` (web/index.html). Dieses Modul der Website
/// hat die Sitzung schon (Token in localStorage und im Cookie auf
/// .rosenweg4303.ch) und kennt den ganzen Ablauf: Rueckkehr von der Anmeldung
/// (`#auth=`), Pruefung gegen `/api/auth/me`, stiller Kerberos-Versuch,
/// Schleifensperre, Abmelden. Hier wird es nur aufgerufen, nicht nachgebaut.
/// Darum gelten Anmelden und Abmelden fuer die ganze Website zugleich, und es
/// gibt keinen eigenen Anmeldeschirm und keinen eigenen Client in Authentik.
///
/// Das Token ist das der Website-Sitzung: dasselbe, mit dem die Seiten der
/// Website die API aufrufen. Rechte und Gruppen kommen darum aus derselben
/// Quelle (`GET /api/auth/me`) wie auf den alten Seiten.
class WebKonto implements Zugangsquelle {
  WebKonto();

  /// Fuer die Anzeige, nach [pruefen].
  String? name;
  String? email;

  JSObject get _a {
    final a = _auth;
    if (a == null) {
      throw StateError('js/authentik-auth.js der Website fehlt. Diese App laeuft nur unter rosenweg4303.ch/app/…');
    }
    return a;
  }

  /// Gibt es eine gueltige Sitzung der Website? Verarbeitet auch die Rueckkehr
  /// von der Anmeldung. Ohne Sitzung wird NICHT umgeleitet (das macht [anmelden]).
  Future<bool> pruefen() async {
    final r = await _a.callMethodVarArgs<JSPromise<JSAny?>>('init'.toJS, [{'requireAuth': false}.jsify()]).toDart;
    final u = r.dartify();
    if (u is! Map) return false;
    name = _text(u['name']) ?? _text(u['displayName']) ?? _text(u['username']);
    email = _text(u['email']);
    return true;
  }

  static String? _text(Object? o) => o is String && o.trim().isNotEmpty ? o.trim() : null;

  /// Zur Anmeldung der Website; danach zurueck auf diese Seite. Liefert nur
  /// false, wenn die Schleifensperre der Website die automatische Anmeldung
  /// angehalten hat (sie zeigt dann selbst einen Hinweis mit Knopf).
  Future<bool> anmelden({bool erneut = false, bool automatisch = false}) async {
    Protokoll.schreiben('Web: zur Anmeldung der Website${erneut ? ' (neu bestaetigen)' : ''}');
    final opts = {if (erneut) 'reauth': true, if (automatisch) 'auto': true}.jsify();
    final r = await _a.callMethodVarArgs<JSPromise<JSAny?>>('login'.toJS, [null, opts]).toDart;
    return r.dartify() != false;
  }

  /// Abmelden auf der ganzen Website; danach auf die Startseite.
  Future<void> abmelden() async {
    name = email = null;
    _a.callMethodVarArgs<JSAny?>('logout'.toJS, ['/'.toJS]);
  }

  @override
  Future<String?> zugangsToken() async {
    final t = _a.callMethodVarArgs<JSAny?>('getToken'.toJS, const []).dartify();
    return t is String && t.isNotEmpty ? t : null;
  }

  @override
  void zugangUngueltig() {}
}
