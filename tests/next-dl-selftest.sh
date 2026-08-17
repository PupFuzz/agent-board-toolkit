#!/usr/bin/env bash
# next-dl-selftest.sh — deterministic, network-free checks for next-dl: its
# highest-int-in-a-stream primitives `max_int`/`max_dl`, and its argument surface.
#
# next-dl runs its main at top level (arg-parse on source), so it is never sourced
# whole — lift just the two one-liner functions out of it (the extract-and-exercise
# pattern promote-pagination-selftest uses on fetch_whole_board). max_int is the
# shared tail of BOTH offline max scans (the CLAUDE_DECISIONS.md `## DL-NNN` header
# scan and the board `dl_number` scan); it undercounted-silently would let next-dl
# re-mint a used DL, so its leading-zero-strip and its DL-only filter are pinned here.
#
# THE ARGUMENT SURFACE HAD NO COVERAGE AT ALL until the flag-value guard was adopted,
# and `--board`'s guard was a COMPOUND condition — `[[ -n "${1:-}" && -z "$project" ]]`
# — doing two unrelated jobs at once: the value-presence test, and the "a project was
# named twice" mutual exclusion. Replacing the whole condition with kb_require_value
# deletes the second job and every test in this file still passes, because none of them
# ran the binary. That is the regression this section exists to make impossible: the two
# halves are asserted independently, by their DISTINCT messages, so collapsing them back
# into one condition reds whichever half was dropped.
#
# The binary is driven as a PROCESS against the shared curl stub (it is not main-guarded,
# so sourcing it would run it). Every refusal below is expected to exit inside the arg
# loop, before any config read or request — asserted as a zero on the stub's request log,
# each paired with the witness run at the end of the section, which shows the same harness
# DOES reach the API when the arguments are valid.
#
# WHAT A GREEN RUN PROVES — the weakest property these assertions support: that next-dl
# refuses these argument shapes with these messages and these exit codes, that a valid
# --board reaches board resolution, and that --peek prefers the inspect endpoint over the
# offline scan and falls back only when that endpoint is absent. It says nothing about the
# atomic-claim endpoint's real behaviour or the offline scan against real checkouts.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
NDL="$HERE/../bin/next-dl"
_need -x "$NDL"

# Lift the two one-liner primitives (never meant to be sourced with the whole script).
ndl_src="$(grep -E '^(max_int|max_dl)\(\) \{' "$NDL")"
[[ "$(printf '%s\n' "$ndl_src" | wc -l)" -eq 2 ]] \
    || { echo "selftest: expected to lift max_int + max_dl from $NDL — did they get renamed?" >&2; exit 1; }
eval "$ndl_src"

echo "== max_int — highest integer in a stream, leading zeros stripped =="
eq "picks the true max"                     "90" "$(printf '7\n90\n3\n'      | max_int)"
eq "ignores leading zeros when comparing"   "90" "$(printf '007\n90\n003\n'  | max_int)"
# The zero-strip is a FORMAT contract, not just ordering: sort -n reads 007 as 7 either way,
# so these red only if the `sed 's/^0*//;s/^$/0/'` is dropped (the output keeps a padded form).
eq "strips leading zeros from the winner"   "7"  "$(printf '007\n003\n'      | max_int)"
eq "a bare zero survives the strip (^\$->0)" "0"  "$(printf '0\n'            | max_int)"
eq "empty stream → empty output"            ""   "$(printf ''                | max_int)"

echo "== max_dl — only DL-prefixed tokens (a bare number must NOT leak) =="
# The DL- filter is the whole point: fed a stream that mixes prose numbers with DL tokens,
# max_dl must count ONLY the DL tokens. Reds if the 'DL-' grep is weakened to plain digits.
eq "counts only DL tokens, ignores prose ints" "40" "$(printf 'see PR 999\nDL-40\nDL-7\n' | max_dl)"
eq "strips zeros via the shared max_int tail"  "7"  "$(printf 'DL-007\n'                  | max_dl)"
eq "no DL tokens → empty"                      ""   "$(printf 'nothing to see, 123\n'     | max_dl)"

