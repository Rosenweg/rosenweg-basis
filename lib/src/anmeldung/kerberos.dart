// SPDX-License-Identifier: GPL-3.0-or-later
// Web hat kein dart:ffi: dort gibt es kein Kerberos (die Website-Sitzung gilt).
export 'kerberos_ffi.dart' if (dart.library.js_interop) 'kerberos_web.dart';
