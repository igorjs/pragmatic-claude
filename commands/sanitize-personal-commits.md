---
description: Rewrite business-hours commit timestamps from the first violation onward, back up, then push. On-demand, so history changes only when you ask.
allowed-tools: Bash
argument-hint: "[--dry-run] [--all] [--squash] [git push args]"
---

# Sanitize Personal Commits

Run the sanitize-personal-commits engine on demand: find the earliest commit
that falls in the hard cap (Sydney Mon-Fri 09:00-17:00) and rewrite the
committer/author dates from there to HEAD, re-sign, then `git push`. It runs only
when you invoke it, so history changes only when you ask.

Two nested windows govern timestamps: the hard cap (09:00-17:00) is inviolable —
commits there are always moved and nothing is ever placed inside it. The soft cap
(08:00-18:00) is preferred-avoid: rewrites aim to land fully outside it, but the
08:00-09:00 / 17:00-18:00 buffer is a tolerated fallback (a warning, not a
failure) that absorbs DST shifts. A commit sitting in the buffer is flagged but
not forced to move.

The rewrite range can include already-pushed commits. When it does, the engine
backs up the original HEAD to a `backup/pre-sanitize-<timestamp>` branch and
force-pushes with lease. It only ever rewrites a range that is solely your own
commits: if any commit by another author sits inside the range, it refuses.

The engine lives at `~/.claude/scripts/sanitize-personal-commits/sanitize-personal-commits` and owns
all the logic: per-repo locking, signing checks, the rewrite planner, the
backup branch, and the push. This command is a thin wrapper.

## Argument parsing

`$ARGUMENTS` is passed straight through to the engine, which splits its own
flags from the trailing `git push` args:

- `--dry-run` → show the planned rewrites, the backup branch, and the push that would run, change nothing.
- `--all` → rewrite the entire history (root..HEAD), re-signing every commit, instead of only from the first violation.
- `--squash` → collapse each contiguous run of business-hours commits into a single commit dated after 17:00, folding it into the immediately following same-day after-17:00 commit when one exists (which keeps its date), otherwise synthesizing one new commit on that day. The combined message is regenerated to describe the changes only. Use instead of the default scatter when you'd rather have one tidy commit per session.
- Everything else (`origin`, branch refs, `-u`, etc.) is forwarded to `git push`.

No args means: rewrite from the first violation if needed, then `git push` (force-with-lease only if the range was already pushed).

## Execution rules

1. Run the engine for real. Do not simulate.
2. The engine decides whether a force-push is needed (range already pushed) and adds `--force-with-lease` itself. Do not add `--force` yourself; forward only the push args the user passed.
3. The engine rewrites with `git filter-branch` only when forbidden-window commits exist and signing is configured. It backs up HEAD to a branch first and restores via `ORIG_HEAD` on filter-branch failure.
4. Report the engine's outcome from its exit code; do not second-guess it.
5. After a successful rewrite (Step 3), always offer to delete the backup branch.

## Step 1: Run the engine

```bash
out=$(python3 "$HOME/.claude/scripts/sanitize-personal-commits/sanitize-personal-commits" $ARGUMENTS 2>&1)
rc=$?
printf '%s\n' "$out"
echo "sanitize-personal-commits exit: $rc"
```

## Step 2: Interpret the result

Map the exit code to a one-line outcome for the user:

- `0` — pushed (or, with `--dry-run`, preview shown). If commits were rewritten, the engine logs each to `~/.claude/logs/sanitize-personal-commits.log` and prints `BACKUP_BRANCH=<name>`.
- `2` — not in a git repo.
- `3` — another instance holds the lock for this repo; retry once it frees.
- `4` — signing not configured (`commit.gpgsign` + `user.signingkey` required). Nothing was rewritten or pushed.
- `5` — the rewrite planner could not fit the commits into valid timestamps. Nothing pushed.
- `6` — backup or the rewrite (`git filter-branch`, or the `--squash` rebuild) failed; the engine restored the original HEAD. Nothing pushed.
- `7` — the range contains commits by another author (any mode), or merge commits with `--squash`; refused so it never force-pushes history that isn't safely, solely yours. Nothing changed.
- `8` — `--squash` only: a business-hours run has no after-17:00 slot at or before now (e.g. you ran it mid-workday). Re-run after 17:00. Nothing changed.

For any non-zero code, surface the engine's stderr verbatim and stop. Don't retry automatically (except to tell the user a `3` is safe to retry).

## Step 3: Offer to delete the backup branch

Only on exit `0` and only when the output contains a `BACKUP_BRANCH=` line (a real rewrite happened, not a dry run). Parse the branch name and ask the user whether to delete it now that the push succeeded:

```bash
backup=$(printf '%s\n' "$out" | sed -n 's/^BACKUP_BRANCH=//p')
```

If `$backup` is set, ask: "Rewrite pushed successfully. Delete the backup branch `$backup`? [y/N]". On an explicit yes, run `git branch -D "$backup"`. On anything else, leave it and tell the user it remains as a recovery point.

## Notes

- Preview first with `/sanitize-personal-commits --dry-run` to see which commits would move, the backup branch, and whether the push would be forced.
- Merge commits and commits authored by someone else are never rewritten; they anchor ordering. A foreign commit inside the rewrite range aborts the run (exit `7`). In `--squash` mode a merge commit inside the range also aborts (exit `7`), since the linear rebuild can't reconstruct it.
- `--squash` rebuilds via `git commit-tree` (not `filter-branch`), re-signs every commit, and verifies the final tree is byte-identical before moving the branch with `reset --soft` (so uncommitted changes are preserved). The squashed commit's message is AI-generated to describe the code changes and never references squashing, timestamps, or hours.
- Commits that land in (or already sit in) the 08:00-09:00 / 17:00-18:00 buffer print a `WARNING` to stderr but do not fail the run. Surface those warnings to the user.
- The engine reads the hard/soft caps and timezone from `sanitize_personal_commits/windows.py` (`HARD_*_HOUR`, `SOFT_*_HOUR`). Change them there, not here.
