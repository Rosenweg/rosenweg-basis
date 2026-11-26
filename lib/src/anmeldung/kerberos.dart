// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Das Kerberos-Ticket der Sitzung als SPNEGO-Token fuer einen Dienst
/// ("Negotiate", RFC 4559) — ohne Browser.
///
/// - Linux (Rosenweg OS, Domaenenanmeldung ueber sssd): GSS-API aus
///   `libgssapi_krb5.so.2` (MIT, Paket `libgssapi-krb5-2`), Mechanismus SPNEGO
///   wie Chromium und `curl --negotiate`. Der Ticket-Speicher ist der der
///   Sitzung (KRB5CCNAME bzw. krb5.conf).
/// - Windows (Rechner der Domaene): SSPI aus `secur32.dll`, Paket
///   "Negotiate" mit dem Ticket der Windows-Anmeldung. Faellt Windows dabei auf
///   NTLM zurueck (kein Kerberos erreichbar), wird das Token verworfen: NTLM
///   soll nicht an den Server gehen (wie AuthSchemes ohne ntlm auf den
///   Stationen).
/// - sonst (macOS, Android): kein Token.
///
/// Gefragt wird der Dienst als voller Principal, z. B.
/// `HTTP/authentik.rosenweg4303.ch@AD.ROSENWEG4303.CH` — ohne DNS-Umweg
/// (CNAME, Rueckwaertsaufloesung), wie DisableAuthNegotiateCnameLookup im
/// Browser der Stationen.
///
/// Gibt es kein Ticket (nicht in der Domaene angemeldet, abgelaufen), endet
/// das sofort mit null, ohne Netz. Mit Ticket, aber ohne erreichbaren KDC
/// (unterwegs) kann die Bibliothek haengen; darum laeuft sie in einem eigenen
/// Isolate und [zeit] begrenzt das Warten.
abstract class KerberosTicket {
  /// Base64 des ersten SPNEGO-Tokens oder null (kein Ticket, Fehler,
  /// Zeit um). Wirft nie.
  Future<String?> token(String dienst, {Duration zeit = const Duration(seconds: 8)});

  /// Das passende fuer dieses System.
  static KerberosTicket system() {
    if (Platform.isLinux) return const _ImIsolate(_gssToken);
    if (Platform.isWindows) return const _ImIsolate(_sspiToken);
    return const KeinKerberos();
  }
}

/// Kein Kerberos (macOS, Telefone, Tests).
class KeinKerberos implements KerberosTicket {
  const KeinKerberos();
  @override
  Future<String?> token(String dienst, {Duration zeit = const Duration(seconds: 8)}) async => null;
}

/// Ergebnis aus dem Isolate: Token oder Grund (nur fuers Protokoll).
typedef KerberosErgebnis = ({Uint8List? token, String grund});

class _ImIsolate implements KerberosTicket {
  const _ImIsolate(this._holen);
  final KerberosErgebnis Function(String dienst) _holen;

  /// Grund des letzten Fehlschlags, ohne Geheimnisse (fuer das Protokoll).
  static String letzterGrund = '';

  @override
  Future<String?> token(String dienst, {Duration zeit = const Duration(seconds: 8)}) async {
    final holen = _holen;
    try {
      final e = await Isolate.run(() => holen(dienst)).timeout(zeit);
      letzterGrund = e.grund;
      final t = e.token;
      return t == null || t.isEmpty ? null : base64Encode(t);
    } catch (e) {
      // Zeit um (KDC nicht erreichbar) oder Bibliothek fehlt.
      letzterGrund = '$e';
      return null;
    }
  }
}

/// Fuer das Protokoll der Anmeldung: warum es kein Ticket gab.
String get kerberosLetzterGrund => _ImIsolate.letzterGrund;

// ── Linux: GSS-API (MIT) ────────────────────────────────────────────────────

final class _GssBuffer extends Struct {
  @Size()
  external int length;
  external Pointer<Void> value;
}

/// gss_OID_desc. Auf Linux (MIT) ohne Packung: OM_uint32, dann Zeiger.
final class _GssOid extends Struct {
  @Uint32()
  external int length;
  external Pointer<Void> elements;
}

typedef _ImportNameC = Uint32 Function(Pointer<Uint32>, Pointer<_GssBuffer>, Pointer<_GssOid>, Pointer<Pointer<Void>>);
typedef _ImportNameD = int Function(Pointer<Uint32>, Pointer<_GssBuffer>, Pointer<_GssOid>, Pointer<Pointer<Void>>);
typedef _InitC = Uint32 Function(
    Pointer<Uint32> minor,
    Pointer<Void> cred,
    Pointer<Pointer<Void>> ctx,
    Pointer<Void> name,
    Pointer<_GssOid> mech,
    Uint32 flags,
    Uint32 zeit,
    Pointer<Void> bindungen,
    Pointer<_GssBuffer> eingabe,
    Pointer<Pointer<_GssOid>> mechIst,
    Pointer<_GssBuffer> ausgabe,
    Pointer<Uint32> flagsIst,
    Pointer<Uint32> zeitIst);
