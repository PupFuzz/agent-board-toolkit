# shellcheck shell=bash
# _kb-board-lib.sh — shared helpers for the agent-board-toolkit's OWN scripts.
#
# Toolkit-only: this file is NOT vendored into consumer repos and NOT byte-synced
# (unlike promote-released-cards, which is and must never source this). It is
# sourced, never executed. It collapses the config-resolution, kanban-API curl
# wrapper, whole-board pagination, and DL-canonicalization logic that was
# copy-pasted across kbcard / next-dl / dl-a0-backfill-triaged /
# dl-a1-register-field / board-snapshot / board-card-start into one definition.
#
# Source it from a sibling toolkit script with:
#   source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/_kb-board-lib.sh"
#
# Conventions honored (unchanged from the per-script copies):
#   - API base is host-level (~/.kanban-host.env, override $KANBAN_HOST_ENV) and
#     is sourced only when KBCARD_API is still unset.
#   - Board env is ~/.kanban-<name>-board.env; kanban|dev (and "no --board") map
#     to the kanban-dev board.
#   - Token file is $KBCARD_TOKEN_FILE (resolvable from inside a config file) or
#     ~/.kanban-dev-token.

if [[ -n "${_KB_BOARD_LIB_LOADED:-}" ]]; then return 0; fi
_KB_BOARD_LIB_LOADED=1

# Message prefix; a script may set KB_PROG, else its own basename is used.
_kb_prog() { printf '%s' "${KB_PROG:-${0##*/}}"; }

# --- config resolution ------------------------------------------------------

# kb_resolve_env <board_env_path>: source the board env, then the host env (only
# when KBCARD_API is still unset), and publish KB_API / KB_BOARD_ID /
# KB_TOKEN_FILE / KB_BOARD_ENV. Does NOT read the token content and does NOT
# require KB_BOARD_ID — the caller decides those. Quiet (return-code only) so a
# fail-soft caller can craft its own message. Returns:
#   0 ok   2 env unreadable   3 KBCARD_API unset   5 token file unreadable
kb_resolve_env() {
    local board_env="$1"
    [[ -r "$board_env" ]] || return 2
    # shellcheck disable=SC1090
    source "$board_env"
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    if [[ -z "${KBCARD_API:-}" && -r "$host_env" ]]; then
        # shellcheck disable=SC1090
        source "$host_env"
    fi
    KB_API="${KBCARD_API:-}"
    [[ -n "$KB_API" ]] || return 3
    KB_BOARD_ID="${KB_BOARD_ID:-}"
    KB_TOKEN_FILE="${KBCARD_TOKEN_FILE:-$HOME/.kanban-dev-token}"
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
        5) echo "$(_kb_prog): token file not readable: $KB_TOKEN_FILE" >&2; return 2 ;;
        *) echo "$(_kb_prog): config error ($rc) for $board_env" >&2; return 2 ;;
    esac
    KB_TOKEN="$(cat "$KB_TOKEN_FILE")"
    return 0
}

# kb_load_host_token [unconditional]: lighter resolver for scripts whose board id
# comes from a different source (board-snapshot iterates many board envs;
# board-card-start reads .release-pr.json). Sources the host env (for a
# KBCARD_TOKEN_FILE override + API base) and reads the token. Publishes KB_API
# (may be empty), KB_TOKEN and KB_TOKEN_FILE. Returns 1 (fail-soft) if the token
# file is unreadable.
#
# Precedence mode (first arg):
#   gated (default)  host env sourced only when KBCARD_API is still unset — for a
#                    script (board-snapshot) that may already have an API in env.
#   unconditional    host env sourced whenever readable, so a KBCARD_TOKEN_FILE
#                    set inside it always wins — board-card-start's prior contract,
#                    which never reads KBCARD_API (api/board come from .release-pr.json)
#                    and must not have its token override skipped by a stray ambient
#                    KBCARD_API.
kb_load_host_token() {
    local mode="${1:-gated}"
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    if [[ -r "$host_env" ]] && { [[ "$mode" == "unconditional" ]] || [[ -z "${KBCARD_API:-}" ]]; }; then
        # shellcheck disable=SC1090
        source "$host_env"
    fi
    KB_API="${KBCARD_API:-}"
    KB_TOKEN_FILE="${KBCARD_TOKEN_FILE:-$HOME/.kanban-dev-token}"
    [[ -r "$KB_TOKEN_FILE" ]] || return 1
    KB_TOKEN="$(cat "$KB_TOKEN_FILE")"
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
kb_api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -H "Accept: application/json")
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
    local pages="" page=1 last_page=1 resp data n total="" read_n out
    # Order-preserving dedup-by-id over the slurped per-page arrays.
    local dedup='def _kb_dedup: (add // []) | reduce .[] as $c ([]; if any(.[]; .id == $c.id) then . else . + [$c] end); _kb_dedup'
    local curl_opts=(-fsS)
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
        if [[ "$page" -eq 1 ]]; then
            last_page="$(printf '%s' "$resp" | jq -r '.meta.last_page // 1' 2>/dev/null)"
            [[ "$last_page" =~ ^[0-9]+$ ]] || last_page=1
            total="$(printf '%s' "$resp" | jq -r '.meta.total // empty' 2>/dev/null)"
        fi
        data="$(printf '%s' "$resp" | jq -c '.data // []' 2>/dev/null)"
        n="$(printf '%s' "$data" | jq 'length' 2>/dev/null)"
        pages+="$data"$'\n'
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
        echo "fetch_board_cards: ⚠ board has $total cards but only $read_n read — list may be INCOMPLETE" >&2
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
