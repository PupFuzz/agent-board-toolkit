#!/usr/bin/env bash
# kb-board-lib-selftest.sh — deterministic, network-free unit checks for the config-resolution
# helpers in `bin/_kb-board-lib.sh` (kb_resolve_env / kb_load_host_env / kb_board_env_for /
# kb_board_env_get / kb_read_token). The lib is freely sourceable (no main), so these drive
# the real functions against synthetic env files under a scratch HOME. Matches the toolkit's
# selftest-CI convention (no bats/shunit2; a runnable script CI invokes).
#
# The token LADDER is the thing under test: a board env's KBCARD_TOKEN_FILE > the host env's >
# an ambient one > ~/.kanban-dev-token. It regressed silently once (#4325) because it is a
# property of source ORDER that nothing exercised.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB="$HERE/../bin/_kb-board-lib.sh"
[[ -r "$LIB" ]] || { echo "selftest: $LIB not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$LIB"
KB_PROG="kb-board-lib-selftest"

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
eq()  { # <label> <expected> <got>
    [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"
}

# Scratch HOME so no real ~/.kanban-* file can influence (or be influenced by) a result.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
export KANBAN_HOST_ENV="$TMP/.kanban-host.env"

printf 'board-token\n'   > "$TMP/board.token"
printf 'host-token\n'    > "$TMP/host.token"
printf 'ambient-token\n' > "$TMP/ambient.token"
printf 'default-token\n' > "$TMP/.kanban-dev-token"
printf 'spaced-token\n'  > "$TMP/tok with space.token"

# reset_env: drop every var the resolvers read or publish, so each case starts from a known
# state — these functions communicate through globals and a leaked one would fake a pass.
reset_env() {
    unset KBCARD_API KBCARD_TOKEN_FILE KB_API KB_BOARD_ID KB_TOKEN KB_TOKEN_FILE \
          KB_BOARD_ENV KB_HOST_TOKEN_FILE KANBAN_EXPECTED_HOST
    : > "$KANBAN_HOST_ENV"
}

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — the token ladder (board > host > ambient > default) =="

# 1. board env's KBCARD_TOKEN_FILE wins over the host's — the case v0.8.2 regressed.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env"; rc=$?
eq "board KBCARD_TOKEN_FILE wins over host (rc)" "0" "$rc"
eq "board KBCARD_TOKEN_FILE wins over host"      "$TMP/board.token" "${KB_TOKEN_FILE:-}"
eq "  and publishes KB_BOARD_ID"                 "42" "${KB_BOARD_ID:-}"
eq "  and publishes KB_BOARD_ENV"                "$TMP/.kanban-x-board.env" "${KB_BOARD_ENV:-}"

# 2. host's wins when the board env sets none.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "host KBCARD_TOKEN_FILE used when board sets none" "$TMP/host.token" "${KB_TOKEN_FILE:-}"

# 3. an ambient one is used when neither config sets one (the tier below host).
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "ambient KBCARD_TOKEN_FILE used when no config sets one" "$TMP/ambient.token" "${KB_TOKEN_FILE:-}"

# 4. host BEATS ambient (source order) — not the reverse.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "host KBCARD_TOKEN_FILE beats an ambient one" "$TMP/host.token" "${KB_TOKEN_FILE:-}"

# 5. the ~/.kanban-dev-token default when nothing sets one.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "falls back to ~/.kanban-dev-token" "$TMP/.kanban-dev-token" "${KB_TOKEN_FILE:-}"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — KBCARD_API is host-only =="

# A board env that sets KBCARD_API is REFUSED (rc 4), not silently honored.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo 'export KBCARD_API="https://board-set.test/api/v3"'; } > "$TMP/.kanban-api-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-api-board.env" 2>/dev/null || rc=$?
eq "board-env KBCARD_API is refused" "4" "$rc"

# The refusal must be LOUD — a silent rc is what an operator never sees.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo 'export KBCARD_API="https://board-set.test/api/v3"'; } > "$TMP/.kanban-api-board.env"
msg="$(kb_resolve_env "$TMP/.kanban-api-board.env" 2>&1 >/dev/null || true)"
case "$msg" in
    *"board-independent"*"$TMP/.kanban-api-board.env"*) ok "refusal names the offending file on stderr" ;;
    *) bad "refusal message missing/unhelpful: '$msg'" ;;
