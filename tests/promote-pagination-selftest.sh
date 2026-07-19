#!/usr/bin/env bash
# promote-pagination-selftest.sh — deterministic, network-free unit checks for the
# whole-board pagination + short-read CENSUS in `bin/promote-released-cards`.
#
# WHY THIS FILE EXISTS. promote-released-cards is a MOVER: a card it fails to scan is a
# card it silently leaves un-promoted. Its inline pagination had drifted from the lib's
# fetch_board_cards — it broke solely on a <200-row page and never checked the board's
# own meta.total, so a server short read (fewer rows than the board claims to hold)
# terminated the scan early and promoted from an INCOMPLETE board (card #4513, dedup-audit
# D4). The census was ported in — but a co-vendored port kept in sync by comment is exactly
# the class of thing that rots unwatched (cf. kb-host-guard-selftest for host_ok). So this
# exercises the ported logic directly against a page-serving stub.
#
# promote-released-cards runs its main at top level (no sourced-guard) and must stay
# standalone, so lift just fetch_whole_board out of it — the same extract-and-exercise
# pattern kb-host-guard-selftest uses on host_ok. The census cases mirror the lib's own
# (kb-board-lib-selftest "short-read rc 4 vs dedup artifact"); the one intended divergence
# is the failure POLICY — the lib returns rc 4 for its caller to interpret, this tool IS
# the caller and DIES on a genuine undercount.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -r "$PRC"

# Lift fetch_whole_board out of the standalone (it is never meant to be sourced whole).
prc_src="$(sed -n '/^fetch_whole_board() {/,/^}/p' "$PRC")"
[[ -n "$prc_src" ]] || { echo "selftest: could not extract fetch_whole_board from $PRC — did it get renamed?" >&2; exit 1; }
eval "$prc_src"

_mktmp_scratch

# fetch_whole_board reads these globals; die() ends the run with rc 2 (the standalone's
# refuse policy), and api() is its network seam — both stubbed here.
API="https://api.example"; BOARD="9"
die() { echo "promote-released-cards: $*" >&2; exit 2; }

# Page-serving api() stub: emits _PAGES[<n>] by inspecting the page= query param. Mirrors
# the lib selftest's _stub_page_curl, driven off promote's api() seam instead of curl.
declare -A _PAGES
api() {
    local a page=1
    for a in "$@"; do [[ "$a" == *"page="* ]] && page="${a##*page=}"; done
    printf '%s' "${_PAGES[$page]:-}"
}

echo "== single full page: totals agree → all cards, silent =="
_PAGES=( [1]='{"data":[{"id":1},{"id":2},{"id":3}],"meta":{"last_page":1,"total":3}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/full.err")" || rc=$?
eq   "single full page → rc 0"            "0"   "$rc"
eq   "single full page → all 3 cards"     "3"   "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/full.err" ]] && bad "clean read must be silent on stderr" || ok "clean single page silent"

echo "== GENUINE short read: meta.total exceeds delivered rows → REFUSE (die) =="
# The core #4513 case: one page, n<200 so the loop breaks, but the board claims 5 and only
# 3 arrived. sum_n(3) < total(5) ⇒ incomplete scan ⇒ must die, not promote from 3.
_PAGES=( [1]='{"data":[{"id":1},{"id":2},{"id":3}],"meta":{"last_page":1,"total":5}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/short.err")" || rc=$?
eq   "genuine short read → dies rc 2"     "2"   "$rc"
grep -q "INCOMPLETE board read" "$TMP/short.err" && ok "genuine short read names the incomplete scan" || bad "missing INCOMPLETE-board-read refusal"
[[ -z "$out" ]] && ok "genuine short read emits no card list to promote from" || bad "short read leaked a partial card list: '$out'"

echo "== DEDUP ARTIFACT: a card straddles a page boundary → complete, warn only =="
# total=202, two pages: p1 = ids 0..199 (200 rows → paging continues), p2 = ids 199,200.
# Pre-dedup sum (202) covers total (202); distinct read_n (201) < total because id 199
# arrived twice. sum_n >= total ⇒ read complete ⇒ warn, do NOT die.
page1="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":202}}')"
page2='{"data":[{"id":199},{"id":200}],"meta":{"last_page":2,"total":202}}'
_PAGES=( [1]="$page1" [2]="$page2" )
rc=0; out="$(fetch_whole_board 2>"$TMP/dedup.err")" || rc=$?
eq   "dedup artifact → rc 0 (read complete)"  "0"   "$rc"
eq   "dedup artifact → 201 distinct cards"    "201" "$(printf '%s' "$out" | jq 'length')"
grep -q "straddled a page boundary" "$TMP/dedup.err" && ok "dedup artifact warns honestly" || bad "dedup warn wording regressed"
grep -q "INCOMPLETE" "$TMP/dedup.err" && bad "dedup artifact must NOT claim INCOMPLETE" || ok "dedup artifact does not claim INCOMPLETE"

