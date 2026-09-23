#!/usr/bin/env bash
# promote-move-readback-selftest.sh — card#9938. `bin/promote-released-cards` reports a card move
# from a READ-BACK of the card, never from the PATCH's status class, and an outcome it could not
# read is the THIRD outcome (`rc 3`, UNVERIFIED) rather than a success or a failure.
#
# ─────────────────────────── WHAT WENT WRONG, AND WHERE ───────────────────────────
#
# The move loop printed `✓ <ref> (#<id>): moved <cur> → <stage>` on curl success and moved on. A
# `2xx` is the server saying it ACCEPTED the request; it is never the board saying it HOLDS the
# result. The two came apart on this fleet on 2026-05-22 (`sola-coordination#588`): 28 of 28
# cards PATCHed, every call `2xx`, `updated_at` bumped on every card, `workflow_stage_id`
# unchanged on every card — and the run printed 28 `✓ … moved` lines and exited 0. The release
# read as fully promoted, the cards sat in Shipped, and nobody looked again, because the job was
# green. That is the card#8556 class one tool over: a success built out of what was SENT.
#
# ─────────────────── WHY A TEST OF A SUCCESSFUL WRITE PROVES NOTHING HERE ───────────────────
#
# ⛔ The tool under test ALREADY PASSED every "the write worked" case, before the fix and after
# it — that is exactly what reporting from the status class gets you. So the load-bearing rows in
# this file are the two where the status and the board DISAGREE, and neither is reachable through
# a stub that only knows how to succeed:
#
#   § 1  THE UN-APPLIED 2xx — the PATCH answers success and the card does not move. The read-back
#        IS a measurement and it says the mutation did not take, so this is NOT APPLIED **AND
#        KNOWN**: `bin/kbcard`'s rc 1, HARD FAILURE, quoting what the board holds. It is NOT the
#        unverified outcome, and the distinction is the whole of card#8556's ladder — rc 3 is for
#        a write nobody can rule on, and this one has been ruled on.
#   § 2  THE READ-BACK THAT IS NOT A MEASUREMENT — refused (401/403: a card this token cannot
#        read is not a card that did not move), never completed, or a 2xx carrying no readable
#        stage. Nothing here says the card moved and nothing says it did not ⇒ `rc 3`.
#
# § 3 is the genuine success and § 4 the visible refusal: both are REGRESSION rows — the card is
# explicit that the refusal axis (card#9301) already worked and must not move — and both are also
# the CONTROL for §§ 1-2, because a tool that reported everything as unverified would pass those
# two sections and fail these.
#
# § 5 is the sibling write in the same file (canon #7): the owner-tag clear's `{tags}` PATCH had
# the identical shape and the identical gap. It is read back the same way — and its outcome still
# changes NO count and NO exit code, which is a shipped, documented property of this tool
# (README.md § The seat owner tag) and is asserted here rather than left to be assumed.
#
# § 6 is MORE THAN ONE CARD, and it is why §§ 1-4's rc rows were not enough on their own: their
# board holds ONE card, so each of them ran in the single-card `moved == 0 && skipped == 0`
# shape — the one configuration in which the shipped rc-1 rule happened to be true. A release
# promotes many cards. That section drives the rc over the run shapes a multi-card release can
# actually take, and says of each whether card#9938 MOVES that rc or PINS it.
#
# WEAKEST PROPERTY OF A GREEN RUN. Every row drives the real bin as a process against a stub
# server, so it says nothing about a real kanban's behaviour — only about what this tool
# concludes from an answer of a given shape. The stub's own fidelity (that it applies the writes
# it says it applied) is `tests/_promote-curl-stub.sh`'s contract, and it is asserted before the
# rows that depend on it: § 0 for the whole-run knobs, and § 6's own first row for the per-card
# ones, which have to produce ONE board holding two different outcomes.
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

export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}}
],"meta":{"last_page":1,"total":1}}
JSON

export KANBAN_WRITEBACK_TOKEN='kbwb_AAAABBBBCCCCDDDDEEEEFFFF0123456789'
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export GET_LOG="$TMP/gets.log"

# run_promote <extra-args…> — the real bin as a process, over the canned board. $REFS is the
# shipped-ref set it is given: a caller prefixes `REFS=…` (as it does `BOARD_FILE=…`) for the
# multi-card rows, so the two fixtures share ONE runner rather than growing a second copy.
REFS="DL-100"
run_promote() {
    : > "$PATCH_LOG"; : > "$GET_LOG"
    rc=0
    out="$(cd "$TMP" && bash "$PRC" --config "$TMP/release-pr.json" --dls "$REFS" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
    patched="$(cat "$PATCH_LOG")"
    gets="$(cat "$GET_LOG")"
}
# card_reads — how many times the run re-read card 1. The read-back's own witness: a tool that
# stopped reading would pass every "it did not claim a move" row by never claiming anything.
card_reads() { printf '%s\n' "$gets" | command grep -cF '/tasks/1.json' || true; }

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 0 — THE STUB REALLY APPLIES, AND REALLY DECLINES TO APPLY, WHAT IT IS TOLD =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# Before any verdict is read out of this fixture: the instrument that produces the two boards
# §§ 1-3 are about must actually produce two DIFFERENT boards. A stub whose card GET answered
# the same thing either way would make § 1 and § 3 one row, passing for the wrong reason.
# _card_now [env assignments…] — what the stub's server answers for card 1 RIGHT NOW.
_card_now() { PATCH_LOG="$TMP/probe.log" "$@" curl -s -o "$TMP/probe.body" -w '%{http_code}' \
                https://kanban.test/api/v3/tasks/1.json >/dev/null
             jq -r '.data.workflow_stage_id' "$TMP/probe.body"; }
