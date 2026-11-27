// SPDX-License-Identifier: GPL-3.0-or-later
/// Rechte der angemeldeten Person, wie sie die API selbst prueft.
///
/// Quelle ist `GET /api/auth/me` (api/server.js): `user.permissions` (Seite →
/// `read`/`write`, schon mit allen Ableitungen des Servers, z. B. "hat Zaehler
/// → energie-monitor read" und Ausschuss → bewohner-verwaltung) und
/// `user.groups`. Technik und Praesident duerfen alles — genau wie
/// `requirePermission` in api/middleware/auth.js, auch fuer Seiten, die nicht
/// in `permissions` stehen.
///
/// Dazu die **Stufe der Anmeldung** (Plan 4.2.1): Karte < Konto < frisch
/// bestaetigtes Konto. Die API liefert sie kuenftig in `auth/me` als
/// `user.anmeldung.stufe` (`karte`, `konto`, `konto-frisch`) und optional
/// `user.anmeldung.frisch_bis` (ISO-Zeit). Fehlt das Feld (API noch ohne
/// Stufen), schaetzt die App die Stufe aus ihrer eigenen Anmeldung
/// ([RosenwegSitzung.stand], [RosenwegSitzung.bestaetigtUm]). Die API
/// entscheidet trotzdem immer selbst; die App blendet nur aus, was ohnehin
/// abgelehnt wuerde.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protokoll.dart';
import 'sitzung.dart';

/// Zugriff auf eine Seite des Portals (`permissions` in der API).
enum Zugriff {
  keiner,
  lesen,
  schreiben;

  /// `none`/`read`/`write` aus der API; Unbekanntes = [keiner].
  static Zugriff ausText(Object? text) => switch (text) {
        'write' => schreiben,
        'read' => lesen,
        _ => keiner,
      };

  bool mindestens(Zugriff z) => index >= z.index;
}

/// Wie stark die aktuelle Anmeldung ist.
enum Anmeldestufe {
  keine('Nicht angemeldet'),

  /// Rosenweg-Karte, Anmelde-QR, Handy-Bestaetigung, geteiltes Telefon.
  karte('Rosenweg-Karte'),

  /// Rosenweg-Konto (Browser, Kerberos, Android-Anmeldeschirm mit Konto).
  konto('Rosenweg-Konto'),

  /// Rosenweg-Konto, gerade eben bestaetigt (Passwort, Passkeys, Tokens).
  kontoFrisch('Rosenweg-Konto, gerade bestätigt');

  const Anmeldestufe(this.text);
  final String text;

  /// `karte`/`konto`/`konto-frisch` aus der API; null = unbekannt.
  static Anmeldestufe? ausText(Object? text) => switch (text) {
        'karte' => karte,
        'konto' => konto,
        'konto-frisch' || 'konto_frisch' || 'frisch' => kontoFrisch,
        _ => null,
      };

  bool mindestens(Anmeldestufe s) => index >= s.index;
}

/// Gruppen, die alles duerfen (wie `requirePermission`).
const _alleRechte = {'technik', 'präsident', 'praesident'};

/// Stand der Rechte zu einem Zeitpunkt (unveraenderlich).
class Rechte {
  const Rechte({
    this.seiten = const {},
    this.gruppen = const [],
    this.stufe = Anmeldestufe.keine,
    this.stufeVomServer = false,
    this.frischBis,
    this.email,
    this.name,
    this.wohnung,
    this.stweg,
  });

  /// Antwort von `GET /api/auth/me` lesen. [ersatzStufe] gilt, wenn die API
  /// (noch) keine Stufe nennt.
  factory Rechte.ausAuthMe(Map<String, dynamic> json, {Anmeldestufe ersatzStufe = Anmeldestufe.karte, DateTime? jetzt}) {
    final u = json['user'] is Map ? (json['user'] as Map).cast<String, dynamic>() : json;
    final seiten = <String, Zugriff>{};
    final p = u['permissions'];
    if (p is Map) {
      p.forEach((k, v) => seiten['$k'] = Zugriff.ausText(v));
    }
    final g = u['groups'];
    final gruppen = g is List ? [for (final x in g) if (x is String) x] : const <String>[];
    // Feld der API-Stufen: in user oder oben (beides erlaubt, damit die API frei ist)
    final a = u['anmeldung'] is Map ? u['anmeldung'] as Map : (json['anmeldung'] is Map ? json['anmeldung'] as Map : null);
    final vomServer = Anmeldestufe.ausText(a?['stufe']);
    final frischBis = a?['frisch_bis'] is String ? DateTime.tryParse(a!['frisch_bis'] as String) : null;
    var stufe = vomServer ?? ersatzStufe;
    // Abgelaufene Frische zaehlt nur noch als Konto
    if (stufe == Anmeldestufe.kontoFrisch && frischBis != null && (jetzt ?? DateTime.now()).isAfter(frischBis)) {
      stufe = Anmeldestufe.konto;
    }
    String? text(String k) => u[k] is String ? u[k] as String : null;
    return Rechte(
      seiten: seiten,
      gruppen: gruppen,
      stufe: stufe,
      stufeVomServer: vomServer != null,
      frischBis: frischBis,
      email: text('email'),
      name: text('name'),
      wohnung: text('wohnung'),
      stweg: u['stweg']?.toString(),
    );
  }

