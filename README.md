# Playbook

A pragmatic Claude Code toolkit: opinionated skills, slash commands, subagents,
and safety and state hooks for planning, review, memory, and guarded editing.
It ships as a Claude Code plugin so it works in any shell. An optional local
setup layer wires the always-on safety guards, seeds `settings.json`, and adds
shell launchers and a custom system prompt.

## Quick start (3 commands)

```bash
claude plugin marketplace add pragmatic-engineer/marketplace
claude plugin install playbook@pragmatic-engineer
```

Then open a Claude Code session and run:

```
/setup
```

`/setup` asks two yes/no questions (both default to yes) and wires what you
choose. Run `/doctor` afterwards to verify.

```
/doctor
```

That is the primary path. The plugin content (skills, commands, agents, hooks)
is available immediately after install. `/setup` adds the local layers on top.

## Layers

Playbook is structured in four layers. Each layer is independent; you can stop
at any level.

**Layer 1: Plugin content** (always, after `claude plugin install`)

Skills, slash commands, subagents, and the functional hooks load from the
plugin. No files are written to `~/.claude`. Works in bash, zsh, or any shell.

**Layer 2: Safety guards and settings** (always after `/setup`)

`/setup` always copies the three guard hooks (`rm-workspace-guard`,
`bg-await-guard`, `no-dash-guard`) into `~/.claude/hooks/` and seeds or merges
`~/.claude/settings.json` from the shipped template. These run regardless of
any other choice.

**Layer 3: Shell launchers** (opt-in)

`/setup` asks "Install the cc and ccd shell launchers?" (recommended yes).
Both bash and zsh are supported:

- bash: `source "$HOME/.claude/shell/cc.sh"` added to `~/.bashrc`
- zsh: `source "$HOME/.claude/shell/cc.zsh"` added to `~/.zshrc`

Note: `cc worktree` (also `cc new`) is zsh-only for now. All other subcommands
(`fresh`, `list`, `prune`) work in bash via `cc.sh`.

**Layer 4: Custom system prompt** (opt-in, recommended)

`/setup` asks "Install the custom system prompt?" (recommended yes). This
copies `prompts/SYSTEM_PROMPT.md` to `~/.claude/prompts/`. The `cc` launcher
passes it as `--system-prompt-file` on every session, enabling the
senior-engineer persona and session rules.

The system prompt is optional. The plugin content works without it.

## Requirements

| Tool | Status | Why |
|---|---|---|
| `claude` on PATH | required | Claude Code itself |
| `bash` | required | hooks and the setup script run in bash |
| zsh | required for `cc worktree` | the worktree subcommand is zsh-only; all other `cc` subcommands and `ccd` work in bash |
| `git`, `jq`, `shasum` | required | used by hooks and the install script |
| `python3` 3.9+ | required | used by two bash hooks (path resolution and the memory-graph rebuild); the hooks themselves are bash |
| `rtk` (Rust Token Killer) | required | a PreToolUse hook routes every Bash command through it to cut token use |
| `gh` | optional | statusline PR and CI status |
| `agent-browser` | optional | browser automation MCP used by `/brainstorm` for web-only tickets and attachments |

## Secondary path: full local adoption with curl

The `curl | bash` one-liner downloads the files into `~/.claude`, runs the
plugin install, and prompts for the opt-in layers. Use this if you want the
full `~/.claude` file set locally (for example, to clone and edit the config).

```bash
curl -fsSL https://raw.githubusercontent.com/pragmatic-engineer/playbook/main/install.sh | bash
```

Pass `--yes` to accept every default without prompting. Pin a version:

```bash
PLAYBOOK_REF=v0.2.1 curl -fsSL https://raw.githubusercontent.com/pragmatic-engineer/playbook/main/install.sh | bash
```

Install files only (no plugin, no local wiring):

```bash
curl -fsSL https://raw.githubusercontent.com/pragmatic-engineer/playbook/main/install.sh | bash -s -- --no-setup
```

Flags (pass after `-s --` when piping):

| Flag | Effect |
|---|---|
| `--yes`, `-y` | non-interactive: accept every step's default |
| `--skip-plugin` | don't add the marketplace or install the plugin |
| `--skip-deps` | skip `brew bundle` |
| `--aliases` | install the shell launchers without prompting |
| `--system-prompt` | install the custom system prompt without prompting (implies `--aliases`) |
| `--no-setup` | install files only: no plugin, deps, or shell edits |
| `--ref <ref>` | source ref (same as `PLAYBOOK_REF`) |

Prefer git? Clone fresh:

```bash
git clone https://github.com/pragmatic-engineer/playbook.git ~/.claude
```

Already have a `~/.claude` from Claude Code? Adopt it in place. The
`.gitignore` is an allowlist so sessions, caches, and runtime files stay
ignored:

```bash
cd ~/.claude
git init
git remote add origin https://github.com/pragmatic-engineer/playbook.git
git fetch origin
git checkout -f main
```

