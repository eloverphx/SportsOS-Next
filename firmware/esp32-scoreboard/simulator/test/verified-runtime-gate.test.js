"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  evaluateVerifiedRuntimeGate,
} = require(
  "../firmware-behavior-simulator.js",
);

test(
  "12.8 pending enrollment blocks authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "PENDING",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      false,
    );

    assert.equal(
      result.state,
      "WAITING_FOR_ENROLLMENT",
    );
  },
);

test(
  "12.8 verified enrollment allows authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "VERIFIED",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      true,
    );

    assert.equal(
      result.state,
      "ALLOWED",
    );
  },
);

test(
  "12.8 rejected enrollment permanently blocks authoritative runtime",
  () => {
    const result =
      evaluateVerifiedRuntimeGate(
        "REJECTED",
      );

    assert.equal(
      result.allowAuthoritativeRuntime,
      false,
    );

    assert.equal(
      result.state,
      "REJECTED",
    );
  },
);
