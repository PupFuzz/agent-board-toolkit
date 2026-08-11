#!/usr/bin/env bash
# _dependabot-gh-stub.sh — the `gh` stand-in that dependabot-reconcile-selftest.sh copies onto
# PATH so `bin/dependabot-deploy-reconcile` can be exercised as a real PROCESS with no network.
#
# WHY IT IS A tests/*.sh FILE and not a heredoc — the same reason as _kb-api-stub-curl.sh: a
# stub written into a temp dir from a quoted heredoc is invisible to `shellcheck tests/*.sh`
# (ci.yml's shellcheck job), so the one piece of code that decides what every assertion sees
# would be the only unchecked code in the suite. The selftest COPIES this file to $TMP/bin/gh.
#
# ROUTING BELONGS TO THE FIXTURE, not to this file. It reads $DR_FIXTURE and answers with:
#   $DR_FIXTURE/alerts-<state>.json   for `...dependabot/alerts?state=<state>`
#   $DR_FIXTURE/alerts-nofilter.json  for the unfiltered query
# so a case chooses its population by writing files, and this stub chooses nothing.
#
# TWO FAILURE INJECTIONS, because the tool's first two gates are about the COMMAND, not the
# body, and a stub that can only succeed cannot drive them:
#   $DR_GH_RC   — exit with this status (after printing $DR_GH_STDERR to stderr).
#   $DR_GH_RAW  — print this file VERBATIM instead of routing, so a non-array or unparseable
#                 body can be fed to the JSON gates.
#
# An unrecognized invocation is a FATAL rc 2 naming what it saw, never a silent empty answer:
# a stub that quietly answers `[]` to a call it does not understand manufactures a false
# "the repository has no alerts" for every assertion downstream of it.
set -uo pipefail

if [ -n "${DR_GH_RC:-}" ]; then
    [ -n "${DR_GH_STDERR:-}" ] && printf '%s\n' "$DR_GH_STDERR" >&2
    exit "$DR_GH_RC"
fi

if [ -n "${DR_GH_RAW:-}" ]; then
    cat "$DR_GH_RAW"
    exit 0
fi

url=""
for a in "$@"; do
    case "$a" in
        repos/*/dependabot/alerts*) url="$a" ;;
    esac
done

if [ -z "$url" ]; then
    echo "gh-stub: unrecognized invocation: $*" >&2
    exit 2
fi

case "$url" in
    *\?state=*) file="alerts-${url##*\?state=}.json" ;;
    *)          file="alerts-nofilter.json" ;;
esac

if [ ! -r "${DR_FIXTURE:-}/$file" ]; then
    echo "gh-stub: no fixture ${DR_FIXTURE:-<unset>}/$file for url '$url'" >&2
    exit 2
fi
cat "${DR_FIXTURE}/$file"
