// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// Browser: nur WebSocket. [adresse] muss mit `ws` beginnen (wss://…).
MqttClient mqttClientErzeugen(String adresse, String kennung, int port) {
  final c = MqttBrowserClient.withPort(adresse, kennung, port);
  c.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return c;
}
