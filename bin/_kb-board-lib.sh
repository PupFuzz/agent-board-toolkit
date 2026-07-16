# shellcheck shell=bash
# _kb-board-lib.sh — shared helpers for the agent-board-toolkit's OWN scripts.
#
# CO-VENDORED, not toolkit-only. Every lib-sourcing bin (kbcard, next-dl,
# board-snapshot, board-card-start, adopt-to-dl, dl-a0-backfill-triaged,
# dl-a1-register-field) `source`s this as a sibling, so a vendor-by-copy consumer
# MUST copy it too. Cited by line, not by section number — ADOPTION.md has no
# numbered sections and its "§8" means the Task-tracking standard's §8:
#   ADOPTION.md:13 ("Where this fits") — a PM project may vendor these tools; the
#     lib-sourcing bins require _kb-board-lib.sh copied beside them.
#   docs/INSTALL.md:141 (§6b) — same requirement, with the failure mode.
#   bin/agent-board-toolkit-drift-check:39 — MISSING-LIB probe flags a lib-sourcing
#     bin vendored without the lib.
#   docs/CHANGELOG.md:11 (v0.15.0) — "Consumers who vendor: re-vendor
#     `promote-released-cards` (#110, diagnostic-only) and `_kb-board-lib.sh`
#     (#103/#106)." (No "[vendor]" tag on it: the only two in that file are
#     v0.14.0's, both for promote-released-cards. v0.11.2/#74 established the
#     co-vendoring requirement itself.)
# (promote-released-cards is the standalone exception: it is vendored and must
# never source this.) This header claimed the opposite until 2026-07-15 — treat any
# change here as having consumer blast radius, because it does.
#
# It is sourced, never executed. It collapses the config-resolution, kanban-API curl
# wrapper, whole-board pagination, and DL-canonicalization logic that was
# copy-pasted across kbcard / next-dl / dl-a0-backfill-triaged /
# dl-a1-register-field / board-snapshot / board-card-start into one definition.
#
# Source it from a sibling toolkit script with:
#   source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/_kb-board-lib.sh"
#
# Conventions honored:
#   - API base ($KBCARD_API) is board-INDEPENDENT: host-level only
#     (~/.kanban-host.env, override $KANBAN_HOST_ENV). A board env that sets it is
#     refused, not honored — see kb_resolve_env.
#   - Board env is ~/.kanban-<name>-board.env; kanban|dev (and "no --board") map
#     to the kanban-dev board.
#   - Token file is $KBCARD_TOKEN_FILE (resolvable from inside a config file) or
#     ~/.kanban-dev-token.

if [[ -n "${_KB_BOARD_LIB_LOADED:-}" ]]; then return 0; fi
_KB_BOARD_LIB_LOADED=1

# Message prefix; a script may set KB_PROG, else its own basename is used.
_kb_prog() { printf '%s' "${KB_PROG:-${0##*/}}"; }

# --- config resolution ------------------------------------------------------
#
# ONE token-file precedence, uniform across every resolver below:
#     a BOARD env's KBCARD_TOKEN_FILE > the HOST env's > an ambient one > ~/.kanban-dev-token
# It falls out of SOURCE ORDER (host first, board second) rather than a ladder of
# explicit tests. KBCARD_API is the mirror image — board-independent, host env only.

