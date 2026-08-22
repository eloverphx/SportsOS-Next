import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.2 control-input namespace repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("imports ScoreboardControlInput into main namespace", () => {
    expect(main).toContain(
      "using sportsos::ScoreboardControlInput;",
    );
  });

  it("imports ScoreboardControlInputType into main namespace", () => {
    expect(main).toContain(
      "using sportsos::ScoreboardControlInputType;",
    );
  });

  it("keeps GPIO button mappings on the shared control contract", () => {
    expect(main).toContain(
      "ScoreboardControlInputType::ScoreHomeIncrement",
    );

    expect(main).toContain(
      "ScoreboardControlInput::typeText",
    );
  });
});
