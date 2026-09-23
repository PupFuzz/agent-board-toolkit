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
# --board reaches board resolution, that --peek prefers the inspect endpoint over the
# offline scan and falls back only when that endpoint is absent, that an undecodable 2xx AND a
# dead transport each take the fallback on the non-consuming read while REFUSING on the consuming
# claim, and that a MISWIRED call site — the argument omitted, or its value misspelled — refuses
# rather than minting (card#10230) — all against a stub. It says nothing about the atomic-claim
# endpoint's real behaviour or the offline scan against real checkouts, and it cannot say
# anything about what a CALLER then stamps: `tests/adopt-to-dl-selftest.sh` owns that half, driving the
# real next-dl and asserting no card is written.
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

USAGE='usage: next-dl kanban|bridge|--board <name> [--peek] [--require-counter]'
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
# Sibling of the card#6645 class, closed by the same shared gate. `--board` is this bin's whole
# value-taking population today, so the two assertions below cover it — and nothing here could
# notice a second flag arriving. `expect_value_flags` derives the population from the bin's own
# guard call sites and reds in both directions.
expect_value_flags "$NDL" --board
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

echo "== a 2xx carrying no usable value is a BENIGN fallback on the NON-CONSUMING read =="
# Not the 500 path's semantics: a 2xx with no number means the route exists but told us nothing,
# which is indistinguishable from an older shape — falling back is right on a call that spent
# NOTHING, and aborting would break every pre-inspect-endpoint board. ⛔ This is NOT the claim
# path's semantics, and asserting that it was is what shipped card#10230: on the claim a number
# may already be burned, so that arm refuses (the matrix near the end of this file owns both).
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
# ⛔ AND THE "CAUSE" IT NAMES IS THE REAL ONE, not a list (card#7245). This line used to
# enumerate kb_resolve_env's rcs 3/4/5 longhand — a copy of a contract that had since grown
# rcs 6 (an api host nobody declared) and 7 (no token file declared), so the two newest causes
# printed five reasons that were all false. Under --require-counter it is the ONLY thing the
# operator gets: that mode refuses before the offline scan's unmuted board read, and its
# refusal ends "Fix the cause above", which the enumeration made unactionable.
eq "no board env → does NOT enumerate causes it did not check" "false" \
   "$(has 'a board env that sets KBCARD_API' "$err")"
run_ndl --board nosuchboard --require-counter
eq "strict + no board env → refuses at rc 4"        "4" "$rc"
eq "strict + no board env → mints NOTHING"          ""  "$out"
eq "strict + no board env → still no enumeration"   "false" \
   "$(has 'a board env that sets KBCARD_API' "$err")"
# The relay itself: resolve_board_cfg's OWN reason reaches the operator in the mode where
# nothing else will print it. Without the relay this is the arm that said "Fix the cause
# above" with no cause above it.
eq "strict + no board env → relays the actual reason" "true" \
   "$(has 'skipping board check' "$err")"
eq "strict + no board env → and still says what it refused" "true" \
   "$(has 'refusing to mint' "$err")"

# --- the fallback is ANNOUNCED, and --require-counter refuses it (card#7214) -------------------
# THE DEFECT, reproduced network-free: with the counter endpoint unavailable, next-dl printed a
# number from the non-atomic offline max+1 scan at rc 0 with an EMPTY stderr — byte-identical, on
# every channel a caller can read, to an atomic claim. Two concurrent allocators were handed the
# same DL by the tool whose whole purpose is to stop that, and nothing said so.
#
# WHY THE CAUSE MATRIX IS THE POINT AND NOT DECORATION. The CAUSES are what `NDL_CAUSES` holds,
# and the rc does not separate them: every one of them can reach the caller as the same
# exit code, so the stderr line is the ONLY place they are distinguishable. A "stderr is
# non-empty" assertion would be satisfied by one generic line, which re-mints the conflation this
# card is about — so each cause asserts its OWN phrase present AND every OTHER cause ABSENT.
# MEASURED, against every `unusable` argument in the bin rewritten to one shared string: since
# card#10230's third round the collapse reds the DERIVATION legs below before the matrix is even
# reached — all four distinctness assertions (identical needles), then all four key binds (no key
# matches the generic string), and then the run aborts at the plant guard, because the sed that
# targets a named cause line now matches nothing. That abort is the guard working, not a defect.
# Before the derivation it reddened only matrix assertions, and only by luck of wording.
#
# ⛔ THE CAUSE SET AND THE rc-1 SET ARE NOT THE SAME SET, and reading them as one is what shipped
# card#10230 (twice). Every cause still prints its own line on both routes — that is what
# `only_cause` holds. But on the CONSUMING claim two of them (unreachable, and a 2xx carrying no
# usable value) exit 3 and abort rather than exiting 1 and degrading, because the call may have
# spent a number. So a leg here asserts the cause line and the DISPOSITION separately; a matrix
# that read one off the other would go green on the defect.
#
# The fixture is the card#6631 block's, deliberately: a local floor of DL-0300 over a board whose
# cards top out at DL-0219, so the offline answer is DL-0301 — a value the counter never returns
# (its claim is 93), so "it degraded" and "it claimed" are never the same number.
FALLBACK='FALLING BACK to the offline max+1 scan'
REFUSAL='--require-counter: refusing to mint'

# --- the cause set is DERIVED FROM THE BIN, not restated here (card#10230, round 3) ------------
# It used to be a hand-written array, so bin/next-dl's rc-1 contract — "Any new way to reach
# exit 1 from here owes a distinct `unusable` cause" — was checked by NOTHING: this file's idea
# of the cause set came from this file, so a FIFTH cause added to dl_sequence_call reddened not
# one leg here. The population now comes from that function's own `unusable` call sites, is
# re-derived on every run, and the COVERAGE leg at the very end of this file reds when a derived
# cause is driven by no leg above. That leg, not this comment, is the :298 guarantee's control.
#
# THE REDUCTION RULE, stated because a derived needle has to be usable by `has`, which is a
# LITERAL substring test: a cause argument may interpolate ($http, $field), and an interpolated
# string is not a literal — so each needle is the LONGEST run of its argument carrying no
# $-expansion, trimmed. Non-empty, $-free and mutually DISTINCT are asserted below rather than
# assumed; degeneracy is additionally self-detecting, since a needle short enough to appear in
# every message reds only_cause's ABSENCE half everywhere at once.
ndl_fn_body() {   # <file> — dl_sequence_call's body, lifted (the bin runs its main at top level)
    LC_ALL=C awk '
        /^dl_sequence_call\(\) \($/ { infn = 1; next }
        infn && /^\)$/              { infn = 0; next }
        infn                        { print }
    ' "$1"
}
ndl_cause_args() {   # <file> — the ARGUMENT of every `unusable "…"` call in that body, in order
    ndl_fn_body "$1" | sed -n 's/^[[:space:]]*unusable "\(.*\)"[[:space:]]*$/\1/p'
}
ndl_cause_needle() {   # <argument> — its longest $-expansion-free run, trimmed
    LC_ALL=C awk '{
        n = split($0, seg, "$"); best = ""
        for (i = 1; i <= n; i++) {
            s = seg[i]
            if (i > 1) { sub(/^\{[^}]*\}/, "", s); sub(/^[A-Za-z_][A-Za-z0-9_]*/, "", s) }
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (length(s) > length(best)) best = s
        }
        print best
    }' <<<"$1"
}
# ndl_planted <sed-expr> — a scratch COPY of bin/next-dl carrying <sed-expr>, for the STATIC legs
# (they READ a file and never run it, so no scratch bin/ is needed — that is ndl_mutant's job).
# Refuses a sed that changed nothing, for ndl_mutant's reason: a no-op plant would make every
# assertion downstream of it a measurement of the shipped file wearing a mutant's name.
NDL_PLANT="$TMP/ndl-planted"
ndl_planted() {
    cp -p "$NDL" "$NDL_PLANT"
    sed -i "$1" "$NDL_PLANT"
    if cmp -s "$NDL" "$NDL_PLANT"; then
        echo "selftest: plant '$1' changed nothing in $NDL — did the site it targets move?" >&2
        exit 1
    fi
}

