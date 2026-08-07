#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# check-agents.sh: validate every agents/*.md definition (excluding the
# _TEMPLATE.md skeleton) against the house agent contract: real frontmatter,
# the required keys, a name that matches the filename, an allowed model
# tier and effort level, a read-only tool allowlist, and the non-negotiable
# guardrail invariants every agent must carry.
#
# Run:  bash shell/check-agents.sh [AGENTS_DIR]
# Exit: 0 if every agent definition is valid, non-zero (offenders on stderr)
#       otherwise.
set -u

die() { echo "check-agents: $*" >&2; exit 1; }

AGENTS_DIR="${1:-}"
if [[ -z "$AGENTS_DIR" ]]; then
  REPO_ROOT="$(git -C . rev-parse --show-toplevel 2>/dev/null)" \
    || die "not inside a git repository and no AGENTS_DIR argument given"
  AGENTS_DIR="${REPO_ROOT}/agents"
fi
[[ -d "$AGENTS_DIR" ]] || die "agents directory not found: $AGENTS_DIR"

ALLOWED_MODELS="haiku sonnet opus"
ALLOWED_EFFORTS="low medium high xhigh max"
# Two read-only tiers, matched strictest first. "Structurally read-only"
# agents (agents/reviewer.md) hold no Bash at all. Plain "read-only" agents
# (agents/auditor.md) may hold Bash for non-mutating shell like git log.
FORBIDDEN_TOOLS_STRICT="Edit Write NotebookEdit Bash"
FORBIDDEN_TOOLS_LOOSE="Edit Write NotebookEdit"

violations=()

add_violation() { violations+=("$1"); }

# in_words <needle> <space separated haystack>: whole word membership test.
in_words() {
  local needle="$1" haystack="$2" word
  for word in $haystack; do
    [[ "$word" == "$needle" ]] && return 0
  done
  return 1
}

# trim <string>: strip leading and trailing whitespace.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# frontmatter_value <body> <key>: print the trimmed, unquoted value of the
# first "<key>: value" line in <body>. Returns non-zero if the key is absent.
# The one place frontmatter parsing lives, so no rule below repeats sed/grep.
frontmatter_value() {
  local body="$1" key="$2" line value
  line="$(printf '%s\n' "$body" | grep -m1 "^${key}:")" || return 1
  value="$(trim "${line#*:}")"
  if [[ "${#value}" -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
    value="${value:1:$(( ${#value} - 2 ))}"
  fi
  printf '%s' "$value"
}

# check_agent <file>: run every rule against one agent definition, recording
# violations instead of stopping at the first one.
check_agent() {
  local file="$1" name
  name="$(basename "$file" .md)"

  local first_line=""
  IFS= read -r first_line < "$file"
  local has_frontmatter=1 closing_line=""
  if [[ "$first_line" != "---" ]]; then
    add_violation "$file: missing opening --- frontmatter delimiter"
    has_frontmatter=0
  else
    closing_line="$(awk 'NR>1 && $0=="---"{print NR; exit}' "$file")"
    if [[ -z "$closing_line" ]]; then
      add_violation "$file: missing closing --- frontmatter delimiter"
      has_frontmatter=0
    fi
  fi

  if [[ "$has_frontmatter" -eq 1 ]]; then
    local body
    body="$(sed -n "2,$(( closing_line - 1 ))p" "$file")"

    local name_value model_value effort_value description_value tools_value

    if name_value="$(frontmatter_value "$body" name)"; then
      [[ "$name_value" == "$name" ]] \
        || add_violation "$file: name '$name_value' does not match filename '$name'"
    else
      add_violation "$file: missing required frontmatter key 'name'"
    fi

    if ! description_value="$(frontmatter_value "$body" description)"; then
      add_violation "$file: missing required frontmatter key 'description'"
    fi

    if ! tools_value="$(frontmatter_value "$body" tools)"; then
      add_violation "$file: missing required frontmatter key 'tools'"
    fi

    if model_value="$(frontmatter_value "$body" model)"; then
      in_words "$model_value" "$ALLOWED_MODELS" \
        || add_violation "$file: model '$model_value' is not one of: $ALLOWED_MODELS"
    else
      add_violation "$file: missing required frontmatter key 'model'"
    fi

    if effort_value="$(frontmatter_value "$body" effort)"; then
      in_words "$effort_value" "$ALLOWED_EFFORTS" \
        || add_violation "$file: effort '$effort_value' is not one of: $ALLOWED_EFFORTS"
    else
      add_violation "$file: missing required frontmatter key 'effort'"
    fi

    if [[ -n "${description_value:-}" && -n "${tools_value:-}" ]]; then
      local forbidden="" tier_reason=""
      if printf '%s' "$description_value" | grep -qi "structurally read-only"; then
        forbidden="$FORBIDDEN_TOOLS_STRICT"
        tier_reason="structurally read-only, tools must not include Edit, Write, NotebookEdit, or Bash"
      elif printf '%s' "$description_value" | grep -qi "read-only"; then
        forbidden="$FORBIDDEN_TOOLS_LOOSE"
        tier_reason="read-only, tools must not include Edit, Write, or NotebookEdit"
      fi
      if [[ -n "$forbidden" ]]; then
        local offending="" tok
        local old_ifs="$IFS"
        IFS=','
        # shellcheck disable=SC2086
        set -- $tools_value
        IFS="$old_ifs"
        for tok in "$@"; do
          tok="$(trim "$tok")"
          if in_words "$tok" "$forbidden"; then
            offending="${offending}${offending:+, }${tok}"
          fi
        done
        [[ -z "$offending" ]] \
          || add_violation "$file: description declares the agent $tier_reason, found: $offending"
      fi
    fi
  fi

  grep -qF '## Non-negotiable guardrails' "$file" \
    || add_violation "$file: missing '## Non-negotiable guardrails' heading"
  grep -Eqi 'no dashes|em dash|en dash' "$file" \
    || add_violation "$file: missing no-dash guardrail clause (no 'no dashes', 'em dash', or 'en dash' found)"
}

count=0
for file in "$AGENTS_DIR"/*.md; do
  [[ -e "$file" ]] || continue
  base="$(basename "$file")"
  [[ "$base" == "_TEMPLATE.md" ]] && continue
  count=$(( count + 1 ))
  check_agent "$file"
done

if [[ "${#violations[@]}" -gt 0 ]]; then
  {
    echo "check-agents: ${#violations[@]} violation(s) across agent definitions:"
    for v in "${violations[@]}"; do
      echo "  $v"
    done
  } >&2
  exit 1
fi

echo "check-agents: OK ($count agent definitions, all valid)"