# kb_resolve_env <board_env_path>: source the host env then the board env, and
# publish KB_API / KB_BOARD_ID / KB_TOKEN_FILE / KB_BOARD_ENV. Does NOT read the
# token content and does NOT require KB_BOARD_ID — the caller decides those. Quiet
# (return-code only) apart from the rc-4 refusal, so a fail-soft caller can craft its
# own message. Returns:
#   0 ok   2 env unreadable   3 KBCARD_API unset   4 board env sets KBCARD_API
#   5 token file unreadable
kb_resolve_env() {
    local board_env="$1"
    [[ -r "$board_env" ]] || return 2
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    # Snapshot the AMBIENT values, then clear them so the two sources below reveal only what
    # THEY set. Both are restored before every return: sourcing mutates the caller's shell, so
    # without this a second kb_resolve_env call in one shell would read the FIRST board's
    # values as its ambient tier and hand board B board A's token. Clearing without snapshotting
    # would be worse than the leak — it would silently delete the documented ambient tier.
    local amb_api="${KBCARD_API:-}" amb_tok="${KBCARD_TOKEN_FILE:-}"
    unset KBCARD_TOKEN_FILE
    # HOST first, BOARD second. This restores the pre-v0.8.2 order (v0.8.1:kbcard:440,
    # "so a config-file KBCARD_TOKEN_FILE is honored"): the board env is sourced LAST,
    # so its KBCARD_TOKEN_FILE wins — which is the whole point of a per-board token.
    # The v0.8.2 lib extraction collapsed six divergent copies onto the two that had
    # the order backwards, silently regressing it (#4325).
    # Sourcing the host env is NOT gated on KBCARD_API: that gate conflated "is the API
    # already known" with "should the host's other vars load", so a stray ambient
    # KBCARD_API also dropped the host's KBCARD_TOKEN_FILE. Precedence is preserved
    # explicitly instead — an ambient API still beats the host's.
    # shellcheck disable=SC1090
    [[ -r "$host_env" ]] && source "$host_env"
    local eff_api="${amb_api:-${KBCARD_API:-}}"
    unset KBCARD_API   # so the board source below reveals a BOARD-set value
    # shellcheck disable=SC1090
    source "$board_env"
    local board_api="${KBCARD_API:-}" cfg_tok="${KBCARD_TOKEN_FILE:-}"   # cfg_tok: board's, else host's
    # Restore both before any return — never leave a caller's env mangled.
    export KBCARD_API="$eff_api"
    KBCARD_TOKEN_FILE="$amb_tok"
    if [[ -n "$board_api" ]]; then
        # Refuse LOUD rather than ignore: the API base is board-independent, so a board
        # env setting it means the operator believes something false about their config.
        echo "$(_kb_prog): KBCARD_API is board-independent and is not read from a board env — remove it from $board_env and set it once in ~/.kanban-host.env (docs/INSTALL.md §3)" >&2
        return 4
    fi
    KB_API="$eff_api"
    [[ -n "$KB_API" ]] || return 3
    KB_BOARD_ID="${KB_BOARD_ID:-}"
    KB_TOKEN_FILE="${cfg_tok:-${amb_tok:-$HOME/.kanban-dev-token}}"   # board > host > ambient > default
    KB_BOARD_ENV="$board_env"
    [[ -r "$KB_TOKEN_FILE" ]] || return 5
    return 0
}

# kb_load_config [board_name]: public config entry for the name-driven scripts
# (kbcard, dl-a0, dl-a1). Maps the --board NAME to its board env, resolves
# api/board/token, and reads the token into KB_TOKEN. An empty NAME means "no
# --board given" and honors $KBCARD_BOARD_ENV (back-compat); kanban|dev resolves
# the kanban-dev board; any other name → ~/.kanban-<name>-board.env. On failure
# prints the cause and returns 2 (KB_BOARD_ID is published but not required).
kb_load_config() {
    local name="${1:-}"
    local board_env
    case "$name" in
        "")         board_env="${KBCARD_BOARD_ENV:-$HOME/.kanban-dev-board.env}" ;;
        kanban|dev) board_env="$HOME/.kanban-dev-board.env" ;;
        *)          board_env="$HOME/.kanban-${name}-board.env" ;;
    esac
    local rc
    kb_resolve_env "$board_env"; rc=$?
    case "$rc" in
        0) ;;
        2) echo "$(_kb_prog): board env file not readable: $board_env" >&2; return 2 ;;
        3) echo "$(_kb_prog): KBCARD_API not set — create ~/.kanban-host.env (see agent-board-toolkit docs/INSTALL.md)" >&2; return 2 ;;
        4) return 2 ;;   # kb_resolve_env already named the file and the fix
        5) echo "$(_kb_prog): token file not readable: $KB_TOKEN_FILE" >&2; return 2 ;;
        *) echo "$(_kb_prog): config error ($rc) for $board_env" >&2; return 2 ;;
    esac
    KB_TOKEN="$(cat "$KB_TOKEN_FILE")"
    return 0
}

