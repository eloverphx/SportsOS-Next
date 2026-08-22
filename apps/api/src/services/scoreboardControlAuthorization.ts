import type { FastifyRequest } from "fastify";

export type ScoreboardControlPermission =
  | "CONTROL_POLICY_READ"
  | "CONTROL_POLICY_WRITE";

type Principal = {
  userId: string | null;
  roles: string[];
};

const READ_ROLES = new Set([
  "ADMIN",
  "SUPER_ADMIN",
  "ORGANIZATION_ADMIN",
  "TOURNAMENT_DIRECTOR",
  "SCOREKEEPER",
  "OPERATOR",
]);

const WRITE_ROLES = new Set([
  "ADMIN",
  "SUPER_ADMIN",
  "ORGANIZATION_ADMIN",
  "TOURNAMENT_DIRECTOR",
  "OPERATOR",
]);

function normalizeRole(value: unknown): string | null {
  if (typeof value !== "string") return null;

  const normalized = value
    .trim()
    .replace(/[\s-]+/g, "_")
    .toUpperCase();

  return normalized || null;
}

function collectRoles(source: unknown): string[] {
  if (typeof source !== "object" || source === null) return [];

  const object = source as Record<string, unknown>;
  const candidates = [object.role, object.roles, object.permissions];
  const roles = new Set<string>();

  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      for (const value of candidate) {
        const role = normalizeRole(value);
        if (role) roles.add(role);
      }
      continue;
    }

    const role = normalizeRole(candidate);
    if (role) roles.add(role);
  }

  return [...roles];
}

export function getScoreboardControlPrincipal(
  request: FastifyRequest,
): Principal {
  const extended = request as FastifyRequest & {
    user?: unknown;
    auth?: unknown;
    session?: unknown;
  };

  const roles = new Set<string>();
  let userId: string | null = null;

  for (const source of [
    extended.user,
    extended.auth,
    extended.session,
  ]) {
    if (typeof source !== "object" || source === null) continue;

    for (const role of collectRoles(source)) roles.add(role);

    if (!userId) {
      const object = source as Record<string, unknown>;
      const candidate = object.userId ?? object.id ?? object.sub;
      if (typeof candidate === "string" && candidate.trim()) {
        userId = candidate.trim();
      }
    }
  }

  return { userId, roles: [...roles] };
}

export function hasScoreboardControlPermission(
  request: FastifyRequest,
  permission: ScoreboardControlPermission,
): boolean {
  const principal = getScoreboardControlPrincipal(request);

  const allowed =
    permission === "CONTROL_POLICY_WRITE"
      ? WRITE_ROLES
      : READ_ROLES;

  return principal.roles.some((role) => allowed.has(role));
}
