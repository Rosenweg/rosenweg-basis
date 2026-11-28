// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Gibt [bytes] im Browser als Datei aus: Download (Speichern-Dialog bzw.
/// Downloads-Ordner des Browsers) oder mit [imTab] in einem neuen Tab (PDF,
/// Bilder; faellt der Tab dem Popup-Blocker zum Opfer, dann Download).
/// true = ausgeloest.
bool browserDatei(String name, Uint8List bytes, String typ, {bool imTab = false}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: typ));
  final url = web.URL.createObjectURL(blob);
  try {
    if (imTab && web.window.open(url, '_blank') != null) return true;
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body!.append(a);
    a.click();
    a.remove();
    return true;
  } finally {
    // Der Tab bzw. Download hat die Daten zu diesem Zeitpunkt uebernommen
    Future<void>.delayed(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}
