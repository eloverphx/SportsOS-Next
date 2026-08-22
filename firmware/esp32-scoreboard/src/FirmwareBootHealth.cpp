#include "FirmwareBootHealth.h"

#include <Preferences.h>

namespace sportsos {

namespace {
Preferences prefs;

constexpr const char* NAMESPACE_NAME =
    "sportsos-ota";

constexpr const char* KEY_PENDING =
    "pending";

constexpr const char* KEY_FAILED =
    "failed";
}  // namespace

FirmwareBootHealth::FirmwareBootHealth()
    : state_(BootHealthState::Unknown) {}

void FirmwareBootHealth::begin() {
  prefs.begin(
      NAMESPACE_NAME,
      false);

  const bool failed =
      prefs.getBool(
          KEY_FAILED,
          false);

  const bool pending =
      prefs.getBool(
          KEY_PENDING,
          false);

  if (failed) {
    state_ =
        BootHealthState::Failed;
    return;
  }

  if (pending) {
    state_ =
        BootHealthState::PendingValidation;
    return;
  }

  state_ =
      BootHealthState::Healthy;
}

void FirmwareBootHealth::markPendingValidation() {
  prefs.putBool(
      KEY_PENDING,
      true);

  prefs.putBool(
      KEY_FAILED,
      false);

  state_ =
      BootHealthState::PendingValidation;
}

void FirmwareBootHealth::confirmHealthy() {
  prefs.putBool(
      KEY_PENDING,
      false);

  prefs.putBool(
      KEY_FAILED,
      false);

  state_ =
      BootHealthState::Healthy;
}

void FirmwareBootHealth::markFailed() {
  prefs.putBool(
      KEY_FAILED,
      true);

  state_ =
      BootHealthState::Failed;
}

BootHealthState
FirmwareBootHealth::state() const {
  return state_;
}

bool FirmwareBootHealth::requiresValidation() const {
  return
      state_ ==
      BootHealthState::PendingValidation;
}

}  // namespace sportsos
