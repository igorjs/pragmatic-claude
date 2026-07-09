#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# statusline.test.sh: unit tests for pure-helper functions in statusline.sh.
# Sources the target with stdin redirected to /dev/null so the source-guard
# prevents any side effects (no cache dir created, no stdin read, no render).
#
# Run:  bash shell/statusline.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=statusline.sh
source "$SCRIPT_DIR/../statusline.sh" </dev/null

PASS=0
FAIL=0

assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        echo "PASS: $name"
        (( PASS++ )) || true
    else
        printf 'FAIL: %s\n  got:  %q\n  want: %q\n' "$name" "$got" "$want" >&2
        (( FAIL++ )) || true
    fi
}

# ── ctx_bar ──────────────────────────────────────────────────────────────────
# Filled cells use █, empty cells use ░. Default width is 10.
# ctx_bar 50 10: filled=(50*10+50)/100=5, empty=5 → █████░░░░░
assert_eq "ctx_bar 50 10 (half fill)"  "$(ctx_bar 50 10)" '█████░░░░░'
# ctx_bar 0: filled=0, empty=10
assert_eq "ctx_bar 0 (empty bar)"      "$(ctx_bar 0)"     '░░░░░░░░░░'
# ctx_bar 100: filled=10, empty=0
assert_eq "ctx_bar 100 (full bar)"     "$(ctx_bar 100)"   '██████████'

# ── fmt_age ──────────────────────────────────────────────────────────────────
assert_eq "fmt_age 5 (seconds)"        "$(fmt_age 5)"     '5s'
assert_eq "fmt_age 90 (minutes)"       "$(fmt_age 90)"    '1m'
assert_eq "fmt_age 3660 (1h 1m)"       "$(fmt_age 3660)"  '1h1m'
assert_eq "fmt_age 7200 (exact hours)" "$(fmt_age 7200)"  '2h'

# ── fmt_ago ──────────────────────────────────────────────────────────────────
# Coarse "N ago" ladder: whole minutes < 1h, whole hours < 1d, whole days else.
# These pin the exact pre-refactor ladder outputs so the dedupe is provably
# behavior-preserving.
assert_eq "fmt_ago 0 (0m)"        "$(fmt_ago 0)"      '0m'
assert_eq "fmt_ago 1800 (30m)"    "$(fmt_ago 1800)"   '30m'
assert_eq "fmt_ago 3600 (1h)"     "$(fmt_ago 3600)"   '1h'
assert_eq "fmt_ago 7200 (2h)"     "$(fmt_ago 7200)"   '2h'
assert_eq "fmt_ago 86400 (1d)"    "$(fmt_ago 86400)"  '1d'
assert_eq "fmt_ago 172800 (2d)"   "$(fmt_ago 172800)" '2d'

# ── cache_hit_pct ─────────────────────────────────────────────────────────────
# Empty when no cache activity (total=0).
assert_eq "cache_hit_pct 0 0 (empty)"      "$(cache_hit_pct 0 0)"    ''
# (150*100)/(50+150) = 75
assert_eq "cache_hit_pct 50 150 (75 pct)"  "$(cache_hit_pct 50 150)" '75'

# ── iso_to_epoch ──────────────────────────────────────────────────────────────
# Fixed UTC date; both GNU and BSD date branches produce the same epoch.
# 2026-07-08T00:00:00Z = 1 783 468 800 (verified: 20642 days × 86400 s).
assert_eq "iso_to_epoch 2026-07-08" \
    "$(iso_to_epoch '2026-07-08T00:00:00Z')" '1783468800'

# ── cache_slug ────────────────────────────────────────────────────────────────
# Non-alphanumeric chars (/, space) become underscores.
assert_eq "cache_slug 'a/b c'" "$(cache_slug 'a/b c')" 'a_b_c'

# ── strip_ansi + visible_len ──────────────────────────────────────────────────
_ansi_str=$'\033[1;32mabc\033[0m'
assert_eq "strip_ansi removes escapes"  "$(strip_ansi "$_ansi_str")"  'abc'
assert_eq "visible_len of ANSI string"  "$(visible_len "$_ansi_str")" '3'

# ── cache_color ───────────────────────────────────────────────────────────────
# Thresholds: >=80 → GREEN, >=50 → YELLOW, <50 → RED.
# printf '%b' interprets the \033 escape in the colour vars to a real ESC byte.
_c_green=$'\033[38;2;166;227;161m'
_c_yellow=$'\033[38;2;249;226;175m'
_c_red=$'\033[38;2;243;139;168m'
assert_eq "cache_color 80 (green)"   "$(cache_color 80)" "$_c_green"
assert_eq "cache_color 60 (yellow)"  "$(cache_color 60)" "$_c_yellow"
assert_eq "cache_color 49 (red)"     "$(cache_color 49)" "$_c_red"

# ── cost_per_min ──────────────────────────────────────────────────────────────
# Empty when wall_ms <= 0; otherwise (cost * 60000) / wall_ms formatted %.4f.
assert_eq "cost_per_min 0 0 (empty)"    "$(cost_per_min 0 0)"       ''
assert_eq "cost_per_min 1.0 60000"      "$(cost_per_min 1.0 60000)" '1.0000'

# ── compact_gap ───────────────────────────────────────────────────────────────
# Empty when used < 50%; otherwise (trigger - used), clamped to 0.
# Pin CLAUDE_AUTOCOMPACT_PCT_OVERRIDE so results are deterministic regardless
# of what the calling shell exports.
assert_eq "compact_gap 30 (< 50, empty)" \
    "$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90 compact_gap 30)" ''
assert_eq "compact_gap 80 (gap=10, trigger=90)" \
    "$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90 compact_gap 80)" '10'

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
