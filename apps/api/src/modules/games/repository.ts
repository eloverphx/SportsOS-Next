import mysql, { type PoolConnection, type RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { enqueueRealtimeEvent } from "../../infrastructure/realtime-outbox.js";
import { logoUrl } from "../../lib/media.js";
import type { GameInput, ScoreAction } from "./schemas.js";
import type { Game, GamePhase, GameStatus, GameTeamOption } from "./types.js";
import {
  applyGameEngineAction,
  type GameEngineState,
} from "./engine.js";
export { GamePhaseError } from "./engine.js";
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
    gamePhase: String(row.game_phase ?? "PREGAME") as GamePhase,
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
      String(row.game_phase) === "INTERMISSION" &&
      intermissionRemainingMs === 0 &&
      Number(row.clock_remaining_ms ?? 0) === 0,
    overtimeEnabled: Boolean(row.overtime_enabled ?? true),
    overtimeLengthMs: Number(row.overtime_length_ms ?? 300_000),
    periodLabel:
      Number(row.period ?? 1) > Number(row.regulation_periods ?? 3)
        ? "OVERTIME"
        : `PERIOD ${Number(row.period ?? 1)}`,
    canAdvancePeriod:
      String(row.status) !== "FINAL" &&
      clockRemainingMs === 0 &&
      (String(row.game_phase) !== "INTERMISSION" || intermissionRemainingMs === 0),
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

export async function listGameTeamOptionsUsingConnection(
  connection: PoolConnection,
): Promise<GameTeamOption[]> {
  const [rows] = await connection.execute<RowDataPacket[]>(
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

export async function listGameTeamOptions(): Promise<GameTeamOption[]> {
  const connection = await pool.getConnection();
  try {
    return await listGameTeamOptionsUsingConnection(connection);
  } finally {
    connection.release();
  }
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

export async function listGamesByOrganizationUsingConnection(
  connection: PoolConnection,
  organizationId: number,
): Promise<Game[]> {
  const [rows] = await connection.execute<RowDataPacket[]>(
    `${SELECT_GAME} WHERE g.organization_id = ?
     ORDER BY g.scheduled_start DESC, g.id DESC`,
    [organizationId],
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

export async function createGameUsingConnection(
  connection: PoolConnection,
  input: GameInput,
): Promise<number> {
  const [result] = await connection.execute<mysql.ResultSetHeader>(
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

  return result.insertId;
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

export async function updateGameUsingConnection(
  connection: PoolConnection,
  id: number,
  input: GameInput,
): Promise<boolean> {
  const [result] = await connection.execute<mysql.ResultSetHeader>(
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

  return result.affectedRows > 0;
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


export class IdempotencyConflictError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IdempotencyConflictError";
  }
}

export interface ScoringActionApplication {
  readonly game: Game;
  readonly applied: boolean;
}

interface LockedScoringRow extends RowDataPacket {
  id: number;
  organization_id: number;
  home_score: number;
  away_score: number;
  status: GameStatus;
  game_phase: GamePhase;
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
       organization_id,
       home_score,
       away_score,
       status,
       game_phase,
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
  actionId?: string,
): Promise<ScoringActionApplication | null> {
  const connection = await pool.getConnection();
  let applied = true;

  try {
    await connection.beginTransaction();

    const row = await lockGame(connection, id);
    if (!row) {
      await connection.rollback();
      return null;
    }

    if (actionId) {
      const actionPayload = JSON.stringify(action);
      const [requests] = await connection.execute<RowDataPacket[]>(
        `SELECT action_payload
         FROM game_action_requests
         WHERE game_id = ? AND action_id = ?
         LIMIT 1
         FOR UPDATE`,
        [id, actionId],
      );

      const existingRequest = requests[0];

      if (existingRequest) {
        if (String(existingRequest.action_payload) !== actionPayload) {
          throw new IdempotencyConflictError(
            "This actionId was already used for a different scoring action",
          );
        }

        applied = false;
        await connection.commit();
      } else {
        await connection.execute(
          `INSERT INTO game_action_requests (game_id, action_id, action_payload)
           VALUES (?, ?, ?)`,
          [id, actionId, actionPayload],
        );
      }
    }

    if (!applied) {
      // The game row was locked before the request ledger was checked, so a
      // replay always observes the previously committed authoritative state.
      return null;
    }

    const clockRemainingMsAtAction = materializedRemainingMs(row);
    const intermissionRemainingMsAtAction = effectiveIntermissionRemainingMs(
      Number(row.intermission_remaining_ms ?? 0),
      Boolean(row.intermission_running),
      row.intermission_started_at,
    );

    const engineState: GameEngineState = {
      homeScore: Number(row.home_score),
      awayScore: Number(row.away_score),
      status: row.status,
      gamePhase: row.game_phase ?? (row.status === "FINAL" ? "FINAL" : "PREGAME"),
      period: Number(row.period),
      periodLengthMs: Number(row.period_length_ms),
      clockRemainingMs: clockRemainingMsAtAction,
      clockRunning: Boolean(row.clock_running) && clockRemainingMsAtAction > 0,
      clockStartedAt:
        Boolean(row.clock_running) && clockRemainingMsAtAction > 0
          ? new Date()
          : null,
      regulationPeriods: Number(row.regulation_periods ?? 3),
      regulationPeriodLengthMs: Number(
        row.regulation_period_length_ms ?? row.period_length_ms,
      ),
      intermissionLengthMs: Number(row.intermission_length_ms ?? 0),
      intermissionRemainingMs: intermissionRemainingMsAtAction,
      intermissionRunning:
        Boolean(row.intermission_running) && intermissionRemainingMsAtAction > 0,
      intermissionStartedAt:
        Boolean(row.intermission_running) && intermissionRemainingMsAtAction > 0
          ? new Date()
          : null,
      overtimeEnabled: Boolean(row.overtime_enabled),
      overtimeLengthMs: Number(row.overtime_length_ms ?? 300_000),
    };

    await materializePenaltyClocks(connection, id);

    const transition = applyGameEngineAction(engineState, action);
    const {
      homeScore,
      awayScore,
      status,
      gamePhase,
      period,
      periodLengthMs,
      clockRemainingMs,
      clockRunning,
      clockStartedAt,
      intermissionLengthMs,
      intermissionRemainingMs,
      intermissionRunning,
      intermissionStartedAt,
    } = transition.state;

    await adjustActivePenaltyClocks(
      connection,
      id,
      transition.penaltyClockAdjustmentMs,
    );

    await connection.execute(
      `UPDATE games SET
       home_score = ?,
       away_score = ?,
       status = ?,
       game_phase = ?,
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
        gamePhase,
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

    const organizationId = Number(row.organization_id);
    const room = `game:${id}`;

    await enqueueRealtimeEvent(connection, {
      room,
      event: "game:scored",
      payload: {
        id,
        gameId: id,
        organizationId,
        action,
        replayed: false,
        homeScore,
        awayScore,
        period,
        clockRemainingMs,
        clockRunning,
        status,
        gamePhase,
      },
    });

    await enqueueRealtimeEvent(connection, {
      room,
      event: "game:updated",
      payload: {
        id,
        gameId: id,
        organizationId,
      },
    });

    await enqueueRealtimeEvent(connection, {
      event: "games:changed",
      payload: {
        reason: "scored",
        id,
        organizationId,
      },
    });

    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }

  const game = await findGameById(id);
  return game ? { game, applied } : null;
}
