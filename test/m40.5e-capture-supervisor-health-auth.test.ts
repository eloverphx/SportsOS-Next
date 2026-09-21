import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const compose = readFileSync("docker-compose.yml", "utf8");

describe("M40.5e capture supervisor health authentication", () => {
  it("passes the supervisor token into both API and supervisor", () => {
    expect(compose).toContain(
      "SPORTSOS_CAPTURE_SUPERVISOR_TOKEN: ${SPORTSOS_CAPTURE_SUPERVISOR_TOKEN:-}",
    );
  });

  it("authenticates the capture supervisor healthcheck", () => {
    expect(compose).toContain("SPORTSOS_CAPTURE_SUPERVISOR_TOKEN");
    expect(compose).toContain("Authorization:'Bearer '+t");
    expect(compose).toContain("http://localhost:4015/health");
  });

  it("does not expose the supervisor health port on the host", () => {
    const start = compose.indexOf("  capture-supervisor:");
    const end = compose.indexOf("\n  api:", start);
    const block = compose.slice(start, end);

    expect(block).not.toContain("ports:");
  });
});
