#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
#
# gh-remote.test.sh: tests for gh_remote_parse in shell/gh-remote.sh. Covers
# github.com and GitHub Enterprise Cloud (*.ghe.com) across scp/ssh/https
# remotes, .git stripping, embedded credentials/ports, and rejection of
# non-GitHub hosts (GitLab, Bitbucket, self-hosted GHE Server) and junk input.
#
# Run:  bash shell/gh-remote.test.sh
# Exit: 0 if all cases pass, non-zero otherwise.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=shell/gh-remote.sh
source "${SCRIPT_DIR}/gh-remote.sh"

PASS=0
FAIL=0
TAB=$'\t'

# accept <name> <remote-url> <expected "host<TAB>owner/repo">
accept() {
  local name="$1" url="$2" want="$3" got rc
  got="$(gh_remote_parse "$url")"; rc=$?
  if [[ $rc -eq 0 && "$got" == "$want" ]]; then
    echo "PASS: $name"; (( PASS++ )) || true
  else
    echo "FAIL: $name -> rc=$rc got='$got' want='$want'"; (( FAIL++ )) || true
  fi
}

# reject <name> <remote-url>
reject() {
  local name="$1" url="$2" got rc
  got="$(gh_remote_parse "$url")"; rc=$?
  if [[ $rc -ne 0 && -z "$got" ]]; then
    echo "PASS: $name"; (( PASS++ )) || true
  else
    echo "FAIL: $name -> rc=$rc got='$got' (expected rejection)"; (( FAIL++ )) || true
  fi
}

# github.com over each remote form
accept "github https"        "https://github.com/acme/widgets.git"         "github.com${TAB}acme/widgets"
accept "github https no-git" "https://github.com/acme/widgets"             "github.com${TAB}acme/widgets"
accept "github scp"          "git@github.com:acme/widgets.git"             "github.com${TAB}acme/widgets"
accept "github ssh"          "ssh://git@github.com/acme/widgets.git"       "github.com${TAB}acme/widgets"
accept "github https token"  "https://x-token@github.com/acme/widgets.git" "github.com${TAB}acme/widgets"

# GitHub Enterprise Cloud (<company>.ghe.com) over each remote form
accept "ghe https"           "https://acme.ghe.com/acme/widgets.git"       "acme.ghe.com${TAB}acme/widgets"
accept "ghe scp"             "git@acme.ghe.com:acme/widgets.git"           "acme.ghe.com${TAB}acme/widgets"
accept "ghe ssh"             "ssh://git@acme.ghe.com/acme/widgets.git"     "acme.ghe.com${TAB}acme/widgets"

# Non-GitHub hosts and malformed input are rejected
reject "gitlab scp"          "git@gitlab.com:acme/widgets.git"
reject "bitbucket https"     "https://bitbucket.org/acme/widgets.git"
reject "ghe-server host"     "git@github.acme.com:acme/widgets.git"
reject "lookalike host"      "https://evilghe.com/acme/widgets.git"
reject "empty"               ""
reject "not a url"           "some-garbage"
reject "owner without repo"  "https://github.com/acme"

TOTAL=$(( PASS + FAIL ))
echo ""
echo "${PASS}/${TOTAL} cases passed"

[[ $FAIL -eq 0 ]]
