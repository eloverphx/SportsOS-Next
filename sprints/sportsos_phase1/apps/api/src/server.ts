import Fastify, { type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import bcrypt from 'bcryptjs';
import mysql, { type Pool, type RowDataPacket } from 'mysql2/promise';
import { createClient } from 'redis';
import mqtt from 'mqtt';
import { Client as MinioClient } from 'minio';
import { Server as SocketIOServer } from 'socket.io';
import { z } from 'zod';

const envSchema = z.object({
  PORT: z.coerce.number().default(4001),
  HOST: z.string().default('0.0.0.0'),
  DASHBOARD_ORIGIN: z.string().default('http://localhost:4000'),
  MYSQL_HOST: z.string().default('mysql'),
  MYSQL_PORT: z.coerce.number().default(3306),
  MYSQL_DATABASE: z.string().default('sportsos'),
  MYSQL_USER: z.string().default('sportsos'),
  MYSQL_PASSWORD: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  REDIS_URL: z.string().default('redis://redis:6379'),
  MQTT_URL: z.string().default('mqtt://mqtt:1883'),
  MINIO_ENDPOINT: z.string().default('minio'),
  MINIO_PORT: z.coerce.number().default(9000),
  MINIO_ACCESS_KEY: z.string().min(1),
  MINIO_SECRET_KEY: z.string().min(1)
});

const env = envSchema.parse(process.env);
const app = Fastify({ logger: true });
await app.register(cors, { origin: env.DASHBOARD_ORIGIN, credentials: true });
await app.register(jwt, { secret: env.JWT_SECRET });

const pool: Pool = mysql.createPool({
  host: env.MYSQL_HOST,
  port: env.MYSQL_PORT,
  database: env.MYSQL_DATABASE,
  user: env.MYSQL_USER,
  password: env.MYSQL_PASSWORD,
  connectionLimit: 10
});

async function runMigrations(): Promise<void> {
  await pool.execute(`CREATE TABLE IF NOT EXISTS organizations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(160) NOT NULL,
    default_sport VARCHAR(80) NOT NULL DEFAULT 'Hockey',
    timezone VARCHAR(100) NOT NULL DEFAULT 'America/Chicago',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    first_name VARCHAR(80) NOT NULL,
    last_name VARCHAR(80) NOT NULL,
    email VARCHAR(190) NOT NULL UNIQUE,
    username VARCHAR(80) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(40) NOT NULL DEFAULT 'admin',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_org FOREIGN KEY (organization_id) REFERENCES organizations(id)
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS settings (
    setting_key VARCHAR(120) NOT NULL PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    action VARCHAR(120) NOT NULL,
    details JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
}
await runMigrations();

const io = new SocketIOServer(app.server, { cors: { origin: env.DASHBOARD_ORIGIN, credentials: true } });
io.on('connection', (socket) => socket.emit('system:hello', { message: 'SportsOS realtime online', timestamp: new Date().toISOString() }));

async function requireAuth(request: FastifyRequest): Promise<void> {
  await request.jwtVerify();
}

const setupSchema = z.object({
  firstName: z.string().trim().min(1).max(80),
  lastName: z.string().trim().min(1).max(80),
  email: z.string().trim().email().max(190),
  username: z.string().trim().min(3).max(80),
  password: z.string().min(10).max(128),
  organizationName: z.string().trim().min(2).max(160),
  defaultSport: z.string().trim().min(2).max(80).default('Hockey'),
  timezone: z.string().trim().min(2).max(100),
  serverName: z.string().trim().min(2).max(120)
});

app.get('/setup/status', async () => {
  const [rows] = await pool.query<RowDataPacket[]>('SELECT COUNT(*) AS count FROM users');
  return { complete: Number(rows[0]?.count ?? 0) > 0 };
});

app.post('/setup/complete', async (request, reply) => {
  const parsed = setupSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'Invalid setup data', details: parsed.error.flatten() });
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [rows] = await connection.query<RowDataPacket[]>('SELECT COUNT(*) AS count FROM users FOR UPDATE');
    if (Number(rows[0]?.count ?? 0) > 0) {
      await connection.rollback();
      return reply.code(409).send({ error: 'Setup has already been completed' });
    }
    const input = parsed.data;
    const [orgResult] = await connection.execute<mysql.ResultSetHeader>(
      'INSERT INTO organizations (name, default_sport, timezone) VALUES (?, ?, ?)',
      [input.organizationName, input.defaultSport, input.timezone]
    );
    const passwordHash = await bcrypt.hash(input.password, 12);
    const [userResult] = await connection.execute<mysql.ResultSetHeader>(
      'INSERT INTO users (organization_id, first_name, last_name, email, username, password_hash, role) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [orgResult.insertId, input.firstName, input.lastName, input.email.toLowerCase(), input.username, passwordHash, 'admin']
    );
    await connection.execute('INSERT INTO settings (setting_key, setting_value) VALUES (?, ?), (?, ?)', [
      'server_name', input.serverName, 'setup_complete', 'true'
    ]);
    await connection.execute('INSERT INTO audit_log (user_id, action, details) VALUES (?, ?, ?)', [
      userResult.insertId, 'setup.completed', JSON.stringify({ organizationId: orgResult.insertId })
    ]);
    await connection.commit();
    return { success: true };
  } catch (error) {
    await connection.rollback();
    request.log.error(error);
    return reply.code(500).send({ error: 'Setup failed' });
  } finally {
    connection.release();
  }
});

const loginSchema = z.object({ identifier: z.string().trim().min(1), password: z.string().min(1) });
app.post('/auth/login', async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'Username/email and password are required' });
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT u.id, u.organization_id, u.first_name, u.last_name, u.email, u.username, u.password_hash, u.role,
            o.name AS organization_name
       FROM users u JOIN organizations o ON o.id = u.organization_id
      WHERE u.username = ? OR u.email = ? LIMIT 1`,
    [parsed.data.identifier, parsed.data.identifier.toLowerCase()]
  );
  const user = rows[0];
  if (!user || !(await bcrypt.compare(parsed.data.password, String(user.password_hash)))) {
    return reply.code(401).send({ error: 'Invalid username/email or password' });
  }
  const token = app.jwt.sign({ sub: String(user.id), organizationId: user.organization_id, role: user.role }, { expiresIn: '8h' });
  await pool.execute('INSERT INTO audit_log (user_id, action, details) VALUES (?, ?, ?)', [user.id, 'auth.login', JSON.stringify({ username: user.username })]);
  return { token, user: { id: user.id, firstName: user.first_name, lastName: user.last_name, email: user.email, username: user.username, role: user.role, organizationName: user.organization_name } };
});

