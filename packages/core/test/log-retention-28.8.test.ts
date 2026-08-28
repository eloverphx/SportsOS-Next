import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.8 log retention / rotation", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/log-retention-check.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("checks container log driver and path",()=> {
    expect(script).toContain(
      ".HostConfig.LogConfig.Type",
    );

    expect(script).toContain(
      ".LogPath",
    );
  });

  it("checks container log size",()=> {
    expect(script).toContain(
      "SPORTSOS_MAX_CONTAINER_LOG_MB",
    );

    expect(script).toContain(
      "log size exceeds",
    );
  });

  it("checks compose rotation settings",()=> {
    expect(script).toContain(
      "max-size",
    );

    expect(script).toContain(
      "max-file",
    );
  });

  it("cleans old operations reports",()=> {
    expect(script).toContain(
      "SPORTSOS_REPORT_RETENTION_DAYS",
    );

    expect(script).toContain(
      "-mtime",
    );

    expect(script).toContain(
      "-delete",
    );
  });

  it("does not truncate live Docker logs",()=> {
    expect(script).not.toContain(
      "truncate -s",
    );

    expect(script).not.toContain(
      "> \"$log_path\"",
    );
  });
});
