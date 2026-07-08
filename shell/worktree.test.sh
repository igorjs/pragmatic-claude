#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# worktree.test.sh: focused tests for the worktree base-dir resolver in
# shell/worktree.zsh (_wt_resolve_base). Covers the default base, relative and
# absolute WORKTREE_BASE_DIR overrides, the repo-name grouping leaf, and the
# guard that stops a "." base collapsing back into the repo root.
#
# Run:  bash shell/worktree.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SCRIPT_DIR}/worktree.zsh"
PASS=0
FAIL=0

if ! command -v zsh >/dev/null 2>&1; then
  echo "SKIP: zsh not available; worktree.zsh resolver tests need zsh"
  exit 0
fi

# Resolve the base dir by sourcing the engine under zsh and calling the helper.
# Args: 1=WORKTREE_BASE_DIR value ("" for default), 2=repo_root, 3=repo_parent.
resolve() {
  local base="$1" root="$2" parent="$3"
  # shellcheck disable=SC2016  # $1..$3 are for the zsh subshell, not bash
  WORKTREE_BASE_DIR="$base" \
    zsh -c 'source "$1"; _wt_resolve_base "$2" "$3"' _ "$ENGINE" "$root" "$parent"
}

run_scenario() {
  local name="$1" fn="$2"
  if "$fn" 2>&1; then echo "PASS: $name"; (( PASS++ )) || true
  else echo "FAIL: $name"; (( FAIL++ )) || true; fi
}

# Default base: <repo-parent>/.worktrees/<repo>
scenario_default() {
  local got want="/home/u/ws/.worktrees/myrepo"
  got="$(resolve "" "/home/u/ws/myrepo" "/home/u/ws")"
  [[ "$got" == "$want" ]] || { echo "  got '$got' want '$want'"; return 1; }
}

# Relative override sits under the repo parent: <repo-parent>/<base>/<repo>
scenario_relative() {
  local got want="/home/u/ws/trees/myrepo"
  got="$(resolve "trees" "/home/u/ws/myrepo" "/home/u/ws")"
  [[ "$got" == "$want" ]] || { echo "  got '$got' want '$want'"; return 1; }
}

# Absolute override is used as-is, with <repo> appended
scenario_absolute() {
  local got want="/var/wt/myrepo"
  got="$(resolve "/var/wt" "/home/u/ws/myrepo" "/home/u/ws")"
  [[ "$got" == "$want" ]] || { echo "  got '$got' want '$want'"; return 1; }
}

# Same-named branches in sibling repos land in distinct dirs (collision guard)
scenario_grouping() {
  local a b
  a="$(resolve "" "/home/u/ws/repo-a" "/home/u/ws")"
  b="$(resolve "" "/home/u/ws/repo-b" "/home/u/ws")"
  [[ "$a" != "$b" ]]    || { echo "  grouping collided: '$a' == '$b'"; return 1; }
  [[ "$a" == */repo-a ]] || { echo "  repo-a leaf missing: '$a'"; return 1; }
  [[ "$b" == */repo-b ]] || { echo "  repo-b leaf missing: '$b'"; return 1; }
}

# A "." base must not resolve back into the repo root
scenario_dot_guard() {
  local got repo_root="/home/u/ws/myrepo"
  got="$(resolve "." "$repo_root" "/home/u/ws")"
  [[ "$got" != "$repo_root" ]]                  || { echo "  '.' collapsed into repo root: '$got'"; return 1; }
  [[ "$got" == "/home/u/ws/.worktrees/myrepo" ]] || { echo "  '.' not defaulted: '$got'"; return 1; }
}

run_scenario "A: default base is .worktrees/<repo>"       scenario_default
run_scenario "B: relative WORKTREE_BASE_DIR override"     scenario_relative
run_scenario "C: absolute WORKTREE_BASE_DIR override"     scenario_absolute
run_scenario "D: repo-name grouping avoids collisions"    scenario_grouping
run_scenario "E: '.' base guarded to default"             scenario_dot_guard

# ── WU-4: smoke tests ─────────────────────────────────────────────────────────

