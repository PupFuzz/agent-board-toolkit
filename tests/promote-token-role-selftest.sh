#!/usr/bin/env bash
# promote-token-role-selftest.sh — card#12491. Before any move, `bin/promote-released-cards`
# reads the writeback token's own user (`GET users/current.json`, whose `boards[]` carries each
# board's `owner_id` and the user's effective `permissions`) and WARNS — stderr, and
# $GITHUB_STEP_SUMMARY when set — when the user owns the target board, holds any permission
# outside the Member set on it, or that cannot be read. The warning is the whole effect: the exit
# code, the summary line and what is promoted are the same as on a Member token. The rule is stated
# once, in the script's header (`KANBAN_WRITEBACK_TOKEN` block); this file holds it.
#
# THE LEGS:
#   § 1  within the Member set — viewer, Member, a custom role granted only Member permissions:
#        no warning, on stderr or in the summary. The control for § 2-3: a tool that warned on
#        every run would pass them.
#   § 2  beyond it — a custom role granted webhook.manage, an Admin, the owner: the warning fires,
#        names what is extra (or the ownership), points at INSTALL § 6a.
#   § 3  the permissions cannot be read (the read refused or never completed, a 2xx with no id, no
#        boards[], the board absent from it, no permissions list, a non-JSON body) — the warning
#        fires, and the run still promotes.
#   § 4  THE EXIT CODE AND THE SUMMARY LINE ARE THE SAME on every fixture, on a clean run (rc 0)
#        and on a run whose own outcome is a failure (rc 1, a move read back un-applied) — so the
#        warning can neither add a failure nor hide one.
#   § 5  the read happens BEFORE the board read and any PATCH, and a refusal body echoing the
#        token is masked in the warning (the warning renders through resp_detail).
#
# WEAKEST PROPERTY OF A GREEN RUN. The server is `tests/_promote-curl-stub.sh`, so this says what
# the tool concludes from answers of these shapes. That the kanban app answers in these shapes, and
# which permissions each role carries, is read off the kanban app's UsersController::current,
# BoardResource and BoardPermissions (its `dev` branch), not measured here.
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

export KANBAN_WRITEBACK_TOKEN='kbwb_RoLeTeStToKeN0123456789abcdef'
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export GET_LOG="$TMP/gets.log"
SUMMARY_FILE="$TMP/step-summary.md"

MEMBER='"board.view","task.create","task.update","task.move","task.archive","subtask.manage","comment.create","attachment.upload","timetracker.manage"'
ADMIN="$MEMBER"',"board.update","board.delete","board.invite","workflow.manage","task.delete","comment.delete_any","attachment.delete","custom_field.manage","webhook.manage","dl_sequence.manage"'
# me <owner_id> <permissions json list body> — a users/current.json answer for user 900 whose
# boards[] holds board 12 (with the given owner and permissions) and an unrelated board 3.
me() { printf '{"data":{"id":900,"boards":[{"id":3,"owner_id":900,"permissions":[%s]},{"id":12,"owner_id":%s,"permissions":[%s]}]}}' "$ADMIN" "$1" "$2"; }
# run_promote — the real bin as a process. Sets rc, out, err, summ (the step summary), patched, gets.
run_promote() {
    : > "$PATCH_LOG"; : > "$GET_LOG"; : > "$SUMMARY_FILE"
    rc=0
    out="$(cd "$TMP" && GITHUB_STEP_SUMMARY="$SUMMARY_FILE" bash "$PRC" --config "$TMP/release-pr.json" --dls DL-100 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
    summ="$(cat "$SUMMARY_FILE")"
    patched="$(cat "$PATCH_LOG")"
    gets="$(cat "$GET_LOG")"
}
WARN='promote-released-cards: ⚠ WARNING — '
DOC='docs/INSTALL.md § 6a, "The writeback token'"'"'s identity"'
CLEAN_LINE='1 moved, 0 already-released, 0 no-card, 0 failed.'

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 1 — within the Member set: silent =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# Board 3 in every fixture is OWNED by the token's user with Admin permissions: a check reading the
# wrong board would warn on every row here.
STUB_ME_BODY="$(me 1 "$MEMBER")" run_promote
eq "the identity read was made (so the silence is a ruling, not a skipped check)" "true" \
   "$(has '/users/current.json' "$gets")"
