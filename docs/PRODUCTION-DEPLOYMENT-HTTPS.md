# SportsOS Production Deployment / External HTTPS

## Milestone 27.1 — External HTTPS preflight

SportsOS now exposes an external HTTPS readiness endpoint:

```text
GET /broadcast-coordinator/external-https-readiness
```

Production expectations:

```text
TLS termination: external reverse proxy
Direct container TLS: not required
X-Forwarded-Proto: required
X-Forwarded-Host: recommended
```

Required readiness checks:

- `NODE_ENV=production`
- `PUBLIC_API_URL` uses `https://`
- `DASHBOARD_ORIGIN` uses `https://`
- API binds to `0.0.0.0`
- production HSTS policy is enabled

Milestone 27.1 is read-only. It does not change DNS, certificates, firewall rules, reverse-proxy routes, or container ports.

## Planned Milestone 27 sequence

27.1 External HTTPS preflight  
27.2 Trusted proxy / forwarded-header handling  
27.3 Public origin / CORS production cutover  
27.4 Reverse proxy route contract  
27.5 Certificate / TLS validation workflow  
27.6 External API/dashboard health verification  
27.7 WebSocket / realtime external-path validation  
27.8 Public attack-surface / exposure audit  
27.9 Production deployment rehearsal  
27.10 External HTTPS production acceptance / closeout

## Milestone 27.2 — Trusted proxy / forwarded-header handling

SportsOS now configures Fastify `trustProxy` explicitly.

Default trusted proxy ranges:

```text
loopback
linklocal
uniquelocal
```

This allows trusted local/reverse-proxy hops to supply:

```text
X-Forwarded-Proto
X-Forwarded-Host
X-Forwarded-For
```

without globally trusting forwarded headers from arbitrary public clients.

Optional override:

```text
SPORTSOS_TRUST_PROXY
```

Example:

```text
SPORTSOS_TRUST_PROXY=loopback,linklocal,uniquelocal
```

or explicit proxy CIDRs/addresses supported by Fastify/proxy-addr.

Readiness endpoint:

```text
GET /broadcast-coordinator/trusted-proxy-readiness
```

The endpoint is read-only.

## Milestone 27.5 — Certificate / TLS validation workflow

SportsOS now exposes TLS certificate readiness:

```text
GET /deployment/tls-certificate-readiness
```

Host validation:

```bash
bash scripts/tls-certificate-check.sh
```

The validation workflow checks:

- public API URL uses HTTPS
- dashboard origin uses HTTPS
- certificate chain validates
- certificate hostname matches the target host
- certificate remains valid for a configurable minimum window

Configuration:

```text
SPORTSOS_TLS_MIN_DAYS=14
```

The host checker uses SNI and does not modify certificates, DNS, or reverse-proxy configuration.

## Milestone 27.6 — External API / dashboard health verification

SportsOS now exposes external-health readiness:

```text
GET /deployment/external-health-readiness
```

Host verification:

```bash
bash scripts/external-health-check.sh
```

The workflow derives and validates:

```text
DASHBOARD_ORIGIN
PUBLIC_API_URL
external /api/health route
```

It verifies:

- both external targets use HTTPS
- dashboard is reachable
- external API health route is reachable
- HTTP status is successful or redirect-successful

This is a non-destructive external reachability test. It does not change DNS, certificates, proxy routes, or firewall configuration.

## Milestone 27.6 — External API / dashboard health verification

SportsOS now exposes external-health readiness:

```text
GET /deployment/external-health-readiness
```

Host verification:

```bash
bash scripts/external-health-check.sh
```

The workflow derives and validates:

```text
DASHBOARD_ORIGIN
PUBLIC_API_URL
external /api/health route
```

It verifies:

- both external targets use HTTPS
- dashboard is reachable
- external API health route is reachable
- HTTP status is successful or redirect-successful

This is a non-destructive external reachability test. It does not change DNS, certificates, proxy routes, or firewall configuration.

## Milestone 27.7 — WebSocket / realtime external-path validation

SportsOS now exposes external realtime readiness:

```text
GET /deployment/external-realtime-readiness
```

Expected public realtime paths:

```text
https://<dashboard-host>/socket.io/?EIO=4&transport=polling
wss://<dashboard-host>/socket.io/?EIO=4&transport=websocket
```

Host validation:

```bash
bash scripts/external-realtime-check.sh
```

The host checker validates the Socket.IO polling handshake and requires a returned session id. The reverse proxy must preserve `/socket.io/` and support WebSocket connection upgrade.

## Milestone 27.9 — Production deployment rehearsal

SportsOS now includes a single orchestration command:

```bash
bash scripts/production-deployment-rehearsal.sh
```

The default rehearsal requires all local/tooling gates to pass and treats external HTTPS checks as expected blockers until the public edge is live.

Default mode:

```text
SPORTSOS_REQUIRE_EXTERNAL_LIVE=0
```

Strict production-cutover mode:

```bash
SPORTSOS_REQUIRE_EXTERNAL_LIVE=1 \
  bash scripts/production-deployment-rehearsal.sh
```

Strict mode requires TLS validation, external dashboard/API health, external realtime validation, and public exposure audit to all pass.

The rehearsal includes:

- typecheck + unit tests
- API/dashboard build and recreation
- container/API health
- secret-source audit
- security regression
- release smoke test
- reverse-proxy route contract
- Docker E2E suite
- TLS certificate validation
- external health verification
- external realtime verification
- public exposure audit
- deployment readiness endpoints

## Milestone 27.10 — External HTTPS production acceptance / closeout

Milestone 27 acceptance is documented in:

```text
docs/MILESTONE-27-EXTERNAL-HTTPS-PRODUCTION-ACCEPTANCE.md
```

Local/tooling acceptance:

```bash
bash scripts/production-deployment-rehearsal.sh
```

Full external production acceptance:

```bash
SPORTSOS_REQUIRE_EXTERNAL_LIVE=1 \
  bash scripts/production-deployment-rehearsal.sh
```

Only strict mode is sufficient to declare the external HTTPS deployment fully production-ready.
