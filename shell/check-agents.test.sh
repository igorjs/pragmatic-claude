#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# check-agents.test.sh: scenarios for shell/check-agents.sh. Builds scratch
# agent fixture directories and asserts a well-formed agent passes, each
# specific contract violation fails, and _TEMPLATE.md is skipped, then
# checks the repo's own agents/ passes for real.
#
# Run:  bash shell/check-agents.test.sh
# Exit: 0 if all scenarios pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${SCRIPT_DIR}/check-agents.sh"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

PASS=0
FAIL=0

WORK="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORK}'" EXIT INT TERM

# write_valid_agent <dir> <stem>: a fixture that satisfies every rule.
write_valid_agent() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Grep, Glob
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_no_model <dir> <stem>: valid frontmatter minus the model key.
write_agent_no_model() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Grep, Glob
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_strict_write_violation <dir> <stem>: strict tier, description
# says "structurally read-only", tools carries Write. Must fail.
write_agent_strict_write_violation() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Write, Glob
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_strict_bash_violation <dir> <stem>: strict tier, description
# says "structurally read-only", tools carries Bash. Must fail: the strict
# tier allows no Bash at all, unlike the loose tier.
write_agent_strict_bash_violation() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Bash, Read, Grep
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_loose_readonly_bash <dir> <stem>: loose tier, description says
# plain "read-only" (not "structurally"), tools carries Bash only. Must
# pass: the loose tier allows Bash for non-mutating shell like git log.
write_agent_loose_readonly_bash() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: An isolated read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Bash, Read, Grep
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_loose_readonly_bash_write <dir> <stem>: same loose-tier
# description as write_agent_loose_readonly_bash, but Write is added to
# tools alongside Bash. Must fail: the loose tier still forbids Write.
write_agent_loose_readonly_bash_write() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: An isolated read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Bash, Write, Read, Grep
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_bad_model <dir> <stem>: model tier outside the allowed set.
write_agent_bad_model() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Grep, Glob
model: gpt
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_bad_effort <dir> <stem>: effort level outside the allowed set.
write_agent_bad_effort() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Grep, Glob
model: sonnet
effort: extreme
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **No dashes in prose.** No em dashes or en dashes anywhere. Use commas, colons, or separate sentences.
EOF
}

# write_agent_missing_no_dash <dir> <stem>: guardrails heading present, no
# no-dash clause anywhere in it.
write_agent_missing_no_dash() {
  local dir="$1" stem="$2"
  mkdir -p "$dir"
  cat > "$dir/${stem}.md" <<EOF
---
name: ${stem}
description: A structurally read-only fixture agent used to test check-agents.sh. Not for general-purpose work.
tools: Read, Grep, Glob
model: sonnet
effort: medium
---

You are a fixture agent used only for check-agents.sh test scenarios.

## Non-negotiable guardrails

1. **Stay in scope.** Do the work asked for and nothing more.
EOF
}

# write_broken_template <dir>: a _TEMPLATE.md that would fail every rule if
# the check did not skip it (no frontmatter, no guardrails heading).
write_broken_template() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/_TEMPLATE.md" <<'EOF'
Not a real agent. No frontmatter, no guardrails, nothing valid here at all.
EOF
}

run_scenario() {  # <expect: pass|fail> <name> <dir>
  local expect="$1" name="$2" dir="$3" rc
  bash "$CHECK" "$dir" >/dev/null 2>&1; rc=$?
  if [[ "$expect" == pass ]]; then
    if [[ $rc -eq 0 ]]; then echo "PASS: $name"; (( PASS++ )) || true
    else echo "FAIL: $name (expected exit 0, got $rc)"; (( FAIL++ )) || true; fi
  else
    if [[ $rc -ne 0 ]]; then echo "PASS: $name"; (( PASS++ )) || true
    else echo "FAIL: $name (expected non-zero, got 0)"; (( FAIL++ )) || true; fi
  fi
}

