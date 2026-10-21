---
paths:
  - "**/adapters/in/**"
  - "**/src/common/**"
  - "**/internal/common/**"
---

# HTTP API contract

What every server's HTTP API looks like, whatever its language. A frontend reads a NestJS server and a Go server the same way. The NestJS implementation is in `rules/server/http-api.md`, the Go one in `rules/go-server/http.md`.

## Standard response

Every response, success or failure, has the same five keys:

```jsonc
// one resource
{ "result": { "id": "user-1", "nickname": "kim" }, "message": null,
  "timestamp": "2026-10-19T07:00:00Z", "requestId": "…", "errorCode": null }

// a list
{ "result": { "items": [ … ], "total": 135, "page": 1, "pageSize": 20 },
  "message": null, "timestamp": "…", "requestId": "…", "errorCode": null }

// a failure
{ "result": null, "message": "user not found", "timestamp": "…", "requestId": "…", "errorCode": "USER_NOT_FOUND" }

// a validation failure: field details go in result, the keys stay the same
{ "result": { "fields": [{ "path": "reason", "message": "expected value to be one of \"moved, not_useful, other\"" }] },
  "message": "…", "timestamp": "…", "requestId": "…", "errorCode": "VALIDATION_FAILED" }
```

- Fields are camelCase.
- One place wraps every success and one place turns every error into this shape. Handlers and controllers never build it.
- `requestId` is created per request, or taken from an incoming `X-Request-Id` header. Every log line carries it.
- `timestamp` is UTC ISO 8601.
- A use case with no result still answers with all five keys and `result: null`.
- Creating a resource answers 201 with `result: { "id": "…" }`, so the client can fetch or link it. Other `POST` actions (withdraw, publish) answer 200.
- `message` is for developers and logs. Clients choose the text users see from `errorCode`.

## Lists

- A list's `result` is the use case's page as it is: `{ items, total, page, pageSize }`. Clients derive the page count from `total` and `pageSize`.
- `pageSize` defaults to 20 and is capped at 100 by the request schema; without a cap, one request can read the whole table.
- A cursor-based list answers `result: { items, nextCursor }`. `nextCursor` is the last row's sort values (`created_at`, `id`) encoded as base64url; clients send it back unchanged and never parse it, so the server can change its sort without breaking them. The sort itself always ends with the id (`rules/database/conventions.md`).
- An empty list is `[]`, never `null`.

## Errors

| Error | Status | `errorCode` |
|---|---|---|
| Domain error with kind `invalid` | 400 | its code |
| kind `unauthorized` | 401 | its code |
| kind `forbidden` | 403 | its code |
| kind `not_found` | 404 | its code |
| kind `conflict` | 409 | its code |
| Request validation failed | 400 | `VALIDATION_FAILED`, with `result.fields` |
| A framework error: an unknown route, a method the route does not take, a body over the limit, the rate limiter, a failed authentication | that status | the status name: `NOT_FOUND`, `METHOD_NOT_ALLOWED`, `PAYLOAD_TOO_LARGE`, `TOO_MANY_REQUESTS`, `UNAUTHORIZED` |
| Anything else | 500 | `INTERNAL_ERROR`; the details go to the log only |

- A domain error's status comes from its kind here and nowhere else, so the domain never knows HTTP and use cases never produce HTTP errors.
- `result.fields` lists each invalid field as `{ path, message }`. `path` is the field inside the body or the query (`reason`, `pageSize`); `message` is the validator's, for developers. Clients map the fields users see from domain error codes, not from these messages.

## Requests

- Fields the request body does not define are ignored, never rejected. The handler picks the fields the use case needs, so an unknown field never reaches it.

## Paths

All routes sit under `/api`. There is no version segment; when a breaking change actually happens, the new routes take `/api/v2`.

## Authentication and defenses

- **Deny by default.** Every route requires authentication unless it is marked public where it is registered. A forgotten mark then blocks a route instead of silently opening it.
- **Roles** are checked by the same mechanism, from the roles each route declares. Which roles exist is the project's decision.
- **CORS** allows only the origins listed in the environment; never `*`.
- **Body size** has an explicit limit; a file upload route sets its own.
- **Rate limits** apply to routes that can be abused, such as sign-in and verification codes.
- **Security headers** are set on every response.
- **Secrets** (passwords, tokens, personal data) never appear in logs or error responses.

## API documentation

- The OpenAPI document is generated from the same schemas that validate requests, so validation, types and documentation have one source.
- It is served at `/api/docs` in development and staging, never in production.
- No separate request collection (Bruno, Postman): it goes stale. Try requests from the documentation page.
