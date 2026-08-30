import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.2 JWT secret rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-jwt-secret.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to preflight-only behavior",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROTATION:-0}"',
    );

    expect(script).toContain(
      "No credential was changed.",
    );
  });

  it("requires explicit rotation opt-in",()=> {
    expect(script).toContain(
      "SPORTSOS_APPLY_ROTATION=1",
    );
  });

  it("backs up environment before rotation",()=> {
    expect(script).toContain(
      ".env.before-jwt-rotation",
    );
  });

  it("generates a cryptographically random secret",()=> {
    expect(script).toContain(
      "randomBytes(48)",
    );
  });

  it("does not print the generated secret",()=> {
    expect(script).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });

  it("recreates application containers and checks health",()=> {
    expect(script).toContain(
      "docker compose up -d --force-recreate api dashboard",
    );

    expect(script).toContain(
      "127.0.0.1:4001/health",
    );
  });

  it("documents session invalidation",()=> {
    expect(script).toContain(
      "Existing JWT sessions/tokens",
    );
  });
});