NDL_CAUSE_ARGS=(); NDL_CAUSES=()
while IFS= read -r _a; do
    NDL_CAUSE_ARGS+=("$_a")
    NDL_CAUSES+=("$(ndl_cause_needle "$_a")")
done < <(ndl_cause_args "$NDL")
unset _a
declare -A NDL_CAUSE_IX=()
NDL_CAUSE_SEEN=()

# The KEYS below NAME the cause a leg drives; they are NOT the population. Each must resolve to
# exactly ONE derived cause — a GUARDED restatement rather than a second copy of the set: a key
# that stops matching (or starts matching two) reds the bind below, and a CAUSE that no key names
# reds the coverage leg at the end. The hand-written array covered neither direction.
C_CONFIG='config could not be resolved'
C_TRANSPORT='could not be REACHED'
C_ABSENT='NOT DEPLOYED'
C_UNDECODABLE='carried no usable number'
NDL_CAUSE_KEYS=("$C_CONFIG" "$C_TRANSPORT" "$C_ABSENT" "$C_UNDECODABLE")

echo "== the cause set is DERIVED from bin/next-dl's own unusable() call sites =="
# Vacuity first: a lift that found the wrong span, or nothing, would make every leg below pass by
# measuring an empty set. The landmark is the shared refusal, which only this function defines.
eq "the lift really got dl_sequence_call's body" "true" \
   "$(has 'spent_refusal() {' "$(ndl_fn_body "$NDL")")"
eq "the lift stopped at the function (it did not swallow the caller)" "false" \
   "$(has 'degrade_or_refuse "atomic claim endpoint"' "$(ndl_fn_body "$NDL")")"
eq "at least one cause was derived" "true" \
   "$([[ ${#NDL_CAUSES[@]} -gt 0 ]] && echo true || echo false)"
for _i in "${!NDL_CAUSES[@]}"; do
    eq "derived needle [$_i] is non-empty" "true" \
       "$([[ -n "${NDL_CAUSES[$_i]}" ]] && echo true || echo false)"
    eq "derived needle [$_i] survives as a LITERAL (no \$-expansion left in it)" "false" \
       "$(has '$' "${NDL_CAUSES[$_i]}")"
    _dup=0
    for _j in "${!NDL_CAUSES[@]}"; do
        [[ "$_i" == "$_j" ]] && continue
        [[ "${NDL_CAUSES[$_j]}" == *"${NDL_CAUSES[$_i]}"* ]] && _dup=1
    done
    eq "derived needle [$_i] is DISTINCT from every other (only_cause's absence half needs it)" \
       "0" "$_dup"
done
unset _i _j _dup
for _k in "${NDL_CAUSE_KEYS[@]}"; do
    _n=0; _want=-1
    for _i in "${!NDL_CAUSE_ARGS[@]}"; do
        [[ "${NDL_CAUSE_ARGS[$_i]}" == *"$_k"* ]] && { _want=$_i; _n=$((_n + 1)); }
    done
    eq "cause key '$_k' still identifies exactly ONE derived cause" "1" "$_n"
    NDL_CAUSE_IX["$_k"]=$_want
done
unset _i _k _n _want

# ⭐ POSITIVE CONTROL — the derivation READS the bin. Without this the whole scheme could be a
# constant wearing a derivation's name, and every leg above would be green for it. Both
# directions, and neither side of either assertion is a written figure: the expected value is
# computed from the SHIPPED derivation, so this cannot be re-synced by editing a number.
_PLANTED_CAUSE='is a PLANTED fifth cause that no leg drives'
ndl_planted "/^        404)/i\\            unusable \"$_PLANTED_CAUSE\""
eq "planting a fifth unusable() call derives one cause MORE" \
   "$(( ${#NDL_CAUSES[@]} + 1 ))" "$(ndl_cause_args "$NDL_PLANT" | wc -l | tr -d ' ')"
eq "…and the planted cause is what is new there" "true" \
   "$(has "$_PLANTED_CAUSE" "$(ndl_cause_args "$NDL_PLANT")")"
eq "…and it is absent from the shipped set (so the comparison is not vacuous)" "false" \
   "$(has "$_PLANTED_CAUSE" "$(ndl_cause_args "$NDL")")"
# ⭐ AND THE COVERAGE LEG WOULD RED ON IT: no existing key names the planted cause, so it derives
# into the population with nothing driving it, which is exactly the end-of-file assertion.
_pk=0
for _k in "${NDL_CAUSE_KEYS[@]}"; do
    [[ "$_PLANTED_CAUSE" == *"$_k"* ]] && _pk=1
done
eq "no cause key binds the planted fifth cause (so the coverage leg RED on it is real)" "0" "$_pk"
unset _k _pk _PLANTED_CAUSE
ndl_planted '/^            unusable "is NOT DEPLOYED/d'
eq "deleting an unusable() call derives one cause FEWER" \
   "$(( ${#NDL_CAUSES[@]} - 1 ))" "$(ndl_cause_args "$NDL_PLANT" | wc -l | tr -d ' ')"
rm -f "$NDL_PLANT"

# only_cause <label> <cause-key|none> <stderr> — the anti-generic-line control. The key NAMES the
# cause this leg drives; the phrase asserted is the DERIVED one, so a derivation that broke would
# red here rather than quietly assert nothing.
only_cause() {
    local label="$1" key="$2" errtext="$3" i want=-1
    if [[ "$key" != none ]]; then
        want="${NDL_CAUSE_IX[$key]:--1}"
        [[ "$want" -ge 0 ]] && NDL_CAUSE_SEEN[$want]=1
    fi
    for i in "${!NDL_CAUSES[@]}"; do
        if [[ "$i" == "$want" ]]; then
            eq "$label names its own cause (${NDL_CAUSES[$i]})" "true" "$(has "${NDL_CAUSES[$i]}" "$errtext")"
        else
            eq "$label does NOT borrow '${NDL_CAUSES[$i]}'"      "false" "$(has "${NDL_CAUSES[$i]}" "$errtext")"
        fi
    done
}