typedef _InitD = int Function(Pointer<Uint32>, Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Void>, Pointer<_GssOid>, int, int,
    Pointer<Void>, Pointer<_GssBuffer>, Pointer<Pointer<_GssOid>>, Pointer<_GssBuffer>, Pointer<Uint32>, Pointer<Uint32>);
typedef _RelBufC = Uint32 Function(Pointer<Uint32>, Pointer<_GssBuffer>);
typedef _RelBufD = int Function(Pointer<Uint32>, Pointer<_GssBuffer>);
typedef _RelNameC = Uint32 Function(Pointer<Uint32>, Pointer<Pointer<Void>>);
typedef _RelNameD = int Function(Pointer<Uint32>, Pointer<Pointer<Void>>);
typedef _DelCtxC = Uint32 Function(Pointer<Uint32>, Pointer<Pointer<Void>>, Pointer<_GssBuffer>);
typedef _DelCtxD = int Function(Pointer<Uint32>, Pointer<Pointer<Void>>, Pointer<_GssBuffer>);

/// 1.2.840.113554.1.2.2.1 (GSS_KRB5_NT_PRINCIPAL_NAME): "dienst/host@REALM".
const _oidKrb5Principal = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x12, 0x01, 0x02, 0x02, 0x01];

/// 1.3.6.1.5.5.2 (SPNEGO).
const _oidSpnego = [0x2b, 0x06, 0x01, 0x05, 0x05, 0x02];

/// GSS_ERROR(): Aufruf- oder Routinefehler (obere 16 Bit).
bool _gssFehler(int major) => major & 0xffff0000 != 0;

/// Bibliothek fuer [gssTokenAus]; auf Linux `libgssapi_krb5.so.2`.
const gssBibliothekLinux = 'libgssapi_krb5.so.2';

KerberosErgebnis _gssToken(String dienst) => gssTokenAus(gssBibliothekLinux, dienst);

/// GSS-API-Token aus einer bestimmten Bibliothek (oeffentlich nur fuer
/// Tests).
KerberosErgebnis gssTokenAus(String bibliothek, String dienst) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(bibliothek);
  } catch (e) {
    return (token: null, grund: '$bibliothek fehlt');
  }
  final importName = lib.lookupFunction<_ImportNameC, _ImportNameD>('gss_import_name');
  final init = lib.lookupFunction<_InitC, _InitD>('gss_init_sec_context');
  final relBuf = lib.lookupFunction<_RelBufC, _RelBufD>('gss_release_buffer');
  final relName = lib.lookupFunction<_RelNameC, _RelNameD>('gss_release_name');
  final delCtx = lib.lookupFunction<_DelCtxC, _DelCtxD>('gss_delete_sec_context');

  return using((a) {
    Pointer<_GssOid> oid(List<int> b) {
      final e = a<Uint8>(b.length)..asTypedList(b.length).setAll(0, b);
      final o = a<_GssOid>();
      o.ref
        ..length = b.length
        ..elements = e.cast();
      return o;
    }

    final minor = a<Uint32>();
    final namePuffer = a<_GssBuffer>();
    final nameBytes = utf8.encode(dienst);
    final n = a<Uint8>(nameBytes.length)..asTypedList(nameBytes.length).setAll(0, nameBytes);
    namePuffer.ref
      ..length = nameBytes.length
      ..value = n.cast();
    final name = a<Pointer<Void>>();
    final ctx = a<Pointer<Void>>()..value = nullptr;
    final aus = a<_GssBuffer>();
    aus.ref
      ..length = 0
      ..value = nullptr;

    var major = importName(minor, namePuffer, oid(_oidKrb5Principal), name);
    if (_gssFehler(major)) return (token: null, grund: 'gss_import_name 0x${major.toRadixString(16)}/${minor.value}');
    try {
      // Ohne Flags: kein Weiterreichen des Tickets (Delegation), keine
      // gegenseitige Pruefung — der Server ist ueber TLS gepruefter Authentik.
      major = init(minor, nullptr, ctx, name.value, oid(_oidSpnego), 0, 0, nullptr, nullptr, nullptr, aus, nullptr, nullptr);
      if (_gssFehler(major)) {
        // z. B. 0x70000 GSS_S_NO_CRED: kein Ticket in der Sitzung.
        return (token: null, grund: 'gss_init_sec_context 0x${major.toRadixString(16)}/${minor.value}');
      }
      final t = Uint8List.fromList(aus.ref.value.cast<Uint8>().asTypedList(aus.ref.length));
      return (token: t, grund: 'ok');
    } finally {
      if (aus.ref.value != nullptr) relBuf(minor, aus);
      if (ctx.value != nullptr) delCtx(minor, ctx, nullptr);
      relName(minor, name);
    }
  });
}

// ── Windows: SSPI ───────────────────────────────────────────────────────────

final class _SecHandle extends Struct {
  @IntPtr()
  external int lower;
  @IntPtr()
  external int upper;
}