# _patch_card [env assignments…] — one stage PATCH, answered by the same stub.
_patch_card() { PATCH_LOG="$TMP/probe.log" "$@" curl -s -X PATCH -d '{"workflow_stage_id":85}' \
                  -o "$TMP/probe.body" -w '%{http_code}' https://kanban.test/api/v3/tasks/1.json >/dev/null; }
: > "$TMP/probe.log"
eq "before any write, the stub's card GET answers the BOARD's stage" "51" "$(_card_now)"
eq "an APPLIED stage PATCH moves the stub's card to 85"              "85" \
   "$(: > "$TMP/probe.log"; _patch_card; _card_now)"
eq "…and under STUB_STAGE_UNAPPLIED the SAME 2xx moves nothing"      "51" \
   "$(: > "$TMP/probe.log"; _patch_card env STUB_STAGE_UNAPPLIED=1; _card_now env STUB_STAGE_UNAPPLIED=1)"
: > "$TMP/probe.log"
unset -f _card_now _patch_card

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 1 — THE UN-APPLIED 2xx: the PATCH succeeds, the card does not move =="
# ═════════════════════════════════════════════════════════════════════════════════════════
STUB_STAGE_UNAPPLIED=1 run_promote
eq "the PATCH really was issued"                          "true"  "$(has '/tasks/1.json' "$patched")"
eq "…and the card really was re-read"                     "1"     "$(card_reads)"
eq "⭐ NOTHING claims the card moved"                      "false" "$(has '✓ DL-100 (#1): moved' "$out$err")"
eq "⭐ the run says NOT APPLIED, quoting what the board holds" "true" \
   "$(has '✗ DL-100 (#1): move NOT APPLIED — the PATCH answered success and the card reads back in stage 51, not 85. The status is not the move; the read-back is.' "$err")"
eq "…counted on its OWN field, not folded into failed"     "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 NOT APPLIED, 0 failed.' "$out")"
eq "…and the run-level line says the board was READ and disagrees" "true" \
   "$(has 'promote-released-cards: 1 stage PATCH(es) answered success and the card(s) READ BACK IN ANOTHER STAGE — NOT APPLIED (rc 1).' "$err")"
eq "…and NOT as an unverified write (rc 1 is a CLAIM; rc 3 is the refusal to make one)" "false" \
   "$(has 'UNVERIFIED' "$out$err")"
eq "⭐ the run exits 1 — the known-failure rc, not 0"      "1"     "$rc"
eq "…and no owner-tag write followed a move that did not happen" "false" "$(has '"tags"' "$patched")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 2 — THE READ-BACK THAT IS NOT A MEASUREMENT: rc 3, UNVERIFIED =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# Three shapes, because they are three different reasons the read said nothing, and a tool that
# handled one and not the others would still report a move it never saw.
echo "-- 2a: the re-read is REFUSED (403 — a card this token cannot read is not a card that did not move)"
STUB_CARD_STATUS=403 STUB_CARD_BODY='{"message":"This action is unauthorized."}' run_promote
eq "nothing claims the card moved"                        "false" "$(has '✓ DL-100 (#1): moved' "$out")"
eq "⭐ …and nothing claims it did NOT move either"         "false" "$(has 'NOT APPLIED' "$err")"
eq "⭐ the run says UNVERIFIED, with the status and the server's words" "true" \
   "$(has '⚠ DL-100 (#1): move UNVERIFIED — the stage PATCH was SENT and answered success, but its outcome could NOT be read back (HTTP 403, server said: {"message":"This action is unauthorized."}). Nothing here says the card moved and nothing says it did not; re-read before acting.' "$err")"
eq "⭐ the run exits 3 — card#8556's third outcome, adopted here" "3" "$rc"
eq "…and the summary carries the count"                   "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 UNVERIFIED, 0 failed.' "$out")"
eq "…and the run-level line says what to do next"         "true" \
   "$(has 'promote-released-cards: 1 stage PATCH(es) were SENT and answered success, and their outcome could NOT be read back — UNVERIFIED WRITE (rc 3).' "$err")"

echo "-- 2b: the re-read NEVER COMPLETED (no status at all)"
# ⚠ The knob is the CARD-scoped one: $STUB_GET_TRANSPORT kills the board read too, and the tool
# then refuses before any PATCH — the row would pass while testing nothing about a read-back. The
# PATCH must still SUCCEED here, or this would be the refusal axis instead.
STUB_CARD_TRANSPORT=7 run_promote
eq "the PATCH was issued"                                 "true"  "$(has '/tasks/1.json' "$patched")"
eq "nothing claims the card moved"                        "false" "$(has '✓ DL-100 (#1): moved' "$out")"
eq "⭐ UNVERIFIED, naming the request that did not complete" "true" \
   "$(has 'move UNVERIFIED — the stage PATCH was SENT and answered success, but its outcome could NOT be read back (the request DID NOT COMPLETE' "$err")"
eq "⭐ the run exits 3"                                    "3"     "$rc"

echo "-- 2c: the re-read answers 2xx and no stage can be read out of it"
STUB_CARD_BODY='<html><body>502 Bad Gateway</body></html>' run_promote
eq "nothing claims the card moved"                        "false" "$(has '✓ DL-100 (#1): moved' "$out")"
eq "⭐ UNVERIFIED, naming the unreadable success"          "true" \
   "$(has 'move UNVERIFIED — the stage PATCH was SENT and answered success, but its outcome could NOT be read back (the re-read answered success and no workflow_stage_id could be read out of it)' "$err")"
eq "⭐ the run exits 3"                                    "3"     "$rc"
eq "…and no owner-tag write rode on a card nobody could read" "false" "$(has '"tags"' "$patched")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 3 — THE GENUINE SUCCESS: still moved, still rc 0, and now it says what it READ =="
# ═════════════════════════════════════════════════════════════════════════════════════════
run_promote
eq "⭐ the card is reported moved, quoting the stage it read back" "true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85 (read back: the card is in stage 85)' "$out")"
eq "⭐ the run exits 0"                                    "0"     "$rc"
eq "the summary counts it, and carries NO unverified field" "true|false" \
   "$(has '1 moved, 0 already-released, 0 no-card, 0 failed.' "$out")|$(has 'UNVERIFIED' "$out")"
eq "…and NEITHER failure word appears on either stream"   "false|false" \
   "$(has 'NOT APPLIED' "$out$err")|$(has 'UNVERIFIED' "$out$err")"
eq "the move PATCH is still the stage-only one it always was" "true" \
   "$(has_line $'https://kanban.test/api/v3/tasks/1.json\t{"workflow_stage_id":85}' "$patched")"
eq "…and the card was read exactly ONCE (the clear's read is the move's, not a second)" "1" "$(card_reads)"

echo "-- 3b: an already-released card is untouched, and reads back nothing"
cat > "$TMP/board-done.json" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":85,"payload":{"dl_number":"DL-100"}}
],"meta":{"last_page":1,"total":1}}
JSON
BOARD_FILE="$TMP/board-done.json" run_promote
eq "already-released: no PATCH, no read, rc 0"            "|0" "$patched|$rc"
eq "…and it is still reported as already released"        "true" "$(has '= DL-100 (#1): already released' "$out")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 4 — THE VISIBLE REFUSAL IS UNCHANGED (card#9301 must not regress) =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# A refused PATCH never reaches the read-back at all: the server said no, the card really is
# where it was, and issuing a confirming read would be asking a question already answered.
STUB_PATCH_STATUS=403 STUB_PATCH_BODY='{"message":"This action is unauthorized."}' run_promote
eq "⭐ still left-in-place, with the status and the body" "true" \
   "$(has '✗ DL-100 (#1): move failed (left in place) — HTTP 403, server said: {"message":"This action is unauthorized."}' "$err")"
