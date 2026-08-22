#include "VerifiedRuntimeGate.h"

namespace sportsos {

RuntimeGateState VerifiedRuntimeGate::evaluate(
    EnrollmentClientState enrollmentState) {
  switch (enrollmentState) {
    case EnrollmentClientState::Verified:
      state_ =
          RuntimeGateState::Allowed;
      break;

    case EnrollmentClientState::Rejected:
      state_ =
          RuntimeGateState::Rejected;
      break;

    case EnrollmentClientState::Idle:
    case EnrollmentClientState::Pending:
    case EnrollmentClientState::TransportError:
    default:
      state_ =
          RuntimeGateState::WaitingForEnrollment;
      break;
  }

  return state_;
}

RuntimeGateState
VerifiedRuntimeGate::state() const {
  return state_;
}

bool VerifiedRuntimeGate::
allowAuthoritativeRuntime() const {
  return
      state_ ==
      RuntimeGateState::Allowed;
}

}  // namespace sportsos
