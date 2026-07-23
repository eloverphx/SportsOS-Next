import type { RowDataPacket } from 'mysql2/promise';
import { env } from '../config/env.js';
import { pool } from './database.js';
import { minio } from './minio.js';

export async function runMigrations(): Promise<void> {
  await pool.execute(`CREATE TABLE IF NOT EXISTS organizations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(160) NOT NULL,
    short_name VARCHAR(50) NULL,
    default_sport VARCHAR(80) NOT NULL DEFAULT 'Hockey',
    timezone VARCHAR(100) NOT NULL DEFAULT 'America/Chicago',
    primary_color VARCHAR(7) NOT NULL DEFAULT '#ef4444',
    secondary_color VARCHAR(7) NOT NULL DEFAULT '#0f172a',
    website VARCHAR(255) NULL,
    logo_asset_id BIGINT UNSIGNED NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
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
  await pool.execute(`CREATE TABLE IF NOT EXISTS media_assets (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NULL,
    bucket VARCHAR(120) NOT NULL,
    object_key VARCHAR(500) NOT NULL UNIQUE,
    original_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    size_bytes BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_media_org FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS teams (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(160) NOT NULL,
    nickname VARCHAR(100) NULL,
    sport VARCHAR(80) NOT NULL DEFAULT 'Hockey',
    division VARCHAR(100) NULL,
    season VARCHAR(40) NULL,
    home_arena VARCHAR(160) NULL,
    primary_color VARCHAR(7) NOT NULL DEFAULT '#ef4444',
    secondary_color VARCHAR(7) NOT NULL DEFAULT '#0f172a',
    logo_asset_id BIGINT UNSIGNED NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_teams_org FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
    CONSTRAINT fk_teams_logo FOREIGN KEY (logo_asset_id) REFERENCES media_assets(id) ON DELETE SET NULL
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

  const [columns] = await pool.query<RowDataPacket[]>(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'organizations'`,
    [env.MYSQL_DATABASE]
  );
  const present = new Set(columns.map((row) => String(row.COLUMN_NAME)));
  const additions: Array<[string, string]> = [
    ['short_name', 'VARCHAR(50) NULL AFTER name'],
    ['primary_color', "VARCHAR(7) NOT NULL DEFAULT '#ef4444' AFTER timezone"],
    ['secondary_color', "VARCHAR(7) NOT NULL DEFAULT '#0f172a' AFTER primary_color"],
    ['website', 'VARCHAR(255) NULL AFTER secondary_color'],
    ['logo_asset_id', 'BIGINT UNSIGNED NULL AFTER website'],
    ['active', 'BOOLEAN NOT NULL DEFAULT TRUE AFTER logo_asset_id'],
    ['updated_at', 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at']
  ];
  for (const [name, sql] of additions) {
    if (!present.has(name)) await pool.execute(`ALTER TABLE organizations ADD COLUMN ${name} ${sql}`);
  }

  if (!(await minio.bucketExists(env.MINIO_BUCKET))) await minio.makeBucket(env.MINIO_BUCKET);
}