eq "⭐ …and NO read-back was issued for it"                "0"     "$(card_reads)"
eq "…nothing is reported unverified"                      "false" "$(has 'UNVERIFIED' "$out$err")"
eq "⭐ the run exits 1, exactly as before"                 "1"     "$rc"
eq "…and the summary is the one card#9301 shipped"        "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 failed.' "$out")"

echo "-- 4b: a PATCH that never completed still reads NOT CONFIRMED, at rc 1 (a named residual)"
# ⚠ By the adopted contract this IS an unverified write too. It stays on the failed count because
# card#9938 opened the un-applied-2xx axis only; moving a visibly-failed request from rc 1 to
# rc 3 is a change to what this tool reports on the axis card#9301 shipped, and that is its own
# decision to ask for. The bin says so at the arm. This row PINS the residual, so the day it is
# closed it is closed deliberately rather than drifted into.
STUB_PATCH_TRANSPORT=7 run_promote
eq "the request went out"                                 "true"  "$(has '/tasks/1.json' "$patched")"
eq "…and is reported NOT CONFIRMED, never left-in-place" "true|false" \
   "$(has '✗ DL-100 (#1): move NOT CONFIRMED' "$err")|$(has 'left in place' "$err")"
eq "RESIDUAL: it is counted failed and exits 1, not 3"    "1|true" \
   "$rc|$(has '0 moved, 0 already-released, 0 no-card, 1 failed.' "$out")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 5 — THE SIBLING: the owner-tag clear is read back too (canon #7) =="
