---
name: writing-pull-requests
description: Use when opening a pull request, or writing or rewriting a PR title or body.
---

# Writing pull requests

The format lives in the git rules (`pull-request.md`, `commit.md`), which load in every session. This skill is the procedure that produces a PR in that format.

The git rules are in the project's `.claude/rules/git/` or in `~/.claude/rules/git/`. When neither has them, read the copy in `rules/git/` two levels above this skill's folder.

## Steps

1. **Issue.** Find the issue this work resolves (`gh issue list --search "<keywords>"`, or ask). If none exists, create one with `gh issue create` and note its number. Done when you hold an issue number `N`.

2. **Branch.** The current branch is `issue/<N>-<kebab-slug>`. If you are on the base branch with no commits yet, create it there. If commits already exist on a differently named branch, ask before renaming it. Done when `git branch --show-current` prints the right name.

3. **Evidence.** Collect what the body will state:
   - `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`
   - every verification command you ran, with its result. Rerun any whose result you are unsure of.
   - what you could not verify, and what would verify it.
   Done when each change in the diff maps to a reason, and each claim in Verification maps to a command you ran.

4. **Body file.** If `.github/PULL_REQUEST_TEMPLATE.md` exists, fill it exactly. Otherwise use the template from `pull-request.md`. Write it to a temporary file. Done when every section is filled or deliberately left empty, and Verification has both Verified and Not verified.

5. **Create.**
   ```bash
   gh pr create --base <base> --title "#<N> <type>: <summary>" --body-file <file>
   gh pr view <number> --json title,body --jq '{title, len: (.body | length)}'
   ```
   Done when the PR exists, `len` is greater than zero, and the title matches `#<N> <type>: <lowercase summary>`.

6. **Labels.** If the repo has a labeling rule, apply it with `gh pr edit <number> --add-label …`.

Report the PR URL.

## Common mistakes

| Mistake | Fix |
|---|---|
| Body passed through stdin or a heredoc | Always `--body-file <path>`; shell wrappers such as `rtk` drop stdin |
| Verification says "tests pass" with no command | Name the command and its numbers |
| Unverified items left out | List them under Not verified; reviewers need to know what was not checked |
| The repo's own template replaced with the default one | The repo template wins; some repos check its headers in CI |
| `#<PR number>` in the title | The title carries the **issue** number |
