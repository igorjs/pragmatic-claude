#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# gen-shared-settings.sh: derive the tracked, conservative settings.shared.json
# template from a live settings.json. Replaces .permissions with a canned
# permissions object, forces model:"default" and skipAutoPermissionPrompt:false,
# and drops the owner's personal keys. Product config (env, hooks, statusLine,
# worktree, plugins, ...) passes through unchanged. Merged JSON goes to stdout.
#
# Usage: gen-shared-settings.sh SRC [PERMS]
#   SRC    path to the live settings.json (required)
#   PERMS  path to the canned permissions object
#          (default: <repo>/permissions.shared.json)
#
# Exit: 0 on success (merged JSON on stdout); non-zero on any guard failure
#       (diagnostic on stderr, nothing on stdout).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die() { echo "gen-shared-settings: $1" >&2; exit "${2:-1}"; }

command -v jq >/dev/null 2>&1 || die "jq not found on PATH" 3

[[ $# -ge 1 ]] || die "usage: gen-shared-settings.sh SRC [PERMS]" 2

SRC="$1"
PERMS="${2:-${REPO_ROOT}/permissions.shared.json}"

[[ -r "$SRC" ]]   || die "source settings not readable: $SRC" 2
[[ -r "$PERMS" ]] || die "permissions file not readable: $PERMS" 2

jq empty "$SRC"   >/dev/null 2>&1 || die "source settings is not valid JSON: $SRC" 2
jq empty "$PERMS" >/dev/null 2>&1 || die "permissions file is not valid JSON: $PERMS" 2

# PERMS must be an object carrying a non-empty allow array.
jq -e 'type == "object" and (.allow | type == "array" and length > 0)' \
  "$PERMS" >/dev/null 2>&1 \
  || die "permissions file must be an object with a non-empty allow array: $PERMS" 2

jq -s '.[0] + {permissions: .[1], model: "default", skipAutoPermissionPrompt: false}
       | del(.effortLevel, .theme, .preferredNotifChannel, .prefersReducedMotion)' \
  "$SRC" "$PERMS"
