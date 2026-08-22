#pragma once

#include <stdint.h>
#include <stddef.h>

namespace sportsos {

static constexpr uint8_t SCOREBOARD_PROTOCOL_VERSION = 1;

enum class ConnectionState : uint8_t {
  Offline = 0,
  Connecting = 1,
  Online = 2,
  Degraded = 3,
};

struct ClockState {
  uint32_t remainingMs;
  bool running;
};

struct ScoreboardState {
  uint8_t protocolVersion;
  char deviceId[64];
  char gameId[64];
  bool hasGame;
  ConnectionState connectionState;
  uint16_t homeScore;
  uint16_t awayScore;
  uint8_t period;
  bool hasPeriod;
  ClockState clock;
  bool hornActive;
};

enum class CommandType : uint8_t {
  Unknown = 0,
  SetGame,
  SetScore,
  SetClock,
  SetPeriod,
  Horn,
  SyncState,
};

struct ParsedCommand {
  uint8_t protocolVersion;
  char commandId[64];
  CommandType type;

  char gameId[64];
  bool hasGame;

  uint16_t homeScore;
  uint16_t awayScore;

  uint32_t remainingMs;
  bool clockRunning;

  uint8_t period;
  bool hasPeriod;

  bool hornActive;

  ScoreboardState syncState;
};

enum class CommandStatus : uint8_t {
  Accepted = 0,
  Rejected = 1,
  Applied = 2,
};

struct CommandResult {
  CommandStatus status;
  char message[128];
};

class ScoreboardProtocol {
 public:
  explicit ScoreboardProtocol(const char* deviceId);

  const ScoreboardState& state() const;

  CommandResult apply(const ParsedCommand& command);

  void setConnectionState(ConnectionState state);

  void tick(uint32_t elapsedMs);

  void clearHorn();

 private:
  ScoreboardState state_;

  CommandResult reject(const char* message) const;
  CommandResult applied() const;

  bool validateBase(const ParsedCommand& command) const;
};

}  // namespace sportsos
