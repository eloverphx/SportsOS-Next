import { z } from "zod";

export const EnvSchema = z.object({
    NODE_ENV: z.enum([
        "development",
        "test",
        "production"
    ]).default("development"),

    HOST: z.string(),

    PORT: z.coerce.number(),

    JWT_SECRET: z.string().min(32),

    DASHBOARD_ORIGIN: z.string()
});
