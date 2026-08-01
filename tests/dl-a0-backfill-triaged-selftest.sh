#!/usr/bin/env bash
# dl-a0-backfill-triaged-selftest.sh — deterministic, network-free end-to-end checks for
# bin/dl-a0-backfill-triaged, which had ZERO test coverage while WRITING to a live board.
#
# WHY THIS FILE EXISTS. Before it, `grep -rn dl-a0-backfill-triaged tests/` returned nothing: no
# selftest named the tool and `tests/help-output-selftest.sh`'s CLIS registry does not carry it
# either — the tool echoes a one-line $USAGE rather than a header block, so CLIS's
# line-count-equality assertion does not apply to it. That is now a STATED exclusion rather than
# an omission: card#5339 made CLIS one half of a completeness gate, so this tool sits in that
# file's EXCLUDED list with its reason, and a bin belonging to neither list reds the build.
# Its --apply path PATCHes the tags array of every matched card on a real board,
# and a tag write REPLACES the whole array — so a defect here does not fail loudly, it quietly
# drops the id:/repo:/type: tags that every other consumer keys on. An uncovered write path is
# the worst tier of the uncovered set, and per canon #4 a bin with no coverage cannot be
# refactored, so its duplication is permanent until this exists (card#5357).
#
# WHAT IS EXERCISED, and how. The bin is NOT main-guarded — sourcing it RUNS it — so it is driven
# as a PROCESS with `curl` stubbed on PATH (tests/_kb-api-stub.sh). That seam is deliberately
# BELOW the lib: the whole config-resolution → paginated-fetch → jq target-selection → PATCH
# chain runs for real, and the assertions are made against the actual HTTP requests the tool
# issued, not against a faked kb_api.
#
# Four properties carry the file:
#   1. DRY-RUN IS THE DEFAULT and it is a READ. No --apply ⇒ not one write request leaves the
#      tool. This is the guarantee an operator relies on before touching a live board.
#   2. THE TARGET FILTER. Only `id:*-pr-*` cards whose triaged-state actually needs changing are
#      touched; --remove inverts the selection, not the filter.
#   3. THE READ-MODIFY-WRITE PRESERVES THE OTHER TAGS. The PATCH body is asserted whole, so a
#      regression that sends `{"tags":["triaged"]}` — losing id:/repo: — is a red, not a silent
#      data loss discovered later on the board.
#   4. FAIL-CLOSED ON AN INCOMPLETE READ. A page-1 failure AND a short read (server total exceeds
#      delivered rows) must both abort with NO writes: a partial read must never drive a partial
#      backfill. That is the posture the tool's own comment claims and nothing asserted.
#
# EVERY ABSENCE ASSERTION IS PAIRED WITH A WITNESS THAT THE RUN CANNOT DESTROY. "No PATCH was
# issued" is meaningless if the tool never reached the API at all, and the two are indis-
# tinguishable from the outside. The stub's request log is written before any response is chosen
# and nothing under test can truncate it, so each "0 PATCHes" assertion sits beside an observed
# non-zero count of the GET that proves the run got that far.
#
# WHAT A GREEN RUN PROVES — the weakest property the assertions support: that against a faked
# kanban API the tool selects, previews and writes what its header claims, and refuses to write
# on an incomplete read. It does not prove anything about the real server's tag semantics, nor
# that the board's `id:*-pr-*` convention is what any particular deployment uses.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"

A0="$HERE/../bin/dl-a0-backfill-triaged"
_need -x "$A0"

_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42
kb_stub_board_config alt 77     # a second board, so "--board routes" is a real assertion
kb_stub_install

