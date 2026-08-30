import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.4 shared-contract build-order repair", () => {
  const rootPackage =
    JSON.parse(
      fs.readFileSync(
        new URL(
          "../../../package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as {
      scripts?: {
        typecheck?: string;
        "ci:prepare"?: string;
      };
    };

  const corePackage =
    JSON.parse(
      fs.readFileSync(
        new URL(
          "../../../packages/core/package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as {
      types?: string;
    };

  const realtime =
    fs.readFileSync(
      new URL(
        "../../../packages/core/src/contracts/realtime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("builds shared declarations before workspace typechecking", () => {
    expect(
      rootPackage.scripts?.typecheck,
    ).toBe(
      "npm run ci:prepare && npm run typecheck --workspaces --if-present",
    );
  });

  it("keeps ci:prepare responsible for core/config builds", () => {
    expect(
      rootPackage.scripts?.[
        "ci:prepare"
      ],
    ).toContain(
      "@sportsos/core",
    );

    expect(
      rootPackage.scripts?.[
        "ci:prepare"
      ],
    ).toContain(
      "@sportsos/config",
    );
  });

  it("documents why the build is required", () => {
    expect(
      corePackage.types,
    ).toBe(
      "./dist/index.d.ts",
    );
  });

  it("retains broadcast-session events in core source", () => {
    expect(
      realtime,
    ).toContain(
      '"broadcast-session:updated"',
    );

    expect(
      realtime,
    ).toContain(
      '"broadcast-session:deleted"',
    );
  });
});
