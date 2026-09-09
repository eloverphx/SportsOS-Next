import { describe, expect, it } from "vitest";
import { deriveEventClipWindow } from "../src/modules/recording-event-anchors/clip-window.js";

describe("Milestone 37.5 deterministic event clip windows", () => {
  it("uses an 8-second pre-roll and 5-second post-roll by default", () => {
    expect(
      deriveEventClipWindow({
        recordingOffsetMs: 30_000,
        recordingDurationMs: 120_000,
      }),
    ).toEqual({
      startMs: 22_000,
      endMs: 35_000,
      durationMs: 13_000,
    });
  });

  it("clamps the beginning of a clip to zero", () => {
    expect(
      deriveEventClipWindow({
        recordingOffsetMs: 3_000,
        recordingDurationMs: 120_000,
      }),
    ).toEqual({
      startMs: 0,
      endMs: 8_000,
      durationMs: 8_000,
    });
  });

  it("clamps the end of a clip to known recording duration", () => {
    expect(
      deriveEventClipWindow({
        recordingOffsetMs: 58_000,
        recordingDurationMs: 60_000,
      }),
    ).toEqual({
      startMs: 50_000,
      endMs: 60_000,
      durationMs: 10_000,
    });
  });

  it("supports an unfinished recording whose duration is not known yet", () => {
    expect(
      deriveEventClipWindow({
        recordingOffsetMs: 20_000,
        recordingDurationMs: null,
      }),
    ).toEqual({
      startMs: 12_000,
      endMs: 25_000,
      durationMs: 13_000,
    });
  });

  it("rejects invalid negative timing inputs", () => {
    expect(() =>
      deriveEventClipWindow({
        recordingOffsetMs: -1,
        recordingDurationMs: null,
      }),
    ).toThrow(RangeError);
  });
});