# One route table for the whole block; each cause is selected by exported variable. The claim and
# the inspect route are both switchable so the peek path is exercised through the same causes.
kb_stub_route() {
    case "$1 $2" in
        "POST "*/dl-sequence/claim.json)
            if [[ -n "${NDL_CLAIM_CURLFAIL:-}" ]]; then printf '!curl %s' "$NDL_CLAIM_CURLFAIL"
            else printf '%s\n%s' "$NDL_CLAIM_HTTP" "$NDL_CLAIM_BODY"; fi ;;
        "GET "*/boards/42/dl-sequence.json*)
            if [[ -n "${NDL_PEEK_CURLFAIL:-}" ]]; then printf '!curl %s' "$NDL_PEEK_CURLFAIL"
            else printf '%s\n%s' "$NDL_PEEK_HTTP" "$NDL_PEEK_BODY"; fi ;;
        "GET "*/tasks/search.json*) printf '%s\n%s' 200 "$NDL_BOARD_CARDS" ;;
    esac
}
export -f kb_stub_route
export NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{"value":93}}'
export NDL_PEEK_HTTP=200 NDL_PEEK_BODY='{"data":{"next":222}}'
export NDL_CLAIM_CURLFAIL="" NDL_PEEK_CURLFAIL=""

echo "== POSITIVE WITNESS: --require-counter still gets an ATOMIC CLAIM when the endpoint answers =="
# PAIRED WITH EVERY REFUSAL BELOW, and the reason this file cannot pass by breaking the tool: a
# next-dl that refused unconditionally would satisfy every strict leg and every fail-closed leg
# below perfectly. This leg is the one that fails for it — the claim is issued, its number is
# minted, and nothing degrades.
run_ndl --board dev --require-counter
eq "endpoint present + strict → rc 0"                 "0" "$rc"
eq "endpoint present + strict → the CLAIMED number"   "DL-0093" "$out"
eq "endpoint present + strict → claimed against board 42" "1" "$(kb_stub_count "${CLAIM[@]}")"
eq "endpoint present + strict → no refusal"           "false" "$(has "$REFUSAL" "$err")"
eq "endpoint present + strict → no fallback notice"   "false" "$(has "$FALLBACK" "$err")"
only_cause "endpoint present + strict" none "$err"
eq "endpoint present + strict → never reaches the scan" "0" "$(kb_stub_count_any "$SEARCH")"

echo "== PERMISSIVE is unchanged where the endpoint answers — no new stderr on the happy path =="
# The compat claim the CHANGELOG makes ("nothing changes for an existing caller, except stderr
# gains a line on the degraded path") is asserted, not asserted-about: a run that does NOT degrade
# must gain nothing at all.
run_ndl --board dev
eq "endpoint present, permissive → rc 0"              "0" "$rc"
eq "endpoint present, permissive → the claimed number" "DL-0093" "$out"
eq "endpoint present, permissive → stderr still SILENT" "" "$err"

echo "== cause 3 (404 ABSENT): permissive mints LOUDLY, strict REFUSES =="
NDL_CLAIM_HTTP=404 NDL_CLAIM_BODY='{"message":"not found"}' run_ndl --board dev
eq "404 permissive → rc 0"                            "0" "$rc"
eq "404 permissive → still mints the offline floor"   "DL-0301" "$out"
eq "404 permissive → announces the fallback"          "true" "$(has "$FALLBACK" "$err")"
eq "404 permissive → names the CLAIM endpoint in the notice" "true" "$(has 'atomic claim endpoint gave no number' "$err")"
eq "404 permissive → offers the opt-out"              "true" "$(has 'Pass --require-counter' "$err")"
only_cause "404 permissive" "$C_ABSENT" "$err"

NDL_CLAIM_HTTP=404 NDL_CLAIM_BODY='{"message":"not found"}' run_ndl --board dev --require-counter
eq "404 strict → rc 4"                                "4" "$rc"
eq "404 strict → mints NOTHING"                       "" "$out"
eq "404 strict → says it is refusing"                 "true" "$(has "$REFUSAL" "$err")"
eq "404 strict → does NOT announce a fallback it did not take" "false" "$(has "$FALLBACK" "$err")"
eq "404 strict → does not leak the floor anywhere"    "false" "$(has 'DL-0301' "$out$err")"
only_cause "404 strict" "$C_ABSENT" "$err"
eq "404 strict → never reads the board at all"        "0" "$(kb_stub_count_any "$SEARCH")"

echo "== cause 2 (TRANSPORT failure): distinct from 404 — nothing was learned about the route =="
# curl exits non-zero with no status. Reporting that as "not deployed" would be a fabricated
# finding about the server, which is card#7210's class: a failed read scored as a usable negative.
# THE CAUSE is one cause on both routes and still gets its own line. What differs is the
# DISPOSITION — and card#10230's SECOND round is that it used not to.
#
# ⛔ THIS IS THE ARM THE FIRST FIX MISSED, and it is the whole reason the ruling is now stated
# over the arm SET rather than per arm. Round 1 closed the 2xx-undecodable arm and left this one
# taking the benign fallback, so an ordinary network flake on the claim POST still minted from
# the offline scan: measured against that head, `NDL_CLAIM_CURLFAIL=52` and `=28` each gave
# `rc 0` and `DL-0301` — the identical defect, on an adjacent arm of the same function, with the
# whole suite green because no leg here drove the CONSUMING route's transport cell at all.
#
# WHY A CONSUMING CALL REFUSES ON EVERY curl rc AND NOT ON A CHOSEN SUBSET. A non-zero curl exit
# means the request DID NOT COMPLETE, which is not evidence that it never arrived: 52 (empty
# reply), 56 (recv failure) and 28 (timeout) all name a POST the server may have applied before
# the answer was lost. Splitting the rcs into "cannot have reached it" (5/6/7) and "may have"
# would put a copy of curl's exit-code table in bin/next-dl, and would buy nothing — where the
# host is genuinely unreachable the offline scan's own board read fails too (card#6631). So
# rc 7 is driven HERE beside 52 and 28: a fix that classified curl's rc into "cannot have reached
# the server" (5/6/7) and "may have" (everything else) would leave the 52 and 28 legs GREEN and
# turn THIS one RED, which is the discrimination the three-value loop exists to make — so rc 7 is
# the leg that catches that fix, and 52/28 are the ones that do not.
# ⛔ THAT SENTENCE USED TO SAY THE OPPOSITE ("keep 52 and 28 red and turn THIS leg green"), which
# was false in the direction that costs: read as written it names the curl-7 leg as the expendable
# one, and it is the only leg here the classifying fix reds. MEASURED independently by the round-2
# review and again by the round-3 fix, against exactly that rival fix (capture curl's rc; `5|6|7`
# ⇒ benign fallback on the consuming route, everything else refuses): 7 assertions FAILED, every
# one of them `claim transport fail (curl 7)`; the 52 and 28 legs PASSED. A wrong comment on a
# control is worse than no comment, because the next maintainer deletes the wrong leg and the
# suite stays green.
for _crc in 7 52 28; do
    NDL_CLAIM_CURLFAIL=$_crc run_ndl --board dev
    eq "claim transport fail (curl $_crc) → rc 1 (fail closed)"        "1" "$rc"
    eq "claim transport fail (curl $_crc) → mints NOTHING"             ""  "$out"
    eq "claim transport fail (curl $_crc) → never answers from the floor" "false" "$(has 'DL-0301' "$out$err")"
    eq "claim transport fail (curl $_crc) → never reaches the scan"    "0" "$(kb_stub_count_any "$SEARCH")"
    eq "claim transport fail (curl $_crc) → says a number may ALREADY be spent" "true" \
       "$(has 'may ALREADY have allocated a number' "$err")"
    # The honest half, and the one a bare refusal would drop: the tool says it cannot tell a
    # claim the server applied from one that never arrived, rather than naming a transport error
    # and leaving the operator to assume nothing was spent.
    eq "claim transport fail (curl $_crc) → says it cannot tell which happened" "true" \
       "$(has 'nothing here can tell a claim the server applied from one that never arrived' "$err")"
    eq "claim transport fail (curl $_crc) → does NOT announce a fallback it refused" "false" \
       "$(has "$FALLBACK" "$err")"
    # No body was read, so there is no excerpt to quote — an empty `Response:` here would say the
    # server answered with nothing, when in fact nothing was heard.
    eq "claim transport fail (curl $_crc) → quotes no response body"   "false" "$(has 'Response:' "$err")"
    only_cause "claim transport fail (curl $_crc)" "$C_TRANSPORT" "$err"
