import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.5 realtime overlay updates", () => {
  it("uses Socket.IO for realtime updates", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'from "socket.io-client"',
    );
    expect(component).toContain("io(SOCKET_URL");
  });

  it("joins and leaves the selected game room", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'socket?.emit("game:join"',
    );
    expect(component).toContain(
      'socket.emit("game:leave"',
    );
  });

  it("refreshes the authoritative snapshot when realtime game events arrive", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'socket.on("game:updated"',
    );
    expect(component).toContain(
      'socket.on("game:event"',
    );
    expect(component).toContain(
      'socket.on("scoreboard:update"',
    );
  });

  it("keeps a fallback polling path", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain("setInterval");
    expect(component).toContain("5000");
    expect(component).toContain(
      "Fallback polling",
    );
  });

  it("shows realtime connection state", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/broadcast/BroadcastOverlayClient.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      'data-testid="overlay-realtime-state"',
    );
    expect(component).toContain("Realtime");
  });
});
