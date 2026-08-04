#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# setup-local.sh: idempotent local wiring for pragmatic-engineer/playbook.
# Copies the always-on safety-guard hooks, seeds or merges settings.json from
# the shipped template, and optionally installs deps (brew) and the shell
# launcher (cc.zsh into ~/.zshrc).
#
# Self-locates its own source tree so it works when called from install.sh
# (after the file-copy loop) or directly from the /setup plugin command.
#
# Usage:  bash shell/setup-local.sh [--skip-deps] [--skip-shell] [--yes]
# Env:    CLAUDE_HOME  target directory (default: $HOME/.claude)
#
# Flags --skip-plugin is accepted and silently ignored; guard wiring and
# settings seeding always run (that is the purpose of this script).
set -euo pipefail

SELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKIP_DEPS=0
SKIP_SHELL=0
# ASSUME_YES is parsed for forward-compatibility; setup-local.sh has no
# interactive prompts of its own.
ASSUME_YES=0

if [ -t 1 ]; then
    C_B=$'\033[1;34m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
else
    C_B=""; C_Y=""; C_R=""; C_0=""
fi
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%serror:%s %s\n'   "$C_R" "$C_0" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-deps)   SKIP_DEPS=1 ;;
        --skip-shell)  SKIP_SHELL=1 ;;
        --yes|-y)      ASSUME_YES=1 ;;
        --skip-plugin) ;; # accepted, ignored -- wiring always runs
        *)             die "unknown option: $1" ;;
    esac
    shift
done

[ -n "$CLAUDE_HOME" ] || die "CLAUDE_HOME is empty"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_HOME/backups/setup-$STAMP"
backed_up=0

# ---------------------------------------------------------------------------
# 1. Copy the 3 always-on safety-guard hooks.
#    Overwriting is fine: these are product files, not user files.
#    Skip the copy if source and destination are the same physical file
#    (e.g. when SELF_ROOT == CLAUDE_HOME after install.sh ran the copy loop).
# ---------------------------------------------------------------------------
mkdir -p "$CLAUDE_HOME/hooks"
for g in rm-workspace-guard.sh bg-await-guard.sh no-dash-guard.sh; do
    src_hook="$SELF_ROOT/hooks/$g"
    dst_hook="$CLAUDE_HOME/hooks/$g"
    [ -f "$src_hook" ] || continue
    # -ef: same device + inode -> same file; self-copy would error on macOS.
    if [ "$src_hook" -ef "$dst_hook" ] 2>/dev/null; then
        continue
    fi
    cp "$src_hook" "$dst_hook"
done
log "Safety-guard hooks installed in $CLAUDE_HOME/hooks"

# ---------------------------------------------------------------------------
# 2. Seed or 3-way-merge settings.json from the shipped template.
#    The template wires the always-on guards; functional hooks live in the
#    plugin and must not be duplicated here (no double-fire).
#
#    Fresh install (no existing settings.json):
#      cp template -> settings.json; record as baseline in .settings.base.json.
#    Existing install:
#      3-way merge (baseline + template + user) preserving user customisations.
#    No template: no-op.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MERGE_TMP="$TMP/settings-merge"
mkdir -p "$MERGE_TMP"

if [ -f "$SELF_ROOT/settings.shared.json" ]; then
    if [ ! -e "$CLAUDE_HOME/settings.json" ]; then
        # Fresh install: seed settings.json and record the shipped baseline.
        cp "$SELF_ROOT/settings.shared.json" "$CLAUDE_HOME/settings.json"
        cp "$SELF_ROOT/settings.shared.json" "$CLAUDE_HOME/.settings.base.json"
        log "Seeded default settings.json from settings.shared.json"
    else
        # Existing install: 3-way merge.
        MERGE_BIN="$SELF_ROOT/shell/merge-settings.sh"
        MERGE_SKIP_TMP="$MERGE_TMP/settings-merge-skipped.json"
        if merged="$(bash "$MERGE_BIN" \
                "$CLAUDE_HOME/.settings.base.json" \
                "$SELF_ROOT/settings.shared.json" \
                "$CLAUDE_HOME/settings.json" \
                "$MERGE_TMP/newbase" \
                "$MERGE_SKIP_TMP" 2>/dev/null)"; then
            if printf '%s\n' "$merged" | cmp -s - "$CLAUDE_HOME/settings.json"; then
                # Idempotent: refresh base only; do not touch settings.json.
                mv "$MERGE_TMP/newbase" "$CLAUDE_HOME/.settings.base.json"
                log "settings.json already up to date"
            else
                # Content changed: snapshot, write, move skip file into backup.
                mkdir -p "$BACKUP"
                cp "$CLAUDE_HOME/settings.json" "$BACKUP/"
                mv "$MERGE_SKIP_TMP" "$BACKUP/settings-merge-skipped.json"
                printf '%s\n' "$merged" > "$MERGE_TMP/settings.json.new"
                mv "$MERGE_TMP/settings.json.new" "$CLAUDE_HOME/settings.json"
                mv "$MERGE_TMP/newbase" "$CLAUDE_HOME/.settings.base.json"
                backed_up=1
                _nw="$(jq 'length' "$BACKUP/settings-merge-skipped.json" 2>/dev/null)" \
                    || _nw='0'
                log "Merged settings.json (${_nw} keys withheld; see $BACKUP/settings-merge-skipped.json)"
                if [ "${_nw:-0}" -gt 0 ]; then
                    warn "Some customised keys were also updated by the new template."
                    warn "Review $BACKUP/settings-merge-skipped.json after setup."
                fi
            fi
            # Prune setup backup dirs older than the newest 5.
            find "$CLAUDE_HOME/backups" -maxdepth 1 -type d -name 'setup-*' \
                2>/dev/null | sort -r | tail -n +6 \
                | while IFS= read -r _old; do [ -n "$_old" ] && rm -rf "$_old"; done \
                || true
        else
            warn "settings.json merge failed; settings.json left unchanged."
            warn "If this persists, delete $CLAUDE_HOME/.settings.base.json to reset to additive merge."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3. Install dependencies via Homebrew (unless --skip-deps).
# ---------------------------------------------------------------------------
if [ "$SKIP_DEPS" -eq 0 ]; then
    if command -v brew >/dev/null 2>&1; then
        if [ -f "$SELF_ROOT/Brewfile" ]; then
            log "Installing dependencies (brew bundle)"
            brew bundle --file "$SELF_ROOT/Brewfile" </dev/null \
                || warn "brew bundle reported errors"
        fi
    else
        warn "Homebrew not found; skipping deps. See https://brew.sh"
        warn "When Homebrew is available: brew bundle --file $SELF_ROOT/Brewfile"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Wire the shell launcher into ~/.zshrc (unless --skip-shell).
#    Single quotes intentional: write the literal \$HOME so zsh expands it
#    at runtime, not the install-time value.
# ---------------------------------------------------------------------------
if [ "$SKIP_SHELL" -eq 0 ]; then
    ZSHRC="$HOME/.zshrc"
    if [ -f "$ZSHRC" ] && grep -qF 'shell/cc.zsh' "$ZSHRC"; then
        log "Your .zshrc already sources cc.zsh"
    else
        # shellcheck disable=SC2016
        printf '\n# playbook launchers (cc/ccd)\nsource "$HOME/.claude/shell/cc.zsh"\n' >> "$ZSHRC"
        log "Added cc.zsh source to your .zshrc"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "Setup complete."
[ "$backed_up" -eq 1 ] && log "Replaced files backed up to: $BACKUP" || true
