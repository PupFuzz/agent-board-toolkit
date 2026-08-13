#!/usr/bin/env bash
# _dependabot-ps-stub.sh — the `ps` stand-in that dependabot-reconcile-selftest.sh copies onto
# PATH, so the running-process binding (the newest write anywhere in the deployed TREE against
# the start time of the oldest process running from it) and the host-wide coverage statement can
# be driven deterministically. A real `ps` reports whatever this host happens to be running,
# which is not a test input.
#
# It prints $DR_PS_FIXTURE verbatim (an absent/empty fixture is the "no process is running"
# case, which is a real disposition and not an error), in the `pid lstart args` column shape the
# tool asks for. An invocation with any other -o spec is a FATAL rc 2: the tool parses fixed
# column positions, so a stub that answered a different shape would feed it garbage silently.
set -uo pipefail

want=""
for a in "$@"; do
    case "$a" in -eo) want="next" ;; *) [ "$want" = "next" ] && want="$a" ;; esac
done

if [ "$want" != "pid=,lstart=,args=" ]; then
    echo "ps-stub: unexpected -o spec '$want' (args: $*)" >&2
    exit 2
fi

[ -n "${DR_PS_FIXTURE:-}" ] && [ -r "$DR_PS_FIXTURE" ] && cat "$DR_PS_FIXTURE"
exit 0