# kb_load_host_env: the lighter resolver for scripts whose board id comes from
# somewhere other than a --board name (board-snapshot iterates every board env;
# board-card-start reads the repo's config). Sources ONLY the host env and publishes
# KB_API (may be empty) + KB_HOST_TOKEN_FILE — the host-level token default that the
# caller layers a per-board override over. Reads NO token, so it CANNOT fail and has
# no return-code contract; the caller reads its token with kb_read_token once it knows
# which board it wants.
#
# It replaced kb_load_host_token's gated/unconditional mode flag: the two modes only
# ever differed because the gate conflated "source the host env" with "let the host's
# KBCARD_API win". Separating those makes one behavior serve both callers — and fixes
# the gated bug where a stray ambient KBCARD_API skipped the host env entirely, silently
# dropping the host's KBCARD_TOKEN_FILE (board-snapshot was the only gated caller, and
# so the only tool affected).
kb_load_host_env() {
    local amb_api="${KBCARD_API:-}"
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    # shellcheck disable=SC1090
    [[ -r "$host_env" ]] && source "$host_env"
    KB_API="${amb_api:-${KBCARD_API:-}}"   # an ambient API still beats the host's
    KB_HOST_TOKEN_FILE="${KBCARD_TOKEN_FILE:-}"
    return 0
}

# kb_board_env_for <board_id>: the ~/.kanban-*-board.env whose KB_BOARD_ID is
# <board_id>, on stdout; returns 1 when none matches. Each candidate is sourced in a
# SUBSHELL: a board env must never leak vars into the caller — KANBAN_EXPECTED_HOST
# and KBCARD_TOKEN_FILE are read by the caller's own token guards, and a file being
# inspected must not be able to move the guard that bounds it.
kb_board_env_for() {
    local want="$1" match="" n=0 envf
    for envf in "$HOME"/.kanban-*-board.env; do
        [[ -r "$envf" ]] || continue
        # unset KB_BOARD_ID first: a value inherited from the caller would let an env
        # that sets no KB_BOARD_ID at all false-match every lookup. 2>/dev/null so a
        # board env missing the key stays quiet here rather than emitting raw noise.
        # shellcheck disable=SC1090
        if ( unset KB_BOARD_ID; . "$envf" 2>/dev/null; [ "${KB_BOARD_ID:-}" = "$want" ] ); then
            match="$envf"; n=$((n+1))
        fi
    done
    # Which duplicate wins is arbitrary either way; that it is SILENT is the defect.
    [[ "$n" -gt 1 ]] && echo "$(_kb_prog): ⚠ $n board envs set KB_BOARD_ID=$want — using $match; remove the stale one" >&2
    [[ -n "$match" ]] || return 1
    printf '%s' "$match"
}

