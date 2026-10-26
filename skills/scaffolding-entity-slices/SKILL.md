---
name: scaffolding-entity-slices
description: Use when adding a new domain entity or API resource to a frontend that follows the entities-layer rules, or when creating an `entities/{domain}/` slice.
---

# Scaffolding entity slices

The structure and conventions live in the entity rules: `entities.md` loads when you touch `entities/`, `entity-data-access.md` when you touch `infrastructure/`. Read both before step 3. `example-slice.md` in this folder is one complete slice to copy from.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Inputs.** Collect, from the API docs or the user:
   - the domain name (kebab-case) and each endpoint: method, path template, request and response shape (or "none", as for a `204` delete)
   - which response fields are essential (the entity means nothing without them)
   - whether the project uses zod and React Query
   - which other entities this one embeds or points at

   Done when every endpoint has a method, a `{param}` path as the docs write it, and its request and response shape or "none".

2. **HTTP client.** Find the shared client (`shared/libs/http` or the common package) and check it against "HTTP client" in `entity-data-access.md`:
   - `httpClient` built with arthron 2.1 or later, with `apiErrors` first in its plugins
   - `HttpClient`, `unwrap`, `ApiError` and `isApiError` exported

   If one is missing, or arthron is older than 2.1 (1.x option names differ, so the adapter code here does not compile; 2.0 lets some error responses past `apiErrors`), stop and report it; adding it is a separate change, and encoding paths or opening bodies in the adapter is what it replaces. A project on another HTTP client is checked against the guarantees listed in that section instead.

3. **Files**, in this order, so each file's imports already exist when you write it:
   1. `infrastructure/dto/` — `{d}.dto.ts`, then request and response files only if needed
   2. `infrastructure/api/{d}.url.const.ts`
   3. `@x/{consumer}.ts` in each **other** entity this one embeds or reuses (from step 1)
   4. `domain/` — `{d}.entity.ts` with its `{Verb}{D}Payload` types, and any product value objects (`{name}.vo.ts`)
   5. `constants/{d}.const.ts` when the slice has public constants, and `constants/{d}.message.const.ts` (`{D}_MESSAGES`) for the i18n keys the schema and use cases pass as data
   6. `errors/{d}.errors.ts` for the server errors this domain's use cases will translate
   7. `schema/{d}.form.schema.ts` (zod) with its `{D}FormValues` type, and list params in `types/`
   8. `infrastructure/mapper/{d}.mapper.ts`
   9. `infrastructure/api/{d}.adapter.ts`
   10. `constants/{d}.query-key.const.ts` (React Query)
   11. `testkit/{d}.testkit.ts` with `createTest{D}Entity(overrides)`, and `infrastructure/api/{d}.adapter.test.ts` with the shared client on a fake `fetchFn`, checking the URL of each method whose template has a placeholder
   12. `index.ts` — explicit named exports

4. **Instance.** The adapter file creates the instance at module level, in the same file as `create{D}Adapter`: `export const {D}Adapter = create{D}Adapter(httpClient)`. In a monorepo package, export only the create function and its type, and create the instance in the app's entities slice.

5. **Verify.** Run every check the project provides: type check, `biome check` on the files you created, the architecture check, and the tests. Then run the `auditing-entity-slices` checklist on the new slice and on every entity that got a new `@x` file.

   Done when every check the project provides passes, the audit is clean, and your report names each check that could not run and why (no test runner, tests excluded from the type check).

## Common mistakes

| Mistake | Fix |
|---|---|
| DTO type left optional "to be safe" | Type the contract exactly; guard essential fields with `required()` in the mapper |
| Placeholders renamed to camelCase | Keep the docs' names; `{user_id}` becomes `pathParams: { user_id: id }` |
| Snake_case request body built outside the adapter | The adapter takes a domain `{Verb}{D}Payload` and calls `{D}Mapper.to…RequestDto` |
| `export *` in `index.ts` | List each export; it is the only thing keeping DTOs private |
| Another entity's type imported directly | Add the shape to the owner's `@x/{consumer}.ts`, or store the id |
| Dates kept as ISO strings | Convert instants to epoch milliseconds in the mapper |
