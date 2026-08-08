import Fastify, { type FastifyInstance } from "fastify";
import jwt from "@fastify/jwt";
import { config } from "@sportsos/config";
import { initializeRealtime } from "./infrastructure/realtime.js";
import { registerPlatformPlugins } from "./plugins/index.js";
import { playerRoutes } from "./modules/players/routes.js";
import { rosterRoutes } from "./modules/rosters/routes.js";
import { seasonRoutes } from "./modules/seasons/routes.js";
import { authRoutes } from "./routes/auth.js";
import { mediaRoutes } from "./routes/media.js";
import { organizationRoutes } from "./routes/organizations.js";
import { platformRoutes } from "./routes/platform.js";
import { setupRoutes } from "./routes/setup.js";
import { systemRoutes } from "./routes/system.js";
import { teamRoutes } from "./routes/teams.js";
import { organizationMemberRoutes } from "./routes/organization-members.js";
import { gameRoutes } from "./modules/games/routes.js";
import { gameEventRoutes } from "./modules/game-events/routes.js";
import { penaltyRoutes } from "./modules/penalties/routes.js";
import { scoreboardDeviceRoutes } from "./modules/scoreboard-devices/routes.js";
import {
  recoverGameClocksOnStartup,
  startClockExpirationService,
} from "./modules/games/clock-expiration.js";
import { startGameRuntimeSupervisor } from "./modules/games/runtime-supervisor.js";
import { gameEngineTelemetryRoutes } from "./modules/games/telemetry-routes.js";
import { simulationRoutes } from "./modules/simulation/routes.js";
import type { IdentityTokenPayload } from "./modules/auth/index.js";
import { startRealtimeOutboxDispatcher } from "./infrastructure/realtime-outbox.js";

export interface BuildAppOptions {
  readonly logger?: boolean;
  readonly realtime?: boolean;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: options.logger ?? true,
    bodyLimit: 6 * 1024 * 1024,
    trustProxy: true,
    requestIdHeader: "x-request-id",
  });

  await registerPlatformPlugins(app);

  await app.register(jwt, {
    secret: config.auth.jwtSecret,
  });

  if (options.realtime ?? true) {
    initializeRealtime(app.server, {
      verifyToken: (token) => app.jwt.verify<IdentityTokenPayload>(token),
    });

    let stopClockExpirationService: (() => void) | undefined;
    let stopGameRuntimeSupervisor: (() => void) | undefined;
    let stopRealtimeOutboxDispatcher: (() => void) | undefined;

    app.addHook("onReady", async () => {
      const recovered = await recoverGameClocksOnStartup();
      if (recovered > 0) {
        app.log.info({ recovered }, "Recovered expired game clocks on startup");
      }

      stopRealtimeOutboxDispatcher = startRealtimeOutboxDispatcher({
        onError: (error) => app.log.error({ error }, "Realtime outbox dispatcher failed"),
      });

      stopClockExpirationService = startClockExpirationService({
        onError: (error) => app.log.error({ error }, "Clock expiration service failed"),
      });

      stopGameRuntimeSupervisor = startGameRuntimeSupervisor({
        onError: (error) =>
          app.log.error({ error }, "Game runtime supervisor failed"),
      });
    });

    app.addHook("onClose", async () => {
      stopClockExpirationService?.();
      stopGameRuntimeSupervisor?.();
      stopRealtimeOutboxDispatcher?.();
    });
  }

  await app.register(platformRoutes);
  await app.register(setupRoutes);
  await app.register(authRoutes);
  await app.register(organizationRoutes);
  await app.register(organizationMemberRoutes);
  await app.register(teamRoutes);
  await app.register(playerRoutes);
  await app.register(seasonRoutes);
  await app.register(gameRoutes);
  await app.register(gameEventRoutes);
  await app.register(penaltyRoutes);
  await app.register(scoreboardDeviceRoutes);
  await app.register(rosterRoutes);
  await app.register(mediaRoutes);
  await app.register(systemRoutes);
  await app.register(gameEngineTelemetryRoutes);
  await app.register(simulationRoutes);

  return app;
}
