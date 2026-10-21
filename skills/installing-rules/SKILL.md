---
name: installing-rules
description: Use when adding the lapidix/skills rules to a project or updating them, or when another skill reports that the project lacks a rule.
---

# Installing rules

Rules are copied into the project's `.claude/rules/`, not linked: Claude Code loads a rule with `paths:` only from a real file inside the project. `copy-rules.sh` does the copying. It is at `${CLAUDE_PLUGIN_ROOT}/scripts/copy-rules.sh` when this skill came from the lapidix-skills plugin, and at `scripts/copy-rules.sh` in a clone of lapidix/skills.

## Steps

1. **Stack.** Read the project's manifests and list each app with its folder and stack:

   | Found | Stack |
   |---|---|
   | `next` or `react` in an app's `package.json` | React or Next.js frontend |
   | `@nestjs/core` in an app's `package.json` | NestJS server |
   | `go.mod` | Go server |
   | `pnpm-workspace.yaml` | pnpm monorepo |
   | `schema.prisma` (its `provider` names the engine), `sqlc.yaml` (its `engine`), `mongoose` or `go.mongodb.org/mongo-driver` in the dependencies | the database tool and engine: Prisma, sqlc, Mongoose or the MongoDB driver |

   Done when every app has a folder and a stack, and every server a database engine and tool (or "none").

2. **Areas.** Map each app's stack to what it needs:

   | Stack | Areas |
   |---|---|
   | React or Next.js frontend | `typescript` `frontend` |
   | NestJS server | `typescript` `server` `api` `database/conventions`, an engine and a tool |
   | Go server | `go` `go-server` `api` `database/conventions`, an engine and a tool |
   | PostgreSQL | `database/postgres`, with `database/prisma` (NestJS) or `database/sqlc` (Go) |
   | MongoDB | `database/mongodb`, with `database/mongoose` (NestJS) or `database/mongo-go-driver` (Go) |
   | pnpm monorepo (the repo root) | `monorepo` |

   A frontend reads `api/contract.md` when it calls one of these servers, but its globs match server code, so `api` goes to server apps only; in a frontend-only project, copy it without a prefix. `git` holds one person's commit and PR format; add it only when the user asks. Done when the user has confirmed which areas go to which apps.

3. **Copy.** From the project root, run `copy-rules.sh` once per group of areas that go to the same apps. In a monorepo, pass `--prefix <app folder>` for each of those apps: the script puts every `**/` glob under the app's folder, so one app's rules do not load while you work on another. Root areas (`monorepo`, `git`) take no prefix. For a Next.js app in `apps/web` and a NestJS app in `apps/api`:

   ```bash
   bash <copy-rules.sh> --prefix apps/web . frontend
   bash <copy-rules.sh> --prefix apps/api . server api database/conventions database/postgres database/prisma
   bash <copy-rules.sh> --prefix apps/web --prefix apps/api . typescript
   bash <copy-rules.sh> . monorepo
   ```

   In a single-app project, one command without `--prefix` copies everything. Exit 1 is a typo in an area or the folder; the message lists the areas. Each run ends by listing areas the copied rules cite that the project lacks, each with the files that cite it. Read the list after the last command, and add an area only when it applies to an app's stack: `go-server (cited by api/contract.md)` in a NestJS project is a mention for comparison, not a need. Done when every confirmed area is in `.claude/rules/` and the commands are written down for the report.

4. **Updating.** Rerun the same commands; the prefixes show in the copied rules' globs if the earlier report is gone. `same` needs nothing. A `differs` file has changed in lapidix/skills or been edited in the project (exit code 2): show the user its diff, then take the change with `--update` on that command, or keep the project's edit. A cited area left out at install stays out unless the stack has changed. Done when every differing file is updated or kept by the user's choice.

5. **Report.** The commands you ran, what was added, updated or kept, and the cited areas left out with the reason.
