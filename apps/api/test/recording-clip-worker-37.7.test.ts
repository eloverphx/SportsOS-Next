import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");
const repoRoot = resolve(apiRoot, "../..");

function apiSource(path: string): string {
  return readFileSync(resolve(apiRoot, path), "utf8");
}

function rootSource(path: string): string {
  return readFileSync(resolve(repoRoot, path), "utf8");
}

const migrations = apiSource("src/infrastructure/streaming-foundation-migrations.ts");
const repository = apiSource("src/modules/recording-clip-jobs/repository.ts");
const ffmpeg = apiSource("src/modules/recording-clip-jobs/ffmpeg.ts");
const worker = apiSource("src/services/recordingClipWorker.ts");
const workerEntry = apiSource("src/workers/recordingClipWorker.ts");
const dockerfile = apiSource("Dockerfile");
const compose = rootSource("docker-compose.yml");

describe("Milestone 37.7 durable clip worker", () => {
  it("uses a database lease with stale PROCESSING recovery and SKIP LOCKED", () => {
    expect(migrations).toContain("claimed_at DATETIME(3)");
    expect(repository).toContain("FOR UPDATE SKIP LOCKED");
    expect(repository).toContain("INTERVAL 15 MINUTE");
    expect(repository).toContain("attempt_count = attempt_count + 1");
  });

  it("waits for an attached video media asset before claiming work", () => {
    expect(repository).toContain("JOIN media_assets m");
    expect(repository).toContain("m.media_kind = 'VIDEO'");
    expect(repository).toContain("m.organization_id = j.organization_id");
  });

  it("runs FFmpeg without a shell and with an internal argument array", () => {
    expect(ffmpeg).toContain("spawn(ffmpegPath, args");
    expect(ffmpeg).not.toContain("shell: true");
    expect(ffmpeg).not.toContain("exec(");
  });

  it("stores derived clips in MinIO and inherits source ownership and visibility", () => {
    expect(worker).toContain("minio.getObject");
    expect(worker).toContain("minio.putObject");
    expect(repository).toContain("m.owner_user_id AS source_owner_user_id");
    expect(repository).toContain("m.visibility AS source_visibility");
    expect(repository).toContain("row.source_visibility");
    expect(repository).toContain("row.source_owner_user_id");
    expect(repository).toContain("INSERT INTO media_access_grants");
    expect(repository).toContain("FROM media_access_grants");
  });

  it("retries failed attempts and atomically links a VIDEO media asset on success", () => {
    expect(repository).toContain("nextStatus: RecordingClipJobStatus");
    expect(repository).toContain('? "FAILED"');
    expect(repository).toContain(': "PENDING"');
    expect(repository).toContain("INSERT INTO media_assets");
    expect(repository).toContain("SET status = 'READY'");
    expect(repository).toContain("output_media_asset_id = ?");
  });

  it("ships FFmpeg and runs the worker as a separate Compose process", () => {
    expect(dockerfile).toContain("apt-get install -y --no-install-recommends ffmpeg");
    expect(compose).toContain("clip-worker:");
    expect(compose).toContain('command: ["node", "apps/api/dist/workers/recordingClipWorker.js"]');
    expect(workerEntry).toContain("runRecordingClipWorker");
  });

  it("does not introduce any AI path that can change authoritative event timing", () => {
    expect(worker).not.toContain("game_events");
    expect(worker).not.toContain("recording_event_anchors");
    expect(repository).not.toContain("UPDATE game_events");
    expect(repository).not.toContain("UPDATE recording_event_anchors");
  });
});
