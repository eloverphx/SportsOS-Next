#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"

namespace sportsos {

struct FirmwareUpdateReporterConfig {
  const char* apiBaseUrl;
  const char* deviceId;
  const char* currentVersion;
};

class FirmwareUpdateReporter {
 public:
  explicit FirmwareUpdateReporter(
      const FirmwareUpdateReporterConfig& config);

  bool report(
      const FirmwareUpdateOffer& offer,
      FirmwareUpdateState state,
      int progressPercent,
      const char* error);

 private:
  FirmwareUpdateReporterConfig config_;

  static const char* stateText(
      FirmwareUpdateState state);
};

}  // namespace sportsos
