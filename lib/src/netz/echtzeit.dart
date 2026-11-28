// SPDX-License-Identifier: GPL-3.0-or-later
/// Echtzeit ueber den MQTT-Broker der Anlage (mqtt.rosenweg4303.ch) – derselbe
/// Weg wie die Web-Seiten (wetter.html, energie.html, display.html): WebSocket
/// mit TLS auf 443, auf Wunsch MQTT ueber TLS (8883). Kein ntfy (Entscheid
/// Stefan 27.11.2026).
///
/// Zugang:
/// - [MqttZugang.fest]: oeffentlicher Lese-Benutzer, der ohnehin im Web-Code
///   steht (z. B. `wetter-public`, nur `wetter/r9/#`, `display-public`, nur
///   `display/#`). Fuer Seiten, die auch ohne Anmeldung gehen.
/// - [MqttZugang.ueberApi]: kurzlebiger Zugang der angemeldeten Person
///   (`POST /api/mqtt/token`, 12 h), der Broker prueft die Themen nach ihren
///   Gruppen (energy/…, Topic-Regeln). Karten-, QR- und Handy-Sitzungen
///   (`rw_app_…`) bekommen keinen MQTT-Zugang (PAT_GESPERRT der API).
///
/// [RosenwegMqtt] verbindet sich selbst wieder (2 s, 4 s, … bis 60 s), holt
/// dabei einen neuen Zugang, wenn der alte abgelehnt wurde, und abonniert alle
/// Themen neu. [zustand] sagt der Oberflaeche, ob die Werte live sind
/// ([EchtzeitAnzeige]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../protokoll.dart';
import 'api.dart';
import 'mqtt_fabrik.dart';

/// Eine empfangene Nachricht.
@immutable
class MqttNachricht {
  const MqttNachricht(this.thema, this.text, {this.behalten = false, required this.zeit});

  /// Thema, z. B. `wetter/r9/outdoortemp`.
  final String thema;

  /// Inhalt als Text (UTF-8).
  final String text;

  /// Vom Broker gespeicherte Nachricht (retained): kam beim Abonnieren, ist
  /// also der letzte bekannte Stand und nicht unbedingt neu.
  final bool behalten;

  /// Wann die App sie empfangen hat.
  final DateTime zeit;

  /// Letzter Teil des Themas (`wetter/r9/outdoortemp` → `outdoortemp`).
  String get feld => thema.substring(thema.lastIndexOf('/') + 1);

  /// Inhalt als Zahl (null, wenn keine).
  double? get zahl => double.tryParse(text.trim());

  /// Inhalt als JSON (null, wenn kein gueltiges JSON).
  Object? get json {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => '$thema = $text';
}

/// Benutzer und Passwort fuer den Broker.
typedef MqttAnmeldung = ({String benutzer, String passwort});

/// Woher der Zugang zum Broker kommt.
abstract class MqttZugang {
  const MqttZugang();

  /// Fester Zugang (oeffentlicher Lese-Benutzer aus dem Web-Code).
  const factory MqttZugang.fest(String benutzer, String passwort) = _FesterZugang;

  /// Zugang der angemeldeten Person ueber `POST /api/mqtt/token`.
  factory MqttZugang.ueberApi(RosenwegApi api, {String pfad}) = _ApiZugang;

  /// Zugang holen; [neu] = der letzte wurde abgelehnt, nicht zwischengespeichert nehmen.
  Future<MqttAnmeldung> holen({bool neu = false});

  /// Zugang beim Server widerrufen (Abmelden). Fester Zugang: nichts.
  Future<void> widerrufen() async {}
}

class _FesterZugang extends MqttZugang {
  const _FesterZugang(this.benutzer, this.passwort);
  final String benutzer;
  final String passwort;
  @override
  Future<MqttAnmeldung> holen({bool neu = false}) async => (benutzer: benutzer, passwort: passwort);
}

class _ApiZugang extends MqttZugang {
  _ApiZugang(this.api, {this.pfad = '/api/mqtt/token'});
  final RosenwegApi api;
  final String pfad;
  MqttAnmeldung? _zuletzt;
  DateTime? _seit;
  Duration _gilt = const Duration(hours: 12);