echo "== positive control: clean two-page read, totals agree → all cards, silent =="
page1c="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":201}}')"
page2b='{"data":[{"id":200}],"meta":{"last_page":2,"total":201}}'
_PAGES=( [1]="$page1c" [2]="$page2b" )
rc=0; out="$(fetch_whole_board 2>"$TMP/clean.err")" || rc=$?
eq   "clean two-page read → rc 0"         "0"   "$rc"
eq   "clean two-page read → 201 cards"    "201" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/clean.err" ]] && bad "clean read must be silent on stderr" || ok "clean two-page read silent"

echo "== no meta.total (server omits it): fall back to the n<200 break, no census =="
# A server that never sends meta.total can't be censused; the loop must still terminate on
# the short page and return what it read (no spurious die).
_PAGES=( [1]='{"data":[{"id":1},{"id":2}]}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/notot.err")" || rc=$?
eq   "absent meta.total → rc 0"           "0"   "$rc"
eq   "absent meta.total → 2 cards"        "2"   "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/notot.err" ]] && bad "absent-total read must be silent" || ok "absent-total read silent"

echo "== FULL 200-row page 1 with NO meta at all: must keep paging, not truncate =="
# Regression guard: a full first page with neither meta.last_page NOR meta.total present
# must fall through to the n<200 break (page 2), NOT stop at page 1. A `last_page // 1`
# default would break here and silently return only page 1 — the #4513 miss re-introduced.
full1="$(jq -nc '{"data":[range(200)|{id:.}]}')"     # 200 rows, no meta whatsoever
tail2='{"data":[{"id":200},{"id":201}]}'             # short page → n<200 terminates
_PAGES=( [1]="$full1" [2]="$tail2" )
rc=0; out="$(fetch_whole_board 2>"$TMP/nometa.err")" || rc=$?
eq   "full page + no meta → rc 0"         "0"   "$rc"
eq   "full page + no meta → paged to 202" "202" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/nometa.err" ]] && bad "no-meta full read must be silent" || ok "no-meta full read silent"

echo "== last_page=0 on a full page: out-of-range ⇒ unknown, must keep paging =="
# A non-positive last_page is not a meaningful declaration; it must not truncate the scan
# at page 1 (same class as gap #1). Full page 1 with last_page:0 and no total → page 2.
lp0="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":0}}')"
_PAGES=( [1]="$lp0" [2]='{"data":[{"id":200}]}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/lp0.err")" || rc=$?
eq   "last_page=0 → rc 0"                 "0"   "$rc"
eq   "last_page=0 → paged to 201"         "201" "$(printf '%s' "$out" | jq 'length')"

echo "== 0 visible cards on page 1 → REFUSE (token not a board member) =="
_PAGES=( [1]='{"data":[],"meta":{"last_page":1,"total":0}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/empty.err")" || rc=$?
eq   "0 visible cards → dies rc 2"        "2"   "$rc"
grep -q "0 visible cards" "$TMP/empty.err" && ok "empty board names the membership cause" || bad "missing 0-visible-cards refusal"

_summary "promote-pagination-selftest"
