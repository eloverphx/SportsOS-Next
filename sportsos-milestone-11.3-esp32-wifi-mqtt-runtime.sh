#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.3-esp32-wifi-mqtt-runtime"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/packages/core" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardProtocol.h" \
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardMqttCodec.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ScoreboardRuntime.h"
SOURCE="$FW_DIR/src/ScoreboardRuntime.cpp"
MAIN="$FW_DIR/src/main.cpp"
PLATFORMIO="$FW_DIR/platformio.ini"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-wifi-mqtt-runtime-11.3.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$HEADER")" \
  "$BACKUP_DIR/$(dirname "$SOURCE")" \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$PLATFORMIO")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$HEADER")" \
  "$(dirname "$SOURCE")" \
  "$(dirname "$MAIN")" \
  "$(dirname "$TEST")"

for file in "$HEADER" "$SOURCE" "$MAIN" "$PLATFORMIO" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>

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

 private:
  RuntimeConfig config_;

  WiFiClient wifiClient_;
  PubSubClient mqttClient_;
  ScoreboardProtocol protocol_;

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
EOF

cat > "$SOURCE" <<'EOF'
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
EOF

cat > "$MAIN" <<'EOF'
#include <Arduino.h>

#include "ScoreboardRuntime.h"

using sportsos::RuntimeConfig;
using sportsos::ScoreboardRuntime;

/*
 * Milestone 11.3 intentionally uses build-time placeholders.
 *
 * Do not commit real Wi-Fi or MQTT credentials.
 * Later provisioning milestones will replace this with a
 * local configuration/provisioning workflow.
 */
#ifndef SPORTSOS_DEVICE_ID
#define SPORTSOS_DEVICE_ID "scoreboard-esp32-1"
#endif

#ifndef SPORTSOS_WIFI_SSID
#define SPORTSOS_WIFI_SSID ""
#endif

#ifndef SPORTSOS_WIFI_PASSWORD
#define SPORTSOS_WIFI_PASSWORD ""
#endif

#ifndef SPORTSOS_MQTT_HOST
#define SPORTSOS_MQTT_HOST "192.168.5.3"
#endif

#ifndef SPORTSOS_MQTT_PORT
#define SPORTSOS_MQTT_PORT 4012
#endif

RuntimeConfig config{
    SPORTSOS_DEVICE_ID,
    SPORTSOS_WIFI_SSID,
    SPORTSOS_WIFI_PASSWORD,
    SPORTSOS_MQTT_HOST,
    SPORTSOS_MQTT_PORT,
    "",
    "",
    5000,
    3000,
    30000,
};

ScoreboardRuntime runtime(
    config);

void setup() {
  Serial.begin(
      115200);

  runtime.begin();
}

void loop() {
  runtime.loop();

  delay(5);
}
EOF

cat > "$PLATFORMIO" <<'EOF'
[platformio]
default_envs = esp32dev

[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200

lib_deps =
  bblanchon/ArduinoJson@^7.2.1
  knolleary/PubSubClient@^2.8

build_flags =
  -D SPORTSOS_FIRMWARE_VERSION=\"0.11.3\"

; Development-only examples.
; Do NOT commit real credentials.
; -D SPORTSOS_DEVICE_ID=\"scoreboard-esp32-1\"
; -D SPORTSOS_WIFI_SSID=\"your-ssid\"
; -D SPORTSOS_WIFI_PASSWORD=\"your-password\"
; -D SPORTSOS_MQTT_HOST=\"192.168.5.3\"
; -D SPORTSOS_MQTT_PORT=4012
EOF

cat >> "$README" <<'EOF'

## Milestone 11.3 — Wi-Fi / MQTT runtime

The ESP32 firmware now includes the device runtime responsible for connectivity and MQTT transport.

### Runtime responsibilities

- connect and reconnect Wi-Fi
- connect and reconnect MQTT
- subscribe to the per-device command topic
- publish retained online/offline presence
- publish retained device state
- publish command acknowledgements
- publish periodic telemetry
- apply SportsOS commands through the Milestone 11.1 protocol core
- re-publish authoritative device state after an applied command

### MQTT topics

For device `<deviceId>`:

- `sportsos/scoreboards/<deviceId>/command`
- `sportsos/scoreboards/<deviceId>/ack`
- `sportsos/scoreboards/<deviceId>/state`
- `sportsos/scoreboards/<deviceId>/telemetry`
- `sportsos/scoreboards/<deviceId>/presence`

### Credentials

Real Wi-Fi and MQTT credentials must not be committed to source control.

Milestone 11.3 uses build-time configuration placeholders only. A later provisioning milestone will provide a local configuration workflow suitable for deployed scoreboard hardware.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.3 ESP32 Wi-Fi / MQTT runtime", () => {
  it("defines all Milestone 10 MQTT topics", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const suffix of [
      "command",
      "ack",
      "state",
      "telemetry",
      "presence",
    ]) {
      expect(source).toContain(
        `"${suffix}"`,
      );
    }

    expect(source).toContain(
      "sportsos/scoreboards/%s/%s",
    );
  });

  it("implements Wi-Fi and MQTT reconnect loops", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "maintainWifi",
    );
    expect(source).toContain(
      "maintainMqtt",
    );
    expect(source).toContain(
      "WiFi.begin",
    );
    expect(source).toContain(
      "connectMqtt",
    );
  });

  it("publishes retained presence and state", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "presenceTopic_",
    );
    expect(source).toContain(
      "stateTopic_",
    );
    expect(source).toContain(
      "publishPresence",
    );
    expect(source).toContain(
      "publishState",
    );
    expect(source).toMatch(
      /mqttClient_\.publish\([\s\S]*stateTopic_[\s\S]*true\)/,
    );
  });

  it("publishes ACCEPTED before applying a valid command", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    const accepted =
      source.indexOf(
        "CommandStatus::Accepted",
      );

    const apply =
      source.indexOf(
        "protocol_.apply",
      );

    expect(accepted).toBeGreaterThan(
      -1,
    );
    expect(apply).toBeGreaterThan(
      accepted,
    );
  });

  it("uses PubSubClient through PlatformIO", () => {
    const platformio =
      fs.readFileSync(
        new URL(
          "../../../firmware/esp32-scoreboard/platformio.ini",
          import.meta.url,
        ),
        "utf8",
      );

    expect(platformio).toContain(
      "knolleary/PubSubClient",
    );
  });

  it("does not commit real Wi-Fi credentials", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      '#define SPORTSOS_WIFI_SSID ""',
    );
    expect(main).toContain(
      '#define SPORTSOS_WIFI_PASSWORD ""',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.3 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - Milestones 11.1 and 11.2 prerequisites verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - ScoreboardRuntime.h/.cpp"
echo "  - ESP32 Wi-Fi reconnect loop"
echo "  - MQTT reconnect loop"
echo "  - per-device MQTT topic construction"
echo "  - retained presence + state publishing"
echo "  - command subscription + acknowledgement flow"
echo "  - telemetry publication"
echo "  - firmware main.cpp bootstrap"
echo "  - PubSubClient dependency"
echo "  - no committed Wi-Fi credentials"
echo "  - Milestone 11.3 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "PlatformIO:"
echo "  Not required for this milestone's repository validation."
echo
echo "Next after green:"
echo "  Milestone 11.4 - ESP32 Local Provisioning / Configuration"
