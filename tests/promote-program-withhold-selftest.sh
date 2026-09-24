#!/usr/bin/env bash
# promote-program-withhold-selftest.sh — deterministic, network-free end-to-end checks for the
# PROGRAM-PARENT WITHHOLD in bin/promote-released-cards (toolkit card#10068).
#
# WHY THIS FILE EXISTS. A card carrying the `program` tag names SEVERAL LEGS rather than one
# deliverable. A release ships one leg, the card's `dl_number`/`pr_number` matches, and the mover
# puts the PARENT in the terminal stage — the one nobody re-reads — while the other legs are
# unbuilt and stop being offered by any queue. The work is still written on the card; the card
# just reads DONE. The bridge has a guard for this shape; this tool had none, and on an install
# with no bridge it is the ONLY writer of the terminal stage, which is exactly where the predicate
# most needs to exist.
#
# ⛔ THE WITHHOLD IS NOT A REFUSAL, AND THIS FILE ASSERTS THE DIFFERENCE RATHER THAN ASSUMING IT.
# This tool is vendored SHA-pinned into other repos' release workflows, so a hard failure here
# becomes THEIR broken release over a card that is not theirs. The shipped behaviour is therefore:
# name the card on stderr, count it in its own summary segment, promote everything else, exit on
# the ladder the run would have exited on anyway. Every one of those four is a cell below, because
# three of them are exactly what a reviewer would "tidy" into a `die`.
#
# ⚠ TWO ARMS, AND NEITHER IS THE OTHER'S BACKGROUND. A guard that withholds EVERYTHING passes a
# one-armed subject test, and promoting cards is this tool's whole job — so the ordinary card and
# the parent are in ONE fixture, driven by ONE invocation, and both are asserted every run. The
# two mutants each of them was watched red against are recorded at the bottom of this header.
#
# THE HARNESS is the shared `_promote-curl-stub.sh` (its contract is documented there): the REAL
# script as a process, over a canned board, with its PATCH set observable. `--dls` drives ref
# derivation so no git-range or merge-tip stubbing is needed. `source: "*"` in the fixture config
# is the DECLARATION that this board tracks one repo, which is what keeps every assertion here a
# claim about the withhold rather than about repo qualification.
#
# ⛔ THE TAG SPELLING IS PINNED AS A LITERAL HERE, NOT READ OUT OF THE BIN, and that is the point
# of the cell that checks it. `program` is a CROSS-REPO spelling: the bridge's own
# `ProgramCardGuard::TAG` matches it exactly (the board stores tags verbatim — it normalizes
# neither case nor whitespace), so the two writers of the terminal stage agree about which cards
# are parents only while the two strings are byte-identical. A fixture that derived its tag from
# the bin would follow any drift silently and could never red on the one change that splits them.
# So the literal is written here, the bin's own constant is asserted equal to it, and a change to
# either side reds. ⚠ WHAT THIS CANNOT REACH, said rather than implied: nothing in this tree can
# read the bridge's constant, so this cell holds the toolkit side to the DECLARED spelling and is
# not evidence that the far end still uses it.
#
# ⚑ THE `already released` CELL IS AN ORDERING ASSERTION, not a redundant one: the withhold is
# evaluated AFTER the idempotence check, so a parent that somebody already moved by hand reads as
# what it is instead of being reported as held back from a stage it is already in.
#
# ⚑ THE `--shipped-stages` CELL IS THE OTHER ORDERING ASSERTION. The withhold is evaluated FIRST
# among the pre-write refusals, so the reason an operator reads for one card does not depend on
# which optional flags another repo's workflow happens to pass. A parent outside the Shipped-class
# stages is reported as a PARENT on every install, not as a stage-guard skip on some of them.
#
# ── THE TWO MUTANTS EACH ARM WAS WATCHED RED AGAINST (card#10068, reproducible) ──────────────
#   SUBJECT ARM — run this file against the PRE-CHANGE bin, over this identical fixture:
#       mkdir -p /tmp/pre/bin && cp -r tests /tmp/pre/tests
#       git show <pre-change-rev>:bin/promote-released-cards > /tmp/pre/bin/promote-released-cards
#       chmod +x /tmp/pre/bin/promote-released-cards && bash /tmp/pre/tests/$(basename "$0")
#     The parent card is PATCHed into the terminal stage, the summary carries no
#     `program-withheld` segment and counts the parent as `moved`. That is the defect.
#   CONTROL ARM — force the predicate true in the bin's correlation
#     (`| true as $prog`, replacing the `index($ptag)` line):
#     every card is withheld, `moved` drops to 0 and the ordinary-card cells red. That is the
#     inverted control: it proves the control arm MEASURES the subject rather than merely
#     responding to it, and it is the mutant a one-armed test cannot see.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

