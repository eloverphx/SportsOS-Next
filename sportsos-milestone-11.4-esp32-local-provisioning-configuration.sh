#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="11.4-esp32-local-provisioning-configuration"
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
  "$ROOT/firmware/esp32-scoreboard/include/ScoreboardRuntime.h" \
  "$ROOT/firmware/esp32-scoreboard/src/ScoreboardRuntime.cpp" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

FW_DIR="firmware/esp32-scoreboard"
HEADER="$FW_DIR/include/ProvisioningManager.h"
SOURCE="$FW_DIR/src/ProvisioningManager.cpp"
MAIN="$FW_DIR/src/main.cpp"
README="$FW_DIR/README.md"
TEST="packages/core/test/esp32-local-provisioning-11.4.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$HEADER")" \
  "$BACKUP_DIR/$(dirname "$SOURCE")" \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$README")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$HEADER")" \
  "$(dirname "$SOURCE")" \
  "$(dirname "$TEST")"

for file in "$HEADER" "$SOURCE" "$MAIN" "$README" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$HEADER" <<'EOF'
#pragma once

#include <Arduino.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>

namespace sportsos {

struct PersistedRuntimeConfig {
  String deviceId;
  String wifiSsid;
  String wifiPassword;
  String mqttHost;
  uint16_t mqttPort;
  String mqttUsername;
  String mqttPassword;
};

class ProvisioningManager {
 public:
  ProvisioningManager();

  bool begin();
  void loop();

  bool hasValidConfig() const;
  const PersistedRuntimeConfig& config() const;

  bool startProvisioningPortal();
  void stopProvisioningPortal();

  bool provisioningActive() const;

  void clearConfiguration();

 private:
  Preferences preferences_;
  WebServer server_;
  PersistedRuntimeConfig config_;
  bool provisioningActive_;

  bool loadConfiguration();
  bool saveConfiguration(
      const PersistedRuntimeConfig& config);

  void configureRoutes();

  void handleRoot();
  void handleSave();
  void handleStatus();
  void handleReset();

  String htmlEscape(
      const String& value) const;

  String provisioningSsid() const;

  static bool validDeviceId(
      const String& deviceId);

  static bool validMqttHost(
      const String& mqttHost);
};

}  // namespace sportsos
EOF

cat > "$SOURCE" <<'EOF'
#include "ProvisioningManager.h"

