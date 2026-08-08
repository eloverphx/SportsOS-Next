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

const {
  claimRealtimeOutboxBatch,
  cleanupDeliveredRealtimeOutbox,
  dispatchRealtimeOutboxBatch,
  enqueueRealtimeEvent,
} = await import("../src/infrastructure/realtime-outbox.js");

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

  it("claims rows with a worker lease before reading them", async () => {
    poolExecute.mockResolvedValueOnce([{ affectedRows: 1 }]);
    poolQuery.mockResolvedValueOnce([
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

    const rows = await claimRealtimeOutboxBatch("worker-a", 25);

    expect(rows).toHaveLength(1);
    expect(String(poolExecute.mock.calls[0]?.[0])).toContain("SET claimed_at = UTC_TIMESTAMP(3)");
    expect(String(poolExecute.mock.calls[0]?.[0])).toContain("claimed_at < DATE_SUB");
    expect(poolExecute.mock.calls[0]?.[1]).toEqual(["worker-a"]);
    expect(String(poolQuery.mock.calls[0]?.[0])).toContain("claimed_by = ?");
    expect(poolQuery.mock.calls[0]?.[1]).toEqual(["worker-a"]);
  });

  it("delivers only its claimed row and clears the lease", async () => {
    poolExecute
      .mockResolvedValueOnce([{ affectedRows: 1 }])
      .mockResolvedValueOnce([{ affectedRows: 1 }]);
    poolQuery.mockResolvedValueOnce([
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

    await expect(dispatchRealtimeOutboxBatch(100, "worker-a")).resolves.toBe(1);

    expect(to).toHaveBeenCalledWith("game:42");
    expect(emit).toHaveBeenCalledWith("game:updated", { gameId: 42 });

    const deliveryCall = poolExecute.mock.calls.find(([sql]) =>
      String(sql).includes("SET delivered_at = UTC_TIMESTAMP(3)"),
    );

    expect(deliveryCall).toBeTruthy();
    expect(String(deliveryCall?.[0])).toContain("claimed_by = ?");
    expect(String(deliveryCall?.[0])).toContain("claimed_at = NULL");
    expect(deliveryCall?.[1]).toEqual([7, "worker-a"]);
  });

  it("releases a failed claim and schedules a retry", async () => {
    poolExecute
      .mockResolvedValueOnce([{ affectedRows: 1 }])
      .mockResolvedValueOnce([{ affectedRows: 1 }]);
    poolQuery.mockResolvedValueOnce([
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

    await expect(dispatchRealtimeOutboxBatch(100, "worker-b")).resolves.toBe(0);

    const retryCall = poolExecute.mock.calls.find(([sql]) =>
      String(sql).includes("available_at = DATE_ADD"),
    );

    expect(retryCall).toBeTruthy();
    expect(String(retryCall?.[0])).toContain("claimed_at = NULL");
    expect(String(retryCall?.[0])).toContain("claimed_by = NULL");
    expect(retryCall?.[1]?.[2]).toBe("worker-b");
  });

  it("deletes only old delivered rows during retention cleanup", async () => {
    poolExecute.mockResolvedValueOnce([{ affectedRows: 12 }]);

    await expect(cleanupDeliveredRealtimeOutbox(7, 500)).resolves.toBe(12);

    expect(String(poolExecute.mock.calls[0]?.[0])).toContain("WHERE delivered_at IS NOT NULL");
    expect(String(poolExecute.mock.calls[0]?.[0])).toContain("INTERVAL 7 DAY");
    expect(String(poolExecute.mock.calls[0]?.[0])).toContain("LIMIT 500");
  });
});
