#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# install-seed.test.sh: hermetic tests for install.sh's settings.json handling.
# Exercises the PRAGMATIC_CLAUDE_SRC local-source seam (no network) to cover the
# first-install seed of settings.json from settings.shared.json, preservation of
# a pre-existing settings.json, the no-template no-op, and the copy-loop skip
# that keeps a shipped settings.json from clobbering the seeded default.
#
# Run:  bash shell/install-seed.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
INSTALL="${REPO_ROOT}/install.sh"
TEMPLATE="${REPO_ROOT}/settings.shared.json"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; (( PASS++ )) || true; }
fail() { echo "FAIL: $1"; (( FAIL++ )) || true; }

# Single top-level scratch dir; each scenario carves out its own subtree.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Run the real installer against a local source, fully hermetic: the seam skips
# the network path and --no-setup skips brew/zshrc/shell-reload.
run_install() {
  local src="$1" home="$2"
  PRAGMATIC_CLAUDE_SRC="$src" CLAUDE_HOME="$home" HOME="$home" \
    bash "$INSTALL" --no-setup >/dev/null 2>&1
}

run_scenario() {
  local name="$1" fn="$2"
  if "$fn"; then pass "$name"; else fail "$name"; fi
}

# (a) Fresh install seeds settings.json from the template.
scenario_fresh() {
  local d src home rc
  d="$(mktemp -d "$WORK/fresh.XXXXXX")"
  src="$d/src"; home="$d/home"
  mkdir -p "$src" "$home"
  cp "$TEMPLATE" "$src/settings.shared.json"
  printf 'placeholder\n' > "$src/CLAUDE.md"

  run_install "$src" "$home"; rc=$?
  [ "$rc" -eq 0 ]                       || { echo "  install rc=$rc"; return 1; }
  [ -f "$home/settings.json" ]          || { echo "  settings.json not created"; return 1; }
  cmp -s "$home/settings.json" "$TEMPLATE" || { echo "  settings.json != template"; return 1; }
}

# (b) A pre-existing settings.json survives byte-for-byte.
scenario_preserve() {
  local d src home rc
  d="$(mktemp -d "$WORK/preserve.XXXXXX")"
  src="$d/src"; home="$d/home"
  mkdir -p "$src" "$home"
  cp "$TEMPLATE" "$src/settings.shared.json"
  printf 'SENTINEL not even json {\n' > "$home/settings.json"
  cp "$home/settings.json" "$d/expected"

  run_install "$src" "$home"; rc=$?
  [ "$rc" -eq 0 ]                          || { echo "  install rc=$rc"; return 1; }
  cmp -s "$home/settings.json" "$d/expected" || { echo "  settings.json was modified"; return 1; }
}

# (c) No template present: exit 0 and create no settings.json.
scenario_no_template() {
  local d src home rc
  d="$(mktemp -d "$WORK/notmpl.XXXXXX")"
  src="$d/src"; home="$d/home"
  mkdir -p "$src" "$home"
  printf 'placeholder\n' > "$src/CLAUDE.md"

  run_install "$src" "$home"; rc=$?
  [ "$rc" -eq 0 ]               || { echo "  install rc=$rc"; return 1; }
  [ ! -e "$home/settings.json" ] || { echo "  settings.json unexpectedly created"; return 1; }
}

# (d) Copy loop skips a shipped settings.json; only the seed step writes it.
scenario_skip_shipped() {
  local d src home rc
  d="$(mktemp -d "$WORK/skip.XXXXXX")"
  src="$d/src"; home="$d/home"
  mkdir -p "$src" "$home"
  cp "$TEMPLATE" "$src/settings.shared.json"
  printf 'SHIPPED SENTINEL must never land\n' > "$src/settings.json"
  cp "$src/settings.json" "$d/sentinel"

  run_install "$src" "$home"; rc=$?
  [ "$rc" -eq 0 ]              || { echo "  install rc=$rc"; return 1; }
  [ -f "$home/settings.json" ] || { echo "  settings.json not created"; return 1; }
  if cmp -s "$home/settings.json" "$d/sentinel"; then
    echo "  copy loop did NOT skip settings.json (sentinel landed)"; return 1
  fi
  cmp -s "$home/settings.json" "$TEMPLATE"        || { echo "  settings.json != template"; return 1; }
  cmp -s "$home/settings.shared.json" "$TEMPLATE" || { echo "  settings.shared.json != template"; return 1; }
}

run_scenario "A: fresh install seeds settings.json from template" scenario_fresh
run_scenario "B: existing settings.json is preserved"            scenario_preserve
run_scenario "C: missing template is a no-op (exit 0)"           scenario_no_template
run_scenario "D: copy loop skips a shipped settings.json"        scenario_skip_shipped

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
