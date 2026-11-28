// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'anmeldung/android_konto.dart';
import 'anmeldung/karten_sitzung.dart';
import 'anmeldung/rosenweg_konto.dart';
import 'anmeldung/ruecksprung.dart';
import 'anmeldung/schluesselbund.dart';
import 'anmeldung/web_konto.dart';
import 'konfig.dart';
import 'fehler_fuer_person.dart';
import 'netz/api.dart';
import 'netz/dateien.dart';
import 'netz/geraet_person.dart';
import 'plattform.dart';
import 'protokoll.dart';
import 'gruppenfarbe.dart';
import 'rechte.dart';

enum Phase {
  /// Start: gespeicherte Anmeldung pruefen.
  pruefen,

  /// Keine (oder eine ueber 30 Tage alte) Anmeldung: Knopf "Anmelden".
  abgemeldet,

  /// Anmeldeseite ist im Browser offen.
  anmelden,

  /// Angemeldet; die App zeigt ihren Inhalt.
  bereit,

  /// Etwas ging schief; Text in [RosenwegSitzung.fehler], Knopf "Nochmals".
  fehler,
}

/// Der Anmelde-Ablauf einer App an einer Stelle.
///
///   Telefon mit Rosenweg Geraet (geteilt) → Anfragen ueber Geraet, keine eigene Anmeldung
///   anderes Android-Handy → Anmeldeschirm von commons-rosenweg ([AndroidKonto]:
///         Rosenweg-Karte oder Rosenweg-Konto, wie der Sperrbildschirm) → bereit
///   sonst (Desktop, iOS) → Rosenweg-Konto (still, wenn <= 30 Tage) → bereit
///         → sonst Karten-/QR-Sitzung dieser App ([KartenSitzung]) → bereit
///         → sonst Kerberos-Ticket der Sitzung (Station, Windows-Domaene) → bereit
///         → sonst Anmeldeschirm ([RosenwegAnmeldeSchirm]): Rosenweg-Karte
///           (USB-Leser bzw. iPhone-NFC), Rosenweg-Konto (Browser), QR
///           (iPhone scannt; Desktop zeigt einen, den das Handy bestaetigt)
///
/// Im Browser (Web-Version unter rosenweg4303.ch/app/…) gibt es nur EINE
/// Anmeldung, die der Website ([WebKonto]): kein eigener Anmeldeschirm, ohne
/// Sitzung geht es zur Anmeldung der Website und danach zurueck; Abmelden
/// meldet auf der ganzen Website ab.
///
/// Die App liest [api] und baut ihre Seiten; [AnmeldeTor] zeigt davor
/// Anmeldeschirm, Warten und Fehler.
class RosenwegSitzung extends ChangeNotifier {
  RosenwegSitzung(RosenwegApp app,
      {RosenwegKonto? konto,
      AndroidKonto? android,
      KartenSitzung? karte,
      Schluesselbund? speicher,
      Transport? transport,
      Future<bool> Function()? geraetDa,
      Stream<String>? personWechsel})
      : this._(app, speicher ?? Schluesselbund(app.ordner),
            konto: konto,
            android: android,
            karte: karte,
            transport: transport,
            geraetDa: geraetDa,
            personWechsel: personWechsel);

  RosenwegSitzung._(this.app, Schluesselbund speicher,
      {RosenwegKonto? konto,
      AndroidKonto? android,
      KartenSitzung? karte,
      Transport? transport,
      Future<bool> Function()? geraetDa,
      Stream<String>? personWechsel})
      // Ein Schluesselbund-Eintrag fuer Konto und Karte (macOS fragt bei
      // unsignierten Apps je Eintrag)
      : konto = konto ?? RosenwegKonto(app, speicher: speicher),
        android = android ?? (konto == null && RosenwegPlattform.istAndroid ? AndroidKontoKanal(gruppe: app.gruppe) : null),
        karte = karte ??
            (konto == null && app.ohneBrowser && !RosenwegPlattform.istAndroid && !kIsWeb ? KartenSitzung(app, speicher: speicher) : null),
        web = kIsWeb && konto == null && transport == null ? WebKonto() : null,
        _transport = transport, // ignore: prefer_initializing_formals
        _geraetDa = geraetDa ?? _standardGeraetDa,
        _personWechsel = personWechsel; // ignore: prefer_initializing_formals

