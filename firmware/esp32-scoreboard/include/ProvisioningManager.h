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
