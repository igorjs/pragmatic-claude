#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Igor Santos
# SPDX-License-Identifier: MIT
# PreToolUse(Bash) guard: block posting text that contains an em or en dash.
#
# Em and en dashes are banned in anything posted for humans (PR titles/bodies,
# review/issue comments, commit and tag messages). The rule lives in the system
# prompt and writing-style, but forked delivery agents keep leaking dashes into
# GitHub. This is the hard chokepoint: it inspects the actual gh/git command
# about to run, and any body/message file it references, and DENIES if a dash is
# present, forcing a rewrite before anything reaches GitHub or git history.
#
# Scoped to posting commands only (gh pr/issue/release create|edit|comment|
# review, gh api review/comment/issue writes, git commit, git tag); every other
# Bash call passes untouched. Matches the dash family U+2012..U+2015 (figure,
# en, em, horizontal bar). Disable with NO_DASH_GUARD=0.
# shellcheck source=hooks/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

[[ "${NO_DASH_GUARD:-1}" == "0" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0   # fail-open if python3 is absent

CMD="$(hi_field '.tool_input.command')"
[[ -z "$CMD" ]] && exit 0

# Gate: only guard commands that post prose to GitHub or git.
is_posting() {
  printf '%s' "$1" | grep -qE '(^|[;&|(]|[[:space:]])gh[[:space:]]+(pr|issue|release)[[:space:]]+(create|edit|comment|review)([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -qE '(^|[;&|(]|[[:space:]])gh[[:space:]]+api\b.*(reviews|comments|issues|pulls)' && return 0
  printf '%s' "$1" | grep -qE '(^|[;&|(]|[[:space:]])git[[:space:]]+(commit|tag)\b' && return 0
  return 1
}
is_posting "$CMD" || exit 0

# Collect body/message files the command references, so file-based bodies
# (--body-file, --input, git commit -F/--file) get scanned too.
files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && files+=("$f")
done < <(printf '%s' "$CMD" | grep -oE -- '(--body-file|--input|--file|-F)[= ]+[^ ]+' \
           | sed -E 's/^(--body-file|--input|--file|-F)[= ]+//; s/^"//; s/"$//')

# Reliable Unicode check (bash/BSD-grep can't match multibyte classes portably).
# Detection runs in python on the RAW hook payload, passed byte-exact through the
# environment via os.environb, and NOT on jq's extracted string: some jq builds
# under a C/POSIX CI locale do not emit multibyte UTF-8 cleanly, dropping the dash
# and failing the guard open. python's json parser is locale-independent, so we
# re-extract .tool_input.command here. jq/$CMD above stay for ASCII-only work
# (the posting gate and file collection), which the dash bytes never affect.
# Dash code points are written as escapes so this file stays ASCII:
# U+2012 figure, U+2013 en, U+2014 em, U+2015 horizontal bar.
found="$(HI_JSON="$HOOK_INPUT" python3 - "${files[@]}" <<'PY'
import os, sys, json
DASHES = {'\u2012', '\u2013', '\u2014', '\u2015'}
if hasattr(os, 'environb'):
    raw = os.environb.get(b'HI_JSON', b'')
else:
    raw = os.environ.get('HI_JSON', '').encode('utf-8', 'surrogateescape')
text = raw.decode('utf-8', 'ignore')
try:
    cmd = (json.loads(text).get('tool_input') or {}).get('command') or ''
except Exception:
    cmd = text  # unparseable payload: scan the whole thing rather than miss a dash
if any(c in DASHES for c in cmd):
    print('the command text'); sys.exit(0)
for p in sys.argv[1:]:
    try:
        with open(os.path.expanduser(p), 'rb') as fh:
            if any(c in DASHES for c in fh.read().decode('utf-8', 'ignore')):
                print('the file ' + p); sys.exit(0)
    except OSError:
        pass
PY
)"

if [[ -n "$found" ]]; then
  emit_pre_deny "Blocked: this post contains an em or en dash in $found. Em and en dashes (and their lookalikes) are banned in anything posted: PR titles and bodies, review and issue comments, and commit and tag messages. Rewrite using commas, colons, parentheses, or separate sentences, then run the command again."
fi
exit 0
