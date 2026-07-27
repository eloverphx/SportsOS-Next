# SportsOS Next

SportsOS Next is a modular platform for sports administration, live scoring,
broadcast overlays, streaming workflows, and connected scoreboard hardware.

## Repository structure

````text
apps/
  api/         Fastify API and realtime services
  dashboard/   Next.js administration dashboard

packages/
  config/      Validated, typed runtime configuration
  core/        Shared contracts, errors, logging interfaces, and utilities

scripts/       Repository maintenance scripts

## Requirements

- Node.js 22
- npm 10 or newer
- Docker and Docker Compose for the full local stack

## Install

Install all workspace dependencies from the repository root:

```bash
npm install
````

## Development

Start the API:

```bash
npm run dev:api
```

Start the dashboard in another terminal:

```bash
npm run dev:dashboard
```

The dashboard uses port `4000`. The API uses port `4001` unless overridden by environment configuration.

## Repository commands

```bash
npm run build
npm run typecheck
npm run lint
npm run test
npm run clean
```

`npm run build` builds the shared core package first, followed by the API and dashboard.

## Architecture principles

- Shared contracts belong in `@sportsos/core`.
- Sports-domain logic remains inside its feature module.
- Applications depend on packages; packages must not depend on applications.
- Configuration is validated at application startup.
- API routes remain thin and delegate behavior to services.
- Changes to calculation or scoring behavior require matching automated tests.

## Current applications

### API

Fastify service providing HTTP endpoints, realtime communication, persistence integrations, and future domain modules.

### Dashboard

Next.js interface for administration, team management, scoring operations, and platform status.

## Roadmap

The next API-foundation milestones add shared configuration, a testable Fastify application factory, production middleware, platform health endpoints, OpenAPI documentation, and integration tests.
