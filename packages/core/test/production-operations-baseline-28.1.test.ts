import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.1 production operations baseline", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/capture-production-baseline.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("captures release identity",()=> {
    expect(script).toContain(
      "git rev-parse HEAD",
    );

    expect(script).toContain(
      "git describe --tags --always --dirty",
    );
  });

  it("captures container and image state",()=> {
    expect(script).toContain(
      "docker compose ps",
    );

    expect(script).toContain(
      "docker compose images",
    );
  });

  it("captures local and public health",()=> {
    expect(script).toContain(
      "http://127.0.0.1:4001/health",
    );

    expect(script).toContain(
      "https://crashthenet.online",
    );

    expect(script).toContain(
      "https://api.crashthenet.online/health",
    );
  });

  it("redacts known secret assignments",()=> {
    expect(script).toContain(
      "JWT_SECRET=",
    );

    expect(script).toContain(
      "[REDACTED]",
    );

    expect(script).toContain(
      "chmod 600",
    );
  });
});