# ═════════════════════════════════════════════════════════════════════════════════════════
_owned='{"data":{"id":1,"tags":["fr","owner:acme/builder"]}}'
echo "-- 5a: the clear lands"
STUB_CARD_BODY="$_owned" run_promote
eq "the tag PATCH was issued"                             "true" "$(has '{"tags":["fr"]}' "$patched")"
eq "⭐ …and the success line quotes the READ, not the status" "true" \
   "$(has '✓ DL-100 (#1): removed owner tag(s) owner:acme/builder — read back: the card now carries no owner tag' "$out")"
eq "the card was read twice: the move's read-back, then the clear's" "2" "$(card_reads)"
eq "rc 0"                                                 "0"    "$rc"

echo "-- 5b: THE UN-APPLIED TAG 2xx — the PATCH succeeds and the tags do not change"
STUB_CARD_BODY="$_owned" STUB_TAGS_UNAPPLIED=1 run_promote
eq "⭐ NOTHING claims the tags were removed"               "false" "$(has 'removed owner tag(s)' "$out")"
eq "⭐ the run says so, quoting what the card still carries" "true" \
   "$(has '✗ DL-100 (#1): owner tags NOT cleared — the PATCH answered success and the card STILL carries owner:acme/builder. The status is not the write; the read-back is.' "$err")"
eq "⭐ …and the MOVE is unaffected: still moved, still rc 0, still 0 failed" "true|0|true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")|$rc|$(has '1 moved, 0 already-released, 0 no-card, 0 failed.' "$out")"

echo "-- 5c: a card whose tag list cannot be read is never written from nothing"
STUB_CARD_BODY='{"data":{"id":1,"tags":{"0":"owner:acme/builder"}}}' run_promote
eq "no tag PATCH at all (the board replaces the list wholesale)" "false" "$(has '"tags"' "$patched")"
eq "…and the run says why"                                "true" "$(has 'no tag list could be read out of it' "$err")"
eq "…while the MOVE is unaffected"                        "true|0" "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")|$rc"

# ⚠ DECLARED UNDRIVEN — two arms of the clear that NO row here reaches, named rather than left to
# look covered. Both need the clear's OWN read-back (the read AFTER the tags PATCH) to fail while
# the move's read-back succeeded, and the stub's card-read knobs are per-RUN, so the two reads
# cannot be made to differ: `owner tag clear UNVERIFIED — … could NOT be re-read` and its
# no-readable-tag-list twin. The third, `owner tag clear NOT CONFIRMED` (a tags PATCH that never
# completed), was already undriven before card#9938 and README.md § The seat owner tag says so.
# Closing them needs a stub knob scoped to the Nth card read; that is recorded, not smuggled in.

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 6 — MORE THAN ONE CARD: the run shapes the exit policy actually rules on =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# ⛔ THE FIXTURE, NOT THE ASSERTION, BOUNDED WHAT §§ 1-4 COULD REACH. Their board holds ONE
# card, so every row above asserting an rc runs in the single-card `moved == 0 && skipped == 0`
# configuration. `⭐ the run exits 1 — the known-failure rc, not 0` was TRUE there and false of
# every other shape: the NOT-APPLIED outcome was counted into `failed`, whose exit clause asks
# "did this run promote NOTHING AT ALL?", so any run that promoted a card, or found one already
# released, printed `✗ … move NOT APPLIED` and exited 0 (measured on the pre-fix bin). The
# 2026-05-22 release was 28 for 28 un-applied, which that condition happens to catch; ONE card
# landing is all it takes to lose it, and a release promotes many cards.
#
# A real release promotes MANY cards, so the population this section covers is derived from the
# exit policy itself: for each outcome a card can end in — measured un-applied, unreadable,
# visibly refused, applied — a run pairing it with each of the COUNTERS the exit clauses test,
# plus the run where every card is clean. Each row says which of the three rcs it expects and
# whether this card MOVES that rc or PINS it. The per-card stub knobs (the `*_IDS` family) exist
# for this and only this: a whole-run knob makes every card behave the same way, which is the one
# thing a mixed run is not.
#
# ⛔ THE COUNTER LIST IS NOT WRITTEN OUT HERE, AND THAT IS THE FIX RATHER THAN AN OMISSION. This
# paragraph used to name it — "(`moved`, `skipped`)" — and card#9938's own diff falsified it on
# arrival by putting a THIRD counter in a clause, so the one pairing that would have decided the
# new term was the one pairing no row drove. An enumeration inside a denominator is a count in
# longer form: true when written, false on a schedule, and silent either way. It is DERIVED
# instead, by 6§d below, whose `_exit_policy_counters` re-reads the shipped clauses every run and
# reds the moment they test a counter the declared list does not name. The derivation is written
# once, there, rather than copied here where a widening of it would leave a second stale spelling.
cat > "$TMP/board-two.json" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-200"}}
],"meta":{"last_page":1,"total":2}}
JSON
cat > "$TMP/board-two-one-done.json" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":85,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-200"}}
],"meta":{"last_page":1,"total":2}}
JSON
# THREE cards, because two cannot separate the unconditional clause from the `failed` one: a run
# holding a refusal and a measured un-applied card and nothing else satisfies BOTH clauses' terms,
# so it exits 1 whichever decides it. The third card MOVES, which falsifies the `failed` clause's
# `moved == 0` and leaves the unconditional clause as the only route to rc 1 (6i).
cat > "$TMP/board-three.json" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-200"}},
  {"id":3,"workflow_stage_id":51,"payload":{"dl_number":"DL-300"}}
],"meta":{"last_page":1,"total":3}}
JSON
# ⚠ The fixtures are spelled out at every call rather than held in an array: bash decides
# what is an assignment PREFIX at parse time, so an expanded `"${ARR[@]}" run_promote` would try
# to run `REFS=…` as a command.

