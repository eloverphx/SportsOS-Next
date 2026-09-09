import type { RowDataPacket } from "mysql2/promise";
import { config } from "@sportsos/config";
import { pool } from "./database.js";

async function columnNames(tableName: string): Promise<Set<string>> {
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT COLUMN_NAME
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?`,
    [config.database.name, tableName],
  );

  return new Set(rows.map((row) => String(row.COLUMN_NAME)));
}

async function columnIsNullable(tableName: string, columnName: string): Promise<boolean> {
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT IS_NULLABLE
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = ?
       AND TABLE_NAME = ?
       AND COLUMN_NAME = ?
     LIMIT 1`,
    [config.database.name, tableName, columnName],
  );

  return String(rows[0]?.IS_NULLABLE ?? "").toUpperCase() === "YES";
}

async function constraintExists(tableName: string, constraintName: string): Promise<boolean> {
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT CONSTRAINT_NAME
     FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
     WHERE TABLE_SCHEMA = ?
       AND TABLE_NAME = ?
       AND CONSTRAINT_NAME = ?
     LIMIT 1`,
    [config.database.name, tableName, constraintName],
  );

  return rows.length > 0;
}

async function indexExists(tableName: string, indexName: string): Promise<boolean> {
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT INDEX_NAME
     FROM INFORMATION_SCHEMA.STATISTICS
     WHERE TABLE_SCHEMA = ?
       AND TABLE_NAME = ?
       AND INDEX_NAME = ?
     LIMIT 1`,
    [config.database.name, tableName, indexName],
  );

  return rows.length > 0;
}

async function ensureMediaOwnershipColumns(): Promise<void> {
  const present = await columnNames("media_assets");

  const additions: Array<[string, string]> = [
    ["owner_user_id", "BIGINT UNSIGNED NULL AFTER organization_id"],
    [
      "media_kind",
      "ENUM('IMAGE','VIDEO','AUDIO','OTHER') NOT NULL DEFAULT 'IMAGE' AFTER owner_user_id",
    ],
    [
      "visibility",
      "ENUM('PRIVATE','ORGANIZATION','PUBLIC') NOT NULL DEFAULT 'ORGANIZATION' AFTER media_kind",
    ],
    ["captured_at", "DATETIME(3) NULL AFTER visibility"],
    ["duration_ms", "BIGINT UNSIGNED NULL AFTER captured_at"],
    ["checksum_sha256", "CHAR(64) NULL AFTER duration_ms"],
  ];

  for (const [name, sql] of additions) {
    if (!present.has(name)) {
      await pool.execute(`ALTER TABLE media_assets ADD COLUMN ${name} ${sql}`);
    }
  }

  if (!(await indexExists("media_assets", "idx_media_assets_owner"))) {
    await pool.execute(
      "ALTER TABLE media_assets ADD INDEX idx_media_assets_owner (owner_user_id, created_at)",
    );
  }

  if (!(await indexExists("media_assets", "idx_media_assets_visibility"))) {
    await pool.execute(
      "ALTER TABLE media_assets ADD INDEX idx_media_assets_visibility (organization_id, visibility, created_at)",
    );
  }

  if (!(await constraintExists("media_assets", "fk_media_assets_owner"))) {
    await pool.execute(
      `ALTER TABLE media_assets
       ADD CONSTRAINT fk_media_assets_owner
       FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE SET NULL`,
    );
  }
}

// Logo URLs are intentionally public because scoreboard/overlay clients
// render them without an authenticated API session.
await pool.execute(
  `UPDATE media_assets
     SET media_kind = 'IMAGE',
         visibility = 'PUBLIC'
     WHERE object_key LIKE 'logos/%'`,
);

