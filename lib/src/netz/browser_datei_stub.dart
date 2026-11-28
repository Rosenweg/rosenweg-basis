// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

/// Nur im Browser (browser_datei_web.dart); sonst nie gerufen.
bool browserDatei(String name, Uint8List bytes, String typ, {bool imTab = false}) =>
    throw UnsupportedError('Nur im Browser');
