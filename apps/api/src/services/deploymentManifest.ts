import {
  execFileSync,
} from "node:child_process";

import fs from "node:fs";
import path from "node:path";

export type DeploymentManifest = {
  generatedAt: string;
  repository: {
    commit: string | null;
    branch: string | null;
    tag: string | null;
    dirty: boolean | null;
  };
  versions: {
    root: string | null;
    api: string | null;
    dashboard: string | null;
    node: string;
  };
  runtime: {
    nodeEnv: string | null;
    port: string | null;
    host: string | null;
    dataDir: string | null;
  };
};

function readJsonVersion(
  file: string,
): string | null {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          file,
          "utf8",
        ),
      ) as {
        version?: string;
      };

    return parsed.version ??
      null;
  } catch {
    return null;
  }
}

function runGit(
  args: string[],
): string | null {
  try {
    return execFileSync(
      "git",
      args,
      {
        cwd:
          process.cwd(),
        encoding:
          "utf8",
        stdio: [
          "ignore",
          "pipe",
          "ignore",
        ],
      },
    )
      .trim() ||
      null;
  } catch {
    return null;
  }
}

export function createDeploymentManifest(): DeploymentManifest {
  const root =
    process.cwd();

  const commit =
    runGit([
      "rev-parse",
      "HEAD",
    ]);

  const branch =
    runGit([
      "branch",
      "--show-current",
    ]);

  const tag =
    runGit([
      "describe",
      "--tags",
      "--exact-match",
      "HEAD",
    ]);

  const status =
    runGit([
      "status",
      "--porcelain",
    ]);

  return {
    generatedAt:
      new Date().toISOString(),
    repository: {
      commit,
      branch,
      tag,
      dirty:
        status === null
          ? null
          : status.length >
            0,
    },
    versions: {
      root:
        readJsonVersion(
          path.resolve(
            root,
            "package.json",
          ),
        ),
      api:
        readJsonVersion(
          path.resolve(
            root,
            "apps/api/package.json",
          ),
        ),
      dashboard:
        readJsonVersion(
          path.resolve(
            root,
            "apps/dashboard/package.json",
          ),
        ),
      node:
        process.version,
    },
    runtime: {
      nodeEnv:
        process.env.NODE_ENV ??
        null,
      port:
        process.env.PORT ??
        null,
      host:
        process.env.HOST ??
        null,
      dataDir:
        process.env.SPORTSOS_DATA_DIR ??
        null,
    },
  };
}