# The cross-repo spelling. See the header for why it is a literal.
TAG='program'

cat > "$TMP/release-pr.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": {
    "board_id": "12",
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3",
    "source": "*"
  }
}
JSON

# ONE fixture, seven cards, every one of them DL-matched by the runs below.
#   #1  an ORDINARY card                            → promoted        (the control arm)
#   #2  a PARENT: tags carry `program`              → WITHHELD        (the subject arm)
#   #3  NO `tags` key at all                        → promoted        (the degrade direction)
#   #4  four near-miss spellings, none of them the tag → promoted     (the predicate discriminates)
#   #5  a PARENT already at the released stage 85   → already-released (ordering vs idempotence)
#   #6  `tags` present but NOT a list               → promoted        (the degrade direction)
#   #7  a PARENT outside the Shipped-class stages   → WITHHELD        (ordering vs --shipped-stages)
export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"tags":["triaged"],"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"tags":["triaged","program"],"payload":{"dl_number":"DL-101"}},
  {"id":3,"workflow_stage_id":51,"payload":{"dl_number":"DL-102"}},
  {"id":4,"workflow_stage_id":51,"tags":["Program","PROGRAM","program ","programme"],"payload":{"dl_number":"DL-103"}},
  {"id":5,"workflow_stage_id":85,"tags":["program"],"payload":{"dl_number":"DL-104"}},
  {"id":6,"workflow_stage_id":51,"tags":"program","payload":{"dl_number":"DL-105"}},
  {"id":7,"workflow_stage_id":99,"tags":["program"],"payload":{"dl_number":"DL-106"}}
],"meta":{"last_page":1,"total":7}}
JSON

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"

# run_promote <dl-list> <extra-args...> — the real script as a process, capturing
# rc / stdout(out) / stderr(err) / the PATCH log(patched).
run_promote() {
    local dls="$1"; shift
    : > "$PATCH_LOG"
    rc=0
    out="$("$PRC" --config "$TMP/release-pr.json" --dls "$dls" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
    patched="$(cat "$PATCH_LOG")"
}

ALL='DL-100,DL-101,DL-102,DL-103,DL-104,DL-105'