done
unset _crc

# The rc-3 abort is upstream of the degrade decision, exactly as the 500 and the 2xx-undecodable
# arms are: strict must not renumber an outcome that has already refused.
NDL_CLAIM_CURLFAIL=52 run_ndl --board dev --require-counter
eq "claim transport fail + strict → still rc 1, not 4" "1" "$rc"
eq "claim transport fail + strict → mints NOTHING"     "" "$out"
only_cause "claim transport fail + strict" "$C_TRANSPORT" "$err"

echo "== CONTROL: the SAME transport failure on the NON-CONSUMING read still falls back =="
# The over-correction control, and the reason this route is driven at all (it never was before).
# A GET allocates nothing, so the benign fallback is CORRECT there and --peek's whole offline
# path depends on it (card#7214). A fix that made the transport fail closed for EVERY caller
# reds every line in this block.
NDL_PEEK_CURLFAIL=52 run_ndl --board dev --peek
eq "peek transport fail → rc 0 (benign fallback)"     "0" "$rc"
eq "peek transport fail → mints the offline floor"    "DL-0301" "$out"
eq "peek transport fail → announces the fallback"     "true" "$(has "$FALLBACK" "$err")"
eq "peek transport fail → names the INSPECT endpoint" "true" \
   "$(has 'DL-sequence inspect endpoint gave no number' "$err")"
eq "peek transport fail → claims NOTHING"             "0" "$(kb_stub_count_any "$CLAIM_URL")"
eq "peek transport fail → does NOT borrow the claim's spent-number wording" "false" \
   "$(has 'may ALREADY have allocated a number' "$err")"
only_cause "peek transport fail" "$C_TRANSPORT" "$err"

NDL_PEEK_CURLFAIL=52 run_ndl --board dev --peek --require-counter
eq "peek transport fail + strict → rc 4"              "4" "$rc"
eq "peek transport fail + strict → mints NOTHING"     "" "$out"
only_cause "peek transport fail + strict" "$C_TRANSPORT" "$err"

echo "== cause 4 (2xx carrying no usable value): ONE cause, TWO dispositions, keyed on CONSUMPTION =="
# THE CAUSE is one cause on both routes and still gets its own line (only_cause holds on both
# arms below). What differs is the DISPOSITION, and card#10230 is that it used not to: the
# 2xx-undecodable arm routed BOTH callers to the benign fallback, which on the CONSUMING route
# is a FAIL-OPEN — the POST has already allocated a number server-side, the offline max+1 scan
# cannot see a claimed-but-unstamped DL (card#6232), so the number it hands back is at or BELOW
# the one just burned: a DUPLICATE correlation key, the one thing an allocator must never emit.
# Measured against the pre-fix binary, this exact input: `DL-0301` on stdout at rc 0.
#
# The realistic producer is not exotic and is driven as its own input below: a gateway answering
# 200 with HTML (an expired SSO session, a WAF block page, a maintenance page). A fix keyed on
# the body being valid JSON would pass the `{"data":{}}` leg and fail-open on that one.
NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{}}' run_ndl --board dev
eq "2xx-no-value on the CONSUMING claim → rc 1 (fail closed)" "1" "$rc"
eq "2xx-no-value on the claim → mints NOTHING"        "" "$out"
eq "2xx-no-value on the claim → never answers from the floor" "false" "$(has 'DL-0301' "$out$err")"
eq "2xx-no-value on the claim → never reaches the scan" "0" "$(kb_stub_count_any "$SEARCH")"
eq "2xx-no-value on the claim → names the HTTP status it got" "true" "$(has 'answered HTTP 200' "$err")"
eq "2xx-no-value on the claim → says a number may ALREADY be burned" "true" \
   "$(has 'may ALREADY have allocated a number' "$err")"
eq "2xx-no-value on the claim → does NOT announce a fallback it refused" "false" "$(has "$FALLBACK" "$err")"
# ⭐ THE PRESENCE WITNESS for the transport arm's "quotes no response body" assertion above. That
# one is an absence, and an absence proves nothing until the same predicate is seen to FIRE: here
# a body WAS read, so the refusal quotes an excerpt of it. Both refusals come from one
# `spent_refusal`, so this is the leg that shows the excerpt is omitted where nothing was heard
# rather than dropped everywhere.
eq "2xx-no-value on the claim → quotes the body it could not read" "true|true" \
   "$(has 'Response:' "$err")|$(has '{"data":{}}' "$err")"
only_cause "2xx-no-value on the claim" "$C_UNDECODABLE" "$err"
# A REMEDIATION STRING IS A DOC SURFACE, so it is asserted like one. `kanban` and `--board kanban`
# name DIFFERENT boards, so a remedy built by re-printing `$project` alone would hand the operator
# a command against the wrong board — it is built from the argv words this run was given.
eq "2xx-no-value on the claim → the remedy is runnable AS PRINTED" "true" \
   "$(has "next-dl --board dev --peek" "$err")"

NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='<html><head><title>Sign in</title></head><body>SSO gateway</body></html>' \
    run_ndl --board dev
eq "200 + an SSO HTML page on the claim → rc 1"       "1" "$rc"
eq "200 + an SSO HTML page on the claim → mints NOTHING" "" "$out"
eq "200 + an SSO HTML page on the claim → never answers from the floor" "false" "$(has 'DL-0301' "$out$err")"
eq "200 + an SSO HTML page on the claim → never reaches the scan" "0" "$(kb_stub_count_any "$SEARCH")"

