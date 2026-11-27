// SPDX-License-Identifier: GPL-3.0-or-later
/// Links, die die App oeffnen (Plan: Deep-Links zwischen Apps): Android App
/// Links (`https://…` mit `autoVerify` und `/.well-known/assetlinks.json` auf
/// dem Web-Server), iOS Universal Links (braucht das Apple Developer Program
/// fuer die Team-ID – bis dahin oeffnet iOS die Web-Seite), Desktop: was das
/// System an die App gibt.
///
/// ```dart
/// AppVerweise.strom.listen((uri) => …);   // inkl. Link, mit dem die App startete
/// ```
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'protokoll.dart';

class AppVerweise {
  AppVerweise._();

  static Stream<Uri>? _strom;

  /// Fuer Tests: statt des Plugins.
  @visibleForTesting
  static Stream<Uri>? attrappe;

  /// Alle Links an die App, zuerst der, mit dem sie gestartet wurde. Einmal
  /// abonnieren (z. B. im State der Hauptseite).
  static Stream<Uri> get strom {
    final a = attrappe;
    if (a != null) return a;
    if (kIsWeb) return const Stream.empty();
    return _strom ??= AppLinks().uriLinkStream.handleError((Object e) => Protokoll.schreiben('Verweis', e)).asBroadcastStream();
  }
}
