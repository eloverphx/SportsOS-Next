#include "FirmwareUpdateContract.h"

#include <string.h>

namespace sportsos {

bool FirmwareUpdateContract::validateOffer(
    const FirmwareUpdateOffer& offer) {
  if (
      offer.releaseId[0] == '\0' ||
      offer.version[0] == '\0' ||
      offer.firmwareUrl[0] == '\0'
  ) {
    return false;
  }

  if (
      strlen(
          offer.firmwareSha256) != 64
  ) {
    return false;
  }

  if (
      offer.firmwareSizeBytes == 0
  ) {
    return false;
  }

  return true;
}

const char*
FirmwareUpdateContract::stateText(
    FirmwareUpdateState state) {
  switch (state) {
    case FirmwareUpdateState::Idle:
      return "IDLE";
    case FirmwareUpdateState::Available:
      return "AVAILABLE";
    case FirmwareUpdateState::Downloading:
      return "DOWNLOADING";
    case FirmwareUpdateState::Verifying:
      return "VERIFYING";
    case FirmwareUpdateState::ReadyToInstall:
      return "READY_TO_INSTALL";
    case FirmwareUpdateState::Installing:
      return "INSTALLING";
    case FirmwareUpdateState::Rebooting:
      return "REBOOTING";
    case FirmwareUpdateState::Succeeded:
      return "SUCCEEDED";
    case FirmwareUpdateState::Failed:
      return "FAILED";
    default:
      return "FAILED";
  }
}

}  // namespace sportsos
