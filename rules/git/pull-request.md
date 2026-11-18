# Pull requests

## Issue first

For a title or body draft, use the available issue information and mark a missing issue number as unresolved. Creating an issue and preparing a branch are part of opening a PR, not prerequisites for drafting its text. Editing an existing PR's title or body keeps its issue and branch unless the user requests a change.

Every PR resolves or references a GitHub issue. When the work has no issue yet, create one with `gh issue create` before branching, then branch from the base as:

```
issue/<N>-<kebab-slug>        e.g. issue/42-withdrawal-reason
```

Why: the issue number ties the branch, the PR title and the history together, so any change can be traced back to why it was made.

## Title

```
#<N> <type>: <summary>        e.g. #42 feat: ask for a reason on withdrawal
```

`<N>` is the **issue** number, not the PR number. `<type>` and `<summary>` follow the commit rules (`rules/git/commit.md`): lowercase start, no trailing period.

## Body

Write the body in English. Put identifiers, paths and commands in backticks.

When the repo has its own template (`.github/PULL_REQUEST_TEMPLATE.md`), fill that template exactly as written; some repos check its headers in CI. Otherwise use this one:

```markdown
## Issue
Resolves #N

## Why

## Changes

## Verification
**Verified**
- 
**Not verified**
- 

## Out of scope & follow-ups

## Notes
```

| Section | What goes in it |
|---|---|
| Issue | `Resolves #N` when the PR fully resolves it. `Refs #N — <reason>` when it covers part of the issue |
| Why | 1–3 paragraphs, at most 1,500 characters: the problem, the evidence, why now. Link related issues and PRs |
| Changes | At most 3,000 characters. Bullets. Large PRs get bold numbered subheads. Per-file changes go in a `File \| Change \| Behavior change` table |
| Verification | The commands you actually ran, with their results (`check-types 4/4`, `vitest 128 passed`). Under Not verified, list everything you did not verify and what would verify it |
| Out of scope & follow-ups | At most 1,000 characters. What this PR deliberately leaves alone, and the follow-up work it implies |
| Notes | At most 1,000 characters. Merge or deploy order, risks, where reviewers should look first |

- A section with nothing to say contains `None`. An empty section reads as forgotten.
- A path or a name in backticks exists in the repository, at the PR head or its base: `src/user/withdraw.ts`, `WithdrawUser`. A name that does not exist is a guess, and a reviewer who searches for it loses time. Not checked: commands, globs, placeholders, dotted names such as `os.Getenv`, names with no lowercase letter such as `NODE_ENV`, host-like paths, product names such as `Next.js`, and paths the repository ignores.
- A warning that must be read before merging gets its own section right after Issue: `## ⚠️ Merge #41 first`.
- A stacked PR says so in a blockquote under Issue: `> Stacked on \`issue/40-…\` (#43). Once #43 merges, the base changes to \`main\`.`
- The body ends with your own content. Leave out `🤖 Generated with …` and any other AI-attribution footer.

## Size

A PR changes at most 1,000 lines, counting added and deleted lines and leaving out generated files: lockfiles (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, `go.sum`) and files marked `linguist-generated` in `.gitattributes`. A PR over the limit says in Notes why it could not be split. The check warns on size and does not block the merge.

Why: a reviewer's attention drops as the diff grows, so large changes get skimmed instead of read.

## Plain language

The body is written for the reviewer, who knows the codebase and has not seen this change. ISO 24495-1 (plain language) names four principles; the rules below apply them:

- Relevant: the first paragraph of Why states the problem and its evidence. Nothing unrelated to the change goes in.
- Findable: the template's headers stay, in order. A section with nothing to say contains `None`.
- Understandable: a sentence has at most 25 words, in the active voice, and a paragraph has one topic. Each section stays within its limit above.
- Usable: Verification lists commands that can be run again, with their results, and Notes says where to look first.

ISO 24495-1 sets no numbers. The limits here are devkit's.

## Checks

`scripts/check-pr.sh`, installed by the `setting-up-pr-checks` skill, checks the template headers, the section contents and limits, the backtick references, the size and the comment rules in `rules/go/conventions.md`, `rules/typescript/conventions.md` and `rules/database/conventions.md`. Size and sentence length only warn; every other violation blocks. `.github/pr-checks.env` changes the numbers. Passing the check does not mean the text conforms to ISO 24495: the standard judges whether readers can use the text, which a script cannot measure.

## Creating the PR

Write the body to a file, create the PR from that file, then confirm the body arrived:

```bash
gh pr create --title "#42 feat: …" --body-file /tmp/pr-body.md
gh pr view <n> --json body --jq '.body | length'
```

Why: passing the body through stdin (`--body-file -` with a heredoc) produced empty PR bodies under shell wrappers that drop stdin, such as `rtk`.

## Labels and merging

- Apply labels when the repo has a labeling rule; follow that rule.
- Merge with the method the repo is configured for. When the repo does not specify one, use a merge commit so each commit and its body stay in history. If intermediate commits do not pass checks on their own, ask for a squash merge in Notes.
