#pragma once

#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>

#include "ConnectivityWatchdog.h"
#include "ScoreboardMqttCodec.h"
#include "ScoreboardProtocol.h"

namespace sportsos {

struct RuntimeConfig {
  const char* deviceId;
  const char* wifiSsid;
  const char* wifiPassword;
  const char* mqttHost;
  uint16_t mqttPort;
  const char* mqttUsername;
  const char* mqttPassword;
  uint32_t wifiRetryMs;
  uint32_t mqttRetryMs;
  uint32_t telemetryIntervalMs;
};

class ScoreboardRuntime {
 public:
  explicit ScoreboardRuntime(
      const RuntimeConfig& config);

  void begin();
  void loop();

  ScoreboardProtocol& protocol();
  const ScoreboardProtocol& protocol() const;

  bool displayStateIsStale() const;
  bool recoveryRequired() const;

 private:
  RuntimeConfig config_;

  WiFiClient wifiClient_;
  PubSubClient mqttClient_;
  ScoreboardProtocol protocol_;
  ConnectivityWatchdog watchdog_;

  unsigned long lastWifiAttemptMs_;
  unsigned long lastMqttAttemptMs_;
  unsigned long lastLoopMs_;
  unsigned long lastTelemetryMs_;

  char commandTopic_[128];
  char ackTopic_[128];
  char stateTopic_[128];
  char telemetryTopic_[128];
  char presenceTopic_[128];

  void buildTopics();

  void maintainWifi(
      unsigned long nowMs);

  void maintainMqtt(
      unsigned long nowMs);

  bool connectMqtt();

  void onMqttMessage(
      char* topic,
      uint8_t* payload,
      unsigned int length);

  void handleCommandJson(
      const char* json);

  void publishAcknowledgement(
      const char* commandId,
      CommandStatus status,
      const char* message);

  void publishState();

  void publishPresence(
      bool online);

  void publishTelemetry();

  const char* timestampNow(
      char* buffer,
      size_t bufferSize) const;

  static ScoreboardRuntime* activeInstance_;

  static void mqttCallback(
      char* topic,
      uint8_t* payload,
      unsigned int length);
};

}  // namespace sportsos
