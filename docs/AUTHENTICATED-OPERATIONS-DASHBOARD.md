# Authenticated Operations Dashboard

Milestone 29.7.2 removes the dashboard TypeScript-alias dependency.

The server-only operations helper is colocated with the page:

```text
apps/dashboard/app/dashboard/operations/operationsStatus.ts
```

The page imports it with:

```text
./operationsStatus
```

This avoids any dependency on `@/*` path aliases in `tsconfig.json`.

Dashboard page:

```text
apps/dashboard/app/dashboard/operations/page.tsx
```

The bearer token remains server-side only and is never rendered in client code.

The operations UI remains disabled unless:

```text
SPORTSOS_OPERATIONS_DASHBOARD_ENABLED=true
```

and the dashboard server runtime receives the same protected operations token configured for the API.
