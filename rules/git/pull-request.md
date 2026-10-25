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
| Why | 1–3 paragraphs: the problem, the evidence, why now. Link related issues and PRs |
| Changes | Bullets. Large PRs get bold numbered subheads. Per-file changes go in a `File \| Change \| Behavior change` table |
| Verification | The commands you actually ran, with their results (`check-types 4/4`, `vitest 128 passed`). Under Not verified, list everything you did not verify and what would verify it |
| Out of scope & follow-ups | What this PR deliberately leaves alone, and the follow-up work it implies |
| Notes | Merge or deploy order, risks, where reviewers should look first |

- A warning that must be read before merging gets its own section right after Issue: `## ⚠️ Merge #41 first`.
- A stacked PR says so in a blockquote under Issue: `> Stacked on \`issue/40-…\` (#43). Once #43 merges, the base changes to \`main\`.`
- The body ends with your own content. Leave out `🤖 Generated with …` and any other AI-attribution footer.

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
