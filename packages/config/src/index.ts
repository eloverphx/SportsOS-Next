import { createConfig } from "./createConfig.js";

export const config = createConfig();

export { createConfig, type SportsOSConfig } from "./createConfig.js";

export { ConfigurationError, formatConfigurationError } from "./errors.js";

export { sportsOSEnvironmentSchema, type SportsOSEnvironment } from "./schema.js";