  final RosenwegApp app;
  final RosenwegKonto konto;

  /// Browser: die Anmeldung der Website. null ausserhalb von Web.
  final WebKonto? web;

  /// Android ohne Rosenweg Geraet: Anmeldung ueber commons-rosenweg (Kotlin).
  /// null auf dem Desktop.
  final AndroidKonto? android;

  /// Desktop und iOS: Anmeldung mit Karte, QR oder Handy (eigene Sitzung je
  /// App, Website api/routes/app-karte.js). null auf Android (dort macht das
  /// commons-rosenweg) und bei Apps mit `ohneBrowser: false`.
  final KartenSitzung? karte;
  final Transport? _transport;
  final Future<bool> Function() _geraetDa;
  final Stream<String>? _personWechsel;
  StreamSubscription<String>? _personAbo;

  static Future<bool> _standardGeraetDa() async => RosenwegPlattform.istAndroid && await RosenwegPlattform.geraetDa();

  Phase phase = Phase.pruefen;

  /// Satz fuer die Person (Phase [Phase.fehler]).
  String? fehler;

  /// Technische Einzelheiten zu [fehler] (aufklappbar unter "Details"),
  /// null bei Fehlern, deren Satz schon alles sagt.
  String? fehlerDetails;

  /// Geteiltes Telefon: Rosenweg Geraet meldet an und ab, nicht die App.
  bool geteiltesTelefon = false;

  /// Zaehlt die Personenwechsel am geteilten Telefon. [RosenwegRahmen] baut
  /// die ganze App (auch geoeffnete Seiten) neu, sobald er sich aendert.
  final personStand = ValueNotifier<int>(0);

  /// Die App ist auch ohne Anmeldung nutzbar (`rosenwegStarten(…,
  /// ohneAnmeldung: …)`): ohne Anmeldung zeigt [AnmeldeTor] diesen Teil statt
  /// des Anmeldeschirms; Android oeffnet den Kotlin-Schirm nicht von selbst.
  bool ohneAnmeldungNutzbar = false;

  /// Die Person hat im Teil ohne Anmeldung "Anmelden" gewaehlt: [AnmeldeTor]
  /// zeigt den Anmeldeschirm (mit "Zurueck").
  bool anmeldungGewuenscht = false;

  /// Aus dem Teil ohne Anmeldung zum Anmeldeschirm (Android: gleich der
  /// Kotlin-Schirm).
  Future<void> anmeldungZeigen() async {
    if (android != null || web != null) return anmelden();
    anmeldungGewuenscht = true;
    notifyListeners();
  }

  /// Vom Anmeldeschirm zurueck in den Teil ohne Anmeldung.
  void ohneAnmeldungWeiter() {
    if (phase == Phase.anmelden) abbrechen();
    anmeldungGewuenscht = false;
    notifyListeners();
  }

  final _vorAbmelden = <Future<void> Function()>[];

  /// [aufgabe] laeuft beim Abmelden, solange die Anmeldung noch gilt (z. B.
  /// den MQTT-Zugang widerrufen, [MqttZugang.widerrufen]). Hoechstens 5 s,
  /// Fehler werden nur protokolliert. Rueckgabe: zum Austragen aufrufen.
  void Function() vorAbmelden(Future<void> Function() aufgabe) {
    _vorAbmelden.add(aufgabe);
    return () => _vorAbmelden.remove(aufgabe);
  }

  Future<void> _vorAbmeldenAusfuehren() async {
    for (final a in List.of(_vorAbmelden)) {
      try {
        await a().timeout(const Duration(seconds: 5));
      } catch (e) {
        Protokoll.schreiben('Vor dem Abmelden: Aufgabe ging nicht', e);
      }
    }
  }

