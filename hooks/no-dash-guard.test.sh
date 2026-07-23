#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
# Behavioral tests for no-dash-guard.sh.
#
# The guard reads a Bash tool-call JSON on stdin and, for a posting command
# (gh/git) whose inline text or referenced body/message file contains an em or
# en dash, emits a deny decision. "block" when it prints JSON; "allow" when it
# prints nothing.
#
# Run:  bash hooks/no-dash-guard.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/no-dash-guard.sh"
pass=0
fail=0

EM=$'—'   # em dash
EN=$'–'   # en dash

TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT
DASH_FILE="$TMPDIR_T/body-dash.md"
CLEAN_FILE="$TMPDIR_T/body-clean.md"
printf 'Summary line with an em dash %s here.\n' "$EM" > "$DASH_FILE"
printf 'Summary line, clean, no dashes here.\n' > "$CLEAN_FILE"

run() {
  local expect="$1" cmd="$2" out
  out="$(printf '{"tool_input":{"command":%s}}' "$(json_str "$cmd")" | bash "$GUARD" 2>/dev/null)"
  local got="allow"
  [[ -n "$out" ]] && got="block"
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: expected %s, got %s for: %s\n' "$expect" "$got" "$cmd" >&2
  fi
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# --- Block: posting commands with an inline em/en dash ---
run block "gh pr edit 42 --title \"feat: do a thing ${EM} really\""
run block "gh pr create --title \"fix: a ${EN} b\" --body \"x\""
run block "git commit -m \"fix: stop stale reads ${EM} after invalidation\""
run block "git tag -a v1.0 -m \"release ${EN} first\""
run block "gh pr comment 42 --body \"nice work ${EM} ship it\""

# --- Block: posting command whose body/message FILE contains a dash ---
run block "gh pr create --body-file $DASH_FILE --title \"clean title\""
run block "gh pr edit 42 --body-file=$DASH_FILE"
run block "git commit -F $DASH_FILE"
run block "gh api -X POST /repos/o/r/pulls/1/reviews --input $DASH_FILE"

# --- Allow: posting commands that are clean (ascii hyphen only) ---
run allow "gh pr edit 42 --title \"feat: do a thing - really\""
run allow "git commit -m \"fix: stop stale reads after invalidation\""
run allow "gh pr create --body-file $CLEAN_FILE --title \"clean title\""
run allow "git commit -F $CLEAN_FILE"

# --- Allow: NON-posting commands are never guarded, even with a dash ---
run allow "echo \"a ${EM} b\""
run allow "grep -n \"${EN}\" notes.md"
run allow "gh pr view 42"
run allow "gh pr diff 42"

printf '\nno-dash-guard: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
