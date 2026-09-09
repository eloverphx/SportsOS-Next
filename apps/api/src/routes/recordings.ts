import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { audit } from "../lib/audit.js";
import { authUser, requireAuth } from "../lib/auth.js";
import { PERMISSIONS, requirePermission } from "../modules/auth/index.js";
import { canManageMedia } from "../modules/media-library/access-policy.js";
import { findMediaAsset } from "../modules/media-library/repository.js";
import { canManageRecording, canViewRecording } from "../modules/recordings/access-policy.js";
import {
  createRecording,
  findRecording,
  gameBelongsToOrganization,
  listRecordings,
  updateRecordingMetadata,
} from "../modules/recordings/repository.js";

const idSchema = z.object({
  id: z.coerce.number().int().positive(),
});

const listSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const createSchema = z.object({
  gameId: z.number().int().positive().nullable().optional(),
  source: z.enum(["LIVE", "UPLOAD", "IMPORT"]).default("UPLOAD"),
  title: z.string().trim().min(1).max(255).nullable().optional(),
});

const updateSchema = z
  .object({
    title: z.string().trim().min(1).max(255).nullable().optional(),
    mediaAssetId: z.number().int().positive().nullable().optional(),
  })
  .refine((value) => value.title !== undefined || value.mediaAssetId !== undefined, {
    message: "At least one recording field is required",
  });

function response(recording: NonNullable<Awaited<ReturnType<typeof findRecording>>>) {
  return {
    id: recording.id,
    organizationId: recording.organizationId,
    gameId: recording.gameId,
    ownerUserId: recording.ownerUserId,
    mediaAssetId: recording.mediaAssetId,
    source: recording.source,
    status: recording.status,
    title: recording.title,
    startedAt: recording.startedAt,
    endedAt: recording.endedAt,
    durationMs: recording.durationMs,
    publishedAt: recording.publishedAt,
    createdAt: recording.createdAt,
    updatedAt: recording.updatedAt,
    mediaUrl: recording.mediaAssetId == null ? null : `/media/${recording.mediaAssetId}`,
  };
}

export async function recordingRoutes(app: FastifyInstance): Promise<void> {
  app.get("/recordings", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.STREAM_READ,
    });

    const parsed = listSchema.safeParse(request.query);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid recordings query",
      });
    }

    const recordings = await listRecordings(
      identity.organizationId,
      identity.userId,
      parsed.data.limit,
    );

    return {
      recordings: recordings
        .filter((recording) => canViewRecording(identity, recording))
        .map(response),
    };
  });

  app.post("/recordings", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.STREAM_MANAGE,
    });

    const parsed = createSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid recording data",
        details: parsed.error.flatten(),
      });
    }

    const gameId = parsed.data.gameId ?? null;

    if (gameId !== null && !(await gameBelongsToOrganization(gameId, identity.organizationId))) {
      return reply.code(400).send({
        error: "Recording game must belong to your organization",
      });
    }

    const recordingId = await createRecording({
      organizationId: identity.organizationId,
      gameId,
      ownerUserId: identity.userId,
      source: parsed.data.source,
      title: parsed.data.title ?? null,
    });

    await audit(identity.sub, "recording.created", {
      recordingId,
      gameId,
      source: parsed.data.source,
    });

    const recording = await findRecording(recordingId, identity.userId);

    if (!recording) {
      throw new Error("Created recording could not be loaded");
    }

    return reply.code(201).send({
      recording: response(recording),
    });
  });

  app.get("/recordings/:id", async (request, reply) => {
    const identity = await requirePermission(request, {
      permission: PERMISSIONS.STREAM_READ,
    });

    const parsed = idSchema.safeParse(request.params);

    if (!parsed.success) {
      return reply.code(400).send({
        error: "Invalid recording id",
      });
    }

    const recording = await findRecording(parsed.data.id, identity.userId);

    if (!recording || !canViewRecording(identity, recording)) {
      return reply.code(404).send({
        error: "Recording not found",
      });
    }

    return {
      recording: response(recording),
    };
  });

  app.patch("/recordings/:id", { preHandler: requireAuth }, async (request, reply) => {
    const params = idSchema.safeParse(request.params);
    const body = updateSchema.safeParse(request.body);

    if (!params.success || !body.success) {
      return reply.code(400).send({
        error: "Invalid recording update",
        details: body.success ? undefined : body.error.flatten(),
      });
    }

    const identity = authUser(request);
    const recording = await findRecording(params.data.id, identity.userId);

    if (!recording || !canManageRecording(identity, recording)) {
      return reply.code(404).send({
        error: "Recording not found",
      });
    }

    let nextMediaAssetId = recording.mediaAssetId;

    if (body.data.mediaAssetId !== undefined) {
      nextMediaAssetId = body.data.mediaAssetId;

      if (nextMediaAssetId !== null) {
        const asset = await findMediaAsset(nextMediaAssetId, identity.userId);

        if (
          !asset ||
          asset.organizationId !== recording.organizationId ||
          asset.mediaKind !== "VIDEO" ||
          !canManageMedia(identity, asset)
        ) {
          return reply.code(400).send({
            error: "Recording media must be a manageable video asset in the same organization",
          });
        }
      }
    }

    await updateRecordingMetadata({
      recordingId: recording.id,
      title: body.data.title === undefined ? recording.title : body.data.title,
      mediaAssetId: nextMediaAssetId,
    });

    await audit(identity.sub, "recording.updated", {
      recordingId: recording.id,
      mediaAssetId: nextMediaAssetId,
    });

    const updated = await findRecording(recording.id, identity.userId);

    if (!updated) {
      throw new Error("Updated recording could not be loaded");
    }

    return {
      recording: response(updated),
    };
  });
}
