#!/usr/bin/env bash
# _run-coverage-gh-stub.sh — the `gh` stand-in that run-coverage-check-selftest.sh copies onto
# PATH so `bin/run-coverage-check` can be exercised as a real PROCESS with no network.
#
# WHY IT IS A tests/*.sh FILE and not a heredoc — the same reason as `_gh-code-search-stub.sh`
# and `_dependabot-gh-stub.sh`: a stub written into a temp dir from a quoted heredoc is
# invisible to `shellcheck tests/*.sh` (ci.yml's shellcheck job), so the one piece of code that
# decides what every assertion sees would be the only unchecked code in the suite. The selftest
# COPIES this file to $TMP/bin/gh.
#
# THE FIXTURE CHOOSES, NOT THIS FILE. Every answer is a file under $RCC_FIX, so a case selects
# a state by writing a directory rather than by teaching this stub a rule:
#     $RCC_FIX/pr.json         repos/O/N/pulls/<n>
#     $RCC_FIX/files.json      repos/O/N/pulls/<n>/files
#     $RCC_FIX/runs.json       repos/O/N/actions/runs?head_sha=…
#     $RCC_FIX/states.json     repos/O/N/actions/workflows
#     $RCC_FIX/workflows.json  repos/O/N/contents/.github/workflows?ref=…
#     $RCC_FIX/wf/<name>       repos/O/N/contents/.github/workflows/<name>?ref=…  (raw)
#     $RCC_FAIL                any endpoint CONTAINING this substring exits 1 with nothing on
#                              stdout — how the "I could not look" arms are driven.
#     $RCC_ARGV                every invocation's argv appended here, one arg per line, so the
#                              wire shape (the FULL 40-hex head_sha in particular) is asserted
#                              from what was actually sent rather than from the tool's echo.
#
# IT APPLIES `--jq` WITH REAL jq. The tool under test reads every endpoint through `--jq`, so a
# stub that ignored the filter would hand back a whole envelope where the tool expects one
# field, and every assertion downstream would be measuring the stub. Same for the raw
# `Accept: application/vnd.github.raw` read of a workflow file: no filter, body verbatim.
#
# AN INVOCATION THIS FILE DOES NOT RECOGNISE IS A FATAL rc 2 NAMING WHAT IT SAW, never a silent
# empty success — a stub that answers "" to a call it does not understand manufactures exactly
# the false negative the tool under test exists to prevent.
set -uo pipefail

if [ -n "${RCC_ARGV:-}" ]; then printf '%s\n' "$@" >> "$RCC_ARGV"; fi

seen_api=0; endpoint=""; filter=""; want_filter=0
for a in "$@"; do
    if [ "$want_filter" -eq 1 ]; then filter="$a"; want_filter=0; continue; fi
    case "$a" in
        api)          seen_api=1 ;;
        --jq)         want_filter=1 ;;
        --paginate|-H) ;;
        -*)           ;;
        *)            [ -z "$endpoint" ] && [ "$seen_api" -eq 1 ] && endpoint="$a" ;;
    esac
done

if [ "$seen_api" -ne 1 ] || [ -z "$endpoint" ]; then
    echo "run-coverage-gh-stub: unrecognized invocation: $*" >&2
    exit 2
fi

if [ -n "${RCC_FAIL:-}" ]; then
    case "$endpoint" in *"$RCC_FAIL"*) echo "run-coverage-gh-stub: forced failure on $endpoint" >&2; exit 1 ;; esac
fi

FIX="${RCC_FIX:?run-coverage-gh-stub: RCC_FIX is unset}"
body=""
case "$endpoint" in
    */actions/workflows)             body="$FIX/states.json" ;;
    */actions/runs\?*)               body="$FIX/runs.json" ;;
    */contents/.github/workflows\?*) body="$FIX/workflows.json" ;;
    */contents/.github/workflows/*)  name="${endpoint#*/contents/.github/workflows/}"; body="$FIX/wf/${name%%\?*}" ;;
    */pulls/*/files)                 body="$FIX/files.json" ;;
    */pulls/*)                       body="$FIX/pr.json" ;;
    *) echo "run-coverage-gh-stub: no fixture rule for endpoint '$endpoint'" >&2; exit 2 ;;
esac

if [ ! -r "$body" ]; then
    echo "run-coverage-gh-stub: no fixture at '$body' for endpoint '$endpoint'" >&2
    exit 2
fi

if [ -n "$filter" ]; then jq -r "$filter" < "$body"; else cat "$body"; fi