final class _SecBuffer extends Struct {
  @Uint32()
  external int cbBuffer;
  @Uint32()
  external int bufferType;
  external Pointer<Void> pvBuffer;
}

final class _SecBufferDesc extends Struct {
  @Uint32()
  external int ulVersion;
  @Uint32()
  external int cBuffers;
  external Pointer<_SecBuffer> pBuffers;
}

typedef _AcquireC = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Void>, Pointer<_SecHandle>, Pointer<Int64>);
typedef _AcquireD = int Function(Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Void>, Pointer<_SecHandle>, Pointer<Int64>);
typedef _IscC = Int32 Function(Pointer<_SecHandle>, Pointer<_SecHandle>, Pointer<Utf16>, Uint32, Uint32, Uint32,
    Pointer<_SecBufferDesc>, Uint32, Pointer<_SecHandle>, Pointer<_SecBufferDesc>, Pointer<Uint32>, Pointer<Int64>);
typedef _IscD = int Function(Pointer<_SecHandle>, Pointer<_SecHandle>, Pointer<Utf16>, int, int, int,
    Pointer<_SecBufferDesc>, int, Pointer<_SecHandle>, Pointer<_SecBufferDesc>, Pointer<Uint32>, Pointer<Int64>);
typedef _FreeBufC = Int32 Function(Pointer<Void>);
typedef _FreeBufD = int Function(Pointer<Void>);
typedef _HandleC = Int32 Function(Pointer<_SecHandle>);
typedef _HandleD = int Function(Pointer<_SecHandle>);

const _secpkgCredOutbound = 2;
const _iscReqAllocateMemory = 0x100;
const _securityNativeDrep = 0x10;
const _secbufferToken = 2;
const _secEOk = 0;
const _secIContinueNeeded = 0x00090312;

/// SSPI will den Dienst ohne Realm ("HTTP/host"); der Realm kommt aus der
/// Domaene des Rechners.
String sspiZiel(String dienst) => dienst.split('@').first;

/// Enthaelt das Token eine NTLM-Nachricht ("NTLMSSP\0")?
bool istNtlm(Uint8List t) {
  const sig = [0x4e, 0x54, 0x4c, 0x4d, 0x53, 0x53, 0x50, 0x00];
  outer:
  for (var i = 0; i + sig.length <= t.length; i++) {
    for (var j = 0; j < sig.length; j++) {
      if (t[i + j] != sig[j]) continue outer;
    }
    return true;
  }
  return false;
}

KerberosErgebnis _sspiToken(String dienst) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open('secur32.dll');
  } catch (e) {
    return (token: null, grund: 'secur32.dll fehlt');
  }
  final acquire = lib.lookupFunction<_AcquireC, _AcquireD>('AcquireCredentialsHandleW');
  final isc = lib.lookupFunction<_IscC, _IscD>('InitializeSecurityContextW');
  final freeBuf = lib.lookupFunction<_FreeBufC, _FreeBufD>('FreeContextBuffer');
  final delCtx = lib.lookupFunction<_HandleC, _HandleD>('DeleteSecurityContext');
  final freeCred = lib.lookupFunction<_HandleC, _HandleD>('FreeCredentialsHandle');

  return using((a) {
    final cred = a<_SecHandle>();
    final ctx = a<_SecHandle>();
    final ablauf = a<Int64>();
    final attr = a<Uint32>();
    final puffer = a<_SecBuffer>();
    puffer.ref
      ..cbBuffer = 0
      ..bufferType = _secbufferToken
      ..pvBuffer = nullptr;
    final aus = a<_SecBufferDesc>();
    aus.ref
      ..ulVersion = 0
      ..cBuffers = 1
      ..pBuffers = puffer;

    var s = acquire(nullptr, 'Negotiate'.toNativeUtf16(allocator: a), _secpkgCredOutbound, nullptr, nullptr, nullptr,
        nullptr, cred, ablauf);
    if (s != _secEOk) return (token: null, grund: 'AcquireCredentialsHandle 0x${s.toUnsigned(32).toRadixString(16)}');
    var mitKontext = false;
    try {
      s = isc(cred, nullptr, sspiZiel(dienst).toNativeUtf16(allocator: a), _iscReqAllocateMemory, 0, _securityNativeDrep,
          nullptr, 0, ctx, aus, attr, ablauf);
      if (s != _secEOk && s != _secIContinueNeeded) {
        return (token: null, grund: 'InitializeSecurityContext 0x${s.toUnsigned(32).toRadixString(16)}');
      }
      mitKontext = true;
      final t = Uint8List.fromList(puffer.ref.pvBuffer.cast<Uint8>().asTypedList(puffer.ref.cbBuffer));
      if (istNtlm(t)) return (token: null, grund: 'nur NTLM (kein Kerberos erreichbar)');
      return (token: t, grund: 'ok');
    } finally {
      if (puffer.ref.pvBuffer != nullptr) freeBuf(puffer.ref.pvBuffer);
      if (mitKontext) delCtx(ctx);
      freeCred(cred);
    }
  });
}