# The rc-3 abort is upstream of the degrade decision, exactly as the 500 arm is (pinned again at
# the end of this file): strict must not renumber an outcome that has already refused.
NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{}}' run_ndl --board dev --require-counter
eq "2xx-no-value on the claim + strict → still rc 1, not 4" "1" "$rc"
eq "2xx-no-value on the claim + strict → mints NOTHING" "" "$out"
only_cause "2xx-no-value on the claim + strict" "$C_UNDECODABLE" "$err"

# THE OTHER SPELLING, which is what makes the line above a measurement of the spelling rather
# than of one literal: the bare project alias must print ITSELF, with no `--board` in front of it.
# A remedy built from `$project` alone passes the assertion above and reds this one.
NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{}}' run_ndl bridge
eq "2xx-no-value on the bridge ALIAS → rc 1"          "1" "$rc"
eq "…and the remedy uses the ALIAS spelling, not --board" "true|false" \
   "$(has 'next-dl bridge --peek' "$err")|$(has '--board' "$err")"

echo "== CONTROL: the SAME undecodable 2xx on the NON-CONSUMING read still falls back =="
# The control that keeps the fix honest. Nothing was spent on a GET, so the benign fallback is
# CORRECT there and --peek's offline path is supported (card#7214). A fix that made the
# transport fail closed for every caller — the over-correction — reds every line here.
NDL_PEEK_HTTP=200 NDL_PEEK_BODY='{"data":{}}' run_ndl --board dev --peek
eq "2xx-no-value on the peek → rc 0 (benign fallback)" "0" "$rc"
eq "2xx-no-value on the peek → mints the offline floor" "DL-0301" "$out"
eq "2xx-no-value on the peek → announces the fallback" "true" "$(has "$FALLBACK" "$err")"
eq "2xx-no-value on the peek → names the INSPECT endpoint" "true" \
   "$(has 'DL-sequence inspect endpoint gave no number' "$err")"
eq "2xx-no-value on the peek → claims NOTHING"        "0" "$(kb_stub_count_any "$CLAIM_URL")"
eq "2xx-no-value on the peek → does NOT borrow the claim's consumed-number wording" "false" \
   "$(has 'may ALREADY have allocated a number' "$err")"
only_cause "2xx-no-value on the peek" "$C_UNDECODABLE" "$err"

NDL_PEEK_HTTP=200 NDL_PEEK_BODY='<html><head><title>Sign in</title></head><body>SSO gateway</body></html>' \
    run_ndl --board dev --peek
eq "200 + an SSO HTML page on the peek → rc 0"        "0" "$rc"
eq "200 + an SSO HTML page on the peek → the offline floor" "DL-0301" "$out"

echo "== and a 2xx that DECODES is unaffected on BOTH routes =="
# The third leg of the matrix: the fix must move only the undecodable case. Both numbers come
# from their own endpoint and neither is reachable from the fixture's board contents.
run_ndl --board dev
eq "decodable claim → rc 0 and the CLAIMED number"    "0|DL-0093" "$rc|$out"
run_ndl --board dev --peek
eq "decodable peek → rc 0 and the COUNTER's next"     "0|DL-0222" "$rc|$out"

echo "== a MISWIRED call site fails CLOSED — both halves, and the omitted one had no control =="
# dl_sequence_call's contract promises that a caller which misspells <consumption> OR OMITS it
# refuses loudly rather than re-minting card#10230 in silence. The OMISSION half was FALSE when
# that sentence was written and nothing here could have seen it: `consumption="$5"; risk="$6"`
# ran before any value test, so under `set -u` an omitted argument killed the subshell at the
# unbound `$6` at rc 1 — the caller's BENIGN fallback — and next-dl printed DL-0301 at rc 0 with
# no `unusable` cause line at all. Reproduced against that head exactly so.
#
# ⛔ THE MISWIRING CANNOT BE DRIVEN THROUGH THE CLI, because every shipped call site is correct
# by construction — which is exactly why the guarantee had no control. So the call site is
# MUTATED in a scratch copy of bin/. `ndl_mutant` refuses a sed that changed nothing, so a leg
# below can never be a measurement of the shipped binary wearing a mutant's name.
#
# ⚠ WHICH BINARY THE MUTANT LEGS BASELINE AGAINST, stated so a whole-file baseline is read
# correctly. They do NOT baseline against the PR base binary: the base has no `<consumption>`
# argument at all, so the first sed below matches nothing there and `ndl_mutant` ABORTS the run —
# which is the guard working, not a suite defect. The omission legs' correct baseline is
# card#10230's FIRST head, which carries the `consuming` line and lacks the arity guard (8 of them
# were watched red there); the misspelling legs' baseline is the shipped binary with the token
# test inverted, and the out-of-range leg further down baselines against the bespoke mutation its
# own comment names — there is no binary that lacked ITS fix, because it fixes nothing.
NDL_MUT="$TMP/ndl-mut"
ndl_mutant() {   # ndl_mutant <sed-expr> — a scratch bin/ whose next-dl carries <sed-expr>
    rm -rf "$NDL_MUT"
    mkdir -p "$NDL_MUT"
    cp -pR "$HERE"/../bin/. "$NDL_MUT"/
    sed -i "$1" "$NDL_MUT/next-dl"
    if cmp -s "$HERE/../bin/next-dl" "$NDL_MUT/next-dl"; then
        echo "selftest: mutation '$1' changed nothing in next-dl — did board_claim's argument list move?" >&2
        exit 1
    fi
}
run_ndl_mut() {
    kb_stub_reset
    rc=0
    out="$("$NDL_MUT/next-dl" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
}

# HALF 1 — the argument is OMITTED. board_claim passes five arguments instead of six.
ndl_mutant '/^        consuming \\$/d'
run_ndl_mut --board dev
eq "MISWIRED (argument OMITTED) → rc 1"               "1" "$rc"
eq "MISWIRED (omitted) → mints NOTHING"               ""  "$out"
eq "MISWIRED (omitted) → never answers from the floor" "false" "$(has 'DL-0301' "$out$err")"
eq "MISWIRED (omitted) → names the miswiring and the arity it got" "true" \
   "$(has 'called with 5 arguments, not 6' "$err")"
# The guard is BEFORE the positional read, which is the whole fix: `set -u` must never be what
# stops this call, because its rc 1 is the benign fallback.
eq "MISWIRED (omitted) → no unbound-variable death"   "false" "$(has 'unbound variable' "$err")"
eq "MISWIRED (omitted) → does NOT announce a fallback" "false" "$(has "$FALLBACK" "$err")"
eq "MISWIRED (omitted) → issued no request at all"    "0" "$(kb_stub_total)"
# strict changes nothing: the abort is upstream of the degrade decision, as every rc-3 member is.
run_ndl_mut --board dev --require-counter
eq "MISWIRED (omitted) + strict → still rc 1, not 4"  "1" "$rc"
eq "MISWIRED (omitted) + strict → mints NOTHING"      ""  "$out"
# ⭐ CONTROL that the mutant is an otherwise-WORKING next-dl and not a tool broken into refusing:
# --peek never calls board_claim, so it must behave exactly as the shipped binary does.
run_ndl_mut --board dev --peek
eq "control: the same mutant's --peek is untouched → rc 0 and the COUNTER's next" "0|DL-0222" "$rc|$out"