# kb_board_env_get <board_env_path> <VAR>...: the value THIS board env gives each named
# var, one per line, in the order asked; empty for one it does not set. Takes the env PATH
# rather than a board id so a caller needing several things from one env (board-card-start
# wants the token AND the stage ids) resolves it ONCE via kb_board_env_for — two matchers
# are free to disagree about which file wins on a duplicate KB_BOARD_ID.
#
# Every requested var is UNSET before the source. This is load-bearing, not hygiene: board
# envs `export` their keys (see examples/kanban-board.env.example), so in an operator shell
# that sourced one board's env, that board's values are already in the environment of every
# tool. Without the unset, a board env that omits an OPTIONAL key (KB_STAGE_HELD, or its
# own KBCARD_TOKEN_FILE) silently inherits the *other* board's value and reports it as its
# own — the same false-read kb_board_env_for's `unset KB_BOARD_ID` prevents.
#
# NEWLINE-delimited, one value per line — never a space-separated tuple, where an empty
# optional field silently SHIFTS every later value left. The trailing '.' sentinel exists
# only so a caller's `$(…)` cannot strip a trailing empty value; it is never read.
kb_board_env_get() {
    local envf="$1"; shift
    (
        local v
        for v in "$@"; do unset "$v"; done
        # shellcheck disable=SC1090
        . "$envf" 2>/dev/null
        for v in "$@"; do printf '%s\n' "${!v:-}"; done
        printf '.\n'
    )
}

# kb_read_token <token_file>: read the bearer token into KB_TOKEN (+ KB_TOKEN_FILE).
# Returns 1 rather than exiting when the file is unreadable — every caller is fail-soft
# and words its own message.
kb_read_token() {
    [[ -r "$1" ]] || return 1
    KB_TOKEN="$(cat "$1")"
    KB_TOKEN_FILE="$1"
    return 0
}

# --- kanban API wrappers ----------------------------------------------------
# Both wrappers use globals KB_API + KB_TOKEN and set KB_HTTP to the status of
# the last call. -sS (not -f) so a 4xx/5xx body is captured and the status is
# inspectable. 2>&1 folds curl's own error text into the captured output so a
# transport failure is logged/visible.
KB_HTTP=""

# kb_auth_header <token>: emit the Authorization header line (no trailing newline)
# for feeding to curl OUT-OF-BAND via a stdin herestring — `curl -H @- … <<<"$(kb_auth_header
# "$tok")"`. The bearer token must never be an argv token: curl's argv is world-readable via
# `ps aux` / /proc/<pid>/cmdline on a multi-user host, so a `-H "Authorization: Bearer $tok"`
# would leak it. The herestring keeps the token off argv AND (unlike a `-H @<(…)` process
# substitution) redirects a regular temp file onto fd 0 rather than a /dev/fd named pipe, so it
# also works on native mingw64/Git-Bash curl where the process-sub fd can't be opened (#34).
kb_auth_header() { printf 'Authorization: Bearer %s' "$1"; }

# kb_require_https_host <api_base>: fail-closed guard for a CONFIG-supplied API base
# (the .release-pr.json .promote.api_base, which a PR can edit). Asserts the base is
# https:// AND its host is the expected host or a subdomain of it — so a malicious
# api_base pointed at an attacker host cannot exfiltrate the bearer token (#3570). The
# expected host is $KANBAN_EXPECTED_HOST — REQUIRED, no baked default: this toolkit is
# vendored by operators on their own kanban hosts, so there is no host to safely assume.
# If it is unset/empty the guard fails CLOSED (returns 1) and the caller MUST NOT send the
# token. Host is parsed per RFC 3986 — the authority ends at the FIRST of '/', '?' or '#',
# then userinfo before the last '@' is stripped, then :port — so none of
# `https://good.host@evil/` (→ evil), `https://good.host.evil/`, or the delimiter splits
# below slip through. Prints a diagnostic and returns 1 on violation.
# (promote-released-cards carries an inline mirror of this — it is vendored standalone
# and must not source this lib; keep the two in sync, INCLUDING this required-var check.)
# The parser MUST agree with curl about where the authority ends. It once terminated the
# authority at '/' ALONE, so `https://evil.example#@good.host` left the fragment in the
# string, the userinfo strip took everything after the LAST '@', and the guard read the
# host as `good.host` and ACCEPTED — while curl discarded the fragment and sent the bearer
# token to evil.example. A '?' did the same via the query. Any future edit here must keep
# the hostile-URL matrix in tests/kb-board-lib-selftest.sh green: a guard that parses a URL
# differently from the client that fetches it is an exfiltration primitive, not a guard.
kb_require_https_host() {
    local api="$1"
    local expect="${KANBAN_EXPECTED_HOST:-}"
    if [[ -z "$expect" ]]; then
        echo "$(_kb_prog): KANBAN_EXPECTED_HOST must be set to the expected api host before sending the writeback token; refusing to send" >&2
        return 1
    fi
    case "$api" in
        https://*) ;;
        *) echo "$(_kb_prog): refusing to send token — api_base is not https:// ($api)" >&2; return 1 ;;
    esac
    local host="${api#https://}"
    host="${host%%[/?#]*}"   # authority ends at the FIRST of / ? # (RFC 3986) — not '/' alone
    host="${host##*@}"       # strip userinfo — host is after the last '@' (RFC 3986)
    host="${host%%:*}"       # strip :port
    if [[ -n "$host" && ( "$host" == "$expect" || "$host" == *".$expect" ) ]]; then
        return 0
    fi
    echo "$(_kb_prog): refusing to send token — api_base host '$host' is not '$expect' (or a subdomain of it); KANBAN_EXPECTED_HOST is the expected host" >&2
    return 1
}

