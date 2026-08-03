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
    initializeRealtime(app.server);
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

  return app;
}
