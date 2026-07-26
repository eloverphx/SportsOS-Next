import type { FastifyInstance } from 'fastify';
import type { RowDataPacket } from 'mysql2/promise';
import { createClient } from 'redis';
import mqtt from 'mqtt';
import { config } from '@sportsos/config';
import { pool } from '../infrastructure/database.js';
import { minio } from '../infrastructure/minio.js';
import { requireAuth } from '../lib/auth.js';

async function checkMysql(): Promise<'online' | 'offline'> {
  try { await pool.query('SELECT 1'); return 'online'; } catch { return 'offline'; }
}
async function checkRedis(): Promise<'online' | 'offline'> {
  const client = createClient({ url: config.redis.url, socket: { connectTimeout: 3000 } });
  try { await client.connect(); await client.ping(); await client.quit(); return 'online'; }
  catch { if (client.isOpen) await client.disconnect(); return 'offline'; }
}
async function checkMqtt(): Promise<'online' | 'offline'> {
  return new Promise((resolve) => {
    const client = mqtt.connect(config.mqtt.url, { connectTimeout: 3000, reconnectPeriod: 0 });
    const timer = setTimeout(() => { client.end(true); resolve('offline'); }, 3500);
    client.once('connect', () => { clearTimeout(timer); client.end(true); resolve('online'); });
    client.once('error', () => { clearTimeout(timer); client.end(true); resolve('offline'); });
  });
}
async function checkMinio(): Promise<'online' | 'offline'> {
  try { await minio.listBuckets(); return 'online'; } catch { return 'offline'; }
}

export async function systemRoutes(app: FastifyInstance): Promise<void> {
  app.get('/dashboard/stats', { preHandler: requireAuth }, async () => {
    const [orgRows] = await pool.query<RowDataPacket[]>('SELECT COUNT(*) AS count FROM organizations WHERE active=TRUE');
    const [teamRows] = await pool.query<RowDataPacket[]>('SELECT COUNT(*) AS count FROM teams WHERE active=TRUE');
    const [playerRows] = await pool.query<RowDataPacket[]>("SELECT COUNT(*) AS count FROM players WHERE status='ACTIVE'");
    return { organizations: Number(orgRows[0]?.count ?? 0), teams: Number(teamRows[0]?.count ?? 0), players: Number(playerRows[0]?.count ?? 0), activeGames: 0, liveStreams: 0 };
  });

  app.get('/audit/recent', { preHandler: requireAuth }, async () => {
    const [rows] = await pool.query<RowDataPacket[]>('SELECT id, action, details, created_at FROM audit_log ORDER BY id DESC LIMIT 20');
    return { events: rows };
  });

  app.get('/', async () => ({ name: 'SportsOS API', version: '0.3.3.1-player-hotfix', endpoints: ['/', '/health', '/version', '/organizations', '/teams', '/players', '/media/logo', '/dashboard/stats'] }));
  app.get('/version', async () => ({ name: 'SportsOS API', version: '0.3.3.1-player-hotfix', node: process.version }));
  app.get('/health', async () => {
    const [mysqlStatus, redisStatus, mqttStatus, minioStatus] = await Promise.all([checkMysql(), checkRedis(), checkMqtt(), checkMinio()]);
    const services = { mysql: mysqlStatus, redis: redisStatus, mqtt: mqttStatus, minio: minioStatus };
    const healthy = Object.values(services).every((status) => status === 'online');
    return { success: healthy, status: healthy ? 'healthy' : 'degraded', services, uptime: Math.round(process.uptime()) };
  });
}