# HALF 2 — the VALUE is misspelled. Every value but the exact token `non-consuming` is consuming,
# so a misspelling on the claim still refuses. This leg is what reds if the token test is ever
# flipped to `== "consuming"`, which would read a typo as a non-consuming call and fall back.
ndl_mutant 's/^        consuming \\$/        consumin \\/'
NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{}}' run_ndl_mut --board dev
eq "MISWIRED (value MISSPELLED) → still rc 1 (fail closed)" "1" "$rc"
eq "MISWIRED (misspelled) → mints NOTHING"            ""  "$out"
eq "MISWIRED (misspelled) → never answers from the floor" "false" "$(has 'DL-0301' "$out$err")"
eq "MISWIRED (misspelled) → takes the SPENT refusal, not the arity one" "true|false" \
   "$(has 'may ALREADY have allocated a number' "$err")|$(has 'arguments, not 6' "$err")"
# ⭐ CONTROL, the other direction: a misspelling of `non-consuming` on the PEEK route is treated
# as consuming too, so it fails closed where the correct spelling falls back. That is the
# fail-closed side being reached BY a typo rather than merely surviving one.
ndl_mutant 's/^        non-consuming \\$/        non_consuming \\/'
NDL_PEEK_HTTP=200 NDL_PEEK_BODY='{"data":{}}' run_ndl_mut --board dev --peek
eq "control: a MISSPELLED non-consuming lands on the FAIL-CLOSED side → rc 1" "1" "$rc"
eq "control: …and mints NOTHING where the correct spelling mints the floor" "" "$out"

rm -rf "$NDL_MUT"
unset -f ndl_mutant run_ndl_mut
unset NDL_MUT

echo "== the LAST post-spend cell: a claim answers a uint the CANON refuses, and still mints nothing =="
# ⭐ FROM THE card#10230 ARM SWEEP, and a null result pinned rather than left unwitnessed. Every
# other way out of dl_sequence_call after a CONSUMING POST is asserted above; this is the one
# that leaves it at rc 0. `kb_is_uint` admits 9999999, so the value is PRINTED and the call
# succeeds — and `kb_dl_canon` then refuses it as out of the canonical range, at the caller.
# That already exits 1 and mints nothing, so this leg fixes no defect; it exists because that
# `|| { … exit 1; }` is the only thing standing between a spent claim and the offline floor on
# this path, and nothing else in this file would notice it being softened into a fallback.
# Watched RED under exactly that mutation (the canon refusal replaced by a fall-through).
NDL_CLAIM_HTTP=200 NDL_CLAIM_BODY='{"data":{"value":9999999}}' run_ndl --board dev
eq "out-of-range claim → rc 1"                        "1" "$rc"
eq "out-of-range claim → mints NOTHING"               ""  "$out"
eq "out-of-range claim → never answers from the offline floor" "false" "$(has 'DL-0301' "$out$err")"
eq "out-of-range claim → never reaches the scan"      "0" "$(kb_stub_count_any "$SEARCH")"
eq "out-of-range claim → names what it refused"       "true" "$(has 'not a canonical DL number' "$err")"

echo "== cause 1 (config UNRESOLVED): no request was issued, and the notice says that =="
# The one rc-1 cause the endpoint-shaped ones hide: dl_sequence_call returns 1 before
# any request when the board config does not resolve, so an UNCONFIGURED board degraded as
# silently as an absent endpoint. Its permissive outcome is card#6631's stated bound — it still
# mints — so only the announcement is new here.
run_ndl --board nosuchboard
eq "unresolved config permissive → rc 0"              "0" "$rc"
eq "unresolved config permissive → still mints the local floor" "DL-0301" "$out"
eq "unresolved config permissive → announces the fallback" "true" "$(has "$FALLBACK" "$err")"
eq "unresolved config permissive → keeps the old skip message too" "true" "$(has 'skipping board check' "$err")"
only_cause "unresolved config permissive" "$C_CONFIG" "$err"
eq "unresolved config permissive → issued no request" "0" "$(kb_stub_total)"

run_ndl --board nosuchboard --require-counter
eq "unresolved config strict → rc 4"                  "4" "$rc"
eq "unresolved config strict → mints NOTHING"         "" "$out"
only_cause "unresolved config strict" "$C_CONFIG" "$err"

echo "== --peek degrades through the SAME policy, in the INSPECT endpoint's name =="
# The two modes call one degrade_or_refuse with different labels. A swapped label would hand the
# operator the claim endpoint's reasoning for a peek, which is the card#6232 mistake one layer up.
NDL_PEEK_HTTP=404 NDL_PEEK_BODY='{"message":"not found"}' run_ndl --board dev --peek
eq "peek 404 permissive → rc 0"                       "0" "$rc"
eq "peek 404 permissive → the offline floor"          "DL-0301" "$out"
eq "peek 404 permissive → names the INSPECT endpoint" "true" "$(has 'DL-sequence inspect endpoint gave no number' "$err")"
eq "peek 404 permissive → does NOT name the claim endpoint" "false" "$(has 'atomic claim endpoint' "$err")"
only_cause "peek 404 permissive" "$C_ABSENT" "$err"
eq "peek 404 permissive → claims nothing"             "0" "$(kb_stub_count_any "$CLAIM_URL")"

NDL_PEEK_HTTP=404 NDL_PEEK_BODY='{"message":"not found"}' run_ndl --board dev --peek --require-counter
eq "peek 404 strict → rc 4"                           "4" "$rc"
eq "peek 404 strict → mints NOTHING"                  "" "$out"
eq "peek 404 strict → says it is refusing"            "true" "$(has "$REFUSAL" "$err")"

echo "== --require-counter does NOT refuse a present-but-errored endpoint differently (rc 1 stands) =="
# The rc-3 abort is upstream of the degrade decision and unchanged: strict must not renumber an
# outcome that already refused, or a caller keying on rc 1 loses the abort it already handles.
NDL_CLAIM_HTTP=500 NDL_CLAIM_BODY='{"message":"boom"}' run_ndl --board dev --require-counter
eq "claim 500 + strict → still rc 1, not 4"           "1" "$rc"
eq "claim 500 + strict → still the PRESENT-but-FAILED message" "true" "$(has 'PRESENT but FAILED' "$err")"
eq "claim 500 + strict → not reported as a strict refusal" "false" "$(has "$REFUSAL" "$err")"

unset NDL_CLAIM_CURLFAIL NDL_PEEK_CURLFAIL

unset KB_DL_CHECKOUT_GLOBS

