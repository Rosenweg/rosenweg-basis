// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Wert [wert] unter HKLM\[unterschluessel] ist 1 (DWORD oder Text)?
/// 64-Bit-Ansicht der Registry, wie GPO sie schreibt.
bool registrySchalter(String unterschluessel, String wert) {
  final advapi = DynamicLibrary.open('advapi32.dll');
  final regGetValue = advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>)>('RegGetValueW');
  const hklm = -0x7FFFFFFE; // (HKEY)(LONG)0x80000002, vorzeichenerweitert
  const rrfRtRegDword = 0x10, rrfRtRegSz = 0x02, rrfSubkeyWow6464 = 0x10000;
  const regSz = 1, regDword = 4;
  return using((arena) {
    final s = unterschluessel.toNativeUtf16(allocator: arena);
    final w = wert.toNativeUtf16(allocator: arena);
    final typ = arena<Uint32>();
    final groesse = arena<Uint32>()..value = 512;
    final daten = arena<Uint8>(512);
    final r = regGetValue(hklm, s, w, rrfRtRegDword | rrfRtRegSz | rrfSubkeyWow6464, typ, daten.cast(), groesse);
    if (r != 0) return false;
    if (typ.value == regDword) return daten.cast<Uint32>().value == 1;
    if (typ.value == regSz) return daten.cast<Utf16>().toDartString().trim() == '1';
    return false;
  });
}
