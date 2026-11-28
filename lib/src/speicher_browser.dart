// SPDX-License-Identifier: GPL-3.0-or-later
// Ablage fuer AppSpeicher im Browser (localStorage), sonst nie benutzt.
export 'speicher_browser_stub.dart' if (dart.library.js_interop) 'speicher_browser_web.dart';
