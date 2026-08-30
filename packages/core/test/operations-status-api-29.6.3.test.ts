import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.6.3 operations status registration",
  () => {
    const app =
      fs.readFileSync(
        "apps/api/src/app.ts",
        "utf8",
      );

    const route =
      fs.readFileSync(
        "apps/api/src/routes/operationsStatus.ts",
        "utf8",
      );

    it("registers the operations route plugin in app.ts", () => {
      expect(app).toContain(
        "registerOperationsStatusRoutes",
      );

      expect(app).toContain(
        "await app.register(registerOperationsStatusRoutes);",
      );
    });

    it("imports the operations route module", () => {
      expect(
        app.includes(
          'from "./routes/operationsStatus.js"',
        ) ||
          app.includes(
            'from "./routes/operationsStatus"',
          ),
      ).toBe(true);
    });

    it("uses the deployment namespace", () => {
      expect(route).toContain(
        "/deployment/operations/status",
      );
    });

    it("remains disabled by default", () => {
      expect(route).toContain(
        "SPORTSOS_OPERATIONS_STATUS_API_ENABLED",
      );
      expect(route).toContain(
        'process.env.SPORTSOS_OPERATIONS_STATUS_API_ENABLED ===',
      );
    });

    it("requires constant-time bearer validation", () => {
      expect(route).toContain(
        "SPORTSOS_OPERATIONS_STATUS_TOKEN",
      );
      expect(route).toContain("timingSafeEqual");
      expect(route).toContain(
        "expectedToken.length < 32",
      );
    });

    it("reads only the sanitized operations snapshot", () => {
      expect(route).toContain(
        "/app/data/operations-status/latest.json",
      );
      expect(route).not.toContain(
        "operations-runs",
      );
      expect(route).not.toContain(
        "backups/mysql",
      );
    });

    it("prevents response caching", () => {
      expect(route).toContain(
        '"Cache-Control", "no-store"',
      );
    });
  },
);