  late RosenwegApi api = _apiFuer(_transport ?? HttpTransport(basis: app.konfig.api, zugang: zugang));

  /// Woher das Token der aktiven Anmeldung kommt (Android: commons-rosenweg;
  /// sonst Rosenweg-Konto oder Karten-/QR-/Handy-Sitzung). Fuer Apps, die
  /// ausser der Haupt-API noch einen eigenen Dienst ansprechen und ihm das
  /// Token mitgeben (rosenweg-vm: vm-gateway). Das Token ist ein
  /// Authentik-Token (Konto, Kerberos) oder ein `rw_app_…` (Karte, QR, Handy;
  /// 15 Minuten, wird hier erneuert). Auf geteilten Telefonen gibt es keins.
  late final Zugangsquelle zugang = android ?? web ?? _Zugang(this);

  /// Ein anderer Dienst hat das Token trotz Erneuern abgelehnt (401): wie bei
  /// der Haupt-API einmal still neu anmelden, sonst zum Anmeldeschirm.
  void nichtMehrAngemeldet() => _nichtMehrAngemeldet();

  /// Name der angemeldeten Person (Anzeige), gleich ob Android oder Desktop.
  String? get name => stand.name;

  /// Wie die App gerade angemeldet ist - fuer Einstellungen/Menue
  /// ([AnmeldungSeite]). Immer der echte Stand, nie eine Vermutung.
  Anmeldestand get stand {
    if (geteiltesTelefon) return const Anmeldestand(art: AnmeldeArt.geteiltesTelefon);
    if (phase != Phase.bereit) return const Anmeldestand(art: AnmeldeArt.keine);
    final a = android;
    if (a != null) {
      return Anmeldestand(art: a.mitKarte ? AnmeldeArt.karte : AnmeldeArt.konto, name: a.name, email: a.email);
    }
    final w = web;
    if (w != null) return Anmeldestand(art: AnmeldeArt.konto, name: w.name, email: w.email);
    if (_kontoAktiv) {
      return Anmeldestand(
          art: _mitKerberos ? AnmeldeArt.kerberos : AnmeldeArt.konto, name: konto.name, email: konto.email);
    }
    final k = karte;
    if (k != null && k.art != null) {
      return Anmeldestand(
        art: switch (k.art!) { SitzungsArt.karte => AnmeldeArt.karte, SitzungsArt.qr => AnmeldeArt.qr, SitzungsArt.handy => AnmeldeArt.handy },
        name: k.name,
        email: k.email,
      );
    }
    return const Anmeldestand(art: AnmeldeArt.keine);
  }

  /// Dateien hoch- und herunterladen mit dem Token dieser Anmeldung
  /// (Fortschritt, roh oder multipart). Austauschbar fuer Tests und
  /// Vorfuehrdaten.
  late RosenwegDateien dateien = RosenwegDateien(
    basis: app.konfig.api,
    zugang: zugang,
    nichtAngemeldet: _nichtMehrAngemeldet,
    geteiltesTelefon: () => geteiltesTelefon,
  );

  /// Rechte der angemeldeten Person (`GET /api/auth/me`), nach jedem Wechsel
  /// der Anmeldung neu. Widgets: [NurMit], `RechteBereich.von(context)`.
  /// Austauschbar fuer Vorfuehrdaten (example/), sonst nie setzen.
  late RosenwegRechte rechte = RosenwegRechte.fuer(this);

  /// Farbe der App fuer die angemeldete Person ([RosenwegApp.farbGruppen]):
  /// Thema, Anmeldeschirm, Logo ([FarbLogo]) und Startsymbol folgen ihr.
  late final GruppenFarbe farbe = GruppenFarbe(this);

  /// Kurzform: `sitzung.darf('reklamationen', Zugriff.schreiben)`. false,
  /// solange die Rechte noch nicht geladen sind (`rechte.laden()`).
  bool darf(String seite, [Zugriff zugriff = Zugriff.lesen]) => rechte.darf(seite, zugriff);

  /// Zeitpunkt der letzten erfolgreichen [bestaetigen] (frische Anmeldung).
  /// Nur Schaetzung fuer die Anzeige, falls die API keine Stufe nennt.
  DateTime? bestaetigtUm;

