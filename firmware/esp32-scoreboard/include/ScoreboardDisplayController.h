#pragma once

#include "ConnectivityWatchdog.h"
#include "ScoreboardDisplayDriver.h"
#include "ScoreboardProtocol.h"

namespace sportsos {

class ScoreboardDisplayController {
 public:
  explicit ScoreboardDisplayController(
      ScoreboardDisplayDriver& driver);

  bool begin();

  void update(
      const ScoreboardState& state,
      ConnectivityHealth connectivityHealth);

  static DisplayHealthState mapHealth(
      ConnectivityHealth connectivityHealth);

 private:
  ScoreboardDisplayDriver& driver_;
};

}  // namespace sportsos
