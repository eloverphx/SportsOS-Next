# SportsOS Milestone 27 — External HTTPS Production Acceptance

Milestone 27 establishes the production deployment and external HTTPS readiness baseline for SportsOS.

## Accepted capabilities

- external HTTPS readiness evaluation
- trusted reverse-proxy / forwarded-header handling
- production CORS origin cutover support
- formal reverse-proxy route contract
- certificate / TLS validation workflow
- external dashboard / API health verification
- external Socket.IO / WebSocket path verification
- public attack-surface / exposure audit
- full production deployment rehearsal

## Local/tooling acceptance

The deployment tooling is considered locally complete when:

```bash
bash scripts/production-deployment-rehearsal.sh
```

passes all local/runtime/tooling gates.

External checks may remain `BLOCKED` in default rehearsal mode until public DNS, TLS certificates, and reverse-proxy routing are live.

## Full external production acceptance

Full production cutover requires:

```bash
SPORTSOS_REQUIRE_EXTERNAL_LIVE=1 \
  bash scripts/production-deployment-rehearsal.sh
```

to pass without blockers.

This requires valid public HTTPS URLs, certificate chain and hostname validation, external dashboard/API health, working Socket.IO/WebSocket paths, and no unintended public admin/debug surfaces.

## Required public route contract

```text
/              -> dashboard:4000
/api/*         -> api:4001/*
/api/health    -> api:4001/health
/socket.io/*   -> api:4001/socket.io/*
```

The reverse proxy must preserve the host, forward protocol/client metadata, strip the external `/api` prefix before API forwarding, and support WebSocket upgrade.

## Completion rule

Do not tag Milestone 27 as production-complete until strict external-live rehearsal passes.