# has <needle> <haystack> → true/false on a LITERAL substring match (robust against the JSON
# brackets and the U+2026 in the tool's "… and N more" line).
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# --- board fixture ----------------------------------------------------------------------------
# 11 cards, chosen so every arm of the jq selector is exercised by a card that must NOT be
# selected as well as one that must:
#   PR + untriaged (targets, default mode) : 1, 11, 12, 13, 14, 15   → 6, i.e. > the 5-row preview
#   PR + triaged   (targets, --remove)     : 2, 6                    → 2
#   id: tag but not "-pr-"                 : 3   (an issue card — the filter is not "any id: tag")
#   empty tags array                       : 4
#   NO tags key at all                     : 5   (the `.tags // []` arm)
# Card 1 and card 6 carry a second non-id tag, so the read-modify-write has something to lose.
export KB_STUB_BOARD_JSON='{"data":[
  {"id":1,"tags":["id:gh-pr-101","repo:x"]},
  {"id":2,"tags":["id:gh-pr-102","triaged"]},
  {"id":3,"tags":["id:gh-issue-7"]},
  {"id":4,"tags":[]},
  {"id":5},
  {"id":6,"tags":["id:gh-pr-103","triaged","repo:y"]},
  {"id":11,"tags":["id:gh-pr-111"]},
  {"id":12,"tags":["id:gh-pr-112"]},
  {"id":13,"tags":["id:gh-pr-113"]},
  {"id":14,"tags":["id:gh-pr-114"]},
  {"id":15,"tags":["id:gh-pr-115"]}
],"meta":{"last_page":1,"total":11}}'

# The same 11 cards with NO card carrying `triaged` — so --remove has zero targets, which is the
# empty-array path through the write loop (`"${targets_json[@]}"` under `set -u`).
KB_STUB_BOARD_NONE_TRIAGED="$(printf '%s' "$KB_STUB_BOARD_JSON" | jq -c '.data |= map(.tags |= (. // [] | map(select(. != "triaged"))))')"

# --- route table ------------------------------------------------------------------------------
# Prints "<http>\n<body>"; an unmatched request is answered 599 by the stub itself.
# KB_STUB_GET_HTTP forces a non-2xx board read; KB_STUB_PATCH_FAIL_IDS (space-separated card ids)
# forces a per-card write failure.
kb_stub_route() {
    local method="$1" url="$2" id
    case "$method $url" in
        "GET "*/tasks/search.json*)
            if [[ "${KB_STUB_GET_HTTP:-200}" == 2* ]]; then
                printf '%s\n%s' "${KB_STUB_GET_HTTP:-200}" "$KB_STUB_BOARD_JSON"
            else
                printf '%s\n%s' "${KB_STUB_GET_HTTP}" '{"error":"forbidden: token lacks board scope"}'
            fi ;;
        "PATCH "*/tasks/*)
            id="${url##*/tasks/}"; id="${id%.json}"
            if [[ " ${KB_STUB_PATCH_FAIL_IDS:-} " == *" $id "* ]]; then
                printf '%s\n%s' 422 '{"message":"The given data was invalid."}'
            else
                printf '%s\n%s' 200 '{"data":{"id":0}}'
            fi ;;
    esac
}
export -f kb_stub_route

# run_a0 <args…> — invoke the real bin against a FRESH request log, capturing rc/out/err.
run_a0() {
    kb_stub_reset
    rc=0
    out="$("$A0" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
}
GET_SEARCH=(GET /tasks/search.json)
PATCH_TASKS=(PATCH /tasks/)

# ---------------------------------------------------------------------------
echo "== dry run is the DEFAULT and it never writes =="
run_a0
eq "dry run → rc 0"                      "0" "$rc"
eq "dry run header states run mode, direction, and all three counts" \
   "[DRY] ADD triaged to 6 id:*-pr-* card(s) (of 8 pr cards, 11 total)" \
   "$(printf '%s\n' "$out" | head -1)"
eq "dry run previews the first 5 targets only" "5" "$(printf '%s\n' "$out" | grep -c 'would touch card')"
eq "preview names the card and its id: tags" "true" \
   "$(has 'would touch card 1: ["id:gh-pr-101"]' "$out")"
