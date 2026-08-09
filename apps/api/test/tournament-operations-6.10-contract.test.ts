import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

const nav = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentOperationsNavigation.tsx",
    import.meta.url,
  ),
  "utf8",
);

const operations = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentDayOperations.tsx",
    import.meta.url,
  ),
  "utf8",
);

const focus = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentFocusPanel.tsx",
    import.meta.url,
  ),
  "utf8",
);

const timeline = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleTimeline.tsx",
    import.meta.url,
  ),
  "utf8",
);

const editor = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleEditor.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament Operations 6.10 hardening contract", () => {
  it("adds a coherent director workflow navigator", () => {
    expect(page).toContain("TournamentOperationsNavigation");
    expect(nav).toContain("Tournament Director workflow");
    expect(nav).toContain("#director-attention");
    expect(nav).toContain("#director-focus");
    expect(nav).toContain("#director-timeline");
    expect(nav).toContain("#director-scheduling");
    expect(nav).toContain('data-testid={`workflow-link-${section.id}`}');
    expect(nav).toContain('aria-label={`${section.label}: ${section.detail}`}');
  });

  it("provides stable workflow section targets", () => {
    expect(operations).toContain('id="director-attention"');
    expect(focus).toContain('id="director-focus"');
    expect(timeline).toContain('id="director-timeline"');
    expect(editor).toContain('id="director-scheduling"');
  });

  it("provides stable E2E selectors", () => {
    expect(operations).toContain('data-testid="director-attention"');
    expect(focus).toContain('data-testid="director-focus"');
    expect(timeline).toContain('data-testid="director-timeline"');
    expect(editor).toContain('data-testid="director-scheduling"');
    expect(nav).toContain('data-testid="tournament-workflow-nav"');
  });

  it("does not move mutation authority into navigation or operations views", () => {
    expect(nav).not.toContain('method: "PUT"');
    expect(operations).not.toContain('method: "PUT"');
    expect(focus).not.toContain('method: "PUT"');
    expect(timeline).not.toContain('method: "PUT"');
    expect(editor).toContain('method: "PUT"');
    expect(editor).toContain("scheduleConflictOverride");
  });
});