namespace sportsos {

namespace {

constexpr const char* PREF_NAMESPACE =
    "sportsos";

constexpr const char* KEY_DEVICE_ID =
    "deviceId";

constexpr const char* KEY_WIFI_SSID =
    "wifiSsid";

constexpr const char* KEY_WIFI_PASSWORD =
    "wifiPass";

constexpr const char* KEY_MQTT_HOST =
    "mqttHost";

constexpr const char* KEY_MQTT_PORT =
    "mqttPort";

constexpr const char* KEY_MQTT_USERNAME =
    "mqttUser";

constexpr const char* KEY_MQTT_PASSWORD =
    "mqttPass";

}  // namespace

ProvisioningManager::ProvisioningManager()
    : server_(80),
      provisioningActive_(false) {}

bool ProvisioningManager::begin() {
  preferences_.begin(
      PREF_NAMESPACE,
      false);

  const bool loaded =
      loadConfiguration();

  if (!loaded) {
    return startProvisioningPortal();
  }

  return true;
}

void ProvisioningManager::loop() {
  if (provisioningActive_) {
    server_.handleClient();
  }
}

bool ProvisioningManager::hasValidConfig() const {
  return
      validDeviceId(
          config_.deviceId) &&
      config_.wifiSsid.length() > 0 &&
      validMqttHost(
          config_.mqttHost) &&
      config_.mqttPort > 0;
}

const PersistedRuntimeConfig&
ProvisioningManager::config() const {
  return config_;
}

bool ProvisioningManager::startProvisioningPortal() {
  if (provisioningActive_) {
    return true;
  }

  WiFi.disconnect(
      true,
      true);

  delay(100);

  WiFi.mode(
      WIFI_AP_STA);

  const String ssid =
      provisioningSsid();

  const bool started =
      WiFi.softAP(
          ssid.c_str());

  if (!started) {
    return false;
  }

  configureRoutes();

  server_.begin();

  provisioningActive_ =
      true;

  return true;
}

void ProvisioningManager::stopProvisioningPortal() {
  if (!provisioningActive_) {
    return;
  }

  server_.stop();
  WiFi.softAPdisconnect(
      true);

  provisioningActive_ =
      false;
}

bool ProvisioningManager::provisioningActive() const {
  return provisioningActive_;
}

void ProvisioningManager::clearConfiguration() {
  preferences_.clear();

  config_ =
      PersistedRuntimeConfig{};
}

bool ProvisioningManager::loadConfiguration() {
  config_.deviceId =
      preferences_.getString(
          KEY_DEVICE_ID,
          "");

  config_.wifiSsid =
      preferences_.getString(
          KEY_WIFI_SSID,
          "");

  config_.wifiPassword =
      preferences_.getString(
          KEY_WIFI_PASSWORD,
          "");

  config_.mqttHost =
      preferences_.getString(
          KEY_MQTT_HOST,
          "");

  config_.mqttPort =
      preferences_.getUShort(
          KEY_MQTT_PORT,
          1883);

  config_.mqttUsername =
      preferences_.getString(
          KEY_MQTT_USERNAME,
          "");

  config_.mqttPassword =
      preferences_.getString(
          KEY_MQTT_PASSWORD,
          "");

  return hasValidConfig();
}

bool ProvisioningManager::saveConfiguration(
    const PersistedRuntimeConfig& config) {
  if (
      !validDeviceId(
          config.deviceId) ||
      config.wifiSsid.length() == 0 ||
      !validMqttHost(
          config.mqttHost) ||
      config.mqttPort == 0
  ) {
    return false;
  }

  preferences_.putString(
      KEY_DEVICE_ID,
      config.deviceId);

  preferences_.putString(
      KEY_WIFI_SSID,
      config.wifiSsid);

  preferences_.putString(
      KEY_WIFI_PASSWORD,
      config.wifiPassword);

  preferences_.putString(
      KEY_MQTT_HOST,
      config.mqttHost);

  preferences_.putUShort(
      KEY_MQTT_PORT,
      config.mqttPort);

  preferences_.putString(
      KEY_MQTT_USERNAME,
      config.mqttUsername);

  preferences_.putString(
      KEY_MQTT_PASSWORD,
      config.mqttPassword);

  config_ =
      config;

  return true;
}

void ProvisioningManager::configureRoutes() {
  server_.on(
      "/",
      HTTP_GET,
      [this]() {
        handleRoot();
      });

  server_.on(
      "/save",
      HTTP_POST,
      [this]() {
        handleSave();
      });

  server_.on(
      "/status",
      HTTP_GET,
      [this]() {
        handleStatus();
      });

  server_.on(
      "/reset",
      HTTP_POST,
      [this]() {
        handleReset();
      });

  server_.onNotFound(
      [this]() {
        server_.sendHeader(
            "Location",
            "/",
            true);

        server_.send(
            302,
            "text/plain",
            "");
      });
}

void ProvisioningManager::handleRoot() {
  const String html =
      String(
          "<!doctype html>"
          "<html><head>"
          "<meta name='viewport' content='width=device-width,initial-scale=1'>"
          "<title>SportsOS Scoreboard Setup</title>"
          "<style>"
          "body{font-family:Arial,sans-serif;max-width:720px;margin:40px auto;padding:0 16px;background:#0f172a;color:#e2e8f0}"
          "input{width:100%;box-sizing:border-box;padding:10px;margin:6px 0 14px;background:#020617;color:#e2e8f0;border:1px solid #334155;border-radius:8px}"
          "button{padding:11px 18px;border-radius:8px;border:1px solid #475569;background:#1e293b;color:#fff;font-weight:700}"
          "label{font-size:13px;color:#94a3b8}"
          "</style></head><body>"
          "<h1>SportsOS Scoreboard Setup</h1>"
          "<p>Configure this scoreboard for your local SportsOS installation.</p>"
          "<form method='POST' action='/save'>"
          "<label>Device ID</label>"
          "<input name='deviceId' value='") +
      htmlEscape(
          config_.deviceId) +
      "' required>"
      "<label>Wi-Fi SSID</label>"
      "<input name='wifiSsid' value='" +
      htmlEscape(
          config_.wifiSsid) +
      "' required>"
      "<label>Wi-Fi Password</label>"
      "<input name='wifiPassword' type='password' value=''>"
      "<label>MQTT Host</label>"
      "<input name='mqttHost' value='" +
      htmlEscape(
          config_.mqttHost) +
      "' required>"
      "<label>MQTT Port</label>"
      "<input name='mqttPort' type='number' min='1' max='65535' value='" +
      String(
          config_.mqttPort > 0
              ? config_.mqttPort
              : 4012) +
      "' required>"
      "<label>MQTT Username (optional)</label>"
      "<input name='mqttUsername' value='" +
      htmlEscape(
          config_.mqttUsername) +
      "'>"
      "<label>MQTT Password (optional)</label>"
      "<input name='mqttPassword' type='password' value=''>"
      "<button type='submit'>Save Configuration</button>"
      "</form>"
      "</body></html>";

  server_.send(
      200,
      "text/html",
      html);
}

void ProvisioningManager::handleSave() {
  PersistedRuntimeConfig next{};

  next.deviceId =
      server_.arg(
          "deviceId");

  next.wifiSsid =
      server_.arg(
          "wifiSsid");

  next.wifiPassword =
      server_.arg(
          "wifiPassword");

  next.mqttHost =
      server_.arg(
          "mqttHost");

  next.mqttPort =
      static_cast<uint16_t>(
          server_.arg(
              "mqttPort")
              .toInt());

  next.mqttUsername =
      server_.arg(
          "mqttUsername");

  next.mqttPassword =
      server_.arg(
          "mqttPassword");

  /*
   * Preserve existing secrets when the operator leaves
   * password inputs blank.
   */
  if (
      next.wifiPassword.length() == 0
  ) {
    next.wifiPassword =
        config_.wifiPassword;
  }

  if (
      next.mqttPassword.length() == 0
  ) {
    next.mqttPassword =
        config_.mqttPassword;
  }

  if (!saveConfiguration(next)) {
    server_.send(
        400,
        "text/plain",
        "Invalid configuration.");
    return;
  }

  server_.send(
      200,
      "text/html",
      "<html><body><h1>Saved</h1><p>Configuration saved. The scoreboard will restart.</p></body></html>");

  delay(500);

  ESP.restart();
}

void ProvisioningManager::handleStatus() {
  String json =
      "{";

  json +=
      "\"configured\":";
  json +=
      hasValidConfig()
          ? "true"
          : "false";

  json +=
      ",\"deviceId\":\"";
  json +=
      htmlEscape(
          config_.deviceId);
  json +=
      "\"";

  json +=
      ",\"provisioning\":";
  json +=
      provisioningActive_
          ? "true"
          : "false";

  json +=
      "}";

  server_.send(
      200,
      "application/json",
      json);
}

void ProvisioningManager::handleReset() {
  clearConfiguration();

  server_.send(
      200,
      "text/plain",
      "Configuration cleared. Restarting.");

  delay(500);

  ESP.restart();
}

String ProvisioningManager::htmlEscape(
    const String& value) const {
  String escaped =
      value;

  escaped.replace(
      "&",
      "&amp;");

  escaped.replace(
      "<",
      "&lt;");

  escaped.replace(
      ">",
      "&gt;");

  escaped.replace(
      "\"",
      "&quot;");

  escaped.replace(
      "'",
      "&#39;");

  return escaped;
}

String ProvisioningManager::provisioningSsid() const {
  const uint64_t chipId =
      ESP.getEfuseMac();

  char suffix[7] = {};

  snprintf(
      suffix,
      sizeof(suffix),
      "%06llX",
      chipId & 0xFFFFFFULL);

  return
      String(
          "SportsOS-Scoreboard-") +
      suffix;
}

bool ProvisioningManager::validDeviceId(
    const String& deviceId) {
  if (
      deviceId.length() == 0 ||
      deviceId.length() >= 64
  ) {
    return false;
  }

  for (
      size_t index = 0;
      index < deviceId.length();
      ++index
  ) {
    const char value =
        deviceId[index];

    const bool valid =
        (value >= 'a' && value <= 'z') ||
        (value >= 'A' && value <= 'Z') ||
        (value >= '0' && value <= '9') ||
        value == '-' ||
        value == '_';

    if (!valid) {
      return false;
    }
  }

  return true;
}

bool ProvisioningManager::validMqttHost(
    const String& mqttHost) {
  return
      mqttHost.length() > 0 &&
      mqttHost.length() < 128;
}

}  // namespace sportsos
EOF

