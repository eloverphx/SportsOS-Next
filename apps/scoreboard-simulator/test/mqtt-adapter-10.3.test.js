import test from "node:test";
import assert from "node:assert/strict";
import {
  applySimulatorCommand,
  createInitialSimulatorState,
} from "../src/mqtt-adapter.js";

test("10.3 applies SET_SCORE commands", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  const next = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-score",
        type: "SET_SCORE",
        homeScore: 3,
        awayScore: 2,
      },
    },
  );

  assert.equal(next.homeScore, 3);
  assert.equal(next.awayScore, 2);
});

test("10.3 applies clock and period commands", () => {
  let state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  state = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-clock",
        type: "SET_CLOCK",
        remainingMs: 90000,
        running: true,
      },
    },
  );

  state = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-period",
        type: "SET_PERIOD",
        period: 2,
      },
    },
  );

  assert.deepEqual(
    state.clock,
    {
      remainingMs: 90000,
      running: true,
    },
  );
  assert.equal(state.period, 2);
});

test("10.3 rejects commands for another device", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  assert.throws(
    () =>
      applySimulatorCommand(
        state,
        {
          deviceId: "another-device",
          sentAt: new Date().toISOString(),
          command: {
            protocolVersion: 1,
            commandId: "cmd-1",
            type: "HORN",
            active: true,
          },
        },
      ),
    /deviceId does not match/,
  );
});

test("10.3 applies full SYNC_STATE", () => {
  const state =
    createInitialSimulatorState(
      "scoreboard-simulator-1",
    );

  const next = applySimulatorCommand(
    state,
    {
      deviceId: "scoreboard-simulator-1",
      sentAt: new Date().toISOString(),
      command: {
        protocolVersion: 1,
        commandId: "cmd-sync",
        type: "SYNC_STATE",
        snapshot: {
          protocolVersion: 1,
          deviceId: "scoreboard-simulator-1",
          gameId: "game-42",
          homeScore: 5,
          awayScore: 4,
          period: 3,
          clock: {
            remainingMs: 45000,
            running: false,
          },
          hornActive: false,
        },
      },
    },
  );

  assert.equal(next.gameId, "game-42");
  assert.equal(next.homeScore, 5);
  assert.equal(next.awayScore, 4);
  assert.equal(next.period, 3);
  assert.equal(
    next.clock.remainingMs,
    45000,
  );
});