  /// Seite → Zugriff, genau wie `permissions` der API.
  final Map<String, Zugriff> seiten;
  final List<String> gruppen;
  final Anmeldestufe stufe;

  /// true = die API hat die Stufe genannt; false = von der App geschaetzt.
  final bool stufeVomServer;
  final DateTime? frischBis;
  final String? email;
  final String? name;
  final String? wohnung;
  final String? stweg;

  /// [stufe], aber eine abgelaufene Frische ([frischBis]) zaehlt nur als Konto.
  Anmeldestufe stufeJetzt([DateTime? jetzt]) {
    final f = frischBis;
    if (stufe == Anmeldestufe.kontoFrisch && f != null && (jetzt ?? DateTime.now()).isAfter(f)) return Anmeldestufe.konto;
    return stufe;
  }

  /// Technik oder Praesident: alles erlaubt.
  bool get alles => gruppen.any((g) => _alleRechte.contains(g.toLowerCase()));

  bool inGruppe(String gruppe) => gruppen.any((g) => g.toLowerCase() == gruppe.toLowerCase());

  Zugriff zugriff(String seite) => alles ? Zugriff.schreiben : (seiten[seite] ?? Zugriff.keiner);

  /// Darf die Person [seite] mindestens mit [zugriff] nutzen?
  /// `darf('reklamationen', Zugriff.schreiben)`.
  bool darf(String seite, [Zugriff zugriff = Zugriff.lesen]) => this.zugriff(seite).mindestens(zugriff);

  /// Mindestens eine der Seiten (wie `permAny` im Menue der Website).
  bool darfEine(Iterable<String> seiten, [Zugriff zugriff = Zugriff.lesen]) => seiten.any((s) => darf(s, zugriff));

  @override
  String toString() => 'Rechte(${seiten.length} Seiten, alles: $alles, Stufe: ${stufe.name}${stufeVomServer ? '' : ' (geschaetzt)'})';
}

/// Laedt und haelt die [Rechte] der angemeldeten Person; meldet Aenderungen
/// (z. B. nach Personenwechsel, Abmelden, Bestaetigen).
///
/// In jeder App ueber [RosenwegSitzung.rechte] erreichbar; Widgets lesen sie
/// mit `RechteBereich.von(context)` bzw. [NurMit].
class RosenwegRechte extends ChangeNotifier {
  RosenwegRechte({
    required Future<Map<String, dynamic>> Function() laden,
    Anmeldestufe Function()? ersatzStufe,
    Future<bool> Function()? bestaetigen,
  })  : _laden = laden, // ignore: prefer_initializing_formals
        _ersatzStufe = ersatzStufe ?? (() => Anmeldestufe.karte),
        _bestaetigen = bestaetigen; // ignore: prefer_initializing_formals

  /// Rechte zu einer Sitzung: laden ueber deren API, nach jedem Wechsel der
  /// Anmeldung (andere Person, abgemeldet, bestaetigt) neu.
  factory RosenwegRechte.fuer(RosenwegSitzung s) {
    final r = RosenwegRechte(
      laden: () => s.api.objekt('/api/auth/me'),
      ersatzStufe: () => stufeAusSitzung(s),
      bestaetigen: s.bestaetigen,
    );
    String schluessel() => '${s.phase.name}|${s.stand.art.name}|${s.stand.email}|${s.personStand.value}|${s.bestaetigtUm}';
    var vorher = schluessel();
    void pruefen() {
      final jetzt = schluessel();
      if (jetzt == vorher) return;
      vorher = jetzt;
      r.verwerfen();
      if (s.phase == Phase.bereit) unawaited(r.laden().then((_) {}, onError: (_) {}));
    }

    s.addListener(pruefen);
    s.personStand.addListener(pruefen);
    return r;
  }

