---
paths:
  - "**/adapters/in/http/**"
  - "**/src/common/**"
---

# HTTP API in NestJS

The contract — standard response, lists, the error table, paths, defenses — is `rules/api/contract.md`. This file is how a NestJS server implements it.

## Standard response

- The zod schema and type of the standard response, `ApiResponse<T>`, live in `src/common/http/api-response.dto.ts`.
- A global interceptor wraps every success and turns an `undefined` result into `result: null`.
- A global exception filter turns every error into the standard response, choosing the status from the contract's table.
- A validation failure from the zod pipe becomes `result.fields`: each issue's `path` joined with `.`, and its `message`.
- A list's `result` is the use case's `PageResult`; `PageResponseDto.from(page, toItem)` in `src/common/http/page.response.dto.ts` maps only the items.
- A create returns `{ id }`, which NestJS answers with 201, its default for `POST`; other `POST` actions set `@HttpCode(200)`.
- HTTP exceptions belong to the framework pieces at the edge (guards, the rate limiter); use cases never throw them (`rules/server/application.md`).

## Authentication and defenses

- **Deny by default.** The auth guard is registered as `APP_GUARD`; a route opts out with `@Public()`.
- **Roles.** `@Roles(...)` with a roles guard.
- **Security headers** come from `helmet`; the body parser has an explicit limit; rate limits use `@nestjs/throttler` on the routes that need it.

## API documentation

- `nestjs-zod` generates the OpenAPI document from the zod DTOs that validate requests. Response DTOs are zod schemas too, and `ApiResponse<T>` is defined once.
- Controllers carry only the decorators the document needs: tag, summary, response statuses.
