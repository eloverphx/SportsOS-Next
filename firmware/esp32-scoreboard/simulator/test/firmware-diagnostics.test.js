"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  buildDiagnosticSnapshot,
} = require(
  "../firmware-behavior-simulator.js",
);

test(
  "11.10 marks stale authoritative state",
  () => {
    const snapshot =
      buildDiagnosticSnapshot({
        uptimeSeconds: 120,
        wifiRssi: -61,
        freeHeapBytes: 180000,
        wifiConnected: true,
        mqttConnected: true,
        connectionState: "ONLINE",
        connectivityHealth:
          "STALE_AUTHORITATIVE_STATE",
        deviceId:
          "scoreboard-sim-1",
        gameId:
          "game-1",
      });

    assert.equal(
      snapshot.authoritativeStateStale,
      true,
    );

    assert.equal(
      snapshot.recoveryRequired,
      false,
    );
  },
);

test(
  "11.10 marks recovery-required fault state",
  () => {
    const snapshot =
      buildDiagnosticSnapshot({
        wifiConnected: false,
        mqttConnected: false,
        connectionState: "DEGRADED",
        connectivityHealth:
          "RECOVERY_REQUIRED",
        deviceId:
          "scoreboard-sim-1",
      });

    assert.equal(
      snapshot.recoveryRequired,
      true,
    );

    assert.equal(
      snapshot.wifiConnected,
      false,
    );

    assert.equal(
      snapshot.mqttConnected,
      false,
    );
  },
);