echo "== STRUCTURAL: every benign exit PAST THE REQUEST is guarded or DECLARED (the arm-SET rule) =="
# ⭐ THE CONTROL FOR A GUARANTEE ABOUT CODE THAT DOES NOT EXIST YET. bin/next-dl states its ruling
# over the arm SET — "EVERY arm in which the call may have SPENT a number and the outcome is
# UNKNOWN refuses … they share one refusal so a new arm inherits the ruling instead of
# re-deciding it" — and until this leg NOTHING checked it. It was falsified by doing the obvious
# thing: three lines treating a gateway 502/503/504 as "temporarily down, fall back and retry
# later", inserted before the `*)` arm, minted DL-0301 at rc 0 off the offline scan on a claim the
# server had ANSWERED, and the whole suite stayed GREEN. card#10230's own defect, on a new arm,
# with CI green — which is what a universal with no control is worth.
#
# A BEHAVIOUR CASE CANNOT COVER THIS, and neither can a list of blessed lines: the population is
# every arm a future editor adds, so the check has to be a STRUCTURAL PROPERTY of the function's
# own text. That is the pattern this repo already owns —
# tests/locale-range-guard-selftest.sh, which bin/next-dl cites three lines above the very `case`
# scanned here — so this extends it rather than siblings a second idiom.
#
# THE PROPERTY. `exit 1` is the caller's BENIGN FALLBACK: it is the code that reaches the offline
# max+1 scan and MINTS. So inside dl_sequence_call every `exit 1` must be one of:
#   * PRE-REQUEST — above the curl command substitution. Nothing was issued, so nothing can have
#     been spent, and that is a property of POSITION rather than of anyone's say-so.
#   * `non-consuming`-GUARDED — inside the `[[ "$consumption" == "non-consuming" ]]` block. A GET
#     allocates nothing, and this is --peek's whole offline path (card#7214).
#   * DECLARED — pinned `NOTHING WAS SPENT` on its own line or the two above it. Today that is the
#     404 arm alone: the server ANSWERED, and what it answered is that the route is absent here.
# Anything else is an arm taking the fallback with a spend possible, which IS the defect. The
# fail-closed exits (spent_refusal then `exit 3`) are not in this population at all — they are the
# ruling being obeyed, and a new arm that takes them needs no pin.
#
# THE POPULATION IS RE-DERIVED ON EVERY RUN, and by hand in one line if you want to read it
# rather than trust this paragraph:
#     ndl_fn_body bin/next-dl | grep -nE '(^|[^A-Za-z0-9_])exit[ \t]+1([^0-9]|$)'
# — every benign exit in the function, plus the comment lines that merely mention one (the
# scanner drops those; a bare grep cannot). What the scanner REPORTS is that list minus its
# comment, pre-request, guarded and declared members. A denominator a reader cannot re-run is one
# nobody can check, which is why it is a command here and not a number.
#
# THE PIN IS A DECLARATION, NOT A PASSWORD, and that is the whole design: a maintainer cannot
# reach green by accident, only by writing down WHY the server's answer proves nothing was
# allocated. That is the decision the guarantee exists to force, and it is the same shape as
# locale-range-guard's `LC_ALL=C` window pin — a structural exemption rather than an allow-list,
# which an earlier draft of that file proved is the difference between a guard and a rubber stamp.
#
# ⚠ WHAT THIS LEG DOES NOT REACH, named rather than implied. The CALLER's
# `if [[ $crc -eq 0 ]] && kb_is_uint "$claimed"` has a false arm that falls through to
# degrade_or_refuse — claim succeeded, answer unreadable ⇒ mint from the scan — and it is OUTSIDE
# this scanner's population BY CONSTRUCTION, because the population is dl_sequence_call's body and
# that test is at the call site, where spent_refusal is not in scope. It is POSITIVELY UNREACHABLE
# today: dl_sequence_call exits 0 only after `kb_is_uint "$val" && [[ "$val" -ge 1 ]]`, so
# `$claimed` is always a uint when crc is 0. No leg drives it and none is claimed to.
#
# THE EXEMPTIONS ERR CLOSED, deliberately. The pin window is two lines; a nested `if` inside the
# consumption guard closes the depth early and turns a guarded exit into a REPORTED one; and
# nothing strips trailing comments, so a trailing comment merely MENTIONING `exit 1` is a hit;
# and the guard opener requires the `if` spelling, so `[[ "$consumption" == "non-consuming" ]] &&
# exit 1` on one line is REPORTED rather than recognised. Each of those is a false POSITIVE —
# loud, visible at the next run, and the direction a guard must err in. A false negative would be
# this leg silently dead, which is the state it replaces.
# ⛔ THE GUARD BLOCK IS TRACKED BY INDENTATION, NOT BY COUNTING `if`/`fi`. The counting version
# was written first and is WRONG in the fail-OPEN direction, which its own fixture caught: a
# one-line `if …; then …; fi` inside the guard increments and never decrements, so the depth
# sticks above zero and every later line in the function reads as guarded — the scanner would go
# quiet for the whole rest of the body, which is the exact failure it exists to prevent. The
# block therefore closes two ways, both anchored on the opening `if`'s own indent: a `fi` at that
# indent, or ANY code line indented LESS than it (a dedent ends the block whatever the `fi` looks
# like). The second arm is the belt for a reindent that the first would miss.
ndl_unpinned_benign_exits() {   # <file> — the offending `exit 1` lines, one per line
    LC_ALL=C awk '
        function indent(t) { match(t, /^[ \t]*/); return RLENGTH }
        /^dl_sequence_call\(\) \($/ { infn = 1; next }
        infn && /^\)$/              { infn = 0; next }
        !infn                        { next }
        {
            raw = $0
            line = raw; sub(/^[ \t]+/, "", line)
            if (line ~ /^#/ || line == "") { p2 = p1; p1 = raw; next }   # comments describe, they do not exit
            if (raw ~ /\$\(curl/) postreq = 1       # THE request: everything below it is spend-capable
            if (!inguard && raw ~ /if[ \t]*\[\[.*consumption.*"non-consuming"/) {
                inguard = 1; gind = indent(raw); p2 = p1; p1 = raw; next
            }
            if (inguard) {
                if (line ~ /^fi([ \t;]|$)/ && indent(raw) == gind) { inguard = 0; p2 = p1; p1 = raw; next }
                if (indent(raw) < gind) inguard = 0          # a dedent ends the block regardless
                else { p2 = p1; p1 = raw; next }
            }
            if (postreq && raw ~ /(^|[^A-Za-z0-9_])exit[ \t]+1([^0-9]|$)/ &&
                (raw p1 p2) !~ /NOTHING WAS SPENT/)
                printf "%s:%d:%s\n", FILENAME, FNR, raw
            p2 = p1; p1 = raw
        }
    ' "$1" 2>/dev/null || true
    return 0
}
n_lines() { [[ -z "$1" ]] && { printf '0'; return 0; }; printf '%s\n' "$1" | wc -l | tr -d ' '; }

# Vacuity first, because every assertion below would pass over an empty scan. Both landmarks are
# unique to this function, so a rename or a reshaped body reds HERE rather than going quiet.
eq "the scanner lifted dl_sequence_call's body" "true" \
   "$(has 'spent_refusal() {' "$(ndl_fn_body "$NDL")")"
eq "the lifted body carries exactly ONE request (the post-request boundary is real)" "1" \
   "$(ndl_fn_body "$NDL" | grep -c '\$(curl')"
eq "the lift stopped at the function and did not swallow the caller" "false" \
   "$(has 'degrade_or_refuse "atomic claim endpoint"' "$(ndl_fn_body "$NDL")")"

_hits="$(ndl_unpinned_benign_exits "$NDL")"
eq "the SHIPPED bin/next-dl has no unguarded, undeclared benign exit past the request" "0" "$(n_lines "$_hits")"
[[ -n "$_hits" ]] && printf '  offending lines:\n%s\n' "$_hits" >&2

echo "== …and the scanner is SEEN TO FAIL on the arm that falsified the sentence =="
# ⭐ THE ACCEPTANCE TEST FOR THIS LEG, and it is the round-2 review's reproduction re-planted
# verbatim: the arm an ordinary maintainer adds. Against the shipped binary that arm passed every
# other check in this file and minted DL-0301 at rc 0 on a 503. Here it is a hit.
ndl_planted '/^        \*)$/i\        502|503|504)\n            unusable "is temporarily unavailable (HTTP $http) — a gateway error, not a deployment state"\n            exit 1 ;;'
_hits="$(ndl_unpinned_benign_exits "$NDL_PLANT")"
eq "a 502/503/504 benign-fallback arm is FLAGGED" "1" "$(n_lines "$_hits")"
case "$_hits" in *"exit 1 ;;"*) ok "…and the flagged line is the arm's own exit" ;;
                 *) bad "…but the flagged line is not the arm's exit: $_hits" ;; esac
# ⭐ THE OTHER DIRECTION ON THE SHIPPED TREE: the 404 arm's pin is LOAD-BEARING, not decoration.
# Without this, the pin arm of the exemption could be dead code and nobody would know.
ndl_planted 's/NOTHING WAS SPENT: the server ANSWERED/the server answered/'
eq "deleting the 404 arm's declaration FLAGS that arm" "1" \
   "$(n_lines "$(ndl_unpinned_benign_exits "$NDL_PLANT")")"

echo "== positive controls: what the scanner must and must NOT flag =="
# Synthetic fixtures, mirroring locale-range-guard-selftest.sh's `pos/` set: the mutations above
# prove the scanner works on the REAL file, and these prove each of its rules discriminates —
# without which a matcher that flagged every post-request line would satisfy both mutations.
_pos="$TMP/ndl-struct"; rm -rf "$_pos"; mkdir -p "$_pos"
_fixture() {   # _fixture <name> <line>...
    local f="$_pos/$1"; shift
    { printf 'dl_sequence_call() (\n'; printf '%s\n' "$@"; printf ')\n'; } > "$f"
}
_fixture pre-request-exit \
    '    cfg="$(resolve_board_cfg)" || {' '        exit 1' '    }' \
    '    resp="$(curl -sS "$url")" || { exit 3; }'
_fixture unguarded-arm \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '    case "$http" in' '        503)' '            exit 1 ;;' '    esac'
_fixture guarded-arm \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        if [[ "$consumption" == "non-consuming" ]]; then' '            exit 1' '        fi'
_fixture pinned-arm \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        404)   # NOTHING WAS SPENT: the server answered that the route is absent' \
    '            unusable "is NOT DEPLOYED"' '            exit 1 ;;'
_fixture pinned-same-line \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '            exit 1 ;;   # NOTHING WAS SPENT: the server answered 404'
_fixture pin-out-of-window \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        # NOTHING WAS SPENT: three lines up is NOT within the window' \
    '        404)' '            unusable "is NOT DEPLOYED"' '            exit 1 ;;'
_fixture refusing-arm \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        503)' '            spent_refusal "may ALREADY have allocated"' '            exit 3 ;;'
_fixture comment-only-mention \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        # a 404 takes exit 1 here, which is described and not done'
_fixture exit-ten \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '            exit 10 ;;'
# An exit past the request but past the FUNCTION too: the caller is a different population, and a
# scanner that never reset `infn` would flag the whole rest of the file.
{ printf 'dl_sequence_call() (\n    resp="$(curl -sS "$url")" || { exit 3; }\n)\n'
  printf 'if [[ $crc -eq 3 ]]; then exit 1; fi\n'; } > "$_pos/outside-the-function"
