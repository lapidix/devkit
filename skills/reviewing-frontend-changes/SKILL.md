---
name: reviewing-frontend-changes
description: Use when reviewing frontend changes against the frontend rules, before opening a PR that touches frontend code, or when asked whether code follows the conventions.
---

# Reviewing frontend changes

A convention review: does the changed code follow `rules/frontend/*.md` and `rules/typescript/conventions.md`? Bugs are another review's job. Mechanical checks run first; the judgment checks in `checklist.md` need you to read the code.

The rule files named here are in the project's `.claude/rules/{area}/` (`rules/frontend/testing.md` is `.claude/rules/frontend/testing.md`). When the project lacks one and this skill came from the lapidix-skills plugin, read it from `${CLAUDE_PLUGIN_ROOT}/rules/` instead and say in your report that the project does not have it; the `installing-rules` skill copies it in.

## Steps

1. **Scope.** List the changed frontend files and, for each, the rule files that cover it (each rule's `paths:`). From `package.json`, note the framework (Next.js when `next` is a dependency, otherwise a React SPA) and the styling tool (Tailwind or not); several checks depend on them, and the report states them.
   ```bash
   BASE=origin/main   # the PR's base; with no remote, the local base branch (main)
   FILES=$(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD -- '*.ts' '*.tsx' '*.css' | grep -E '(^|/)(src|app)/')
   ```
   When the user names files or a folder instead, use those. Done when every file in `FILES` has its rule files listed.

2. **Tools.** Run each check the project's `package.json` scripts provide: `check:arch`, `check-types`, `biome check` on `FILES`, and the tests. Record each command and its result. A check that cannot run goes in the report with the reason.

3. **Grep checks.** Run every command below. Read each hit: comments, strings and legitimate exceptions can match.

   ```bash
   # g PATTERN [PATH_REGEX]: grep FILES, optionally only paths matching PATH_REGEX
   g() { printf '%s\n' "$FILES" | grep -E "${2:-.}" | xargs grep -nE "$1" /dev/null; }

   g '\b(useMemo|useCallback)\(|\bmemo\(' '\.tsx?$'                      # manual memoization; React Compiler is on (react.md)
   g 'React\.FC|defaultProps|forwardRef\(' '\.tsx$'                       # component declaration (react.md)
   g 'window\.(alert|confirm)\(|Alert\.alert\(' '\.tsx?$'                 # native dialogs (react.md)
   g "^['\"]use client['\"]" '/pages/|/layouts/|(^|/)app/.*(page|layout)\.tsx?$'   # pages, layouts, routes stay server components (react.md)
   g 'export \*' '/index\.tsx?$'                                          # public API is an explicit list (entities.md, features.md index.ts)
   g 'use(Suspense)?Query\(\{|useMutation\(\{|queryKey: \[' '\.tsx?$'     # inline React Query options or keys (react-query.md)
   g '\.reset\(' 'use[A-Z][A-Za-z]*Form\.ts$'                             # reset in a form hook; check it is not in an effect (forms-rhf-zod.md)
   g 'disabled=\{[^}]*(isValid|isDirty)' '\.tsx$'                         # submit disabled on validity (forms-rhf-zod.md)
   g "\.(min|max|length|regex|email|url)\([^)]*, *['\"]" '\.form\.schema\.ts$'   # literal message instead of {D}_MESSAGES (i18n.md)
   g "(message|successMessage): *['\"]" '\.mutations\.ts$|use[A-Z][A-Za-z]*\.ts$' # literal key passed as data (i18n.md)
   g "\bt\( *['\"][^'\"]+['\"] *, *['\"]" '\.tsx?$'                        # inline fallback text (i18n.md)
   g '\b(text|bg|border|ring|fill|stroke)-(slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-[0-9]{2,3}\b' '\.tsx$'   # raw palette (styling.md)
   g '#[0-9a-fA-F]{3,8}\b|style=\{\{' '\.tsx$'                            # hex values, inline style (styling.md)
   g 'className=\{ *`' '\.tsx$'                                           # template-string class names (styling.md)
   g 'toLocale(Date|Time)?String\(|dayjs\([^)]*\)\.format\(' '\.tsx$'     # formatting outside shared formatters (styling.md)
   g 'as unknown as' '\.test\.tsx?$'                                      # cast instead of satisfies (testing.md)
   g "vi\.mock\( *['\"](@/|\.\.?/)" '\.test\.tsx?$'                        # mocking our own module; add the app's alias (@web/) (testing.md)
   g "globalThis\.fetch *=|stubGlobal\( *['\"]fetch|spyOn\(globalThis, *['\"]fetch" '\.test\.tsx?$'   # a stubbed global fetch; give the shared client a fake fetch (testing.md)
   printf '%s\n' "$FILES" | grep -v 'env\.config\.ts$' | xargs grep -nE 'process\.env|import\.meta\.env' /dev/null   # env outside env.config.ts (shared.md)

   # slices in scope without an index.ts (entities.md, features.md, widgets.md, pages.md index.ts)
   printf '%s\n' "$FILES" | sed -nE 's#^((.*/)?src/(entities|features|pages)/[^/]+)/.*#\1#p; s#^((.*/)?src/widgets/[^/]+/[^/]+)/.*#\1#p' | sort -u |
     while read -r d; do [ -f "$d/index.ts" ] || echo "$d: no index.ts"; done
   ```

   Done when every command has run and every hit is classified as a violation or a false positive.

4. **Judgment checks.** For each changed file, go through the sections of `checklist.md` for the rule files it is covered by. Done when every applicable item has been checked for every file.

5. **Entities.** For each changed `entities/*/` slice, run the `auditing-entity-slices` skill. Merge its findings into the per-file rows and drop the ones already listed; its app-wide greps can repeat hits from step 3.

6. **Report.** Write it in the user's language:
   - the framework and styling tool from step 1
   - findings grouped by file, one row each: `file:line | rule (file and section) | fix`. A finding about a whole slice (a missing `index.ts`) uses the slice folder as its location; one that spans files lists each `file:line`. A file with no findings is listed as clean
   - the tool results from step 2, each with its command
   - what was not checked, and why

   Done when every file in scope appears in the report and every finding names the rule it breaks.
