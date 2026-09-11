# Milestone 38 — Client Session Hardening

Milestone 38 builds on the durable account/session backend completed in M37 and makes dashboard session behavior match that backend.

## M38.1 — Dashboard refresh-session lifecycle

M37.2 introduced durable refresh sessions with rotation, but the dashboard still behaved like the older access-token-only client. M38.1 closes that mismatch.

- Login now persists the backend-issued refresh token alongside the access token and current user.
- The dashboard understands the durable login/refresh response shape, including session identity and expiry metadata.
- Both existing authenticated request helpers retry a request once after a `401`.
- A retry first rotates the durable refresh session through `POST /auth/refresh`, stores the newly rotated access and refresh tokens, then repeats the original request with the new bearer token.
- Refresh is single-flight within the browser runtime, preventing concurrent `401` responses from racing to rotate the same one-time refresh token.
- Failed or expired refresh sessions clear local authentication and require a fresh sign-in.
- Ordinary non-authentication API failures are not retried through refresh.
- The backend remains authoritative for account status and session validity; the browser does not extend or fabricate session expiry.
