---
name: installing-rules
description: Use when adding the lapidix devkit rules to a project or updating them, or when another skill reports that the project lacks a rule.
---

# Installing rules

Rules are copied into the project's `.claude/rules/`, not linked: Claude Code loads a rule with `paths:` only from a real file inside the project. `copy-rules.sh` does the copying. It is in the `scripts/` folder two levels above this skill's folder, in the plugin and in a clone of lapidix/devkit alike; a skill copied into a project has no `scripts/` there, so use a clone. Codex does not read `.claude/rules/`, so for a project worked on with Codex the script also keeps an index of the copied rules in the project's `AGENTS.md`.

## Steps

1. **Stack.** Read the project's manifests and list each app with its folder and stack:

   | Found | Stack |
   |---|---|
   | `next` or `react` in an app's `package.json` | React or Next.js frontend |
   | `expo` or `react-native` in an app's `package.json` (this wins over `react`) | React Native or Expo app |
   | `react` or `react-native` in a monorepo package's `package.json`, with components | the platform the package renders for |
   | `@nestjs/core` in an app's `package.json` | NestJS server |
   | `go.mod` with an HTTP server (huma, `net/http` listening) | Go server |
   | `go.mod` with no inbound port: a `main` that runs jobs and dials out (gRPC clients, `os/exec`, tickers) | Go daemon |
   | `pnpm-workspace.yaml` | pnpm monorepo |
   | `schema.prisma` (its `provider` names the engine), `sqlc.yaml` (its `engine`), `mongoose` or `go.mongodb.org/mongo-driver` in the dependencies | the database tool and engine: Prisma, sqlc, Mongoose or the MongoDB driver |

   Done when every app has a folder and a stack, and every server a database engine and tool (or "none").

2. **Areas.** Map each app's stack to what it needs:

   | Stack | Areas |
   |---|---|
   | React or Next.js frontend | `typescript` `frontend` `frontend-web`; a SPA copies the `frontend-web` files one by one and leaves out `frontend-web/nextjs` |
   | React Native or Expo app | `typescript` `frontend` `frontend-native` |
   | Monorepo package with components | `typescript` `frontend` and the area of the platform it renders for; a package with no components gets `typescript` only |
   | NestJS server | `typescript` `server` `api` `database/conventions`, an engine and a tool |
   | Go server | `go` `go-server` `api` `database/conventions`, an engine and a tool |
   | Go daemon | `go` `go-daemon` |
   | PostgreSQL | `database/postgres`, with `database/prisma` (NestJS) or `database/sqlc` (Go) |
   | MongoDB | `database/mongodb`, with `database/mongoose` (NestJS) or `database/mongo-go-driver` (Go) |
   | pnpm monorepo (the repo root) | `monorepo` |

   A frontend reads `api/contract.md` when it calls one of these servers, but its globs match server code, so `api` goes to server apps only; in a frontend-only project, copy it without a prefix. `git` holds one person's commit and PR format; add it only when the user asks. Done when the user has confirmed which areas go to which apps.

3. **Copy.** From the project root, run `copy-rules.sh` once per group of areas that go to the same apps. In a monorepo, pass `--prefix <app folder>` for each of those apps: the script puts every `**/` glob under the app's folder, so one app's rules do not load while you work on another. Root areas (`monorepo`, `git`) take no prefix. For a Next.js app in `apps/web` and a NestJS app in `apps/api`:

   ```bash
   bash <copy-rules.sh> --prefix apps/web . frontend frontend-web
   bash <copy-rules.sh> --prefix apps/api . server api database/conventions database/postgres database/prisma
   bash <copy-rules.sh> --prefix apps/web --prefix apps/api . typescript
   bash <copy-rules.sh> . monorepo
   ```

   In a single-app project, one command without `--prefix` copies everything.

   When running in Codex, always add `--agents-md` to the first command, even if the project has no `AGENTS.md` and the user has not mentioned Codex. Also add it when the project has an `AGENTS.md` or the user says the project is worked on with Codex. For the first command in the example above, use `bash <copy-rules.sh> --agents-md --prefix apps/web . frontend frontend-web`. The script writes a marked index of the copied rules and their paths into `AGENTS.md` and refreshes it on every later run, leaving the rest of the file alone.

   Exit 1 is a typo in an area or the folder; the message lists the areas. Each run ends by listing areas the copied rules cite that the project lacks, each with the files that cite it. Read the list after the last command, and add an area only when it applies to an app's stack: `go-server (cited by api/contract.md)` in a NestJS project is a mention for comparison, not a need, and so is `go-server` in a Go daemon, except `go-server/domain.md` and `go-server/application.md` when one of its jobs has invariants of its own (`rules/go-daemon/architecture.md`). The `frontend` rules cite both `frontend-web` and `frontend-native`; an app needs only its own platform's. Done when every confirmed area is in `.claude/rules/`, Codex projects have a current `AGENTS.md` index, and the commands are written down for the report.

4. **Updating.** Rerun the same commands; the prefixes show in the copied rules' globs if the earlier report is gone. `same` needs nothing. A `differs` file has changed in lapidix devkit or been edited in the project (exit code 2): show the user its diff, then take the change with `--update` on that command, or keep the project's edit. A cited area left out at install stays out unless the stack has changed. A frontend copied before `frontend-web` existed (2026-10-28) gets it now: the SPA and Next.js layouts, URL state, Next.js, Tailwind, web accessibility and jsdom rules moved there, and updating `frontend` alone drops them. Done when every differing file is updated or kept by the user's choice.

5. **Report.** The commands you ran, what was added, updated or kept, and the cited areas left out with the reason.
