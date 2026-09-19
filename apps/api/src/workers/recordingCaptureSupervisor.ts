import { spawn, type ChildProcess } from "node:child_process";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { buildRecordingCaptureArgs } from "../services/recordingCaptureFfmpeg.js";

interface CaptureEntry {
  readonly gameId: string;
  readonly recordingId: number;
  readonly capturePath: string;
  readonly startedAt: string;
  readonly child: ChildProcess;
  stderrTail: string;
}

const captures = new Map<string, CaptureEntry>();

function ffmpegPath(): string {
  return process.env.SPORTSOS_FFMPEG_PATH?.trim() || process.env.FFMPEG_PATH?.trim() || "ffmpeg";
}

function captureDirectory(): string {
  const dataDir = process.env.SPORTSOS_DATA_DIR ?? path.resolve(process.cwd(), "data");
  return path.join(dataDir, "recordings", "in-progress");
}

function safeGameId(gameId: string): string {
  return gameId.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function expectedToken(): string {
  return process.env.SPORTSOS_CAPTURE_SUPERVISOR_TOKEN?.trim() ?? "";
}

function authorized(request: IncomingMessage): boolean {
  const token = expectedToken();

  if (!token) {
    return true;
  }

  return request.headers.authorization === `Bearer ${token}`;
}

function sendJson(response: ServerResponse, status: number, value: unknown): void {
  const body = JSON.stringify(value);

  response.statusCode = status;
  response.setHeader("content-type", "application/json");
  response.setHeader("content-length", Buffer.byteLength(body));
  response.end(body);
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;

  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;

    if (size > 64 * 1024) {
      throw new Error("Request body is too large.");
    }

    chunks.push(buffer);
  }

  const body = Buffer.concat(chunks).toString("utf8");

  return body ? JSON.parse(body) : {};
}

function session(entry: CaptureEntry) {
  return {
    gameId: entry.gameId,
    recordingId: entry.recordingId,
    capturePath: entry.capturePath,
    running: entry.child.exitCode === null,
    exitCode: entry.child.exitCode,
    startedAt: entry.startedAt,
  };
}

async function startCapture(input: {
  gameId: string;
  recordingId: number;
  sourceUrl: string;
}): Promise<CaptureEntry> {
  const current = captures.get(input.gameId);

  if (current) {
    if (current.recordingId === input.recordingId && current.child.exitCode === null) {
      return current;
    }

    throw new Error(`Capture session already exists for game ${input.gameId}.`);
  }

  const directory = captureDirectory();
  await mkdir(directory, { recursive: true });

  const fileName =
    `recording-${input.recordingId}-game-${safeGameId(input.gameId)}-` +
    `${Date.now()}.capture.mkv`;

  const capturePath = path.join(directory, fileName);

  const child = spawn(ffmpegPath(), buildRecordingCaptureArgs(input.sourceUrl, capturePath), {
    shell: false,
    stdio: ["ignore", "ignore", "pipe"],
    env: process.env,
  });

  const entry: CaptureEntry = {
    gameId: input.gameId,
    recordingId: input.recordingId,
    capturePath,
    startedAt: new Date().toISOString(),
    child,
    stderrTail: "",
  };

  child.stderr?.on("data", (chunk: Buffer) => {
    entry.stderrTail = (entry.stderrTail + chunk.toString("utf8")).slice(-16_000);
  });

  await new Promise<void>((resolve, reject) => {
    child.once("spawn", resolve);
    child.once("error", reject);
  });

  captures.set(input.gameId, entry);

  console.info(
    JSON.stringify({
      message: "Recording capture supervisor started capture",
      gameId: input.gameId,
      recordingId: input.recordingId,
      capturePath,
      pid: child.pid,
    }),
  );

  return entry;
}

async function stopEntry(entry: CaptureEntry): Promise<void> {
  if (entry.child.exitCode !== null) {
    return;
  }

  entry.child.kill("SIGTERM");

  await new Promise<void>((resolve) => {
    let settled = false;

    const finish = () => {
      if (settled) return;
      settled = true;
      resolve();
    };

    entry.child.once("close", finish);

    const timer = setTimeout(() => {
      if (entry.child.exitCode === null) {
        entry.child.kill("SIGKILL");
      }

      finish();
    }, 10_000);

    timer.unref();
  });
}