eq "preview omits the non-id tags (they are not the identity)" "false" "$(has 'repo:x' "$out")"
eq "preview reports the elided remainder" "true" "$(has 'and 1 more' "$out")"
# The absence assertion and its witness. The log is written by the stub before any response is
# chosen, and nothing in the run can truncate it — so a zero PATCH count here cannot be the
# "the tool never started" reading.
eq "dry run issued NO write request"     "0" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "witness: the dry run DID reach the API (board was read)" "1" "$(kb_stub_count "${GET_SEARCH[@]}")"

echo "== --remove selects the INVERSE set, still without writing =="
run_a0 --remove
eq "--remove dry → rc 0"                 "0" "$rc"
eq "--remove header states the opposite direction and its own target count" \
   "[DRY] REMOVE triaged from 2 id:*-pr-* card(s) (of 8 pr cards, 11 total)" \
   "$(printf '%s\n' "$out" | head -1)"
eq "--remove previews both targets"      "2" "$(printf '%s\n' "$out" | grep -c 'would touch card')"
eq "--remove preview does not elide (2 ≤ 5)" "false" "$(has 'more' "$out")"
eq "--remove dry issued NO write request" "0" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "witness: the --remove dry run read the board" "1" "$(kb_stub_count "${GET_SEARCH[@]}")"

# ---------------------------------------------------------------------------
echo "== --apply writes one PATCH per target, and ONLY per target =="
run_a0 --apply
eq "--apply → rc 0"                      "0" "$rc"
eq "--apply header says APPLY, not DRY"  "true" "$(has '[APPLY] ADD triaged to 6' "$out")"
eq "--apply reports patched/total"       "true" "$(has 'patched 6/6' "$out")"
eq "--apply issued exactly 6 writes"     "6" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "--apply wrote card 1"                "1" "$(kb_stub_count PATCH /tasks/1.json)"
eq "--apply wrote card 15"               "1" "$(kb_stub_count PATCH /tasks/15.json)"
# The four non-targets, each a different reason to be excluded. Their witness is the 6 writes
# above: the run demonstrably wrote, so these zeros are exclusions, not an inert run.
eq "already-triaged PR card 2 not written"      "0" "$(kb_stub_count PATCH /tasks/2.json)"
eq "id: tag without -pr- (card 3) not written"  "0" "$(kb_stub_count PATCH /tasks/3.json)"
eq "empty-tags card 4 not written"              "0" "$(kb_stub_count PATCH /tasks/4.json)"
eq "card with no tags key (5) not written"      "0" "$(kb_stub_count PATCH /tasks/5.json)"

echo "== the write is a READ-MODIFY-WRITE: the other tags survive =="
# A tag write REPLACES the whole array, so this is the assertion that stands between a regression
# and silently stripping every id:/repo: tag off every PR card on a live board.
eq "card 1 body appends triaged and keeps id:+repo:" \
   '{"tags":["id:gh-pr-101","repo:x","triaged"]}' "$(kb_stub_bodies PATCH /tasks/1.json)"
eq "the body carries the tags key ONLY (no incidental fields)" \
   '["tags"]' "$(kb_stub_bodies PATCH /tasks/1.json | jq -c 'keys')"

echo "== --remove --apply strips triaged and keeps the rest =="
run_a0 --remove --apply
eq "--remove --apply → rc 0"             "0" "$rc"
eq "--remove --apply reports 2/2"        "true" "$(has 'patched 2/2' "$out")"
eq "--remove --apply issued exactly 2 writes" "2" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "card 6 body drops ONLY triaged"      '{"tags":["id:gh-pr-103","repo:y"]}' \
   "$(kb_stub_bodies PATCH /tasks/6.json)"
eq "an untriaged PR card is not written in --remove mode" "0" "$(kb_stub_count PATCH /tasks/1.json)"

