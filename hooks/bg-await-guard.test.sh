#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
# Behavioral tests for bg-await-guard.sh.
#
# The guard reads a Bash tool-call JSON on stdin and, when run_in_background is
# set on an await-sensitive command (install/build/typecheck/node_modules wipe),
# emits an additionalContext nudge. "warn" when it prints JSON; "quiet" when it
# prints nothing.
#
# Run:  bash hooks/bg-await-guard.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/bg-await-guard.sh"
pass=0
fail=0

# run <expect: warn|quiet> <run_in_background: true|false> <command-string>
run() {
  local expect="$1" bg="$2" cmd="$3" out
  out="$(printf '{"tool_input":{"command":%s,"run_in_background":%s}}' \
    "$(json_str "$cmd")" "$bg" | bash "$GUARD" 2>/dev/null)"
  local got="quiet"
  [[ -n "$out" ]] && got="warn"
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: expected %s, got %s for (bg=%s): %s\n' "$expect" "$got" "$bg" "$cmd" >&2
  fi
}

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# --- Warn: backgrounded await-sensitive commands ---
run warn true "npm install"
run warn true "rm -rf node_modules package-lock.json && npm install"
run warn true "pnpm install --frozen-lockfile"
run warn true "yarn install"
run warn true "bun install"
run warn true "npm ci"
run warn true "npm run build"
run warn true "tsc && tsc-alias"
run warn true "make build"
run warn true "cargo build --release"
run warn true "pip install -r requirements.txt"
run warn true "rm -rf node_modules"

# --- Quiet: same commands in the foreground (backgrounding is the trigger) ---
run quiet false "npm install"
run quiet false "npm run build"
run quiet false "rm -rf node_modules && npm install"

# --- Quiet: backgrounded commands that are legitimately long-running watches ---
run quiet true "npm run dev"
run quiet true "vite --host"
run quiet true "tail -f /var/log/app.log"
run quiet true "node server.js"

printf '\nbg-await-guard: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