After cloning or adopting, run `/setup` inside a Claude Code session to wire
the local layers.

## Usage

```bash
cc                     # resume this directory's last session, or start fresh
ccd                    # same, with --dangerously-skip-permissions
cc fresh               # new session, no history
cc list                # recent sessions for this directory
cc clean               # resume with /model, /effort, /config, /output-style, /style stripped
cc raw [id]            # resume verbatim, no fork or cleanup
cc worktree <branch>   # create/enter a git worktree, then start a session there (zsh only)
cc new <branch>        # alias for cc worktree (zsh only)
```

`cc` loads the system prompt (when installed), picks a model, and prunes old
transcripts (keeps the newest 5; set `CCD_KEEP` to change, `CCD_KEEP=0`
disables).

`cc worktree` (also `ccd worktree`) creates or enters a worktree off the
project's base branch, grouped under `<repo-parent>/.worktrees/<repo>/<folder>`
(set `WORKTREE_BASE_DIR` to change the base folder). It names the folder after
the JIRA key in the branch name, copies `.env`, clones `node_modules` with a
copy-on-write copy so each branch gets an independent tree, pushes the branch
to set upstream (pass `--no-push` or set `WORKTREE_NO_PUSH=1` to skip), and
runs a daily background cleanup of merged or stale worktrees. On a rebase
conflict Claude offers to resolve it (`--ai-resolve` is always set): you get a
prompt first, and it defaults to yes. Set `WORKTREE_AI_RESOLVE_SILENT=1` to
resolve without the prompt, or `WORKTREE_AI_RESOLVE=0` to turn it off. Only
available via `cc`/`ccd` on zsh.

## Docs

Full documentation: [`docs/index.md`](docs/index.md).

- **Concepts** (`docs/concepts/`): system prompt design and the memory system.
- **Guides** (`docs/guides/`): plan-and-implement, review and PR flow, decisions and memory.
- **Authoring** (`docs/authoring/`): writing commands, skills, and hooks.
- **Internals** (`docs/internals/`): launcher, hooks, model routing, and memory injection.

## System prompt

`prompts/SYSTEM_PROMPT.md` is passed as `--system-prompt-file` on every `cc`
session (when installed via `/setup`). It sets the persona (senior principal
engineer, security specialization) and the rules every session follows: terse
output, voice rules for prose, `rtk` integration, model routing, TDD,
verification, and the memory protocol. Edit it to change how sessions behave;
changes take effect on the next fresh session.

## Commands

Slash commands live in `commands/`. See [docs/guides](docs/guides) for full usage.

- `/setup`: asks two opt-in questions (launchers, system prompt), then wires the guards, seeds settings.json, and installs what you chose. Safe to run repeatedly.
- `/doctor`: checks the four layers (plugin enabled, guards wired, launcher installed, system prompt installed) and prints a pass/info table with a remediation hint for each miss.
- `/brainstorm`: divergent discovery session; explores a raw idea, weighs approaches, and produces an approved design doc that hands off to `/scope`.
- `/scope`: interview-driven planning; saves a verified, parallel-safe plan to `.claude/plans/` for `/implement`.
- `/implement`: executes a `/scope` plan or `/adr` blueprint with subagents and TDD, committing each work unit. `--auto` opens a PR.
- `/adr`: creates an Architecture Decision Record through investigate, draft, quality-gate, finalise. Saves to `.claude/adr/`.
- `/commit-and-push`: writes a commit message from the staged diff, commits signed, optionally rebases, then pushes.
- `/create-pull-request`: opens a PR with pre-flight checks, a conventional-commit title, and the team PR template.
- `/quick-review`: single-pass PR review using the `grounding-review` discipline, posted as a pending GitHub review.
- `/deep-review`: multi-agent PR review; spawns specialist subagents in parallel, consolidates findings, posts a pending review.
- `/address-pr-comments`: walks unresolved PR comments, applies fixes or drafts replies, then pushes and posts replies.
- `/learn-project`: analyses the repo (git history, code, PRs, JIRA/Confluence) and writes distilled facts to memory. Read-only; confirms before writing.
- `/repo-audit`: read-only four-phase repository audit (discovery, findings, strategy, task plan).

## Skills

Skills live in `skills/` and load on demand. See [docs/authoring/01-commands-skills-hooks.md](docs/authoring/01-commands-skills-hooks.md).

- `grounding-review`: review discipline; severity levels, Conventional Comments, proof ladder, verification summary.
- `grounding-research`: investigation discipline; citation rules (every claim sourced to file:line), structured findings, scope boundaries.
- `engineering-standards`: PR readiness, test types, mocking rules, incremental delivery, deployment flow.
- `engineering-standards-javascript`: JS/TS companion to `engineering-standards`; covers Zod validation and Jest/Vitest mocking.
- `writing-style`: voice rules for human-facing prose; spartan, active voice, contractions, no dashes.
- `session-handoff`: decision-first handoff so the next session picks up cold without rereading the thread.