# --- the argument surface, driven as a process ------------------------------------------------
_mktmp_scratch --home
kb_stub_scrub_env
unset KB_DL_CHECKOUT_GLOBS NEXT_DL_PAGE_CAP
kb_stub_board_config dev 42
kb_stub_board_config alt 77       # a second RESOLVABLE board, so the refusals below are refusals
kb_stub_board_config bridge 88    # `bridge` is a bare project TOKEN here, resolvable for the same reason
kb_stub_install

USAGE='usage: next-dl kanban|bridge|--board <name> [--peek]'
NO_VALUE='next-dl: --board requires a non-empty value'

# The atomic claim is the DEFAULT path, so a run that gets past the arg loop lands here; the
# board read is the --peek path's fallback seed. Both are answered so the witness run below can
# assert next-dl reached the API rather than merely failing later.
kb_stub_route() {
    case "$1 $2" in
        "POST "*/dl-sequence/claim.json) printf '%s\n%s' 200 '{"data":{"value":93}}' ;;
        "GET "*/tasks/search.json*) printf '%s\n%s' 200 '{"data":[],"meta":{"last_page":1,"total":0}}' ;;
    esac
}
export -f kb_stub_route

run_ndl() {
    kb_stub_reset
    rc=0
    out="$("$NDL" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
}
# Board-QUALIFIED on purpose: the route table answers any board's claim endpoint, so a count
# that stopped at `/dl-sequence/claim.json` would stay green while --board's value was routed to
# a different board entirely (measured — it did).
CLAIM=(POST /boards/42/dl-sequence/claim.json)

echo "== --board's VALUE guard names the flag, missing and empty alike =="
# Both forms are asserted because they are different inputs: `--board` trailing leaves $1 unset,
# `--board ""` sets it empty. The old compound condition answered both with the bare usage line,
# which named none of the three ways to spell a project.
run_ndl --board
eq "a trailing --board → rc 2"                 "2" "$rc"
eq "a trailing --board names the flag"         "$NO_VALUE" "$err"
eq "a trailing --board does not leak an unbound-variable error" "false" "$(has 'unbound variable' "$err")"
run_ndl --board ""
eq "an empty --board → rc 2"                   "2" "$rc"
eq "an empty --board names the flag"           "$NO_VALUE" "$err"
# NEITHER form carries an "and it issued no request" zero, unlike the mutual-exclusion cases below.
# Measured with this guard deleted outright: a trailing --board dies on the arg loop's own closing
# `shift` (exhausted stack, `set -e`), and an empty one leaves `$project` empty and is caught by the
# `[[ -n "$project" ]]` refusal after the loop. Both zeros are held by something other than the
# guard under test, so neither can be made to fail here — and a check that cannot fail is
# decoration (canon #9). The exclusion cases below have no such backstop, so theirs are live.

echo "== PRESERVE: a project named twice is still refused, and keeps its OWN message =="
# This is the half a drop-in kb_require_value swap deletes. Each case must stay rc 2 with the
# generic usage line — a mutual-exclusion violation is not a value-guard failure, and if the two
# checks were ever re-collapsed these would either mint a DL (rc 0) or answer with $NO_VALUE.
#
# EVERY --board here names a board the fixture can RESOLVE, deliberately. Against an unknown
# board name the run would die at config resolution anyway, and the "mints nothing"/"issues no
# request" assertions would pass on a deleted exclusion — measured: they did. With `dev`/`alt`
# resolvable, dropping the exclusion mints DL-0093 and issues a claim, so those zeros are live.
for args in "kanban --board dev" "--board dev kanban" "kanban bridge" "--board dev --board alt"; do
    # shellcheck disable=SC2086  # deliberate word-split: each case is a distinct argv
    run_ndl $args
    eq "next-dl $args → rc 2"                  "2" "$rc"
    eq "next-dl $args prints the usage line"   "$USAGE" "$err"
    eq "next-dl $args is NOT reported as a value-guard failure" "false" "$(has 'requires a non-empty value' "$err")"
    eq "next-dl $args mints nothing"           "" "$out"
    eq "next-dl $args issues no request"       "0" "$(kb_stub_total)"
