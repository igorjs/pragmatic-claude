#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# check-shared-settings.test.sh: scenarios for shell/check-shared-settings.sh.
# Builds scratch TEMPLATE / PERMISSIONS / REPO_ROOT fixtures, asserts a good
# template passes, asserts each injected defect fails, and covers the rtk skip,
# dual-prefix (~/.claude vs $HOME/.claude) hook resolution, and the jq-absent
# error path.
#
# Run:  bash shell/check-shared-settings.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/check-shared-settings.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available"
  exit 0
fi

PASS=0
FAIL=0

WORK="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORK}'" EXIT INT TERM

# HOME isolation: the guard resolves prefixes textually, but keep it hermetic.
export HOME="${WORK}/home"
mkdir -p "$HOME"

# Scratch repo root holding the files that hook commands point at.
REPO="${WORK}/repo"
mkdir -p "${REPO}/hooks"
: > "${REPO}/hooks/session-init.sh"
: > "${REPO}/x.sh"

# Tracked permissions fixture.
PERMS="${WORK}/permissions.json"
cat > "$PERMS" <<'JSON'
{
  "allow": ["Read", "Bash(git:*)"],
  "deny": ["Read(**/.env)"],
  "ask": ["Bash(curl:*)"],
  "defaultMode": "auto"
}
JSON

# Base template (permissions injected below so it deep-equals PERMS).
BASE="${WORK}/base.json"
cat > "$BASE" <<'JSON'
{
  "skipAutoPermissionPrompt": false,
  "permissions": {},
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/session-init.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "rtk hook claude" } ] }
    ]
  }
}
JSON

GOOD="${WORK}/good.json"
jq --slurpfile p "$PERMS" '.permissions = $p[0]' "$BASE" > "$GOOD"

# Defect templates derived from the good one.
BAD_PERMS="${WORK}/bad-perms.json"
jq '.permissions.allow += ["Sneaky"]' "$GOOD" > "$BAD_PERMS"

BAD_MODEL="${WORK}/bad-model.json"
jq '.model = "opus"' "$GOOD" > "$BAD_MODEL"

BAD_SKIP="${WORK}/bad-skip.json"
jq '.skipAutoPermissionPrompt = true' "$GOOD" > "$BAD_SKIP"

BAD_HOOK="${WORK}/bad-hook.json"
jq '.hooks.SessionStart[0].hooks[0].command = "~/.claude/hooks/does-not-exist.sh"' \
  "$GOOD" > "$BAD_HOOK"

# rtk-only hooks: proves the rtk prefix is skipped, not failed.
RTK_ONLY="${WORK}/rtk-only.json"
jq '.hooks = {"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}' \
  "$GOOD" > "$RTK_ONLY"

# Dual-prefix resolution: both ~/.claude/x.sh and $HOME/.claude/x.sh -> REPO/x.sh.
DUAL="${WORK}/dual.json"
jq '.hooks = {"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"~/.claude/x.sh"},{"type":"command","command":"$HOME/.claude/x.sh"}]}]}' \
  "$GOOD" > "$DUAL"

expect_pass() {  # <name> <template>
  local name="$1" tmpl="$2"
  if bash "$GUARD" "$tmpl" "$PERMS" "$REPO" >/dev/null 2>&1; then
    echo "PASS: $name"; (( PASS++ )) || true
  else
    echo "FAIL: $name (expected exit 0, got non-zero)"; (( FAIL++ )) || true
  fi
}

expect_fail() {  # <name> <template>
  local name="$1" tmpl="$2"
  if bash "$GUARD" "$tmpl" "$PERMS" "$REPO" >/dev/null 2>&1; then
    echo "FAIL: $name (expected non-zero, got exit 0)"; (( FAIL++ )) || true
  else
    echo "PASS: $name"; (( PASS++ )) || true
  fi
}

expect_pass "good template validates"                 "$GOOD"
expect_fail "wrong .permissions is rejected"          "$BAD_PERMS"
expect_fail "a pinned .model is rejected"             "$BAD_MODEL"
expect_fail ".skipAutoPermissionPrompt != false"      "$BAD_SKIP"
expect_fail "missing hook path is rejected"           "$BAD_HOOK"

# Each personal key must be rejected when present.
for key in effortLevel theme preferredNotifChannel prefersReducedMotion; do
  f="${WORK}/personal-${key}.json"
  jq --arg k "$key" '.[$k] = "leaked"' "$GOOD" > "$f"
  expect_fail "personal key present is rejected: ${key}" "$f"
done

expect_pass "rtk hook command is skipped, not failed"  "$RTK_ONLY"
expect_pass "dual-prefix hook paths both resolve"      "$DUAL"

# jq-absent: run the guard with an empty PATH; it must error out non-zero.
scenario_jq_absent() {
  local bashbin rc
  bashbin="$(command -v bash)"
  env -i PATH=/nonexistent HOME="$HOME" "$bashbin" "$GUARD" "$GOOD" "$PERMS" "$REPO" \
    >/dev/null 2>&1
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "PASS: jq absent errors non-zero"; (( PASS++ )) || true
  else
    echo "FAIL: jq absent should error but exited 0"; (( FAIL++ )) || true
  fi
}
scenario_jq_absent

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
