// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Client fuer [adresse]: `ws…` = WebSocket, sonst MQTT ueber TLS.
MqttClient mqttClientErzeugen(String adresse, String kennung, int port) {
  final c = MqttServerClient.withPort(adresse, kennung, port);
  if (adresse.startsWith('ws')) {
    c.useWebSocket = true;
    c.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  } else {
    c.secure = true;
  }
  return c;
}
