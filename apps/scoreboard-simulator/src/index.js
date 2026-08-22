import {
  startScoreboardMqttAdapter,
} from "./mqtt-adapter.js";
import http from "node:http";

const API_URL = process.env.API_URL ?? "http://api:4001";
const DEVICE_ID = Number(process.env.SCOREBOARD_DEVICE_ID ?? "0");
const DEVICE_KEY = process.env.SCOREBOARD_DEVICE_KEY ?? "";
const PORT = Number(process.env.PORT ?? "4020");
const HEARTBEAT_INTERVAL_MS = Number(process.env.HEARTBEAT_INTERVAL_MS ?? "30000");
const GAME_POLL_INTERVAL_MS = Number(process.env.GAME_POLL_INTERVAL_MS ?? "2000");

if (!Number.isInteger(DEVICE_ID) || DEVICE_ID <= 0) {
  throw new Error("SCOREBOARD_DEVICE_ID must be a positive integer");
}

if (DEVICE_KEY.length < 20) {
  throw new Error("SCOREBOARD_DEVICE_KEY must contain the device key from SportsOS");
}

let assignedGameId = null;
let game = null;
let connected = false;
let lastHeartbeatAt = null;
let lastGameFetchAt = null;
let lastError = null;
let activeEffect = null;
let activeEffectExpiresAt = 0;
let previousHomeScore = null;
let previousAwayScore = null;
let previousPenaltyIds = new Set();
let hornSequence = 0;
let hornReason = null;

function effectiveRemainingMs(currentGame) {
  if (!currentGame) return 0;
  if (!currentGame.clockRunning || !currentGame.clockStartedAt) {
    return Math.max(0, currentGame.clockRemainingMs);
  }

  return Math.max(
    0,
    currentGame.clockRemainingMs - (Date.now() - new Date(currentGame.clockStartedAt).getTime()),
  );
}

function effectiveIntermissionRemainingMs(currentGame) {
  if (!currentGame) return 0;

  if (!currentGame.intermissionRunning || !currentGame.intermissionStartedAt) {
    return Math.max(0, currentGame.intermissionRemainingMs ?? 0);
  }

  return Math.max(
    0,
    Number(currentGame.intermissionRemainingMs ?? 0) -
      (Date.now() - new Date(currentGame.intermissionStartedAt).getTime()),
  );
}

function penaltyRemainingMs(penalty) {
  if (!penalty.running || !penalty.startedAt) {
    return Math.max(0, penalty.remainingMs);
  }

  return Math.max(0, penalty.remainingMs - (Date.now() - new Date(penalty.startedAt).getTime()));
}

function formatClock(milliseconds) {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

function state() {
  return {
    deviceId: DEVICE_ID,
    connected,
    assignedGameId,
    lastHeartbeatAt,
    lastGameFetchAt,
    lastError,
    hornSequence,
    hornReason,
    game: game
      ? {
          ...game,
          effectiveClockRemainingMs: effectiveRemainingMs(game),
          effectiveIntermissionRemainingMs: effectiveIntermissionRemainingMs(game),
          formattedClock: formatClock(
            game.gamePhase === "INTERMISSION"
              ? effectiveIntermissionRemainingMs(game)
              : effectiveRemainingMs(game),
          ),
          displayMode: game.gamePhase === "INTERMISSION" ? "INTERMISSION" : "GAME",
        }
      : null,
  };
}

async function heartbeat() {
  try {
    const response = await fetch(`${API_URL}/public/scoreboard-devices/${DEVICE_ID}/heartbeat`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: DEVICE_KEY }),
    });

    const body = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(body.error ?? `Heartbeat failed (${response.status})`);
    }

    const recovered = !connected;

    connected = true;
    assignedGameId = typeof body.gameId === "number" ? body.gameId : null;
    lastHeartbeatAt = new Date().toISOString();
    lastError = null;

    if (!assignedGameId) {
      game = null;
    } else if (recovered) {
      previousHomeScore = null;
      previousAwayScore = null;
      previousPenaltyIds = new Set();
      activeEffect = null;
      await fetchGame();
    }
  } catch (error) {
    connected = false;
    lastError = error instanceof Error ? error.message : "Heartbeat failed";
  }
}