echo "-- 6§0: the per-card knob really produces ONE board holding TWO different outcomes"
# § 0's leg for the new instrument: a knob that turned out to be whole-run after all would make
# every row below test a uniform board while reading as a mixed one. Driven at the stub, without
# the tool, so it is the FIXTURE being measured and not what the tool concluded from it.
_two_now() { PATCH_LOG="$TMP/probe.log" BOARD_FILE="$TMP/board-two.json" STUB_STAGE_UNAPPLIED_IDS=2 \
               curl -s -o "$TMP/probe.body" -w '%{http_code}' "https://kanban.test/api/v3/tasks/$1.json" >/dev/null
             jq -r '.data.workflow_stage_id' "$TMP/probe.body"; }
_two_patch() { PATCH_LOG="$TMP/probe.log" BOARD_FILE="$TMP/board-two.json" STUB_STAGE_UNAPPLIED_IDS=2 \
                 curl -s -X PATCH -d '{"workflow_stage_id":85}' -o "$TMP/probe.body" -w '%{http_code}' \
                 "https://kanban.test/api/v3/tasks/$1.json" >/dev/null; }
: > "$TMP/probe.log"; _two_patch 1; _two_patch 2
eq "⭐ card 1's 2xx APPLIED and card 2's did not, in one run" "85|51" "$(_two_now 1)|$(_two_now 2)"
: > "$TMP/probe.log"
unset -f _two_now _two_patch

echo "-- 6§0b: …and a per-card REFUSAL stays per-card when its status is not the default"
# The same leg for the OTHER per-card knob, and it is here because the contract for it was false
# in exactly the way § 6 exists to catch: $STUB_PATCH_REFUSE_IDS answered with $STUB_PATCH_STATUS,
# so a caller refusing ONE card with a 422 — the spelling the comment described — refused EVERY
# card and read the uniform run as a mixed one. Driven at the stub, without the tool.
# _patch_st <card-id> [env assignments…] — the status ONE stage PATCH is answered with.
_patch_st() { local i="$1"; shift
              PATCH_LOG="$TMP/probe.log" BOARD_FILE="$TMP/board-two.json" "$@" curl -s -X PATCH \
                -d '{"workflow_stage_id":85}' -o /dev/null -w '%{http_code}' \
                "https://kanban.test/api/v3/tasks/$i.json"; }
: > "$TMP/probe.log"
eq "the id list alone: one card refused 403, the other answered 200" "200|403" \
   "$(_patch_st 1 env STUB_PATCH_REFUSE_IDS=2)|$(_patch_st 2 env STUB_PATCH_REFUSE_IDS=2)"
eq "⭐ …and with a NON-DEFAULT refusal status, the unlisted card still answers 200" "200|422" \
   "$(_patch_st 1 env STUB_PATCH_REFUSE_IDS=2 STUB_PATCH_REFUSE_STATUS=422)|$(_patch_st 2 env STUB_PATCH_REFUSE_IDS=2 STUB_PATCH_REFUSE_STATUS=422)"
eq "⭐ PRECEDENCE: a whole-run status does NOT leak onto the unlisted card" "200|403" \
   "$(_patch_st 1 env STUB_PATCH_REFUSE_IDS=2 STUB_PATCH_STATUS=422)|$(_patch_st 2 env STUB_PATCH_REFUSE_IDS=2 STUB_PATCH_STATUS=422)"
eq "…and with NO id list the whole-run knob still refuses every card" "422|422" \
   "$(_patch_st 1 env STUB_PATCH_STATUS=422)|$(_patch_st 2 env STUB_PATCH_STATUS=422)"
: > "$TMP/probe.log"
unset -f _patch_st

