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
if [[ "$fails" -gt 0 ]]; then
    echo "kb-board-lib-selftest: $fails check(s) FAILED" >&2
    exit 1
fi
echo "kb-board-lib-selftest: all checks passed"
