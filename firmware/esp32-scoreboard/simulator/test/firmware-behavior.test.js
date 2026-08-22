"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildNumericSnapshot,
  renderSevenSegment,
  tickFrame,
} = require("../firmware-behavior-simulator.js");

test("11.9 converts state into numeric display state", () => {
  const snapshot =
    buildNumericSnapshot({
      homeScore: 4,
      awayScore: 2,
      hasPeriod: true,
      period: 3,
      remainingMs: 125000,
      clockRunning: true,
      hornActive: false,
      health: "Normal",
    });

  assert.deepEqual(snapshot, {
    homeScore: 4,
    awayScore: 2,
    period: 3,
    clockMinutes: 2,
    clockSeconds: 5,
    clockRunning: true,
    hornActive: false,
    health: "Normal",
  });
});

test("11.9 renders fixed-width fields", () => {
  const rendered =
    renderSevenSegment({
      homeScore: 4,
      awayScore: 2,
      period: 3,
      clockMinutes: 2,
      clockSeconds: 5,
      clockRunning: true,
      hornActive: false,
      health: "Normal",
    });

  assert.equal(rendered.home, "04");
  assert.equal(rendered.away, "02");
  assert.equal(rendered.clock, "02:05");
});

test("11.9 projects clock and stops at zero", () => {
  const next =
    tickFrame(
      {
        remainingMs: 1500,
        clockRunning: true,
      },
      2000,
    );

  assert.equal(next.remainingMs, 0);
  assert.equal(next.clockRunning, false);
});
