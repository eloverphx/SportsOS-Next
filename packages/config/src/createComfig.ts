import "dotenv/config";

import { EnvSchema } from "./schema.js";

export function createConfig() {
    const env = EnvSchema.parse(process.env);

    return {
        api: {
            host: env.HOST,
            port: env.PORT
        },

        jwt: {
            secret: env.JWT_SECRET
        },

        dashboard: {
            origin: env.DASHBOARD_ORIGIN
        },

        environment: env.NODE_ENV
    };
}