# kb_api <method> <path> [body]: fail-closed. Prints the response body on a 2xx
# and returns 0; on a non-2xx or transport failure prints a diagnostic to stderr
# and returns 1 (no body on stdout). Knobs (set by the caller):
#   KB_LOG_FILE   append a failure line to this file (kbcard's failure log).
#   KB_API_ERRBODY=1  also echo the error response body to stderr (kbcard).
#   KB_API_QUIET=1    suppress the non-2xx stderr line (dl-a1, which lets its
#                     callers print their own FATAL message); transport failures
#                     are still reported.
#   KB_CURL_MAX_TIME  cap EACH request at N seconds (curl --max-time). Unset = no
#                     cap, so every existing caller is byte-for-byte unaffected
#                     (nothing in this repo sets it but board-snapshot, and it is
#                     never exported).
#                     This is the SAME knob fetch_board_cards honors, and it must
#                     stay that way: a caller has no way to tell which lib function
#                     it reached. When only one of the two honored it, a bounded
#                     paginated read sat beside an unbounded single read under one
#                     knob that looked global — the cap silently did not apply, and
#                     the hang it exists to prevent came back via the sibling.
#                     ⚠ It caps WRITES too, and the parity argument does NOT carry
#                     there: a timed-out POST/PATCH is AMBIGUOUS (the server may
#                     have committed it) yet kb_api returns 1, so a non-idempotent
#                     retry can duplicate a card or burn a DL number. Set it around
#                     a read; do NOT export it process-wide over the bins that WRITE
#                     through this lib — enumerated, not recalled:
#                       kbcard                 POST + PATCH
#                       dl-a0-backfill-triaged PATCH
#                       dl-a1-register-field   POST + PATCH, and the sole
#                                              kb_api_status caller
#                     (next-dl and adopt-to-dl are not themselves on that list:
#                     next-dl's dl-sequence claim is a raw curl outside this lib, so
#                     the knob never reaches it. adopt-to-dl stamps via a `kbcard`
#                     SUBPROCESS, so an EXPORTED cap DOES reach that write — through
#                     kbcard above, which is why exporting is the thing warned
#                     against. It does not burn a DL there: adopt-to-dl surfaces the
#                     minted DL BEFORE the write for exactly this reason, and the
#                     documented retry `--dl N` re-stamps idempotently. What you get
#                     is an ambiguous stamp to resolve by hand — bad, not corrupting.)
#                     ⚠ It bounds a REQUEST, not a caller's total runtime. N
#                     requests can still take N×cap — board-snapshot's cap does not
#                     by itself keep it inside the SessionStart hook timeout.
kb_api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -H "Accept: application/json")
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && args+=(--max-time "$KB_CURL_MAX_TIME")
    [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
    local out
    # Auth fed via stdin herestring (-H @- <<<) so the token never enters argv (#3569) AND
    # the call is portable: a herestring redirects a regular temp file onto fd 0, avoiding the
    # /dev/fd process-substitution path that native mingw64/Git-Bash curl can't open (#34).
    out="$(curl "${args[@]}" -H @- -w $'\n__HTTP__%{http_code}' "$KB_API$path" 2>&1 <<<"$(kb_auth_header "$KB_TOKEN")")" || {
        [[ -n "${KB_LOG_FILE:-}" ]] && echo "$(date -u +%FT%TZ) $method $path FAILED-CURL $out" >> "$KB_LOG_FILE"
        echo "$(_kb_prog): curl failed on $method $path" >&2
        KB_HTTP="000"; return 1
    }
    KB_HTTP="${out##*__HTTP__}"
    local resp="${out%__HTTP__*}"
    if [[ ! "$KB_HTTP" =~ ^2 ]]; then
        [[ -n "${KB_LOG_FILE:-}" ]] && echo "$(date -u +%FT%TZ) $method $path HTTP-$KB_HTTP $resp" >> "$KB_LOG_FILE"
        [[ "${KB_API_QUIET:-}" == 1 ]] || echo "$(_kb_prog): HTTP $KB_HTTP on $method $path" >&2
        [[ "${KB_API_ERRBODY:-}" == 1 ]] && echo "$resp" >&2
        return 1
    fi
    printf '%s' "$resp"
}

