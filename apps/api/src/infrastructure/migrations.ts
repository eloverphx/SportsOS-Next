import type { RowDataPacket } from "mysql2/promise";
import { config } from "@sportsos/config";
import { pool } from "./database.js";
import { minio } from "./minio.js";

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

  await pool.execute(`CREATE TABLE IF NOT EXISTS players (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    team_id BIGINT UNSIGNED NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    preferred_name VARCHAR(100) NULL,
    jersey_number TINYINT UNSIGNED NULL,
    position ENUM('Goalie','Defense','Left Wing','Center','Right Wing') NOT NULL,
    shoots ENUM('L','R') NULL,
    birth_date DATE NULL,
    height_cm SMALLINT UNSIGNED NULL,
    weight_kg SMALLINT UNSIGNED NULL,
    email VARCHAR(255) NULL,
    phone VARCHAR(50) NULL,
    photo_asset_id BIGINT UNSIGNED NULL,
    status ENUM('ACTIVE','INACTIVE','INJURED','SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_players_org (organization_id),
    INDEX idx_players_team (team_id),
    INDEX idx_players_name (last_name, first_name),
    INDEX idx_players_status (status),
    CONSTRAINT fk_players_org FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
    CONSTRAINT fk_players_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL,
    CONSTRAINT fk_players_photo FOREIGN KEY (photo_asset_id) REFERENCES media_assets(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS seasons (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(100) NOT NULL,
    start_date DATE NULL,
    end_date DATE NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_seasons_org_name (organization_id, name),
    INDEX idx_seasons_org (organization_id),
    INDEX idx_seasons_active (active),
    CONSTRAINT fk_seasons_org FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS team_rosters (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    season_id BIGINT UNSIGNED NOT NULL,
    team_id BIGINT UNSIGNED NOT NULL,
    player_id BIGINT UNSIGNED NOT NULL,
    jersey_number TINYINT UNSIGNED NULL,
    position ENUM('Goalie','Defense','Left Wing','Center','Right Wing') NOT NULL,
    role ENUM('PLAYER','CAPTAIN','ALTERNATE') NOT NULL DEFAULT 'PLAYER',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_roster_assignment (season_id, team_id, player_id),
    INDEX idx_rosters_team_season (team_id, season_id),
    INDEX idx_rosters_player (player_id),
    CONSTRAINT fk_rosters_season FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE RESTRICT,
    CONSTRAINT fk_rosters_team FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE RESTRICT,
    CONSTRAINT fk_rosters_player FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE RESTRICT
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS games (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    season_id BIGINT UNSIGNED NOT NULL,
    home_team_id BIGINT UNSIGNED NOT NULL,
    away_team_id BIGINT UNSIGNED NOT NULL,
    scheduled_start DATETIME NOT NULL,
    timezone VARCHAR(100) NOT NULL DEFAULT 'America/Chicago',
    venue VARCHAR(160) NULL,
    status ENUM('SCHEDULED','LIVE','FINAL','POSTPONED','CANCELED') NOT NULL DEFAULT 'SCHEDULED',
    home_score SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    away_score SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    period SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    period_length_ms INT UNSIGNED NOT NULL DEFAULT 1200000,
    clock_remaining_ms INT UNSIGNED NOT NULL DEFAULT 1200000,
    clock_running BOOLEAN NOT NULL DEFAULT FALSE,
    clock_started_at DATETIME(3) NULL,
    notes TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_games_org_start (organization_id, scheduled_start),
    INDEX idx_games_season (season_id),
    INDEX idx_games_home_team (home_team_id),
    INDEX idx_games_away_team (away_team_id),
    INDEX idx_games_status (status),
    CONSTRAINT fk_games_org FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
    CONSTRAINT fk_games_season FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE RESTRICT,
    CONSTRAINT fk_games_home_team FOREIGN KEY (home_team_id) REFERENCES teams(id) ON DELETE RESTRICT,
    CONSTRAINT fk_games_away_team FOREIGN KEY (away_team_id) REFERENCES teams(id) ON DELETE RESTRICT
  ) ENGINE=InnoDB`);

  await pool.execute(`CREATE TABLE IF NOT EXISTS scoreboard_devices (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    organization_id BIGINT UNSIGNED NOT NULL,
    game_id BIGINT UNSIGNED NULL,
    name VARCHAR(160) NOT NULL,
    location VARCHAR(160) NULL,
    device_key VARCHAR(128) NOT NULL UNIQUE,
    last_seen_at DATETIME(3) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_scoreboard_devices_org (organization_id),
    INDEX idx_scoreboard_devices_game (game_id),
    INDEX idx_scoreboard_devices_last_seen (last_seen_at),
    CONSTRAINT fk_scoreboard_devices_org
      FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE RESTRICT,
    CONSTRAINT fk_scoreboard_devices_game
      FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE SET NULL
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
    [config.database.name],
  );
  const present = new Set(columns.map((row) => String(row.COLUMN_NAME)));
  const additions: Array<[string, string]> = [
    ["short_name", "VARCHAR(50) NULL AFTER name"],
    ["primary_color", "VARCHAR(7) NOT NULL DEFAULT '#ef4444' AFTER timezone"],
    ["secondary_color", "VARCHAR(7) NOT NULL DEFAULT '#0f172a' AFTER primary_color"],
    ["website", "VARCHAR(255) NULL AFTER secondary_color"],
    ["logo_asset_id", "BIGINT UNSIGNED NULL AFTER website"],
    ["active", "BOOLEAN NOT NULL DEFAULT TRUE AFTER logo_asset_id"],
    [
      "updated_at",
      "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at",
    ],
  ];
  for (const [name, sql] of additions) {
    if (!present.has(name))
      await pool.execute(`ALTER TABLE organizations ADD COLUMN ${name} ${sql}`);
  }
  const [gameColumns] = await pool.query<RowDataPacket[]>(
    `SELECT COLUMN_NAME
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'games'`,
    [config.database.name],
  );

  const presentGameColumns = new Set(gameColumns.map((row) => String(row.COLUMN_NAME)));

  const gameAdditions: Array<[string, string]> = [
    ["period", "SMALLINT UNSIGNED NOT NULL DEFAULT 1 AFTER away_score"],
    ["period_length_ms", "INT UNSIGNED NOT NULL DEFAULT 1200000 AFTER period"],
    ["clock_remaining_ms", "INT UNSIGNED NOT NULL DEFAULT 1200000 AFTER period_length_ms"],
    ["clock_running", "BOOLEAN NOT NULL DEFAULT FALSE AFTER clock_remaining_ms"],
    ["clock_started_at", "DATETIME(3) NULL AFTER clock_running"],
  ];

  for (const [name, sql] of gameAdditions) {
    if (!presentGameColumns.has(name)) {
      await pool.execute(`ALTER TABLE games ADD COLUMN ${name} ${sql}`);
    }
  }
  const [crossOrgGameColumns] = await pool.query<RowDataPacket[]>(
    `SELECT COLUMN_NAME
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'games'`,
    [config.database.name],
  );

  const presentCrossOrgGameColumns = new Set(
    crossOrgGameColumns.map((row) => String(row.COLUMN_NAME)),
  );

  if (!presentCrossOrgGameColumns.has("home_external_name")) {
    await pool.execute(
      `ALTER TABLE games ADD COLUMN home_external_name VARCHAR(160) NULL AFTER home_team_id`,
    );
  }

  if (!presentCrossOrgGameColumns.has("away_external_name")) {
    await pool.execute(
      `ALTER TABLE games ADD COLUMN away_external_name VARCHAR(160) NULL AFTER away_team_id`,
    );
  }

  await pool.execute(
    `ALTER TABLE games
       MODIFY COLUMN home_team_id BIGINT UNSIGNED NULL,
       MODIFY COLUMN away_team_id BIGINT UNSIGNED NULL`,
  );

  await pool.execute(`CREATE TABLE IF NOT EXISTS game_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    game_id BIGINT UNSIGNED NOT NULL,
    organization_id BIGINT UNSIGNED NOT NULL,
    type ENUM('GOAL', 'PENALTY') NOT NULL,
    side ENUM('home', 'away') NOT NULL,
    period SMALLINT UNSIGNED NOT NULL,
    clock_remaining_ms INT UNSIGNED NOT NULL,
    player_id BIGINT UNSIGNED NULL,
    assist1_player_id BIGINT UNSIGNED NULL,
    assist2_player_id BIGINT UNSIGNED NULL,
    penalty_code VARCHAR(100) NULL,
    penalty_minutes SMALLINT UNSIGNED NULL,
    notes VARCHAR(500) NULL,
    created_by_user_id BIGINT UNSIGNED NULL,
    voided_at DATETIME(3) NULL,
    voided_by_user_id BIGINT UNSIGNED NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_game_events_game (game_id, id),
    INDEX idx_game_events_org (organization_id),
    CONSTRAINT fk_game_events_game FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    CONSTRAINT fk_game_events_org FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT fk_game_events_player FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL,
    CONSTRAINT fk_game_events_assist1 FOREIGN KEY (assist1_player_id) REFERENCES players(id) ON DELETE SET NULL,
    CONSTRAINT fk_game_events_assist2 FOREIGN KEY (assist2_player_id) REFERENCES players(id) ON DELETE SET NULL,
    CONSTRAINT fk_game_events_created_by FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_game_events_voided_by FOREIGN KEY (voided_by_user_id) REFERENCES users(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`);

  if (!(await minio.bucketExists(config.storage.bucket)))
    await minio.makeBucket(config.storage.bucket);
}