esac

# An ambient KBCARD_API still beats the host's (and does NOT trip the board-env refusal).
reset_env
echo 'export KBCARD_API="https://host.test/api/v3"' > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_API="https://ambient.test/api/v3"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "ambient KBCARD_API beats the host's" "https://ambient.test/api/v3" "${KB_API:-}"

# KBCARD_API must be restored in the caller's env — the probe unsets it internally, and a
# caller (or a child process) left with it missing would be a silent side effect.
eq "KBCARD_API restored in the caller's env after resolve" "https://ambient.test/api/v3" "${KBCARD_API:-}"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — no cross-call leak (sourcing mutates the caller's shell) =="
# Resolving board A then board B in ONE shell: B sets no token, so it must land on the
# DEFAULT — not on A's token. kb_resolve_env sources into the caller, so without an explicit
# restore A's value would still be sitting there as B's "ambient" tier.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=1'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-one-board.env"
echo 'KB_BOARD_ID=2' > "$TMP/.kanban-two-board.env"   # sets NO token
kb_resolve_env "$TMP/.kanban-one-board.env"
eq "board A resolves to its own token"          "$TMP/board.token"       "${KB_TOKEN_FILE:-}"
kb_resolve_env "$TMP/.kanban-two-board.env"
eq "board B (sets none) does NOT inherit A's token" "$TMP/.kanban-dev-token" "${KB_TOKEN_FILE:-}"

# ...and the ambient tier still works after a resolve has run.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-one-board.env"   # board A: sets its own
kb_resolve_env "$TMP/.kanban-two-board.env"   # board B: none -> must fall to AMBIENT, not A's
eq "board B falls through to the ambient token, not A's" "$TMP/ambient.token" "${KB_TOKEN_FILE:-}"
eq "ambient KBCARD_TOKEN_FILE restored in the caller's env" "$TMP/ambient.token" "${KBCARD_TOKEN_FILE:-}"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — failure return codes =="
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
rc=0; kb_resolve_env "$TMP/nope-board.env" 2>/dev/null || rc=$?
eq "unreadable board env → rc 2" "2" "$rc"

reset_env   # empty host env ⇒ no KBCARD_API anywhere
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "no KBCARD_API → rc 3" "3" "$rc"

reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/absent.token\""; } > "$TMP/.kanban-x-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "unreadable token file → rc 5" "5" "$rc"

# ---------------------------------------------------------------------------
echo "== kb_load_host_env =="
reset_env
{ echo 'export KBCARD_API="https://host.test/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""
  echo 'export KANBAN_EXPECTED_HOST="host.test"'; } > "$KANBAN_HOST_ENV"
kb_load_host_env
eq "publishes KB_API from the host env"          "https://host.test/api/v3" "${KB_API:-}"
eq "publishes KB_HOST_TOKEN_FILE"                "$TMP/host.token" "${KB_HOST_TOKEN_FILE:-}"

# The regression the gated mode caused: a stray ambient KBCARD_API must NOT stop the host env
# from loading, or KANBAN_EXPECTED_HOST vanishes and every https-host guard fail-closes.
reset_env
{ echo 'export KBCARD_API="https://host.test/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""
  echo 'export KANBAN_EXPECTED_HOST="host.test"'; } > "$KANBAN_HOST_ENV"
export KBCARD_API="https://ambient.test/api/v3"
kb_load_host_env
eq "ambient KBCARD_API still wins"                        "https://ambient.test/api/v3" "${KB_API:-}"
eq "  but the host env STILL loaded (KANBAN_EXPECTED_HOST)" "host.test" "${KANBAN_EXPECTED_HOST:-}"
eq "  and the host token default STILL loaded"             "$TMP/host.token" "${KB_HOST_TOKEN_FILE:-}"

