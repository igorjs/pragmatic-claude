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

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
