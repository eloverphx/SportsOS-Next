import { z } from "zod";
import { ROLES } from "../auth/index.js";

export const organizationIdParamsSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
});

export const organizationMemberParamsSchema = z.object({
  organizationId: z.coerce.number().int().positive(),
  userId: z.coerce.number().int().positive(),
});

export const updateOrganizationMemberRoleSchema = z.object({
  role: z.enum([
    ROLES.SYSTEM_ADMIN,
    ROLES.ORGANIZATION_OWNER,
    ROLES.ORGANIZATION_ADMIN,
    ROLES.TEAM_ADMIN,
    ROLES.COACH,
    ROLES.SCOREKEEPER,
    ROLES.BROADCASTER,
    ROLES.VIEWER,
  ]),
});