echo "== zero targets: rc 0, no writes, and no unbound-array crash =="
# The write loop iterates "${targets_json[@]}" under `set -u`; a board with nothing to do is the
# path that would expose an empty-array expansion regression.
KB_STUB_BOARD_JSON="$KB_STUB_BOARD_NONE_TRIAGED" run_a0 --remove --apply
eq "zero targets → rc 0"                 "0" "$rc"
eq "zero targets reports 0/0"            "true" "$(has 'patched 0/0' "$out")"
eq "zero targets issued NO write"        "0" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "witness: the zero-target run read the board" "1" "$(kb_stub_count "${GET_SEARCH[@]}")"
eq "zero targets says so in the header"  "true" "$(has 'REMOVE triaged from 0' "$out")"

# ---------------------------------------------------------------------------
echo "== a failing PATCH is reported per card and fails the run =="
KB_STUB_PATCH_FAIL_IDS="13" run_a0 --apply
eq "one failed write → rc 1"             "1" "$rc"
eq "the failure names the card"          "true" "$(has 'ERR card 13: PATCH failed' "$err")"
eq "the count reports the shortfall"     "true" "$(has 'patched 5/6' "$out")"
eq "the other 5 targets were still attempted" "6" "$(kb_stub_count "${PATCH_TASKS[@]}")"

# ---------------------------------------------------------------------------
echo "== fail-closed: an unreadable board aborts BEFORE any write =="
KB_STUB_GET_HTTP=403 run_a0 --apply
eq "page-1 HTTP 403 → rc 1"              "1" "$rc"
eq "the abort names the board and refuses a partial backfill" "true" \
   "$(has 'board 42 read was incomplete or unreachable — aborting (no partial backfill)' "$err")"
eq "loud fetch surfaces the status (KB_FETCH_LOUD)" "true" "$(has 'HTTP 403' "$err")"
eq "witness: the read WAS attempted (this is a refusal, not a no-op)" "1" \
   "$(kb_stub_count "${GET_SEARCH[@]}")"
# There is deliberately NO "and no card was written" assertion here. On a page-1 failure
# fetch_board_cards emits nothing at all, so zero writes follows from having no targets rather
# than from the refusal — no single regression in this tool can make that assertion fail, and a
# check that cannot fail is decoration (canon #9). The write-absence property IS live on the
# short-read leg below, where the fetcher legitimately emits the partial array, and it is
# asserted there.

echo "== fail-closed: a SHORT READ aborts too (rc 4 is not a success) =="
# The server claims 99 cards and delivers 11. fetch_board_cards returns 4 and still emits the
# partial array — a caller that treated rc 4 as usable would backfill a subset of the board and
# report success. This is the assertion behind the tool's "a partial read must never drive a
# partial backfill" comment.
KB_STUB_BOARD_JSON="$(printf '%s' "$KB_STUB_BOARD_JSON" | jq -c '.meta.total = 99')" \
    run_a0 --apply
eq "short read → rc 1"                   "1" "$rc"
eq "the short read is surfaced as INCOMPLETE" "true" "$(has 'INCOMPLETE' "$err")"
eq "the abort message is the same fail-closed refusal" "true" \
   "$(has 'no partial backfill' "$err")"
eq "no card was written on a short read" "0" "$(kb_stub_count "${PATCH_TASKS[@]}")"
eq "witness: the short read DID deliver rows (11 of a claimed 99)" "true" \
   "$(has 'delivered only 11' "$err")"

# ---------------------------------------------------------------------------
echo "== --board selects the board, and an unknown one is a named refusal =="
run_a0 --board alt
eq "--board alt → rc 0"                  "0" "$rc"
eq "--board alt read board 77, not the default 42" "1" "$(kb_stub_count GET 'board_id=77')"
eq "--board alt did not touch the default board"   "0" "$(kb_stub_count GET 'board_id=42')"
run_a0 --board nosuchboard
eq "unknown --board → rc 2"              "2" "$rc"
eq "the refusal names the missing env file" "true" "$(has '.kanban-nosuchboard-board.env' "$err")"
eq "the refusal lists the boards that DO exist" "true" "$(has 'boards found on this box' "$err")"
eq "an unresolvable board issues no request at all" "0" "$(kb_stub_total)"

