#include "FirmwareInstallPolicy.h"

namespace sportsos {

FirmwareInstallDecision
FirmwareInstallPolicy::evaluate(
    const FirmwareInstallPolicyInput& input) {
  if (!input.enrollmentVerified) {
    return
        FirmwareInstallDecision::BlockedUnverified;
  }

  if (
      input.runtimeActive &&
      input.gameInProgress
  ) {
    return
        FirmwareInstallDecision::WaitForIdle;
  }

  if (
      !input.updateAvailable ||
      !input.stagedSuccessfully
  ) {
    return
        FirmwareInstallDecision::NotReady;
  }

  if (
      input.runtimeActive &&
      !input.mandatory
  ) {
    return
        FirmwareInstallDecision::BlockedRuntimeUnsafe;
  }

  return
      FirmwareInstallDecision::ReadyToInstall;
}

}  // namespace sportsos
