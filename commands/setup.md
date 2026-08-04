---
description: Wire the always-on safety guards, seed or merge settings.json, add shell/cc.zsh to ~/.zshrc, and install Homebrew deps.
allowed-tools: Bash, Read
argument-hint: ""
model: sonnet
effort: low
---

# Setup

Run the local wiring script to activate the always-on safety guards and the
rest of the local config. Safe to run repeatedly; each step is idempotent.

## What it does

- Copies the three safety-guard hooks (`rm-workspace-guard.sh`,
  `bg-await-guard.sh`, `no-dash-guard.sh`) into `~/.claude/hooks/`.
- Seeds `~/.claude/settings.json` from the shipped template on a fresh
  install, or runs a 3-way merge that preserves your customisations on an
  existing install.
- Appends `source "$HOME/.claude/shell/cc.zsh"` to `~/.zshrc` if it is not
  already present, wiring the `cc` and `ccd` launchers.
- Runs `brew bundle` if Homebrew is available, to install the declared deps.

## Run

Ask the user if they want to proceed, then run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/shell/setup-local.sh"
```

Report back what was done for each item:

- Guards: were the three hook files copied (or already in place)?
- Settings: was `settings.json` freshly seeded, merged, or already up to date?
- Shell: was `cc.zsh` added to `~/.zshrc`, or was it already present?
- Deps: did `brew bundle` run, and did it succeed?

If anything looks wrong, suggest running `/doctor` to see the full status.
