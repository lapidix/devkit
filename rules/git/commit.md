# Commit messages

## Format

```
<type>: <summary>

- <what changed and why>
- <next point>
```

- **Summary**: starts lowercase, imperative mood, 50 characters or fewer, no trailing period.
- **Body**: a blank line after the summary, then bullets. Each bullet says what changed *and* why. Wrap at 72 characters; indent continuation lines by two spaces.
- Write both in English.

Why: the summary is what `git log --oneline`, PR titles and merge commits show, so it stays short and uniform. The reason behind a change is not in the diff, so the body carries it.

```
fix: keep the withdrawal time on a repeated withdraw

- Withdrawing a user who had already withdrawn overwrote the
  withdrawal time, so the re-signup cooldown started over
- A second withdraw now fails with USER_ALREADY_WITHDRAWN
```

## Types

| type | Use for |
|---|---|
| `feat` | A capability that did not exist before |
| `enhance` | Making an existing capability better (behavior changes, but nothing new) |
| `fix` | Correcting behavior that differs from what was intended |
| `refactor` | Changing structure while behavior stays identical |
| `perf` | Making something faster or lighter without changing behavior |
| `style` | Formatting only: whitespace, quotes, line breaks. Not CSS styling |
| `test` | Adding or fixing tests only |
| `docs` | Documentation only, including comments and rule files |
| `chore` | Dependencies, config, tooling that is not CI or build |
| `ci` | CI workflow changes only |
| `build` | Build configuration and bundler changes |
| `revert` | Reverting an earlier commit: `revert: <original summary>` |
| `release` | Release and environment-promotion commits |

## One change per commit

Each commit holds one logical change and passes the repo's checks on its own. When a repo keeps merge commits, every commit stays in history, so a broken intermediate commit breaks `git bisect` for everyone.

## Attribution

A commit message contains only the subject and body above. Leave out `Co-Authored-By: Claude …`, `Generated with …`, and any other AI-attribution trailer or line, and leave out DCO `Signed-off-by` lines.