cat > "$MAIN" <<'EOF'
#include <Arduino.h>

#include "ProvisioningManager.h"
#include "ScoreboardRuntime.h"

using sportsos::PersistedRuntimeConfig;
using sportsos::ProvisioningManager;
using sportsos::RuntimeConfig;
using sportsos::ScoreboardRuntime;

ProvisioningManager provisioning;

ScoreboardRuntime* runtime =
    nullptr;

void setup() {
  Serial.begin(
      115200);

  provisioning.begin();

  if (
      !provisioning.hasValidConfig()
  ) {
    return;
  }

  const PersistedRuntimeConfig&
      persisted =
          provisioning.config();

  RuntimeConfig runtimeConfig{
      persisted.deviceId.c_str(),
      persisted.wifiSsid.c_str(),
      persisted.wifiPassword.c_str(),
      persisted.mqttHost.c_str(),
      persisted.mqttPort,
      persisted.mqttUsername.c_str(),
      persisted.mqttPassword.c_str(),
      5000,
      3000,
      30000,
  };

  runtime =
      new ScoreboardRuntime(
          runtimeConfig);

  runtime->begin();
}

void loop() {
  provisioning.loop();

  if (runtime != nullptr) {
    runtime->loop();
  }

  delay(5);
}
EOF

cat >> "$README" <<'EOF'

