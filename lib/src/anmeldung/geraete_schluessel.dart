// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Schluesselpaar EC P-256, das eine Karten-/QR-Sitzung an dieses Geraet
/// bindet - wie `KartenSitzung` in commons-rosenweg (Android-Keystore), hier
/// fuer Desktop und iOS in Dart (pointycastle).
///
/// Der Server (Website api/lib/appkarte.js) kennt nur den oeffentlichen
/// Schluessel (SPKI/DER, Base64) und prueft beim Erneuern eine Unterschrift
/// SHA256withECDSA (DER) ueber `rw-app-sitzung-erneuern\n<sitzung>\n<herausforderung>`.
///
/// Der private Schluessel liegt im Schluesselbund des Systems (macOS/iOS
/// Schluesselbund, Windows Anmeldeinformationen, Linux Secret Service), nicht
/// in Hardware wie auf Android. Wer ihn UND die Sitzungs-Id stiehlt, kann die
/// Sitzung weiterfuehren, bis sie im Portal abgemeldet wird; jede Sitzung ist
/// dort sichtbar (Profil → App-Anmeldungen).
class GeraeteSchluessel {
  GeraeteSchluessel._(this.privat, this.oeffentlich);

  /// Privater Schluessel als Hex (Skalar d) - nur fuer den Schluesselbund.
  final String privat;

  /// Oeffentlicher Schluessel, SPKI/DER Base64 - geht an den Server.
  final String oeffentlich;

  static final _kurve = ECCurve_secp256r1();

  /// SubjectPublicKeyInfo-Kopf fuer EC P-256 mit unkomprimiertem Punkt
  /// (SEQUENCE{SEQUENCE{id-ecPublicKey, prime256v1}, BIT STRING}).
  static const _spkiKopf = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, //
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ];

  static GeraeteSchluessel erzeugen() {
    final r = Random.secure();
    final zufall = FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)))));
    final g = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_kurve), zufall));
    final paar = g.generateKeyPair();
    final pub = paar.publicKey;
    final priv = paar.privateKey;
    final punkt = pub.Q!.getEncoded(false); // 04 || X || Y
    return GeraeteSchluessel._(priv.d!.toRadixString(16), base64Encode([..._spkiKopf, ...punkt]));
  }

  /// SHA256withECDSA ueber [text] (UTF-8), DER, Base64. Deterministisch
  /// (RFC 6979), braucht also keinen Zufall.
  static String unterschreiben(String privatHex, String text) {
    final d = BigInt.parse(privatHex, radix: 16);
    final s = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, _kurve)));
    final u = s.generateSignature(Uint8List.fromList(utf8.encode(text))) as ECSignature;
    return base64Encode(_der(u.r, u.s));
  }

  /// Fuer Tests: Unterschrift mit dem oeffentlichen Schluessel (SPKI Base64) pruefen.
  static bool pruefen(String spkiB64, String text, String unterschriftB64) {
    final spki = base64Decode(spkiB64);
    if (spki.length != _spkiKopf.length + 65) return false;
    final q = _kurve.curve.decodePoint(spki.sublist(_spkiKopf.length));
    final (r, s) = _derLesen(base64Decode(unterschriftB64));
    final v = ECDSASigner(SHA256Digest())..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, _kurve)));
    return v.verifySignature(Uint8List.fromList(utf8.encode(text)), ECSignature(r, s));
  }

  static List<int> _ganzzahl(BigInt z) {
    var b = <int>[];
    var x = z;
    while (x > BigInt.zero) {
      b.insert(0, (x & BigInt.from(0xff)).toInt());
      x = x >> 8;
    }
    if (b.isEmpty) b = [0];
    if (b.first & 0x80 != 0) b.insert(0, 0); // positiv bleiben
    return [0x02, b.length, ...b];
  }

  static List<int> _der(BigInt r, BigInt s) {
    final inhalt = [..._ganzzahl(r), ..._ganzzahl(s)];
    return [0x30, inhalt.length, ...inhalt];
  }

  static (BigInt, BigInt) _derLesen(List<int> d) {
    var i = 2;
    BigInt lies() {
      final n = d[i + 1];
      var z = BigInt.zero;
      for (final b in d.sublist(i + 2, i + 2 + n)) {
        z = (z << 8) | BigInt.from(b);
      }
      i += 2 + n;
      return z;
    }

    final r = lies();
    return (r, lies());
  }
}
