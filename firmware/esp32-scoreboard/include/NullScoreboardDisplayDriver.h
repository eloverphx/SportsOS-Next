#pragma once

#include "ScoreboardDisplayDriver.h"

namespace sportsos {

class NullScoreboardDisplayDriver final
    : public ScoreboardDisplayDriver {
 public:
  bool begin() override;

  void render(
      const DisplayFrame& frame) override;

  void setHorn(
      bool active) override;

  void setStatusIndicator(
      DisplayHealthState health) override;

  void clear() override;

  const DisplayFrame& lastFrame() const;

 private:
  DisplayFrame lastFrame_{};
};

}  // namespace sportsos
