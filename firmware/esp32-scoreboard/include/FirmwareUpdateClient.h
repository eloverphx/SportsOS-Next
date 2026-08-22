#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"
#include "FirmwareUpdateDownloader.h"

namespace sportsos {

enum class FirmwareUpdateCheckState : uint8_t {
  Idle = 0,
  Checking,
  NoUpdate,
  UpdateAvailable,
  TransportError,
  InvalidOffer,
};

struct FirmwareUpdateClientConfig {
  const char* apiBaseUrl;
  const char* deviceId;
  const char* currentVersion;
  const char* channel;
  const char* target;
  uint32_t checkIntervalMs;
};

class FirmwareUpdateClient {
 public:
  explicit FirmwareUpdateClient(
      const FirmwareUpdateClientConfig& config);

  void begin();

  void loop(
      bool wifiConnected,
      bool enrollmentVerified);

  FirmwareUpdateCheckState state() const;

  bool updateAvailable() const;

  const FirmwareUpdateOffer& offer() const;

  FirmwareDownloadResult stageAvailableUpdate();

  const FirmwareDownloadProgress&
  downloadProgress() const;

 private:
  FirmwareUpdateClientConfig config_;
  FirmwareUpdateCheckState state_;
  FirmwareUpdateOffer offer_;
  unsigned long lastCheckMs_;
  FirmwareUpdateDownloader downloader_;

  bool checkForUpdate();
  void clearOffer();
};

}  // namespace sportsos
