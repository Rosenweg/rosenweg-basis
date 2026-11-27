// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'konfig.dart';
import 'plattform.dart';
import 'protokoll.dart';
import 'station.dart';
import 'verwaltet.dart';

/// Regel (Stefan 25./27.11.2026): Jede Rosenweg-App aktualisiert sich selbst.
/// Aus ist das nur, wo jemand anderes aktualisiert:
///
/// | wo | wer aktualisiert |
/// |---|---|
/// | Android | Rosenweg Updater aus commons-rosenweg (kommt mit dem Android-Teil der Basis); auf geteilten Telefonen Rosenweg Geraet |
/// | Rosenweg-Station (os-stationen) | os-stationen, darum hier aus und ohne Hinweis ([RosenwegStation]) |
/// | Windows-Domaene (verwaltete Installation) | GPO mit `/ALLUSERS`, darum hier aus und ohne Hinweis ([RosenwegVerwaltet]: unter Program Files installiert oder `HKLM\Software\Rosenweg\Verwaltet` = 1) |
/// | iOS | (noch) keine Verteilung ausserhalb des App Store, darum aus |
/// | Linux (eigener Rechner), macOS, Windows | **dieser Updater** |
///
/// Quelle ist derselbe oeffentliche Katalog wie fuer Android und die Seite
/// /apps: `GET https://pbx.rosenweg4303.ch/api/apps/index.json`, Liste
/// `karten`, Eintrag mit `paket` = [RosenwegApp.kennung], darin je Plattform
/// ein Download (`linux-deb`, `macos`, `windows`) mit `version`, `sha256`,
/// `groesse` und `url` (`/api/apps/datei/<app>/<plattform>`). Die Anlage
/// nimmt Dateien nur aus der CI der eingetragenen Repos an (GitHub-OIDC,
/// Version = Tag, Pruefsumme) - siehe Website pbx/README.md.
///
/// Die geladene Datei muss Groesse und SHA-256 aus dem Katalog haben, sonst
/// wird sie geloescht und nichts installiert. Installiert wird immer erst
/// nach einem Klick der Person:
///
/// - Windows: Installer starten, die App beendet sich (damit ihre Dateien
///   frei sind).
/// - macOS: Disk-Image oeffnen; die Person zieht die App in "Programme".
/// - Linux: `pkexec apt-get install` (fragt nach dem Passwort); geht das
///   nicht, liegt das .deb in "Downloads" mit einer klaren Anleitung.
class RosenwegAktualisierung extends ChangeNotifier {
  RosenwegAktualisierung(
    this.app, {
    http.Client? client,
    this.katalog = standardKatalog,
    Future<String> Function()? installiert,
    bool? aktiv,
    String? plattform,
    this.ersteVerzoegerung = const Duration(seconds: 20),
    this.abstand = const Duration(hours: 12),
  })  : _client = client ?? http.Client(),
        _installiert = installiert ?? _standardInstalliert,
        plattform = plattform ?? plattformSchluessel(),
        _aktivFest = aktiv;

  static const standardKatalog = 'https://pbx.rosenweg4303.ch/api/apps/index.json';

  final RosenwegApp app;
  final String katalog;
  final http.Client _client;
  final Future<String> Function() _installiert;
  final bool? _aktivFest;
  final Duration ersteVerzoegerung;
  final Duration abstand;

  /// Schluessel der Plattform im Katalog (`linux-deb`, `macos`, `windows`),
  /// null wo dieser Updater nichts tut.
  final String? plattform;

  static Future<String> _standardInstalliert() async => (await PackageInfo.fromPlatform()).version;

  static String? plattformSchluessel() {
    if (kIsWeb || RosenwegPlattform.istAndroid || RosenwegPlattform.istIos) return null;
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux-deb';
    return null;
  }

