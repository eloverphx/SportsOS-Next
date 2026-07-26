import { buildApp } from './app.js';
import { config } from "@sportsos/config";
import { runMigrations } from './infrastructure/migrations.js';

await runMigrations();
const app = await buildApp();
await app.listen({
    host: config.api.host,
    port: config.api.port
});