async function fetchGame() {
  if (!assignedGameId) {
    game = null;
    return;
  }

  try {
    const response = await fetch(`${API_URL}/public/games/${assignedGameId}/scoreboard`, {
      cache: "no-store",
    });

    const body = await response.json().catch(() => ({}));

    if (!response.ok || !body.game) {
      throw new Error(body.error ?? `Game fetch failed (${response.status})`);
    }

    const nextGame = body.game;
    const nextIntermissionMs = effectiveIntermissionRemainingMs(nextGame);

    if (
      previousIntermissionMs !== null &&
      previousIntermissionMs > 0 &&
      nextIntermissionMs === 0 &&
      nextGame.intermissionRunning
    ) {
      hornSequence += 1;
      hornReason = "INTERMISSION_COMPLETE";
      activeEffect = {
        type: "HORN",
        teamName: "Ready for next period",
      };
      activeEffectExpiresAt = Date.now() + 3500;
      console.log("Intermission complete: horn triggered");
    }

    previousIntermissionMs = nextIntermissionMs;

    if (previousHomeScore !== null && nextGame.homeScore > previousHomeScore) {
      activeEffect = { type: "GOAL", teamName: nextGame.homeTeamName };
      activeEffectExpiresAt = Date.now() + 4500;
    } else if (previousAwayScore !== null && nextGame.awayScore > previousAwayScore) {
      activeEffect = { type: "GOAL", teamName: nextGame.awayTeamName };
      activeEffectExpiresAt = Date.now() + 4500;
    }

    const nextPenaltyIds = new Set((nextGame.penalties ?? []).map((penalty) => penalty.id));

    if (previousPenaltyIds.size > 0) {
      for (const id of previousPenaltyIds) {
        if (!nextPenaltyIds.has(id) && !activeEffect) {
          activeEffect = { type: "PENALTY_ENDED", teamName: "Penalty ended" };
          activeEffectExpiresAt = Date.now() + 3000;
          break;
        }
      }
    }

    previousHomeScore = nextGame.homeScore;
    previousAwayScore = nextGame.awayScore;
    previousPenaltyIds = nextPenaltyIds;
    game = nextGame;
    lastGameFetchAt = new Date().toISOString();
    lastError = null;
  } catch (error) {
    lastError = error instanceof Error ? error.message : "Game fetch failed";
  }
}

