"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  evaluateFirmwareUpdateOffer,
} = require(
  "../firmware-behavior-simulator.js",
);

const validRelease = {
  releaseId: "esp32dev-0.13.4-test",
  version: "0.13.4",
  firmwareSha256:
    "a".repeat(64),
  firmwareSizeBytes: 123456,
};

test(
  "13.4 blocks update offers for unverified devices",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "PENDING",
        currentVersion: "0.13.3",
        release: validRelease,
      });

    assert.equal(
      result.updateAvailable,
      false,
    );

    assert.equal(
      result.state,
      "BLOCKED_UNVERIFIED",
    );
  },
);

test(
  "13.4 accepts valid update offer for verified device",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "VERIFIED",
        currentVersion: "0.13.3",
        release: validRelease,
      });

    assert.equal(
      result.updateAvailable,
      true,
    );

    assert.equal(
      result.state,
      "UPDATE_AVAILABLE",
    );
  },
);

test(
  "13.4 rejects malformed firmware offers",
  () => {
    const result =
      evaluateFirmwareUpdateOffer({
        enrollmentStatus: "VERIFIED",
        currentVersion: "0.13.3",
        release: {
          ...validRelease,
          firmwareSha256: "bad",
        },
      });

    assert.equal(
      result.state,
      "INVALID_OFFER",
    );
  },
);
