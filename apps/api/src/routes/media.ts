import { randomUUID } from "node:crypto";
import type { FastifyInstance, FastifyRequest } from "fastify";
import mysql from "mysql2/promise";
import { z } from "zod";
import { config } from "@sportsos/config";
import { pool } from "../infrastructure/database.js";
import { minio } from "../infrastructure/minio.js";
import { realtime } from "../infrastructure/realtime.js";
import { audit } from "../lib/audit.js";
import { authUser, requireAuth } from "../lib/auth.js";
import { assertActiveAccount } from "../modules/auth/account-status.js";
import {
  authenticatedIdentity,
  PERMISSIONS,
  requirePermission,
  type AuthenticatedIdentity,
} from "../modules/auth/index.js";
import { canManageMedia, canViewMedia } from "../modules/media-library/access-policy.js";
import {
  findMediaAsset,
  grantMediaAccess,
  listMediaAssetsForIdentity,
  listMediaGrants,
  revokeMediaAccess,
  updateMediaVisibility,
  userBelongsToOrganization,
} from "../modules/media-library/repository.js";
import { logoUrl } from "../lib/media.js";

const uploadSchema = z.object({
  organizationId: z.number().int().positive().nullable().optional(),
  fileName: z.string().trim().min(1).max(255),
  mimeType: z.enum(["image/png", "image/jpeg", "image/webp", "image/svg+xml"]),
  dataBase64: z.string().min(1),
});

const assetIdSchema = z.object({
  id: z.coerce.number().int().positive(),
});

const grantParamsSchema = z.object({
  id: z.coerce.number().int().positive(),
  userId: z.coerce.number().int().positive(),
});

const visibilitySchema = z.object({
  visibility: z.enum(["PRIVATE", "ORGANIZATION", "PUBLIC"]),
});

const grantSchema = z.object({
  permission: z.enum(["VIEW", "EDIT", "MANAGE"]),
});

const listSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

function publicMetadata(
  asset: Awaited<ReturnType<typeof findMediaAsset>> extends infer T ? NonNullable<T> : never,
) {
  return {
    id: asset.id,
    organizationId: asset.organizationId,
    ownerUserId: asset.ownerUserId,
    mediaKind: asset.mediaKind,
    visibility: asset.visibility,
    originalName: asset.originalName,
    mimeType: asset.mimeType,
    sizeBytes: asset.sizeBytes,
    capturedAt: asset.capturedAt,
    durationMs: asset.durationMs,
    checksumSha256: asset.checksumSha256,
    createdAt: asset.createdAt,
    url: `/media/${asset.id}`,
  };
}

async function optionalIdentity(request: FastifyRequest): Promise<AuthenticatedIdentity | null> {
  if (!request.headers.authorization) {
    return null;
  }

  try {
    await request.jwtVerify();
    const identity = authenticatedIdentity(request);
    await assertActiveAccount(identity);
    return identity;
  } catch {
    return null;
  }
}

