#!/usr/bin/env bash
# _gh-code-search-stub.sh — the `gh` stand-in that gh-code-search-selftest.sh copies onto PATH
# so `bin/gh-code-search` can be exercised as a real PROCESS with no network.
#
# WHY IT IS A tests/*.sh FILE and not a heredoc — the same reason as _dependabot-gh-stub.sh: a
# stub written into a temp dir from a quoted heredoc is invisible to `shellcheck tests/*.sh`
# (ci.yml's shellcheck job), so the one piece of code that decides what every assertion sees
# would be the only unchecked code in the suite. The selftest COPIES this file to $TMP/bin/gh.
#
# THE FIXTURE CHOOSES, NOT THIS FILE. It answers with whatever $GCS_BODY names and exits
# $GCS_RC, so a case selects a state by writing a file rather than by teaching this stub a
# rule:
#   $GCS_BODY    file printed VERBATIM to stdout (absent ⇒ nothing on stdout).
#   $GCS_RC      exit status (default 0).
#   $GCS_STDERR  printed to stderr before exiting.
# The three are independent ON PURPOSE, because the real `gh` combines them: on a 4xx it
# prints the response BODY to stdout *and* its own diagnostic to stderr *and* exits 1, and a
# stub that could not reproduce that shape could not drive the tool's ERROR arm the way the
# live API drives it (measured: `gh api search/code -f q=user:` → body on stdout, `gh:
# ERROR_TYPE_QUERY_PARSING_FATAL … (HTTP 422)` on stderr, rc 1).
#
# IT ALSO RECORDS ITS ARGV to $GCS_ARGV (one argument per line), which is how the wire-shape
# assertions read what was actually sent — the query, the per_page, the method and the path —
# rather than trusting the tool's own echo of them.
#
# An invocation that is not an `api … search/code …` call is a FATAL rc 2 naming what it saw,
# never a silent success: a stub that quietly answers an empty envelope to a call it does not
# understand manufactures a false "no matches" for every assertion downstream of it — which is
# the very defect the tool under test exists to prevent.
set -uo pipefail

if [ -n "${GCS_ARGV:-}" ]; then
    printf '%s\n' "$@" > "$GCS_ARGV"
fi

seen_api=0
seen_path=0
for a in "$@"; do
    case "$a" in
        api)         seen_api=1 ;;
        search/code) seen_path=1 ;;
    esac
done
if [ "$seen_api" -ne 1 ] || [ "$seen_path" -ne 1 ]; then
    echo "gh-code-search-stub: unrecognized invocation: $*" >&2
    exit 2
fi

[ -n "${GCS_STDERR:-}" ] && printf '%s\n' "$GCS_STDERR" >&2
if [ -n "${GCS_BODY:-}" ]; then
    if [ ! -r "$GCS_BODY" ]; then
        echo "gh-code-search-stub: no body fixture at '$GCS_BODY'" >&2
        exit 2
    fi
    cat "$GCS_BODY"
fi
exit "${GCS_RC:-0}"
