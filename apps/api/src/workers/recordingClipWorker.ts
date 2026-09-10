import { pool } from "../infrastructure/database.js";
import { runRecordingClipWorker } from "../services/recordingClipWorker.js";

const controller = new AbortController();

function stop(): void {
  if (!controller.signal.aborted) {
    controller.abort();
  }
}

process.once("SIGINT", stop);
process.once("SIGTERM", stop);

try {
  await runRecordingClipWorker(controller.signal);
} finally {
  await pool.end();
}
