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
PRC="${PROMOTE_PAGINATION_PRC:-$HERE/../bin/promote-released-cards}"
_need -r "$PRC"

# Lift fetch_whole_board out of the standalone (it is never meant to be sourced whole).
_adopt_fn "$PRC" fetch_whole_board

# …and the file-scope helpers it calls. Lifting the REAL uint_ok rather than stubbing one
# keeps this exercising the shipped numeric check (which matches under LC_ALL=C, because a
# bare `*[!0-9]*` glob range is a COLLATION range — card#5409). An UNLIFTED helper does not
# fail loudly: the call returns 127, the census silently no-ops, and the only tell is a
# "command not found" on a stream some cases don't read — so the extraction must exit 1, which
# is what `_adopt_fn` does. This site was hand-spelled until card#8529 gave `_fn_src` a one-line
# mode and a space-run anchor: `uint_ok()     {` needed BOTH — five spaces before the brace, and
# a whole body on the definition line — which is why relaxing either one alone had freed nothing.
_adopt_fn "$PRC" uint_ok

_mktmp_scratch

# fetch_whole_board reads these globals; die() ends the run with rc 2 (the standalone's
# refuse policy), and api() is its network seam — both stubbed here.
API="https://api.example"; BOARD="9"
die() { echo "promote-released-cards: $*" >&2; exit 2; }