## Memory

One markdown store at `~/.claude/memory/`, local-only (git-ignored at the `.claude` level, never committed):

- Global facts sit flat in `~/.claude/memory/`, indexed by `MEMORY.md`.
- Project facts live under `~/.claude/memory/<owner>/<repo>/`, where `<owner>/<repo>` comes from the repo's git remote. Each project subfolder keeps its own `MEMORY.md`, injected at session start.

A single `graph.json` covers every fact, global and project, and rebuilds automatically whenever a fact file is saved. See [docs/concepts/02-memory-system.md](docs/concepts/02-memory-system.md).

## Layout

- `settings.json`: Claude Code settings (hooks, permissions, env, statusline, plugins).
- `shell/`: the `cc`/`ccd` launcher and its modules (session resume, config-drift detection, transcript retention) plus `worktree.zsh`. `cc.zsh` is the zsh launcher; `cc.sh` is the bash launcher.
- `hooks/`: SessionStart, PreToolUse, PostToolUse, and other hooks (model auto-detect, read/edit guards, memory reminders). The functional hooks are wired by the plugin (`hooks/hooks.json`); the always-on safety guards (`rm-workspace-guard`, `bg-await-guard`, `no-dash-guard`) are wired by your `settings.json` so they never depend on the plugin and never double-fire.
- `.claude-plugin/`: plugin manifest (`plugin.json`) and marketplace descriptor (`marketplace.json`) for the opt-in Claude Code plugin.
- `statusline.sh`: statusline (git branch, PR/CI status, token usage).
- `output-styles/`: custom output styles.

## Uninstall

```bash
bash ~/.claude/uninstall.sh
```

This removes every shipped file from `~/.claude` and strips the launcher source
lines from `~/.zshrc` and `~/.bashrc`. It backs up the rc files before editing.

**Preserved by default:** `settings.json`, `.settings.base.json`, `backups/`, and all runtime state (`sessions/`, `projects/`, `history*`, `plugins/`, `memory/`, `plans/`, `runtime/`, `cache/`, `logs/`, `todos/`, `shell-snapshots/`, `.credentials*`, `cc-state/`, `ccd-state/`).

Pass `--purge` to also remove `settings.json`, `.settings.base.json`, and `backups/`.

**Flags:**

- `--yes`: skip the confirmation prompt.
- `--force`: bypass the git-repo guard (see below).
- `--purge`: remove user config in addition to shipped files.

**Git-repo guard:** if `~/.claude` is a git working tree, the script refuses to run. Raw `rm` leaves index entries dangling; the correct path for decommissioning is `git rm -r <entries>`. Pass `--force` to bypass this guard if you know what you are doing. `--force` bypasses only the git guard; it does not skip the confirmation prompt.

## Notes

Config edits (`settings.json` or hooks) take effect on a fresh session only. After changing them, run `cc fresh` or plain `claude`. `cc` warns you when a resumed session runs on stale config. The repo tracks config files, not runtime state. The allowlist `.gitignore` keeps sessions, caches, plugin manifests, and credentials out of git.

## Settings merge

Each `install.sh` run merges the shipped template into your `settings.json` rather than overwriting it. New product config lands automatically; keys you have customised stay as you set them.

The merge tracks a baseline in `~/.claude/.settings.base.json`. On each install it compares that baseline against the new template and your live file to decide which keys to update and which to leave alone.

After each install, check `backups/install-<stamp>/settings-merge-skipped.json`. It lists every key the new template tried to change but your customisation took precedence. Entries look like `{"key":"...", "template_had":..., "yours":...}`. Review them and decide whether to adopt the template value manually.

`permissions` is a single top-level key. If you have customised it (for example, added rules to `permissions.deny`), the whole `permissions` block is treated as contested and the template's version is withheld. Your custom rules take precedence. The skip file will show the entry so you can compare and merge manually if the template shipped new deny rules you want.

If an install is interrupted after writing `settings.json` but before writing the baseline, the files are out of sync. Delete `~/.claude/.settings.base.json` to reset. The next install treats the missing baseline as an empty object and falls back to additive mode: all your keys are kept and new template keys are added.

## Security

The shipped install seed (`settings.shared.json`) carries a conservative permissions default. It drops bare `Bash` and the keychain `security` commands from auto-allow. It moves twelve interpreters (`node`, `python3`, `npx`, `npm`, `make`, `awk`, `go`, `source`, `xargs`, `sqlite3`, `psql`, `docker`) from allow to ask, so the installer gets prompted. This closes the obvious `node -e` and `python3 -c` one-liners.

It is not a sandbox. Some commands still run without a prompt: `git`, `gh`, `find -exec`, the `sed` e-command, and anything under `Bash(**/.claude/**)`. The split lowers the default prompt surface, nothing more.

Autoupdates ship disabled through `DISABLE_AUTOUPDATER` in the env block. To turn them back on, remove that variable or set it to `0`.

## License

MIT. See `LICENSE`.
