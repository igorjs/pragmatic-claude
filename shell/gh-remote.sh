#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# gh-remote.sh: parse a git remote URL into a GitHub host and owner/repo path,
# restricted to GitHub-family hosts: github.com and GitHub Enterprise Cloud
# (<company>.ghe.com). Sourced by statusline.sh; kept standalone so the parsing
# is unit-testable in isolation (shell/gh-remote.test.sh).
#
# The `gh` CLI already resolves the host from the repo remote, so this parser
# only exists to (a) decide whether a remote is GitHub at all and (b) build
# host-correct web URLs for the OSC 8 PR/branch hyperlinks.

# gh_remote_parse <remote-url>
#   On a recognised GitHub-family remote, prints "<host>\t<owner>/<repo>" (tab
#   separated) and returns 0. Otherwise prints nothing and returns 1. Callers
#   treat the empty result as "not GitHub" and skip every gh-using block.
gh_remote_parse() {
    local url="$1" host="" path=""

    if [[ "$url" =~ ^git@([^:]+):(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"
    elif [[ "$url" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]%%:*}"; path="${BASH_REMATCH[2]}"   # strip :port
    elif [[ "$url" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]##*@}"; path="${BASH_REMATCH[2]}"   # strip user@
        host="${host%%:*}"                                         # strip :port
    else
        return 1
    fi

    path="${path%.git}"

    # Only github.com and GitHub Enterprise Cloud (*.ghe.com) count as GitHub.
    # Other hosts (GitLab, Bitbucket, self-hosted GHE Server on arbitrary
    # hostnames) render as plain text with no gh calls.
    case "$host" in
        github.com|*.ghe.com) : ;;
        *) return 1 ;;
    esac

    # Require an owner/repo shape; a bare "/owner" is not a repo remote.
    [[ "$path" == */* ]] || return 1

    printf '%s\t%s\n' "$host" "$path"
}
