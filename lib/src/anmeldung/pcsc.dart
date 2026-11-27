// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Kleinster Teil von PC/SC (Smartcard-Schnittstelle der Systeme) fuer
/// USB-NFC-Leser am Computer (z. B. ACR122U, ACR1252U, Identiv uTrust):
/// Leser auflisten, Karte verbinden, UID lesen (`FF CA 00 00 00`, PC/SC
/// Teil 3 - die Leser beantworten das selbst, ohne die Karte zu fragen).
///
///   Linux   libpcsclite.so.1 (Paket pcscd + libpcsclite1)
///   macOS   PCSC.framework (immer da; eine App mit Sandbox braucht
///           com.apple.security.smartcard)
///   Windows winscard.dll (Dienst "Smartcard")
///
/// Die Typen unterscheiden sich: pcsclite auf Linux nimmt `long` (64 Bit),
/// Apple feste 32 Bit, Windows 32 Bit mit Zeiger-grossem Kontext. Darum zwei
/// Bindungen. Alles blockiert nur kurz (Verbinden ohne Karte kehrt sofort
/// zurueck), darum ohne eigenen Isolate.
abstract class Pcsc {
  /// null = keine PC/SC-Bibliothek oder kein Dienst (dann gibt es keinen Leser).
  static Pcsc? oeffnen() {
    try {
      if (Platform.isMacOS) return _Pcsc32._(DynamicLibrary.open('/System/Library/Frameworks/PCSC.framework/PCSC'));
      if (Platform.isLinux) return _PcscLang._(DynamicLibrary.open('libpcsclite.so.1'), ansi: false);
      if (Platform.isWindows) return _PcscLang._(DynamicLibrary.open('winscard.dll'), ansi: true);
    } catch (_) {}
    return null;
  }

  /// Namen der angeschlossenen Leser (leer = keiner).
  List<String> leser();

  /// UID der Karte auf [leser] als Hex, null = keine Karte.
  String? uid(String leser);

  void schliessen();

  static const _erfolg = 0;
  static const _shareShared = 2;
  static const _t0t1 = 3;
  static const _leaveCard = 0;
  static final _uidApdu = Uint8List.fromList([0xFF, 0xCA, 0x00, 0x00, 0x00]);

  static List<String> _namen(Pointer<Uint8> p, int laenge) {
    final b = p.asTypedList(laenge);
    final namen = <String>[];
    var start = 0;
    for (var i = 0; i < b.length; i++) {
      if (b[i] == 0) {
        if (i > start) namen.add(String.fromCharCodes(b.sublist(start, i)));
        start = i + 1;
      }
    }
    return namen;
  }

  static String? _hex(Uint8List antwort) {
    // Antwort: UID + 90 00
    if (antwort.length < 6 || antwort[antwort.length - 2] != 0x90 || antwort[antwort.length - 1] != 0x00) return null;
    return antwort.sublist(0, antwort.length - 2).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }
}

// ── Linux (long = 64 Bit) und Windows (long = 32 Bit, Kontext zeigergross) ──
// dart:ffi Long/UnsignedLong passen sich an; SCARDCONTEXT/SCARDHANDLE sind
// auf beiden zeigergross (Linux LONG = 64 Bit = IntPtr).

typedef _EstablishL = Long Function(UnsignedLong, Pointer<Void>, Pointer<Void>, Pointer<IntPtr>);
typedef _EstablishD = int Function(int, Pointer<Void>, Pointer<Void>, Pointer<IntPtr>);
typedef _ListL = Long Function(IntPtr, Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLong>);
typedef _ListD = int Function(int, Pointer<Uint8>, Pointer<Uint8>, Pointer<UnsignedLong>);
typedef _ConnectL = Long Function(IntPtr, Pointer<Uint8>, UnsignedLong, UnsignedLong, Pointer<IntPtr>, Pointer<UnsignedLong>);
typedef _ConnectD = int Function(int, Pointer<Uint8>, int, int, Pointer<IntPtr>, Pointer<UnsignedLong>);
typedef _TransmitL = Long Function(IntPtr, Pointer<Void>, Pointer<Uint8>, UnsignedLong, Pointer<Void>, Pointer<Uint8>, Pointer<UnsignedLong>);
typedef _TransmitD = int Function(int, Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, Pointer<Uint8>, Pointer<UnsignedLong>);
typedef _HandleL = Long Function(IntPtr, UnsignedLong);
typedef _HandleD = int Function(int, int);
typedef _ReleaseL = Long Function(IntPtr);
typedef _ReleaseD = int Function(int);

