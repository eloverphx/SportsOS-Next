import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateExternalRealtimeReadiness,
} from "../../../apps/api/src/services/externalRealtimeReadiness";

describe("Milestone 27.7 external realtime readiness", () => {
  it("derives wss and polling targets",()=> {
    const result =
      evaluateExternalRealtimeReadiness({
        DASHBOARD_ORIGIN:
          "https://sports.example.com",
      });

    expect(result.ready).toBe(true);

    expect(result.websocketUrl).toBe(
      "wss://sports.example.com/socket.io/?EIO=4&transport=websocket",
    );

    expect(result.socketIoPollingUrl).toBe(
      "https://sports.example.com/socket.io/?EIO=4&transport=polling",
    );
  });

  it("rejects HTTP dashboard origin",()=> {
    expect(
      evaluateExternalRealtimeReadiness({
        DASHBOARD_ORIGIN:
          "http://sports.example.com",
      }).ready,
    ).toBe(false);
  });
});