# No host env at all must not fail (it reads no token, so it has nothing to fail on).
reset_env
rm -f "$KANBAN_HOST_ENV"
rc=0; kb_load_host_env || rc=$?
eq "no host env → still rc 0" "0" "$rc"
eq "  KB_API empty"           ""  "${KB_API:-}"
: > "$KANBAN_HOST_ENV"

# ---------------------------------------------------------------------------
echo "== kb_board_env_for =="
reset_env
rm -f "$TMP"/.kanban-*-board.env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-a-board.env"
echo 'KB_BOARD_ID=99' > "$TMP/.kanban-b-board.env"
eq "finds the env whose KB_BOARD_ID matches" "$TMP/.kanban-a-board.env" "$(kb_board_env_for 42 2>/dev/null)"
eq "finds the other one"                     "$TMP/.kanban-b-board.env" "$(kb_board_env_for 99 2>/dev/null)"
rc=0; kb_board_env_for 7 >/dev/null 2>&1 || rc=$?
eq "no match → rc 1" "1" "$rc"

# An env that sets NO KB_BOARD_ID must never match — with KB_BOARD_ID leaked from the caller
# it would otherwise match every lookup.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'KB_STAGE_BACKLOG=1' > "$TMP/.kanban-noid-board.env"   # sets no KB_BOARD_ID
KB_BOARD_ID=42   # a leaked global from an earlier resolve
rc=0; kb_board_env_for 42 >/dev/null 2>&1 || rc=$?
eq "env with no KB_BOARD_ID does not false-match a leaked KB_BOARD_ID" "1" "$rc"
unset KB_BOARD_ID

# A duplicate KB_BOARD_ID is arbitrary either way — the defect is being silent about it.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-dup1-board.env"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-dup2-board.env"
warn="$(kb_board_env_for 42 2>&1 >/dev/null || true)"
case "$warn" in
    *"2 board envs set KB_BOARD_ID=42"*) ok "duplicate KB_BOARD_ID warns loudly" ;;
    *) bad "duplicate KB_BOARD_ID did not warn: '$warn'" ;;
esac
[[ -n "$(kb_board_env_for 42 2>/dev/null)" ]] && ok "duplicate still returns a usable path" \
    || bad "duplicate returned no path"

# A board env that is unparsable must not abort the scan or match.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'this is ( not valid shell' > "$TMP/.kanban-broken-board.env"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-good-board.env"
eq "a broken board env is skipped, not fatal" "$TMP/.kanban-good-board.env" "$(kb_board_env_for 42 2>/dev/null)"

# ---------------------------------------------------------------------------
echo "== kb_board_env_get =="
# get1: read one var the way a caller does (first line; the '.' sentinel is never read).
get1() { local v; IFS= read -r v <<<"$(kb_board_env_get "$1" "$2")"; printf '%s' "$v"; }

reset_env
rm -f "$TMP"/.kanban-*-board.env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-a-board.env"
eq "reports the board env's own KBCARD_TOKEN_FILE" "$TMP/board.token" \
   "$(get1 "$TMP/.kanban-a-board.env" KBCARD_TOKEN_FILE)"

# Empty (not the inherited host value) when the board env sets none — otherwise the caller
# would read the host's override back as a per-board one and never fall through its ladder.
reset_env
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-b-board.env"
export KBCARD_TOKEN_FILE="$TMP/host.token"   # as kb_load_host_env would have left it
eq "empty when the board env sets none (host value not echoed back)" "" \
   "$(get1 "$TMP/.kanban-b-board.env" KBCARD_TOKEN_FILE)"

# A token path containing a space must survive intact (no word-splitting).
reset_env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/tok with space.token\""; } > "$TMP/.kanban-sp-board.env"
eq "a token path with a space survives" "$TMP/tok with space.token" \
   "$(get1 "$TMP/.kanban-sp-board.env" KBCARD_TOKEN_FILE)"

