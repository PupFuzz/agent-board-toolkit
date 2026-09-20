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
# WEAKEST PROPERTY OF A GREEN RUN. Every row drives the real bin as a process against a stub
# server, so it says nothing about a real kanban's behaviour — only about what this tool
# concludes from an answer of a given shape. The stub's own fidelity (that it applies the writes
# it says it applied) is `tests/_promote-curl-stub.sh`'s contract, and § 0 below asserts the two
# halves of it this file depends on before any row is read.
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

# run_promote <extra-args…> — the real bin as a process, over the canned board.
run_promote() {
    : > "$PATCH_LOG"; : > "$GET_LOG"
    rc=0
    out="$(cd "$TMP" && bash "$PRC" --config "$TMP/release-pr.json" --dls "DL-100" "$@" 2>"$TMP/err")" || rc=$?
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
eq "…counted as one failure and nothing else"             "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 failed.' "$out")"
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
eq "…nothing is reported failed or unverified"            "false" "$(has 'NOT APPLIED' "$err")"
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

_summary "promote-move-readback-selftest"