  /// Laeuft der Updater hier? Nein auf Android (dort der Kotlin-Updater),
  /// iOS, Rosenweg-Stationen, verwalteten Installationen (Windows-Domaene,
  /// GPO) und in Entwicklungsbauten.
  bool get aktiv =>
      _aktivFest ??
      laeuftHier(plattform: plattform, station: RosenwegStation.erkannt, verwaltet: plattform != null && RosenwegVerwaltet.erkannt);

  /// Die Regel an einer Stelle (testbar).
  static bool laeuftHier(
          {required String? plattform, required bool station, bool verwaltet = false, bool release = kReleaseMode}) =>
      plattform != null && !station && !verwaltet && release;

  AktualisierungsStand stand = AktualisierungsStand.nichts;

  /// Neue Fassung laut Katalog (nur wenn neuer als die installierte).
  NeueFassung? neu;

  /// Installierte Fassung (z. B. "1.2.0").
  String? installiert;

  /// Fortschritt beim Laden, 0..1 (null = unbekannt).
  double? fortschritt;

  /// Text fuer die Person (Fehler, Anleitung nach dem Laden).
  String? meldung;

  /// Geladene, gepruefte Datei.
  File? datei;

  /// Die Person hat "Spaeter" gewaehlt (bis zum naechsten Start).
  bool spaeter = false;

  Timer? _uhr;

  void _setzen(AktualisierungsStand s, {String? text}) {
    stand = s;
    meldung = text;
    notifyListeners();
  }