echo "-- 6§d: the DENOMINATOR is re-derived from the shipped exit policy, not written down here"
# ⛔ THE SECTION'S OWN POPULATION IS A DERIVATION (canon #19). The prose above used to name the
# counters the exit clauses test, and the diff that added a third one left that name-list stale on
# arrival — the shape § 6 exists to escape, one level up. This leg re-reads the clauses instead,
# so a counter that ENTERS the exit policy reds HERE rather than shipping as an untested term —
# and that is the whole of the predicate: it compares the counter SET, and nothing in it can check
# that a counter already in the list still has a row (the rows below are what establish that, one
# pairing each). The declared list is the only written copy, and it is GUARDED by this comparison
# rather than trusted.
# ⚠ THE BRACED SPELLING IS IN REACH DELIBERATELY. `"$c"` and `"${c:-0}"` are one counter to bash
# and were two to a `'"\$[a-z_]*"'` reader, which saw only the first — and the second is not
# exotic: this same tool already writes `"${nmiss:-0}"` and `"${nstranded:-0}"` a few clauses up.
# A counter entering the exit policy in the spelling the extractor cannot see is exactly the
# untested term this leg exists to red on, so the control below uses THAT spelling.
#
# ⚠ LOWERCASE IS THE PREDICATE, and it is what tells a COUNTER from the rest: these clauses also
# test `$RC_UNVERIFIED` (the exit value), `$DLS_IN`, `$CARDS_IN` and `$HEAD_REF` (this run's
# inputs), which are not counts of anything and have no row to pair. This tool spells every
# counter lowercase, so the row's scope below is stated as the counters and means exactly them.
# ⚠ AND THAT CONVENTION IS DECLARED HERE, NOT CHECKED — reviewed and DECLINED, with the reason
# (card#9938). An uppercase or unquoted counter is out of the extractor's reach, so such a
# spelling would enter the exit policy unseen by the leg below. It is TRUE at this head — every
# counter `promote-released-cards` initialises is lowercase and quoted — so a guard would red on
# nothing and would be checking a rule that nothing currently violates. What makes the decline
# safe to leave is that the declaration is the CONVENTION itself and not a claim about a
# population that moves independently of it: a counter added in another spelling is breaking the
# stated rule, not outrunning a stale guard. Revisit if a counter is ever added uppercase.
_exit_policy_counters() {
    command sed -n '/^# --- exit policy/,$p' "$1" | command grep '^if \[ ' \
      | command grep -oE '"\$\{?[a-z_]+' | tr -d '"${' | sort -u | tr '\n' ' ' || true
}
eq "⭐ the exit clauses test exactly these counters" \
   "failed moved not_applied skipped unverified " "$(_exit_policy_counters "$PRC")"
# CONTROL, because a derivation nobody has seen move is a decoration: a clause that GAINS a term
# must change that answer — which is exactly the edit this leg failed to catch when it did not
# exist. `guarded` is a real counter of this tool that no exit clause tests.
sed 's/^if \[ "\$failed" -gt 0 \]/if [ "${guarded:-0}" = 0 ] \&\& [ "$failed" -gt 0 ]/' "$PRC" > "$TMP/prc-mutant"
eq "⭐ …and a counter ADDED to a clause shows up in the derivation (the control)" \
   "failed guarded moved not_applied skipped unverified " "$(_exit_policy_counters "$TMP/prc-mutant")"
unset -f _exit_policy_counters

echo "-- 6a: one card MOVES and one is measured NOT APPLIED — the 2026-05-22 shape"
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" STUB_STAGE_UNAPPLIED_IDS=2 run_promote
eq "the card that moved is reported from its read-back"   "true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85 (read back: the card is in stage 85)' "$out")"
eq "…and the card that did not is named, quoting the board" "true" \
   "$(has '✗ DL-200 (#2): move NOT APPLIED — the PATCH answered success and the card reads back in stage 51, not 85.' "$err")"
eq "…both counted, each on its own field"                 "true" \
   "$(has '1 moved, 0 already-released, 0 no-card, 1 NOT APPLIED, 0 failed.' "$out")"
eq "⭐ THE RUN GATES: rc 1 with moved > 0 (it was rc 0 before)" "1" "$rc"

echo "-- 6b: one card ALREADY RELEASED and one measured NOT APPLIED (moved == 0, skipped == 1)"
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two-one-done.json" STUB_STAGE_UNAPPLIED_IDS=2 run_promote
eq "the released card is skipped, the other is NOT APPLIED" "true|true" \
   "$(has '= DL-100 (#1): already released' "$out")|$(has '✗ DL-200 (#2): move NOT APPLIED' "$err")"
eq "…counted"                                             "true" \
   "$(has '0 moved, 1 already-released, 0 no-card, 1 NOT APPLIED, 0 failed.' "$out")"
eq "⭐ THE RUN GATES: rc 1 with skipped > 0 (it was rc 0 before)" "1" "$rc"