  @override
  Future<MqttAnmeldung> holen({bool neu = false}) async {
    final z = _zuletzt, s = _seit;
    // Der Server gibt 12 h (Karte/geteiltes Telefon kuerzer, `expires_in`);
    // nach 90 % der Laufzeit vorsorglich neu holen.
    if (!neu && z != null && s != null && DateTime.now().difference(s) < _gilt * 0.9) return z;
    final j = await api.anfrage('POST', pfad);
    if (j is! Map || j['username'] is! String || j['password'] is! String) {
      throw StateError('MQTT-Zugang: unerwartete Antwort');
    }
    final sek = j['expires_in'];
    _gilt = sek is num && sek > 0 ? Duration(seconds: sek.round()) : const Duration(hours: 12);
    _seit = DateTime.now();
    return _zuletzt = (benutzer: j['username'] as String, passwort: j['password'] as String);
  }

  /// `DELETE /api/mqtt/token` mit dem zuletzt geholten Token.
  @override
  Future<void> widerrufen() async {
    final z = _zuletzt;
    _zuletzt = _seit = null;
    if (z == null) return;
    try {
      await api.anfrage('DELETE', pfad, koerper: {'token': z.passwort});
    } catch (e) {
      Protokoll.schreiben('MQTT-Zugang: widerrufen ging nicht', e);
    }
  }
}

/// Stand der Verbindung (fuer [EchtzeitAnzeige]).
enum EchtzeitStand {
  /// noch nie verbunden oder gerade am Verbinden
  verbinde,

  /// verbunden, Abos laufen
  live,

  /// Verbindung verloren, neuer Versuch folgt
  getrennt,

  /// Broker lehnt Zugang oder Thema ab (kein neuer Versuch ohne neuen Zugang)
  keinZugriff,

  /// [EchtzeitQuelle.schliessen] aufgerufen
  geschlossen,
}

/// Verbindung plus Zeit der letzten Nachricht.
@immutable
class EchtzeitZustand {
  const EchtzeitZustand(this.stand, {this.letzteNachricht, this.grund});
  final EchtzeitStand stand;

  /// Zuletzt eine NEUE Nachricht empfangen (null = noch keine). Gespeicherte
  /// Werte (retained), die beim Abonnieren kommen, zaehlen nicht: sie koennen
  /// Wochen alt sein (Wetterstation ohne Werte, Zaehler aus).
  final DateTime? letzteNachricht;

  /// Kurzer Grund fuers Protokoll bzw. die Anzeige (nie ein Passwort).
  final String? grund;

  /// Verbunden, aber seit [nach] nichts mehr gekommen (oder noch nie).
  bool veraltet(Duration nach, {DateTime? jetzt}) {
    final l = letzteNachricht;
    return l == null || (jetzt ?? DateTime.now()).difference(l) > nach;
  }

  EchtzeitZustand mit({EchtzeitStand? stand, DateTime? letzteNachricht, String? grund}) =>
      EchtzeitZustand(stand ?? this.stand, letzteNachricht: letzteNachricht ?? this.letzteNachricht, grund: grund);
}

/// Was Seiten von der Echtzeit brauchen – eine Schnittstelle, damit Tests und
/// die Attrappe ohne Broker auskommen ([EchtzeitAttrappe]).
abstract class EchtzeitQuelle {
  /// Stand der Verbindung, aendert sich laufend.
  ValueListenable<EchtzeitZustand> get zustand;

  /// Nachrichten zu [filter] (MQTT-Muster mit `+` und `#`). Das erste Abo
  /// startet die Verbindung. Gespeicherte Werte (retained) kommen sofort.
  /// Abbestellen = Abo des Streams kuendigen.
  Stream<MqttNachricht> abonnieren(String filter);

  /// Nach „getrennt“ oder „kein Zugriff“ sofort neu versuchen (Knopf, App
  /// wieder im Vordergrund).
  void nochmals();

  /// Verbindung beenden (z. B. in dispose der Seite).
  Future<void> schliessen();
}

/// Passt [thema] zum MQTT-Muster [filter]? (`+` = eine Ebene, `#` = Rest.)
bool mqttThemaPasst(String filter, String thema) {
  final f = filter.split('/'), t = thema.split('/');
  for (var i = 0; i < f.length; i++) {
    if (f[i] == '#') return true;
    if (i >= t.length) return false;
    if (f[i] == '+') continue;
    if (f[i] != t[i]) return false;
  }
  return f.length == t.length;
}

/// Gemeinsamer Teil: Abos verwalten und Nachrichten verteilen.
abstract class _Verteiler implements EchtzeitQuelle {
  final _zustand = ValueNotifier(const EchtzeitZustand(EchtzeitStand.verbinde));
  final _abos = <String, int>{};
  final _alle = StreamController<MqttNachricht>.broadcast();

  /// Letzte Nachricht je Thema: wer spaeter abonniert, bekommt sie gleich.
  final _letzte = <String, MqttNachricht>{};

