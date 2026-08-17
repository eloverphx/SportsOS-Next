import { describe, expect, it } from "vitest";
import {
  buildTournamentOperationsSummary,
} from "../lib/tournament-operations-dashboard";

describe("Milestone 7.10 tournament operations dashboard", () => {
  it("reports pregame blockers", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: false,
      effectiveReady: false,
      homeCheckedIn: false,
      awayCheckedIn: true,
      homeRosterLocked: false,
      awayRosterLocked: true,
      officialsReady: false,
      startAuthorized: false,
      liveStarted: false,
      finalized: false,
    });

    expect(summary.stage).toBe("PREGAME");
    expect(summary.blockers).toContain("Home team not checked in");
    expect(summary.blockers).toContain("Home roster not locked");
    expect(summary.blockers).toContain(
      "Required officials not assigned",
    );
  });

  it("reports authorized stage before live start", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: false,
      finalized: false,
    });

    expect(summary.stage).toBe("AUTHORIZED");
  });

  it("reports live stage", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: true,
      finalized: false,
    });

    expect(summary.stage).toBe("LIVE");
  });

  it("reports final stage with no blockers", () => {
    const summary = buildTournamentOperationsSummary({
      actualReady: true,
      effectiveReady: true,
      homeCheckedIn: true,
      awayCheckedIn: true,
      homeRosterLocked: true,
      awayRosterLocked: true,
      officialsReady: true,
      startAuthorized: true,
      liveStarted: true,
      finalized: true,
    });

    expect(summary.stage).toBe("FINAL");
    expect(summary.blockers).toEqual([]);
    expect(summary.completionPercent).toBe(100);
  });
});