# kb_api_status <method> <path> [body]: status-exposing variant. Emits
# "<http>\n<body>" to stdout and ALWAYS returns 0, so a caller capturing the
# output via $() can branch on the EXACT status (e.g. dl-a1's idempotent
# 409/422 = already-registered) — a status the kb_api global can't carry across
# a command substitution. A transport failure yields http "000".
kb_api_status() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -H "Accept: application/json")
    # Honors KB_CURL_MAX_TIME for the same reason kb_api and fetch_board_cards do:
    # the knob means one thing across every fetcher in this lib, because a caller
    # cannot tell which one it reached. This is the THIRD — a parity claim that
    # covers two of three is just a wrong claim.
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && args+=(--max-time "$KB_CURL_MAX_TIME")
    [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
    local out
    # Auth via stdin herestring (-H @- <<<) — token stays out of argv (#3569) + portable
    # (no /dev/fd process-sub dependency that breaks native mingw64 curl, #34).
    out="$(curl "${args[@]}" -H @- -w $'\n__HTTP__%{http_code}' "$KB_API$path" 2>&1 <<<"$(kb_auth_header "$KB_TOKEN")")" || { printf '000\n%s' "$out"; return 0; }
    KB_HTTP="${out##*__HTTP__}"
    printf '%s\n%s' "$KB_HTTP" "${out%__HTTP__*}"
}