  /// Desktop/iOS: ist das Rosenweg-Konto (Browser/Kerberos) die aktive
  /// Anmeldung? Sonst die Karten-Sitzung.
  bool _kontoAktiv = false;
  bool _mitKerberos = false;

  RosenwegApi _apiFuer(Transport t) => RosenwegApi(t, nichtAngemeldet: _nichtMehrAngemeldet);

  void _setzen(Phase p, [String? f, String? details]) {
    if (p != phase || f != null) {
      Protokoll.schreiben('Phase ${p.name}${f != null ? ' — $f' : ''}${details != null ? ' ($details)' : ''}');
    }
    phase = p;
    fehler = f;
    fehlerDetails = details;
    notifyListeners();
  }

  void _fehler(Object e) {
    final f = fehlerFuerPerson(e);
    _setzen(Phase.fehler, f.text, f.details);
  }

  Future<void> starten() async {
    try {
      _setzen(Phase.pruefen);
      if (_transport != null) {
        // Fester Transport (Tests, Vorfuehrdaten): keine Anmeldung noetig.
        _setzen(Phase.bereit);
        return;
      }
      if (await _geraetDa()) {
        geteiltesTelefon = true;
        api = _apiFuer(GeraetTransport(app.kennung, personGewechselt: personGewechselt));
        _personAbo ??= (_personWechsel ?? GeraetPerson.wechsel).listen((_) => personGewechselt());
        _setzen(Phase.bereit);
        return;
      }
      final w = web;
      if (w != null) {
        // Browser: die Sitzung der Website gilt (kein eigener Schirm)
        if (await w.pruefen()) {
          _setzen(Phase.bereit);
        } else if (ohneAnmeldungNutzbar) {
          _setzen(Phase.abgemeldet);
        } else {
          await _webAnmelden(automatisch: true);
        }
        return;
      }
      final a = android;
      if (a != null) {
        // Wie die Kotlin-Apps (RosenwegAnmeldeSchirm.zeigenFallsNoetig): gleich den Schirm zeigen
        if (await a.angemeldet) {
          _setzen(Phase.bereit);
        } else if (ohneAnmeldungNutzbar) {
          _setzen(Phase.abgemeldet);
        } else {
          await anmelden();
        }
        return;
      }
      if (await konto.ausstehendeAbschliessen() || await konto.angemeldet) {
        _kontoAktiv = true;
        _setzen(Phase.bereit);
      } else if (await karte?.angemeldet ?? false) {
        _kontoAktiv = false;
        _setzen(Phase.bereit);
      } else if (await konto.stillAnmelden()) {
        // Station/Domaene: sofort angemeldet, der Schirm erscheint gar nicht
        _kontoAktiv = _mitKerberos = true;
        _setzen(Phase.bereit);
      } else {
        _setzen(Phase.abgemeldet);
      }
    } catch (e) {
      _fehler(e);
    }
  }

  /// Ohne Oberflaeche anmelden (Abfrage im Hintergrund, [HintergrundAbfrage]):
  /// nur eine schon bestehende Anmeldung, nie ein Anmeldeschirm oder Browser.
  /// true = [api] ist benutzbar.
  ///
  /// Geteilte Telefone: immer false – die Person am Telefon wechselt, eine
  /// Benachrichtigung fuer die vorige Person waere ein Datenleck.
  Future<bool> hintergrundStarten() async {
    try {
      if (_transport != null) {
        _setzen(Phase.bereit);
        return true;
      }
      if (await _geraetDa()) return false;
      final w = web;
      if (w != null) return false; // im Browser gibt es keine Abfrage im Hintergrund
      final a = android;
      final ok = a != null
          ? await a.angemeldet
          : (await konto.angemeldet) ? (_kontoAktiv = true) : (await karte?.angemeldet ?? false);
      if (ok) _setzen(Phase.bereit);
      return ok;
    } catch (e) {
      Protokoll.schreiben('Hintergrund: keine Anmeldung', e);
      return false;
    }
  }