  /// Stufe, wenn die API keine nennt: aus der Art der Anmeldung der App.
  /// "Frisch" gilt [frischDauer] lang nach [RosenwegSitzung.bestaetigen].
  static Anmeldestufe stufeAusSitzung(RosenwegSitzung s, {DateTime? jetzt}) {
    final art = s.stand.art;
    switch (art) {
      case AnmeldeArt.keine:
        return Anmeldestufe.keine;
      case AnmeldeArt.karte || AnmeldeArt.qr || AnmeldeArt.handy || AnmeldeArt.geteiltesTelefon:
        return Anmeldestufe.karte;
      case AnmeldeArt.konto || AnmeldeArt.kerberos:
        final b = s.bestaetigtUm;
        if (b != null && (jetzt ?? DateTime.now()).difference(b) < frischDauer) return Anmeldestufe.kontoFrisch;
        return Anmeldestufe.konto;
    }
  }

  /// Wie lange eine Bestaetigung als "frisch" gilt, wenn die API nichts sagt.
  static const frischDauer = Duration(minutes: 5);

  final Future<Map<String, dynamic>> Function() _laden;
  final Anmeldestufe Function() _ersatzStufe;
  final Future<bool> Function()? _bestaetigen;

  Rechte? _stand;
  Object? _fehler;
  Future<Rechte>? _laeuft;
  int _runde = 0;

  /// Zuletzt geladene Rechte; null = noch nicht geladen.
  Rechte? get stand => _stand;
  bool get geladen => _stand != null;
  bool get laedt => _laeuft != null;

  /// Fehler beim letzten Laden (Text mit `fehlerText`).
  Object? get fehler => _fehler;

  /// Rechte laden (einmal; [neu] = auch wenn schon geladen). Mehrere
  /// gleichzeitige Aufrufe teilen sich eine Anfrage.
  Future<Rechte> laden({bool neu = false}) {
    final s = _stand;
    if (s != null && !neu) return Future.value(s);
    final l = _laeuft;
    if (l != null) return l;
    final runde = _runde;
    final f = () async {
      try {
        final r = Rechte.ausAuthMe(await _laden(), ersatzStufe: _ersatzStufe());
        if (runde == _runde) {
          _stand = r;
          _fehler = null;
          Protokoll.schreiben('$r');
        }
        return r;
      } catch (e) {
        if (runde == _runde) _fehler = e;
        rethrow;
      } finally {
        if (runde == _runde) {
          _laeuft = null;
          notifyListeners();
        }
      }
    }();
    _laeuft = f;
    notifyListeners();
    return f;
  }

  /// Vergessen (Abmelden, andere Person); das naechste [laden] fragt neu.
  void verwerfen() {
    _runde++;
    _stand = null;
    _fehler = null;
    _laeuft = null;
    notifyListeners();
  }

  /// Wie [Rechte.darf]; false, solange nichts geladen ist.
  bool darf(String seite, [Zugriff zugriff = Zugriff.lesen]) => _stand?.darf(seite, zugriff) ?? false;

  /// Reicht die aktuelle Anmeldung fuer [stufe]? Wenn die API keine Stufe
  /// nennt, gilt die Schaetzung der App (auch fuer "frisch", das mit der
  /// Zeit verfaellt).
  bool hatStufe(Anmeldestufe stufe) {
    final s = _stand;
    if (s == null) return false;
    final aktuell = s.stufeVomServer ? s.stufeJetzt() : _ersatzStufe();
    return aktuell.mindestens(stufe);
  }

  /// Hoehere Stufe holen: mit dem Rosenweg-Konto bestaetigen
  /// ([RosenwegSitzung.bestaetigen]), danach Rechte neu laden. true = jetzt
  /// erreicht.
  Future<bool> stufeErreichen(Anmeldestufe stufe) async {
    if (hatStufe(stufe)) return true;
    if (!await bestaetigen()) return false;
    return hatStufe(stufe);
  }

  /// Mit dem Rosenweg-Konto bestaetigen (immer, auch wenn die Stufe schon
  /// reicht) und die Rechte neu laden. true = bestaetigt.
  Future<bool> bestaetigen() async {
    final b = _bestaetigen;
    if (b == null || !await b()) return false;
    await laden(neu: true);
    return true;
  }
}
