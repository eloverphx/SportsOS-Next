import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  evaluateRollbackRestoreReadiness,
} from "../../../apps/api/src/services/rollbackRestoreReadiness";

describe("Milestone 25.6 rollback / restore readiness", () => {
  it("passes when required files and directories are available",()=> {
    const root=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-root-",
        ),
      );

    const data=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-data-",
        ),
      );

    const backup=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-backup-",
        ),
      );

    fs.mkdirSync(
      path.join(
        root,
        "scripts",
      ),
      {
        recursive:
          true,
      },
    );

    fs.writeFileSync(
      path.join(
        root,
        "docker-compose.yml",
      ),
      "services: {}",
    );

    fs.writeFileSync(
      path.join(
        root,
        "scripts/release-smoke-test.sh",
      ),
      "#!/bin/sh",
    );

    expect(
      evaluateRollbackRestoreReadiness({
        root,
        dataDir:
          data,
        backupDir:
          backup,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("fails without persistent data directory",()=> {
    const root=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-root-",
        ),
      );

    expect(
      evaluateRollbackRestoreReadiness({
        root,
        dataDir:
          null,
        backupDir:
          null,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("provides rollback readiness API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/rollback-restore-readiness"',
    );

    expect(route).toContain(
      "evaluateRollbackRestoreReadiness",
    );
  });

  it("provides host rollback preflight",()=> {
    const script=
      fs.readFileSync(
        new URL(
          "../../../scripts/release-rollback-preflight.sh",
          import.meta.url,
        ),
        "utf8",
      );

    expect(script).toContain(
      "git rev-parse --verify HEAD",
    );

    expect(script).toContain(
      "Rollback preflight PASSED.",
    );

    expect(script).toContain(
      "does not perform a rollback",
    );
  });
});