  @override
  ValueListenable<EchtzeitZustand> get zustand => _zustand;

  void _stand(EchtzeitStand s, [String? grund]) {
    if (_zustand.value.stand == EchtzeitStand.geschlossen) return;
    _zustand.value = _zustand.value.mit(stand: s, grund: grund);
  }

  void verteilen(MqttNachricht n) {
    _letzte[n.thema] = n;
    if (!n.behalten) _zustand.value = _zustand.value.mit(letzteNachricht: n.zeit);
    _alle.add(n);
  }

  void aboStarten(String filter);
  void aboBeenden(String filter);

  @override
  Stream<MqttNachricht> abonnieren(String filter) {
    late StreamController<MqttNachricht> c;
    StreamSubscription<MqttNachricht>? sub;
    c = StreamController<MqttNachricht>(
      onListen: () {
        for (final n in _letzte.values) {
          if (mqttThemaPasst(filter, n.thema)) c.add(n);
        }
        sub = _alle.stream.where((n) => mqttThemaPasst(filter, n.thema)).listen(c.add);
        final vorher = _abos[filter] ?? 0;
        _abos[filter] = vorher + 1;
        if (vorher == 0) aboStarten(filter);
      },
      onCancel: () async {
        await sub?.cancel();
        final n = (_abos[filter] ?? 1) - 1;
        if (n <= 0) {
          _abos.remove(filter);
          aboBeenden(filter);
        } else {
          _abos[filter] = n;
        }
      },
    );
    return c.stream;
  }

  @mustCallSuper
  @override
  Future<void> schliessen() async {
    _zustand.value = _zustand.value.mit(stand: EchtzeitStand.geschlossen);
    await _alle.close();
  }
}

/// MQTT ueber den Broker der Anlage.
///
/// ```dart
/// final mqtt = RosenwegMqtt(MqttZugang.ueberApi(sitzung.api));
/// mqtt.abonnieren('energy/r9/+/power').listen((n) => …);
/// EchtzeitAnzeige(quelle: mqtt, veraltetNach: const Duration(minutes: 5));
/// ```
class RosenwegMqtt extends _Verteiler {
  RosenwegMqtt(
    this.zugang, {
    this.adresse = 'wss://mqtt.rosenweg4303.ch',
    this.port = 443,
    this.kennungVorsilbe = 'rwapp',
    this.lebenszeichen = const Duration(seconds: 30),
  });

  final MqttZugang zugang;

  /// `wss://…` (WebSocket mit TLS, wie die Web-Seiten) oder ein Rechnername
  /// fuer MQTT ueber TLS (dann [port] 8883).
  final String adresse;
  final int port;

  /// Anfang der Client-Kennung (der Rest ist zufaellig), z. B. `rwwetter`.
  final String kennungVorsilbe;
  final Duration lebenszeichen;

  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _empfang;
  Timer? _wieder;
  var _versuch = 0;
  var _abgelehnt = false;
  var _laeuft = false;
  var _zu = false;

  bool get _verbunden => _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  void aboStarten(String filter) {
    if (_verbunden) {
      _client!.subscribe(filter, MqttQos.atMostOnce);
    } else {
      _verbinden();
    }
  }

  @override
  void aboBeenden(String filter) {
    if (_verbunden) _client!.unsubscribe(filter);
  }

  Future<void> _verbinden() async {
    if (_laeuft || _zu || _verbunden || _abos.isEmpty) return;
    _laeuft = true;
    _wieder?.cancel();
    _stand(EchtzeitStand.verbinde);
    try {
      final a = await zugang.holen(neu: _abgelehnt);
      final kennung = '${kennungVorsilbe}_${Random().nextInt(0x100000000).toRadixString(16).padLeft(8, '0')}';
      final c = mqttClientErzeugen(adresse, kennung, port);
      c.setProtocolV311();
      c.logging(on: false);
      c.keepAlivePeriod = lebenszeichen.inSeconds;
      c.connectTimeoutPeriod = 12000;
      c.autoReconnect = false;
      c.onDisconnected = _getrennt;
      c.onSubscribeFail = (thema) {
        Protokoll.schreiben('MQTT: Abo abgelehnt: $thema');
        _stand(EchtzeitStand.keinZugriff, 'Thema abgelehnt');
      };
      c.connectionMessage = MqttConnectMessage().withClientIdentifier(kennung).startClean().authenticateAs(a.benutzer, a.passwort);
      _client = c;
      final s = await c.connect();
      if (s?.state != MqttConnectionState.connected) {
        throw _Abgelehnt('${s?.returnCode}');
      }
      _versuch = 0;
      _abgelehnt = false;
      _empfang = c.updates?.listen(_empfangen);
      for (final f in _abos.keys) {
        c.subscribe(f, MqttQos.atMostOnce);
      }
      _stand(EchtzeitStand.live);
    } on NoConnectionException catch (e) {
      // mqtt_client meldet abgelehnte Anmeldung so (returnCode im Text)
      final text = '$e';
      final abgelehnt = text.contains('notAuthorized') || text.contains('badUsernameOrPassword');
      _fehlschlag(abgelehnt ? 'Zugang abgelehnt' : 'nicht erreichbar', abgelehnt: abgelehnt);
    } on _Abgelehnt catch (e) {
      _fehlschlag('Zugang abgelehnt (${e.code})', abgelehnt: true);
    } catch (e) {
      _fehlschlag(_kurz(e));
    } finally {
      _laeuft = false;
    }
  }