# Multi-var read: the exact call board-card-start makes for its stage ids. An unset OPTIONAL
# key must come back EMPTY and must not shift a later value into its place.
reset_env
{ echo 'KB_BOARD_ID=42'; echo 'export KB_STAGE_IN_PROGRESS=84'; echo 'export KB_STAGE_BACKLOG=83'
  echo 'export KB_STAGE_PRIORITIZED=86'; } > "$TMP/.kanban-noheld-board.env"   # NO KB_STAGE_HELD
{ IFS= read -r ip; IFS= read -r bl; IFS= read -r pr; IFS= read -r hl; } \
    <<<"$(kb_board_env_get "$TMP/.kanban-noheld-board.env" KB_STAGE_IN_PROGRESS KB_STAGE_BACKLOG KB_STAGE_PRIORITIZED KB_STAGE_HELD)"
eq "multi-var: in_progress" "84" "$ip"
eq "multi-var: backlog"     "83" "$bl"
eq "multi-var: prioritized" "86" "$pr"
eq "multi-var: an unset optional KB_STAGE_HELD reads EMPTY (no shift)" "" "$hl"

# THE LEAK: board envs `export` their keys, so another board's value is live in an operator
# shell. A board env that omits an optional key must NOT inherit it.
reset_env
export KB_STAGE_HELD=88   # leaked from a previously-sourced board env
{ IFS= read -r ip; IFS= read -r bl; IFS= read -r pr; IFS= read -r hl; } \
    <<<"$(kb_board_env_get "$TMP/.kanban-noheld-board.env" KB_STAGE_IN_PROGRESS KB_STAGE_BACKLOG KB_STAGE_PRIORITIZED KB_STAGE_HELD)"
eq "a leaked KB_STAGE_HELD is NOT reported as this board's" "" "$hl"
unset KB_STAGE_HELD

reset_env
export KBCARD_TOKEN_FILE="$TMP/host.token"
eq "a leaked KBCARD_TOKEN_FILE is NOT reported as this board's" "" \
   "$(get1 "$TMP/.kanban-noheld-board.env" KBCARD_TOKEN_FILE)"

# kb_board_env_get must not leak the board env into the caller.
reset_env
get1 "$TMP/.kanban-a-board.env" KBCARD_TOKEN_FILE >/dev/null
eq "does not leak the board env's KB_BOARD_ID into the caller" "" "${KB_BOARD_ID:-}"

# ---------------------------------------------------------------------------
echo "== kb_read_token =="
reset_env
kb_read_token "$TMP/board.token"
eq "reads the token content"        "board-token"      "${KB_TOKEN:-}"
eq "publishes the token file path"  "$TMP/board.token" "${KB_TOKEN_FILE:-}"
kb_read_token "$TMP/tok with space.token"
eq "reads a token path with a space" "spaced-token" "${KB_TOKEN:-}"
rc=0; kb_read_token "$TMP/absent.token" || rc=$?
eq "unreadable token → rc 1 (returns, never exits)" "1" "$rc"

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: HTTP failure carries status + body (card #4337) =="
# curl is stubbed as a shell function (shadows the binary for the sourced lib) so the
# checks are network-free. The stub consumes the herestring auth on fd 0 and emits the
# lib's -w marker exactly as real curl would.
reset_env
FETCH_LOG="$TMP/fetch-failures.log"

# The stub EMULATES real curl's -f semantics (body discarded, rc 22 on non-2xx) so
# reintroducing -f into curl_opts reds the body checks below (mutation-sensitive).
_stub_curl_respond() { # <body> <status>
    cat >/dev/null
    local a
    for a in "${_STUB_ARGS[@]}"; do
        if [[ "$a" == -f* && "$2" != 2* ]]; then return 22; fi
    done
    printf '%s\n__HTTP__%s' "$1" "$2"
    return 0
}
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"forbidden: token lacks board scope"}' 403; }
rc=0; out="$(KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 2>"$TMP/fetch.err")" || rc=$?
eq "HTTP 403 on page 1 → rc 1"                    "1" "$rc"
eq "HTTP 403 → no data on stdout"                 ""  "$out"
grep -q "HTTP-403" "$FETCH_LOG" && ok "failure log carries the HTTP status" || bad "failure log missing HTTP-403"
grep -q "forbidden: token lacks board scope" "$FETCH_LOG" && ok "failure log carries the error body (403 vs 422 distinguishable)" || bad "failure log lost the error body"
grep -q "HTTP 403" "$TMP/fetch.err" && ok "loud mode surfaces the status on stderr" || bad "stderr missing HTTP 403"

curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":{"stage_id":["invalid"]}}' 422; }
: > "$FETCH_LOG"
rc=0; KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1 || rc=$?
grep -q "HTTP-422" "$FETCH_LOG" && ok "a 422 logs as HTTP-422, not a generic curl rc" || bad "422 indistinguishable in log"

curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 200; }
rc=0; out="$(fetch_board_cards "https://api.example" tok 8)" || rc=$?
eq "200 single page → rc 0"          "0" "$rc"
eq "200 single page → data returned" '[{"id":7}]' "$out"

curl() { cat >/dev/null; return 7; }
: > "$FETCH_LOG"
rc=0; KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1 || rc=$?
eq "transport failure on page 1 → rc 1" "1" "$rc"
grep -q "FAILED-FETCH curl-rc=7" "$FETCH_LOG" && ok "transport failure keeps the curl-rc log line" || bad "transport log line regressed"
unset -f curl

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: short-read rc 4 vs dedup artifact (card #4338) =="
# Page-aware stub: emits per-page payloads by inspecting the page= query param.
_stub_page_curl() { # uses _PAGES assoc: _PAGES[<n>]=<json>
    cat >/dev/null
    local a page=1
    for a in "${_STUB_ARGS[@]}"; do
        [[ "$a" == *"page="* ]] && page="${a##*page=}"
    done
    printf '%s\n__HTTP__200' "${_PAGES[$page]}"
    return 0
}
declare -A _PAGES

# GENUINE short read: server claims total=3, delivers 2 rows on the only page.
curl() { _STUB_ARGS=("$@"); _stub_page_curl; }
_PAGES=( [1]='{"data":[{"id":1},{"id":2}],"meta":{"last_page":1,"total":3}}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/short.err")" || rc=$?
eq "genuine short read → rc 4"                 "4" "$rc"
eq "genuine short read still emits the partial data" '[{"id":1},{"id":2}]' "$out"
grep -q "INCOMPLETE" "$TMP/short.err" && ok "genuine short read warns INCOMPLETE" || bad "missing INCOMPLETE warn"

# DEDUP ARTIFACT: two pages, one card straddles the boundary; pre-dedup sum (201)
# covers total (201) but distinct read_n (200) < total → complete, rc 0, soft warn.
# total=202 while only 201 DISTINCT ids exist: the straddling duplicate (199)
# makes the pre-dedup sum (202) cover the total, so the read is complete and
# the 201<202 gap is the collapsed duplicate, not a missing row.
page1="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":202}}')"
page2='{"data":[{"id":199},{"id":200}],"meta":{"last_page":2,"total":202}}'
_PAGES=( [1]="$page1" [2]="$page2" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/dedup.err")" || rc=$?
eq "dedup artifact → rc 0 (read complete)"     "0" "$rc"
eq "dedup artifact → all distinct cards"       "201" "$(printf '%s' "$out" | jq 'length')"   # 202 delivered, 1 collapsed
grep -q "duplicates across pages collapsed" "$TMP/dedup.err" && ok "dedup artifact warns honestly (not INCOMPLETE)" || bad "dedup warn wording regressed"
grep -q "INCOMPLETE" "$TMP/dedup.err" && bad "dedup artifact must not claim INCOMPLETE" || ok "dedup artifact does not claim INCOMPLETE"

# Positive control: clean two-page read, totals agree → rc 0, silent.
page1c="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":201}}')"
page2b='{"data":[{"id":200}],"meta":{"last_page":2,"total":201}}'
_PAGES=( [1]="$page1c" [2]="$page2b" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/clean.err")" || rc=$?
eq "clean two-page read → rc 0"                "0" "$rc"
eq "clean two-page read → 201 cards"           "201" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/clean.err" ]] && bad "clean read must be silent on stderr" || ok "clean read silent"

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: last_page must not truncate a full page 1 (card #4623) =="
# Parity with the standalone's fetch_whole_board (promote-pagination-selftest): meta.last_page
# is a SECONDARY signal; the n<200 short-page break is primary. An ABSENT or out-of-range
# last_page defaults to UNKNOWN and must fall through to the short-page break, never stop the
# scan at a full 200-row page 1. The old `// 1` default broke here and silently returned only
# page 1 (the #4513 miss). Reverting the guard reds these two cases.

# Full 200-row page 1 with NO meta at all: must keep paging to the short page, not truncate.
full1="$(jq -nc '{"data":[range(200)|{id:.}]}')"     # 200 rows, no meta whatsoever
tail2='{"data":[{"id":200},{"id":201}]}'             # short page → n<200 terminates
_PAGES=( [1]="$full1" [2]="$tail2" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/nometa.err")" || rc=$?
eq "full page + no meta → rc 0"                "0"   "$rc"
eq "full page + no meta → paged to 202"        "202" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/nometa.err" ]] && bad "no-meta full read must be silent on stderr" || ok "no-meta full read silent"

# last_page=0 on a full page: a non-positive value is not a meaningful declaration ⇒ unknown ⇒
# must keep paging, not break at page 1 (the same truncation class as an absent last_page).
lp0="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":0}}')"
_PAGES=( [1]="$lp0" [2]='{"data":[{"id":200}]}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/lp0.err")" || rc=$?
eq "last_page=0 → rc 0"                        "0"   "$rc"
eq "last_page=0 → paged to 201"                "201" "$(printf '%s' "$out" | jq 'length')"
unset -f curl _stub_page_curl

# --- KB_CURL_MAX_TIME parity: kb_api and fetch_board_cards honor the SAME knob ---
# board-snapshot sets this knob ONCE at the top of the script so a slow/down API can
# never stall SessionStart, then reaches the board through BOTH lib fetchers. kb_api
# ignored it while fetch_board_cards honored it, so a single read was unbounded under
# a cap that read as global — reintroducing, via the sibling, the exact hang the cap
# exists to prevent. A caller cannot tell which fetcher it landed on, so the knob must
# mean the same thing in both. Keep these three assertions together: the parity IS the
# contract, and the unset case pins that existing callers are unaffected.
#
# argv is captured to a FILE, not a variable: kb_api runs curl inside "$(…)", so a
# stub-assigned array dies with that subshell and would assert nothing.
_argv_file="$TMP/curl-argv.txt"
curl() { printf '%s\n' "$@" > "$_argv_file"; _stub_curl_respond '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 200; }
_maxtime_arg() { grep -A1 -x -F -- '--max-time' "$_argv_file" 2>/dev/null | tail -1; }

KB_API="https://api.example"
KB_TOKEN=tok

: > "$_argv_file"
KB_CURL_MAX_TIME=5
kb_api GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api honors KB_CURL_MAX_TIME → curl gets --max-time 5"        "5" "$(_maxtime_arg)"

: > "$_argv_file"
KB_CURL_MAX_TIME=5
fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1
eq "fetch_board_cards honors the SAME knob (parity)"                "5" "$(_maxtime_arg)"

# kb_api_status is the THIRD fetcher. It was the sibling missed when kb_api was
# fixed — a parity claim covering two of three is just a wrong claim, and the
# caller cannot tell which of the three it reached. Assert all three or none.
: > "$_argv_file"
KB_CURL_MAX_TIME=5
kb_api_status GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api_status honors the SAME knob (third fetcher)"             "5" "$(_maxtime_arg)"

: > "$_argv_file"
unset KB_CURL_MAX_TIME
kb_api GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api without the knob → no --max-time (callers unchanged)"    ""  "$(_maxtime_arg)"

unset -f curl _maxtime_arg
unset KB_API KB_TOKEN _argv_file

# ---------------------------------------------------------------------------
# expect_out drives a function and compares stdout; expect_rc compares exit status.
expect_out() { # <label> <expected> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local got; got="$("$@" 2>/dev/null || true)"
    eq "$label" "$exp" "$got"
}
expect_rc() { # <label> <expected-rc> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local rc=0; "$@" >/dev/null 2>&1 || rc=$?
    eq "$label (rc)" "$exp" "$rc"
}

echo "== kb_dl_num — strict (rejects non-DL loudly) =="
expect_out "bare int"                   "42"  kb_dl_num "42"
expect_out "DL-093 -> 93"               "93"  kb_dl_num "DL-093"
expect_out "lowercase dl- prefix"       "42"  kb_dl_num "dl-042"
expect_rc  "no digits rejected"         2     kb_dl_num "DL-"
expect_rc  "all-zeros rejected"         2     kb_dl_num "DL-0000"
expect_rc  "mixed junk rejected"        2     kb_dl_num "v2-DL-0042"
expect_rc  "over-6-digits rejected"     2     kb_dl_num "1234567"

echo "== kb_dl_canon — the ONE canonical stored form DL-NNNN =="
expect_out "pads to 4"                  "DL-0093"   kb_dl_canon "93"
expect_out "already-canonical token"    "DL-0093"   kb_dl_canon "DL-093"
expect_out "5-digit not truncated"      "DL-12345"  kb_dl_canon "12345"
expect_rc  "non-DL rejected"            2           kb_dl_canon "not-a-dl"

echo "== kb_dl_int_lenient — server canonicalize('dl') (strip non-digits, collapse zeros) =="
expect_out "bare int"                   "42"    kb_dl_int_lenient "42"
expect_out "DL-088 3-pad -> 88"         "88"    kb_dl_int_lenient "DL-088"
expect_out "DL-0192 4-pad -> 192"       "192"   kb_dl_int_lenient "DL-0192"
expect_out "lowercase dl- prefix"       "42"    kb_dl_int_lenient "dl-042"
expect_out "empty -> empty"             ""      kb_dl_int_lenient ""
expect_out "no digits -> empty"         ""      kb_dl_int_lenient "DL-"
expect_out "all-zeros -> 0"             "0"     kb_dl_int_lenient "DL-0000"
expect_out "multi-run strips all"       "20042" kb_dl_int_lenient "v2-DL-0042"

echo "== kb_by_ref_hit — object-or-array tolerant by-ref predicate =="
expect_rc "envelope: card present -> hit"        0 kb_by_ref_hit '{"data":[{"id":4020}]}'          4020
expect_rc "envelope: present among many"         0 kb_by_ref_hit '{"data":[{"id":4020},{"id":5}]}' 4020
expect_rc "envelope: different card -> miss"     1 kb_by_ref_hit '{"data":[{"id":99}]}'            4020
expect_rc "envelope: empty data -> miss"         1 kb_by_ref_hit '{"data":[]}'                     4020
expect_rc "bare array: present -> hit"           0 kb_by_ref_hit '[{"id":4020}]'                   4020
expect_rc "bare array: different -> miss"        1 kb_by_ref_hit '[{"id":99}]'                     4020
expect_rc "bare empty array -> miss"             1 kb_by_ref_hit '[]'                              4020
expect_rc "missing data key -> miss"             1 kb_by_ref_hit '{}'                              4020
# Malformed JSON: jq's own parse-error exit code passes through (not necessarily 1); the
# contract every caller relies on is "falsy = no hit", so assert the truthiness, not the code.
if kb_by_ref_hit 'not json' 4020; then bad "malformed json -> miss (fail-closed)"; else ok "malformed json -> miss (fail-closed)"; fi

# ---------------------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
    echo "kb-board-lib-selftest: $fails check(s) FAILED" >&2
    exit 1
fi
echo "kb-board-lib-selftest: all checks passed"
