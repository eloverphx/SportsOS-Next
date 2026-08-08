import type { GameEvent } from "./game-events.js";
import type { GamePhase, GameStatus } from "./games.js";
import type { ScoreboardDeviceStatus } from "./scoreboard-devices.js";

export type RealtimeSubscriptionScope = "game" | "scoreboard-device";

export interface SystemHelloPayload {
  message: string;
  timestamp: string;
  authenticated: boolean;
}

export interface SubscriptionRejectedPayload {
  scope: RealtimeSubscriptionScope;
  id: number | null;
  reason: string;
}

export interface GameSubscriptionPayload {
  gameId: number;
}

export interface ScoreboardDeviceSubscriptionPayload {
  deviceId: number;
}

export interface GameReferencePayload {
  id?: number;
  gameId?: number;
  organizationId?: number;
}

export interface GameChangedPayload {
  id: number;
  organizationId: number;
  gameId?: number;
}

export type GameScoringActionPayload =
  | { action: "adjustScore"; side: "home" | "away"; amount: number }
  | { action: "setScore"; homeScore: number; awayScore: number }
  | { action: "startClock" }
  | { action: "pauseClock" }
  | { action: "startIntermission" }
  | { action: "pauseIntermission" }
  | { action: "resetIntermission" }
  | { action: "setIntermission"; intermissionLengthMs: number }
  | { action: "skipIntermission" }
  | { action: "nextPeriod" }
  | { action: "startOvertime" }
  | { action: "finishGame" }
  | { action: "resetClock"; periodLengthMs?: number }
  | { action: "adjustClock"; amountMs: number }
  | { action: "setClock"; clockRemainingMs: number }
  | { action: "setPeriod"; period: number }
  | { action: "setStatus"; status: GameStatus };

export interface GameScoredPayload {
  id: number;
  gameId: number;
  organizationId: number;
  action: GameScoringActionPayload;
  replayed: boolean;
  homeScore: number;
  awayScore: number;
  period: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  status: GameStatus;
  gamePhase: GamePhase;
}

export interface GameEventChangedPayload {
  gameId: number;
  event: GameEvent;
}

export interface GamePenaltiesUpdatedPayload {
  gameId: number;
}

export type GamesChangedReason =
  | "created"
  | "updated"
  | "deleted"
  | "scored"
  | "clock-expired"
  | "intermission-expired"
  | "event";

export interface GamesChangedPayload {
  reason: GamesChangedReason;
  id: number;
  organizationId: number;
}

export type BroadcastEffectType = "GOAL" | "PENALTY" | "PENALTY_ENDED";
export type BroadcastSoundType = "GOAL" | "PENALTY" | "HORN" | "INTERMISSION_COMPLETE";

export interface BroadcastEffectPayload {
  gameId: number;
  effectId: string;
  type: BroadcastEffectType;
  side: "home" | "away";
  playerName?: string | null;
  jerseyNumber?: number | null;
  infraction?: string | null;
  penaltyMinutes?: number | null;
  createdAt?: string;
}

export interface BroadcastSoundPayload {
  gameId: number;
  soundId: string;
  type: BroadcastSoundType;
}

export interface ScoreboardDeviceChangedPayload {
  id: number;
  organizationId: number;
  gameId: number | null;
}

export interface ScoreboardDeviceDeletedPayload {
  id: number;
  organizationId: number;
}

export interface ScoreboardDeviceStatusPayload {
  id: number;
  organizationId: number;
  status: ScoreboardDeviceStatus;
  lastSeenAt: Date | string | null;
}

export type ScoreboardDevicesChangedReason = "created" | "updated" | "status" | "deleted";

export interface ScoreboardDevicesChangedPayload {
  reason: ScoreboardDevicesChangedReason;
  id: number;
}

export interface RealtimeServerEvents {
  "system:hello": (payload: SystemHelloPayload) => void;
  "subscription:rejected": (payload: SubscriptionRejectedPayload) => void;

  "game:scored": (payload: GameScoredPayload) => void;
  "game:updated": (payload: GameChangedPayload) => void;
  "game:deleted": (payload: GameChangedPayload) => void;
  "game:clock-expired": (payload: GameChangedPayload) => void;
  "game:intermission-expired": (payload: GameChangedPayload) => void;
  "game:penalties-updated": (payload: GamePenaltiesUpdatedPayload) => void;
  "game:event-created": (payload: GameEventChangedPayload) => void;
  "game:event-voided": (payload: GameEventChangedPayload) => void;
  "games:changed": (payload: GamesChangedPayload) => void;

  "scoreboard:effect": (payload: BroadcastEffectPayload) => void;
  "scoreboard:sound": (payload: BroadcastSoundPayload) => void;

  "scoreboard-device:updated": (payload: ScoreboardDeviceChangedPayload) => void;
  "scoreboard-device:deleted": (payload: ScoreboardDeviceDeletedPayload) => void;
  "scoreboard-device:status": (payload: ScoreboardDeviceStatusPayload) => void;
  "scoreboard-devices:changed": (payload: ScoreboardDevicesChangedPayload) => void;
}

export interface RealtimeClientEvents {
  "public-game:subscribe": (payload: GameSubscriptionPayload) => void;
  "game:subscribe": (payload: GameSubscriptionPayload) => void;
  "game:leave": (payload: GameSubscriptionPayload) => void;
  "scoreboard-device:subscribe": (payload: ScoreboardDeviceSubscriptionPayload) => void;
  "scoreboard-device:leave": (payload: ScoreboardDeviceSubscriptionPayload) => void;
}

export type RealtimeOutboxEventName =
  | "game:scored"
  | "game:updated"
  | "game:clock-expired"
  | "game:intermission-expired"
  | "game:event-created"
  | "game:event-voided"
  | "games:changed"
  | "scoreboard:effect"
  | "scoreboard:sound";

export type RealtimePayload<EventName extends keyof RealtimeServerEvents> = Parameters<
  RealtimeServerEvents[EventName]
>[0];

export type RealtimeOutboxEvent = {
  [EventName in RealtimeOutboxEventName]: {
    readonly event: EventName;
    readonly room?: string | null;
    readonly payload: RealtimePayload<EventName>;
  };
}[RealtimeOutboxEventName];
