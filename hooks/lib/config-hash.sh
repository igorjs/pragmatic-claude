# shellcheck shell=sh
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
# Shared config hash: settings.json + hook scripts (excluding tests).
# Sourceable by both bash hooks and the zsh cc modules.
config_hash() {
    {
        cat "$HOME/.claude/settings.json" 2>/dev/null
        find "$HOME/.claude/hooks" -name '*.sh' ! -name '*.test.sh' -type f -print0 2>/dev/null |
            sort -z | xargs -0 cat 2>/dev/null
    } | shasum -a 256 2>/dev/null | cut -c1-16
}