class _PcscLang extends Pcsc {
  _PcscLang._(DynamicLibrary l, {required bool ansi})
      : _list = l.lookupFunction<_ListL, _ListD>(ansi ? 'SCardListReadersA' : 'SCardListReaders'),
        _connect = l.lookupFunction<_ConnectL, _ConnectD>(ansi ? 'SCardConnectA' : 'SCardConnect'),
        _transmit = l.lookupFunction<_TransmitL, _TransmitD>('SCardTransmit'),
        _disconnect = l.lookupFunction<_HandleL, _HandleD>('SCardDisconnect'),
        _release = l.lookupFunction<_ReleaseL, _ReleaseD>('SCardReleaseContext') {
    final establish = l.lookupFunction<_EstablishL, _EstablishD>('SCardEstablishContext');
    final p = calloc<IntPtr>();
    try {
      if (establish(0 /* SCARD_SCOPE_USER */, nullptr, nullptr, p) & 0xFFFFFFFF != Pcsc._erfolg) {
        throw StateError('PC/SC-Dienst nicht erreichbar');
      }
      _kontext = p.value;
    } finally {
      calloc.free(p);
    }
  }

  final _ListD _list;
  final _ConnectD _connect;
  final _TransmitD _transmit;
  final _HandleD _disconnect;
  final _ReleaseD _release;
  late final int _kontext;

  @override
  List<String> leser() {
    final n = calloc<UnsignedLong>();
    try {
      if (_list(_kontext, nullptr, nullptr, n) & 0xFFFFFFFF != Pcsc._erfolg || n.value == 0) return const [];
      final puffer = calloc<Uint8>(n.value);
      try {
        if (_list(_kontext, nullptr, puffer, n) & 0xFFFFFFFF != Pcsc._erfolg) return const [];
        return Pcsc._namen(puffer, n.value);
      } finally {
        calloc.free(puffer);
      }
    } finally {
      calloc.free(n);
    }
  }

  @override
  String? uid(String leser) {
    final name = leser.toNativeUtf8().cast<Uint8>();
    final karte = calloc<IntPtr>();
    final protokoll = calloc<UnsignedLong>();
    try {
      if (_connect(_kontext, name, Pcsc._shareShared, Pcsc._t0t1, karte, protokoll) & 0xFFFFFFFF != Pcsc._erfolg) return null;
      try {
        // SCARD_IO_REQUEST {dwProtocol, cbPciLength}, je ein unsigned long
        final pci = calloc<UnsignedLong>(2);
        final senden = calloc<Uint8>(5);
        final empfang = calloc<Uint8>(64);
        final laenge = calloc<UnsignedLong>();
        try {
          pci[0] = protokoll.value;
          pci[1] = 2 * sizeOf<UnsignedLong>();
          senden.asTypedList(5).setAll(0, Pcsc._uidApdu);
          laenge.value = 64;
          if (_transmit(karte.value, pci.cast(), senden, 5, nullptr, empfang, laenge) & 0xFFFFFFFF != Pcsc._erfolg) return null;
          return Pcsc._hex(Uint8List.fromList(empfang.asTypedList(laenge.value)));
        } finally {
          calloc.free(pci);
          calloc.free(senden);
          calloc.free(empfang);
          calloc.free(laenge);
        }
      } finally {
        _disconnect(karte.value, Pcsc._leaveCard);
      }
    } finally {
      calloc.free(name);
      calloc.free(karte);
      calloc.free(protokoll);
    }
  }

  @override
  void schliessen() => _release(_kontext);
}

// ── macOS: DWORD, LONG und SCARDCONTEXT sind 32 Bit ──

