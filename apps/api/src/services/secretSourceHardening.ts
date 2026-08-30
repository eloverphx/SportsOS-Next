import fs from "node:fs";
import path from "node:path";

export type SecretSourceCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type SecretSourceHardeningInput = {
  root: string;
};

export type SecretSourceHardeningResult = {
  ready: boolean;
  checks: SecretSourceCheck[];
};

function modeString(
  file: string,
): string | null {
  try {
    const mode =
      fs.statSync(file).mode &
      0o777;

    return mode
      .toString(8)
      .padStart(3, "0");
  } catch {
    return null;
  }
}

export function evaluateSecretSourceHardening(
  input: SecretSourceHardeningInput,
): SecretSourceHardeningResult {
  const checks: SecretSourceCheck[] = [];

  const envFile =
    path.join(
      input.root,
      ".env",
    );

  const gitignore =
    path.join(
      input.root,
      ".gitignore",
    );

  const envMode =
    modeString(
      envFile,
    );

  checks.push({
    id:
      "env:file-present",
    ok:
      fs.existsSync(
        envFile,
      ),
    required:
      true,
    message:
      ".env must be present.",
  });

  checks.push({
    id:
      "env:mode",
    ok:
      envMode ===
      "600",
    required:
      true,
    message:
      envMode
        ? `.env permissions are ${envMode}; expected 600.`
        : ".env permissions could not be read.",
  });

  let ignored =
    false;

  try {
    const source =
      fs.readFileSync(
        gitignore,
        "utf8",
      );

    ignored =
      source
        .split(/\r?\n/)
        .some(
          (line) =>
            line.trim() ===
              ".env" ||
            line.trim() ===
              ".env*" ||
            line.trim() ===
              "*.env",
        );
  } catch {
    ignored =
      false;
  }

  checks.push({
    id:
      "env:gitignored",
    ok:
      ignored,
    required:
      true,
    message:
      ignored
        ? ".env is covered by .gitignore."
        : ".env is not covered by .gitignore.",
  });

  const duplicateCandidates = [
    ".env.local",
    ".env.production",
    ".env.development",
    ".env.override",
  ];

  const duplicates =
    duplicateCandidates.filter(
      (file) =>
        fs.existsSync(
          path.join(
            input.root,
            file,
          ),
        ),
    );

  checks.push({
    id:
      "env:no-duplicate-sources",
    ok:
      duplicates.length ===
      0,
    required:
      true,
    message:
      duplicates.length === 0
        ? "No alternate environment source files detected."
        : `Alternate environment sources detected: ${duplicates.join(", ")}`,
  });

  return {
    ready:
      checks
        .filter(
          (check) =>
            check.required,
        )
        .every(
          (check) =>
            check.ok,
        ),
    checks,
  };
}
