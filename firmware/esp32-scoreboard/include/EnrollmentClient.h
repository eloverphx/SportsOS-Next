#pragma once

#include <Arduino.h>

#include "DeviceEnrollment.h"

namespace sportsos {

enum class EnrollmentClientState : uint8_t {
  Idle = 0,
  Pending,
  Verified,
  Rejected,
  TransportError,
};

struct EnrollmentClientConfig {
  const char* apiBaseUrl;
  uint32_t retryIntervalMs;
};

class EnrollmentClient {
 public:
  EnrollmentClient(
      const EnrollmentClientConfig& config,
      const DeviceEnrollmentIdentity& identity);

  void begin();

  void loop(
      bool wifiConnected);

  EnrollmentClientState state() const;

  bool isVerified() const;

  bool isRejected() const;

 private:
  EnrollmentClientConfig config_;
  DeviceEnrollmentIdentity identity_;

  EnrollmentClientState state_;
  unsigned long lastAttemptMs_;

  bool submitFirstBoot();

  bool refreshStatus();

  void applyServerStatus(
      const String& status);
};

}  // namespace sportsos