done

echo "== when BOTH halves would refuse, presence still answers first =="
# The old single condition short-circuited `-n "${1:-}"` before `-z "$project"`, so an empty
# value won even with the slot already full. The split keeps that order deliberately; this pins
# it, because two sequential checks make the order a choice where `&&` made it automatic.
run_ndl kanban --board ""
eq "an empty --board after a project → rc 2"   "2" "$rc"
eq "an empty --board after a project reports the VALUE failure" "$NO_VALUE" "$err"

echo "== the witness: valid arguments DO reach the board =="
# Pairs with every "issues no request" zero above. It also proves the guard did not eat the
# happy path: the value reaches board resolution (board 42's claim endpoint, not another board's).
run_ndl --board dev
eq "--board dev → rc 0"                        "0" "$rc"
eq "--board dev mints the claimed number"      "DL-0093" "$out"
eq "--board dev claimed against board 42"      "1" "$(kb_stub_count "${CLAIM[@]}")"
eq "--board dev issued exactly one request"    "1" "$(kb_stub_total)"

# --- --peek prefers the authoritative NON-CONSUMING counter (card#6232) ------------------------
# THE DEFECT, reproduced network-free in the exact shape it was measured in: --peek used to go
# straight to the offline max+1 scan, which maxes over DLs that reached a CARD. A number that was
# CLAIMED but never STAMPED is invisible to that scan, so it under-reports by one per burned claim
# and hands back an ALREADY-ALLOCATED number. On the real board it returned DL-0220 against an
# authoritative next of 222.
#
# WHY THIS PAIR IS A CONTROL AND NOT TWO PASSES. Both cases below run against BYTE-IDENTICAL board
# contents — one card stamped DL-0219, so the offline scan's answer is 220 either way. The ONLY
# variable is whether the inspect endpoint answers. Endpoint present ⇒ 222 (the counter's truth);
# endpoint absent ⇒ 220 (the scan's floor). A fix that ignored the endpoint would return 220 for
# both and red the first assertion; a "fix" that broke the fallback would return nothing for the
# second. Neither can pass by accident, and 222 is not derivable from the board contents at all.
NDL_BOARD_CARDS='{"data":[{"id":7,"payload":{"dl_number":"DL-0219"}}],"meta":{"last_page":1,"total":1}}'
kb_stub_route() {
    case "$1 $2" in
        "GET "*/boards/42/dl-sequence.json*)
            printf '%s\n%s' "${NDL_PEEK_HTTP:-200}" "${NDL_PEEK_BODY:-'{"data":{"next":222}}'}" ;;
        "POST "*/dl-sequence/claim.json) printf '%s\n%s' 200 '{"data":{"value":93}}' ;;
        "GET "*/tasks/search.json*)       printf '%s\n%s' 200 "$NDL_BOARD_CARDS" ;;
    esac
}
export -f kb_stub_route
export NDL_BOARD_CARDS
INSPECT=(GET /boards/42/dl-sequence.json)
CLAIM_URL=/dl-sequence/claim.json
SEARCH=/tasks/search.json

echo "== --peek reads the authoritative counter, NOT the card-derived floor =="
NDL_PEEK_HTTP=200 NDL_PEEK_BODY='{"data":{"next":222}}' run_ndl --board dev --peek
eq "endpoint present → rc 0"                        "0" "$rc"
# 222 exists ONLY in the counter. The board's cards top out at DL-0219, so a scan-derived
# answer is necessarily 220 — this value cannot be reached by the path being replaced.
eq "endpoint present → the counter's next, not max+1" "DL-0222" "$out"
eq "endpoint present → the inspect endpoint was read" "1" "$(kb_stub_count "${INSPECT[@]}")"
# NON-CONSUMING is the whole contract of --peek: a claim here would burn a number per peek.
eq "--peek claims NOTHING"                          "0" "$(kb_stub_count_any "$CLAIM_URL")"
# The scan is not merely unused-for-the-answer, it is not even reached — no wasted board read.
eq "--peek does not fall through to the scan"       "0" "$(kb_stub_count_any "$SEARCH")"