app.get('/auth/me', { preHandler: requireAuth }, async (request, reply) => {
  const payload = request.user as { sub: string };
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT u.id, u.first_name, u.last_name, u.email, u.username, u.role, o.name AS organization_name
       FROM users u JOIN organizations o ON o.id = u.organization_id WHERE u.id = ? LIMIT 1`,
    [payload.sub]
  );
  const user = rows[0];
  if (!user) return reply.code(404).send({ error: 'User not found' });
  return { user: { id: user.id, firstName: user.first_name, lastName: user.last_name, email: user.email, username: user.username, role: user.role, organizationName: user.organization_name } };
});

app.post('/auth/logout', { preHandler: requireAuth }, async () => ({ success: true }));

async function checkMysql(): Promise<'online' | 'offline'> { try { await pool.query('SELECT 1'); return 'online'; } catch { return 'offline'; } }
async function checkRedis(): Promise<'online' | 'offline'> {
  const client = createClient({ url: env.REDIS_URL, socket: { connectTimeout: 3000 } });
  try { await client.connect(); await client.ping(); await client.quit(); return 'online'; }
  catch { if (client.isOpen) await client.disconnect(); return 'offline'; }
}
async function checkMqtt(): Promise<'online' | 'offline'> { return new Promise((resolve) => {
  const client = mqtt.connect(env.MQTT_URL, { connectTimeout: 3000, reconnectPeriod: 0 });
  const timer = setTimeout(() => { client.end(true); resolve('offline'); }, 3500);
  client.once('connect', () => { clearTimeout(timer); client.end(true); resolve('online'); });
  client.once('error', () => { clearTimeout(timer); client.end(true); resolve('offline'); });
}); }
async function checkMinio(): Promise<'online' | 'offline'> { try {
  const client = new MinioClient({ endPoint: env.MINIO_ENDPOINT, port: env.MINIO_PORT, useSSL: false, accessKey: env.MINIO_ACCESS_KEY, secretKey: env.MINIO_SECRET_KEY });
  await client.listBuckets(); return 'online';
} catch { return 'offline'; } }

app.get('/', async () => ({ name: 'SportsOS API', version: '0.3.0-sprint1.1', endpoints: ['/', '/health', '/version', '/setup/status', '/setup/complete', '/auth/login', '/auth/me'] }));
app.get('/version', async () => ({ name: 'SportsOS API', version: '0.3.0-sprint1.1', node: process.version }));
app.get('/health', async () => {
  const [mysqlStatus, redisStatus, mqttStatus, minioStatus] = await Promise.all([checkMysql(), checkRedis(), checkMqtt(), checkMinio()]);
  const services = { mysql: mysqlStatus, redis: redisStatus, mqtt: mqttStatus, minio: minioStatus };
  const healthy = Object.values(services).every((status) => status === 'online');
  return { success: healthy, status: healthy ? 'healthy' : 'degraded', services, uptime: Math.round(process.uptime()) };
});

await app.listen({ host: env.HOST, port: env.PORT });
