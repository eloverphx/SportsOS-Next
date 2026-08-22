#pragma once

#include <Arduino.h>

namespace sportsos {

struct DeviceEnrollmentIdentity {
  char deviceId[64];
  char firmwareVersion[32];
  char chipId[32];
};

class DeviceEnrollment {
 public:
  static DeviceEnrollmentIdentity buildIdentity(
      const char* deviceId);

  static String buildFirstBootJson(
      const DeviceEnrollmentIdentity& identity);

  static String buildClaimVerificationJson(
      const char* claimToken);
};

}  // namespace sportsos
