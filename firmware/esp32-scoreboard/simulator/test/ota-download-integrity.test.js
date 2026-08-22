"use strict";

const test =
  require("node:test");

const assert =
  require("node:assert/strict");

const {
  verifyFirmwareDownload,
} = require(
  "../firmware-behavior-simulator.js",
);

const SHA =
  "a".repeat(64);

test(
  "13.5 accepts matching firmware size and SHA-256",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 1000,
        expectedSha256: SHA,
        actualSha256: SHA,
      });

    assert.equal(
      result.ok,
      true,
    );

    assert.equal(
      result.state,
      "READY_TO_INSTALL",
    );
  },
);

test(
  "13.5 rejects incomplete firmware download",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 999,
        expectedSha256: SHA,
        actualSha256: SHA,
      });

    assert.equal(
      result.ok,
      false,
    );

    assert.equal(
      result.reason,
      "SIZE_MISMATCH",
    );
  },
);

test(
  "13.5 rejects firmware with invalid SHA-256",
  () => {
    const result =
      verifyFirmwareDownload({
        expectedSize: 1000,
        actualSize: 1000,
        expectedSha256: SHA,
        actualSha256:
          "b".repeat(64),
      });

    assert.equal(
      result.ok,
      false,
    );

    assert.equal(
      result.reason,
      "SHA256_MISMATCH",
    );
  },
);