  /// Knopf "Mit Rosenweg-Konto anmelden". Erst still (Kerberos; z. B. nach
  /// "Abmelden" in der App), sonst im Browser.
  Future<void> anmelden() async {
    if (web != null) return _webAnmelden();
    final a = android;
    if (a != null) {
      // Anmeldeschirm von commons-rosenweg (Karte oder Rosenweg-Konto)
      try {
        _setzen(Phase.anmelden);
        _setzen(await a.anmeldeSchirm() ? Phase.bereit : Phase.abgemeldet);
      } catch (e) {
        _fehler(e);
      }
      return;
    }
    try {
      _setzen(Phase.pruefen);
      if (await konto.stillAnmelden()) {
        _kontoAktiv = _mitKerberos = true;
        _setzen(Phase.bereit);
        return;
      }
      _setzen(Phase.anmelden);
      await konto.anmelden();
      _kontoAktiv = true;
      _mitKerberos = false;
      _setzen(Phase.bereit);
    } on AnmeldungAbgebrochen {
      _setzen(Phase.abgemeldet);
    } catch (e) {
      _fehler(e);
    }
  }

  /// Browser: zur Anmeldung der Website, danach zurueck hierher. Die Seite
  /// wird dabei verlassen; nur wenn die Sperre der Website die automatische
  /// Anmeldung anhaelt (mehrere Fehlversuche), geht es hier weiter.
  Future<void> _webAnmelden({bool automatisch = false, bool erneut = false}) async {
    try {
      _setzen(Phase.anmelden);
      final los = await web!.anmelden(automatisch: automatisch, erneut: erneut);
      if (!los) {
        _setzen(Phase.fehler, 'Die automatische Anmeldung hat mehrmals nicht geklappt und wurde angehalten.');
      }
    } catch (e) {
      _fehler(e);
    }
  }

  /// Knopf "Abbrechen" waehrend die Anmeldeseite offen ist.
  void abbrechen() => konto.abbrechen();

  /// Der Anmeldeschirm hat [karte] angemeldet (Karte, QR, Handy).
  void ohneBrowserAngemeldet() {
    _kontoAktiv = _mitKerberos = false;
    _setzen(Phase.bereit);
  }

  /// Frische Anmeldung fuer heikle Aktionen (API: 403 mit `reauth`). Die
  /// App bleibt dabei sichtbar; true = bestaetigt.
  Future<bool> bestaetigen() async {
    if (geteiltesTelefon) return false;
    if (web != null) {
      // Die Website fragt erneut nach dem Ausweis und kommt hierher zurueck
      await _webAnmelden(erneut: true);
      return false;
    }
    if (android != null) {
      final ok = await android!.bestaetigen();
      if (ok) {
        bestaetigtUm = DateTime.now();
        notifyListeners();
      }
      return ok;
    }
    try {
      await konto.anmelden(bestaetigen: true);
      // Ab jetzt laeuft die App mit dem Rosenweg-Konto (die Karten-Sitzung bleibt bestehen)
      _kontoAktiv = true;
      _mitKerberos = false;
      bestaetigtUm = DateTime.now();
      notifyListeners();
      return true;
    } on AnmeldungAbgebrochen {
      return false;
    }
  }

  Future<void> abmelden() async {
    if (geteiltesTelefon) return;
    await _vorAbmeldenAusfuehren();
    anmeldungGewuenscht = false;
    final w = web;
    if (w != null) {
      // Abmelden in der App = Abmelden auf der ganzen Website (Seite wird verlassen)
      await w.abmelden();
      return;
    }
    if (android != null) {
      await android!.abmelden();
      if (ohneAnmeldungNutzbar) {
        _setzen(Phase.abgemeldet);
      } else {
        await anmelden(); // Anmeldeschirm, wie nach dem Start
      }
      return;
    }
    await konto.abmelden();
    await karte?.abmelden();
    _kontoAktiv = _mitKerberos = false;
    bestaetigtUm = null;
    _setzen(Phase.abgemeldet);
  }

