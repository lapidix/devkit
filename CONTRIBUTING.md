# Contributing

## Report a rule that is wrong

Open an issue with the **Rule is wrong or out of date** form. Name the rule file, quote what it says, and say what is true instead, with the evidence: the library version and its changelog or docs, or a short example that fails when it follows the rule.

## Ask for a rule or skill

Open an issue with the **Rule or skill request** form. Describe what agents get wrong today without it, and the stack it is for.

## Pull requests

1. Start from an issue. Branch from `main` as `issue/<N>-<kebab-slug>`.
2. Make the change following [AGENTS.md](AGENTS.md), which holds the conventions for rules and skills. Coding agents read it on their own; read it yourself before your first change.
3. Sign off every commit with `git commit -s`. The DCO check fails on a commit without a `Signed-off-by` line, and the line certifies the [Developer Certificate of Origin](https://developercertificate.org/) for your change.
4. Run the checks CI runs:
   ```bash
   bash scripts/check-catalog.sh
   claude plugin validate . --strict
   claude plugin validate ./skills
   shellcheck scripts/*.sh examples/*.sh examples/*/check.sh
   ```
   When you change a skill example, or a rule its support files follow, also run that example's `bash examples/{frontend,nestjs,go}/check.sh`. They need Node 22 and Go. The Go database tests run when `TEST_DATABASE_URL` points at a PostgreSQL 17 database you can throw away, and skip without it.
5. Open the pull request with the title `#<N> <type>: <summary>` and fill in the template. The maintainer reviews it; it merges once DCO and CI pass and the review approves it.

Commit messages follow [`rules/git/commit.md`](rules/git/commit.md), and pull requests follow [`rules/git/pull-request.md`](rules/git/pull-request.md).

## Security issues

Report them privately, as [SECURITY.md](SECURITY.md) describes, not in a public issue.
