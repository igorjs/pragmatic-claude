#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# incr-counter.test.sh: tests for _incr_counter() in hooks/lib/common.sh.
# Covers missing-file init, sequential increment, lock-dir cleanup, and
# pre-seeded starting values. Verifies both file content and $_INCR_RESULT.
#
# Run:  bash hooks/incr-counter.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# common.sh reads stdin at load time (HOOK_INPUT initialisation). Redirect
# /dev/null so the cat inside the [[ ! -t 0 ]] branch consumes nothing and
# HOOK_INPUT stays empty. This is safe because _incr_counter never touches
# HOOK_INPUT; the stdin side-effect is limited to that one assignment.
# shellcheck source=hooks/lib/common.sh
source "$SCRIPT_DIR/../hooks/lib/common.sh" </dev/null

PASS=0
FAIL=0

# Scratch directory; cleaned up on exit.
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# check <name> <got> <want>
check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $name"; (( PASS++ )) || true
  else
    echo "FAIL: $name -> got='$got' want='$want'"; (( FAIL++ )) || true
  fi
}

# Scenario 1: missing file -> file content is 1, _INCR_RESULT is 1
f="$TMPDIR_TEST/counter1"
_incr_counter "$f"
check "missing-file: file content" "$(cat "$f")" "1"
check "missing-file: _INCR_RESULT" "$_INCR_RESULT" "1"

# Scenario 2: second call -> 2 and _INCR_RESULT 2
_incr_counter "$f"
check "second-call: file content" "$(cat "$f")" "2"
check "second-call: _INCR_RESULT" "$_INCR_RESULT" "2"

# Scenario 3: lock dir does NOT exist after the call
if [[ ! -d "${f}.lock" ]]; then
  echo "PASS: lock-dir-absent"; (( PASS++ )) || true
else
  echo "FAIL: lock-dir-absent -> lock dir still exists"; (( FAIL++ )) || true
fi

# Scenario 4: pre-seeded file with 41 -> 42 and _INCR_RESULT 42
f2="$TMPDIR_TEST/counter2"
printf '%s' "41" > "$f2"
_incr_counter "$f2"
check "pre-seeded: file content" "$(cat "$f2")" "42"
check "pre-seeded: _INCR_RESULT" "$_INCR_RESULT" "42"

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
