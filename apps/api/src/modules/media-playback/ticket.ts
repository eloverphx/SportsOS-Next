import { createHmac, timingSafeEqual } from "node:crypto";

export interface MediaPlaybackTicket {
  readonly assetId: number;
  readonly userId: number;
  readonly organizationId: number;
  readonly expiresAt: number;
}

function encodeJson(value: unknown): string {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function signPayload(payload: string, secret: string): string {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}

export function createMediaPlaybackTicket(ticket: MediaPlaybackTicket, secret: string): string {
  const payload = encodeJson(ticket);
  return `${payload}.${signPayload(payload, secret)}`;
}

export function verifyMediaPlaybackTicket(
  value: string,
  secret: string,
  nowMs = Date.now(),
): MediaPlaybackTicket | null {
  const separator = value.lastIndexOf(".");

  if (separator <= 0 || separator === value.length - 1) {
    return null;
  }

  const payload = value.slice(0, separator);
  const providedSignature = value.slice(separator + 1);
  const expectedSignature = signPayload(payload, secret);

  const provided = Buffer.from(providedSignature);
  const expected = Buffer.from(expectedSignature);

  if (provided.length !== expected.length || !timingSafeEqual(provided, expected)) {
    return null;
  }

  let decoded: unknown;

  try {
    decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    return null;
  }

  if (
    typeof decoded !== "object" ||
    decoded === null ||
    !("assetId" in decoded) ||
    !("userId" in decoded) ||
    !("organizationId" in decoded) ||
    !("expiresAt" in decoded)
  ) {
    return null;
  }

  const ticket = decoded as Record<string, unknown>;

  if (
    !Number.isSafeInteger(ticket.assetId) ||
    Number(ticket.assetId) <= 0 ||
    !Number.isSafeInteger(ticket.userId) ||
    Number(ticket.userId) <= 0 ||
    !Number.isSafeInteger(ticket.organizationId) ||
    Number(ticket.organizationId) <= 0 ||
    !Number.isSafeInteger(ticket.expiresAt) ||
    Number(ticket.expiresAt) <= nowMs
  ) {
    return null;
  }

  return {
    assetId: Number(ticket.assetId),
    userId: Number(ticket.userId),
    organizationId: Number(ticket.organizationId),
    expiresAt: Number(ticket.expiresAt),
  };
}

export function parseCookie(cookieHeader: string | undefined, name: string): string | null {
  if (!cookieHeader) return null;

  for (const part of cookieHeader.split(";")) {
    const [rawName, ...rest] = part.trim().split("=");

    if (rawName === name) {
      return decodeURIComponent(rest.join("="));
    }
  }

  return null;
}
