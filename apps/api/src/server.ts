import { config } from "@sportsos/config";
import { buildApp } from "./app.js";
import { runMigrations } from "./infrastructure/migrations.js";

await runMigrations();

const app = await buildApp();

let shuttingDown = false;

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  app.log.info({ signal }, "Shutdown signal received");

  const forceExitTimer = setTimeout(() => {
    app.log.error("Graceful shutdown timed out");
    process.exit(1);
  }, 10_000);

  forceExitTimer.unref();

  try {
    await app.close();
    app.log.info("API shutdown completed");
    process.exitCode = 0;
  } catch (error) {
    app.log.error({ err: error }, "API shutdown failed");
    process.exitCode = 1;
  }
}

process.once("SIGINT", () => {
  void shutdown("SIGINT");
});

process.once("SIGTERM", () => {
  void shutdown("SIGTERM");
});

try {
  await app.listen({
    host: config.api.host,
    port: config.api.port,
  });

  app.log.info(
    {
      host: config.api.host,
      port: config.api.port,
      environment: config.environment.name,
    },
    "SportsOS API listening",
  );
} catch (error) {
  app.log.fatal({ err: error }, "SportsOS API failed to start");
  process.exitCode = 1;
}