echo "-- 6c: one card moves and one read-back NEVER COMPLETES — rc 3, unchanged (a pin)"
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" STUB_CARD_TRANSPORT_IDS=2 run_promote
eq "the moved card is reported, the other is UNVERIFIED"  "true|true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")|$(has '⚠ DL-200 (#2): move UNVERIFIED' "$err")"
eq "…and nothing claims the unreadable card did NOT move" "false" "$(has 'NOT APPLIED' "$out$err")"
eq "…counted"                                             "true" \
   "$(has '1 moved, 0 already-released, 0 no-card, 1 UNVERIFIED, 0 failed.' "$out")"
eq "⭐ rc 3 with moved > 0 — the rc the unverified arm already had" "3" "$rc"

echo "-- 6d: every card moves — rc 0, and neither failure word is anywhere"
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" run_promote
eq "both cards reported from their read-backs"            "true|true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")|$(has '✓ DL-200 (#2): moved 51 → 85' "$out")"
eq "the summary is the byte-identical pre-card#9938 one"  "true" \
   "$(has '2 moved, 0 already-released, 0 no-card, 0 failed.' "$out")"
eq "…with NEITHER new field on it, on either stream"      "false|false" \
   "$(has 'NOT APPLIED' "$out$err")|$(has 'UNVERIFIED' "$out$err")"
eq "⭐ rc 0"                                               "0" "$rc"

echo "-- 6e: BOTH read-back outcomes in ONE run — the measured one decides the rc"
# The precedence is a ruling, so it is asserted rather than left to whichever clause runs first:
# rc 3 says NOBODY KNOWS and rc 1 is a MEASUREMENT that the write did not take, so a run holding
# both answers with the measurement. ⛔ AND THE LOSING OUTCOME KEEPS ITS LINE: the rc can carry
# one verdict, the operator needs both, so neither run-level line may sit behind the other's exit.
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" STUB_STAGE_UNAPPLIED_IDS=1 STUB_CARD_TRANSPORT_IDS=2 run_promote
eq "one card is measured un-applied, the other unreadable" "true|true" \
   "$(has '✗ DL-100 (#1): move NOT APPLIED' "$err")|$(has '⚠ DL-200 (#2): move UNVERIFIED' "$err")"
eq "…both counted, on their own fields"                   "true" \
   "$(has '0 moved, 0 already-released, 0 no-card, 1 NOT APPLIED, 1 UNVERIFIED, 0 failed.' "$out")"
eq "⭐ BOTH run-level lines are printed — neither outcome goes silent" "true|true" \
   "$(has 'READ BACK IN ANOTHER STAGE — NOT APPLIED (rc 1).' "$err")|$(has 'could NOT be read back — UNVERIFIED WRITE (rc 3).' "$err")"
eq "⭐ rc 1 — the MEASUREMENT outranks the absence of one"  "1" "$rc"

echo "-- 6f: RESIDUAL — a VISIBLY refused move beside a skipped card still exits 0"
# ⚠ Pinned, not endorsed. This is the acceptance card#9301 shipped: `failed`'s clause asks "did
# this run promote nothing at all?", and a run with an already-released card has an answer that
# is not "nothing". card#9938 opened the un-applied-2xx axis only, and widening this one changes
# what the tool reports on runs it has always called green — its own decision to ask for. What
# card#9938 owes is that docs/INSTALL.md §4 states the CONDITION rather than an unconditional
# rc-1 rule, and this row is what makes that statement falsifiable.
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two-one-done.json" STUB_PATCH_STATUS=403 STUB_PATCH_BODY='{"message":"This action is unauthorized."}' run_promote
eq "the refusal is reported, with the status and the body" "true" \
   "$(has '✗ DL-200 (#2): move failed (left in place) — HTTP 403' "$err")"
eq "…counted as a failure, and nothing is read back"      "true|false" \
   "$(has '0 moved, 1 already-released, 0 no-card, 1 failed.' "$out")|$(has 'NOT APPLIED' "$out$err")"
eq "⚠ RESIDUAL: the run exits 0"                          "0" "$rc"

echo "-- 6g: RESIDUAL, the other half — a refused move beside a card that DID move exits 0"
# The `moved == 0` term, driven the same way 6f drives `skipped == 0`. Both are asserted rather
# than reasoned from the clause, because the whole finding this section answers was a clause
# read correctly and never RUN in the shape that falsifies it.
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" STUB_PATCH_REFUSE_IDS=2 STUB_PATCH_BODY='{"message":"This action is unauthorized."}' run_promote
eq "one card moved and one was refused"                   "true|true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85 (read back: the card is in stage 85)' "$out")|$(has '✗ DL-200 (#2): move failed (left in place) — HTTP 403' "$err")"
eq "…and no read-back was issued for the refused one"     "false" "$(has 'DL-200 (#2): move NOT APPLIED' "$err")"
eq "…counted"                                             "true" \
   "$(has '1 moved, 0 already-released, 0 no-card, 1 failed.' "$out")"