async function ensureUserAccountColumns(): Promise<void> {
  const present = await columnNames("users");

  const additions: Array<[string, string]> = [
    [
      "account_status",
      "ENUM('PENDING','ACTIVE','SUSPENDED','REJECTED') NOT NULL DEFAULT 'ACTIVE' AFTER role",
    ],
    ["approved_at", "DATETIME(3) NULL AFTER account_status"],
    ["approved_by_user_id", "BIGINT UNSIGNED NULL AFTER approved_at"],
  ];

  for (const [name, sql] of additions) {
    if (!present.has(name)) {
      await pool.execute(`ALTER TABLE users ADD COLUMN ${name} ${sql}`);
    }
  }

  if (!(await indexExists("users", "idx_users_account_status"))) {
    await pool.execute(
      "ALTER TABLE users ADD INDEX idx_users_account_status (organization_id, account_status, created_at)",
    );
  }

  if (!(await constraintExists("users", "fk_users_approved_by"))) {
    await pool.execute(
      `ALTER TABLE users
       ADD CONSTRAINT fk_users_approved_by
       FOREIGN KEY (approved_by_user_id)
       REFERENCES users(id)
       ON DELETE SET NULL`,
    );
  }
}

async function ensureDurableGoLiveOwnershipColumns(): Promise<void> {
  if (!(await columnIsNullable("recordings", "owner_user_id"))) {
    await pool.execute("ALTER TABLE recordings MODIFY COLUMN owner_user_id BIGINT UNSIGNED NULL");
  }

  if (!(await columnIsNullable("stream_sessions", "created_by_user_id"))) {
    await pool.execute(
      "ALTER TABLE stream_sessions MODIFY COLUMN created_by_user_id BIGINT UNSIGNED NULL",
    );
  }
}

