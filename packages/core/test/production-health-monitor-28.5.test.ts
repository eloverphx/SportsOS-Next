import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.5 production health monitoring", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/production-health-monitor.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("checks production containers",()=> {
    for (
      const name
      of [
        "sportsos_api",
        "sportsos_dashboard",
        "sportsos_mysql",
        "sportsos_redis",
        "sportsos_mqtt",
        "sportsos_minio",
      ]
    ) {
      expect(script).toContain(name);
    }
  });

  it("checks local dependency health",()=> {
    expect(script).toContain(
      "http://127.0.0.1:4001/health",
    );

    expect(script).toContain(
      "allOnline",
    );
  });

  it("checks external health and realtime",()=> {
    expect(script).toContain(
      "scripts/external-health-check.sh",
    );

    expect(script).toContain(
      "scripts/external-realtime-check.sh",
    );
  });

  it("checks disk utilization",()=> {
    expect(script).toContain(
      "disk-usage below 90%",
    );

    expect(script).toContain(
      "df -P",
    );
  });

  it("writes protected reports",()=> {
    expect(script).toContain(
      "data/operations-health",
    );

    expect(script).toContain(
      "latest.txt",
    );

    expect(script).toContain(
      "chmod 600",
    );
  });
});
