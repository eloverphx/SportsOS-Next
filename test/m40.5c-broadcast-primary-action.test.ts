import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const source = readFileSync("apps/dashboard/app/broadcast/operations/[gameId]/page.tsx", "utf8");

describe("M40.5c broadcast primary action UX", () => {
  it("tracks start and stop independently from generic busy state", () => {
    expect(source).toContain('useState<"start" | "stop" | null>(null)');

    expect(source).toContain('setPrimaryAction("start")');
    expect(source).toContain('setPrimaryAction("stop")');
  });

  it("keeps STARTING visible while start orchestration is still running", () => {
    expect(source).toContain('primaryAction === "start" ? "Starting…" : "Start Broadcast"');
  });

  it("keeps STOPPING visible while stop orchestration is running", () => {
    expect(source).toContain('primaryAction === "stop"');
    expect(source).toContain('"Stopping…"');
  });

  it("allows stopping from authoritative STARTING/LIVE/RECORDING states", () => {
    expect(source).toContain('recording?.status === "RECORDING"');
    expect(source).toContain('snapshot.goLive.status === "STARTING"');
    expect(source).toContain('snapshot.goLive.status === "LIVE"');
  });

  it("does not require a healthy publisher in order to offer stop", () => {
    expect(source).toContain('primaryAction !== "start"');
    expect(source).toContain('onClick={() => void runCoordinatorAction("stop")}');
  });
});
