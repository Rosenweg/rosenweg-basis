// SPDX-License-Identifier: GPL-3.0-or-later
// Windows-Registry nur mit dart:ffi; im Web gibt es keine.
export 'verwaltet_registry_ffi.dart' if (dart.library.js_interop) 'verwaltet_registry_web.dart';