eq "⚠ RESIDUAL: the run exits 0"                          "0" "$rc"

echo "-- 6h: a VISIBLY REFUSED move beside an UNREADABLE one — the refusal decides the rc"
# ⛔ THE PAIRING THE `failed` CLAUSE'S TERMS TURN ON, and the one no row drove while the clause
# carried an `$unverified = 0` term: with it, this run fell past rc 1 into rc 3, and a gate reading
# rc 3 as the published "not always a failed one / re-running is safe" would have swallowed a 403
# that re-running does not fix. 6e is the other route (a MEASURED un-applied card beside an
# unreadable one); this is the refused one, and the ladder answers both the same way, unscoped: a
# run that has measured one of its cards does not hedge. Nothing moved and nothing was already
# released, so the `failed` clause's own terms are satisfied and the residual 6f/6g pin is not in
# play — the only question this row asks is whether the unreadable card demotes the refusal.
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two.json" STUB_PATCH_REFUSE_IDS=1 \
  STUB_PATCH_BODY='{"message":"This action is unauthorized."}' STUB_CARD_TRANSPORT_IDS=2 run_promote
eq "one card is visibly refused, the other's read-back never completes" "true|true" \
   "$(has '✗ DL-100 (#1): move failed (left in place) — HTTP 403' "$err")|$(has '⚠ DL-200 (#2): move UNVERIFIED' "$err")"
eq "…and nothing claims either card was measured in another stage" "false" "$(has 'NOT APPLIED' "$out$err")"
eq "…both counted, on their own fields"                   "true" \
   "$(has '0 moved, 0 already-released, 0 no-card, 1 UNVERIFIED, 1 failed.' "$out")"
eq "⭐ the UNVERIFIED run-level line is still printed — the losing outcome keeps its cards" "true" \
   "$(has 'could NOT be read back — UNVERIFIED WRITE (rc 3).' "$err")"
eq "⭐ THE RUN EXITS 1 — a KNOWN refusal is not demoted by a card nobody could read" "1" "$rc"

echo "-- 6i: a MEASURED un-applied card beside a VISIBLY REFUSED one AND a card that moved"
# ⛔ THE ONLY ROW COVERING THE UNCONDITIONAL CLAUSE AGAINST `failed`. That clause carries no
# run-shape term, and "it reads no counter" is what this row ESTABLISHES rather than what it may
# assume — the same reasoning, one clause over, was live on the sibling arm and shipped. Its other
# pairings are covered (`moved` 6a, `skipped` 6b, `unverified` 6e); a `$failed = 0` term added
# here is invisible to all three, and it exits a MEASURED un-applied card at 0 — card#9938's whole
# defect, back. The card that MOVES is load-bearing, not scenery: without it the `failed` clause
# answers 1 on its own terms and the row cannot tell which clause decided the rc.
REFS=DL-100,DL-200,DL-300 BOARD_FILE="$TMP/board-three.json" STUB_PATCH_REFUSE_IDS=2 \
  STUB_PATCH_BODY='{"message":"This action is unauthorized."}' STUB_STAGE_UNAPPLIED_IDS=3 run_promote
eq "one card moved, one was refused, one read back in the wrong stage" "true|true|true" \
   "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")|$(has '✗ DL-200 (#2): move failed (left in place) — HTTP 403' "$err")|$(has '✗ DL-300 (#3): move NOT APPLIED' "$err")"
eq "…each counted on its own field"                       "true" \
   "$(has '1 moved, 0 already-released, 0 no-card, 1 NOT APPLIED, 1 failed.' "$out")"
eq "⭐ THE RUN EXITS 1 — the unconditional clause answers with a refusal beside it" "1" "$rc"

echo "-- 6j: a card ALREADY RELEASED beside one whose read-back never completes"
# ⛔ THE ONLY ROW COVERING THE UNVERIFIED CLAUSE AGAINST `skipped`. 6c drives it against `moved`
# and nothing drives it against `skipped`, so a `$skipped = 0` term added there reds nowhere in
# this file — and it drops an UNVERIFIED write to rc 0 on the most ordinary release shape there
# is, a run where some of the cards were already released.
REFS=DL-100,DL-200 BOARD_FILE="$TMP/board-two-one-done.json" STUB_CARD_TRANSPORT_IDS=2 run_promote
eq "the released card is skipped, the other is UNVERIFIED" "true|true" \
   "$(has '= DL-100 (#1): already released' "$out")|$(has '⚠ DL-200 (#2): move UNVERIFIED' "$err")"
eq "…counted"                                             "true" \
   "$(has '0 moved, 1 already-released, 0 no-card, 1 UNVERIFIED, 0 failed.' "$out")"
eq "⭐ rc 3 with skipped > 0 — the unverified clause reads no run-shape counter" "3" "$rc"

_summary "promote-move-readback-selftest"
