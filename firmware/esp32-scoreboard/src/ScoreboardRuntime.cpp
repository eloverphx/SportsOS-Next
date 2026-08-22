#include "ScoreboardRuntime.h"

#include <stdio.h>
#include <string.h>

namespace sportsos {

ScoreboardRuntime*
ScoreboardRuntime::activeInstance_ =
    nullptr;

namespace {

constexpr size_t JSON_BUFFER_SIZE =
    1024;

void buildTopic(
    char* output,
    size_t outputSize,
    const char* deviceId,
    const char* suffix) {
  snprintf(
      output,
      outputSize,
      "sportsos/scoreboards/%s/%s",
      deviceId,
      suffix);
}

}  // namespace

ScoreboardRuntime::ScoreboardRuntime(
    const RuntimeConfig& config)
    : config_(config),
      mqttClient_(wifiClient_),
      protocol_(config.deviceId),
      watchdog_(ConnectivityWatchdogConfig{
          15000,
          15000,
          120000,
          60000,
      }),
      lastWifiAttemptMs_(0),
      lastMqttAttemptMs_(0),
      lastLoopMs_(0),
      lastTelemetryMs_(0) {
  memset(
      commandTopic_,
      0,
      sizeof(commandTopic_));
  memset(
      ackTopic_,
      0,
      sizeof(ackTopic_));
  memset(
      stateTopic_,
      0,
      sizeof(stateTopic_));
  memset(
      telemetryTopic_,
      0,
      sizeof(telemetryTopic_));
  memset(
      presenceTopic_,
      0,
      sizeof(presenceTopic_));
}

void ScoreboardRuntime::begin() {
  activeInstance_ = this;

  watchdog_.begin(
      millis());

  buildTopics();

  protocol_.setConnectionState(
      ConnectionState::Connecting);

  WiFi.mode(
      WIFI_STA);

  mqttClient_.setServer(
      config_.mqttHost,
      config_.mqttPort);

  mqttClient_.setCallback(
      ScoreboardRuntime::mqttCallback);

  mqttClient_.setBufferSize(
      JSON_BUFFER_SIZE);

  maintainWifi(
      millis());
}

void ScoreboardRuntime::loop() {
  const unsigned long nowMs =
      millis();

  const unsigned long elapsedMs =
      nowMs - lastLoopMs_;

  lastLoopMs_ =
      nowMs;

  protocol_.tick(
      elapsedMs);

  maintainWifi(
      nowMs);

  maintainMqtt(
      nowMs);

  watchdog_.evaluate(
      nowMs,
      WiFi.status() == WL_CONNECTED,
      mqttClient_.connected());

  if (mqttClient_.connected()) {
    mqttClient_.loop();

    if (
        nowMs - lastTelemetryMs_ >=
        config_.telemetryIntervalMs
    ) {
      publishTelemetry();
      lastTelemetryMs_ =
          nowMs;
    }
  }
}

ScoreboardProtocol&
ScoreboardRuntime::protocol() {
  return protocol_;
}

const ScoreboardProtocol&
ScoreboardRuntime::protocol() const {
  return protocol_;
}

bool ScoreboardRuntime::displayStateIsStale() const {
  return watchdog_.displayStateIsStale();
}

bool ScoreboardRuntime::recoveryRequired() const {
  return watchdog_.recoveryRequired();
}

void ScoreboardRuntime::buildTopics() {
  buildTopic(
      commandTopic_,
      sizeof(commandTopic_),
      config_.deviceId,
      "command");

  buildTopic(
      ackTopic_,
      sizeof(ackTopic_),
      config_.deviceId,
      "ack");

  buildTopic(
      stateTopic_,
      sizeof(stateTopic_),
      config_.deviceId,
      "state");

  buildTopic(
      telemetryTopic_,
      sizeof(telemetryTopic_),
      config_.deviceId,
      "telemetry");

  buildTopic(
      presenceTopic_,
      sizeof(presenceTopic_),
      config_.deviceId,
      "presence");
}

void ScoreboardRuntime::maintainWifi(
    unsigned long nowMs) {
  if (
      WiFi.status() ==
      WL_CONNECTED
  ) {
    watchdog_.noteSuccessfulWifiConnect(
        nowMs);
    return;
  }

  protocol_.setConnectionState(
      ConnectionState::Connecting);

  if (
      nowMs - lastWifiAttemptMs_ <
      config_.wifiRetryMs
  ) {
    return;
  }

  lastWifiAttemptMs_ =
      nowMs;

  WiFi.disconnect();
  WiFi.begin(
      config_.wifiSsid,
      config_.wifiPassword);
}

void ScoreboardRuntime::maintainMqtt(
    unsigned long nowMs) {
  if (
      WiFi.status() !=
      WL_CONNECTED
  ) {
    if (mqttClient_.connected()) {
      mqttClient_.disconnect();
    }

    protocol_.setConnectionState(
        ConnectionState::Offline);

    return;
  }

  if (mqttClient_.connected()) {
    protocol_.setConnectionState(
        ConnectionState::Online);
    return;
  }

  if (
      nowMs - lastMqttAttemptMs_ <
      config_.mqttRetryMs
  ) {
    return;
  }

  lastMqttAttemptMs_ =
      nowMs;

  protocol_.setConnectionState(
      ConnectionState::Connecting);

  if (!connectMqtt()) {
    protocol_.setConnectionState(
        ConnectionState::Degraded);
  }
}

bool ScoreboardRuntime::connectMqtt() {
  char offlinePayload[160] = {};
  char reportedAt[40] = {};

  MqttPresence offlinePresence{};
  offlinePresence.online = false;

  timestampNow(
      reportedAt,
      sizeof(reportedAt));

  strncpy(
      offlinePresence.reportedAt,
      reportedAt,
      sizeof(
          offlinePresence.reportedAt) - 1);

  ScoreboardMqttCodec::encodePresence(
      offlinePresence,
      offlinePayload,
      sizeof(offlinePayload));

  bool connected = false;

  const bool hasCredentials =
      config_.mqttUsername != nullptr &&
      config_.mqttUsername[0] != '\0';

  if (hasCredentials) {
    connected =
        mqttClient_.connect(
            config_.deviceId,
            config_.mqttUsername,
            config_.mqttPassword,
            presenceTopic_,
            1,
            true,
            offlinePayload);
  } else {
    connected =
        mqttClient_.connect(
            config_.deviceId,
            presenceTopic_,
            1,
            true,
            offlinePayload);
  }

  if (!connected) {
    return false;
  }

  mqttClient_.subscribe(
      commandTopic_,
      1);

  publishPresence(
      true);

  publishState();

  watchdog_.noteSuccessfulMqttConnect(
      millis());

  protocol_.setConnectionState(
      ConnectionState::Online);

  return true;
}

void ScoreboardRuntime::mqttCallback(
    char* topic,
    uint8_t* payload,
    unsigned int length) {
  if (activeInstance_ == nullptr) {
    return;
  }

  activeInstance_
      ->onMqttMessage(
          topic,
          payload,
          length);
}

void ScoreboardRuntime::onMqttMessage(
    char* topic,
    uint8_t* payload,
    unsigned int length) {
  if (
      strcmp(
          topic,
          commandTopic_) != 0
  ) {
    return;
  }

  if (
      length == 0 ||
      length >= JSON_BUFFER_SIZE
  ) {
    return;
  }

  char json[JSON_BUFFER_SIZE] = {};

  memcpy(
      json,
      payload,
      length);

  json[length] = '\0';

  handleCommandJson(
      json);
}

void ScoreboardRuntime::handleCommandJson(
    const char* json) {
  ParsedCommand command{};
  char error[128] = {};

  if (
      !ScoreboardMqttCodec::parseCommand(
          json,
          command,
          error,
          sizeof(error))
  ) {
    publishAcknowledgement(
        command.commandId,
        CommandStatus::Rejected,
        error);
    return;
  }

  publishAcknowledgement(
      command.commandId,
      CommandStatus::Accepted,
      nullptr);

  const CommandResult result =
      protocol_.apply(
          command);

  publishAcknowledgement(
      command.commandId,
      result.status,
      result.message);

  if (
      result.status ==
      CommandStatus::Applied
  ) {
    watchdog_.noteAuthoritativeState(
        millis());
    publishState();
  }
}

void ScoreboardRuntime::publishAcknowledgement(
    const char* commandId,
    CommandStatus status,
    const char* message) {
  if (!mqttClient_.connected()) {
    return;
  }

  MqttAcknowledgement acknowledgement{};

  strncpy(
      acknowledgement.commandId,
      commandId != nullptr
          ? commandId
          : "",
      sizeof(
          acknowledgement.commandId) - 1);

  acknowledgement.status =
      status;

  strncpy(
      acknowledgement.message,
      message != nullptr
          ? message
          : "",
      sizeof(
          acknowledgement.message) - 1);

  timestampNow(
      acknowledgement.acknowledgedAt,
      sizeof(
          acknowledgement.acknowledgedAt));

  char json[384] = {};

  if (
      ScoreboardMqttCodec
          ::encodeAcknowledgement(
              acknowledgement,
              json,
              sizeof(json))
  ) {
    mqttClient_.publish(
        ackTopic_,
        json,
        false);
  }
}

void ScoreboardRuntime::publishState() {
  if (!mqttClient_.connected()) {
    return;
  }

  char updatedAt[40] = {};

  timestampNow(
      updatedAt,
      sizeof(updatedAt));

  char json[768] = {};

  if (
      ScoreboardMqttCodec::encodeState(
          protocol_.state(),
          updatedAt,
          json,
          sizeof(json))
  ) {
    mqttClient_.publish(
        stateTopic_,
        json,
        true);
  }
}

void ScoreboardRuntime::publishPresence(
    bool online) {
  if (!mqttClient_.connected()) {
    return;
  }

  MqttPresence presence{};
  presence.online =
      online;

  timestampNow(
      presence.reportedAt,
      sizeof(
          presence.reportedAt));

  char json[160] = {};

  if (
      ScoreboardMqttCodec::encodePresence(
          presence,
          json,
          sizeof(json))
  ) {
    mqttClient_.publish(
        presenceTopic_,
        json,
        true);
  }
}

void ScoreboardRuntime::publishTelemetry() {
  if (!mqttClient_.connected()) {
    return;
  }

  MqttTelemetry telemetry{};

  strncpy(
      telemetry.firmwareVersion,
      SPORTSOS_FIRMWARE_VERSION,
      sizeof(
          telemetry.firmwareVersion) - 1);

  const String ip =
      WiFi.localIP().toString();

  strncpy(
      telemetry.ipAddress,
      ip.c_str(),
      sizeof(
          telemetry.ipAddress) - 1);

  telemetry.wifiRssi =
      WiFi.RSSI();

  telemetry.uptimeSeconds =
      millis() / 1000UL;

  telemetry.freeHeapBytes =
      ESP.getFreeHeap();

  timestampNow(
      telemetry.reportedAt,
      sizeof(
          telemetry.reportedAt));

  char json[384] = {};

  if (
      ScoreboardMqttCodec::encodeTelemetry(
          telemetry,
          json,
          sizeof(json))
  ) {
    mqttClient_.publish(
        telemetryTopic_,
        json,
        false);
  }
}

const char* ScoreboardRuntime::timestampNow(
    char* buffer,
    size_t bufferSize) const {
  if (
      buffer == nullptr ||
      bufferSize == 0
  ) {
    return "";
  }

  snprintf(
      buffer,
      bufferSize,
      "uptime:%lu",
      millis());

  return buffer;
}

}  // namespace sportsos