export async function mediaRoutes(app: FastifyInstance): Promise<void> {
  app.get("/media/assets", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.STREAM_READ,
    });

    const parsed = listSchema.safeParse(request.query);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media list query",
      });
    }

    const assets = await listMediaAssetsForIdentity(
      identity.organizationId,
      identity.userId,
      parsed.data.limit,
    );

    return {
      assets: assets.filter((asset) => canViewMedia(identity, asset)).map(publicMetadata),
    };
  });

  app.get("/media/assets/:id", { preHandler: requireAuth }, async (request, reply) => {
    const parsed = assetIdSchema.safeParse(request.params);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media id",
      });
    }

    const identity = authUser(request);
    const asset = await findMediaAsset(parsed.data.id, identity.userId);

    if (!asset || !canViewMedia(identity, asset)) {
      return reply.code(404).send({
        error: "Media not found",
      });
    }

    return {
      asset: publicMetadata(asset),
    };
  });

  app.patch("/media/assets/:id/visibility", { preHandler: requireAuth }, async (request, reply) => {
    const params = assetIdSchema.safeParse(request.params);
    const body = visibilitySchema.safeParse(request.body);

    if (!params.success || !body.success) {
      return reply.code(400).send({
        error: "Invalid media visibility update",
      });
    }

    const identity = authUser(request);
    const asset = await findMediaAsset(params.data.id, identity.userId);

    if (!asset || !canManageMedia(identity, asset)) {
      return reply.code(404).send({
        error: "Media not found",
      });
    }

    await updateMediaVisibility(asset.id, body.data.visibility);

    await audit(identity.sub, "media.visibility.updated", {
      assetId: asset.id,
      visibility: body.data.visibility,
    });

    return {
      success: true,
      visibility: body.data.visibility,
    };
  });

  app.get("/media/assets/:id/grants", { preHandler: requireAuth }, async (request, reply) => {
    const params = assetIdSchema.safeParse(request.params);

    if (!params.success) {
      return reply.code(400).send({
        error: "Invalid media id",
      });
    }

    const identity = authUser(request);
    const asset = await findMediaAsset(params.data.id, identity.userId);

    if (!asset || !canManageMedia(identity, asset)) {
      return reply.code(404).send({
        error: "Media not found",
      });
    }

    return {
      grants: await listMediaGrants(asset.id),
    };
  });

  app.put(
    "/media/assets/:id/grants/:userId",
    { preHandler: requireAuth },
    async (request, reply) => {
      const params = grantParamsSchema.safeParse(request.params);
      const body = grantSchema.safeParse(request.body);

      if (!params.success || !body.success) {
        return reply.code(400).send({
          error: "Invalid media grant",
        });
      }

      const identity = authUser(request);
      const asset = await findMediaAsset(params.data.id, identity.userId);

      if (!asset || !canManageMedia(identity, asset)) {
        return reply.code(404).send({
          error: "Media not found",
        });
      }

      if (
        asset.organizationId === null ||
        !(await userBelongsToOrganization(params.data.userId, asset.organizationId))
      ) {
        return reply.code(400).send({
          error: "Media can only be shared with an active user in the same organization",
        });
      }

      await grantMediaAccess({
        assetId: asset.id,
        granteeUserId: params.data.userId,
        permission: body.data.permission,
        grantedByUserId: identity.userId,
      });

      await audit(identity.sub, "media.access.granted", {
        assetId: asset.id,
        userId: params.data.userId,
        permission: body.data.permission,
      });

      return {
        success: true,
      };
    },
  );

  app.delete(
    "/media/assets/:id/grants/:userId",
    { preHandler: requireAuth },
    async (request, reply) => {
      const params = grantParamsSchema.safeParse(request.params);

      if (!params.success) {
        return reply.code(400).send({
          error: "Invalid media grant",
        });
      }

      const identity = authUser(request);
      const asset = await findMediaAsset(params.data.id, identity.userId);

      if (!asset || !canManageMedia(identity, asset)) {
        return reply.code(404).send({
          error: "Media not found",
        });
      }

      const removed = await revokeMediaAccess(asset.id, params.data.userId);

      await audit(identity.sub, "media.access.revoked", {
        assetId: asset.id,
        userId: params.data.userId,
        removed,
      });

      return {
        success: true,
        removed,
      };
    },
  );

  app.post("/media/logo", { preHandler: requireAuth }, async (request, reply) => {
    const parsed = uploadSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid logo upload",
        details: parsed.error.flatten(),
      });
    }

    const identity = authUser(request);
    const d = parsed.data;
    const organizationId = d.organizationId ?? identity.organizationId;

    if (organizationId !== identity.organizationId) {
      return reply.code(403).send({
        error: "Logo uploads must belong to your organization",
      });
    }

    const buffer = Buffer.from(d.dataBase64.replace(/^data:[^;]+;base64,/, ""), "base64");

    if (!buffer.length || buffer.length > 5 * 1024 * 1024) {
      return reply.code(413).send({
        error: "Logo must be between 1 byte and 5 MB",
      });
    }

    const ext =
      d.mimeType === "image/png"
        ? "png"
        : d.mimeType === "image/jpeg"
          ? "jpg"
          : d.mimeType === "image/webp"
            ? "webp"
            : "svg";

    const key = `logos/${new Date().getUTCFullYear()}/` + `${randomUUID()}.${ext}`;

    await minio.putObject(config.storage.bucket, key, buffer, buffer.length, {
      "Content-Type": d.mimeType,
    });

    const [result] = await pool.execute<mysql.ResultSetHeader>(
      `INSERT INTO media_assets (
             organization_id,
             owner_user_id,
             media_kind,
             visibility,
             bucket,
             object_key,
             original_name,
             mime_type,
             size_bytes
           )
           VALUES (?, ?, 'IMAGE', 'PUBLIC', ?, ?, ?, ?, ?)`,
      [
        organizationId,
        identity.userId,
        config.storage.bucket,
        key,
        d.fileName,
        d.mimeType,
        buffer.length,
      ],
    );

    await audit(identity.sub, "logo.uploaded", {
      assetId: result.insertId,
      objectKey: key,
    });

    realtime().emit("logo:uploaded", {
      id: result.insertId,
    });

    return reply.code(201).send({
      id: result.insertId,
      url: logoUrl(result.insertId),
    });
  });

  app.get("/media/:id", async (request, reply) => {
    const parsed = assetIdSchema.safeParse(request.params);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid media id",
      });
    }

    let asset = await findMediaAsset(parsed.data.id, null);

    if (!asset) {
      return reply.code(404).send({
        error: "Media not found",
      });
    }

    let identity: AuthenticatedIdentity | null = null;

    if (asset.visibility !== "PUBLIC") {
      identity = await optionalIdentity(request);

      if (identity) {
        asset = (await findMediaAsset(asset.id, identity.userId)) ?? asset;
      }
    }

    if (!canViewMedia(identity, asset)) {
      return reply.code(404).send({
        error: "Media not found",
      });
    }

    const stream = await minio.getObject(asset.bucket, asset.objectKey);

    reply.header("Content-Type", asset.mimeType);

    reply.header(
      "Cache-Control",
      asset.visibility === "PUBLIC" ? "public, max-age=3600" : "private, no-store",
    );

    return reply.send(stream);
  });
}