echo "== CONTROL: same board contents, endpoint ABSENT → the offline floor, as before =="
NDL_PEEK_HTTP=404 NDL_PEEK_BODY='{"message":"not found"}' run_ndl --board dev --peek
eq "endpoint 404 → rc 0 (benign fallback)"          "0" "$rc"
eq "endpoint 404 → falls back to the card-derived max+1" "DL-0220" "$out"
eq "endpoint 404 → the scan WAS consulted"          "1" "$(kb_stub_count_any "$SEARCH")"
eq "endpoint 404 → still claims nothing"            "0" "$(kb_stub_count_any "$CLAIM_URL")"

echo "== a PRESENT-but-errored endpoint aborts — it never answers from the floor =="
# Mirrors the claim path's rc-3 discipline. Answering 220 here would be the worst outcome of
# all: a plausible, wrong, already-allocated number minted into a decision log on a bad token.
NDL_PEEK_HTTP=500 NDL_PEEK_BODY='{"message":"boom"}' run_ndl --board dev --peek
eq "endpoint 500 → rc 1"                            "1" "$rc"
eq "endpoint 500 → mints nothing"                   ""  "$out"
eq "endpoint 500 → says the endpoint is present but failed" "true" "$(has 'PRESENT but FAILED' "$err")"
eq "endpoint 500 → names the HTTP status"           "true" "$(has 'HTTP 500' "$err")"
eq "endpoint 500 → does NOT silently answer from the scan" "0" "$(kb_stub_count_any "$SEARCH")"

echo "== a 2xx carrying no usable value is a BENIGN fallback, not an abort =="
# Deliberately the claim path's semantics, not the 500 path's: a 2xx with no number means the
# route exists but told us nothing, which is indistinguishable from an older shape — falling
# back is right, aborting would break every pre-inspect-endpoint board.
NDL_PEEK_HTTP=200 NDL_PEEK_BODY='{"data":{}}' run_ndl --board dev --peek
eq "2xx with no .data.next → rc 0"                  "0" "$rc"
eq "2xx with no .data.next → the offline floor"     "DL-0220" "$out"

echo "== the DEFAULT (claim) path is untouched by the --peek change =="
# Regression guard for the sibling `if`: the claim block must still win when --peek is absent,
# and must NOT read the inspect endpoint.
run_ndl --board dev
eq "no --peek → still the atomic claim"             "DL-0093" "$out"
eq "no --peek → claimed exactly once"               "1" "$(kb_stub_count_any "$CLAIM_URL")"
eq "no --peek → never touches the inspect endpoint" "0" "$(kb_stub_count "${INSPECT[@]}")"

echo "== the claim path's ERROR arms survive the shared-transport extraction =="
# The two routes now share one transport (card#6232), so the claim's 404-vs-errored split is
# no longer its own code and could regress silently while the happy path above stayed green.
# Its rc-3 message is BUILT from arguments now, so the label and the consequence clause are
# assertable text rather than a literal — a swapped argument pair would hand the operator the
# peek endpoint's reasoning for a claim failure.
kb_stub_route() {
    case "$1 $2" in
        "POST "*/dl-sequence/claim.json) printf '%s\n%s' "${NDL_CLAIM_HTTP:-200}" "${NDL_CLAIM_BODY:-'{"data":{"value":93}}'}" ;;
        "GET "*/tasks/search.json*)      printf '%s\n%s' 200 "$NDL_BOARD_CARDS" ;;
    esac
}
export -f kb_stub_route

