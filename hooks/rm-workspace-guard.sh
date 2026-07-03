#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
# PreToolUse(Bash) guard: block `rm` targets outside ~/Workspace/** and ~/.claude/**.
# Best-effort protection against an accidental rm, NOT a security boundary: it can't
# parse `rm` hidden in command substitution, and it only guards `rm` (not find -delete,
# unlink, or `>` truncation). A `cd` in the command makes relative targets
# unresolvable, so those are blocked conservatively.
set -u  # not -e: a parse failure must not exit non-zero and let the rm through

CMD=$(jq -r '.tool_input.command // ""' -)
[[ -z "$CMD" ]] && exit 0

WORKSPACE="$HOME/Workspace"
CLAUDE_DIR="$HOME/.claude"

is_allowed() {
  local path="${1/#\~/$HOME}"
  [[ "$path" != /* ]] && path="$(pwd)/$path"
  [[ "$path" == "$WORKSPACE" || "$path" == "$WORKSPACE/"* ]] && return 0
  [[ "$path" == "$CLAUDE_DIR" || "$path" == "$CLAUDE_DIR/"* ]] && return 0
  return 1
}

in_rm=false
saw_cd=false
outside=()
IFS=' ' read -ra tokens <<< "$CMD"

for token in "${tokens[@]}"; do
  [[ -z "$token" ]] && continue
  # A `cd` anywhere means $(pwd) no longer reflects where a relative rm resolves.
  if [[ "$token" == "cd" || "$token" == */cd ]]; then
    saw_cd=true; continue
  fi
  if [[ "$token" == "rm" || "$token" == */rm ]]; then
    in_rm=true; continue
  fi
  if [[ "$token" == ";" || "$token" == "&&" || "$token" == "||" || "$token" == "|" || "$token" == "&" ]]; then
    in_rm=false; continue
  fi
  if [[ "$in_rm" == true ]]; then
    [[ "$token" == -* ]] && continue
    if [[ "$saw_cd" == true && "$token" != /* && "$token" != '~'* ]]; then
      outside+=("$token")            # relative target after a cd: unresolvable, block
    elif ! is_allowed "$token"; then
      outside+=("$token")
    fi
  fi
done

if (( ${#outside[@]} > 0 )); then
  joined=$(IFS=', '; echo "${outside[*]}")
  jq -n --arg r "rm blocked: $joined is outside ~/Workspace/** and ~/.claude/**" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