## Milestone 11.4 — Local provisioning / configuration

The scoreboard can now enter a local Wi-Fi access-point setup mode when no valid configuration exists.

### Provisioning behavior

When configuration is missing, the ESP32 creates an access point named:

`SportsOS-Scoreboard-XXXXXX`

where the suffix is derived from the device chip ID.

The local setup portal provides fields for:

- scoreboard device ID
- Wi-Fi SSID
- Wi-Fi password
- MQTT host
- MQTT port
- optional MQTT username
- optional MQTT password

Configuration is stored locally using ESP32 `Preferences` / NVS.

### Local routes

- `GET /` — setup form
- `POST /save` — validate and persist configuration
- `GET /status` — local configuration status
- `POST /reset` — erase device configuration and restart

### Security behavior

- credentials are stored locally on the ESP32
- real secrets are not committed to the SportsOS source repository
- password fields are never echoed back into the setup form
- blank password fields preserve previously stored secrets
- the configuration portal is intended for local setup only
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.4 ESP32 local provisioning", () => {
  it("stores configuration with ESP32 Preferences", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ProvisioningManager.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "#include <Preferences.h>",
    );
    expect(header).toContain(
      "PersistedRuntimeConfig",
    );
  });

  it("provides local save status and reset routes", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    for (const route of [
      '"/save"',
      '"/status"',
      '"/reset"',
    ]) {
      expect(source).toContain(
        route,
      );
    }
  });

  it("creates a unique SportsOS local access point", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "SportsOS-Scoreboard-",
    );
    expect(source).toContain(
      "ESP.getEfuseMac",
    );
    expect(source).toContain(
      "WiFi.softAP",
    );
  });

  it("does not echo stored passwords into the setup form", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ProvisioningManager.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "type='password' value=''",
    );
    expect(source).toContain(
      "Preserve existing secrets",
    );
  });

  it("boots the runtime from persisted configuration", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "ProvisioningManager provisioning",
    );
    expect(main).toContain(
      "provisioning.hasValidConfig",
    );
    expect(main).toContain(
      "new ScoreboardRuntime",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 11.4 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - Milestone 11.3 prerequisites verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - local ESP32 provisioning access point"
echo "  - SportsOS-Scoreboard-XXXXXX setup SSID"
echo "  - local web configuration form"
echo "  - persistent Preferences/NVS configuration"
echo "  - device ID / Wi-Fi / MQTT settings"
echo "  - local status + reset endpoints"
echo "  - password values are not echoed in HTML"
echo "  - runtime boots from persisted configuration"
echo "  - Milestone 11.4 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "PlatformIO:"
echo "  Still optional; not required for repository validation."
echo
echo "Next after green:"
echo "  Milestone 11.5 - ESP32 Connectivity Watchdog / Failsafe Runtime"
