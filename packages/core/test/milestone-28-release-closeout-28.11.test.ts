import fs from "node:fs";
import {
  describe,
  expect,
  it,
} from "vitest";

describe(
  "Milestone 28 release closeout",
  () => {
    const script =
      fs.readFileSync(
        new URL(
          "../../../scripts/release-milestone-28.sh",
          import.meta.url,
        ),
        "utf8",
      );

    it(
      "requires a passed closeout report",
      () => {
        expect(script).toContain(
          "Operations closeout PASSED.",
        );
      },
    );

    it(
      "defaults to dry-run",
      () => {
        expect(script).toContain(
          'SPORTSOS_APPLY_M28_RELEASE:-0',
        );
      },
    );

    it(
      "uses the milestone 28 completion tag",
      () => {
        expect(script).toContain(
          "sportsos-m28-complete",
        );
      },
    );

    it(
      "blocks runtime and secret locations",
      () => {
        expect(script).toContain(
          ".game-engine-backups",
        );

        expect(script).toContain(
          ".deployment-backups",
        );

        expect(script).toContain(
          ".env",
        );
      },
    );

    it(
      "creates an annotated tag only during apply",
      () => {
        expect(script).toContain(
          'git tag -a "$TAG"',
        );

        expect(script).toContain(
          'if [[ "$APPLY" != "1" ]]',
        );
      },
    );
  },
);