# --- whole-board pagination -------------------------------------------------
# fetch_board_cards <api> <token> <board_id> [page_cap]: read the WHOLE board via
# (rc contract: 0 complete · 1 page-1 failed · 2 later-page failed · 3 page-cap hit,
# partial data emitted · 4 SHORT READ detected — server total exceeds delivered rows,
# partial data emitted; refuse-policy callers must treat 4 like 2/3)
# search.json (limit=200), accumulate VIA STDIN (printf | jq -s, never argv, so a
# page over MAX_ARG_STRLEN can't trip "Argument list too long" — the #3091 /
# #3362 class), dedup by id (order-preserving), and emit ONE JSON array on
# stdout. Stops on a short page (n<200) or meta.last_page, whichever comes first.
# Honors KB_CURL_MAX_TIME (seconds) when set (board-snapshot's 5s startup cap).
# Returns:
#   0  full read (array on stdout)
#   1  page 1 unreachable (nothing usable) — a fail-soft caller skips the board
#   2  incomplete: a page > 1 failed mid-pagination — a correctness-sensitive
#      caller (the DL minter) MUST refuse rather than risk a truncated scan
#   3  page cap hit: the partial array is still emitted (so a display caller can
#      show what it has) but the read is flagged INCOMPLETE on stderr
# A short-read backstop (meta.total vs cards read) also warns on stderr.
fetch_board_cards() {
    local api="$1" token="$2" board="$3" page_cap="${4:-50}"
    local pages="" page=1 last_page=1 resp data n total="" read_n out sum_n=0
    # Order-preserving dedup-by-id over the slurped per-page arrays.
    local dedup='def _kb_dedup: (add // []) | reduce .[] as $c ([]; if any(.[]; .id == $c.id) then . else . + [$c] end); _kb_dedup'
    # -sS WITHOUT -f (card #4337): -f discards the 4xx/5xx body and collapses every
    # HTTP failure to curl rc 22, making a 403 token-scope failure and a 422
    # validation failure indistinguishable in the failure log. Status is captured
    # via the same -w marker kb_api uses; the body is logged/surfaced on non-2xx.
    local curl_opts=(-sS)
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && curl_opts+=(--max-time "$KB_CURL_MAX_TIME")
    # KB_FETCH_LOUD=1 makes a page-fetch failure observable (kbcard's list contract):
    # curl's own -S HTTP/transport error reaches stderr instead of the default quiet
    # 2>/dev/null (which backs board-snapshot's fail-soft SessionStart display), and
    # when KB_LOG_FILE is set a failure line is appended to it. Default = silent
    # (return-code only), so board-snapshot's behavior is unchanged.
    local errsink=/dev/null
    [[ -n "${KB_FETCH_LOUD:-}" ]] && errsink=/dev/stderr
    while :; do
        local url="$api/tasks/search.json?q=board_id=${board}&limit=200&page=${page}"
        local rc
        # Auth via stdin herestring (-H @- <<<) so the token never enters argv (#3569) +
        # portable (no /dev/fd process-sub dependency that breaks native mingw64 curl, #34).
        resp="$(curl "${curl_opts[@]}" -H @- -H "Accept: application/json" \
                -w $'\n__HTTP__%{http_code}' \
                "$url" 2>"$errsink" <<<"$(kb_auth_header "$token")")" || {
            rc=$?
            if [[ -n "${KB_FETCH_LOUD:-}" ]]; then
                echo "fetch_board_cards: page $page read failed for board $board (curl rc=$rc)" >&2
                [[ -n "${KB_LOG_FILE:-}" ]] && \
                    echo "$(date -u +%FT%TZ) GET $url FAILED-FETCH curl-rc=$rc" >> "$KB_LOG_FILE"
            fi
            [[ "$page" -eq 1 ]] && return 1
            return 2
        }
        local http="${resp##*__HTTP__}"
        resp="${resp%__HTTP__*}"
        if [[ ! "$http" =~ ^2 ]]; then
            if [[ -n "${KB_FETCH_LOUD:-}" ]]; then
                echo "fetch_board_cards: page $page read failed for board $board (HTTP $http): $resp" >&2
            fi
            [[ -n "${KB_LOG_FILE:-}" ]] && \
                echo "$(date -u +%FT%TZ) GET $url HTTP-$http $resp" >> "$KB_LOG_FILE"
            [[ "$page" -eq 1 ]] && return 1
            return 2
        fi
        if [[ "$page" -eq 1 ]]; then
            last_page="$(printf '%s' "$resp" | jq -r '.meta.last_page // 1' 2>/dev/null)"
            [[ "$last_page" =~ ^[0-9]+$ ]] || last_page=1
            total="$(printf '%s' "$resp" | jq -r '.meta.total // empty' 2>/dev/null)"
        fi
        data="$(printf '%s' "$resp" | jq -c '.data // []' 2>/dev/null)"
        n="$(printf '%s' "$data" | jq 'length' 2>/dev/null)"
        pages+="$data"$'\n'
        sum_n=$((sum_n + ${n:-0}))
        [[ "${n:-0}" -lt 200 ]] && break
        [[ "$page" -ge "$last_page" ]] && break
        page=$((page + 1))
        if [[ "$page" -gt "$page_cap" ]]; then
            echo "fetch_board_cards: ⚠ stopped paging at page cap=$page_cap — list may be INCOMPLETE" >&2
            printf '%s\n' "$pages" | jq -c -s "$dedup" 2>/dev/null
            return 3
        fi
    done
    out="$(printf '%s\n' "$pages" | jq -c -s "$dedup" 2>/dev/null)"
    read_n="$(printf '%s' "$out" | jq 'length' 2>/dev/null)"
    if [[ "${total:-}" =~ ^[0-9]+$ && "${read_n:-}" =~ ^[0-9]+$ && "$total" -gt "$read_n" ]]; then
        # Distinguish a REAL undercount from a dedup artifact (card #4338): the
        # PRE-dedup page sum is the tell. sum_n < total ⇒ pages genuinely delivered
        # fewer rows than the server claims exist ⇒ emit the partial data and
        # return the DISTINCT rc 4 so refuse-policy callers (next-dl: an
        # undercount could re-mint a used DL; kbcard list: never print a
        # truncated list) can reach it — the warn-then-return-0 shape was a
        # backstop no caller could consume. sum_n >= total with read_n < total ⇒
        # the same card arrived on two pages (a page-boundary shift mid-scan) and
        # dedup collapsed it — the read is complete; warn-only. Residual accepted
        # risk, documented: a server delivering the SAME page twice would also
        # read as an artifact — that is a server fault this client-side census
        # cannot distinguish, and the warn still surfaces the count mismatch.
        if [[ "$sum_n" -lt "$total" ]]; then
            echo "fetch_board_cards: ⚠ board has $total cards but pages delivered only $sum_n ($read_n after dedup) — list INCOMPLETE" >&2
            printf '%s' "$out"
            return 4
        fi
        echo "fetch_board_cards: ⚠ read $read_n distinct of $total — duplicates across pages collapsed (page-boundary shift); read complete" >&2
    fi
    printf '%s' "$out"
}