async function stopCapture(gameId: string): Promise<CaptureEntry | null> {
  const entry = captures.get(gameId);

  if (!entry) {
    return null;
  }

  await stopEntry(entry);
  captures.delete(gameId);

  console.info(
    JSON.stringify({
      message: "Recording capture supervisor stopped capture",
      gameId,
      recordingId: entry.recordingId,
      capturePath: entry.capturePath,
      exitCode: entry.child.exitCode,
    }),
  );

  return entry;
}

const server = createServer(async (request, response) => {
  try {
    if (!authorized(request)) {
      sendJson(response, 401, { error: "Unauthorized" });
      return;
    }

    const url = new URL(request.url ?? "/", "http://localhost");

    if (request.method === "GET" && url.pathname === "/health") {
      sendJson(response, 200, {
        healthy: true,
        activeCaptures: [...captures.values()].filter((entry) => entry.child.exitCode === null)
          .length,
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/sessions") {
      sendJson(response, 200, {
        sessions: [...captures.values()].map(session),
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/start") {
      const body = (await readJson(request)) as {
        gameId?: unknown;
        recordingId?: unknown;
        sourceUrl?: unknown;
      };

      const gameId = typeof body.gameId === "string" ? body.gameId.trim() : "";
      const recordingId = typeof body.recordingId === "number" ? body.recordingId : Number.NaN;
      const sourceUrl = typeof body.sourceUrl === "string" ? body.sourceUrl.trim() : "";

      if (!gameId || !Number.isSafeInteger(recordingId) || recordingId <= 0 || !sourceUrl) {
        sendJson(response, 400, { error: "Invalid capture start request." });
        return;
      }

      try {
        const entry = await startCapture({
          gameId,
          recordingId,
          sourceUrl,
        });

        sendJson(response, 200, session(entry));
      } catch (error) {
        sendJson(response, 409, {
          error: error instanceof Error ? error.message : String(error),
        });
      }

      return;
    }

    if (request.method === "POST" && url.pathname === "/stop") {
      const body = (await readJson(request)) as {
        gameId?: unknown;
      };

      const gameId = typeof body.gameId === "string" ? body.gameId.trim() : "";

      if (!gameId) {
        sendJson(response, 400, { error: "Game ID is required." });
        return;
      }

      const entry = await stopCapture(gameId);

      if (!entry) {
        sendJson(response, 404, { error: "Capture session not found." });
        return;
      }

      sendJson(response, 200, {
        gameId: entry.gameId,
        recordingId: entry.recordingId,
        capturePath: entry.capturePath,
        stderrTail: entry.stderrTail,
        exitCode: entry.child.exitCode,
      });

      return;
    }

    sendJson(response, 404, { error: "Not found" });
  } catch (error) {
    console.error(
      JSON.stringify({
        message: "Recording capture supervisor request failed",
        error: error instanceof Error ? error.message : String(error),
      }),
    );

    sendJson(response, 500, { error: "Capture supervisor request failed." });
  }
});

const port = Number.parseInt(process.env.PORT ?? "4015", 10);
const host = process.env.HOST?.trim() || "0.0.0.0";

server.listen(port, host, () => {
  console.info(
    JSON.stringify({
      message: "Recording capture supervisor listening",
      host,
      port,
    }),
  );
});

let shuttingDown = false;

async function shutdown(): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;

  /*
   * Deliberately stop existing children but DO NOT recreate them.
   * Their durable capture files remain available for orphan recovery.
   */
  await Promise.all(
    [...captures.values()].map(async (entry) => {
      await stopEntry(entry).catch(() => undefined);
    }),
  );

  captures.clear();

  server.close(() => process.exit(0));

  const timer = setTimeout(() => process.exit(0), 12_000);
  timer.unref();
}

process.once("SIGINT", () => {
  void shutdown();
});

process.once("SIGTERM", () => {
  void shutdown();
});
