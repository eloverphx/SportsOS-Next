#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
cd "$ROOT"
SERVICE="apps/api/src/services/goLiveSession.ts"
ROUTE="apps/api/src/routes/goLiveSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
for f in "$SERVICE" "$ROUTE" "$PANEL"; do [[ -f "$f" ]] || { echo "ERROR: missing $f"; exit 1; }; done
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/.game-engine-backups/milestone-21.3-$STAMP"
mkdir -p "$BACKUP/apps/api/src/services" "$BACKUP/apps/api/src/routes" "$BACKUP/apps/dashboard/app/scoreboards/operations"
cp -a "$SERVICE" "$BACKUP/$SERVICE"; cp -a "$ROUTE" "$BACKUP/$ROUTE"; cp -a "$PANEL" "$BACKUP/$PANEL"

node <<'NODE'
const fs=require("fs"); const f="apps/api/src/services/goLiveSession.ts"; let s=fs.readFileSync(f,"utf8");
if(!s.includes("autoArmEnabled: boolean;")) s=s.replace("  startWindowLateMinutes: number;\n};","  startWindowLateMinutes: number;\n  autoArmEnabled: boolean;\n  autoArmLeadMinutes: number;\n};");
s=s.replaceAll("    startWindowLateMinutes:\n      15,\n  };","    startWindowLateMinutes:\n      15,\n    autoArmEnabled:\n      false,\n    autoArmLeadMinutes:\n      30,\n  };");
s=s.replaceAll("    startWindowLateMinutes:\n      15,\n  });","    startWindowLateMinutes:\n      15,\n    autoArmEnabled:\n      false,\n    autoArmLeadMinutes:\n      30,\n  });");
if(!s.includes("export function configureGoLiveAutoArm")) {
 const i=s.indexOf("export function evaluateGoLiveStartWindow("); if(i<0) throw Error("start-window evaluator missing");
 const x=`export function configureGoLiveAutoArm(input: { gameId: string; enabled: boolean; leadMinutes?: number; }): GoLiveSession {
  const current = getGoLiveSession(input.gameId);
  const lead = Number.isFinite(input.leadMinutes) ? Math.max(0, Math.min(240, Math.floor(Number(input.leadMinutes)))) : current.autoArmLeadMinutes;
  return replaceSession({ ...current, autoArmEnabled: input.enabled, autoArmLeadMinutes: lead, lastTransitionAt: new Date().toISOString() });
}

export function evaluateGoLiveCountdown(gameId: string, now = new Date()) {
  const session = getGoLiveSession(gameId);
  if (!session.scheduledStartAt) return { scheduled:false, scheduledStartAt:null, secondsUntilStart:null, autoArmAt:null, autoArmDue:false };
  const start = Date.parse(session.scheduledStartAt);
  const arm = start - session.autoArmLeadMinutes * 60000;
  const nowMs = now.getTime();
  return { scheduled:true, scheduledStartAt:session.scheduledStartAt, secondsUntilStart:Math.ceil((start-nowMs)/1000), autoArmAt:new Date(arm).toISOString(), autoArmDue:session.autoArmEnabled && nowMs >= arm && nowMs <= start };
}

`;
 s=s.slice(0,i)+x+s.slice(i);
}
fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs"); const f="apps/api/src/routes/goLiveSessions.ts"; let s=fs.readFileSync(f,"utf8");
if(!s.includes("configureGoLiveAutoArm,")) s=s.replace("  configureGoLiveSchedule,\n  evaluateGoLiveStartWindow,","  configureGoLiveAutoArm,\n  configureGoLiveSchedule,\n  evaluateGoLiveCountdown,\n  evaluateGoLiveStartWindow,");
if(!s.includes('"/go-live-sessions/:gameId/auto-arm"')) {
 const i=s.indexOf('  app.put(\n    "/go-live-sessions/:gameId/schedule",'); if(i<0) throw Error("schedule route missing");
 const x=`  app.put(
    "/go-live-sessions/:gameId/auto-arm",
    async (request, reply) => {
      const params = request.params as { gameId?: string };
      const body = request.body as { enabled?: boolean; leadMinutes?: number };
      const gameId = params.gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      const session = configureGoLiveAutoArm({ gameId, enabled:body.enabled === true, leadMinutes:body.leadMinutes });
      return { success:true, data:{ session, countdown:evaluateGoLiveCountdown(gameId) } };
    },
  );

  app.get(
    "/go-live-sessions/:gameId/countdown",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      return { success:true, data:{ session:getGoLiveSession(gameId), countdown:evaluateGoLiveCountdown(gameId) } };
    },
  );

  app.post(
    "/go-live-sessions/:gameId/auto-arm/evaluate",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) return reply.code(400).send({ success:false, error:"Game ID is required." });
      const countdown = evaluateGoLiveCountdown(gameId);
      const current = getGoLiveSession(gameId);
      if (countdown.autoArmDue && ["IDLE","COMPLETE","ERROR"].includes(current.status)) {
        const preflight = evaluateStreamingReadiness(gameId);
        if (preflight.ready) return { success:true, data:{ autoArmed:true, session:armGoLiveSession(gameId), countdown, preflight } };
        return reply.code(409).send({ success:false, error:"Auto-arm is due but streaming readiness preflight failed.", data:{ autoArmed:false, session:current, countdown, preflight } });
      }
      return { success:true, data:{ autoArmed:false, session:current, countdown } };
    },
  );

`;
 s=s.slice(0,i)+x+s.slice(i);
}
fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs"); const f="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"; let s=fs.readFileSync(f,"utf8");
if(!s.includes("autoArmEnabled: boolean;")) s=s.replace("  startWindowLateMinutes: number;\n};","  startWindowLateMinutes: number;\n  autoArmEnabled: boolean;\n  autoArmLeadMinutes: number;\n};");
if(!s.includes("const [autoArmEnabled")) {
 const marker="  async function saveGoLiveSchedule() {"; const i=s.indexOf(marker); if(i<0) throw Error("schedule function missing");
 const x=`  const [autoArmEnabled, setAutoArmEnabled] = useState(false);
  const [autoArmLeadMinutes, setAutoArmLeadMinutes] = useState(30);
  const [goLiveCountdown, setGoLiveCountdown] = useState<{ scheduled:boolean; scheduledStartAt:string|null; secondsUntilStart:number|null; autoArmAt:string|null; autoArmDue:boolean } | null>(null);

  async function saveAutoArmSettings() {
    const normalized = gameId.trim(); if (!normalized) return;
    setBusy(true);
    try {
      const response = await fetch(\`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/auto-arm\`, { method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({enabled:autoArmEnabled,leadMinutes:autoArmLeadMinutes}) });
      const json = await response.json(); if (!response.ok) throw new Error(json?.error ?? "Auto-arm save failed.");
      setGoLiveSession(json?.data?.session ?? null); setGoLiveCountdown(json?.data?.countdown ?? null); setError(null);
    } catch (e) { setError(e instanceof Error ? e.message : "Unable to save auto-arm settings."); } finally { setBusy(false); }
  }

  async function evaluateAutoArm() {
    const normalized=gameId.trim(); if(!normalized) return;
    const response=await fetch(\`\${API_BASE}/go-live-sessions/\${encodeURIComponent(normalized)}/auto-arm/evaluate\`,{method:"POST"});
    const json=await response.json(); setGoLiveSession(json?.data?.session ?? null); setGoLiveCountdown(json?.data?.countdown ?? null);
    if(!response.ok) setError(json?.error ?? "Auto-arm evaluation failed.");
  }

`;
 s=s.slice(0,i)+x+s.slice(i);
}
if(!s.includes("Auto-Arm Countdown")) {
 const anchor='        <div className="mt-4 flex flex-wrap gap-3">'; const base=s.indexOf("Production Go-Live"); const i=s.indexOf(anchor,base); if(i<0) throw Error("go-live actions missing");
 const x=`        <div className="mt-4 rounded border border-slate-800 p-3">
          <div className="text-sm font-semibold">Auto-Arm Countdown</div>
          <div className="mt-3 flex flex-wrap items-end gap-3">
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={autoArmEnabled} onChange={(e) => setAutoArmEnabled(e.target.checked)} />Enable scheduled auto-arm</label>
            <label className="text-sm"><span className="text-xs text-slate-500">Auto-Arm Lead (minutes)</span><input type="number" min={0} max={240} value={autoArmLeadMinutes} onChange={(e) => setAutoArmLeadMinutes(Number(e.target.value)||0)} className="mt-1 block rounded-lg border border-slate-700 bg-slate-950 px-3 py-2" /></label>
            <button type="button" disabled={busy || !gameId.trim()} onClick={() => void saveAutoArmSettings()} className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50">Save Auto-Arm</button>
            <button type="button" disabled={busy || !gameId.trim()} onClick={() => void evaluateAutoArm()} className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50">Evaluate Auto-Arm</button>
          </div>
          {goLiveCountdown && <div className="mt-3 text-xs text-slate-400">Countdown: {goLiveCountdown.secondsUntilStart == null ? "Not scheduled" : \`\${goLiveCountdown.secondsUntilStart}s\`} · Auto-arm due: {goLiveCountdown.autoArmDue ? "YES" : "NO"}</div>}
        </div>

`;
 s=s.slice(0,i)+x+s.slice(i);
}
fs.writeFileSync(f,s);
NODE

