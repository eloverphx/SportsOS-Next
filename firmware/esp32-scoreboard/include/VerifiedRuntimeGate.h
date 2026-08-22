#pragma once

#include <stdint.h>

#include "EnrollmentClient.h"

namespace sportsos {

enum class RuntimeGateState : uint8_t {
  WaitingForEnrollment = 0,
  Allowed,
  Rejected,
};

class VerifiedRuntimeGate {
 public:
  RuntimeGateState evaluate(
      EnrollmentClientState enrollmentState);

  RuntimeGateState state() const;

  bool allowAuthoritativeRuntime() const;

 private:
  RuntimeGateState state_ =
      RuntimeGateState::WaitingForEnrollment;
};

}  // namespace sportsos
