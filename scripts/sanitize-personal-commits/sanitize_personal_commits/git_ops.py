from __future__ import annotations

import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Tuple

from .planner import Commit


class NoUpstreamError(Exception):
    pass


class SigningNotConfiguredError(Exception):
    pass


class RewriteError(Exception):
    pass


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=check,
    )


def get_upstream(repo: Path) -> str:
    r = _git(
        repo,
        "rev-parse",
        "--abbrev-ref",
        "--symbolic-full-name",
        "@{u}",
        check=False,
    )
    if r.returncode != 0:
        raise NoUpstreamError(r.stderr.strip() or "no upstream configured")
    return r.stdout.strip()


def get_local_email(repo: Path) -> str:
    return _git(repo, "config", "user.email").stdout.strip()


def is_pushed(repo: Path, sha: str) -> bool:
    """True if `sha` is already an ancestor of the branch's upstream, i.e.
    rewriting it would require a force-push. False when there is no upstream."""
    try:
        upstream = get_upstream(repo)
    except NoUpstreamError:
        return False
    r = _git(repo, "merge-base", "--is-ancestor", sha, upstream, check=False)
    return r.returncode == 0


def _count_lines_changed(repo: Path, sha: str) -> int:
    """Sum of insertions + deletions for a commit, from --shortstat."""
    r = _git(repo, "show", "--shortstat", "--format=", sha, check=False)
    if r.returncode != 0 or not r.stdout.strip():
        return 0
    # Last non-empty line: " N files changed, X insertions(+), Y deletions(-)"
    last = [ln for ln in r.stdout.strip().split("\n") if ln.strip()][-1]
    total = 0
    for word in last.replace(",", "").split():
        if word.isdigit():
            total += int(word)
    # Subtract the "N files changed" count
    for word in last.replace(",", "").split():
        if word.isdigit():
            total -= int(word)
            break
    return max(0, total)


def _build_commits(repo: Path, *, local_email: str, range_expr: str) -> List[Commit]:
    fmt = "%H%x00%cI%x00%ae%x00%P"
    r = _git(repo, "log", "--reverse", f"--pretty={fmt}", range_expr)
    if not r.stdout.strip():
        return []
    out: List[Commit] = []
    for line in r.stdout.strip().split("\n"):
        sha, date_str, author_email, parents = line.split("\x00")
        is_merge = len(parents.split()) > 1
        is_foreign = author_email.lower() != local_email.lower()
        lines_changed = _count_lines_changed(repo, sha)
        out.append(
            Commit(
                sha=sha,
                committer_date=datetime.fromisoformat(date_str),
                lines_changed=lines_changed,
                is_merge=is_merge,
                is_foreign=is_foreign,
            )
        )
    return out


def list_unpushed_commits(repo: Path, *, local_email: str) -> List[Commit]:
    upstream = get_upstream(repo)
    return _build_commits(repo, local_email=local_email, range_expr=f"{upstream}..HEAD")


def list_all_commits(repo: Path, *, local_email: str) -> List[Commit]:
    """Every commit reachable from HEAD, oldest first. Used by --all mode to
    sanitize already-pushed history when the repo is solely the local author's."""
    return _build_commits(repo, local_email=local_email, range_expr="HEAD")


def create_backup_branch(repo: Path, name: str) -> str:
    """Point a new branch at current HEAD so the pre-rewrite commits stay
    reachable (and recoverable) after filter-branch moves the working ref."""
    r = _git(repo, "branch", name, "HEAD", check=False)
    if r.returncode != 0:
        raise RewriteError(f"could not create backup branch {name}: {r.stderr.strip()}")
    return name


def check_signing_configured(repo: Path) -> None:
    r = _git(repo, "config", "--get", "commit.gpgsign", check=False)
    if r.stdout.strip().lower() != "true":
        raise SigningNotConfiguredError(
            "commit.gpgsign is not true — refusing to produce unsigned commits"
        )
    r = _git(repo, "config", "--get", "user.signingkey", check=False)
    if not r.stdout.strip():
        raise SigningNotConfiguredError("user.signingkey is not set")


def rewrite_dates(
    repo: Path,
    rewrites: List[Tuple[str, datetime]],
    *,
    sign: bool,
    range_expr: str | None = None,
) -> None:
    """Rewrite committer+author dates for the given SHAs via filter-branch.

    `range_expr` bounds the filter-branch rev-list. Defaults to `@{u}..HEAD`
    (unpushed only); `--all` mode passes `HEAD` to rewrite the full history.
    Only commits listed in `rewrites` are modified; others pass through
    unchanged. If `sign` is True, every commit in the rewritten range is
    re-signed.
    """
    if not rewrites:
        return

    cases = []
    for sha, dt in rewrites:
        iso = dt.isoformat()
        cases.append(
            f'    {sha}) export GIT_AUTHOR_DATE="{iso}"; '
            f'export GIT_COMMITTER_DATE="{iso}" ;;'
        )
    env_filter = "case $GIT_COMMIT in\n" + "\n".join(cases) + "\n  esac"

    cmd = [
        "git", "-C", str(repo), "filter-branch", "-f",
        "--env-filter", env_filter,
    ]
    if sign:
        cmd.extend(["--commit-filter", 'git commit-tree -S "$@"'])

    if range_expr is None:
        range_expr = f"{get_upstream(repo)}..HEAD"
    cmd.append(range_expr)

    env = {**os.environ, "FILTER_BRANCH_SQUELCH_WARNING": "1"}
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        # Best-effort restore
        subprocess.run(
            ["git", "-C", str(repo), "reset", "--hard", "ORIG_HEAD"],
            capture_output=True, check=False,
        )
        raise RewriteError(f"filter-branch failed: {r.stderr or r.stdout}")
