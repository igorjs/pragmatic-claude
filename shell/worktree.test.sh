#!/usr/bin/env zsh
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# worktree.test.sh: unit tests for the `cc workspace`/`cc new` branch-name
# transform in shell/worktree.zsh (_cc_workspace). Stubs the worktree engine
# (_cc_worktree, captured) and forces GitHub-username resolution through
# CC_GH_USER, so nothing touches git, gh, or the network.
#
# Run:  zsh shell/worktree.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
emulate -R zsh

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/worktree.zsh"

PASS=0
FAIL=0
typeset -ga CAPTURED
CAPTURED=()

# Stub the engine: record exactly what _cc_workspace delegates, do nothing else.
_cc_worktree() { CAPTURED=("$@"); return 0; }

# Stub gh to fail, so a username only ever comes from CC_GH_USER. Keeps the
# suite hermetic regardless of whether the real gh is installed/authenticated.
gh() { return 1; }

# Start from a known-clean slate (don't inherit a real CC_GH_USER).
unset CC_GH_USER

run_scenario() {
    local name="$1" fn="$2"
    CAPTURED=()
    if "$fn"; then
        print -- "PASS: $name"; (( PASS++ ))
    else
        print -- "FAIL: $name"; (( FAIL++ ))
    fi
}

# Assert the stubbed engine received exactly these args (space-joined).
assert_captured() {
    local expected="$1" got="${(j: :)CAPTURED}"
    [[ "$got" == "$expected" ]] && return 0
    print -u2 -- "  expected engine args: [$expected]"
    print -u2 -- "  got:                  [$got]"
    return 1
}

# 1. Ticket is prefixed with the resolved GitHub username.
test_username_prefix() {
    CC_GH_USER=igorjs
    _cc_workspace --ai-resolve PROJ-1234 || return 1
    unset CC_GH_USER
    assert_captured "--ai-resolve igorjs/PROJ-1234"
}

# 2. No username resolves -> bare ticket, no prefix (the documented fallback).
test_bare_fallback() {
    unset CC_GH_USER
    _cc_workspace --ai-resolve PROJ-1234 || return 1
    assert_captured "--ai-resolve PROJ-1234"
}

# 3. An optional env-base-folder passes through as the engine's 2nd positional.
test_env_base_passthrough() {
    CC_GH_USER=igorjs
    _cc_workspace --ai-resolve PROJ-1234 backend || return 1
    unset CC_GH_USER
    assert_captured "--ai-resolve igorjs/PROJ-1234 backend"
}

# 4. Extra flags pass straight through, in order, ahead of the branch.
test_extra_flags_passthrough() {
    CC_GH_USER=igorjs
    _cc_workspace --ai-resolve --foo PROJ-1234 || return 1
    unset CC_GH_USER
    assert_captured "--ai-resolve --foo igorjs/PROJ-1234"
}

# 5. Missing ticket -> usage error, engine never invoked.
test_missing_ticket() {
    CC_GH_USER=igorjs
    _cc_workspace --ai-resolve 2>/dev/null
    local rc=$?
    unset CC_GH_USER
    (( rc != 0 ))          || { print -u2 -- "  expected non-zero exit, got $rc"; return 1; }
    (( ${#CAPTURED} == 0 )) || { print -u2 -- "  engine should not be called"; return 1; }
    return 0
}

run_scenario "username prefix"            test_username_prefix
run_scenario "bare-ticket fallback"       test_bare_fallback
run_scenario "env-base pass-through"      test_env_base_passthrough
run_scenario "extra flags pass-through"   test_extra_flags_passthrough
run_scenario "missing ticket errors"      test_missing_ticket

print -- "----"
print -- "PASS: $PASS  FAIL: $FAIL"
(( FAIL == 0 ))
