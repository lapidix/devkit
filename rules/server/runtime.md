---
paths:
  - "**/infrastructure/config/**"
  - "**/main.ts"
  - "**/src/common/**"
---

# Server runtime: configuration and observability

## Environment variables

```ts
// infrastructure/config/env.config.ts
const EnvSchema = z.object({
  DATABASE_URL: z.string().url(),
  DATABASE_POOL_SIZE: z.coerce.number().int().positive().default(10),
  SERVICE_TIME_ZONE: z.string().default('Asia/Seoul'), // day boundaries (rules/database/conventions.md)
  JWT_SECRET: z.string().min(32),
  CORS_ORIGINS: z.string().transform((v) => v.split(',')),
  RESIGNUP_COOLDOWN_DAYS: z.coerce.number().int().default(30),
  PAYMENT_API_KEY: z.string().optional(), // optional integration
});

export const ENV = EnvSchema.parse(process.env);
```

- **Validated at boot.** A wrong or missing required value stops the server when it deploys, not on the first request that needs it.
- **In `process.env` before the app starts.** `ENV` is parsed when its module is imported, which happens before any framework module initializes, so a config module that loads a file later is too late. Deployments inject the values; locally, the scripts load the file before Node starts:
  ```jsonc
  "start": "node --env-file=.env dist/main.js",
  "dev": "dotenv -e .env -- nest start --watch"
  ```
- **Read in one place.** Only `infrastructure/config/env.config.ts` touches `process.env`. Composition roots (`*.module.ts`, `main.ts`) import the validated `ENV`; everything else receives values from them by injection (policies, client options).
- **Use cases never read configuration.** A value a use case needs arrives as a policy port (`rules/server/application.md`), filled by the module.
- **Optional integrations are optional in the schema.** When one is missing, the server still starts and its adapter throws when called, so only that feature fails. Values the server cannot run without (the database, token secrets) stay required.

## Logs

- **Structured JSON**, one object per line, and every line carries the `requestId` from the standard response (`rules/api/contract.md`). One response a user received leads straight to its log lines.
- **One request log line per request**: method, route, status, duration in milliseconds, `requestId`, user id. Never the body.
- **Levels.**

  | Level | For |
  |---|---|
  | `error` | Unexpected errors (500) only |
  | `warn` | Handled but unusual: a retried external call, a fallback taken |
  | `info` | Request lines and meaningful business events |

  A domain error (404, 409 …) is a normal response, not an `error`.
- **No secrets.** Passwords, tokens and personal data never reach a log line.
- **No `console`.** Everything goes through the logger.

## Errors, health and metrics

- **Error tracking** (Sentry or similar) receives unexpected errors (500) only. Sending domain errors buries the real problems.
- **Health.** `/api/health` is `@Public()` and splits liveness (the process answers) from readiness (the database answers).
- **Metrics** are the project's choice. When a project collects them, they include request count, status code and duration, not only the runtime defaults.