echo "== the argument surface refuses before it reaches the board =="
run_a0 --help
eq "--help → rc 0"                       "0" "$rc"
eq "--help prints the usage line"        "usage: dl-a0-backfill-triaged [--board NAME] [--apply] [--remove]" "$out"
eq "--help issues no request"            "0" "$(kb_stub_total)"
run_a0 -h
eq "-h → rc 0"                           "0" "$rc"
eq "-h prints the same usage"            "usage: dl-a0-backfill-triaged [--board NAME] [--apply] [--remove]" "$out"

# MISSING and EMPTY are separate inputs and are asserted separately: the two are the same
# behaviour here only because the guard tests the VALUE, and a regression that dispatched on the
# flag being seen would keep one of them green. Both must name the offending flag — the usage
# line alone left the operator to work out WHICH flag was short, and this tool takes four.
NO_VALUE='dl-a0-backfill-triaged: --board requires a non-empty value'
run_a0 --board ""
eq "--board with an empty value → rc 2"  "2" "$rc"
eq "the empty-value refusal names the offending flag" "$NO_VALUE" "$err"
eq "an empty --board never selects the default board" "0" "$(kb_stub_total)"
run_a0 --board
eq "a trailing --board with no argument → rc 2" "2" "$rc"
eq "a trailing --board is refused identically to an empty one" "$NO_VALUE" "$err"
eq "the trailing-flag refusal does not leak an unbound-variable error" "false" \
   "$(has 'unbound variable' "$err")"
# There is deliberately no "and it issued no request" here, though there is one for the EMPTY
# form above. Measured: with the guard deleted outright, a TRAILING --board still reaches no
# request — the arg loop's own closing `shift` fails on an exhausted stack and `set -e` ends the
# run first. No regression in this guard can make that assertion fail, and a check that cannot
# fail is decoration (canon #9). The empty form has no such backstop, so its zero is live.
run_a0 --bogus
eq "an unknown option → rc 2"            "2" "$rc"
eq "the unknown-option refusal prints usage" "true" "$(has 'usage: dl-a0-backfill-triaged' "$err")"
run_a0 stray
eq "a stray positional → rc 2"           "2" "$rc"

# The witness for the four "no request" zeros above: the identical harness, one argument later,
# does reach the API. Without this the refusals could all be passing for the wrong reason.
run_a0 --remove
eq "witness: the same harness DOES issue a request when the arguments are valid" "1" \
   "$(kb_stub_count "${GET_SEARCH[@]}")"

echo "== a lib-less copy is refused before the argument surface, --help included =="
# The arg loop parses with the lib's kb_require_value, so the lib is sourced AHEAD of it. That
# ordering is caller-visible on a BROKEN install only, and this is where it shows: a copy vendored
# without _kb-board-lib.sh beside it now answers every invocation with the missing-lib refusal at
# rc 1. With the check BELOW the loop it reported the missing lib only for an invocation the loop
# let through: measured lib-less on the pre-change binary, --help answered rc 0 and each arg-loop
# refusal (--bogus, a trailing --board, a stray positional) answered rc 2 with the usage line.
# next-dl, kbcard and adopt-to-dl have always behaved this way; this pins the alignment.
mkdir -p "$TMP/nolib"
cp "$A0" "$TMP/nolib/"
nolib_rc=0
nolib_err="$("$TMP/nolib/dl-a0-backfill-triaged" --help 2>&1 >/dev/null)" || nolib_rc=$?
eq "a lib-less copy refuses --help → rc 1" "1" "$nolib_rc"
eq "the refusal names the lib and how to fix it" "true" \
   "$(has 'shared lib _kb-board-lib.sh not found next to this script' "$nolib_err")"

_summary "dl-a0-backfill-triaged-selftest"
