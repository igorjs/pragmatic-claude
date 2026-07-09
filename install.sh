#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# Installer for igorjs/pragmatic-claude: drops the tracked config into ~/.claude
# without a git clone. Quick start:
#
#   curl -fsSL https://raw.githubusercontent.com/igorjs/pragmatic-claude/main/install.sh | bash
#
# Source of truth: the latest GitHub release by default, or PRAGMATIC_CLAUDE_REF
# (any tag/branch/sha). Falls back to the main branch when no release exists.
# Existing tracked files are backed up before being replaced; runtime state
# (sessions/, projects/, history, plugins/) is never touched.
set -euo pipefail

REPO="igorjs/pragmatic-claude"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
REF="${PRAGMATIC_CLAUDE_REF:-}"
SKIP_DEPS=0
SKIP_SHELL=0

if [ -t 1 ]; then
    C_B=$'\033[1;34m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
else
    C_B=""; C_Y=""; C_R=""; C_0=""
fi
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

print_help() {
    cat <<'EOF'
Install igorjs/pragmatic-claude into ~/.claude (no git clone).

Usage:
  curl -fsSL https://raw.githubusercontent.com/igorjs/pragmatic-claude/main/install.sh | bash
  curl -fsSL .../install.sh | bash -s -- [flags]
  ./install.sh [flags]

Env:
  PRAGMATIC_CLAUDE_REF=<tag|branch|sha>  source ref (default: latest release, else main)
  CLAUDE_HOME=<dir>                   install target (default: $HOME/.claude)

Flags:
  --ref <ref>    same as PRAGMATIC_CLAUDE_REF
  --skip-deps    skip 'brew bundle'
  --skip-shell   skip editing ~/.zshrc
  --no-setup     skip all setup steps (install files only)
  -h, --help     show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-deps)  SKIP_DEPS=1 ;;
        --skip-shell) SKIP_SHELL=1 ;;
        --no-setup)   SKIP_DEPS=1; SKIP_SHELL=1 ;;
        --ref)        shift; REF="${1:-}" ;;
        --ref=*)      REF="${1#--ref=}" ;;
        -h|--help)    print_help; exit 0 ;;
        *)            die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

[ -n "$CLAUDE_HOME" ] || die "CLAUDE_HOME is empty"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"

resolve_tarball_url() {
    if [ -n "$REF" ]; then
        printf 'https://codeload.github.com/%s/tar.gz/%s\n' "$REPO" "$REF"
        return
    fi
    local api tag
    api="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || true)"
    tag="$(printf '%s' "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    tag="${tag%%$'\n'*}"
    if [ -n "$tag" ]; then
        printf 'https://codeload.github.com/%s/tar.gz/refs/tags/%s\n' "$REPO" "$tag"
    else
        warn "no GitHub release found; falling back to the main branch"
        printf 'https://codeload.github.com/%s/tar.gz/refs/heads/main\n' "$REPO"
    fi
}

# PRAGMATIC_CLAUDE_SRC is a test seam: when set, install straight from a local
# checkout and skip the network path (resolve/curl/tar) entirely.
SRC="${PRAGMATIC_CLAUDE_SRC:-}"
if [ -n "$SRC" ]; then
    [ -d "$SRC" ] || die "PRAGMATIC_CLAUDE_SRC is not a directory: $SRC"
    log "Installing from local source $SRC"
else
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    url="$(resolve_tarball_url)"
    log "Downloading $url"
    curl -fsSL "$url" -o "$TMP/config.tar.gz" || die "download failed: $url"
    tar -xzf "$TMP/config.tar.gz" -C "$TMP" || die "could not extract archive"

    SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d -name '*pragmatic-claude*' | head -1)"
    [ -n "$SRC" ] || SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [ -d "$SRC" ] || die "could not locate extracted source directory"
fi

mkdir -p "$CLAUDE_HOME"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_HOME/backups/install-$STAMP"
backed_up=0

