#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# setup-local.test.sh: hermetic tests for shell/setup-local.sh.
# Each scenario carves its own mktemp HOME; the real ~/.claude is never
# touched. --skip-deps and --skip-shell keep brew and ~/.zshrc out of scope.
#
# Run:  bash shell/setup-local.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/setup-local.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; (( PASS++ )) || true; }
fail() { echo "FAIL: $1"; (( FAIL++ )) || true; }

# Single top-level scratch dir; each scenario carves its own subtree.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Run setup-local.sh with a controlled CLAUDE_HOME, always skipping brew and
# zshrc so the test stays hermetic.  HOME is set to a temp dir so that any
# accidental ~/.zshrc write goes nowhere harmful.
run_setup() {
    local home="$1"; shift
    CLAUDE_HOME="$home" HOME="$home" bash "$SCRIPT" --skip-deps --skip-shell "$@" >/dev/null 2>&1
}

run_scenario() {
    local name="$1" fn="$2"
    if "$fn"; then pass "$name"; else fail "$name"; fi
}

# ---------------------------------------------------------------------------
# (a) FRESH: run into an empty HOME.
#     Expects: settings.json seeded, 3 guards wired in settings.json (>=3),
#     .settings.base.json written, all 3 guard hook files present.
# ---------------------------------------------------------------------------
scenario_fresh() {
    local d home rc guards g
    d="$(mktemp -d "$WORK/fresh.XXXXXX")"
    home="$d/home"
    mkdir -p "$home"

    run_setup "$home"; rc=$?
    [ "$rc" -eq 0 ] || { echo "  rc=$rc"; return 1; }

    [ -f "$home/settings.json" ] \
        || { echo "  settings.json not created"; return 1; }
    [ -f "$home/.settings.base.json" ] \
        || { echo "  .settings.base.json not created"; return 1; }

    guards="$(jq '[.hooks.PreToolUse[]?.hooks[]?.command]
                  | map(select(test("rm-workspace-guard|bg-await-guard|no-dash-guard")))
                  | length' \
                "$home/settings.json" 2>/dev/null || echo 0)"
    [ "${guards:-0}" -ge 3 ] \
        || { echo "  guards=${guards:-0} (expected >=3)"; return 1; }

    for g in rm-workspace-guard.sh bg-await-guard.sh no-dash-guard.sh; do
        [ -f "$home/hooks/$g" ] \
            || { echo "  guard hook not copied: $g"; return 1; }
    done
}

# ---------------------------------------------------------------------------
# (b) IDEMPOTENT: run three times (seed, normalise, no-op).
#     settings.json and .settings.base.json must be byte-identical between
#     runs 2 and 3 (the seed-to-jq format shift from run 1 to run 2 is
#     expected; only the subsequent run is the idempotency test).
# ---------------------------------------------------------------------------
scenario_idempotent() {
    local d home rc
    d="$(mktemp -d "$WORK/idem.XXXXXX")"
    home="$d/home"
    mkdir -p "$home"

    # Run 1: fresh seed (cp format, not yet jq-normalised).
    run_setup "$home"; rc=$?
    [ "$rc" -eq 0 ] || { echo "  run1 rc=$rc"; return 1; }

    # Run 2: first merge run -- normalises to jq-sorted format, refreshes base.
    run_setup "$home"; rc=$?
    [ "$rc" -eq 0 ] || { echo "  run2 rc=$rc"; return 1; }

    cp "$home/settings.json"       "$d/settings_after2.json"
    cp "$home/.settings.base.json" "$d/base_after2.json"

    # Run 3: must be a strict no-op.
    run_setup "$home"; rc=$?
    [ "$rc" -eq 0 ] || { echo "  run3 rc=$rc"; return 1; }

    cmp -s "$home/settings.json" "$d/settings_after2.json" \
        || { echo "  settings.json changed on idempotent run"; return 1; }
    cmp -s "$home/.settings.base.json" "$d/base_after2.json" \
        || { echo "  .settings.base.json changed on idempotent run"; return 1; }
}

# ---------------------------------------------------------------------------
# (c) MERGE-PRESERVES: pre-create settings.json with a custom key, then run.
#     The custom key must survive (a naive cp would overwrite it).
# ---------------------------------------------------------------------------
scenario_merge_preserves() {
    local d home rc
    d="$(mktemp -d "$WORK/merge.XXXXXX")"
    home="$d/home"
    mkdir -p "$home"

    # Seed a custom key with no baseline.  With base={}, every user key is
    # treated as contested (user != base) and is preserved by the merge policy.
    printf '{"my_custom_key":"sentinel_value"}\n' > "$home/settings.json"

    run_setup "$home"; rc=$?
    [ "$rc" -eq 0 ] || { echo "  rc=$rc"; return 1; }

    jq -e '.my_custom_key == "sentinel_value"' "$home/settings.json" \
        >/dev/null 2>&1 \
        || { echo "  custom key lost: $(jq -c . "$home/settings.json" 2>/dev/null)"; return 1; }
}

run_scenario "A: fresh run seeds settings.json, writes base, copies guard hooks" scenario_fresh
run_scenario "B: idempotent -- third run byte-identical to second"               scenario_idempotent
run_scenario "C: merge preserves a custom key from pre-existing settings.json"   scenario_merge_preserves

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
