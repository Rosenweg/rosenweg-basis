// SPDX-License-Identifier: GPL-3.0-or-later
// Web-Version der Apps: die Anmeldung der Website (js/authentik-auth.js) gilt.
// Ausserhalb des Browsers gibt es das nicht (web_konto_stub.dart).
export 'web_konto_stub.dart' if (dart.library.js_interop) 'web_konto_web.dart';
