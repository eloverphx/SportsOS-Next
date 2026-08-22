#pragma once

#include <Arduino.h>

namespace sportsos {

constexpr uint8_t
FIRMWARE_UPDATE_PROTOCOL_VERSION = 1;

enum class FirmwareUpdateState : uint8_t {
  Idle = 0,
  Available,
  Downloading,
  Verifying,
  ReadyToInstall,
  Installing,
  Rebooting,
  Succeeded,
  Failed,
};

struct FirmwareUpdateOffer {
  char releaseId[64];
  char version[32];
  char firmwareUrl[256];
  char firmwareSha256[65];
  uint32_t firmwareSizeBytes;
  bool mandatory;
};

struct FirmwareUpdateProgress {
  FirmwareUpdateState state;
  uint8_t progressPercent;
  char error[128];
};

class FirmwareUpdateContract {
 public:
  static bool validateOffer(
      const FirmwareUpdateOffer& offer);

  static const char* stateText(
      FirmwareUpdateState state);
};

}  // namespace sportsos
