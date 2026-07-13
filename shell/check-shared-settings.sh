#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# check-shared-settings.sh: validate the shipped settings.shared.json template
# against the tracked permissions.shared.json and the repo layout. Confirms the
# permissions block matches, no model is pinned, the prompt defaults are set, no personal
# keys leaked in, and every hook command resolves to a file inside the repo.
#
# Run:  bash shell/check-shared-settings.sh TEMPLATE PERMISSIONS REPO_ROOT
# Exit: 0 if the template is valid, non-zero (message on stderr) otherwise.
set -u

die() { echo "check-shared-settings: $*" >&2; exit 1; }

TEMPLATE="${1:-}"
PERMISSIONS="${2:-}"
REPO_ROOT="${3:-}"

[[ -n "$TEMPLATE" && -n "$PERMISSIONS" && -n "$REPO_ROOT" ]] \
  || die "usage: check-shared-settings.sh TEMPLATE PERMISSIONS REPO_ROOT"

command -v jq >/dev/null 2>&1 || die "jq is required but was not found on PATH"

[[ -r "$TEMPLATE" ]]    || die "template not readable: $TEMPLATE"
[[ -r "$PERMISSIONS" ]] || die "permissions not readable: $PERMISSIONS"
[[ -d "$REPO_ROOT" ]]   || die "repo root is not a directory: $REPO_ROOT"

jq -e . "$TEMPLATE"    >/dev/null 2>&1 || die "template is not valid JSON: $TEMPLATE"
jq -e . "$PERMISSIONS" >/dev/null 2>&1 || die "permissions is not valid JSON: $PERMISSIONS"

# The permissions file must itself be a JSON object.
jq -e 'type == "object"' "$PERMISSIONS" >/dev/null 2>&1 \
  || die "permissions file is not a JSON object: $PERMISSIONS"

# .permissions must exist, be an object, and deep-equal the permissions file.
jq -e '.permissions | type == "object"' "$TEMPLATE" >/dev/null 2>&1 \
  || die ".permissions is missing or not an object in $TEMPLATE"

jq -e --slurpfile perms "$PERMISSIONS" '.permissions == $perms[0]' "$TEMPLATE" >/dev/null 2>&1 \
  || die ".permissions in template does not deep-equal $PERMISSIONS"

# Shipped defaults.
# The seed must NOT pin a model: "default" is not a valid model value, so the
# harness (or the user's own settings.json) chooses the model instead.
jq -e 'has("model") | not' "$TEMPLATE" >/dev/null 2>&1 \
  || die ".model must not ship in $TEMPLATE (the harness or user picks the model)"

jq -e '.skipAutoPermissionPrompt == false' "$TEMPLATE" >/dev/null 2>&1 \
  || die ".skipAutoPermissionPrompt must be false in $TEMPLATE"

# Personal keys must never ship in the public template.
for key in effortLevel theme preferredNotifChannel prefersReducedMotion; do
  if jq -e --arg k "$key" 'has($k)' "$TEMPLATE" >/dev/null 2>&1; then
    die "personal key must be absent from template: $key"
  fi
done

# Every hook command must resolve to a file inside the repo (rtk is external).
while IFS= read -r cmd; do
  [[ -n "$cmd" ]] || continue
  # Strip an optional "bash " wrapper.
  cmd="${cmd#bash }"
  # rtk is an external tool wrapper, not a repo file.
  [[ "$cmd" == rtk* ]] && continue
  # Resolve either ~/.claude/ or literal $HOME/.claude/ to a repo-relative path.
  rel="$cmd"
  rel="${rel#\~/.claude/}"
  rel="${rel#\$HOME/.claude/}"
  [[ -e "$REPO_ROOT/$rel" ]] \
    || die "hook command path not found under repo root: '$cmd' (looked for $REPO_ROOT/$rel)"
done < <(jq -r '(.hooks // {}) | to_entries[] | .value[]? | .hooks[]? | .command | select(type == "string")' "$TEMPLATE")

echo "check-shared-settings: OK ($TEMPLATE)"
