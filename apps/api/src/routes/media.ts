import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import mysql, { type RowDataPacket } from 'mysql2/promise';
import { z } from 'zod';
import { config } from '@sportsos/config';
import { pool } from '../infrastructure/database.js';
import { minio } from '../infrastructure/minio.js';
import { realtime } from '../infrastructure/realtime.js';
import { audit } from '../lib/audit.js';
import { authUser, requireAuth } from '../lib/auth.js';
import { logoUrl } from '../lib/media.js';

const uploadSchema = z.object({
  organizationId: z.number().int().positive().nullable().optional(),
  fileName: z.string().trim().min(1).max(255),
  mimeType: z.enum(['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']),
  dataBase64: z.string().min(1)
});

export async function mediaRoutes(app: FastifyInstance): Promise<void> {
  app.get('/media/:id', async (request, reply) => {
    const id = z.coerce.number().int().positive().safeParse((request.params as { id: string }).id);
    if (!id.success) return reply.code(400).send({ error: 'Invalid media id' });
    const [rows] = await pool.execute<RowDataPacket[]>('SELECT object_key, mime_type FROM media_assets WHERE id=? LIMIT 1', [id.data]);
    if (!rows[0]) return reply.code(404).send({ error: 'Media not found' });
    const stream = await minio.getObject(config.storage.bucket, String(rows[0].object_key));
    reply.header('Content-Type', String(rows[0].mime_type));
    reply.header('Cache-Control', 'public, max-age=3600');
    return reply.send(stream);
  });

  app.post('/media/logo', { preHandler: requireAuth }, async (request, reply) => {
    const parsed = uploadSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'Invalid logo upload', details: parsed.error.flatten() });
    const d = parsed.data;
    const buffer = Buffer.from(d.dataBase64.replace(/^data:[^;]+;base64,/, ''), 'base64');
    if (!buffer.length || buffer.length > 5 * 1024 * 1024) {
      return reply.code(413).send({ error: 'Logo must be between 1 byte and 5 MB' });
    }
    const ext = d.mimeType === 'image/png' ? 'png' : d.mimeType === 'image/jpeg' ? 'jpg' : d.mimeType === 'image/webp' ? 'webp' : 'svg';
    const key = `logos/${new Date().getUTCFullYear()}/${randomUUID()}.${ext}`;
    await minio.putObject(config.storage.bucket, key, buffer, buffer.length, { 'Content-Type': d.mimeType });
    const [result] = await pool.execute<mysql.ResultSetHeader>('INSERT INTO media_assets (organization_id, bucket, object_key, original_name, mime_type, size_bytes) VALUES (?, ?, ?, ?, ?, ?)', [d.organizationId || null, config.storage.bucket, key, d.fileName, d.mimeType, buffer.length]);
    await audit(authUser(request).sub, 'logo.uploaded', { assetId: result.insertId, objectKey: key });
    realtime().emit('logo:uploaded', { id: result.insertId });
    return reply.code(201).send({ id: result.insertId, url: logoUrl(result.insertId) });
  });
}
