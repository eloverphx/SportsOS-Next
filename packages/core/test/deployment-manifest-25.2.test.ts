import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  createDeploymentManifest,
} from "../../../apps/api/src/services/deploymentManifest";

describe("Milestone 25.2 deployment manifest / version metadata", () => {
  it("creates version and runtime metadata",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.generatedAt,
    ).toBeTruthy();

    expect(
      manifest.versions.node,
    ).toBe(
      process.version,
    );

    expect(
      manifest.versions.root,
    ).toBeTruthy();
  });

  it("includes repository metadata shape",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.repository,
    ).toHaveProperty(
      "commit",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "branch",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "tag",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "dirty",
    );
  });

  it("includes deployment runtime fields",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "nodeEnv",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "port",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "host",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "dataDir",
    );
  });

  it("provides deployment-manifest API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/deployment-manifest"',
    );

    expect(route).toContain(
      "createDeploymentManifest",
    );
  });

  it("does not write deployment state",()=> {
    const service=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/services/deploymentManifest.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(service).not.toContain(
      "writeFileSync",
    );

    expect(service).not.toContain(
      "renameSync",
    );
  });
});
