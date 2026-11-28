// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

/// Web: kein Kerberos aus der App heraus. Den stillen Kerberos-Versuch macht
/// dort die Website-Anmeldung selbst (js/authentik-auth.js). Gleiche
/// Schnittstelle wie kerberos_ffi.dart.
abstract class KerberosTicket {
  Future<String?> token(String dienst, {Duration zeit = const Duration(seconds: 8)});

  static KerberosTicket system() => const KeinKerberos();
}

class KeinKerberos implements KerberosTicket {
  const KeinKerberos();
  @override
  Future<String?> token(String dienst, {Duration zeit = const Duration(seconds: 8)}) async => null;
}

typedef KerberosErgebnis = ({Uint8List? token, String grund});

String get kerberosLetzterGrund => '';