# Page-serving api() stub: emits _PAGES[<n>] selected by the request's id WINDOW. Mirrors the
# lib selftest's _stub_page_curl, driven off promote's api() seam instead of curl: the walk keys
# every request after the first on `id<C`, C the last id of the page before (card#10626), so no
# window is page 1 and `id<C` is the page FOLLOWING the one ending in C. Fixture pages are
# therefore id-DESCENDING and each wholly below the last, as the real server answers. A window
# no page follows answers a body with no card array.
declare -A _PAGES
api() {
    local a cur="" k=1 prev
    for a in "$@"; do [[ "$a" =~ id%3C([0-9]+) ]] && cur="${BASH_REMATCH[1]}"; done
    if [[ -n "$cur" ]]; then
        k=""
        for prev in "${!_PAGES[@]}"; do
            [[ "$(jq -r '.data[-1].id // empty' <<<"${_PAGES[$prev]}" 2>/dev/null)" == "$cur" ]] && k=$((prev + 1))
        done
        [[ -n "$k" ]] || { printf '{"stub":"no page follows id<%s"}' "$cur"; return 0; }
    fi
    printf '%s' "${_PAGES[$k]:-}"
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

echo "== a DUPLICATE no longer excuses a shortfall → REFUSE (die) (card#10626) =="
# The census used to read "rows delivered >= total, distinct < total" as a card straddling a
# page boundary, and promote anyway. The shift that delivers a card twice is the one that skips
# another, so it promoted from a board missing a card. 3 claimed, 3 rows, 2 distinct → die.
_PAGES=( [1]='{"data":[{"id":3},{"id":2},{"id":2}],"meta":{"last_page":1,"total":3}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/dedup.err")" || rc=$?
eq   "a repeated row covering the total → dies rc 2" "2" "$rc"
[[ -z "$out" ]] && ok "…and no card list reaches the mover" || bad "a repeated-row shortfall leaked a card list: '$out'"
grep -q "pages delivered 3 rows, only 2 of them distinct" "$TMP/dedup.err" && ok "…naming the rows that were not distinct cards" || bad "missing the not-distinct refusal"

echo "== a card DISPLACED across a page boundary mid-walk (card#10626) =="
# The board changes BETWEEN the walk's requests; tests/_board-walk-sim.sh computes each answer
# from the board as it stands at that request (the argument is in kb-board-lib-selftest's
# matching block, which drives the lib's copy of this walk over the same simulator). Asserted:
# every card live for the WHOLE walk is in the list this mover promotes from.
# shellcheck source=/dev/null
source "$HERE/_board-walk-sim.sh"
declare -f api > "$TMP/api-pages.fn"
api() { bws_respond "$1"; }
_walk() { _W_RC=0; _W_OUT="$(fetch_whole_board 2>"$TMP/walk.err")" || _W_RC=$?; }
_walk_missing() { jq -c --argjson e "$1" '$e - [.[].id]' <<<"${_W_OUT:-[]}"; }

bws_init "$TMP/sim-dl" "$(jq -nc '[range(1;501)]')"       # 3 pages
bws_after 1 archive 400                                    # page 2 would lose card 300 …
bws_after 2 create                                         # … and page 3 re-deliver card 100
_walk
eq   "dup+loss walk → rc 0"                                  "0"  "$_W_RC"
eq   "dup+loss walk → no card live for the whole walk is missing" "[]" \
     "$(_walk_missing "$(jq -nc '[range(1;501)] - [400]')")"

bws_init "$TMP/sim-sl" "$(jq -nc '[range(1;301)] - [50]')" '[50]'   # 2 pages
bws_after 1 archive 250                                    # page 2 would lose card 100 …
bws_after 1 unarchive 50                                   # … and card 50 makes up the count
_walk
eq   "shift+loss walk → rc 0"                                "0"  "$_W_RC"
eq   "shift+loss walk → no card live for the whole walk is missing" "[]" \
     "$(_walk_missing "$(jq -nc '[range(1;301)] - [250, 50]')")"

bws_init "$TMP/sim-ctl" "$(jq -nc '[range(1;451)]')"
_walk
eq   "CONTROL: unchanged 3-page board → rc 0"                "0"   "$_W_RC"
eq   "CONTROL: …exactly its 450 cards"                       "450" "$(jq 'length' <<<"${_W_OUT:-[]}")"
eq   "CONTROL: …in 3 requests"                               "3"   "$(bws_calls)"

bws_init "$TMP/sim-noid" "$(jq -nc '[range(1;451)]')"
export BWS_IGNORE_ID=1; _walk; unset BWS_IGNORE_ID
eq   "a server that does not apply the id window → dies rc 2" "2" "$_W_RC"
[[ -z "$_W_OUT" ]] && ok "…and no card list reaches the mover" || bad "an unkeyed walk leaked a card list"
grep -q "outside the requested id window" "$TMP/walk.err" && ok "…naming the broken property" || bad "missing the id-window refusal"
bws_init "$TMP/sim-asc" "$(jq -nc '[range(1;451)]')"
export BWS_ORDER=asc; _walk; unset BWS_ORDER
eq   "a server answering in ASCENDING id order → dies rc 2"  "2" "$_W_RC"
[[ -z "$_W_OUT" ]] && ok "…and no card list reaches the mover" || bad "an unordered walk leaked a card list"
grep -q "not in strictly descending id order" "$TMP/walk.err" && ok "…naming the broken property" || bad "missing the id-order refusal"
# shellcheck source=/dev/null
source "$TMP/api-pages.fn"
unset -f _walk _walk_missing
unset _W_RC _W_OUT

echo "== positive control: clean two-page read, totals agree → all cards, silent =="
page1c="$(jq -nc '{"data":[range(201;1;-1)|{id:.}],"meta":{"last_page":2,"total":201}}')"
page2b='{"data":[{"id":1}],"meta":{"last_page":1,"total":1}}'
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
full1="$(jq -nc '{"data":[range(202;2;-1)|{id:.}]}')" # 200 rows, no meta whatsoever
tail2='{"data":[{"id":2},{"id":1}]}'                 # short page → n<200 terminates
_PAGES=( [1]="$full1" [2]="$tail2" )
rc=0; out="$(fetch_whole_board 2>"$TMP/nometa.err")" || rc=$?
eq   "full page + no meta → rc 0"         "0"   "$rc"
eq   "full page + no meta → paged to 202" "202" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/nometa.err" ]] && bad "no-meta full read must be silent" || ok "no-meta full read silent"

echo "== last_page=0 on a full page: out-of-range ⇒ unknown, must keep paging =="
# A non-positive last_page is not a meaningful declaration; it must not truncate the scan
# at page 1 (same class as gap #1). Full page 1 with last_page:0 and no total → page 2.
lp0="$(jq -nc '{"data":[range(201;1;-1)|{id:.}],"meta":{"last_page":0}}')"
_PAGES=( [1]="$lp0" [2]='{"data":[{"id":1}]}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/lp0.err")" || rc=$?
eq   "last_page=0 → rc 0"                 "0"   "$rc"
eq   "last_page=0 → paged to 201"         "201" "$(printf '%s' "$out" | jq 'length')"

echo "== 0 visible cards on page 1 → REFUSE (token not a board member) =="
_PAGES=( [1]='{"data":[],"meta":{"last_page":1,"total":0}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/empty.err")" || rc=$?
eq   "0 visible cards → dies rc 2"        "2"   "$rc"
grep -q "0 visible cards" "$TMP/empty.err" && ok "empty board names the membership cause" || bad "missing 0-visible-cards refusal"

echo "== an unreadable PAGE 2 → REFUSE, never promote from a truncated board (card#6630) =="
# `.data // []` answered a 2xx that carried no card ARRAY with `[]`, and `[]` is a SHORT page,
# which ENDS the loop — so a page-2 fault returned page 1's rows at rc 0 with nothing on stderr
# and this MOVER promoted from a board it had only partly read. The page-1 predicate is
# unchanged (zero CARDS, above) and deliberately still differs from the lib's; only the
# later-page hole is closed, at this tool's existing refuse policy: die.
#
# The body is VALID JSON on purpose. An unparseable one (a proxy's HTML) already exits at jq's
# own status under the script's `set -euo pipefail` — loud, and not the silent truncation this
# guards — so a fixture built from it would red for a reason that predates the fix. The shape
# below is the one that reached rc 0: a JSON error object at HTTP 200.
full1b="$(jq -nc '{"data":[range(201;1;-1)|{id:.}]}')" # full page 1, no meta ⇒ no census to catch it
_PAGES=( [1]="$full1b" [2]='{"error":"upstream connect error"}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/p2.err")" || rc=$?
eq   "unreadable page 2 → dies rc 2"      "2"   "$rc"
grep -q "page 2 returned no readable card array" "$TMP/p2.err" && ok "the refusal names the page and the cause" || bad "missing page-2 unreadable-body refusal"
grep -q "INCOMPLETE board read" "$TMP/p2.err" && ok "…and says what it refused to do" || bad "page-2 refusal does not name the incomplete read"
[[ -z "$out" ]] && ok "no partial card list escapes to the mover" || bad "page-2 fault leaked a truncated card list: '$out'"

# Same fault on a server that DOES declare meta.total: the census would have caught this one
# (that is why this install never saw the defect), and the refusal must still be the page-2 one,
# reached BEFORE the census — a card left un-promoted is the same either way, but "page 2 was
# unreadable" and "the board is bigger than what arrived" are different operator actions.
fullt="$(jq -nc '{"data":[range(201;1;-1)|{id:.}],"meta":{"last_page":2,"total":201}}')"
_PAGES=( [1]="$fullt" [2]='{"error":"upstream connect error"}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/p2t.err")" || rc=$?
eq   "unreadable page 2, meta.total present → still dies rc 2" "2" "$rc"
grep -q "page 2 returned no readable card array" "$TMP/p2t.err" && ok "the page-2 cause wins over the census wording" || bad "census message displaced the page-2 cause"

# THE CONTROL: a legitimate SHORT page 2 is how a real multi-page read ENDS. A predicate that
# cannot tell it from an unreadable body refuses every board over one page — and this block
# would pass anyway, on refusals alone.
_PAGES=( [1]="$full1b" [2]='{"data":[{"id":1}]}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/p2ok.err")" || rc=$?
eq   "CONTROL: legitimate short page 2 → rc 0"      "0"   "$rc"
eq   "CONTROL: both pages' rows are promoted from" "201" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/p2ok.err" ]] && bad "a legitimate two-page read must be silent" || ok "legitimate two-page read silent"

# THE ONE PAGE-1 ACCEPTANCE CHANGE OF THE SHARED EXTRACTION. The predicate is what EXTRACTS
# `data`, so page 1 gets it too — and for the two shapes `.data // []` passed through as a
# non-array, what the tool ACCEPTS moved. This is not a change of failure wording, and an earlier
# draft of these assertions said it was.
#
# MEASURED against `git show HEAD:bin/promote-released-cards`, this same function lifted onto this
# same stub: `{"data":{"id":9}}` and `{"data":"str"}` made `fetch_whole_board` return **rc 0 with
# EMPTY stdout**. The accumulator's `jq -c -s 'add'` did fault (status 5, `array ([]) and object
# ({"id":9}) cannot be added`) — and that fault is NON-FATAL, because `errexit` is not inherited by
# a command-substitution subshell and nothing in this repo sets `inherit_errexit`. So the caller
# `CARDS="$(fetch_whole_board)"` took an EMPTY CARD LIST at rc 0 and the script ran on, aborting
# three assignments later at `MISSING="$(jq -n --argjson md "$MATCHED_DLS" …)"` with `jq: invalid
# JSON text passed to --argjson` — a different jq, at a different site, at status 2. The PROCESS
# exit was 2 either way and nothing was PATCHed either way (both aborts precede the move loop),
# which is exactly what makes this easy to mis-describe as a wording change.
#
# The page-1 PREDICATE is unchanged (zero CARDS), so the lib/mirror divergence is intact — an empty
# ENVELOPE on page 1 still dies here and still succeeds there — and no OTHER page-1 shape moved,
# measured over six bodies against both HEAD and the fix: `{"error":…}`, `{"data":null}`,
# `{"data":[]}` and an unparseable `<html>` body all reached the zero-cards die at rc 2 before and
# still do; only these two rows moved. The die's named cause (board membership) is wrong for these
# two shapes, as it already was for the other two; that is the page-1 message's own pre-existing
# scope, recorded on card#6630 in docs/CONSOLIDATION-PLAN.md and deliberately not widened here.
for _p1 in '{"data":{"id":9}}' '{"data":"str"}'; do
  _PAGES=( [1]="$_p1" )
  rc=0; out="$(fetch_whole_board 2>"$TMP/p1.err")" || rc=$?
  eq   "page 1 $_p1 → dies rc 2 (measured pre-fix: rc 0 and an EMPTY card list — an ACCEPTANCE change)" "2" "$rc"
  [[ -z "$out" ]] && ok "  no fabricated card list reaches the mover" || bad "page-1 non-array leaked '$out'"
  grep -q '^jq:' "$TMP/p1.err" && bad "a raw jq fault still reaches stderr instead of the tool's refusal" || ok "  the refusal is the tool's own, with no jq fault on stderr"
done
unset _p1

# …and an EMPTY page 2 is a complete read too (the empty ENVELOPE is readable; it is zero rows on
# PAGE 1 that this tool refuses, and that page-1 rule is untouched).
_PAGES=( [1]="$full1b" [2]='{"data":[],"meta":{"total":200}}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/p2e.err")" || rc=$?
eq   "CONTROL: empty page 2 → rc 0"                 "0"   "$rc"
eq   "CONTROL: page 1's rows are the answer"        "200" "$(printf '%s' "$out" | jq 'length')"

_summary "promote-pagination-selftest"