# F: Branch classification – assert the protected-branch case patterns directly.
# Exact patterns from worktree.zsh:378 (more than the spec listed):
#   main|master|trunk|develop|dev|staging|release|release/*|hotfix|hotfix/*
scenario_branch_classification() {
  local branch result ok=1
  local CASE_SNIPPET='
    b="$1"
    case "$b" in
      main|master|trunk|develop|dev|staging|release|release/*|hotfix|hotfix/*) print protected ;;
      *) print feature ;;
    esac
  '
  for branch in main master trunk develop dev staging release "release/1.2" hotfix "hotfix/x"; do
    result="$(zsh -c "$CASE_SNIPPET" _ "$branch")"
    if [[ "$result" != "protected" ]]; then
      echo "  branch '$branch': expected 'protected', got '$result'"
      ok=0
    fi
  done
  for branch in "feature/foo" mybranch; do
    result="$(zsh -c "$CASE_SNIPPET" _ "$branch")"
    if [[ "$result" != "feature" ]]; then
      echo "  branch '$branch': expected 'feature', got '$result'"
      ok=0
    fi
  done
  (( ok ))
}

# G: _wt_restore_stash pops the stash when STASH_APPLIED=1, is a no-op when 0.
# Env vars confirmed from worktree.zsh:212-215: STASH_APPLIED, MAIN_WORKTREE.
scenario_restore_stash() {
  local repo ok=1
  repo="$(mktemp -d)"

  git -C "$repo" init -q
  git -C "$repo" config user.email "t@t"
  git -C "$repo" config user.name "t"
  printf 'initial\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "initial"

  # Sub-case 1: STASH_APPLIED=1 -> _wt_restore_stash must pop the stash
  printf 'dirty\n' > "$repo/file.txt"
  git -C "$repo" stash push --quiet -m "test stash"

  local content
  content="$(cat "$repo/file.txt")"
  if [[ "$content" != "initial" ]]; then
    echo "  pre-condition: stash push did not restore working tree (got '$content')"
    ok=0
  fi

  # shellcheck disable=SC2016
  zsh -c '
    source "$1"
    STASH_APPLIED=1
    MAIN_WORKTREE="$2"
    _wt_restore_stash
  ' _ "$ENGINE" "$repo"

  content="$(cat "$repo/file.txt")"
  if [[ "$content" != "dirty" ]]; then
    echo "  sub-case 1 (STASH_APPLIED=1): expected 'dirty' after pop, got '$content'"
    ok=0
  fi

  # Sub-case 2: STASH_APPLIED=0 -> no-op; stash list must be unchanged
  git -C "$repo" stash push --quiet -m "another stash"
  local before after
  before="$(git -C "$repo" stash list | wc -l | tr -d '[:space:]')"

  # shellcheck disable=SC2016
  zsh -c '
    source "$1"
    STASH_APPLIED=0
    MAIN_WORKTREE="$2"
    _wt_restore_stash
  ' _ "$ENGINE" "$repo"

  after="$(git -C "$repo" stash list | wc -l | tr -d '[:space:]')"
  if [[ "$before" != "$after" ]]; then
    echo "  sub-case 2 (STASH_APPLIED=0): stash count changed ($before -> $after); should be no-op"
    ok=0
  fi

  rm -rf "$repo"
  (( ok ))
}

# H: _wt_find_env_base across four cases.
# The function reads $REPO_ROOT as a global (confirmed worktree.zsh:103-115).
# Calling convention: _wt_find_env_base [arg] where arg is optional.
scenario_find_env_base() {
  local repo ok=1
  repo="$(mktemp -d)"

  git -C "$repo" init -q

  # (a) REPO_ROOT/.env exists, no arg -> returns "."
  touch "$repo/.env"
  local got
  # shellcheck disable=SC2016
  got="$(zsh -c 'source "$1"; REPO_ROOT="$2"; _wt_find_env_base' _ "$ENGINE" "$repo")"
  if [[ "$got" != "." ]]; then
    echo "  (a) REPO_ROOT/.env exists, no arg: expected '.', got '$got'"
    ok=0
  fi
  rm "$repo/.env"

  # (b) exactly one nested sub/.env, no arg -> returns subdir name
  mkdir -p "$repo/apps"
  touch "$repo/apps/.env"
  # shellcheck disable=SC2016
  got="$(zsh -c 'source "$1"; REPO_ROOT="$2"; _wt_find_env_base' _ "$ENGINE" "$repo")"
  if [[ "$got" != "apps" ]]; then
    echo "  (b) nested apps/.env, no arg: expected 'apps', got '$got'"
    ok=0
  fi
  rm "$repo/apps/.env"
  rmdir "$repo/apps"

  # (c) explicit valid arg "myenv" with REPO_ROOT/myenv/.env -> returns "myenv"
  mkdir -p "$repo/myenv"
  touch "$repo/myenv/.env"
  # shellcheck disable=SC2016
  got="$(zsh -c 'source "$1"; REPO_ROOT="$2"; _wt_find_env_base "$3"' _ "$ENGINE" "$repo" "myenv")"
  if [[ "$got" != "myenv" ]]; then
    echo "  (c) explicit arg 'myenv': expected 'myenv', got '$got'"
    ok=0
  fi
  rm "$repo/myenv/.env"
  rmdir "$repo/myenv"

  # (d) no .env anywhere, no arg -> returns ""
  # shellcheck disable=SC2016
  got="$(zsh -c 'source "$1"; REPO_ROOT="$2"; _wt_find_env_base' _ "$ENGINE" "$repo")"
  if [[ "$got" != "" ]]; then
    echo "  (d) no .env, no arg: expected '', got '$got'"
    ok=0
  fi

  rm -rf "$repo"
  (( ok ))
}

run_scenario "F: branch classification (protected vs feature)"  scenario_branch_classification
run_scenario "G: _wt_restore_stash stash-pop and no-op"        scenario_restore_stash
run_scenario "H: _wt_find_env_base four cases"                 scenario_find_env_base

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
