export type FinalizedGameResult = {
  gameId: string;
  homeScore: number;
  awayScore: number;
  status: string;
  gamePhase: string | null;
  finalizedAt: string;
};

export function buildFinalizedGameResult(input: {
  gameId: string;
  homeScore: unknown;
  awayScore: unknown;
  status: unknown;
  gamePhase?: unknown;
  finalizedAt?: Date;
}): FinalizedGameResult {
  if (
    typeof input.homeScore !== "number" ||
    !Number.isFinite(input.homeScore) ||
    typeof input.awayScore !== "number" ||
    !Number.isFinite(input.awayScore)
  ) {
    throw new Error("Finalized game response has invalid scores.");
  }

  if (typeof input.status !== "string" || !input.status.trim()) {
    throw new Error("Finalized game response has invalid status.");
  }

  return {
    gameId: input.gameId,
    homeScore: input.homeScore,
    awayScore: input.awayScore,
    status: input.status,
    gamePhase:
      typeof input.gamePhase === "string"
        ? input.gamePhase
        : null,
    finalizedAt: (input.finalizedAt ?? new Date()).toISOString(),
  };
}

export function resultLabel(
  result: FinalizedGameResult,
): string {
  if (result.homeScore > result.awayScore) return "Home win";
  if (result.awayScore > result.homeScore) return "Away win";
  return "Tie";
}
