// SPDX-License-Identifier: GPL-3.0-or-later
// Web hat kein dart:ffi: dort gibt es keine USB-Kartenleser (PC/SC).
export 'pcsc_ffi.dart' if (dart.library.js_interop) 'pcsc_web.dart';