log "Installing config into $CLAUDE_HOME"
shopt -s dotglob nullglob
for src in "$SRC"/*; do
    name="$(basename "$src")"
    case "$name" in
        .git|.github|.DS_Store) continue ;;
        settings.json) continue ;;  # never clobber a user's live settings
    esac
    dest="$CLAUDE_HOME/$name"
    if [ -e "$dest" ]; then
        mkdir -p "$BACKUP"
        cp -R "$dest" "$BACKUP/"
        rm -rf "$dest"
        backed_up=1
    fi
    cp -R "$src" "$dest"
done
shopt -u dotglob nullglob

# Ensure TMP is always set: the network path creates it above; the local-source
# path (PRAGMATIC_CLAUDE_SRC test seam) does not. Both the merge scratch dir and
# any tarball temp dir share the same EXIT trap so there is only one cleanup.
if [ -z "${TMP:-}" ]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
fi

# Seed or merge settings.json from the shipped template.
# - Fresh install (no existing settings.json): copy template to settings.json
#   and record it as the baseline in .settings.base.json.
# - Existing install: run a 3-way merge (baseline + template + user) via the
#   merge-settings.sh that was just copied in from the installed tree.
#   Customisations are preserved; new product config is applied. Uses an atomic
#   temp-file-then-mv pattern to avoid partial writes.
# - Absent template: no-op; continue safely.
MERGE_TMP="$TMP/settings-merge"
mkdir -p "$MERGE_TMP"
if [ -f "$CLAUDE_HOME/settings.shared.json" ]; then
    if [ ! -e "$CLAUDE_HOME/settings.json" ]; then
        # Fresh install: seed settings.json and record the shipped baseline.
        cp "$CLAUDE_HOME/settings.shared.json" "$CLAUDE_HOME/settings.json"
        cp "$CLAUDE_HOME/settings.shared.json" "$CLAUDE_HOME/.settings.base.json"
        log "Seeded default settings.json from settings.shared.json"
    else
        # Existing install: 3-way merge.
        MERGE_BIN="$CLAUDE_HOME/shell/merge-settings.sh"
        MERGE_SKIP_TMP="$MERGE_TMP/settings-merge-skipped.json"
        if merged="$(bash "$MERGE_BIN" \
                "$CLAUDE_HOME/.settings.base.json" \
                "$CLAUDE_HOME/settings.shared.json" \
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
                    warn "Review $BACKUP/settings-merge-skipped.json after install."
                fi
                log "A resumed session may show config-drift; run 'cc fresh' to reload."
            fi
            # Prune install backup dirs older than the newest 5.
            find "$CLAUDE_HOME/backups" -maxdepth 1 -type d -name 'install-*' \
                2>/dev/null | sort -r | tail -n +6 \
                | while IFS= read -r _old; do [ -n "$_old" ] && rm -rf "$_old"; done \
                || true
        else
            warn "settings.json merge failed; settings.json left unchanged."
            warn "If this persists, delete $CLAUDE_HOME/.settings.base.json to reset to additive merge."
        fi
    fi
fi

# --- setup -----------------------------------------------------------------

if [ "$SKIP_DEPS" -eq 0 ]; then
    if command -v brew >/dev/null 2>&1; then
        log "Installing dependencies (brew bundle)"
        # </dev/null is required: when this script is run via `curl ... | bash`,
        # the script itself arrives on stdin. brew reads stdin and would consume
        # the rest of the script, so setup steps after this would silently never
        # run. Redirecting keeps brew off the script stream.
        brew bundle --file "$CLAUDE_HOME/Brewfile" </dev/null || warn "brew bundle reported errors"
    else
        warn "Homebrew not found; skipping deps. See https://brew.sh, then: brew bundle --file $CLAUDE_HOME/Brewfile"
    fi
fi

if [ "$SKIP_SHELL" -eq 0 ]; then
    ZSHRC="$HOME/.zshrc"
    if [ -f "$ZSHRC" ] && grep -qF 'shell/cc.zsh' "$ZSHRC"; then
        log "Your .zshrc already sources cc.zsh"
    else
        zshrc_backup=""
        if [ -f "$ZSHRC" ]; then
            cp "$ZSHRC" "$ZSHRC.bak-$STAMP"
            zshrc_backup=" (backup: $ZSHRC.bak-$STAMP)"
        fi
        # Single quotes are intentional: write the literal $HOME so zsh expands
        # it at runtime, not the install-time value.
        # shellcheck disable=SC2016
        printf '\n# pragmatic-claude launchers (cc/ccd)\nsource "$HOME/.claude/shell/cc.zsh"\n' >> "$ZSHRC"
        log "Added cc.zsh source to your .zshrc${zshrc_backup}"
    fi
fi

# --- summary ---------------------------------------------------------------

log "Done."
printf '\n'
printf 'Installed to: %s\n' "$CLAUDE_HOME"
[ "$backed_up" -eq 1 ] && printf 'Replaced files backed up to: %s\n' "$BACKUP"
printf '\nNext steps:\n'
printf '  - Install the claude CLI if needed: npm i -g @anthropic-ai/claude-code (or the native installer)\n'

# Drop into a fresh login shell so the new config is active immediately.
# Only when interactive and shell setup ran. Reconnect stdin to the terminal
# (</dev/tty) so this works under `curl ... | bash`, where stdin is the pipe.
# exec replaces this process, so nothing runs after it.
if [ "$SKIP_SHELL" -eq 0 ] && [ -t 1 ] && [ -e /dev/tty ]; then
    USER_SHELL="${SHELL:-/bin/zsh}"
    log "Reloading your shell ($USER_SHELL)"
    exec "$USER_SHELL" -l </dev/tty
fi
