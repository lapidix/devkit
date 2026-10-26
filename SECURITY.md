# Security policy

## Supported versions

Only `main`. Every commit on it is a release, so a fix ships in the next commit, and a project gets it with a plugin update or a rerun of `copy-rules.sh`.

## Reporting a vulnerability

Report it privately on GitHub: **Security → [Report a vulnerability](https://github.com/lapidix/devkit/security/advisories/new)**. Do not open a public issue, pull request or discussion.

Include the rule, skill or script, what it makes an agent or a machine do, and the steps that show it. Please keep the details private until the fix is on `main`.

## Scope

The scripts run on users' machines, and the rules and skills steer coding agents in users' projects. In scope:

- a script writing, linking or deleting outside what it documents: `copy-rules.sh` writes `.claude/rules/` and `AGENTS.md` inside the project it is given, and `link-user.sh` creates one symlink at `~/.claude/rules/git`;
- a skill that has an agent run a command that is not its documented check, or send data outside the project;
- a rule or skill that has an agent weaken a project's security: a default that exposes secrets or data, a check it turns off, or advice that disables a defense the rules elsewhere require.

Out of scope:

- the agents themselves (Claude Code, Codex) and how they load rules and skills;
- a project's own code, even when it was written following a rule. Report a rule that leads to insecure code as above.
