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
