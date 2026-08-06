import mysql, { type PoolConnection, type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { logoUrl } from "../../lib/media.js";
import type { GameInput, ScoreAction } from "./schemas.js";
import type { Game, GameStatus, GameTeamOption } from "./types.js";
import {
  adjustActivePenaltyClocks,
  materializePenaltyClocks,
  setPenaltyClockRunning,
} from "../penalties/repository.js";

const SELECT_GAME = `SELECT
  g.*,
  o.name AS organization_name,
  o.logo_asset_id AS organization_logo_asset_id,
  o.primary_color AS organization_primary_color,
  o.secondary_color AS organization_secondary_color,
  s.name AS season_name,
  home.name AS registered_home_team_name,
  home.logo_asset_id AS home_logo_asset_id,
  home.primary_color AS home_primary_color,
  home.secondary_color AS home_secondary_color,
  home_org.name AS home_team_organization_name,
  away.name AS registered_away_team_name,
  away.logo_asset_id AS away_logo_asset_id,
  away.primary_color AS away_primary_color,
  away.secondary_color AS away_secondary_color,
  away_org.name AS away_team_organization_name
FROM games g
JOIN organizations o ON o.id = g.organization_id
JOIN seasons s ON s.id = g.season_id
LEFT JOIN teams home ON home.id = g.home_team_id
LEFT JOIN organizations home_org ON home_org.id = home.organization_id
LEFT JOIN teams away ON away.id = g.away_team_id
LEFT JOIN organizations away_org ON away_org.id = away.organization_id`;

function dateToIso(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(String(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function effectiveClockRemainingMs(
  storedRemainingMs: number,
  running: boolean,
  startedAt: unknown,
): number {
  if (!running) return storedRemainingMs;
  const started = startedAt instanceof Date ? startedAt : new Date(String(startedAt));
  if (Number.isNaN(started.getTime())) return storedRemainingMs;
  return Math.max(0, storedRemainingMs - (Date.now() - started.getTime()));
}

function effectiveIntermissionRemainingMs(
  storedRemainingMs: number,
  running: boolean,
  startedAt: unknown,
): number {
  if (!running) return storedRemainingMs;
  const started = startedAt instanceof Date ? startedAt : new Date(String(startedAt));
  if (Number.isNaN(started.getTime())) return storedRemainingMs;
  return Math.max(0, storedRemainingMs - (Date.now() - started.getTime()));
}

function mapGame(row: RowDataPacket): Game {
  const storedRemainingMs = Number(row.clock_remaining_ms ?? 0);
  const clockRunning = Boolean(row.clock_running);
  const clockRemainingMs = effectiveClockRemainingMs(
    storedRemainingMs,
    clockRunning,
    row.clock_started_at,
  );

  const intermissionStoredRemainingMs = Number(row.intermission_remaining_ms ?? 0);
  const intermissionRunning = Boolean(row.intermission_running);
  const intermissionRemainingMs = effectiveIntermissionRemainingMs(
    intermissionStoredRemainingMs,
    intermissionRunning,
    row.intermission_started_at,
  );

  const homeExternalName = row.home_external_name == null ? null : String(row.home_external_name);
  const awayExternalName = row.away_external_name == null ? null : String(row.away_external_name);

  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    organizationLogoUrl: logoUrl(
      row.organization_logo_asset_id == null ? null : Number(row.organization_logo_asset_id),
    ),
    organizationPrimaryColor: String(row.organization_primary_color ?? "#ef4444"),
    organizationSecondaryColor: String(row.organization_secondary_color ?? "#0f172a"),
    seasonId: Number(row.season_id),
    seasonName: String(row.season_name),

    homeTeamId: row.home_team_id == null ? null : Number(row.home_team_id),
    homeTeamName:
      row.registered_home_team_name == null
        ? (homeExternalName ?? "Home team")
        : String(row.registered_home_team_name),
    homeTeamOrganizationName:
      row.home_team_organization_name == null ? null : String(row.home_team_organization_name),
    homeExternalName,
    homeTeamLogoUrl: logoUrl(
      row.home_logo_asset_id == null ? null : Number(row.home_logo_asset_id),
    ),
    homeTeamPrimaryColor: String(
      row.home_primary_color ?? row.organization_primary_color ?? "#ef4444",
    ),
    homeTeamSecondaryColor: String(
      row.home_secondary_color ?? row.organization_secondary_color ?? "#0f172a",
    ),

    awayTeamId: row.away_team_id == null ? null : Number(row.away_team_id),
    awayTeamName:
      row.registered_away_team_name == null
        ? (awayExternalName ?? "Away team")
        : String(row.registered_away_team_name),
    awayTeamOrganizationName:
      row.away_team_organization_name == null ? null : String(row.away_team_organization_name),
    awayExternalName,
    awayTeamLogoUrl: logoUrl(
      row.away_logo_asset_id == null ? null : Number(row.away_logo_asset_id),
    ),
    awayTeamPrimaryColor: String(
      row.away_primary_color ?? row.organization_primary_color ?? "#64748b",
    ),
    awayTeamSecondaryColor: String(
      row.away_secondary_color ?? row.organization_secondary_color ?? "#0f172a",
    ),

    scheduledStart:
      row.scheduled_start instanceof Date
        ? row.scheduled_start.toISOString()
        : String(row.scheduled_start),
    timezone: String(row.timezone),
    venue: row.venue == null ? null : String(row.venue),
    status: String(row.status) as GameStatus,
    homeScore: Number(row.home_score),
    awayScore: Number(row.away_score),
    period: Number(row.period ?? 1),
    periodLengthMs: Number(row.period_length_ms ?? 1_200_000),
    clockRemainingMs,
    clockRunning: clockRunning && clockRemainingMs > 0,
    clockStartedAt: clockRunning && clockRemainingMs > 0 ? new Date().toISOString() : null,
    regulationPeriods: Number(row.regulation_periods ?? 3),
    regulationPeriodLengthMs: Number(
      row.regulation_period_length_ms ?? row.period_length_ms ?? 1_200_000,
    ),
    intermissionLengthMs: Number(row.intermission_length_ms ?? 900_000),
    intermissionRemainingMs,
    intermissionRunning: intermissionRunning && intermissionRemainingMs > 0,
    intermissionStartedAt:
      intermissionRunning && intermissionRemainingMs > 0 ? new Date().toISOString() : null,
    intermissionReady:
      intermissionStoredRemainingMs === 0 &&
      !intermissionRunning &&
      Number(row.clock_remaining_ms ?? 0) === 0,
    overtimeEnabled: Boolean(row.overtime_enabled ?? true),
    overtimeLengthMs: Number(row.overtime_length_ms ?? 300_000),
    periodLabel:
      Number(row.period ?? 1) > Number(row.regulation_periods ?? 3)
        ? "OVERTIME"
        : `PERIOD ${Number(row.period ?? 1)}`,
    canAdvancePeriod: String(row.status) !== "FINAL" && clockRemainingMs === 0,
    notes: row.notes == null ? null : String(row.notes),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export interface GameFilters {
  organizationId?: number;
  seasonId?: number;
  teamId?: number;
  status?: GameStatus;
  search?: string;
}

export async function listGameTeamOptions(): Promise<GameTeamOption[]> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT
       t.id,
       t.organization_id,
       o.name AS organization_name,
       t.name
     FROM teams t
     JOIN organizations o ON o.id = t.organization_id
     WHERE t.active = TRUE
     ORDER BY o.name, t.name`,
  );

  return rows.map((row) => ({
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    organizationName: String(row.organization_name),
    name: String(row.name),
  }));
}

export async function listGames(filters: GameFilters): Promise<Game[]> {
  const conditions: string[] = [];
  const params: Array<string | number> = [];

  if (filters.organizationId !== undefined) {
    conditions.push("g.organization_id = ?");
    params.push(filters.organizationId);
  }

  if (filters.seasonId !== undefined) {
    conditions.push("g.season_id = ?");
    params.push(filters.seasonId);
  }

  if (filters.teamId !== undefined) {
    conditions.push("(g.home_team_id = ? OR g.away_team_id = ?)");
    params.push(filters.teamId, filters.teamId);
  }

  if (filters.status !== undefined) {
    conditions.push("g.status = ?");
    params.push(filters.status);
  }

  const search = filters.search?.trim();

  if (search) {
    conditions.push(`(
      home.name LIKE ?
      OR away.name LIKE ?
      OR g.home_external_name LIKE ?
      OR g.away_external_name LIKE ?
      OR g.venue LIKE ?
    )`);
    const like = `%${search}%`;
    params.push(like, like, like, like, like);
  }

  const where = conditions.length ? ` WHERE ${conditions.join(" AND ")}` : "";

  const [rows] = await pool.execute<RowDataPacket[]>(
    `${SELECT_GAME}${where}
     ORDER BY g.scheduled_start DESC, g.id DESC`,
    params,
  );

  return rows.map(mapGame);
}

export async function findGameById(id: number): Promise<Game | null> {
  const [rows] = await pool.execute<RowDataPacket[]>(`${SELECT_GAME} WHERE g.id = ? LIMIT 1`, [id]);

  return rows[0] ? mapGame(rows[0]) : null;
}

export async function validateGameRelationships(
  input: Pick<GameInput, "organizationId" | "seasonId" | "homeTeamId" | "awayTeamId">,
): Promise<"organization" | "season" | "homeTeam" | "awayTeam" | null> {
  const [organizations] = await pool.execute<RowDataPacket[]>(
    "SELECT id FROM organizations WHERE id = ? LIMIT 1",
    [input.organizationId],
  );
  if (!organizations[0]) return "organization";

  const [seasons] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM seasons
     WHERE id = ? AND organization_id = ?
     LIMIT 1`,
    [input.seasonId, input.organizationId],
  );
  if (!seasons[0]) return "season";

  if (input.homeTeamId !== null) {
    const [homeTeams] = await pool.execute<RowDataPacket[]>(
      "SELECT id FROM teams WHERE id = ? LIMIT 1",
      [input.homeTeamId],
    );
    if (!homeTeams[0]) return "homeTeam";
  }

  if (input.awayTeamId !== null) {
    const [awayTeams] = await pool.execute<RowDataPacket[]>(
      "SELECT id FROM teams WHERE id = ? LIMIT 1",
      [input.awayTeamId],
    );
    if (!awayTeams[0]) return "awayTeam";
  }

  return null;
}

export async function createGame(input: GameInput): Promise<Game> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `INSERT INTO games (
       organization_id,
       season_id,
       home_team_id,
       home_external_name,
       away_team_id,
       away_external_name,
       scheduled_start,
       timezone,
       venue,
       status,
       home_score,
       away_score,
       period_length_ms,
       clock_remaining_ms,
       regulation_periods,
       regulation_period_length_ms,
       intermission_length_ms,
       overtime_enabled,
       overtime_length_ms,
       notes
     )
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      input.organizationId,
      input.seasonId,
      input.homeTeamId,
      input.homeTeamId ? null : input.homeExternalName,
      input.awayTeamId,
      input.awayTeamId ? null : input.awayExternalName,
      new Date(input.scheduledStart),
      input.timezone,
      input.venue,
      input.status,
      input.homeScore,
      input.awayScore,
      input.regulationPeriodLengthMs,
      input.regulationPeriodLengthMs,
      input.regulationPeriods,
      input.regulationPeriodLengthMs,
      input.intermissionLengthMs,
      input.overtimeEnabled,
      input.overtimeLengthMs,
      input.notes,
    ],
  );

  const game = await findGameById(result.insertId);
  if (!game) throw new Error("Game could not be read after creation");
  return game;
}

export async function updateGame(id: number, input: GameInput): Promise<Game | null> {
  const [result] = await pool.execute<mysql.ResultSetHeader>(
    `UPDATE games SET
       organization_id = ?,
       season_id = ?,
       home_team_id = ?,
       home_external_name = ?,
       away_team_id = ?,
       away_external_name = ?,
       scheduled_start = ?,
       timezone = ?,
       venue = ?,
       status = ?,
       home_score = ?,
       away_score = ?,
       regulation_periods = ?,
       regulation_period_length_ms = ?,
       intermission_length_ms = ?,
       overtime_enabled = ?,
       overtime_length_ms = ?,
       notes = ?
     WHERE id = ?`,
    [
      input.organizationId,
      input.seasonId,
      input.homeTeamId,
      input.homeTeamId ? null : input.homeExternalName,
      input.awayTeamId,
      input.awayTeamId ? null : input.awayExternalName,
      new Date(input.scheduledStart),
      input.timezone,
      input.venue,
      input.status,
      input.homeScore,
      input.awayScore,
      input.regulationPeriods,
      input.regulationPeriodLengthMs,
      input.intermissionLengthMs,
      input.overtimeEnabled,
      input.overtimeLengthMs,
      input.notes,
      id,
    ],
  );

  if (!result.affectedRows) return null;
  return findGameById(id);
}

export async function deleteGame(id: number): Promise<boolean> {
  const [result] = await pool.execute<mysql.ResultSetHeader>("DELETE FROM games WHERE id = ?", [
    id,
  ]);
  return result.affectedRows > 0;
}

export class GamePhaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GamePhaseError";
  }
}

interface LockedScoringRow extends RowDataPacket {
  id: number;
  home_score: number;
  away_score: number;
  status: GameStatus;
  period: number;
  period_length_ms: number;
  clock_remaining_ms: number;
  clock_running: number;
  clock_started_at: Date | null;
  regulation_periods: number;
  regulation_period_length_ms: number;
  intermission_length_ms: number;
  overtime_enabled: number;
  overtime_length_ms: number;
  intermission_remaining_ms: number;
  intermission_running: number;
  intermission_started_at: Date | null;
}

function materializedRemainingMs(row: LockedScoringRow): number {
  return effectiveClockRemainingMs(
    Number(row.clock_remaining_ms),
    Boolean(row.clock_running),
    row.clock_started_at,
  );
}

async function lockGame(connection: PoolConnection, id: number): Promise<LockedScoringRow | null> {
  const [rows] = await connection.execute<LockedScoringRow[]>(
    `SELECT
       id,
       home_score,
       away_score,
       status,
       period,
       period_length_ms,
       clock_remaining_ms,
       clock_running,
       clock_started_at,
       regulation_periods,
       regulation_period_length_ms,
       intermission_length_ms,
       overtime_enabled,
       overtime_length_ms,
       intermission_remaining_ms,
       intermission_running,
       intermission_started_at
     FROM games
     WHERE id = ?
     FOR UPDATE`,
    [id],
  );

  return rows[0] ?? null;
}

export async function applyGameScoringAction(
  id: number,
  action: ScoreAction,
): Promise<Game | null> {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const row = await lockGame(connection, id);
    if (!row) {
      await connection.rollback();
      return null;
    }

    let homeScore = Number(row.home_score);
    let awayScore = Number(row.away_score);
    let status = row.status;
    let period = Number(row.period);
    let periodLengthMs = Number(row.period_length_ms);
    let clockRemainingMs = materializedRemainingMs(row);
    let clockRunning = Boolean(row.clock_running) && clockRemainingMs > 0;
    let clockStartedAt: Date | null = clockRunning ? new Date() : null;
    let intermissionLengthMs = Number(row.intermission_length_ms ?? 0);
    let intermissionRemainingMs = effectiveIntermissionRemainingMs(
      Number(row.intermission_remaining_ms ?? 0),
      Boolean(row.intermission_running),
      row.intermission_started_at,
    );
    let intermissionRunning = Boolean(row.intermission_running) && intermissionRemainingMs > 0;
    let intermissionStartedAt: Date | null = intermissionRunning ? new Date() : null;

    const intermissionPaused =
      !intermissionRunning &&
      intermissionRemainingMs > 0 &&
      intermissionRemainingMs < intermissionLengthMs;

    await materializePenaltyClocks(connection, id);
    const previousClockRemainingMs = clockRemainingMs;

    switch (action.action) {
      case "adjustScore":
        if (action.side === "home") {
          homeScore = Math.max(0, Math.min(999, homeScore + action.amount));
        } else {
          awayScore = Math.max(0, Math.min(999, awayScore + action.amount));
        }
        break;
      case "setScore":
        homeScore = action.homeScore;
        awayScore = action.awayScore;
        break;
      case "startClock":
        if (status === "FINAL") {
          throw new GamePhaseError("A final game cannot be restarted");
        }
        if (intermissionRunning || intermissionPaused) {
          throw new GamePhaseError("Finish or skip intermission before starting the game clock");
        }
        if (clockRemainingMs > 0) {
          clockRunning = true;
          clockStartedAt = new Date();
          if (status === "SCHEDULED") status = "LIVE";
        }
        break;
      case "pauseClock":
        clockRunning = false;
        clockStartedAt = null;
        break;
      case "startIntermission":
        if (status === "FINAL") {
          throw new GamePhaseError("Intermission cannot start after the game is final");
        }
        if (clockRemainingMs > 0) {
          throw new GamePhaseError("Intermission can start only when the game clock is at 0:00");
        }
        clockRunning = false;
        clockStartedAt = null;
        if (intermissionRemainingMs <= 0) {
          intermissionRemainingMs = Number(row.intermission_length_ms ?? 0);
        }
        intermissionRunning = intermissionRemainingMs > 0;
        intermissionStartedAt = intermissionRunning ? new Date() : null;
        break;
      case "pauseIntermission":
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      case "resetIntermission":
        intermissionRemainingMs = intermissionLengthMs;
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      case "setIntermission":
        intermissionLengthMs = action.intermissionLengthMs;
        intermissionRemainingMs = action.intermissionLengthMs;
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      case "skipIntermission":
        intermissionRemainingMs = 0;
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      case "nextPeriod": {
        clockRunning = false;
        clockStartedAt = null;

        const regulationPeriods = Number(row.regulation_periods ?? 3);
        const regulationLength = periodLengthMs;

        if (status === "FINAL") {
          throw new GamePhaseError("A final game cannot advance to another period");
        }
        if (clockRemainingMs > 0) {
          throw new GamePhaseError("The game clock must be at 0:00 before advancing periods");
        }
        if (intermissionRunning || intermissionRemainingMs > 0) {
          throw new GamePhaseError("Finish or skip intermission before advancing periods");
        }
        if (period >= regulationPeriods) {
          throw new GamePhaseError("Choose overtime or final after regulation has ended");
        }

        period += 1;
        periodLengthMs = regulationLength;
        clockRemainingMs = regulationLength;
        intermissionRemainingMs = 0;
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      }

      case "startOvertime": {
        clockRunning = false;
        clockStartedAt = null;

        const regulationPeriods = Number(row.regulation_periods ?? 3);
        const overtimeEnabled = Boolean(row.overtime_enabled);
        const overtimeLength = Number(row.overtime_length_ms ?? 300_000);

        if (status === "FINAL") {
          throw new GamePhaseError("A final game cannot enter overtime");
        }
        if (!overtimeEnabled) {
          throw new GamePhaseError("Overtime is disabled for this game");
        }
        if (period < regulationPeriods) {
          throw new GamePhaseError("Regulation has not ended");
        }
        if (clockRemainingMs > 0) {
          throw new GamePhaseError("Regulation must reach 0:00 before overtime");
        }
        if (intermissionRunning || intermissionRemainingMs > 0) {
          throw new GamePhaseError("Finish or skip intermission before starting overtime");
        }

        period = Math.max(period + 1, regulationPeriods + 1);
        periodLengthMs = overtimeLength;
        clockRemainingMs = overtimeLength;
        clockRunning = false;
        clockStartedAt = null;
        status = "LIVE";
        intermissionRemainingMs = 0;
        intermissionRunning = false;
        intermissionStartedAt = null;
        break;
      }

      case "finishGame":
        clockRunning = false;
        clockStartedAt = null;
        clockRemainingMs = 0;
        intermissionRemainingMs = 0;
        intermissionRunning = false;
        intermissionStartedAt = null;
        status = "FINAL";
        break;

      case "resetClock":
        periodLengthMs = action.periodLengthMs ?? periodLengthMs;
        clockRemainingMs = periodLengthMs;
        clockRunning = false;
        clockStartedAt = null;
        break;
      case "adjustClock":
        clockRemainingMs = Math.max(0, Math.min(7_200_000, clockRemainingMs + action.amountMs));
        clockRunning = clockRunning && clockRemainingMs > 0;
        clockStartedAt = clockRunning ? new Date() : null;
        break;
      case "setClock":
        clockRemainingMs = action.clockRemainingMs;
        periodLengthMs = action.clockRemainingMs;
        clockRunning = false;
        clockStartedAt = null;
        break;
      case "setPeriod":
        period = action.period;
        intermissionRemainingMs = 0;
        intermissionRunning = false;
        intermissionStartedAt = null;
        clockStartedAt = clockRunning ? new Date() : null;
        break;
      case "setStatus":
        status = action.status;
        if (status !== "LIVE") {
          clockRunning = false;
          clockStartedAt = null;
          intermissionRunning = false;
          intermissionStartedAt = null;
        }
        if (status === "FINAL") {
          clockRemainingMs = 0;
          intermissionRemainingMs = 0;
        }
        break;
    }

    if (clockRemainingMs === 0) {
      clockRunning = false;
      clockStartedAt = null;
    }

    const penaltyClockAdjustmentMs =
      action.action === "adjustClock" ||
      action.action === "setClock" ||
      action.action === "resetClock"
        ? clockRemainingMs - previousClockRemainingMs
        : 0;

    await adjustActivePenaltyClocks(connection, id, penaltyClockAdjustmentMs);

    await connection.execute(
      `UPDATE games SET
       home_score = ?,
       away_score = ?,
       status = ?,
       period = ?,
       period_length_ms = ?,
       clock_remaining_ms = ?,
       clock_running = ?,
       clock_started_at = ?,
       intermission_length_ms = ?,
       intermission_remaining_ms = ?,
       intermission_running = ?,
       intermission_started_at = ?
       WHERE id = ?`,
      [
        homeScore,
        awayScore,
        status,
        period,
        periodLengthMs,
        clockRemainingMs,
        clockRunning,
        clockStartedAt,
        intermissionLengthMs,
        intermissionRemainingMs,
        intermissionRunning,
        intermissionStartedAt,
        id,
      ],
    );

    await setPenaltyClockRunning(
      connection,
      id,
      clockRunning && status === "LIVE" && !intermissionRunning,
    );

    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }

  return findGameById(id);
}