NDL_CLAIM_HTTP=404 NDL_CLAIM_BODY='{"message":"not found"}' run_ndl --board dev
eq "claim 404 → rc 0, falls back to the scan"       "0" "$rc"
eq "claim 404 → mints the offline floor"            "DL-0220" "$out"

NDL_CLAIM_HTTP=500 NDL_CLAIM_BODY='{"message":"boom"}' run_ndl --board dev
eq "claim 500 → rc 1"                               "1" "$rc"
eq "claim 500 → mints nothing"                      ""  "$out"
eq "claim 500 → names the CLAIM endpoint, not the inspect one" "true" "$(has 'atomic claim endpoint is PRESENT but FAILED' "$err")"
eq "claim 500 → carries the claim's own consequence clause"    "true" "$(has 'not atomic and could re-mint on a shared board' "$err")"
eq "claim 500 → does NOT borrow the peek's reasoning"          "false" "$(has 'claimed-but-unstamped' "$err")"
eq "claim 500 → never falls through to the scan"    "0" "$(kb_stub_count_any "$SEARCH")"

# --- a CONFIGURED board that cannot be read REFUSES the mint (card#6631) -----------------------
# THE DEFECT, reproduced network-free: with the claim endpoint absent, next-dl fell through to the
# offline max+1 scan, and a board read that returned NOTHING (paginator rc 1) was fail-soft — the
# board's DL floor was dropped and the number was minted from the local CLAUDE_DECISIONS.md scan
# alone. It was the one non-zero paginator rc that fail-softed; no ranking against the other three
# is claimed, because rc 2 emits nothing as well (only rc 3 and rc 4 emit a partial array). The
# operator ruling on card#6631 withdrew offline allocation as a contract, so rc 1 now refuses
# like 2/3/4.
#
# WHY THESE LEGS CAN FAIL, which is the whole reason for the local-floor fixture below. With no
# checkout glob the offline scan finds nothing, and next-dl exits 1 with empty stdout on the
# "no DL headers found" refusal — MEASURED identical to the fix on rc and on stdout (both rc 1,
# both empty), differing only in the stderr line. Every rc/stdout assertion here would therefore
# have passed against the unfixed binary, leaving the policy asserted by its message alone. A
# local floor of DL-0300 makes the unfixed behaviour an observable MINT (DL-0301, since 300 >
# the board's 219). Measured both ways before this block was trusted: reverting the arm to
# `exit 1` reds 6 of these assertions, and restoring it byte-identically greens them.
_ndl_checkout="$TMP/pm-checkout"
mkdir -p "$_ndl_checkout"
printf '## DL-0300 — a local header the offline scan will find\n' > "$_ndl_checkout/CLAUDE_DECISIONS.md"
export KB_DL_CHECKOUT_GLOBS="$_ndl_checkout"

# The claim endpoint is ABSENT throughout this block (404 ⇒ the benign fallback), so every run
# below reaches the offline scan — which is the only path on which the board read is consulted.
kb_stub_route() {
    case "$1 $2" in
        "POST "*/dl-sequence/claim.json) printf '%s\n%s' 404 '{"message":"not found"}' ;;
        "GET "*page=2*) printf '%s\n%s' "${NDL_PAGE2_HTTP:-200}" "${NDL_PAGE2_BODY:-{\"data\":[]\}}" ;;
        "GET "*/tasks/search.json*) printf '%s\n%s' "${NDL_SEARCH_HTTP:-200}" "${NDL_SEARCH_BODY:-$NDL_BOARD_CARDS}" ;;
    esac
}
export -f kb_stub_route

echo "== CONTROL: the same fixture with a READABLE board still mints the offline floor =="
# Pairs with every refusal below: it shows the fallback path is reachable, that the local floor
# is live (301 = 300 + 1, a value only the header scan can supply), and that the change did not
# turn a legitimate offline mint into a refusal.
NDL_SEARCH_HTTP=200 NDL_SEARCH_BODY="$NDL_BOARD_CARDS" run_ndl --board dev
eq "readable board → rc 0"                          "0" "$rc"
eq "readable board → mints local-floor + 1"         "DL-0301" "$out"
eq "readable board → the scan WAS consulted"        "1" "$(kb_stub_count_any "$SEARCH")"

