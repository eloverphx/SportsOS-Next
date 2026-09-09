import { describe, expect, it } from "vitest";
import {
  parseDurableGameId,
  recordingStatusForGoLiveStatus,
} from "../src/services/durableGoLiveBridge.js";

describe("Milestone 37.4 durable go-live bridge", () => {
  it("persists only canonical positive integer database game ids", () => {
    expect(parseDurableGameId("42")).toBe(42);
    expect(parseDurableGameId(" 42 ")).toBe(42);
    expect(parseDurableGameId("game-42")).toBeNull();
    expect(parseDurableGameId("0")).toBeNull();
    expect(parseDurableGameId("-1")).toBeNull();
    expect(parseDurableGameId("999999999999999999999")).toBeNull();
  });

  it("maps live/degraded sessions to active recording state", () => {
    expect(recordingStatusForGoLiveStatus("LIVE")).toBe("RECORDING");
    expect(recordingStatusForGoLiveStatus("DEGRADED")).toBe("RECORDING");
  });

  it("moves completed live recordings to processing", () => {
    expect(recordingStatusForGoLiveStatus("COMPLETE")).toBe("PROCESSING");
  });

  it("marks errored and emergency-stopped recordings failed", () => {
    expect(recordingStatusForGoLiveStatus("ERROR")).toBe("FAILED");
    expect(recordingStatusForGoLiveStatus("EMERGENCY_STOPPED")).toBe("FAILED");
  });

  it("does not create recording state before a stream reaches live", () => {
    expect(recordingStatusForGoLiveStatus("IDLE")).toBeNull();
    expect(recordingStatusForGoLiveStatus("ARMED")).toBeNull();
    expect(recordingStatusForGoLiveStatus("STARTING")).toBeNull();
    expect(recordingStatusForGoLiveStatus("STOPPING")).toBeNull();
  });
});