typedef _EstablishM = Int32 Function(Uint32, Pointer<Void>, Pointer<Void>, Pointer<Int32>);
typedef _EstablishMD = int Function(int, Pointer<Void>, Pointer<Void>, Pointer<Int32>);
typedef _ListM = Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint32>);
typedef _ListMD = int Function(int, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint32>);
typedef _ConnectM = Int32 Function(Int32, Pointer<Uint8>, Uint32, Uint32, Pointer<Int32>, Pointer<Uint32>);
typedef _ConnectMD = int Function(int, Pointer<Uint8>, int, int, Pointer<Int32>, Pointer<Uint32>);
typedef _TransmitM = Int32 Function(Int32, Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Void>, Pointer<Uint8>, Pointer<Uint32>);
typedef _TransmitMD = int Function(int, Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, Pointer<Uint8>, Pointer<Uint32>);
typedef _HandleM = Int32 Function(Int32, Uint32);
typedef _HandleMD = int Function(int, int);
typedef _ReleaseM = Int32 Function(Int32);
typedef _ReleaseMD = int Function(int);

class _Pcsc32 extends Pcsc {
  _Pcsc32._(DynamicLibrary l)
      : _list = l.lookupFunction<_ListM, _ListMD>('SCardListReaders'),
        _connect = l.lookupFunction<_ConnectM, _ConnectMD>('SCardConnect'),
        _transmit = l.lookupFunction<_TransmitM, _TransmitMD>('SCardTransmit'),
        _disconnect = l.lookupFunction<_HandleM, _HandleMD>('SCardDisconnect'),
        _release = l.lookupFunction<_ReleaseM, _ReleaseMD>('SCardReleaseContext') {
    final establish = l.lookupFunction<_EstablishM, _EstablishMD>('SCardEstablishContext');
    final p = calloc<Int32>();
    try {
      if (establish(0, nullptr, nullptr, p) & 0xFFFFFFFF != Pcsc._erfolg) throw StateError('PC/SC-Dienst nicht erreichbar');
      _kontext = p.value;
    } finally {
      calloc.free(p);
    }
  }

  final _ListMD _list;
  final _ConnectMD _connect;
  final _TransmitMD _transmit;
  final _HandleMD _disconnect;
  final _ReleaseMD _release;
  late final int _kontext;

  @override
  List<String> leser() {
    final n = calloc<Uint32>();
    try {
      if (_list(_kontext, nullptr, nullptr, n) & 0xFFFFFFFF != Pcsc._erfolg || n.value == 0) return const [];
      final puffer = calloc<Uint8>(n.value);
      try {
        if (_list(_kontext, nullptr, puffer, n) & 0xFFFFFFFF != Pcsc._erfolg) return const [];
        return Pcsc._namen(puffer, n.value);
      } finally {
        calloc.free(puffer);
      }
    } finally {
      calloc.free(n);
    }
  }

  @override
  String? uid(String leser) {
    final name = leser.toNativeUtf8().cast<Uint8>();
    final karte = calloc<Int32>();
    final protokoll = calloc<Uint32>();
    try {
      if (_connect(_kontext, name, Pcsc._shareShared, Pcsc._t0t1, karte, protokoll) & 0xFFFFFFFF != Pcsc._erfolg) return null;
      try {
        final pci = calloc<Uint32>(2);
        final senden = calloc<Uint8>(5);
        final empfang = calloc<Uint8>(64);
        final laenge = calloc<Uint32>();
        try {
          pci[0] = protokoll.value;
          pci[1] = 8;
          senden.asTypedList(5).setAll(0, Pcsc._uidApdu);
          laenge.value = 64;
          if (_transmit(karte.value, pci.cast(), senden, 5, nullptr, empfang, laenge) & 0xFFFFFFFF != Pcsc._erfolg) return null;
          return Pcsc._hex(Uint8List.fromList(empfang.asTypedList(laenge.value)));
        } finally {
          calloc.free(pci);
          calloc.free(senden);
          calloc.free(empfang);
          calloc.free(laenge);
        }
      } finally {
        _disconnect(karte.value, Pcsc._leaveCard);
      }
    } finally {
      calloc.free(name);
      calloc.free(karte);
      calloc.free(protokoll);
    }
  }

  @override
  void schliessen() => _release(_kontext);
}
