import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.7 operator focus mode / single broadcast workspace", () => {
  const operations =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const focus =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("links attention queue into focus mode",()=> {
    expect(operations).toContain("Open Focus Mode");
    expect(operations).toContain("/broadcast/operations/");
  });

  it("provides single-broadcast workspace",()=> {
    expect(focus).toContain("Broadcast Focus");
    expect(focus).toContain("Single-broadcast operator workspace");
  });

  it("shows core operational state",()=> {
    expect(focus).toContain("Coordinator");
    expect(focus).toContain("Go-Live");
    expect(focus).toContain("Encoder");
    expect(focus).toContain("Publish Health");
    expect(focus).toContain("Retry");
  });

  it("provides existing safe control surfaces",()=> {
    expect(focus).toContain("Safe Operator Actions");
    expect(focus).toContain("Acknowledge Incident");
    expect(focus).toContain("Emergency Stop Broadcast");
  });

  it("shows operator timeline",()=> {
    expect(focus).toContain("Operator Timeline");
    expect(focus).toContain("operator-timeline");
  });

  it("does not directly control encoder runtime",()=> {
    expect(focus).not.toContain("startEncoderRuntime");
    expect(focus).not.toContain("stopEncoderRuntime");
  });

  it("refreshes every five seconds",()=> {
    expect(focus).toContain("5000");
    expect(focus).toContain("setInterval");
  });
});
