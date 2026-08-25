import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.8 operator notes / shift handoff context", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastOperatorNotes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const focus=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists operator notes in shared SportsOS data storage",()=> {
    expect(service).toContain("SPORTSOS_DATA_DIR");
    expect(service).toContain("broadcast-operator-notes.json");
    expect(service).toContain("2500");
  });

  it("requires operator and note text",()=> {
    expect(service).toContain("Operator name is required.");
    expect(service).toContain("Operator note is required.");
  });

  it("provides notes API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-notes"');
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("addBroadcastOperatorNote");
  });

  it("provides shift handoff notes UI",()=> {
    expect(focus).toContain("Shift Handoff Notes");
    expect(focus).toContain("Save Handoff Note");
    expect(focus).toContain("operatorNotes");
  });

  it("does not let notes control broadcast state",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
    expect(service).not.toContain("setBroadcastCoordinatorIntent");
    expect(service).not.toContain("markGoLive");
  });
});
