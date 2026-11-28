// SPDX-License-Identifier: GPL-3.0-or-later
// Der MQTT-Client haengt an der Plattform: Dart-Sockets (dart:io) auf
// Telefon und Desktop, im Browser nur WebSocket (MqttBrowserClient).
export 'mqtt_fabrik_io.dart' if (dart.library.js_interop) 'mqtt_fabrik_web.dart';