function html() {
  if (activeEffect && Date.now() >= activeEffectExpiresAt) {
    activeEffect = null;
  }

  const current = state();
  const currentGame = current.game;

  let powerPlay = "";
  if (currentGame) {
    const home = (currentGame.penalties ?? []).filter((penalty) => penalty.side === "home").length;
    const away = (currentGame.penalties ?? []).filter((penalty) => penalty.side === "away").length;

    if (home !== away) {
      powerPlay = `<div class="power-play">POWER PLAY · ${
        home < away ? currentGame.homeTeamName : currentGame.awayTeamName
      }</div>`;
    }
  }

  const effectHtml = activeEffect
    ? `<section class="effect"><strong>${
        activeEffect.type === "GOAL"
          ? "GOAL!"
          : activeEffect.type === "HORN"
            ? "HORN"
            : "PENALTY ENDED"
      }</strong><span>${activeEffect.teamName}</span></section>`
    : "";

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="2">
<title>SportsOS Scoreboard Simulator</title>
<style>
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; display:grid; place-items:center; background:#030914; color:#fff; font-family:Inter,system-ui,sans-serif; }
  main { width:min(1100px,96vw); border:1px solid #263958; border-radius:22px; background:#081323; padding:26px; }
  header { display:flex; justify-content:space-between; gap:16px; align-items:center; margin-bottom:24px; }
  .status { border-radius:999px; padding:8px 13px; background:${current.connected ? "#14532d" : "#7f1d1d"}; font-weight:900; }
  .game { display:grid; grid-template-columns:1fr minmax(220px,.8fr) 1fr; gap:18px; align-items:center; text-align:center; }
  .team-logo { width:96px; height:96px; object-fit:contain; }
  .team h2 { min-height:2.4em; display:grid; place-items:center; }
  .score { font-size:clamp(5rem,15vw,11rem); line-height:.9; font-weight:1000; }
  .clock { border:1px solid #314667; border-radius:18px; padding:24px 14px; background:#0d192c; }
  .clock strong { display:block; font-size:clamp(3.5rem,9vw,7rem); font-variant-numeric:tabular-nums; }
  .muted { color:#9eb0c8; }
  .error { color:#fca5a5; }
  .penalties { display:flex; gap:12px; justify-content:center; margin-top:16px; }
  .penalties div { display:grid; gap:4px; padding:12px 16px; border-radius:12px; background:#7f1d1d; }
  .penalties strong { font-size:2rem; font-variant-numeric:tabular-nums; }
  .effect { position:fixed; inset:0; z-index:10; display:grid; place-content:center; justify-items:center; text-align:center; background:rgba(127,29,29,.96); pointer-events:none; }
  .effect strong { font-size:clamp(5rem,20vw,14rem); line-height:.85; }
  .effect span { margin-top:16px; font-size:clamp(2rem,6vw,5rem); font-weight:900; }
  .power-play { margin:0 0 16px; padding:10px 16px; border-radius:12px; text-align:center; background:#facc15; color:#111827; font-weight:1000; }
  .intermission-ready { margin:0 0 16px; padding:12px 16px; border:1px solid #0f766e; border-radius:12px; text-align:center; color:#99f6e4; background:rgba(15,118,110,.18); font-weight:1000; }
  .sound-button { border:1px solid #334155; border-radius:10px; padding:9px 12px; color:#fff; background:#0f172a; font:inherit; font-weight:900; cursor:pointer; }
  @media (max-width:720px) { .game { grid-template-columns:1fr 1fr; } .clock { grid-column:1/-1; grid-row:1; } }
</style>
</head>
<body>
${effectHtml}
<main>
  <header>
    <div>
      <strong>SportsOS Device Simulator #${DEVICE_ID}</strong>
      <div class="muted">API: ${API_URL}</div>
    </div>
    <div style="display:flex;gap:10px;align-items:center">
      <button id="sound-button" class="sound-button" type="button">Enable horn sound</button>
      <span class="status">${current.connected ? "ONLINE" : "OFFLINE"}</span>
    </div>
  </header>
  ${powerPlay}
  ${
    currentGame?.displayMode === "INTERMISSION" &&
    currentGame.effectiveIntermissionRemainingMs === 0
      ? '<div class="intermission-ready">INTERMISSION COMPLETE · READY FOR NEXT PERIOD</div>'
      : ""
  }
  ${
    currentGame
      ? `<section class="game">
          <article class="team">
            <span class="muted">AWAY</span>
            ${currentGame.awayTeamLogoUrl ? `<img class="team-logo" src="${currentGame.awayTeamLogoUrl}" alt="">` : ""}
            <h2>${currentGame.awayTeamName}</h2>
            <div class="score">${currentGame.awayScore}</div>
          </article>
          <section class="clock">
            <span class="muted">${
              currentGame.displayMode === "INTERMISSION"
                ? "INTERMISSION"
                : (currentGame.periodLabel ?? `PERIOD ${currentGame.period}`)
            }</span>
            <strong>${currentGame.formattedClock}</strong>
            <span class="muted">${
              currentGame.displayMode === "INTERMISSION"
                ? currentGame.effectiveIntermissionRemainingMs === 0
                  ? "READY FOR NEXT PERIOD"
                  : currentGame.intermissionRunning
                    ? "RUNNING · PENALTIES PAUSED"
                    : "PAUSED · PENALTIES PAUSED"
                : `${currentGame.clockRunning ? "RUNNING" : "PAUSED"} · ${currentGame.status}`
            }</span>
          </section>
          <article class="team">
            <span class="muted">HOME</span>
            ${currentGame.homeTeamLogoUrl ? `<img class="team-logo" src="${currentGame.homeTeamLogoUrl}" alt="">` : ""}
            <h2>${currentGame.homeTeamName}</h2>
            <div class="score">${currentGame.homeScore}</div>
          </article>
        </section>
        ${
          currentGame.penalties?.length
            ? `<section class="penalties">${currentGame.penalties
                .map(
                  (penalty) =>
                    `<div><b>${penalty.side.toUpperCase()} PENALTY</b><strong>${formatClock(
                      penaltyRemainingMs(penalty),
                    )}</strong><span>${penalty.playerName || penalty.infraction}</span></div>`,
                )
                .join("")}</section>`
            : ""
        }`
      : `<p class="muted">No game is assigned to this scoreboard device.</p>`
  }
  ${current.lastError ? `<p class="error">${current.lastError}</p>` : ""}
</main>
<script>
(() => {
  const enabledKey = "sportsos-simulator-sound-enabled";
  const sequenceKey = "sportsos-simulator-horn-sequence";
  const button = document.getElementById("sound-button");

  function playHorn() {
    const AudioContextClass =
      window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;

    const context = new AudioContextClass();
    const start = context.currentTime + 0.02;

    for (const [frequency, offset, duration] of [
      [190, 0, 1.25],
      [145, 0.08, 1.35],
    ]) {
      const oscillator = context.createOscillator();
      const gain = context.createGain();

      oscillator.type = "square";
      oscillator.frequency.setValueAtTime(frequency, start + offset);
      gain.gain.setValueAtTime(0.0001, start + offset);
      gain.gain.exponentialRampToValueAtTime(
        0.22,
        start + offset + 0.02,
      );
      gain.gain.exponentialRampToValueAtTime(
        0.0001,
        start + offset + duration,
      );

      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(start + offset);
      oscillator.stop(start + offset + duration + 0.03);
    }
  }

  function updateButton() {
    const enabled = localStorage.getItem(enabledKey) === "true";
    button.textContent = enabled ? "Horn sound enabled" : "Enable horn sound";
  }

  button.addEventListener("click", () => {
    const next = localStorage.getItem(enabledKey) !== "true";
    localStorage.setItem(enabledKey, String(next));
    updateButton();

    if (next) playHorn();
  });

  updateButton();

  const sequence = String(${current.hornSequence});
  const previous = localStorage.getItem(sequenceKey);

  if (
    localStorage.getItem(enabledKey) === "true" &&
    previous !== null &&
    previous !== sequence
  ) {
    playHorn();
  }

  localStorage.setItem(sequenceKey, sequence);
})();
</script>
</body>
</html>`;
}

const server = http.createServer((request, response) => {
  if (request.url === "/health") {
    response.writeHead(connected ? 200 : 503, { "content-type": "application/json" });
    response.end(JSON.stringify(state()));
    return;
  }

  if (request.url === "/state") {
    response.writeHead(200, {
      "content-type": "application/json",
      "cache-control": "no-store",
    });
    response.end(JSON.stringify(state()));
    return;
  }

  response.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(html());
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`SportsOS scoreboard simulator listening on ${PORT}`);
  console.log(`Device ID: ${DEVICE_ID}`);
  console.log(`API URL: ${API_URL}`);
});

await heartbeat();
await fetchGame();

setInterval(() => void heartbeat(), HEARTBEAT_INTERVAL_MS);
setInterval(() => void fetchGame(), GAME_POLL_INTERVAL_MS);


const mqttAdapter = startScoreboardMqttAdapter();

process.on("SIGTERM", async () => {
  await mqttAdapter.stop();
  process.exit(0);
});

process.on("SIGINT", async () => {
  await mqttAdapter.stop();
  process.exit(0);
});