echo "== page 1 non-2xx (paginator rc 1) → REFUSE, do not mint from the local floor =="
NDL_SEARCH_HTTP=500 NDL_SEARCH_BODY='{"message":"boom"}' run_ndl --board dev
eq "page-1 500 → rc 1"                              "1" "$rc"
eq "page-1 500 → mints NOTHING"                     ""  "$out"
eq "page-1 500 → does not answer from the local floor" "false" "$(has 'DL-0301' "$out$err")"
eq "page-1 500 → says the board could not be read at all" "true" "$(has 'could not be read at all' "$err")"
eq "page-1 500 → says it is refusing"               "true" "$(has 'refusing to mint from the local scan alone' "$err")"
eq "page-1 500 → does NOT claim it skipped the board check" "false" "$(has 'skipping board check' "$err")"

echo "== page 1 is a 2xx carrying no card array (card#6594's cause, same rc 1) → REFUSE =="
# The cause that made this residual worth closing: a REACHABLE board answering 200 with a proxy's
# HTML error page. Distinct input, same arm — asserted separately because a fix keyed on the
# status alone would pass the 500 leg above and still mint here.
NDL_SEARCH_HTTP=200 NDL_SEARCH_BODY='<html><head><title>502 Bad Gateway</title></head><body>502</body></html>' run_ndl --board dev
eq "200 + <html>502</html> → rc 1"                  "1" "$rc"
eq "200 + <html>502</html> → mints NOTHING"         ""  "$out"
eq "200 + <html>502</html> → does not answer from the local floor" "false" "$(has 'DL-0301' "$out$err")"
eq "200 + <html>502</html> → names the rc-1 causes"  "true" "$(has 'a 2xx carrying no card array' "$err")"

echo "== a LATER page failing (paginator rc 2) still refuses, in its OWN words =="
# Unchanged behaviour, asserted here because the two arms now share one policy and differ only in
# wording: collapsing them would lose the cause set rc 1 alone is entitled to name, and the
# fetch-board-cards-caller-claims registry would no longer describe the tree.
NDL_SEARCH_BODY="$(jq -nc '{"data":[range(200)|{id:.,payload:{dl_number:219}}],"meta":{"total":400}}')" \
NDL_PAGE2_HTTP=500 NDL_PAGE2_BODY='{"message":"boom"}' run_ndl --board dev
eq "page-2 500 → rc 1"                              "1" "$rc"
eq "page-2 500 → mints NOTHING"                     ""  "$out"
eq "page-2 500 → names the rc, not a cause"         "true" "$(has 'did not return a complete card list (fetch rc=2)' "$err")"
eq "page-2 500 → keeps the partial-scan wording"    "true" "$(has 'refusing to mint from a partial scan' "$err")"
eq "page-2 500 → does not borrow the rc-1 arm's causes" "false" "$(has 'could not be read at all' "$err")"

echo "== an UNCONFIGURED board is NOT a board that failed to answer — it still mints =="
# The stated bound of card#6631's ruling. With no resolvable board env, resolve_board_cfg fails
# and board_dl_max exits 1 (not 2), so the local floor still mints. If this ever reds, the
# refusal has widened past the ruling and every board-less checkout has lost its allocator.
run_ndl --board nosuchboard
eq "no board env → rc 0"                            "0" "$rc"
eq "no board env → mints local-floor + 1"           "DL-0301" "$out"
eq "no board env → says it is skipping the board check" "true" "$(has 'skipping board check' "$err")"
eq "no board env → never reached the API"           "0" "$(kb_stub_total)"

unset KB_DL_CHECKOUT_GLOBS

_summary "next-dl-selftest"
