import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.4 MinIO credential rotation workflow", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/rotate-minio-credentials.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("defaults to preflight only",()=> {
    expect(script).toContain(
      'APPLY="${SPORTSOS_APPLY_ROTATION:-0}"',
    );

    expect(script).toContain(
      "No credential was changed.",
    );
  });

  it("validates current MinIO credentials first",()=> {
    expect(script).toContain(
      "Checking current MinIO credentials",
    );

    expect(script).toContain(
      "MC_HOST_sportsos",
    );

    expect(script).toContain(
      "mc ready sportsos",
    );
  });

  it("backs up environment before rotation",()=> {
    expect(script).toContain(
      ".env.before-minio-rotation",
    );
  });

  it("recreates MinIO before API",()=> {
    const minioIndex =
      script.indexOf(
        "docker compose up -d --force-recreate minio",
      );

    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(minioIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(minioIndex);
  });

  it("verifies new MinIO credential before API recreation",()=> {
    const verifyIndex =
      script.indexOf(
        "Verifying new MinIO credential",
      );

    const apiIndex =
      script.indexOf(
        "docker compose up -d --force-recreate api",
      );

    expect(verifyIndex).toBeGreaterThan(-1);
    expect(apiIndex).toBeGreaterThan(verifyIndex);
  });

  it("does not print the new secret",()=> {
    expect(script).not.toContain(
      'echo "$NEW_SECRET"',
    );
  });
});