# 1: the repo's own agents/ passes.
# Arrange: no fixture, target the real repo agents directory directly.
# Act + Assert: run_scenario invokes the check and asserts exit 0.
run_scenario pass "the real agents dir passes" "${REPO_ROOT}/agents"

# 2: a valid new agent passes.
# Arrange: scratch dir with one well-formed agent fixture.
VALID="${WORK}/valid"
write_valid_agent "$VALID" "sample"
# Act + Assert
run_scenario pass "a valid new agent passes" "$VALID"

# 3: missing frontmatter key fails.
# Arrange: scratch dir with a fixture that has no model key.
NO_MODEL="${WORK}/no-model"
write_agent_no_model "$NO_MODEL" "sample"
# Act + Assert
run_scenario fail "missing frontmatter key fails (no model)" "$NO_MODEL"

# 4: strict-tier read-only violation fails (Write).
# Arrange: scratch dir, description says "structurally read-only", Write in tools.
STRICT_WRITE="${WORK}/strict-write-violation"
write_agent_strict_write_violation "$STRICT_WRITE" "sample"
# Act + Assert
run_scenario fail "strict tier read-only violation fails (Write in tools)" "$STRICT_WRITE"

# 5: strict-tier read-only violation fails (Bash).
# Arrange: scratch dir, description says "structurally read-only", Bash in tools.
STRICT_BASH="${WORK}/strict-bash-violation"
write_agent_strict_bash_violation "$STRICT_BASH" "sample"
# Act + Assert
run_scenario fail "strict tier read-only violation fails (Bash in tools)" "$STRICT_BASH"

# 6: bad model tier fails.
# Arrange: scratch dir with model: gpt.
BAD_MODEL="${WORK}/bad-model"
write_agent_bad_model "$BAD_MODEL" "sample"
# Act + Assert
run_scenario fail "bad model tier fails (gpt)" "$BAD_MODEL"

# 7: effort out of range fails.
# Arrange: scratch dir with effort: extreme.
BAD_EFFORT="${WORK}/bad-effort"
write_agent_bad_effort "$BAD_EFFORT" "sample"
# Act + Assert
run_scenario fail "effort out of range fails (extreme)" "$BAD_EFFORT"

# 8: missing no-dash guardrail fails.
# Arrange: scratch dir with a guardrails heading but no no-dash clause.
NO_DASH_MISSING="${WORK}/no-dash-missing"
write_agent_missing_no_dash "$NO_DASH_MISSING" "sample"
# Act + Assert
run_scenario fail "missing no-dash guardrail fails" "$NO_DASH_MISSING"

# 9: _TEMPLATE.md is skipped.
# Arrange: scratch dir with one valid agent plus a _TEMPLATE.md that would
# fail every rule if it were not skipped.
TEMPLATE_SKIP="${WORK}/template-skip"
write_valid_agent "$TEMPLATE_SKIP" "sample"
write_broken_template "$TEMPLATE_SKIP"
# Act + Assert
run_scenario pass "_TEMPLATE.md is skipped" "$TEMPLATE_SKIP"

# 10: loose-tier read-only agent with Bash passes.
# Arrange: scratch dir, description says plain "read-only", Bash only in tools.
LOOSE_BASH="${WORK}/loose-bash-ok"
write_agent_loose_readonly_bash "$LOOSE_BASH" "sample"
# Act + Assert
run_scenario pass "loose tier read-only agent with Bash passes" "$LOOSE_BASH"

# 11: loose-tier read-only agent with Bash and Write fails.
# Arrange: scratch dir, same loose-tier description, Write added alongside Bash.
LOOSE_BASH_WRITE="${WORK}/loose-bash-write-violation"
write_agent_loose_readonly_bash_write "$LOOSE_BASH_WRITE" "sample"
# Act + Assert
run_scenario fail "loose tier read-only agent with Bash and Write fails" "$LOOSE_BASH_WRITE"

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} scenarios passed"

[[ $FAIL -eq 0 ]]