  void _fehlschlag(String grund, {bool abgelehnt = false}) {
    Protokoll.schreiben('MQTT: $grund');
    _aufraeumen();
    if (abgelehnt && _abgelehnt) {
      // zweimal hintereinander abgelehnt, auch mit neuem Zugang: aufgeben,
      // bis jemand neu abonniert oder [nochmals] ruft.
      _stand(EchtzeitStand.keinZugriff, grund);
      return;
    }
    _abgelehnt = abgelehnt;
    _stand(EchtzeitStand.getrennt, grund);
    _spaeter();
  }

  void _getrennt() {
    if (_zu) return;
    _aufraeumen();
    _stand(EchtzeitStand.getrennt, 'Verbindung verloren');
    _spaeter();
  }

  void _spaeter() {
    if (_zu || _abos.isEmpty) return;
    _versuch++;
    final s = min(60, 2 << min(_versuch - 1, 5)); // 2, 4, 8, 16, 32, 60 s
    _wieder?.cancel();
    _wieder = Timer(Duration(seconds: s), _verbinden);
  }

  @override
  void nochmals() {
    if (_verbunden || _zu) return;
    _versuch = 0;
    if (_zustand.value.stand == EchtzeitStand.keinZugriff) _abgelehnt = true; // neuen Zugang holen
    _wieder?.cancel();
    _verbinden();
  }

  void _empfangen(List<MqttReceivedMessage<MqttMessage>> liste) {
    for (final m in liste) {
      final p = m.payload;
      if (p is! MqttPublishMessage) continue;
      final text = utf8.decode(p.payload.message.toList(), allowMalformed: true);
      verteilen(MqttNachricht(m.topic, text, behalten: p.header?.retain ?? false, zeit: DateTime.now()));
    }
  }

  void _aufraeumen() {
    _empfang?.cancel();
    _empfang = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.onDisconnected = null;
      try {
        c.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<void> schliessen() async {
    _zu = true;
    _wieder?.cancel();
    _aufraeumen();
    await super.schliessen();
  }
}

class _Abgelehnt implements Exception {
  _Abgelehnt(this.code);
  final String code;
}

// Kurzer Fehlertext fuers Protokoll (ohne Stapel).
String _kurz(Object e) {
  final t = '$e';
  return t.length > 160 ? '${t.substring(0, 160)}…' : t;
}

/// Echtzeit ohne Broker: fuer Tests, Bildschirmfotos und die Attrappe einer App.
///
/// ```dart
/// final e = EchtzeitAttrappe({'wetter/r9/outdoortemp': '4.2'});
/// e.senden('wetter/r9/outdoortemp', '4.3');
/// ```
class EchtzeitAttrappe extends _Verteiler {
  /// [gespeichert] = was der Broker als retained haette.
  EchtzeitAttrappe([Map<String, String> gespeichert = const {}, this.stand = EchtzeitStand.live]) {
    final jetzt = DateTime.now();
    gespeichert.forEach((t, v) => _letzte[t] = MqttNachricht(t, v, behalten: true, zeit: jetzt));
  }

  /// Stand nach dem ersten Abo (z. B. [EchtzeitStand.getrennt] fuer Tests).
  final EchtzeitStand stand;

  @override
  void aboStarten(String filter) => _stand(stand);

  @override
  void aboBeenden(String filter) {}

  @override
  void nochmals() => _stand(EchtzeitStand.live);

  /// Neue Nachricht wie vom Broker.
  void senden(String thema, String text, {bool behalten = false}) =>
      verteilen(MqttNachricht(thema, text, behalten: behalten, zeit: DateTime.now()));

  /// Stand von aussen setzen (Tests).
  void standSetzen(EchtzeitStand s) => _stand(s);
}