export async function runStreamingFoundationMigrations(): Promise<void> {
  await ensureUserAccountColumns();
  await ensureMediaOwnershipColumns();

  await pool.execute(`CREATE TABLE IF NOT EXISTS auth_sessions (
    session_id CHAR(36) NOT NULL PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    organization_id BIGINT UNSIGNED NOT NULL,
    refresh_token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at DATETIME(3) NOT NULL,
    last_seen_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    revoked_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_auth_sessions_user (user_id, revoked_at, expires_at),
    INDEX idx_auth_sessions_org (organization_id, expires_at),
    CONSTRAINT fk_auth_sessions_user
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_auth_sessions_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS recordings (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    game_id BIGINT UNSIGNED NULL,
    owner_user_id BIGINT UNSIGNED NULL,
    media_asset_id BIGINT UNSIGNED NULL,
    source ENUM('LIVE','UPLOAD','IMPORT') NOT NULL DEFAULT 'LIVE',
    status ENUM('CREATED','RECORDING','PROCESSING','READY','FAILED','ARCHIVED')
      NOT NULL DEFAULT 'CREATED',
    title VARCHAR(255) NULL,
    started_at DATETIME(3) NULL,
    ended_at DATETIME(3) NULL,
    duration_ms BIGINT UNSIGNED NULL,
    published_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
      ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_recordings_media_asset (media_asset_id),
    INDEX idx_recordings_org_created (organization_id, created_at),
    INDEX idx_recordings_game (game_id, created_at),
    INDEX idx_recordings_owner (owner_user_id, created_at),
    INDEX idx_recordings_status (status, created_at),
    CONSTRAINT fk_recordings_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT fk_recordings_game
      FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE SET NULL,
    CONSTRAINT fk_recordings_owner
      FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_recordings_media
      FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS stream_sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    session_uuid CHAR(36) NOT NULL UNIQUE,
    organization_id BIGINT UNSIGNED NOT NULL,
    game_id BIGINT UNSIGNED NOT NULL,
    created_by_user_id BIGINT UNSIGNED NULL,
    recording_id BIGINT UNSIGNED NULL,
    status ENUM(
      'PLANNED','ARMED','STARTING','LIVE','DEGRADED',
      'STOPPING','COMPLETE','ERROR','EMERGENCY_STOPPED'
    ) NOT NULL DEFAULT 'PLANNED',
    started_at DATETIME(3) NULL,
    live_at DATETIME(3) NULL,
    ended_at DATETIME(3) NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
      ON UPDATE CURRENT_TIMESTAMP(3),
    INDEX idx_stream_sessions_game (game_id, created_at),
    INDEX idx_stream_sessions_org_status (organization_id, status, created_at),
    INDEX idx_stream_sessions_creator (created_by_user_id, created_at),
    CONSTRAINT fk_stream_sessions_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT fk_stream_sessions_game
      FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    CONSTRAINT fk_stream_sessions_creator
      FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_stream_sessions_recording
      FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);

  await ensureDurableGoLiveOwnershipColumns();

  await pool.execute(`CREATE TABLE IF NOT EXISTS media_access_grants (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    media_asset_id BIGINT UNSIGNED NOT NULL,
    grantee_user_id BIGINT UNSIGNED NOT NULL,
    permission ENUM('VIEW','EDIT','MANAGE') NOT NULL DEFAULT 'VIEW',
    granted_by_user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
      ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_media_access_grant (media_asset_id, grantee_user_id),
    INDEX idx_media_access_grantee (grantee_user_id, permission),
    CONSTRAINT fk_media_access_asset
      FOREIGN KEY (media_asset_id) REFERENCES media_assets(id) ON DELETE CASCADE,
    CONSTRAINT fk_media_access_grantee
      FOREIGN KEY (grantee_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_media_access_granted_by
      FOREIGN KEY (granted_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS recording_event_anchors (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    recording_id BIGINT UNSIGNED NOT NULL,
    game_event_id BIGINT UNSIGNED NOT NULL,
    recording_offset_ms BIGINT UNSIGNED NOT NULL,
    anchor_source ENUM('SCOREKEEPER','SYSTEM') NOT NULL DEFAULT 'SCOREKEEPER',
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_recording_event_anchor (recording_id, game_event_id),
    INDEX idx_recording_event_anchor_event (game_event_id),
    CONSTRAINT fk_recording_event_anchor_recording
      FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE,
    CONSTRAINT fk_recording_event_anchor_event
      FOREIGN KEY (game_event_id) REFERENCES game_events(id) ON DELETE CASCADE
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS recording_clip_jobs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    recording_id BIGINT UNSIGNED NOT NULL,
    game_event_id BIGINT UNSIGNED NOT NULL,
    requested_by_user_id BIGINT UNSIGNED NOT NULL,
    selection_source ENUM('SCOREKEEPER_EVENT','AI_SELECTION')
      NOT NULL DEFAULT 'SCOREKEEPER_EVENT',
    start_ms BIGINT UNSIGNED NOT NULL,
    end_ms BIGINT UNSIGNED NOT NULL,
    status ENUM('PENDING','PROCESSING','READY','FAILED','CANCELLED')
      NOT NULL DEFAULT 'PENDING',
    output_media_asset_id BIGINT UNSIGNED NULL,
    error_message VARCHAR(1000) NULL,
    attempt_count INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
      ON UPDATE CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_recording_clip_job_window (
      recording_id,
      game_event_id,
      requested_by_user_id,
      start_ms,
      end_ms,
      selection_source
    ),
    INDEX idx_recording_clip_jobs_org_status (
      organization_id,
      status,
      created_at
    ),
    INDEX idx_recording_clip_jobs_recording (
      recording_id,
      status,
      created_at
    ),
    INDEX idx_recording_clip_jobs_requester (
      requested_by_user_id,
      created_at
    ),
    CONSTRAINT fk_recording_clip_jobs_org
      FOREIGN KEY (organization_id)
      REFERENCES organizations(id)
      ON DELETE CASCADE,
    CONSTRAINT fk_recording_clip_jobs_recording
      FOREIGN KEY (recording_id)
      REFERENCES recordings(id)
      ON DELETE CASCADE,
    CONSTRAINT fk_recording_clip_jobs_event
      FOREIGN KEY (game_event_id)
      REFERENCES game_events(id)
      ON DELETE CASCADE,
    CONSTRAINT fk_recording_clip_jobs_requester
      FOREIGN KEY (requested_by_user_id)
      REFERENCES users(id)
      ON DELETE RESTRICT,
    CONSTRAINT fk_recording_clip_jobs_output_media
      FOREIGN KEY (output_media_asset_id)
      REFERENCES media_assets(id)
      ON DELETE SET NULL
  ) ENGINE=InnoDB`);
}
