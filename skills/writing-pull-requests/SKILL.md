---
name: writing-pull-requests
description: Use when opening a pull request, or writing or rewriting a PR title or body.
---

# Writing pull requests

The format lives in the git rules (`pull-request.md`, `commit.md`). This skill produces a draft or a published PR in that format, according to the user's request.

The git rules are in the project's `.claude/rules/git/` or in `~/.claude/rules/git/`. When neither has them, read the copy in `rules/git/` two levels above this skill's folder.

## Choose the requested output

- **Title or body only:** Read the diff and available verification results, follow the repository's template and the git rules, and return the requested text. Use an existing issue number when known; otherwise mark it as missing rather than inventing one. Stop after the draft: do not create an issue, change branches, push commits, or create or edit a PR. The check in step 5 runs here too; it fetches the base and changes nothing else.
- **Edit an existing PR:** Update only the requested title or body of that PR, then verify the saved text. Keep its issue and branch unless the user asks to change them.
- **Open a PR:** Follow the publishing steps below. A request to open a PR authorizes publishing; do not ask for the same permission again.

## Publishing steps

1. **Issue.** Find the issue this work resolves (`gh issue list --search "<keywords>"`, or ask). If none exists, create one with `gh issue create` and note its number. Done when you hold an issue number `N`.

2. **Branch.** The current branch is `issue/<N>-<kebab-slug>`. If you are on the base branch with no commits yet, create it there. If commits already exist on a differently named branch, ask before renaming it. Done when `git branch --show-current` prints the right name.

3. **Evidence.** Collect what the body will state:
   - `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`
   - every verification command you ran, with its result. Rerun any whose result you are unsure of.
   - what you could not verify, and what would verify it.
   Done when each change in the diff maps to a reason, and each claim in Verification maps to a command you ran.

4. **Body file.** If `.github/PULL_REQUEST_TEMPLATE.md` exists, fill it exactly. Otherwise use the template from `pull-request.md`. Write it to a temporary file. Check it against the four principles before moving on: relevant (the first Why paragraph states the problem and its evidence) and usable (the command to rerun is in Verification, and Notes says where to look first). Done when every section is filled, with `None` where there is nothing to say, and Verification has both Verified and Not verified.

5. **Check.** Run the PR check on the body file, from the project root. First run `git fetch origin <base>`, so a stale local base does not count other people's commits.
   - When the project has `scripts/check-pr.sh`: `bash scripts/check-pr.sh --base origin/<base> --body <file>`.
   - When it does not: `bash <this skill's folder>/../setting-up-pr-checks/check-pr.sh --base origin/<base> --body <file> --no-diff`. It checks the body only, because a project without the script never adopted the comment rules; say so in the report.

   Exit 0 means clean or warnings only, 1 means blocking violations, and 2 means a usage, config or history error: fix the arguments, or fetch more history, and run it again. Warning lines start with `warning: `. Fix each body violation in the file and run it again; fix or explain each warning. A diff violation needs a code change, which this skill does not make: when opening a PR, show the list before creating it and ask whether to fix them first; for a title or body only, list them in the report. Done when the body has no blocking violations, each warning is fixed or explained, and each diff violation is fixed, accepted by the user, or (for a title or body only) listed in the report.

6. **Create.**
   ```bash
   gh pr create --base <base> --title "#<N> <type>: <summary>" --body-file <file>
   gh pr view <number> --json title,body --jq '{title, len: (.body | length)}'
   ```
   Done when the PR exists, `len` is greater than zero, and the title matches `#<N> <type>: <lowercase summary>`.

7. **Labels.** If the repo has a labeling rule, apply it with `gh pr edit <number> --add-label …`.

Report the PR URL.

## Common mistakes

| Mistake | Fix |
|---|---|
| Body passed through stdin or a heredoc | Always `--body-file <path>`; shell wrappers such as `rtk` drop stdin |
| Verification says "tests pass" with no command | Name the command and its numbers |
| Unverified items left out | List them under Not verified; reviewers need to know what was not checked |
| The repo's own template replaced with the default one | The repo template wins; some repos check its headers in CI |
| `#<PR number>` in the title | The title carries the **issue** number |
| A name in backticks that the repo does not contain | Write the real name, or drop the backticks |
| A section left empty | Write `None` |
| Why runs to four paragraphs | Keep it to three; move the rest to Changes or Notes |
