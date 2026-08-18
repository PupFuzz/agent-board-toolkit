#!/usr/bin/env bash
# _kb-jq-uri-fail-stub.sh — a `jq` stand-in that fails EXACTLY ONE call: the `@uri` encode of
# fetch_board_cards' optional search term. Every other jq invocation is handed to the real jq
# unchanged, so the process under test still resolves its config, filters and renders.
#
# WHY IT EXISTS. `fetch_board_cards` refuses at rc 5 when that encode yields nothing, because an
# empty encoding is not a narrower read — it is the whole board answered as though it were the
# match set. That arm is unreachable from any input a test can pass (a non-empty string always
# has a non-empty @uri), so without a seam it would be a branch no run could ever redden, i.e. a
# decoration. This is the seam, and it is the narrowest one that reaches the arm.
#
# WHY IT IS A tests/*.sh FILE and not a heredoc, for the same reason tests/_kb-api-stub-curl.sh
# gives: a stub written into a temp dir from a quoted heredoc is invisible to ci.yml's
# `shellcheck tests/*.sh`, which would leave the code deciding a test's verdict as the only
# unchecked code in the suite. A selftest COPIES this file onto its PATH; nothing sources it.
#
# KB_JQ_REAL must name the real jq (resolved by the caller BEFORE this file is put on PATH —
# resolving it here would find this stub). Unset is a fatal rc 2, never a silent passthrough.
set -uo pipefail
: "${KB_JQ_REAL:?_kb-jq-uri-fail-stub: KB_JQ_REAL is unset — resolve the real jq before installing the stub}"
for _a in "$@"; do
    case "$_a" in
        *@uri*) echo "jq-uri-fail-stub: refusing the @uri encode (deliberate)" >&2; exit 5 ;;
    esac
done
exec "$KB_JQ_REAL" "$@"
