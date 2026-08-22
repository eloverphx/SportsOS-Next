#pragma once

#include <Arduino.h>

namespace sportsos {

enum class BootHealthState : uint8_t {
  Unknown = 0,
  PendingValidation,
  Healthy,
  Failed,
};

class FirmwareBootHealth {
 public:
  FirmwareBootHealth();

  void begin();

  void markPendingValidation();

  void confirmHealthy();

  void markFailed();

  BootHealthState state() const;

  bool requiresValidation() const;

 private:
  BootHealthState state_;
};

}  // namespace sportsos
