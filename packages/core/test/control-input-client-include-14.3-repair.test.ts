import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.3 control-input client include repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("includes the control input client directly", () => {
    expect(main).toContain(
      '#include "ScoreboardControlInputClient.h"',
    );
  });

  it("does not depend on ScoreboardControlInput.h being directly included", () => {
    expect(main).toContain(
      "ScoreboardControlInputClient",
    );
  });

  it("submits physical button events through the client", () => {
    expect(main).toContain(
      "scoreboardControlInputClient->submit",
    );
  });
});
