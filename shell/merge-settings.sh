#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# merge-settings.sh BASE TEMPLATE USER NEWBASE_OUT [SKIP_OUT]
#
# 3-way merge for Claude Code settings.json. Merged JSON -> stdout.
# Refreshed baseline -> NEWBASE_OUT path.
#
# Merge policy (per top-level key, over UNION of template+user keys):
#   user lacks key         -> template value
#   user[k] == base[k]    -> template value (update applied; dropped if template dropped it)
#   user[k] != base[k]    -> user value (customization preserved)
#   BASE absent/invalid   -> treat as {} (additive fallback) + warn stderr
#
# NEWBASE_OUT partial base refresh (C2 fix):
#   contested (user != base) -> freeze OLD base value as sentinel (NEVER template value)
#   otherwise               -> template value
#
# Validation:
#   N2: TEMPLATE and USER must be JSON objects; non-object or parse error -> exit 1, no stdout
#   N4: BASE absent or invalid -> {} + stderr warning (never hard-fail on bad base)
#   N3: SKIP_OUT (optional 5th arg): JSON array of {key,template_had,yours} for each
#       contested key where the template had a different value than the user.
#       Writes [] when zero keys are withheld. When SKIP_OUT is omitted the
#       skip info is discarded.
set -euo pipefail

warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n'   "$*" >&2; exit 1; }

[ $# -ge 4 ] || die "usage: merge-settings.sh BASE TEMPLATE USER NEWBASE_OUT [SKIP_OUT]"

BASE="$1"
TEMPLATE="$2"
USER_FILE="$3"
NEWBASE_OUT="$4"
SKIP_OUT="${5:-}"

command -v jq >/dev/null 2>&1 || die "jq is required"

# --- Validate TEMPLATE (N2: hard fail on non-object or parse error) ---
if [ ! -f "$TEMPLATE" ]; then
    die "TEMPLATE not found: $TEMPLATE"
fi
if ! jq -e 'type == "object"' "$TEMPLATE" >/dev/null 2>&1; then
    die "TEMPLATE is not a JSON object: $TEMPLATE"
fi

# --- Validate USER (N2: hard fail on non-object or parse error) ---
if [ ! -f "$USER_FILE" ]; then
    die "USER not found: $USER_FILE"
fi
if ! jq -e 'type == "object"' "$USER_FILE" >/dev/null 2>&1; then
    die "USER is not a JSON object: $USER_FILE"
fi

# --- Load BASE (N4: soft fail -> {}, stderr warning) ---
base_json='{}'
if [ ! -f "$BASE" ]; then
    warn "BASE not found; treating as {}: $BASE"
elif ! jq -e 'type == "object"' "$BASE" >/dev/null 2>&1; then
    warn "BASE is not a valid JSON object; treating as {}: $BASE"
else
    base_json="$(jq -c '.' "$BASE")"
fi

template_json="$(jq -c '.' "$TEMPLATE")"
user_json="$(jq -c '.' "$USER_FILE")"

# --- Run the 3-way merge in a single jq pass ---
# Produces: { merged, newbase, skipped }
all="$(jq -n \
    --argjson base     "$base_json" \
    --argjson template "$template_json" \
    --argjson user     "$user_json" \
    '
    ([$template, $user] | map(keys_unsorted) | add | unique) as $keys |
    {
      merged: (
        reduce $keys[] as $k ({};
          . as $acc |
          if ($user | has($k) | not) then
            if ($template | has($k)) then $acc + {($k): $template[$k]} else $acc end
          elif $user[$k] == $base[$k] then
            if ($template | has($k)) then $acc + {($k): $template[$k]} else $acc end
          else
            $acc + {($k): $user[$k]}
          end
        )
      ),
      newbase: (
        reduce $keys[] as $k ({};
          . as $acc |
          if ($user | has($k) | not) then
            if ($template | has($k)) then $acc + {($k): $template[$k]} else $acc end
          elif $user[$k] != $base[$k] then
            if ($base | has($k)) then $acc + {($k): $base[$k]} else $acc end
          else
            if ($template | has($k)) then $acc + {($k): $template[$k]} else $acc end
          end
        )
      ),
      skipped: [
        $keys[] |
        . as $k |
        select(
          ($user | has($k)) and
          ($user[$k] != $base[$k]) and
          ($template | has($k)) and
          ($template[$k] != $user[$k])
        ) |
        { key: $k, template_had: $template[$k], yours: $user[$k] }
      ]
    }
    '
)"

merged_out="$(printf '%s' "$all" | jq '.merged')"
newbase_out="$(printf '%s' "$all" | jq '.newbase')"
skipped_out="$(printf '%s' "$all" | jq '.skipped')"

# --- Atomic writes via a temp dir ---
TMP_MERGE="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -rf "$TMP_MERGE"' EXIT INT TERM

mkdir -p "$(dirname "$NEWBASE_OUT")"
printf '%s\n' "$newbase_out" > "$TMP_MERGE/newbase.json"
mv "$TMP_MERGE/newbase.json" "$NEWBASE_OUT"

if [ -n "$SKIP_OUT" ]; then
    mkdir -p "$(dirname "$SKIP_OUT")"
    printf '%s\n' "$skipped_out" > "$TMP_MERGE/skipped.json"
    mv "$TMP_MERGE/skipped.json" "$SKIP_OUT"
fi

# Emit merged JSON to stdout
printf '%s\n' "$merged_out"