cat >> docs/GO-LIVE-OPERATIONS.md <<'EOF'

## Milestone 21.3 — Scheduled auto-arm and operator countdown

Scheduled sessions may optionally auto-arm before start. The default lead is 30 minutes and is clamped to 0–240 minutes. Auto-arm remains readiness-gated and never starts FFmpeg automatically.

Endpoints:

```text
PUT  /go-live-sessions/:gameId/auto-arm
GET  /go-live-sessions/:gameId/countdown
POST /go-live-sessions/:gameId/auto-arm/evaluate
```
EOF

mkdir -p packages/core/test
cat > packages/core/test/scheduled-auto-arm-countdown-21.3.test.ts <<'EOF'
import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 21.3 scheduled auto-arm / operator countdown", () => {
  const service=fs.readFileSync(new URL("../../../apps/api/src/services/goLiveSession.ts",import.meta.url),"utf8");
  const route=fs.readFileSync(new URL("../../../apps/api/src/routes/goLiveSessions.ts",import.meta.url),"utf8");
  const panel=fs.readFileSync(new URL("../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",import.meta.url),"utf8");

  it("persists auto-arm configuration",()=>{ expect(service).toContain("autoArmEnabled"); expect(service).toContain("autoArmLeadMinutes"); });
  it("calculates countdown",()=>{ expect(service).toContain("evaluateGoLiveCountdown"); expect(service).toContain("secondsUntilStart"); expect(service).toContain("autoArmDue"); });
  it("provides APIs",()=>{ expect(route).toContain('"/go-live-sessions/:gameId/auto-arm"'); expect(route).toContain('"/go-live-sessions/:gameId/countdown"'); expect(route).toContain('"/go-live-sessions/:gameId/auto-arm/evaluate"'); });
  it("gates auto-arm on readiness",()=>expect(route).toContain("Auto-arm is due but streaming readiness preflight failed."));
  it("provides operator controls",()=>{ expect(panel).toContain("Auto-Arm Countdown"); expect(panel).toContain("Enable scheduled auto-arm"); expect(panel).toContain("Save Auto-Arm"); });
});
EOF

echo "Milestone 21.3 installed."
echo "Backup: $BACKUP"
echo "Run: npm run typecheck && npm test"
echo "Then: docker compose up -d --build api dashboard && npm run test:e2e:docker"
