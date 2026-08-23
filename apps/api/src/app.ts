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
import { registerScoreboardDeviceEnrollmentRoutes } from "./routes/scoreboardDeviceEnrollment.js";
import { registerScoreboardFirmwareReleaseRoutes } from "./routes/scoreboardFirmwareReleases.js";
import { registerScoreboardFirmwareArtifactRoutes } from "./routes/scoreboardFirmwareArtifacts.js";
import { registerScoreboardFirmwareDeploymentStatusRoutes } from "./routes/scoreboardFirmwareDeploymentStatus.js";
import { registerScoreboardFirmwareRolloutRoutes } from "./routes/scoreboardFirmwareRollouts.js";
import { registerScoreboardControlAuditRoutes } from "./routes/scoreboardControlAudit.js";
import { registerScoreboardControlPolicyRoutes } from "./routes/scoreboardControlPolicy.js";
import { startScoreboardReadinessIncidentMonitor } from "./services/scoreboardReadinessIncidentMonitor.js";
import { registerScoreboardDeviceCommissioningRoutes } from "./routes/scoreboardDeviceCommissioning.js";
import { registerGameDayHardwarePreflightRoutes } from "./routes/gameDayHardwarePreflight.js";
import { registerBroadcastSessionProfileRoutes } from "./routes/broadcastSessionProfiles.js";
import { registerStreamDestinationProfileRoutes } from "./routes/streamDestinationProfiles.js";
import { registerEncoderSessionRoutes } from "./routes/encoderSessions.js";

import { scoreboardDevicesRoutes } from "./routes/scoreboardDevices.js";

export interface BuildAppOptions {
  readonly logger?: boolean;
  readonly realtime?: boolean;
  /**
   * Limits route registration for focused HTTP contract tests.
   * Production/default behavior remains "all".
   */
  readonly routeScope?: "all" | "platform";
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: options.logger ?? true,
    bodyLimit: 6 * 1024 * 1024,
    trustProxy: true,
    requestIdHeader: "x-request-id",
  });

  await registerPlatformPlugins(app);

  await app.register(scoreboardDevicesRoutes);
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

  if ((options.routeScope ?? "all") === "all") {
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
  await app.register(registerScoreboardDeviceCommissioningRoutes);
  await app.register(registerGameDayHardwarePreflightRoutes);
  await app.register(registerBroadcastSessionProfileRoutes);
  await app.register(registerStreamDestinationProfileRoutes);
  await app.register(registerEncoderSessionRoutes);
  }

  await registerScoreboardDeviceEnrollmentRoutes(app);
  await registerScoreboardFirmwareReleaseRoutes(app);
  await registerScoreboardFirmwareArtifactRoutes(app);
  await registerScoreboardFirmwareDeploymentStatusRoutes(app);
  await registerScoreboardFirmwareRolloutRoutes(app);

    await registerScoreboardControlAuditRoutes(app);

  await registerScoreboardControlPolicyRoutes(app);

  const stopScoreboardReadinessIncidentMonitor =
    startScoreboardReadinessIncidentMonitor(
      app,
    );

  app.addHook(
    "onClose",
    async () => {
      stopScoreboardReadinessIncidentMonitor();
    },
  );

return app;
}
