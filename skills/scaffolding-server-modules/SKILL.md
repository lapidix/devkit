---
name: scaffolding-server-modules
description: Use when adding a new domain module to a server that follows the server rules, or when creating a `src/modules/{domain}/` folder, its aggregate, use cases and adapters.
---

# Scaffolding server modules

The structure and conventions live in the server rules (`rules/server/*.md`), which load as you touch the matching folders. Read `architecture.md`, `domain.md`, `application.md` and `adapters.md` before step 3, and the database rules (`rules/database/conventions.md`, the engine's file and the ORM's file) before step 3.10. `example-module.md` in this folder is one complete module to copy from.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one, read the copy that ships with this skill, in the `rules/` folder two levels above this skill's folder, and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Inputs.** Collect, from the spec or the user:
   - the module name (kebab-case) and its aggregate root: fields, which are value objects, and the value lists (statuses, reasons)
   - the invariants: what must hold when the aggregate is created and at each state change
   - each operation: whether it writes or reads, its input and its result, and the errors it can raise (with the `kind` of each)
   - what it needs from outside: another module (and which public use case of it), a technical capability, a setting
   - the HTTP routes, if the module is exposed, and who may call each one (public, a role, only the owner)

   Done when every operation has an input, a result (or `void`) and its errors, every outside need names the port it becomes, and every route names who may call it.

2. **Shared pieces.** Check that what the module will import exists: `src/shared/domain/domain.error.ts`, `src/shared/domain/id.ts` when it creates aggregates, `src/shared/types/page.types.ts` and `src/common/http/page.response.dto.ts` when it has list routes, the transaction setup (`ClsModule` with `@nestjs-cls/transactional`) when it writes, the ORM client, and the `@/` alias. If one is missing, stop and report it; adding it is a separate change.

3. **Files**, in this order, so each file's imports already exist when you write it:
   1. `domain/{d}.const.ts`: value lists and their union types
   2. `domain/{d}.errors.ts`: one `DomainError` subclass per error, with `code` and `kind`
   3. `domain/{name}.vo.ts`: each value object, with `create` and `restore`
   4. `domain/{d}.entity.ts`: the aggregate (`fromSnapshot`, `toSnapshot`, state-changing methods taking `now`, and `register` or the domain's creation verb when the module creates it) and its snapshot type
   5. `domain/{d}.repository.ts`: the repository port of the aggregate root
   6. `application/ports/{name}.port.ts`: every other outside need, and `transaction-runner.port.ts` when a use case makes several writes that must succeed together
   7. `application/usecases/{verb}.usecase.ts`: one per operation, with its command or query and its plain result
   8. `testkit/{d}.testkit.ts`: `createTest{D}(overrides)` built through `fromSnapshot`
   9. tests: `domain/{d}.entity.test.ts`, one `{verb}.usecase.test.ts` per use case with fake ports
   10. the table in the project's database schema, as the database rules say (names, types, the index of each list query with its comment), then write its migration file and regenerate the ORM client
   11. `adapters/out/persistence/{d}.mapper.ts` and its test, then `{d}.{orm}.repository.ts`; repository tests only for methods that use database-specific behavior
   12. `adapters/out/{target}/{port}.{target}.adapter.ts`: one per remaining port
   13. `adapters/in/http/dto/{d}.request.dto.ts`, `{d}.response.dto.ts`, then `{d}.controller.ts`
   14. `{d}.module.ts`: bind each port to its adapter, list in `imports` the modules whose use cases its adapters call, and `exports` only the use cases other modules call (leave `exports` out when there are none)
   15. `index.ts`: the module class and its public use cases with their query and result types and the domain errors they throw

   Done when every file in the list exists and the type check passes.

4. **Register.** Add the new module to `app.module.ts`. For each module the new one calls, check that it `exports` the use case the adapter injects; if it does not, adding that export is a change to that module, so say so in your report. Done when the app module imports the new module and every injected use case is exported by its module.

5. **Verify.** Run every check the project provides: the type check, `biome check` on the files you created, `check:arch` (or the dependency-cruiser command it wraps), and the tests. Done when every check passes, and your report names each check that could not run and why.

## Common mistakes

| Mistake | Fix |
|---|---|
| A use case returns the aggregate | Return a plain result built from `toSnapshot()`; controllers and other modules never hold the domain model |
| A use case throws `NotFoundException` | Throw the module's `DomainError`; the exception filter picks the status |
| A use case injects another module's use case | Declare a port in `application/ports` and implement it in `adapters/out` |
| `fromSnapshot` calls `Nickname.create` | Use `restore`; stored values are trusted, or a tightened rule breaks old rows |
| A domain method calls `new Date()` | Take `now: Date`; the use case passes `execute(command, now = new Date())` |
| The controller spreads the request DTO into the command | Pick each field the use case needs |
| Plain CRUD repository methods get tests, or tests assert a mocked ORM's arguments | Test the mapper without a database; integration-test only database-specific behavior |
