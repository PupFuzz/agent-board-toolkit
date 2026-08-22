#!/usr/bin/env bash
# _kb-api-stub-curl.sh — the `curl` stand-in that tests/_kb-api-stub.sh copies onto PATH so a
# lib-SOURCING bin can be exercised as a real PROCESS with no network.
#
# WHY IT IS A tests/*.sh FILE and not a heredoc. A stub written into a temp dir from a quoted
# heredoc is invisible to `shellcheck tests/*.sh` (ci.yml's shellcheck job), so the one piece of
# code that decides what every assertion sees would be the only unchecked code in the suite.
# kb_stub_install COPIES this file to $TMP/bin/curl; nothing sources it.
#
# WHAT IT EMULATES — only what _kb-board-lib.sh's three callers actually depend on:
#   1. The auth header arrives on STDIN (`-H @-` fed by a herestring), never on argv, because the
#      bearer token must not be world-readable via `ps` (_kb-board-lib.sh:253). It is DRAINED and
#      never inspected: a stub that read the token from argv would pass while the lib leaked it.
#   2. `-w <format>` is echoed after the body with `%{http_code}` substituted. The lib's
#      `\n__HTTP__%{http_code}` marker is therefore produced by honoring the CALLER's format
#      rather than by hardcoding the marker here — the stub cannot drift from the parser.
#   3. `-f` semantics (rc 22, body discarded, on a non-2xx). Nothing in the lib passes -f, and
#      that is deliberate — -f collapses a 403 and a 422 into one indistinguishable curl rc and
#      throws the error body away (card #4337). Emulating it means reintroducing -f REDS the
#      error-body assertions instead of silently discarding them again.
#
# An unrecognized option is a FATAL rc 2, never a silent skip: a stub that quietly misparses an
# option it has not been taught manufactures false greens for every assertion downstream of it.
#
# ROUTING BELONGS TO THE CALLER. This file chooses no response. It calls the exported bash
# function `kb_stub_route` (defined in the selftest, so it is shellchecked there too) as
#     kb_stub_route <method> <url> <body> <route_n> <call_n>
# and reads its STDOUT: the HTTP status on line 1, the response body on every line after it.
#
# A TRANSPORT failure is a route answering `!curl <rc>` on line 1 (card#7214): the stub then
# exits with THAT status having written no body, which is what real curl does when it cannot
# connect (rc 7), resolve, or finish a transfer. It is spelled as a route answer, not an
# env switch, because it is a property of one request like every other answer here. Without
# it the stub could only ever produce an HTTP STATUS, so the `curl … || <fallback>` arm that
# every caller in bin/ carries was unreachable from the suite — and a caller that treats
# "could not connect" as "the endpoint is not deployed" is a real defect the tests could not
# have seen. The rc must be a non-negative integer; anything else is the same fatal misparse
# an unhandled option is, for the same reason.
# Arguments in, one value out — neither side needs a shared global, and so neither side needs a
# static-analysis suppression for one. A responder that prints nothing (no matching arm, or no
# responder exported at all) answers HTTP 599, so an unexpected call fails loudly, not silently.
#
# EVERY request is appended to $KB_STUB_LOG as "<method>\t<url>\t<body>" BEFORE a response is
# chosen, including unrouted and -f-failed ones. That log is the witness an absence assertion
# needs: nothing in a run under test can truncate it, so "no PATCH was issued" is distinguishable
# from "the run never reached the API at all".
#
# ONE REQUEST IS ONE LINE, so newlines in the body are collapsed to spaces. That matters because
# a body is not always compact — dl-a1-register-field builds its throwaway with `jq -n` (not
# `-nc`), so it arrives pretty-printed across nine lines, and an unescaped write would turn one
# request into nine log records and silently inflate every count. The collapse is faithful for
# what this API takes: bodies are JSON, where a newline outside a string is insignificant
# whitespace and a newline INSIDE a string is already escaped as \n, so the logged line parses to
# the same value. An exact-equality assertion therefore compares against the collapsed spelling.
set -uo pipefail

# Drain the `-H @-` herestring. Guarded on a tty only so a hand-run of this file from a terminal
# cannot hang — every real caller redirects stdin.
[ -t 0 ] || cat >/dev/null

METHOD=GET
URL=""
DATA=""
WFMT=""
FAILFAST=0
while (($#)); do
    case "$1" in
        -X)                 METHOD="${2:-}"; shift ;;
        --data)             DATA="${2:-}"; shift ;;
        -w)                 WFMT="${2:-}"; shift ;;
        -H|--max-time)      shift ;;
        -f*)                FAILFAST=1 ;;
        -s|-S|-sS)          ;;
        http://*|https://*) URL="$1" ;;
        -*) echo "kb-api-stub-curl: unhandled curl option '$1' — teach the stub before using it" >&2; exit 2 ;;
        *)  echo "kb-api-stub-curl: unexpected non-option argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

: "${KB_STUB_LOG:?kb-api-stub-curl: KB_STUB_LOG is unset — call kb_stub_install first}"

# Ordinals are this request's, so they are counted BEFORE it is logged. ROUTE_N counts only
# prior requests with the SAME method and URL (the trailing tab pins the whole URL field), which
# is what lets a test give three answers to dl-a1's three identical by-ref reads.
CALL_N=$(( $(wc -l < "$KB_STUB_LOG") + 1 ))
ROUTE_N=$(( $(grep -cF -- "$(printf '%s\t%s\t' "$METHOD" "$URL")" "$KB_STUB_LOG" || true) + 1 ))
printf '%s\t%s\t%s\n' "$METHOD" "$URL" "${DATA//$'\n'/ }" >> "$KB_STUB_LOG"

ROUTED=""
UNROUTED='{"error":"kb-api-stub-curl: no route matched this request"}'
if declare -F kb_stub_route >/dev/null 2>&1; then
    ROUTED="$(kb_stub_route "$METHOD" "$URL" "$DATA" "$ROUTE_N" "$CALL_N")"
else
    # Named separately from "no arm matched": forgetting `export -f kb_stub_route` fails EVERY
    # request identically, and the two causes are otherwise indistinguishable from the assertions.
    UNROUTED='{"error":"kb-api-stub-curl: kb_stub_route is not defined here — is it exported with `export -f`?"}'
fi
if [[ "$ROUTED" == '!curl '* ]]; then
    FAILRC="${ROUTED#'!curl '}"; FAILRC="${FAILRC%%$'\n'*}"
    case "$FAILRC" in
        ''|*[!0-9]*) echo "kb-api-stub-curl: '!curl <rc>' needs a non-negative integer, got '$FAILRC'" >&2; exit 2 ;;
    esac
    echo "kb-api-stub-curl: simulated transport failure (exit $FAILRC) for $METHOD $URL" >&2
    exit "$FAILRC"
fi
if [[ "$ROUTED" == *$'\n'* ]]; then
    HTTP="${ROUTED%%$'\n'*}"
    BODY="${ROUTED#*$'\n'}"
elif [[ -n "$ROUTED" ]]; then
    HTTP="$ROUTED"
    BODY=""
else
    HTTP=599
    BODY="$UNROUTED"
fi

[[ "$FAILFAST" == 1 && "$HTTP" != 2* ]] && exit 22
printf '%s' "$BODY"
[[ -n "$WFMT" ]] && printf '%s' "${WFMT//"%{http_code}"/$HTTP}"
exit 0