# A one-line `if …; fi` nested inside the consumption guard — the shape that broke the counting
# tracker. Still NOT flagged, because the exit really is guarded; what this pins is that the
# scanner does not lose the block on it.
_fixture nested-if-in-guard \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        if [[ "$consumption" == "non-consuming" ]]; then' \
    '            if [[ -n "$x" ]]; then :; fi' '            exit 1' '        fi'
# ⭐ THE GUARD MUST CLOSE. Without this the block could swallow the whole rest of the function and
# every arm after it would read as guarded — which is how the counting tracker failed.
_fixture exit-after-the-guard-closes \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        if [[ "$consumption" == "non-consuming" ]]; then' '            exit 1' '        fi' \
    '        exit 1 ;;'
# …and it closes on a DEDENT too, where the `fi` has been reindented out of alignment.
_fixture dedent-closes-the-guard \
    '    resp="$(curl -sS "$url")" || { exit 3; }' \
    '        if [[ "$consumption" == "non-consuming" ]]; then' '                exit 1' '          fi' \
    '    exit 1'

_flagged() { [[ -n "$(ndl_unpinned_benign_exits "$_pos/$1")" ]] && echo true || echo false; }
for _f in unguarded-arm pin-out-of-window exit-after-the-guard-closes dedent-closes-the-guard; do
    eq "FLAGS $_f" "true" "$(_flagged "$_f")"
done
for _f in pre-request-exit guarded-arm pinned-arm pinned-same-line refusing-arm \
          comment-only-mention exit-ten outside-the-function nested-if-in-guard; do
    eq "does NOT flag $_f" "false" "$(_flagged "$_f")"
done
unset _f
rm -rf "$_pos" "$NDL_PLANT"
unset -f _fixture _flagged ndl_planted

echo "== COVERAGE: every cause dl_sequence_call can PRINT is driven by a leg above (the rc-1 rule) =="
# ⭐ THE :298 GUARANTEE'S CONTROL — "Any new way to reach exit 1 from here owes a distinct
# `unusable` cause". The population is DERIVED from the bin (see the derivation near the cause
# matrix above), so a FIFTH cause added to dl_sequence_call lands here with nothing driving it and
# reds, where under the old hand-written array it reddened nothing at all.
# ⛔ A NEW CAUSE OWES MORE THAN A LEG HERE: it is described per cause, not as a count, in
# bin/next-dl's header, in README.md and in docs/CHANGELOG.md. Those are prose and this cannot
# check them; it can tell you to go and write them, which is what this line is for.
for _i in "${!NDL_CAUSES[@]}"; do
    eq "derived cause [$_i] <${NDL_CAUSES[$_i]}> is asserted PRESENT by at least one leg" \
       "1" "${NDL_CAUSE_SEEN[$_i]:-0}"
done
unset _i

_summary "next-dl-selftest"
