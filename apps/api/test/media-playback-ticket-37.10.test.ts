import { describe, expect, it } from "vitest";
import {
  createMediaPlaybackTicket,
  parseCookie,
  verifyMediaPlaybackTicket,
} from "../src/modules/media-playback/ticket.js";

const secret = "m37.10-test-secret";

describe("M37.10 media playback ticket", () => {
  it("round-trips a valid short-lived ticket", () => {
    const now = 1_000_000;
    const value = createMediaPlaybackTicket(
      {
        assetId: 42,
        userId: 7,
        organizationId: 3,
        expiresAt: now + 60_000,
      },
      secret,
    );

    expect(verifyMediaPlaybackTicket(value, secret, now)).toEqual({
      assetId: 42,
      userId: 7,
      organizationId: 3,
      expiresAt: now + 60_000,
    });
  });

  it("rejects tampering, wrong secrets, and expiration", () => {
    const now = 1_000_000;
    const value = createMediaPlaybackTicket(
      {
        assetId: 42,
        userId: 7,
        organizationId: 3,
        expiresAt: now + 60_000,
      },
      secret,
    );

    expect(verifyMediaPlaybackTicket(`${value}x`, secret, now)).toBeNull();
    expect(verifyMediaPlaybackTicket(value, "wrong-secret", now)).toBeNull();
    expect(verifyMediaPlaybackTicket(value, secret, now + 60_001)).toBeNull();
  });

  it("extracts the scoped playback cookie", () => {
    expect(
      parseCookie(
        "other=1; sportsos_media_playback=abc.def; theme=dark",
        "sportsos_media_playback",
      ),
    ).toBe("abc.def");
  });
});