# --- DL canonicalization ----------------------------------------------------
# kb_dl_num <token>: the bare positive integer of a DL token, strict (the kbcard
# form). Accepts an optional DL-/dl- prefix + leading zeros + 1..6 digits,
# anchored — so a pr_url / version / hex fat-fingered in FAILS loudly instead of
# silently becoming a plausible-but-wrong DL. The {1,6} bound keeps base-10
# arithmetic in int range. Prints the integer; returns 2 on a non-DL / zero.
kb_dl_num() {
    [[ "$1" =~ ^([Dd][Ll]-?)?0*([0-9]{1,6})$ ]] \
        || { echo "$(_kb_prog): '$1' is not a DL number (expect e.g. DL-093 or 93)" >&2; return 2; }
    local n="$((10#${BASH_REMATCH[2]}))"   # 10# forces base-10 so a zero-padded value isn't read as octal
    [[ "$n" -ge 1 ]] || { echo "$(_kb_prog): '$1' resolves to 0 — not a valid DL number" >&2; return 2; }
    printf '%s' "$n"
}

# kb_dl_canon <token>: the ONE canonical stored form DL-NNN, zero-padded to >=4
# (matching next-dl's DL-%04d; width is cosmetic — every reader extracts digits
# and compares numerically — so pre-existing 3-padded cards stay valid). Returns
# 2 on a non-DL input.
kb_dl_canon() {
    local n
    n="$(kb_dl_num "$1")" || return 2
    printf 'DL-%04d' "$n"
}