eq "⭐ Member: no warning on stderr"             "false" "$(has "$WARN" "$err")"
eq "⭐ …and nothing in the step summary"         ""      "$summ"
eq "the run promoted, rc 0"                      "true|0" "$(has "$CLEAN_LINE" "$out")|$rc"
BASE_OUT="$out"; BASE_RC="$rc"
STUB_ME_BODY="$(me 1 '"board.view"')" run_promote
eq "⭐ viewer: no warning"                        "false|" "$(has "$WARN" "$err")|$summ"
# A custom role holding only what a Member has: board.view + the inherited set + create/update/move.
STUB_ME_BODY="$(me 1 '"board.view","task.create","task.move","task.archive","comment.create"')" run_promote
eq "⭐ custom role within the Member set: no warning" "false|" "$(has "$WARN" "$err")|$summ"
eq "…and rc and summary line are a Member run's" "$BASE_RC|$BASE_OUT" "$rc|$out"
STUB_ME_BODY="$(me null "$MEMBER")" run_promote
eq "an orphaned board (owner_id null) with Member permissions: no warning" "false" "$(has "$WARN" "$err")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 2 — beyond the Member set: the warning fires =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# beyond_row <label> <expected stderr fragment> — the assertions every beyond-Member fixture owes.
beyond_row() {
    eq "⭐ $1: stderr names it"                      "true" "$(has "${WARN}$2" "$err")"
    eq "$1: …and points at the INSTALL section"      "true" "$(has "$DOC" "$err")"
    eq "⭐ $1: the step summary carries the same line" "true" "$(has "${WARN}$2" "$summ")"
    eq "⭐ $1: rc and summary line are a Member run's" "$BASE_RC|$BASE_OUT" "$rc|$out"
}
STUB_ME_BODY="$(me 1 "$MEMBER"',"webhook.manage"')" run_promote
beyond_row "custom role granted webhook.manage" "the writeback token's user (#900) holds permissions on board 12 beyond a Member's: webhook.manage."
STUB_ME_BODY="$(me 1 "$MEMBER"',"task.delete"')" run_promote
beyond_row "custom role granted task.delete" "the writeback token's user (#900) holds permissions on board 12 beyond a Member's: task.delete."
STUB_ME_BODY="$(me 1 "$ADMIN")" run_promote
beyond_row "board_admin" "the writeback token's user (#900) holds permissions on board 12 beyond a Member's: board.update, board.delete, board.invite, workflow.manage"
STUB_ME_BODY="$(me 900 "$ADMIN")" run_promote
beyond_row "owner" "the writeback token's user (#900) is the OWNER of board 12. An owner holds every Admin permission and can also archive or delete the board"
eq "owner: named as the owner, not as an extra-permission list" "false" "$(has 'beyond a Member' "$err")"

echo "-- 2b: no GITHUB_STEP_SUMMARY (off a runner): stderr only, and nothing breaks"
: > "$PATCH_LOG"; : > "$GET_LOG"; rc=0
out="$(cd "$TMP" && env -u GITHUB_STEP_SUMMARY STUB_ME_BODY="$(me 1 "$ADMIN")" \
         bash "$PRC" --config "$TMP/release-pr.json" --dls DL-100 2>"$TMP/err")" || rc=$?
