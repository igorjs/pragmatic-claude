---
description: Check plugin status, safety guards, settings, shell integration, and deps. Prints a status table with a remediation hint for each miss.
allowed-tools: Bash, Read
argument-hint: ""
model: sonnet
effort: low
---

# Doctor

Run each check below, then print a status table. For every failing item,
include a short remediation hint.

## Checks

Run all five checks. Do not stop early if one fails.

**1. Plugin enabled**

```bash
claude plugin list 2>/dev/null | grep -qi 'playbook'
```

Pass if the output contains "playbook" and the line includes "enabled".

**2. Safety guards wired**

```bash
jq '[.hooks.PreToolUse[]?.hooks[]?.command]
    | map(select(test("rm-workspace-guard|bg-await-guard|no-dash-guard")))
    | length' ~/.claude/settings.json 2>/dev/null
```

Pass if the result is 3 or more.

**3. settings.json present**

```bash
test -f ~/.claude/settings.json
```

Pass if the file exists.

**4. Shell integration present**

```bash
grep -q 'shell/cc.zsh' ~/.zshrc 2>/dev/null
```

Pass if `~/.zshrc` contains the `cc.zsh` source line.

**5. Key deps available**

```bash
command -v delta jq gh
```

Pass if all three commands are found on PATH.

## Output format

Print a table with one row per check. Use a clear pass or fail marker and a
brief label. For each failing item add a one-line remediation hint. Example
shape (use plain text, no markdown table syntax needed):

```
PASS  plugin enabled
FAIL  safety guards wired        -- run /setup to seed settings.json with the guards
PASS  settings.json present
FAIL  shell integration          -- run /setup to add shell/cc.zsh to ~/.zshrc
FAIL  deps (delta jq gh)         -- brew bundle --file ~/.claude/Brewfile
```

If all checks pass, say so in one line. If any fail, end with: "Run /setup to
fix the items above."
