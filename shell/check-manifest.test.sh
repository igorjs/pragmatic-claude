#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# check-manifest.test.sh: scenarios for shell/check-manifest.sh. Builds scratch
# git repos and asserts a clean allowlisted skeleton passes, an out-of-allowlist
# tracked file fails, and a tracked settings.json fails.
#
# Run:  bash shell/check-manifest.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/check-manifest.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

PASS=0
FAIL=0

WORK="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORK}'" EXIT INT TERM

# HOME isolation so no global gitconfig/hooks bleed into the scratch repos.
export HOME="${WORK}/home"
mkdir -p "$HOME"

# init_repo <dir>: create a scratch git repo with local identity, no signing.
init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "audit@example.test"
  git -C "$dir" config user.name "Audit Test"
  git -C "$dir" config commit.gpgsign false
}

# add_file <dir> <relpath>: create an empty tracked fixture at relpath.
add_file() {
  local dir="$1" rel="$2"
  mkdir -p "$dir/$(dirname "$rel")"
  : > "$dir/$rel"
}

# commit_repo <dir>: stage everything and commit.
commit_repo() {
  local dir="$1"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "fixture"
}

# Populate a repo with an allowlisted skeleton (top-level files + dir contents).
seed_skeleton() {
  local dir="$1"
  add_file "$dir" ".gitignore"
  add_file "$dir" "README.md"
  add_file "$dir" "LICENSE"
  add_file "$dir" "settings.shared.json"
  add_file "$dir" "permissions.shared.json"
  add_file "$dir" "statusline.sh"
  add_file "$dir" "shell/worktree.zsh"
  add_file "$dir" "hooks/session-init.sh"
  add_file "$dir" "docs/index.md"
  add_file "$dir" ".github/workflows/ci.yml"
}

run_scenario() {  # <expect: pass|fail> <name> <repo>
  local expect="$1" name="$2" repo="$3" rc
  bash "$GUARD" "$repo" >/dev/null 2>&1; rc=$?
  if [[ "$expect" == pass ]]; then
    if [[ $rc -eq 0 ]]; then echo "PASS: $name"; (( PASS++ )) || true
    else echo "FAIL: $name (expected exit 0, got $rc)"; (( FAIL++ )) || true; fi
  else
    if [[ $rc -ne 0 ]]; then echo "PASS: $name"; (( PASS++ )) || true
    else echo "FAIL: $name (expected non-zero, got 0)"; (( FAIL++ )) || true; fi
  fi
}

# 1: clean allowlisted skeleton -> pass.
CLEAN="${WORK}/clean"
init_repo "$CLEAN"
seed_skeleton "$CLEAN"
commit_repo "$CLEAN"
run_scenario pass "clean skeleton passes" "$CLEAN"

# 2: an out-of-allowlist tracked file -> fail.
LEAK="${WORK}/leak"
init_repo "$LEAK"
seed_skeleton "$LEAK"
add_file "$LEAK" "sessions/leaked.json"
commit_repo "$LEAK"
run_scenario fail "out-of-allowlist file fails (sessions/leaked.json)" "$LEAK"

# 3: a tracked settings.json -> fail.
SETTINGS="${WORK}/settings"
init_repo "$SETTINGS"
seed_skeleton "$SETTINGS"
add_file "$SETTINGS" "settings.json"
commit_repo "$SETTINGS"
run_scenario fail "tracked settings.json fails" "$SETTINGS"

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
