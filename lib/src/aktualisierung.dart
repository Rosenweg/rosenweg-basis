// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// - macOS: der Browser laedt das Disk-Image (in der Sandbox geladene Dateien
///   duerfen nicht ausgefuehrt werden); die Person zieht die App in "Programme".
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
    this.standAdresse = standardStand,
    Future<String?> Function()? geraetKennung,
    Future<bool> Function(Uri)? imBrowserOeffnen,
  })  : _client = client ?? http.Client(),
        _imBrowser = imBrowserOeffnen ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication)),
        _installiert = installiert ?? _standardInstalliert,
        plattform = plattform ?? plattformSchluessel(),
        _aktivFest = aktiv,
        _geraetKennung = geraetKennung ?? standardGeraetKennung {
    zuletzt = this;
  }

  static const standardKatalog = 'https://pbx.rosenweg4303.ch/api/apps/index.json';

  /// Versionsstand ans NOC (Telefonanlage, Tabelle apps_stand; ohne Personendaten).
  static const standardStand = 'https://pbx.rosenweg4303.ch/api/apps/stand';

  /// Der Updater dieser App (zuletzt erzeugt, in der Regel von [rosenwegStarten]):
  /// fuer den Knopf "Nach Updates suchen" in den gemeinsamen Einstellungen.
  static RosenwegAktualisierung? zuletzt;

  final String standAdresse;
  final Future<String?> Function() _geraetKennung;
  final Future<bool> Function(Uri) _imBrowser;

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
      // Auch ohne Update den Stand melden (Stationen, verwaltete PCs), damit das NOC sie sieht.
      if (plattform != null && kReleaseMode) {
        _uhr?.cancel();
        _uhr = Timer(ersteVerzoegerung, standMelden);
      }
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
      await _pruefen();
    } catch (e) {
      Protokoll.schreiben('Aktualisierung pruefen', e);
    }
  }

  /// "Nach Updates suchen" (Knopf in den Einstellungen): sofort pruefen.
  /// Ergebnis fuer die Person; wirft nie. Neue Fassung: danach
  /// [aktualisieren] ("Installieren").
  Future<PruefErgebnis> jetztPruefen() async {
    if (!aktiv) return PruefErgebnis.aus(ausGrund);
    if (stand == AktualisierungsStand.laedt) return const PruefErgebnis._(PruefArt.laeuft, 'Die neue Fassung wird gerade geladen …');
    try {
      installiert ??= await _installiert();
      final f = await _pruefen();
      spaeter = false;
      if (f == null) return PruefErgebnis._(PruefArt.aktuell, 'Aktuell: ${app.name} $installiert ist die neueste Fassung.');
      notifyListeners();
      return PruefErgebnis._(PruefArt.neu, 'Neue Fassung ${f.version} (installiert $installiert)', neu: f);
    } catch (e) {
      Protokoll.schreiben('Nach Updates suchen', e);
      return PruefErgebnis._(PruefArt.fehler, klartext(e));
    }
  }

  /// Warum der Updater hier aus ist, als Satz fuer die Person (leer, wenn er laeuft).
  String get ausGrund {
    if (aktiv) return '';
    if (plattform == null) {
      return RosenwegPlattform.istAndroid
          ? 'Auf Android hält der Rosenweg Updater die Apps aktuell.'
          : 'Auf diesem Gerät gibt es (noch) keine Updates über die App.';
    }
    if (RosenwegStation.erkannt) return 'Auf dieser Rosenweg-Station hält die Station selbst die Apps aktuell.';
    if (plattform != null && RosenwegVerwaltet.erkannt) return 'Diese Installation wird zentral verwaltet und aktualisiert (${RosenwegVerwaltet.grund}).';
    return 'Entwicklungsfassung: keine Updates über die App.';
  }

  /// Technischer Fehler -> Satz fuer die Person.
  static String klartext(Object e) => switch (e) {
        AktualisierungsFehler(:final text) => text,
        SocketException() => 'Keine Verbindung zum Rosenweg-Server. Ist der Computer mit dem Internet verbunden?',
        TimeoutException() => 'Der Rosenweg-Server antwortet nicht. Bitte später nochmals versuchen.',
        HandshakeException() || TlsException() => 'Die sichere Verbindung zum Rosenweg-Server ist fehlgeschlagen (Datum und Uhrzeit richtig?).',
        HttpException(:final message) => 'Der Rosenweg-Server hat die Liste der Apps nicht geliefert ($message).',
        FormatException() => 'Der Rosenweg-Server hat eine unlesbare Antwort geschickt. Bitte später nochmals versuchen.',
        _ => 'Unerwarteter Fehler: $e',
      };

  Future<NeueFassung?> _pruefen() async {
    installiert ??= await _installiert();
    final r = await _client.get(Uri.parse(katalog)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw HttpException('Fehler ${r.statusCode}');
    final f = fassungImKatalog(jsonDecode(utf8.decode(r.bodyBytes)), app.kennung, plattform!, basis: Uri.parse(katalog));
    unawaited(standMelden());
    if (f == null || !istNeuer(f.version, installiert!)) {
      neu = null;
      if (stand == AktualisierungsStand.verfuegbar) _setzen(AktualisierungsStand.nichts);
      return null;
    }
    if (neu?.version != f.version) {
      Protokoll.schreiben('Neue Fassung ${f.version} (installiert $installiert)');
      neu = f;
      datei = null;
      _setzen(AktualisierungsStand.verfuegbar);
    }
    return f;
  }

  /// Versionsstand ans NOC melden: Geraet (gehasht), Paket, Version,
  /// Plattform - keine Personendaten. Fehler bleiben still.
  Future<void> standMelden() async {
    final pf = plattform;
    if (pf == null) return;
    try {
      final g = await _geraetKennung();
      if (g == null) return;
      installiert ??= await _installiert();
      final body = standJson(geraet: g, plattform: pf, paket: app.kennung, version: installiert!,
          station: RosenwegStation.erkannt || RosenwegVerwaltet.erkannt, system: Platform.operatingSystem);
      final r = await _client
          .post(Uri.parse(standAdresse), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) Protokoll.schreiben('Stand melden: ${r.statusCode}');
    } catch (e) {
      Protokoll.schreiben('Stand melden', e);
    }
  }

  static Future<String?> _eigeneKennung() async {
    final heim = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (heim == null) return null;
    final f = File('$heim${Platform.pathSeparator}.rosenweg-geraet-id');
    if (await f.exists()) return (await f.readAsString()).trim();
    final r = Random.secure();
    final neu = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await f.writeAsString(neu);
    return neu;
  }

  /// Inhalt der Meldung (testbar).
  static Map<String, Object?> standJson(
          {required String geraet,
          required String plattform,
          required String paket,
          required String version,
          bool station = false,
          String system = ''}) =>
      {
        'geraet': geraet,
        'plattform': plattform,
        'station': station,
        'system': system,
        'apps': [
          {'paket': paket, 'version': version.split('+').first},
        ],
      };

  /// Geraet fuer das NOC: SHA-256 der Maschinen-ID (Linux /etc/machine-id,
  /// macOS IOPlatformUUID, Windows MachineGuid) mit festem Praefix - wie
  /// der Android-Updater, nicht umkehrbar. null, wenn es keine gibt.
  static Future<String?> standardGeraetKennung() async {
    try {
      String? id;
      if (Platform.isLinux) {
        for (final p in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
          final f = File(p);
          if (await f.exists()) {
            id = (await f.readAsString()).trim();
            break;
          }
        }
      } else if (Platform.isMacOS) {
        final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
        id = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch('${r.stdout}')?.group(1);
      } else if (Platform.isWindows) {
        final r = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
        id = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${r.stdout}')?.group(1);
      }
      // Rueckfall (z. B. macOS-Sandbox ohne ioreg): eine zufaellige Kennung im Ordner der
      // App, einmal erzeugt. Dann zaehlt das NOC das Geraet je App, das genuegt fuer
      // "Anteil veralteter Geraete je App".
      if (id == null || id.isEmpty) id = await _eigeneKennung();
      if (id == null || id.isEmpty) return null;
      return sha256.convert(utf8.encode('rosenweg-geraet:$id')).toString();
    } catch (_) {
      return null;
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
      if (plattform == 'macos') {
        await _macosImBrowser(f);
        return;
      }
      final d = datei ?? await _laden(f);
      datei = d;
      await _installieren(d, f);
    } catch (e) {
      Protokoll.schreiben('Aktualisierung', e);
      _setzen(AktualisierungsStand.fehler, text: e is AktualisierungsFehler ? e.text : 'Die neue Fassung konnte nicht geladen werden. Bitte später nochmals versuchen.');
    }
  }

  /// macOS (0.6.3, Test 27.11.2026): Ein Disk-Image, das die App selbst laedt, bekommt
  /// in der App-Sandbox die Quarantaene "created by an AppSandbox" - die daraus kopierte
  /// App laesst sich danach NICHT mehr oeffnen ("exec/open not allowed", Fehler -10810).
  /// Darum laedt auf dem Mac der Browser die neue Fassung (wie von /apps); macOS prueft
  /// und fragt dann wie bei der ersten Installation.
  Future<void> _macosImBrowser(NeueFassung f) async {
    if (!await _imBrowser(f.url)) {
      throw AktualisierungsFehler('Der Browser liess sich nicht öffnen. Die neue Fassung gibt es auf rosenweg4303.ch/apps.');
    }
    Protokoll.schreiben('macOS: neue Fassung ${f.version} im Browser geladen (${f.url})');
    _setzen(AktualisierungsStand.installiert,
        text: 'Die neue Fassung ${f.version} wird im Browser geladen. Das Disk-Image öffnen, „${app.name}“ in „Programme“ '
            'ziehen und ersetzen, dann ${app.name} neu öffnen.');
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

enum PruefArt { aktuell, neu, fehler, aus, laeuft }

/// Ergebnis von [RosenwegAktualisierung.jetztPruefen].
class PruefErgebnis {
  const PruefErgebnis._(this.art, this.text, {this.neu});
  const PruefErgebnis.aus(this.text)
      : art = PruefArt.aus,
        neu = null;
  final PruefArt art;

  /// Satz fuer die Person.
  final String text;
  final NeueFassung? neu;
}

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
