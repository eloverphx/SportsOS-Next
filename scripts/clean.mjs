import { rm } from "node:fs/promises";
import { resolve } from "node:path";

const targets = ["apps/api/dist", "apps/dashboard/.next", "packages/core/dist", "coverage"];

await Promise.all(
  targets.map(async (target) => {
    await rm(resolve(process.cwd(), target), { force: true, recursive: true });
  }),
);

console.log("SportsOS build artifacts removed.");