echo "== 1. one run, both arms: the parent is withheld and every other matched card promotes =="
run_promote "$ALL"
eq "a withheld parent does not change the rc"        "0"     "$rc"
# THE SUBJECT ARM.
eq "parent #2 was NOT PATCHed"                       "false" "$(has '/tasks/2.json' "$patched")"
eq "the withhold line names the card"                "true"  "$(has '(#2)' "$err")"
eq "the withhold line names the tag"                 "true"  "$(has "carries the \`$TAG\` tag" "$err")"
eq "the withhold line says what a parent IS"         "true"  "$(has 'PARENT card naming SEVERAL legs' "$err")"
eq "the withhold line says the card was left alone"  "true"  "$(has 'WITHHELD, not promoted' "$err")"
eq "the run-level line names the count"              "true"  "$(has '1 card(s) carrying the' "$err")"
eq "the run-level line says it is not a failure"     "true"  "$(has 'This is not a failure' "$err")"
# THE CONTROL ARM — the whole job of this tool, asserted in the same run as the withhold.
eq "ordinary card #1 WAS PATCHed"                    "true"  "$(has '/tasks/1.json' "$patched")"
eq "card #3 (no tags key) WAS PATCHed"               "true"  "$(has '/tasks/3.json' "$patched")"
eq "card #4 (near-miss spellings) WAS PATCHed"       "true"  "$(has '/tasks/4.json' "$patched")"
eq "card #6 (tags not a list) WAS PATCHed"           "true"  "$(has '/tasks/6.json' "$patched")"
eq "parent #5 read as already-released, not withheld" "true" "$(has '(#5): already released' "$out")"
eq "#5 is not ALSO reported as withheld"             "false" "$(has '(#5): carries' "$err")"
# ⛔ THE SUMMARY, WHOLE AND EXACT — the honesty cell. A withheld card is neither promoted nor
# failed, so `moved` must not carry it and no existing count may absorb it; the segment ORDER is
# the order the move loop applies its refusals in. Asserting the entire line is what makes a
# future fold-in visible, which a `has '1 program-withheld'` on its own would not be.
eq "summary: own segment, honest counts, loop order" \
   "promote-released-cards: 4 moved, 1 already-released, 1 program-withheld, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | tail -n 1)"
# The parent MATCHED a ref, so it is not a missing card: sending release-pr-body's coverage report
# after a card that is on the board is the wrong remedy, and `0 no-card` above is only half of it.
eq "the withheld ref is not reported as 'no card'"   "false" "$(has 'matched NO card' "$err")"

echo "== 2. a run with no parent in it keeps a BYTE-IDENTICAL summary line =="
# The guard is unconditional — there is no flag to leave off — so this is the only thing standing
# between it and every consumer that parses this line. It is asserted as the WHOLE line, against
# the exact text this tool printed before the withhold existed.
run_promote 'DL-100'
eq "no-parent run → rc 0"                            "0"     "$rc"
eq "summary carries no program segment at all"       "false" "$(has 'program-withheld' "$out")"
eq "summary line is byte-identical to the pre-change tool" \
   "promote-released-cards: 1 moved, 0 already-released, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | tail -n 1)"
eq "stderr carries no run-level withhold line"       "false" "$(has 'were WITHHELD' "$err")"

echo "== 3. the tag spelling the bin matches is the one this file pins =="
# Read back OUT of the bin, so a silent edit to the constant reds here rather than on the fleet.
eq "bin's PROGRAM_TAG is the declared cross-repo spelling" \
   "$TAG" "$(sed -n "s/^PROGRAM_TAG='\\(.*\\)'\$/\\1/p" "$PRC")"
eq "the spelling is assigned in exactly one place in the bin" \
   "1" "$(command grep -c "^PROGRAM_TAG=" "$PRC")"
# ⛔ THE ONE RESTATEMENT, AND IT IS GUARDED RATHER THAN DELETED. The header block IS the published
# contract — `--help` prints it, and it ships inside a copy vendored standalone with no docs beside
# it — so an operator reading it needs the literal tag, not the name of a shell variable they would
# have to go and resolve. That makes it a second copy of the spelling, which earns a drift check:
# this cell and the one above pin BOTH copies to the same literal, so changing either alone reds.
eq "the published contract states the same spelling the predicate matches" \
   "true" "$(has "MATCH ON THE TAG \`$TAG\`" "$("$PRC" --help 2>&1)")"

echo "== 4. --dry-run previews the withhold and counts nothing as moved =="
run_promote 'DL-100,DL-101' --dry-run
eq "dry-run → rc 0"                                  "0"     "$rc"
eq "dry-run wrote nothing at all"                    ""      "$patched"
eq "dry-run still names the withheld parent"         "true"  "$(has '(#2): carries' "$err")"
eq "dry-run summary keeps the withhold out of moved" \
   "promote-released-cards: 1 moved, 0 already-released, 1 program-withheld, 0 no-card, 0 failed (dry-run)." \
   "$(printf '%s' "$out" | tail -n 1)"

echo "== 5. a parent outside the Shipped-class stages reads as a PARENT, on every install =="
run_promote 'DL-106' --shipped-stages 51
eq "guarded parent → rc 0"                           "0"     "$rc"
eq "parent #7 was NOT PATCHed"                       "false" "$(has '/tasks/7.json' "$patched")"
eq "#7 is reported as a parent"                      "true"  "$(has '(#7): carries' "$err")"
eq "#7 is NOT reported as a stage-guard skip"        "false" "$(has 'not in a Shipped-class source stage' "$err")"
eq "the two counts stay separate on one line" \
   "promote-released-cards: 0 moved, 0 already-released, 1 program-withheld, 0 stage-guarded, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | tail -n 1)"

_summary "promote-program-withhold-selftest"
