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
_adopt_fn "$PRC" fetch_whole_board

# …and the file-scope helpers it calls. Lifting the REAL uint_ok rather than stubbing one
# keeps this exercising the shipped numeric check (which matches under LC_ALL=C, because a
# bare `*[!0-9]*` glob range is a COLLATION range — card#5409). An UNLIFTED helper does not
# fail loudly: the call returns 127, the census silently no-ops, and the only tell is a
# "command not found" on a stream some cases don't read — so the extraction is asserted.
uint_src="$(grep -E '^uint_ok\(\)' "$PRC" || true)"   # `|| true`: under set -e a no-match
                                                     # grep kills the run before the message
[[ -n "$uint_src" ]] || { echo "selftest: could not extract uint_ok from $PRC — did it get renamed?" >&2; exit 1; }
eval "$uint_src"

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
full1b="$(jq -nc '{"data":[range(200)|{id:.}]}')"      # full page 1, no meta ⇒ no census to catch it
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
fullt="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":201}}')"
_PAGES=( [1]="$fullt" [2]='{"error":"upstream connect error"}' )
rc=0; out="$(fetch_whole_board 2>"$TMP/p2t.err")" || rc=$?
eq   "unreadable page 2, meta.total present → still dies rc 2" "2" "$rc"
grep -q "page 2 returned no readable card array" "$TMP/p2t.err" && ok "the page-2 cause wins over the census wording" || bad "census message displaced the page-2 cause"

# THE CONTROL: a legitimate SHORT page 2 is how a real multi-page read ENDS. A predicate that
# cannot tell it from an unreadable body refuses every board over one page — and this block
# would pass anyway, on refusals alone.
_PAGES=( [1]="$full1b" [2]='{"data":[{"id":200}]}' )
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
