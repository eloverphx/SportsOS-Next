import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("game event realtime outbox contract", () => {
  it("enqueues create and void event realtime messages inside the repository", () => {
    const repository = fs.readFileSync(
      new URL("../src/modules/game-events/repository.ts", import.meta.url),
      "utf8",
    );

    expect(repository).toContain('event: "game:event-created"');
    expect(repository).toContain('event: "scoreboard:effect"');
    expect(repository).toContain('event: "scoreboard:sound"');
    expect(repository).toContain('event: "game:event-voided"');
    expect(repository).toContain("await enqueueRealtimeEvent(connection");
  });

  it("does not directly emit detailed event realtime messages from the route", () => {
    const routes = fs.readFileSync(
      new URL("../src/modules/game-events/routes.ts", import.meta.url),
      "utf8",
    );

    expect(routes).not.toContain('.emit("game:event-created"');
    expect(routes).not.toContain('.emit("game:event-voided"');
    expect(routes).not.toContain('.emit("scoreboard:effect"');
    expect(routes).not.toContain('.emit("scoreboard:sound"');
  });
});
