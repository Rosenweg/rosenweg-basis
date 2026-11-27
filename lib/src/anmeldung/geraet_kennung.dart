// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../plattform.dart';

/// Wie das Geraet sich beim Server meldet (Karten-, QR- und Handy-Anmeldung):
/// Kennung fuer "neues Geraet" (Mail an die Person), Name und Plattform fuer
/// die Anzeige im Portal.
///
/// Die Kennung ist `sha256("rosenweg:<id>")` als Hex - wie commons-rosenweg mit
/// der ANDROID_ID -, damit alle Rosenweg-Apps EINES Geraets dieselbe haben
/// und die Person nicht pro App eine Mail "neues Geraet" bekommt:
///   Linux   /etc/machine-id
///   macOS   IOPlatformUUID (ioreg)
///   Windows MachineGuid (Registry)
///   iOS     identifierForVendor (alle Rosenweg-Apps desselben Herausgebers)
/// Ohne sie: eine zufaellige, im Schluesselbund der App gemerkte Kennung.
class GeraetKennung {
  GeraetKennung._();

  static String _hash(String id) => sha256.convert(utf8.encode('rosenweg:$id')).toString();

  /// Kennung (64 Hex-Zeichen) oder null, wenn das System keine liefert.
  static Future<String?> lesen() async {
    try {
      final id = await _roh();
      if (id == null || id.trim().isEmpty) return null;
      return _hash(id.trim().toLowerCase());
    } catch (_) {
      return null;
    }
  }

  /// Aus einer zufaelligen Zeichenkette (Rueckfall, im Schluesselbund gemerkt).
  static String ausZufall(String zufall) => _hash('zufall:$zufall');

  static Future<String?> _roh() async {
    if (RosenwegPlattform.istIos) return RosenwegPlattform.iosGeraetKennung();
    if (Platform.isLinux) {
      for (final p in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        final f = File(p);
        if (await f.exists()) return f.readAsString();
      }
      return null;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('/usr/sbin/ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      final m = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch('${r.stdout}');
      return m?.group(1);
    }
    if (Platform.isWindows) {
      final r = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${r.stdout}');
      return m?.group(1);
    }
    return null;
  }

  /// Anzeigename, z. B. "station-07" oder "iPhone".
  static Future<String> name() async {
    if (RosenwegPlattform.istIos) return await RosenwegPlattform.iosGeraetName() ?? 'iPhone';
    try {
      final h = Platform.localHostname.trim();
      if (h.isNotEmpty) return h.length > 60 ? h.substring(0, 60) : h;
    } catch (_) {}
    return plattform();
  }

  /// "Linux", "macOS 15.2", "Windows 11", "iOS 18.1" - kurz, fuer die Anzeige.
  static String plattform() {
    final v = Platform.operatingSystemVersion;
    if (Platform.isIOS) return 'iOS ${RegExp(r'[\d.]+').firstMatch(v)?.group(0) ?? ''}'.trim();
    if (Platform.isMacOS) return 'macOS ${RegExp(r'[\d.]+').firstMatch(v)?.group(0) ?? ''}'.trim();
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}
