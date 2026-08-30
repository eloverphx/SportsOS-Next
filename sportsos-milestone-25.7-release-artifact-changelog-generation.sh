#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.7-release-artifact-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SCRIPT="scripts/generate-release-artifact.sh"
TEST="packages/core/test/release-artifact-generation-25.7.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "package.json" \
  "scripts/release-smoke-test.sh" \
  "docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md" \
  "docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SCRIPT" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SCRIPT")" "$(dirname "$TEST")"

cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
OUT_DIR="${SPORTSOS_RELEASE_ARTIFACT_DIR:-${ROOT}/release-artifacts}"

cd "$ROOT"

mkdir -p "$OUT_DIR"

VERSION="$(
  node -p "require('./package.json').version"
)"

COMMIT="$(
  git rev-parse HEAD
)"

SHORT_COMMIT="$(
  git rev-parse --short HEAD
)"

BRANCH="$(
  git branch --show-current
)"

TAG="$(
  git describe --tags --exact-match HEAD 2>/dev/null || true
)"

DIRTY="$(
  if [[ -n "$(git status --porcelain)" ]]; then
    echo yes
  else
    echo no
  fi
)"

STAMP="$(
  date +%Y%m%d-%H%M%S
)"

ARTIFACT="${OUT_DIR}/sportsos-release-${VERSION}-${SHORT_COMMIT}-${STAMP}.md"

{
  echo "# SportsOS Release Artifact"
  echo
  echo "Generated: $(date --iso-8601=seconds)"
  echo
  echo "## Release Identity"
  echo
  echo "- Version: ${VERSION}"
  echo "- Commit: ${COMMIT}"
  echo "- Branch: ${BRANCH:-detached}"
  echo "- Tag: ${TAG:-none}"
  echo "- Dirty working tree: ${DIRTY}"
  echo
  echo "## Recent Changes"
  echo
  git log -15 --pretty='- %h %s'
  echo
  echo "## Milestone 23 Acceptance"
  echo
  sed -n '1,220p' docs/MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md
  echo
  echo "## Milestone 24 Acceptance"
  echo
  sed -n '1,260p' docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md
  echo
  echo "## Deployment Verification Commands"
  echo
  echo '```bash'
  echo 'npm run typecheck && npm test'
  echo 'docker compose up -d --build api dashboard'
  echo 'bash scripts/release-smoke-test.sh'
  echo 'npm run test:e2e:docker'
  echo '```'
} > "$ARTIFACT"

echo "Release artifact created:"
echo "  $ARTIFACT"
EOF

chmod +x "$SCRIPT"

cat >> "$DOC" <<'EOF'

## Milestone 25.7 — Release artifact / changelog generation

SportsOS now includes a reproducible release artifact generator:

```text
scripts/generate-release-artifact.sh
```

The generated Markdown artifact includes:

- package version
- full and short git commit
- branch
- exact tag when present
- dirty-working-tree status
- recent git commit history
- Milestone 23 acceptance summary
- Milestone 24 resilience acceptance summary
- deployment verification commands

Default output directory:

```text
release-artifacts/
```

Optional override:

```text
SPORTSOS_RELEASE_ARTIFACT_DIR
```

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/generate-release-artifact.sh
```

The generator is read-only with respect to application and deployment state. It only writes the release artifact file.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.7 release artifact / changelog generation", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/generate-release-artifact.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("captures release identity",()=> {
    expect(script).toContain("git rev-parse HEAD");
    expect(script).toContain("git branch --show-current");
    expect(script).toContain("git describe --tags --exact-match HEAD");
    expect(script).toContain("Dirty working tree");
  });

  it("captures recent changelog history",()=> {
    expect(script).toContain("git log -15");
    expect(script).toContain("## Recent Changes");
  });

  it("includes prior acceptance milestones",()=> {
    expect(script).toContain("MILESTONE-23-BROADCAST-OPERATIONS-ACCEPTANCE.md");
    expect(script).toContain("MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md");
  });

  it("includes deployment verification commands",()=> {
    expect(script).toContain("npm run typecheck && npm test");
    expect(script).toContain("bash scripts/release-smoke-test.sh");
    expect(script).toContain("npm run test:e2e:docker");
  });

  it("writes to release-artifacts by default",()=> {
    expect(script).toContain("release-artifacts");
    expect(script).toContain("SPORTSOS_RELEASE_ARTIFACT_DIR");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.7 installed"
echo "============================================================"
echo "Added:"
echo "  - release artifact generator"
echo "  - version/commit/branch/tag metadata"
echo "  - dirty tree status"
echo "  - recent git changelog"
echo "  - acceptance milestone summaries"
echo "  - deployment verification commands"
echo "  - release artifact output directory"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  bash scripts/generate-release-artifact.sh"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 25.8 - Preflight Deployment Dashboard"
