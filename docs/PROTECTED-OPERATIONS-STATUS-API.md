# Protected Operations Status API

Milestone 29.6.3 registers the protected operations route using the actual SportsOS API bootstrap architecture.

API bootstrap:

```text
apps/api/src/app.ts
```

Route module:

```text
apps/api/src/routes/operationsStatus.ts
```

Registration:

```text
await app.register(registerOperationsStatusRoutes);
```

Endpoint:

```text
GET /deployment/operations/status
```

The endpoint remains disabled by default.

To intentionally enable it, configure the API runtime with:

```text
SPORTSOS_OPERATIONS_STATUS_API_ENABLED=true
SPORTSOS_OPERATIONS_STATUS_TOKEN=<random secret at least 32 characters long>
```

Do not commit the token.

The endpoint reads only:

```text
/app/data/operations-status/latest.json
```

Responses use:

```text
Cache-Control: no-store
```

No raw logs, backup archives, webhook URLs, credentials, tokens, or Docker mount metadata are returned.
