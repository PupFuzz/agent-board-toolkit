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
# name the card on stderr, count it in its own summary segment, promote everything else, and never
# raise the run's rc. Every one of those four is a cell below, because three of them are exactly
# what a reviewer would "tidy" into a `die`. "Never raise" is only half of rc PARITY, so the rc
# cells run BOTH directions against the pre-change bin's own rc on each shape: a parent that bin
# would have PATCHed must keep the "promoted nothing?" arms quiet (§ 6, § 7 — red on a head that
# withheld it without telling those arms), and a parent it would have stage-guarded or seen
# refused by the completeness gate must NOT (§ 8, § 9, § 10 — red on 77468c8, which counted every
# withheld parent). Every rc cell passes against origin/dev's bin at 7b93cde. The bin gets both
# directions from ONE placement rather than from bookkeeping: the withhold is the last check before
# the write, so a parent the stage guard or the gate stops is reported as exactly that — and those
# cells assert the old REPORT too, not only the old rc.
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
# ⚑ THE `--shipped-stages` CELL IS THE OTHER ORDERING ASSERTION. The withhold is evaluated LAST
# among the pre-write refusals, immediately before the write, because the tag only matters for a
# card that would otherwise MOVE. A parent outside the Shipped-class stages is therefore a stage-
# guard skip, reported and counted exactly as the pre-withhold tool reported it — and a parent the
# completeness gate refuses is a completeness refusal (§ 10). That is what gives rc parity for free.
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
#   #7  a PARENT outside the Shipped-class stages   → stage-guarded under --shipped-stages (ordering)
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

echo "== 5. a parent outside the Shipped-class stages reads as a STAGE-GUARD SKIP, as it always did =="
run_promote 'DL-106' --shipped-stages 51
eq "guarded parent → rc 0"                           "0"     "$rc"
eq "parent #7 was NOT PATCHed"                       "false" "$(has '/tasks/7.json' "$patched")"
eq "#7 is NOT reported as a withheld parent"         "false" "$(has '(#7): carries' "$err")"
eq "#7 IS reported as a stage-guard skip"            "true"  "$(has '(#7): current stage 99 not in a Shipped-class source stage' "$err")"
eq "stderr carries no run-level withhold line"       "false" "$(has 'were WITHHELD' "$err")"
eq "the summary counts it stage-guarded, with no program segment" \
   "promote-released-cards: 0 moved, 0 already-released, 1 stage-guarded, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | tail -n 1)"

echo "== 6. a withheld parent beside a REFUSED move does not turn the run red (rc parity, arm 1) =="
# The rc-1 arm fires on a run that promoted NOTHING AT ALL — `failed` > 0 with `moved` and
# `skipped` both 0. Before the withhold existed the parent here was PATCHed and counted `moved`,
# so this exact run exited 0; a withhold that left `program_held` out of that arm's terms turned
# it into rc 1 over a card that is not a failure. Counting the parent anywhere would be the wrong
# fix (see the summary cell in § 1): the arm is told about it as its own term instead.
STUB_PATCH_REFUSE_IDS=1 run_promote 'DL-100,DL-101'
eq "refused card + withheld parent → rc 0, as before the withhold" "0" "$rc"
eq "the refusal is still reported"                   "true"  "$(has '(#1): move failed' "$err")"
eq "the refusal is still counted" \
   "promote-released-cards: 0 moved, 0 already-released, 1 program-withheld, 0 no-card, 1 failed." \
   "$(printf '%s' "$out" | tail -n 1)"
eq "parent #2 was NOT PATCHed"                       "false" "$(has '/tasks/2.json' "$patched")"

echo "== 7. a parent-only match behind a squash tip does not trip the ref-completeness die (arm 2) =="
# Refs DERIVED from git (no --dls/--cards) behind a NON-merge tip, and the only card they reach is
# a parent. Before the withhold that card moved, so `moved` was 1 and the die never asked its
# question; with the parent withheld and no term for it, `moved` is 0 and the die sent the
# operator after dropped refs at rc 2 — refs that demonstrably arrived and matched a card.
GITDIR="$TMP/gitfx"; mkdir -p "$GITDIR"
git -C "$GITDIR" init -q -b main
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
git -C "$GITDIR" tag v0.0.1
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "release: v0.0.2 DL-101 squashed"
: > "$PATCH_LOG"
rc=0; out="$(cd "$GITDIR" && "$PRC" --config "$TMP/release-pr.json" 2>"$TMP/err")" || rc=$?
err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
eq "parent-only match, squash tip → rc 0, as before the withhold" "0" "$rc"
eq "the die did not fire"                            "false" "$(has 'not a merge commit' "$err")"
eq "the parent was named as withheld"                "true"  "$(has '(#2): carries' "$err")"
eq "nothing was PATCHed"                             ""      "$patched"

echo "== 8. a parent the pre-withhold bin would NOT have moved leaves the ref-completeness die armed (run A) =="
# The other direction of § 7, and the reason the exit arms count only a parent the old bin would
# have PATCHed. Parent #7 sits OUTSIDE the Shipped-class stages, so before the withhold existed the
# stage guard skipped it, `moved` stayed 0, and behind this squash tip the die fired at rc 2. A term
# that counted EVERY withheld parent kept that die quiet — a withhold LOWERING an rc the run always
# had. RED on 77468c8 (rc 0); origin/dev's bin is rc 2 on this exact run.
GITA="$TMP/gitA"; mkdir -p "$GITA"
git -C "$GITA" init -q -b main
git -C "$GITA" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
git -C "$GITA" tag v0.0.1
git -C "$GITA" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "release: v0.0.2 DL-106 squashed"
: > "$PATCH_LOG"
rc=0; out="$(cd "$GITA" && "$PRC" --config "$TMP/release-pr.json" --shipped-stages 51 2>"$TMP/err")" || rc=$?
err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
eq "stage-guarded parent only, squash tip → rc 2, as before the withhold" "2" "$rc"
eq "the die fired"                                   "true"  "$(has 'not a merge commit' "$err")"
eq "the parent is reported as stage-guarded, as before" "true" "$(has '(#7): current stage 99 not in a Shipped-class' "$err")"
eq "the parent is NOT reported as withheld"          "false" "$(has '(#7): carries' "$err")"
eq "nothing was PATCHed"                             ""      "$patched"