  /// Am geteilten Telefon hat sich jemand an- oder abgemeldet (Rosenweg Geraet,
  /// oder die `sitzung`-Marke einer Antwort hat gewechselt): alles neu laden.
  void personGewechselt() {
    if (!geteiltesTelefon) return;
    Protokoll.schreiben('Personenwechsel am Telefon — neu laden');
    personStand.value++;
  }

  void _nichtMehrAngemeldet() {
    if (geteiltesTelefon) return; // Geraet entscheidet; die App zeigt die Meldung
    if (web != null) {
      if (phase == Phase.bereit) _webNeuPruefen();
      return;
    }
    if (phase == Phase.bereit) {
      _neuStill();
    }
  }

  /// Browser: die API lehnt das Token ab. Die Website prueft es selbst (und
  /// raeumt die Sitzung auf); ohne Sitzung zur Anmeldung.
  Future<void> _webNeuPruefen() async {
    try {
      if (await web!.pruefen()) return; // war nur ein Aussetzer
      if (ohneAnmeldungNutzbar) {
        _setzen(Phase.abgemeldet);
      } else {
        await _webAnmelden(automatisch: true);
      }
    } catch (e) {
      _fehler(e);
    }
  }

  /// Anmeldung widerrufen/abgelaufen: einmal still neu (Kerberos), sonst
  /// zurueck zum Knopf.
  Future<void> _neuStill() async {
    if (android != null) {
      // Kotlin hat eine widerrufene Sitzung schon verworfen; sonst gilt die Anmeldung weiter
      _setzen(await android!.angemeldet ? Phase.bereit : Phase.abgemeldet);
      return;
    }
    _setzen(Phase.pruefen);
    if (_kontoAktiv) {
      await konto.abmelden();
      // Noch eine Karten-Sitzung? Dann mit ihr weiter.
      if (await karte?.angemeldet ?? false) {
        _kontoAktiv = _mitKerberos = false;
        _setzen(Phase.bereit);
        return;
      }
    } else {
      await karte?.abmelden();
    }
    final still = await konto.stillAnmelden();
    _kontoAktiv = _mitKerberos = still;
    _setzen(still ? Phase.bereit : Phase.abgemeldet);
  }

  /// Nicht aufgefangener Fehler (rosenwegStarten): sichtbar machen statt
  /// still weiterlaufen. Den Pfad der Logdatei mit anzeigen.
  void unerwartet(Object e) {
    final p = Protokoll.pfad;
    final f = fehlerFuerPerson(e);
    _setzen(Phase.fehler, f.text, '${f.details ?? e}${p != null ? '\n\nProtokoll: $p' : ''}');
  }
}

/// Zugang fuer die API auf Desktop und iOS: das Rosenweg-Konto, wenn es die
/// aktive Anmeldung ist, sonst die Karten-Sitzung.
class _Zugang implements Zugangsquelle {
  _Zugang(this._s);
  final RosenwegSitzung _s;

  Zugangsquelle get _quelle {
    final k = _s.karte;
    return _s._kontoAktiv || k == null ? _s.konto : k;
  }

  @override
  Future<String?> zugangsToken() => _quelle.zugangsToken();

  @override
  void zugangUngueltig() => _quelle.zugangUngueltig();
}

/// Womit die App angemeldet ist.
enum AnmeldeArt {
  keine('Nicht angemeldet'),
  konto('Rosenweg-Konto'),
  kerberos('Rosenweg-Konto (automatisch an diesem Computer)'),
  karte('Rosenweg-Karte'),
  qr('Anmelde-QR aus dem Portal'),
  handy('Mit dem Handy bestätigt'),
  geteiltesTelefon('Geteiltes Rosenweg-Telefon');

  const AnmeldeArt(this.text);
  final String text;
}

/// Echter Stand der Anmeldung (fuer Einstellungen und Menue).
class Anmeldestand {
  const Anmeldestand({required this.art, this.name, this.email});
  final AnmeldeArt art;
  final String? name;
  final String? email;
  bool get angemeldet => art != AnmeldeArt.keine;
}
