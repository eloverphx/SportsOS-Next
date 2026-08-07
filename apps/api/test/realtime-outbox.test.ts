import { beforeEach, describe, expect, it, vi } from "vitest";

const poolQuery = vi.fn();
const poolExecute = vi.fn();
const emit = vi.fn();
const to = vi.fn(() => ({ emit }));

vi.mock("../src/infrastructure/database.js", () => ({
  pool: {
    query: poolQuery,
    execute: poolExecute,
  },
}));

vi.mock("../src/infrastructure/realtime.js", () => ({
  realtime: () => ({
    emit,
    to,
  }),
}));

const { dispatchRealtimeOutboxBatch, enqueueRealtimeEvent } = await import(
  "../src/infrastructure/realtime-outbox.js"
);

describe("realtime outbox", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("enqueues an event through the provided transaction connection", async () => {
    const execute = vi.fn().mockResolvedValue([{ affectedRows: 1 }]);
    const connection = { execute } as never;

    await enqueueRealtimeEvent(connection, {
      room: "game:42",
      event: "game:updated",
      payload: { gameId: 42 },
    });

    expect(execute).toHaveBeenCalledTimes(1);
    expect(String(execute.mock.calls[0]?.[0])).toContain("INSERT INTO realtime_outbox");
    expect(execute.mock.calls[0]?.[1]).toEqual([
      "game:updated",
      "game:42",
      JSON.stringify({ gameId: 42 }),
    ]);
  });

  it("delivers a room-scoped event and marks it delivered", async () => {
    poolQuery.mockResolvedValue([
      [
        {
          id: 7,
          event_name: "game:updated",
          room_name: "game:42",
          payload_json: JSON.stringify({ gameId: 42 }),
          attempts: 0,
        },
      ],
    ]);
    poolExecute.mockResolvedValue([{ affectedRows: 1 }]);

    await expect(dispatchRealtimeOutboxBatch()).resolves.toBe(1);

    expect(to).toHaveBeenCalledWith("game:42");
    expect(emit).toHaveBeenCalledWith("game:updated", { gameId: 42 });
    expect(
      poolExecute.mock.calls.some(([sql]) =>
        String(sql).includes("SET delivered_at = UTC_TIMESTAMP(3)"),
      ),
    ).toBe(true);
  });

  it("leaves a failed event pending and schedules a retry", async () => {
    poolQuery.mockResolvedValue([
      [
        {
          id: 8,
          event_name: "game:updated",
          room_name: "game:42",
          payload_json: "{bad-json",
          attempts: 0,
        },
      ],
    ]);
    poolExecute.mockResolvedValue([{ affectedRows: 1 }]);

    await expect(dispatchRealtimeOutboxBatch()).resolves.toBe(0);

    expect(
      poolExecute.mock.calls.some(([sql]) => String(sql).includes("available_at = DATE_ADD")),
    ).toBe(true);
  });
});
