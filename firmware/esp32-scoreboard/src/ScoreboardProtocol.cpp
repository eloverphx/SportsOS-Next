#include "ScoreboardProtocol.h"

#include <string.h>

namespace sportsos {

namespace {

void copyText(
    char* destination,
    size_t destinationSize,
    const char* source) {
  if (destinationSize == 0) {
    return;
  }

  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }

  strncpy(
      destination,
      source,
      destinationSize - 1);

  destination[
      destinationSize - 1] = '\0';
}

CommandResult makeResult(
    CommandStatus status,
    const char* message) {
  CommandResult result{};
  result.status = status;

  copyText(
      result.message,
      sizeof(result.message),
      message);

  return result;
}

}  // namespace

ScoreboardProtocol::ScoreboardProtocol(
    const char* deviceId) {
  memset(&state_, 0, sizeof(state_));

  state_.protocolVersion =
      SCOREBOARD_PROTOCOL_VERSION;

  copyText(
      state_.deviceId,
      sizeof(state_.deviceId),
      deviceId);

  state_.connectionState =
      ConnectionState::Offline;

  state_.clock.remainingMs = 0;
  state_.clock.running = false;
}

const ScoreboardState&
ScoreboardProtocol::state() const {
  return state_;
}

bool ScoreboardProtocol::validateBase(
    const ParsedCommand& command) const {
  return
      command.protocolVersion ==
          SCOREBOARD_PROTOCOL_VERSION &&
      command.commandId[0] != '\0';
}

CommandResult
ScoreboardProtocol::reject(
    const char* message) const {
  return makeResult(
      CommandStatus::Rejected,
      message);
}

CommandResult
ScoreboardProtocol::applied() const {
  return makeResult(
      CommandStatus::Applied,
      nullptr);
}

CommandResult
ScoreboardProtocol::apply(
    const ParsedCommand& command) {
  if (!validateBase(command)) {
    return reject(
        "Invalid command protocol or commandId.");
  }

  switch (command.type) {
    case CommandType::SetGame:
      state_.hasGame =
          command.hasGame;

      copyText(
          state_.gameId,
          sizeof(state_.gameId),
          command.hasGame
              ? command.gameId
              : "");

      return applied();

    case CommandType::SetScore:
      state_.homeScore =
          command.homeScore;
      state_.awayScore =
          command.awayScore;

      return applied();

    case CommandType::SetClock:
      state_.clock.remainingMs =
          command.remainingMs;
      state_.clock.running =
          command.clockRunning;

      return applied();

    case CommandType::SetPeriod:
      state_.hasPeriod =
          command.hasPeriod;
      state_.period =
          command.hasPeriod
              ? command.period
              : 0;

      return applied();

    case CommandType::Horn:
      state_.hornActive =
          command.hornActive;

      return applied();

    case CommandType::SyncState:
      if (
          command.syncState.protocolVersion !=
          SCOREBOARD_PROTOCOL_VERSION
      ) {
        return reject(
            "SYNC_STATE protocol version mismatch.");
      }

      state_.hasGame =
          command.syncState.hasGame;

      copyText(
          state_.gameId,
          sizeof(state_.gameId),
          command.syncState.hasGame
              ? command.syncState.gameId
              : "");

      state_.homeScore =
          command.syncState.homeScore;
      state_.awayScore =
          command.syncState.awayScore;
      state_.hasPeriod =
          command.syncState.hasPeriod;
      state_.period =
          command.syncState.period;
      state_.clock =
          command.syncState.clock;
      state_.hornActive =
          command.syncState.hornActive;

      return applied();

    case CommandType::Unknown:
    default:
      return reject(
          "Unsupported command type.");
  }
}

void ScoreboardProtocol::setConnectionState(
    ConnectionState state) {
  state_.connectionState = state;
}

void ScoreboardProtocol::tick(
    uint32_t elapsedMs) {
  if (!state_.clock.running) {
    return;
  }

  if (
      elapsedMs >=
      state_.clock.remainingMs
  ) {
    state_.clock.remainingMs = 0;
    state_.clock.running = false;
    return;
  }

  state_.clock.remainingMs -=
      elapsedMs;
}

void ScoreboardProtocol::clearHorn() {
  state_.hornActive = false;
}

}  // namespace sportsos
