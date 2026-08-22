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

# ⛔ THIS HARNESS WRITES CREDENTIAL AND API CONFIG FILES, AND IT ONCE WROTE THE OPERATOR'S OWN
# (card#7245). At 00:42 on 2026-08-22 a run of it replaced the live `~/.kanban-host.env`
# wholesale, overwrote the live token file with `stub-token`, and left a stray
# `~/.kanban-e2e-board.env` behind; every board tool on the box failed — first
# `Could not resolve host: kanban.test`, then `HTTP 401 Unauthenticated` — until the operator
# restored the credential by hand. Two things made that possible and both are closed below:
#   1. the only guard was `: "${HOME:?…}"`, which fires when HOME is UNSET and is therefore
#      satisfied by the one value that matters — the operator's REAL home. `kb_stub_contained`
#      now tests the property the harness actually needs: HOME is the scratch dir THIS run
#      created. A test that forgets `_mktmp_scratch --home` gets a refusal, not a live write.
#   2. it wrote the shared `~/.kanban-host.env` and the shared default token file, when
#      `$KANBAN_HOST_ENV` — a per-invocation override the lib has always honored — lets it
#      name its OWN. The override existed; the harness did not use it. It does now, and the
#      host env it writes DECLARES `KBCARD_TOKEN_FILE`, so nothing here depends on a default.
#
# The stub's api host is a DECLARATION, not a URL to be parsed back: KB_STUB_HOST is the host
# and KB_STUB_API is built from it. That is what lets the harness set KANBAN_EXPECTED_HOST
# (which the lib's preflight requires) without a second copy of the RFC 3986 authority parser
# living in the test tree — the class of copy that has already been wrong once here.
KB_STUB_HOST="${KB_STUB_HOST:-kanban.test}"
KB_STUB_API="${KB_STUB_API:-https://$KB_STUB_HOST/api/v3}"

# kb_stub_contained — refuse (EXIT 1, not return: most selftests run without `set -e`, where a
# return would be silently discarded and the write would happen anyway) unless HOME is exactly
# the scratch dir `_mktmp_scratch --home` made. The equality is deliberate over "is under
# $TMP": the whole point is that the caller ran the documented setup, and any other HOME —
# real, inherited, or half-configured — is the state this refuses.
kb_stub_contained() {
    local who="$1"
    if [[ -z "${TMP:-}" || -z "${HOME:-}" || "$HOME" != "$TMP" ]]; then
        printf '%s: REFUSING to write board config — HOME (%s) is not the scratch dir from `_mktmp_scratch --home` (TMP=%s).\n' \
            "$who" "${HOME:-<unset>}" "${TMP:-<unset>}" >&2
        printf '%s:   → call `_mktmp_scratch --home` before sourcing/using this harness; it writes real ~/.kanban-* files and this guard is what stops it writing YOURS (card#7245).\n' \
            "$who" >&2
        exit 1
    fi
}

# kb_stub_scrub_env — drop the ambient config keys an operator shell may already carry. Board
# envs `export` their keys (examples/kanban-board.env.example), so a shell that sourced one hands
# every child a KBCARD_API / KBCARD_TOKEN_FILE / KB_BOARD_ID of its own — and kb_resolve_env
# honors an AMBIENT KBCARD_API over the host env's, so a real host could otherwise end up in the
# asserted URL. KANBAN_EXPECTED_HOST goes with them: an operator shell carrying the REAL host
# would make the lib's api-host preflight pass for a reason no test declared.
# Scrubbed here rather than per-selftest so neither can forget.
kb_stub_scrub_env() {
    unset KBCARD_API KBCARD_TOKEN_FILE KBCARD_BOARD_ENV KANBAN_HOST_ENV KANBAN_EXPECTED_HOST
    unset KB_API KB_BOARD_ID KB_TOKEN KB_TOKEN_FILE KB_BOARD_ENV KB_CURL_MAX_TIME
}

# kb_stub_board_config <name> <board-id> [extra board-env line…] — write the harness's OWN host
# env (exported as $KANBAN_HOST_ENV), its own token file, and ~/.kanban-<name>-board.env.
# Requires the scratch HOME from `_mktmp_scratch --home` and refuses without it. Call it once
# per board a test needs; a second board proves --board actually routes rather than being
# ignored. The board env stays under $HOME because that is how the lib addresses a board by
# name — which is exactly why the containment guard above is the load-bearing one.
kb_stub_board_config() {
    local name="$1" board_id="$2"; shift 2
    kb_stub_contained kb_stub_board_config
    export KANBAN_HOST_ENV="$TMP/kanban-host.env"
    export KB_STUB_TOKEN_FILE="$TMP/kb-stub.token"
    {
        printf 'export KBCARD_API="%s"\n' "$KB_STUB_API"
        printf 'export KANBAN_EXPECTED_HOST="%s"\n' "$KB_STUB_HOST"
        printf 'export KBCARD_TOKEN_FILE="%s"\n' "$KB_STUB_TOKEN_FILE"
    } > "$KANBAN_HOST_ENV"
    {
        printf 'export KB_BOARD_ID=%s\n' "$board_id"
        [[ $# -gt 0 ]] && printf '%s\n' "$@"
    } > "$HOME/.kanban-${name}-board.env"
    printf 'stub-token\n' > "$KB_STUB_TOKEN_FILE"
}

# kb_stub_install — copy the curl stand-in to $TMP/bin/curl, put it first on PATH, and start a
# fresh request log.
kb_stub_install() {
    # TMP only — this one writes nothing outside $TMP/bin, so the HOME containment guard
    # kb_stub_board_config carries would be a guard whose message names a file it never opens.
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
