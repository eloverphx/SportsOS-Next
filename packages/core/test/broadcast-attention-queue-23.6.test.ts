import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.6 attention queue / operator prioritization", () => {
  const route=fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const page=fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/broadcast/operations/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("provides attention queue API",()=> {
    expect(route).toContain('"/broadcast-coordinator/attention-queue"');
  });

  it("derives ranked severity from existing state",()=> {
    for(const severity of [
      "CRITICAL",
      "HIGH",
      "MEDIUM",
      "LOW",
    ]) {
      expect(route).toContain(`"${severity}"`);
    }

    expect(route).toContain('"EMERGENCY_STOPPED"');
    expect(route).toContain('"DEGRADED"');
    expect(route).toContain('"EXHAUSTED"');
    expect(route).toContain('"SCHEDULED"');
  });

  it("sorts by score descending",()=> {
    expect(route).toContain("b.score");
    expect(route).toContain("a.score");
  });

  it("provides operator attention queue UI",()=> {
    expect(page).toContain("Operator Attention Queue");
    expect(page).toContain("attentionItems");
    expect(page).toContain("Refresh Queue");
  });

  it("refreshes queue with operations status",()=> {
    expect(page).toContain("loadAttentionQueue");
    expect(page).toContain("5000");
  });

  it("does not persist a second incident model",()=> {
    expect(page).not.toContain("localStorage");
    expect(route).not.toContain("attention-queue.json");
  });
});
