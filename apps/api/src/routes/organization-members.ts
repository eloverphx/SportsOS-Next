import type { FastifyInstance } from "fastify";
import { audit } from "../lib/audit.js";
import {
  PERMISSIONS,
  ROLES,
  assertRoleAssignmentAllowed,
  requirePermission,
} from "../modules/auth/index.js";
import {
  findOrganizationMember,
  listOrganizationMembers,
  updateOrganizationMemberRole,
} from "../modules/organization-members/repository.js";
import {
  organizationIdParamsSchema,
  organizationMemberParamsSchema,
  updateOrganizationMemberRoleSchema,
} from "../modules/organization-members/schemas.js";

export async function organizationMemberRoutes(app: FastifyInstance): Promise<void> {
  app.get("/organizations/:organizationId/members", async (request, reply) => {
    const parsed = organizationIdParamsSchema.safeParse(request.params);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid organization id",
      });
    }

    await requirePermission(request, {
      permission: PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE,
      organizationId: parsed.data.organizationId,
    });

    const members = await listOrganizationMembers(parsed.data.organizationId);

    return {
      members,
    };
  });

  app.patch("/organizations/:organizationId/members/:userId/role", async (request, reply) => {
    const params = organizationMemberParamsSchema.safeParse(request.params);

    const body = updateOrganizationMemberRoleSchema.safeParse(request.body);

    if (!params.success || !body.success) {
      return reply.code(400).send({
        error: "Invalid organization member role update",
      });
    }

    const identity = await requirePermission(request, {
      permission: PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE,
      organizationId: params.data.organizationId,
    });

    assertRoleAssignmentAllowed(identity, body.data.role);

    const member = await findOrganizationMember(params.data.organizationId, params.data.userId);

    if (!member) {
      return reply.code(404).send({
        error: "Organization member not found",
      });
    }

    if (identity.role !== ROLES.SYSTEM_ADMIN && member.role === ROLES.ORGANIZATION_OWNER) {
      return reply.code(403).send({
        error: "Only a system administrator can modify an organization owner",
      });
    }

    if (identity.userId === params.data.userId && identity.role !== ROLES.SYSTEM_ADMIN) {
      return reply.code(409).send({
        error: "You cannot change your own organization role",
      });
    }

    const updated = await updateOrganizationMemberRole(
      params.data.organizationId,
      params.data.userId,
      body.data.role,
    );

    if (!updated) {
      return reply.code(404).send({
        error: "Organization member not found",
      });
    }

    await audit(identity.sub, "organization.member.role_updated", {
      organizationId: params.data.organizationId,
      userId: params.data.userId,
      previousRole: member.role,
      role: body.data.role,
    });

    return {
      success: true,
      member: {
        ...member,
        role: body.data.role,
      },
    };
  });
}