eq "the warning is on stderr"                    "true" "$(has "${WARN}the writeback token's user (#900) holds permissions on board 12 beyond" "$(cat "$TMP/err")")"
eq "rc and summary line are a Member run's"      "$BASE_RC|$BASE_OUT" "$rc|$out"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 3 — the permissions cannot be read: the warning fires, and the run still promotes =="
# ═════════════════════════════════════════════════════════════════════════════════════════
UNREAD="${WARN}the writeback token's permissions on board 12 could NOT be read"
# unread_row <label> <expected detail> — the three assertions every unreadable fixture owes.
unread_row() {
    eq "⭐ $1: stderr says it could not be read, and why" "true" "$(has "$UNREAD ($2" "$err")"
    eq "$1: …and the step summary says so too"     "true" "$(has "$UNREAD" "$summ")"
    eq "⭐ $1: rc and summary line are a Member run's" "$BASE_RC|$BASE_OUT" "$rc|$out"
}
STUB_ME_STATUS=401 STUB_ME_BODY='{"message":"Unauthenticated."}' run_promote
unread_row "users/current.json refused" 'GET users/current.json: HTTP 401, server said: {"message":"Unauthenticated."})'
STUB_ME_TRANSPORT=7 run_promote
unread_row "users/current.json never completed" 'GET users/current.json: the request DID NOT COMPLETE'
STUB_ME_BODY='{"data":{"name":"no id","boards":[]}}' run_promote
unread_row "2xx with no id" 'users/current.json answered success with no numeric .data.id)'
STUB_ME_BODY='{"data":{"id":900}}' run_promote
unread_row "2xx with no boards[]" 'users/current.json carries no boards[] list)'
STUB_ME_BODY='{"data":{"id":900,"boards":[{"id":3,"owner_id":1,"permissions":["board.view"]}]}}' run_promote
unread_row "target board absent from boards[]" 'board 12 is not in the boards[] of the token user (#900)'
STUB_ME_BODY='{"data":{"id":900,"boards":[{"id":12,"owner_id":1}]}}' run_promote
unread_row "board present, no permissions list" 'board 12 in boards[] carries no permissions list of strings)'
STUB_ME_BODY='<html>502</html>' run_promote
unread_row "2xx, not JSON" 'users/current.json answered success with a body that is not JSON)'

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 4 — the exit code is the run's own, on a FAILING run too =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# A clean run cannot show the warning hiding a failure. Here the move reads back un-applied, which
# is rc 1 on its own; the warning must neither lift nor change that.
STUB_STAGE_UNAPPLIED=1 STUB_ME_BODY="$(me 1 "$MEMBER")" run_promote
FAIL_RC="$rc"; FAIL_OUT="$out"
eq "control: a Member run whose move did not apply exits 1, silently" "1|false" "$FAIL_RC|$(has "$WARN" "$err")"
for fx in owner admin unread; do
    case "$fx" in
      owner)  STUB_STAGE_UNAPPLIED=1 STUB_ME_BODY="$(me 900 "$ADMIN")" run_promote ;;
      admin)  STUB_STAGE_UNAPPLIED=1 STUB_ME_BODY="$(me 1 "$ADMIN")" run_promote ;;
      unread) STUB_STAGE_UNAPPLIED=1 STUB_ME_STATUS=500 run_promote ;;
    esac
    eq "⭐ $fx: warned, and the failing run's rc and summary line are unchanged" "true|$FAIL_RC|$FAIL_OUT" \
       "$(has "$WARN" "$err")|$rc|$out"
done

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 5 — order, and the mask =="
# ═════════════════════════════════════════════════════════════════════════════════════════
STUB_ME_BODY="$(me 1 "$ADMIN")" run_promote
eq "the identity read is the run's FIRST request, before the board read" \
   "https://kanban.test/api/v3/users/current.json|true" \
   "$(sed -n 1p <<<"$gets")|$(has 'tasks/search.json' "$(sed -n 2p <<<"$gets")")"
eq "the move still went out after the warning"   "true" "$(has '/tasks/1.json' "$patched")"

STUB_ME_STATUS=403 STUB_ME_BODY="{\"message\":\"denied\",\"echo\":\"Bearer $KANBAN_WRITEBACK_TOKEN\"}" run_promote
eq "control: the refusal body carried the token, and the warning rendered it" "true" "$(has '"echo":"Bearer ***"' "$err")"
eq "⭐ a refusal body echoing the token is masked on stderr and in the summary" "false|false" \
   "$(has "$KANBAN_WRITEBACK_TOKEN" "$err")|$(has "$KANBAN_WRITEBACK_TOKEN" "$summ")"

_summary "promote-token-role-selftest"
