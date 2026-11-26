// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/services.dart';

/// Geteilte Telefone: Rosenweg Geraet meldet, wenn sich am Telefon jemand an-
/// oder abmeldet (android/…/GeraetPerson.kt, nur Broadcasts von Rosenweg-Apps).
/// Ereignisse: `angemeldet` | `abgemeldet`. Ohne Android: kein Ereignis.
class GeraetPerson {
  GeraetPerson._();

  static const kanal = EventChannel('ch.rosenweg4303.basis/person');

  static Stream<String> get wechsel => kanal
      .receiveBroadcastStream()
      .where((e) => e is String)
      .cast<String>()
      .handleError((Object _) {}, test: (e) => e is MissingPluginException);
}