echo "== 9. a stage-guarded parent does not quiet the rc-1 arm over a refused move (run B) =="
# Before the withhold, #7 here was a stage-guard skip — it never reached the PATCH, never counted
# `moved` — so card #1's refused move was a run that promoted nothing, and exited 1. RED on
# 77468c8 (rc 0 with `1 failed` on the line); origin/dev's bin is rc 1.
STUB_PATCH_REFUSE_IDS=1 run_promote 'DL-100,DL-106' --shipped-stages 51
eq "refused card + stage-guarded parent → rc 1, as before the withhold" "1" "$rc"
eq "the refusal is reported"                         "true"  "$(has '(#1): move failed' "$err")"
eq "the parent is reported as stage-guarded, as before" "true" "$(has '(#7): current stage 99 not in a Shipped-class' "$err")"
eq "the parent is NOT reported as withheld"          "false" "$(has '(#7): carries' "$err")"
eq "the summary is the pre-withhold one" \
   "promote-released-cards: 0 moved, 0 already-released, 1 stage-guarded, 0 no-card, 1 failed." \
   "$(printf '%s' "$out" | tail -n 1)"
eq "parent #7 was NOT PATCHed"                       "false" "$(has '/tasks/7.json' "$patched")"

echo "== 10. under --require-complete a parent keeps the verdict the gate would have given it =="
# The oracle is a stub (`--completeness PATH`), so no GitHub lookup is made. It is asked about the
# MATCHED set, which includes the parent — exactly as the pre-withhold bin asked — so reading the
# parent's verdict costs no request. Before the withhold an INCOMPLETE or UNMEASURED parent was a
# completeness refusal: rc 5, or rc 2 behind a squash tip. A COMPLETE one was PATCHed and counted
# `moved`, which is the § 6 shape again under the flag.
ORACLE="$TMP/oracle"
_oracle() {
    local orc="$1"; shift
    { printf '#!/usr/bin/env bash\n'
      local line
      for line in "$@"; do printf 'printf %%s\\\\n %s\n' "$(printf '%q' "$line")"; done
      printf 'exit %s\n' "$orc"
    } > "$ORACLE"
    chmod +x "$ORACLE"
}
_oracle 5 "1	COMPLETE	-" "2	INCOMPLETE	#99 (open)"
run_promote 'DL-100,DL-101' --require-complete --completeness "$ORACLE"
eq "INCOMPLETE parent beside a promoted card → rc 5, as before the withhold" "5" "$rc"
eq "ordinary card #1 WAS PATCHed"                    "true"  "$(has '/tasks/1.json' "$patched")"
eq "parent #2 was NOT PATCHed"                       "false" "$(has '/tasks/2.json' "$patched")"
eq "the parent is reported INCOMPLETE, as before"    "true"  "$(has '(#2): INCOMPLETE — ' "$err")"
eq "the parent's line carries the gate's verdict"    "true"  "$(has '#99 (open)' "$err")"
eq "the parent is NOT reported as withheld"          "false" "$(has '(#2): carries' "$err")"
eq "a run-level FAILED line explains the rc 5"       "true"  "$(has 'FAILED —' "$err")"
eq "the summary counts it completeness-refused, with no program segment" \
   "promote-released-cards: 1 moved, 0 already-released, 1 completeness-refused, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | tail -n 1)"

_oracle 6 "1	COMPLETE	-"
run_promote 'DL-100,DL-101' --require-complete --completeness "$ORACLE"
eq "UNMEASURED parent (no verdict line) → rc 5, as before the withhold" "5" "$rc"
eq "the parent is reported UNMEASURED, not withheld" "true"  "$(has '(#2): completeness UNMEASURED' "$err")"

_oracle 0 "1	COMPLETE	-" "2	COMPLETE	-"
STUB_PATCH_REFUSE_IDS=1 run_promote 'DL-100,DL-101' --require-complete --completeness "$ORACLE"
eq "COMPLETE parent + refused card → rc 0, as before the withhold (it would have moved)" "0" "$rc"
eq "the COMPLETE parent passed the gate and was WITHHELD" "true" "$(has '(#2): carries' "$err")"
eq "the summary puts program-withheld after completeness-refused (loop order)" \
   "promote-released-cards: 0 moved, 0 already-released, 0 completeness-refused, 1 program-withheld, 0 no-card, 1 failed." \
   "$(printf '%s' "$out" | tail -n 1)"

_oracle 5 "2	INCOMPLETE	#99 (open)"
: > "$PATCH_LOG"
rc=0; out="$(cd "$GITDIR" && "$PRC" --config "$TMP/release-pr.json" --require-complete --completeness "$ORACLE" 2>"$TMP/err")" || rc=$?
err="$(cat "$TMP/err")"
eq "INCOMPLETE parent only, squash tip → rc 2, as before the withhold" "2" "$rc"
eq "  … the die fired"                               "true"  "$(has 'not a merge commit' "$err")"
eq "  … the parent is reported INCOMPLETE, not withheld" "true" "$(has '(#2): INCOMPLETE — ' "$err")"

_summary "promote-program-withhold-selftest"