  /// Beim Start: nach [ersteVerzoegerung] pruefen, dann alle [abstand].
  void starten() {
    if (!aktiv) {
      final grund = plattform == null
          ? 'Plattform'
          : RosenwegStation.erkannt
              ? 'Rosenweg-Station'
              : RosenwegVerwaltet.erkannt
                  ? 'verwaltete Installation, ${RosenwegVerwaltet.grund}'
                  : 'Entwicklungsbau';
      Protokoll.schreiben('Aktualisierung aus ($grund)');
      return;
    }
    _uhr?.cancel();
    _uhr = Timer(ersteVerzoegerung, () {
      pruefen();
      _uhr = Timer.periodic(abstand, (_) => pruefen());
    });
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  /// Katalog lesen. Fehler (kein Netz, Katalog kaputt) bleiben still im
  /// Protokoll: ein fehlendes Update ist kein Grund, die Person zu stoeren.
  Future<void> pruefen() async {
    if (!aktiv || stand == AktualisierungsStand.laedt || stand == AktualisierungsStand.installiert) return;
    try {
      installiert ??= await _installiert();
      final r = await _client.get(Uri.parse(katalog)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw HttpException('Katalog ${r.statusCode}');
      final f = fassungImKatalog(jsonDecode(utf8.decode(r.bodyBytes)), app.kennung, plattform!, basis: Uri.parse(katalog));
      if (f == null || !istNeuer(f.version, installiert!)) {
        neu = null;
        if (stand == AktualisierungsStand.verfuegbar) _setzen(AktualisierungsStand.nichts);
        return;
      }
      if (neu?.version != f.version) {
        Protokoll.schreiben('Neue Fassung ${f.version} (installiert $installiert)');
        neu = f;
        datei = null;
        _setzen(AktualisierungsStand.verfuegbar);
      }
    } catch (e) {
      Protokoll.schreiben('Aktualisierung pruefen', e);
    }
  }

  /// "Spaeter": Hinweis bis zum naechsten Start ausblenden.
  void spaeterErinnern() {
    spaeter = true;
    notifyListeners();
  }

  /// Leiste schliessen (nach der Anleitung oder einem Fehler).
  void ausblenden() {
    spaeter = true;
    _setzen(neu != null && stand == AktualisierungsStand.fehler ? AktualisierungsStand.verfuegbar : AktualisierungsStand.nichts);
  }

  /// Laden, pruefen, installieren (ein Klick).
  Future<void> aktualisieren() async {
    final f = neu;
    if (f == null) return;
    try {
      final d = datei ?? await _laden(f);
      datei = d;
      await _installieren(d, f);
    } catch (e) {
      Protokoll.schreiben('Aktualisierung', e);
      _setzen(AktualisierungsStand.fehler, text: e is AktualisierungsFehler ? e.text : 'Die neue Fassung konnte nicht geladen werden. Bitte später nochmals versuchen.');
    }
  }

  Future<File> _laden(NeueFassung f) async {
    fortschritt = 0;
    _setzen(AktualisierungsStand.laedt);
    final ordner = await Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}rosenweg-aktualisierung${Platform.pathSeparator}${app.ordner}')
        .create(recursive: true);
    final ziel = File('${ordner.path}${Platform.pathSeparator}${f.dateiname(app.ordner)}');
    final r = await _client.send(http.Request('GET', f.url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw AktualisierungsFehler('Die neue Fassung ist gerade nicht erhältlich (${r.statusCode}).');
    final gesamt = f.groesse > 0 ? f.groesse : (r.contentLength ?? 0);
    final aus = ziel.openWrite();
    var n = 0;
    final summe = _Summe();
    final rechner = sha256.startChunkedConversion(summe);
    try {
      await for (final teil in r.stream.timeout(const Duration(seconds: 60))) {
        rechner.add(teil);
        aus.add(teil);
        n += teil.length;
        if (gesamt > 0) {
          fortschritt = n / gesamt;
          notifyListeners();
        }
      }
    } finally {
      await aus.close();
      rechner.close();
    }
    final ist = summe.wert.toString();
    if (!pruefsummeStimmt(ist: ist, istGroesse: n, soll: f)) {
      await ziel.delete().catchError((_) => ziel);
      Protokoll.schreiben('Pruefsumme falsch: $ist / ${f.sha256}, $n / ${f.groesse} Bytes');
      throw AktualisierungsFehler('Die geladene Datei ist beschädigt (Prüfsumme stimmt nicht). Sie wurde gelöscht; bitte später nochmals.');
    }
    Protokoll.schreiben('Neue Fassung ${f.version} geladen und geprueft: ${ziel.path}');
    return ziel;
  }

  Future<void> _installieren(File d, NeueFassung f) async {
    switch (plattform) {
      case 'windows':
        // Inno Setup (PrivilegesRequired=lowest): ersetzt die App; dazu muss sie zu sein.
        await Process.start(d.path, const [], mode: ProcessStartMode.detached);
        _setzen(AktualisierungsStand.installiert, text: 'Das Installationsprogramm ist gestartet. ${app.name} schliesst sich jetzt.');
        Protokoll.schreiben('Installer gestartet, App endet');
        await Future<void>.delayed(const Duration(seconds: 2));
        exit(0);
      case 'macos':
        final r = await Process.run('open', [d.path]);
        if (r.exitCode != 0) throw AktualisierungsFehler('Das Disk-Image liess sich nicht öffnen: ${d.path}');
        _setzen(AktualisierungsStand.installiert,
            text: 'Im geöffneten Fenster „${app.name}“ in „Programme“ ziehen und ersetzen, dann ${app.name} neu öffnen.');
      case 'linux-deb':
        if (await _mitPkexec(d)) {
          _setzen(AktualisierungsStand.installiert, text: 'Fassung ${f.version} ist installiert. Bitte ${app.name} schliessen und neu öffnen.');
          return;
        }
        final kopie = await _nachDownloads(d);
        _setzen(AktualisierungsStand.installiert,
            text: 'Die neue Fassung liegt in ${kopie.path}.\nInstallieren im Terminal mit:\n'
                'sudo apt install "${kopie.path}"\nDanach ${app.name} neu öffnen.');
    }
  }

  /// Debian/Ubuntu: apt prueft Abhaengigkeiten; pkexec fragt nach dem
  /// Passwort (polkit). false, wenn es nicht geht (kein pkexec, abgebrochen).
  Future<bool> _mitPkexec(File d) async {
    try {
      final da = await Process.run('sh', ['-c', 'command -v pkexec && command -v apt-get']);
      if (da.exitCode != 0) return false;
      _setzen(AktualisierungsStand.installiert, text: 'Installieren … (das System fragt nach dem Passwort)');
      final r = await Process.run('pkexec', ['apt-get', 'install', '-y', d.absolute.path]);
      Protokoll.schreiben('pkexec apt-get install: ${r.exitCode}');
      return r.exitCode == 0;
    } catch (e) {
      Protokoll.schreiben('pkexec', e);
      return false;
    }
  }

  Future<File> _nachDownloads(File d) async {
    final heim = Platform.environment['HOME'];
    final dl = heim == null ? null : Directory('$heim/Downloads');
    if (dl == null || !await dl.exists()) return d;
    return d.copy('${dl.path}/${d.uri.pathSegments.last}');
  }
}

enum AktualisierungsStand { nichts, verfuegbar, laedt, installiert, fehler }

/// Eine Fassung aus dem Katalog.
class NeueFassung {
  const NeueFassung({required this.version, required this.sha256, required this.groesse, required this.url, this.notiz = ''});
  final String version;
  final String sha256;
  final int groesse;
  final Uri url;
  final String notiz;

  String dateiname(String ordner) {
    final endung = switch (url.pathSegments.isEmpty ? '' : url.pathSegments.last) {
      'windows' => '.exe',
      'macos' => '.dmg',
      'linux-deb' => '.deb',
      _ => '',
    };
    return '$ordner-$version$endung'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  }
}

/// Eintrag fuer [paket] und [plattform] aus `index.json` (Liste `karten`),
/// null wenn keiner da ist oder er unvollstaendig ist.
NeueFassung? fassungImKatalog(Object? json, String paket, String plattform, {required Uri basis}) {
  if (json is! Map) return null;
  final karten = json['karten'];
  if (karten is! List) return null;
  for (final k in karten) {
    if (k is! Map || k['paket'] != paket) continue;
    final dl = k['downloads'];
    if (dl is! List) return null;
    for (final d in dl) {
      if (d is! Map || d['plattform'] != plattform) continue;
      final v = '${d['version'] ?? ''}'.trim();
      final sha = '${d['sha256'] ?? ''}'.trim().toLowerCase();
      final url = '${d['url'] ?? ''}';
      if (v.isEmpty || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) || !url.startsWith('/api/apps/')) return null;
      return NeueFassung(
        version: v,
        sha256: sha,
        groesse: d['groesse'] is int ? d['groesse'] as int : int.tryParse('${d['groesse']}') ?? 0,
        // nur relative Adressen auf derselben Anlage
        url: basis.resolve(url),
        notiz: '${d['notiz'] ?? ''}',
      );
    }
  }
  return null;
}

/// "1.10.0" > "1.9.3"? Build-Nummer (+n) und Vorab-Teile (-beta) zaehlen
/// nicht; fehlende Stellen gelten als 0.
bool istNeuer(String katalog, String installiert) {
  List<int> teile(String v) =>
      v.split(RegExp(r'[+-]')).first.split('.').map((t) => int.tryParse(t.trim()) ?? 0).toList();
  final a = teile(katalog), b = teile(installiert);
  for (var i = 0; i < 4; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

bool pruefsummeStimmt({required String ist, required int istGroesse, required NeueFassung soll}) =>
    ist.toLowerCase() == soll.sha256 && (soll.groesse <= 0 || istGroesse == soll.groesse);

class _Summe implements Sink<Digest> {
  Digest? wert;
  @override
  void add(Digest d) => wert = d;
  @override
  void close() {}
}

class AktualisierungsFehler implements Exception {
  AktualisierungsFehler(this.text);
  final String text;
  @override
  String toString() => text;
}
