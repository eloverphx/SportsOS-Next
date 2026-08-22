#pragma once

#include <Arduino.h>

#include "FirmwareUpdateClient.h"

namespace sportsos {

enum class FirmwareInstallDecision : uint8_t {
  NotReady = 0,
  WaitForIdle,
  ReadyToInstall,
  BlockedUnverified,
  BlockedRuntimeUnsafe,
};

struct FirmwareInstallPolicyInput {
  bool enrollmentVerified;
  bool runtimeActive;
  bool gameInProgress;
  bool updateAvailable;
  bool stagedSuccessfully;
  bool mandatory;
};

class FirmwareInstallPolicy {
 public:
  static FirmwareInstallDecision evaluate(
      const FirmwareInstallPolicyInput& input);
};

}  // namespace sportsos
