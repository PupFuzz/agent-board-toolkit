# shellcheck shell=bash
# _kb-api-stub.sh — harness for exercising a lib-SOURCING bin as a PROCESS against a faked
# kanban API: a scratch board config for kb_load_config to resolve, a `curl` stand-in first on
# PATH, and a request log to assert against.
#
# WHY A PROCESS. bin/dl-a0-backfill-triaged and bin/dl-a1-register-field are NOT main-guarded —
# sourcing them RUNS them — so the seam cannot be a stubbed `kb_api` shell function the way
# kbcard-field-selftest's is. The only seam left is `curl` itself, which means a real executable
# on PATH (tests/_kb-api-stub-curl.sh) rather than a shell function that a child process would
# never see.
#
# Sourced by a selftest AFTER _selftest-prelude.sh and _mktmp_scratch --home:
#     _mktmp_scratch --home
#     source "$HERE/_kb-api-stub.sh"
#     kb_stub_scrub_env
#     kb_stub_board_config dev 42
#     kb_stub_install
#     kb_stub_route() { … }; export -f kb_stub_route
#
# The route table is an EXPORTED bash function, not a mini-language interpreted here: it is then
# ordinary shellchecked bash in the selftest that owns it, and the shared code stays limited to
# the parts that are genuinely shared — the curl contract, the scratch config, and the log. It is
# called `kb_stub_route <method> <url> <body> <route_n> <call_n>` and prints the HTTP status on
# line 1 and the response body after it; see tests/_kb-api-stub-curl.sh for the full contract.
# Scenario switching is by exported variable (the stub is a fresh process per request, so it
# re-reads the environment every call); re-exporting the function is not needed.

_KB_STUB_HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# kb_stub_scrub_env — drop the ambient config keys an operator shell may already carry. Board
# envs `export` their keys (examples/kanban-board.env.example), so a shell that sourced one hands
# every child a KBCARD_API / KBCARD_TOKEN_FILE / KB_BOARD_ID of its own — and kb_resolve_env
# honors an AMBIENT KBCARD_API over the host env's, so a real host could otherwise end up in the
# asserted URL. Scrubbed here rather than per-selftest so neither can forget.
kb_stub_scrub_env() {
    unset KBCARD_API KBCARD_TOKEN_FILE KBCARD_BOARD_ENV KANBAN_HOST_ENV
    unset KB_API KB_BOARD_ID KB_TOKEN KB_TOKEN_FILE KB_BOARD_ENV KB_CURL_MAX_TIME
}

# kb_stub_board_config <name> <board-id> [extra board-env line…] — write the scratch
# ~/.kanban-host.env, ~/.kanban-<name>-board.env and the default token file. Requires the scratch
# HOME from `_mktmp_scratch --home`. Call it once per board a test needs; a second board proves
# --board actually routes rather than being ignored.
kb_stub_board_config() {
    local name="$1" board_id="$2"; shift 2
    : "${HOME:?kb_stub_board_config: HOME is unset — call _mktmp_scratch --home first}"
    printf 'export KBCARD_API="%s"\n' "${KB_STUB_API:-https://kanban.test/api/v3}" > "$HOME/.kanban-host.env"
    {
        printf 'export KB_BOARD_ID=%s\n' "$board_id"
        [[ $# -gt 0 ]] && printf '%s\n' "$@"
    } > "$HOME/.kanban-${name}-board.env"
    # The token file every resolver defaults to when neither env names one (_kb-board-lib.sh:99).
    printf 'stub-token\n' > "$HOME/.kanban-dev-token"
}

# kb_stub_install — copy the curl stand-in to $TMP/bin/curl, put it first on PATH, and start a
# fresh request log.
kb_stub_install() {
    : "${TMP:?kb_stub_install: TMP is unset — call _mktmp_scratch first}"
    mkdir -p "$TMP/bin"
    cp "$_KB_STUB_HERE/_kb-api-stub-curl.sh" "$TMP/bin/curl"
    chmod +x "$TMP/bin/curl"
    export PATH="$TMP/bin:$PATH"
    export KB_STUB_LOG="$TMP/kb-api-requests.log"
    : > "$KB_STUB_LOG"
}

# kb_stub_reset — start a fresh request log (and reset every ROUTE_N with it).
kb_stub_reset() { : > "$KB_STUB_LOG"; }

# kb_stub_lines <method> <url-substring> — the logged requests matching both, one per line.
# Matched field-wise (method EXACT, substring against the URL field only) so a body that happens
# to contain "PATCH" or a path cannot inflate a count. awk's -v processes backslash escapes, so a
# needle containing a backslash must be doubled — no URL these tools build carries one.
kb_stub_lines() {
    awk -F'\t' -v m="$1" -v n="$2" '$1 == m && index($2, n)' "$KB_STUB_LOG"
}
# kb_stub_count <method> <url-substring> — how many such requests were issued.
kb_stub_count() { kb_stub_lines "$@" | wc -l | tr -d ' '; }
# kb_stub_count_any <url-substring> — how many requests of ANY method hit a matching URL.
kb_stub_count_any() { awk -F'\t' -v n="$1" 'index($2, n)' "$KB_STUB_LOG" | wc -l | tr -d ' '; }
# kb_stub_total — how many requests were issued in total (one request is one log line).
kb_stub_total() { wc -l < "$KB_STUB_LOG" | tr -d ' '; }
# kb_stub_bodies <method> <url-substring> — their request bodies, one per line.
kb_stub_bodies() { kb_stub_lines "$@" | cut -f3-; }
