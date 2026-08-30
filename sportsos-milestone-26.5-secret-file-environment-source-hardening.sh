#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.5-secret-source-hardening-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/secretSourceHardening.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
SCRIPT="scripts/secret-source-audit.sh"
TEST="packages/core/test/secret-source-hardening-26.5.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  ".env" \
  ".gitignore" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$SCRIPT" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$SCRIPT")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
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
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateSecretSourceHardening,
} from "../services/secretSourceHardening.js";`;

if(!s.includes("evaluateSecretSourceHardening")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/secret-source-hardening"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/credential-rotation-readiness",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("26.1 credential rotation readiness route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/secret-source-hardening",
    async () => {
      return {
        success: true,
        data:
          evaluateSecretSourceHardening({
            root:
              process.cwd(),
          }),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Secret Source Audit"
echo "============================================================"

failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

if [[ -f .env ]]; then
  pass ".env present"
else
  fail ".env missing"
fi

if [[ -f .env ]]; then
  mode="$(
    stat -c '%a' .env 2>/dev/null ||
    stat -f '%Lp' .env 2>/dev/null ||
    true
  )"

  if [[ "$mode" == "600" ]]; then
    pass ".env permissions = 600"
  else
    fail ".env permissions = ${mode:-unknown} (expected 600)"
  fi
fi

if git check-ignore -q .env; then
  pass ".env is ignored by git"
else
  fail ".env is NOT ignored by git"
fi

tracked="$(
  git ls-files --error-unmatch .env 2>/dev/null || true
)"

if [[ -z "$tracked" ]]; then
  pass ".env is not tracked"
else
  fail ".env is tracked by git"
fi

duplicates=()

for file in \
  .env.local \
  .env.production \
  .env.development \
  .env.override
do
  [[ -f "$file" ]] && duplicates+=("$file")
done

if (( ${#duplicates[@]} == 0 )); then
  pass "no alternate environment source files"
else
  fail "alternate environment sources detected: ${duplicates[*]}"
fi

for name in \
  JWT_SECRET \
  MYSQL_PASSWORD \
  MINIO_ROOT_PASSWORD
do
  count="$(
    grep -Rsl --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.security-backups \
      --exclude='.env' \
      "^${name}=" . 2>/dev/null |
      wc -l |
      tr -d ' '
  )"

  if [[ "$count" == "0" ]]; then
    pass "${name} not duplicated in repository files"
  else
    fail "${name} appears in ${count} additional repository file(s)"
  fi
done

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Secret source audit FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Secret source audit PASSED."
EOF

chmod +x "$SCRIPT"

cat >> "$DOC" <<'EOF'

## Milestone 26.5 — Secret file / environment source hardening

SportsOS now validates how deployment secrets are sourced.

API:

```text
GET /broadcast-coordinator/secret-source-hardening
```

Host audit:

```text
scripts/secret-source-audit.sh
```

Checks include:

- `.env` exists
- `.env` permissions are `600`
- `.env` is covered by `.gitignore`
- `.env` is not tracked by git
- no alternate environment source files are present
- key secret variables are not duplicated in other repository files

Alternate files that currently block readiness:

```text
.env.local
.env.production
.env.development
.env.override
```

Milestone 26.5 does not modify or print secret values.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.5 secret file / environment source hardening", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/secretSourceHardening.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const audit =
    fs.readFileSync(
      new URL(
        "../../../scripts/secret-source-audit.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("requires restrictive env permissions",()=> {
    expect(service).toContain(
      '"600"',
    );
    expect(audit).toContain(
      "expected 600",
    );
  });

  it("requires env to be gitignored and untracked",()=> {
    expect(service).toContain(
      "env:gitignored",
    );
    expect(audit).toContain(
      "git check-ignore -q .env",
    );
    expect(audit).toContain(
      "git ls-files --error-unmatch .env",
    );
  });

  it("detects alternate environment sources",()=> {
    expect(service).toContain(
      ".env.local",
    );
    expect(service).toContain(
      ".env.production",
    );
    expect(service).toContain(
      ".env.development",
    );
    expect(service).toContain(
      ".env.override",
    );
  });

  it("audits secret duplication without printing values",()=> {
    expect(audit).toContain(
      "JWT_SECRET",
    );
    expect(audit).toContain(
      "MYSQL_PASSWORD",
    );
    expect(audit).toContain(
      "MINIO_ROOT_PASSWORD",
    );
    expect(audit).not.toContain(
      "cat .env",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.5 installed"
echo "============================================================"
echo "Added:"
echo "  - secret source hardening evaluator"
echo "  - .env permission validation"
echo "  - gitignore/untracked validation"
echo "  - duplicate environment source detection"
echo "  - secret duplication audit"
echo "  - read-only hardening API"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  chmod 600 .env"
echo "  bash scripts/secret-source-audit.sh"
echo "  docker compose up -d --build api dashboard"
echo "  curl -fsS http://127.0.0.1:4001/broadcast-coordinator/secret-source-hardening"
echo
echo "Next after green:"
echo "  Milestone 26.6 - Session / Token Invalidation Readiness"
