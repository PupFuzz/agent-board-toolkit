#!/usr/bin/env bash
# promote-token-role-selftest.sh — card#12491. Before any move, `bin/promote-released-cards`
# reads the writeback token's own user and that user's role on the target board, and WARNS —
# stderr, and $GITHUB_STEP_SUMMARY when set — when the role is the owner's or board_admin, or
# cannot be read. The warning is the whole effect: the exit code, the summary line and what is
# promoted are the same as on a Member token. The rule is stated once, in the script's header
# (`KANBAN_WRITEBACK_TOKEN` block); this file holds it.
#
# THE LEGS:
#   § 1  Member — the role the token's user SHOULD hold: no warning, on stderr or in the summary.
#        It is the control for § 2-3: a tool that warned on every run would pass them.
#   § 2  owner and board_admin — the warning fires, names the role, points at INSTALL § 6a.
#   § 3  the role cannot be read (each read refused, a read that never completed, a 2xx with no
#        usable id or row) — the warning fires, and the run still promotes.
#   § 4  THE EXIT CODE AND THE SUMMARY LINE ARE THE SAME on every fixture, on a clean run (rc 0)
#        and on a run whose own outcome is a failure (rc 1, a move read back un-applied) — so the
#        warning can neither add a failure nor hide one.
#   § 5  the reads happen BEFORE the board read and any PATCH, and a refusal body echoing the
#        token is masked in the warning (the warning renders through resp_detail).
#
# WEAKEST PROPERTY OF A GREEN RUN. The server is `tests/_promote-curl-stub.sh`, so this says what
# the tool concludes from answers of these shapes. That the kanban app answers in these shapes
# (`users/current.json` → `.data.id`; `boards/<id>/members.json` → `.data[]` rows of `user_id`,
# `role`, `is_owner`, the owner listed as `board_admin` with `is_owner: true`) is read off the
# kanban app's UsersController::current and BoardMembersController::index, not measured here.
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

ROW_MEMBER='{"user_id":900,"name":"release","role":"board_member","custom_permissions":null,"is_owner":false}'
ROW_ADMIN='{"user_id":900,"name":"release","role":"board_admin","custom_permissions":null,"is_owner":false}'
ROW_OWNER='{"user_id":900,"name":"release","role":"board_admin","custom_permissions":null,"is_owner":true}'
ROW_OTHER_OWNER='{"user_id":1,"name":"someone","role":"board_admin","custom_permissions":null,"is_owner":true}'
members() { printf '{"data":[%s]}' "$(IFS=,; printf '%s' "$*")"; }

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
echo "== § 1 — a Member token: silent =="
# ═════════════════════════════════════════════════════════════════════════════════════════
STUB_MEMBERS_BODY="$(members "$ROW_OTHER_OWNER" "$ROW_MEMBER")" run_promote
eq "both role reads were made (so the silence is a ruling, not a skipped check)" "true|true" \
   "$(has '/users/current.json' "$gets")|$(has '/boards/12/members.json' "$gets")"
eq "⭐ no warning on stderr"                     "false" "$(has "$WARN" "$err")"
eq "⭐ …and nothing in the step summary"         ""      "$summ"
eq "the run promoted, rc 0"                      "true|0" "$(has "$CLEAN_LINE" "$out")|$rc"
BASE_OUT="$out"; BASE_RC="$rc"

echo "-- 1b: a board_viewer / board_custom role is not warned about either"
STUB_MEMBERS_BODY="$(members '{"user_id":900,"role":"board_custom","custom_permissions":{"move":true},"is_owner":false}')" run_promote
eq "board_custom: no warning"                    "false" "$(has "$WARN" "$err")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 2 — owner and board_admin: the warning fires =="
# ═════════════════════════════════════════════════════════════════════════════════════════
echo "-- 2a: the token's user OWNS the board"
STUB_MEMBERS_BODY="$(members "$ROW_OWNER" '{"user_id":7,"role":"board_member","is_owner":false}')" run_promote
eq "⭐ stderr names the OWNER role" "true" \
   "$(has "${WARN}the writeback token's user (#900) is the OWNER of board 12 (role board_admin, is_owner true)." "$err")"
eq "…and points at the INSTALL section"          "true" "$(has "$DOC" "$err")"
eq "⭐ the step summary carries the same line"   "true" \
   "$(has "${WARN}the writeback token's user (#900) is the OWNER of board 12" "$summ")"
eq "⭐ rc and summary line are a Member run's"   "$BASE_RC|$BASE_OUT" "$rc|$out"

echo "-- 2b: the token's user is a board_admin"
STUB_MEMBERS_BODY="$(members "$ROW_OTHER_OWNER" "$ROW_ADMIN")" run_promote
eq "⭐ stderr names the board_admin role" "true" \
   "$(has "${WARN}the writeback token's user (#900) holds role board_admin on board 12." "$err")"
eq "…and points at the INSTALL section"          "true" "$(has "$DOC" "$err")"
eq "⭐ the step summary carries the same line"   "true" \
   "$(has "${WARN}the writeback token's user (#900) holds role board_admin on board 12." "$summ")"
eq "⭐ rc and summary line are a Member run's"   "$BASE_RC|$BASE_OUT" "$rc|$out"

echo "-- 2c: no GITHUB_STEP_SUMMARY (off a runner): stderr only, and nothing breaks"
: > "$PATCH_LOG"; : > "$GET_LOG"; rc=0
out="$(cd "$TMP" && env -u GITHUB_STEP_SUMMARY STUB_MEMBERS_BODY="$(members "$ROW_ADMIN")" \
         bash "$PRC" --config "$TMP/release-pr.json" --dls DL-100 2>"$TMP/err")" || rc=$?
eq "the warning is on stderr"                    "true" "$(has "${WARN}the writeback token's user (#900) holds role board_admin" "$(cat "$TMP/err")")"
eq "rc and summary line are a Member run's"      "$BASE_RC|$BASE_OUT" "$rc|$out"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 3 — the role cannot be read: the warning fires, and the run still promotes =="
# ═════════════════════════════════════════════════════════════════════════════════════════
UNREAD="${WARN}the writeback token's role on board 12 could NOT be read"
# unread_row <label> <expected detail> — the three assertions every unreadable fixture owes.
unread_row() {
    eq "⭐ $1: stderr says the role could not be read, and why" "true" "$(has "$UNREAD ($2" "$err")"
    eq "$1: …and the step summary says so too"     "true" "$(has "$UNREAD" "$summ")"
    eq "⭐ $1: rc and summary line are a Member run's" "$BASE_RC|$BASE_OUT" "$rc|$out"
}
STUB_ME_STATUS=401 STUB_ME_BODY='{"message":"Unauthenticated."}' run_promote
unread_row "users/current.json refused" 'GET users/current.json: HTTP 401, server said: {"message":"Unauthenticated."})'
STUB_ME_TRANSPORT=7 run_promote
unread_row "users/current.json never completed" 'GET users/current.json: the request DID NOT COMPLETE'
STUB_ME_BODY='{"data":{"name":"no id"}}' run_promote
unread_row "users/current.json 2xx with no id" 'GET users/current.json answered success with no numeric .data.id)'
STUB_MEMBERS_STATUS=403 STUB_MEMBERS_BODY='{"message":"This action is unauthorized."}' run_promote
unread_row "members.json refused" 'GET boards/12/members.json: HTTP 403, server said: {"message":"This action is unauthorized."})'
STUB_MEMBERS_BODY='<html>502</html>' run_promote
unread_row "members.json 2xx, not a member list" 'GET boards/12/members.json answered success with no readable row(s)'
STUB_MEMBERS_BODY="$(members "$ROW_OTHER_OWNER")" run_promote
unread_row "no row for the token's user" 'GET boards/12/members.json answered success with 0 row(s) for the token'"'"'s user #900'
STUB_MEMBERS_BODY="$(members '{"user_id":900,"is_owner":false}')" run_promote
unread_row "the row carries no role" 'the member row for the token'"'"'s user #900 carries no role string)'

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 4 — the exit code is the run's own, on a FAILING run too =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# A clean run cannot show the warning hiding a failure. Here the move reads back un-applied, which
# is rc 1 on its own; the warning must neither lift nor change that.
STUB_STAGE_UNAPPLIED=1 run_promote
FAIL_RC="$rc"; FAIL_OUT="$out"
eq "control: a Member run whose move did not apply exits 1, silently" "1|false" "$FAIL_RC|$(has "$WARN" "$err")"
for fx in owner admin unread; do
    case "$fx" in
      owner)  STUB_STAGE_UNAPPLIED=1 STUB_MEMBERS_BODY="$(members "$ROW_OWNER")" run_promote ;;
      admin)  STUB_STAGE_UNAPPLIED=1 STUB_MEMBERS_BODY="$(members "$ROW_ADMIN")" run_promote ;;
      unread) STUB_STAGE_UNAPPLIED=1 STUB_ME_STATUS=500 run_promote ;;
    esac
    eq "⭐ $fx: warned, and the failing run's rc and summary line are unchanged" "true|$FAIL_RC|$FAIL_OUT" \
       "$(has "$WARN" "$err")|$rc|$out"
done

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 5 — order, and the mask =="
# ═════════════════════════════════════════════════════════════════════════════════════════
STUB_MEMBERS_BODY="$(members "$ROW_ADMIN")" run_promote
eq "the role reads are the run's FIRST two requests, before the board read" \
   "https://kanban.test/api/v3/users/current.json|https://kanban.test/api/v3/boards/12/members.json|true" \
   "$(sed -n 1p <<<"$gets")|$(sed -n 2p <<<"$gets")|$(has 'tasks/search.json' "$(sed -n 3p <<<"$gets")")"
eq "the move still went out after the warning"   "true" "$(has '/tasks/1.json' "$patched")"

STUB_MEMBERS_STATUS=403 STUB_MEMBERS_BODY="{\"message\":\"denied\",\"echo\":\"Bearer $KANBAN_WRITEBACK_TOKEN\"}" run_promote
eq "control: the refusal body carried the token, and the warning rendered it" "true" "$(has '"echo":"Bearer ***"' "$err")"
eq "⭐ a refusal body echoing the token is masked on stderr and in the summary" "false|false" \
   "$(has "$KANBAN_WRITEBACK_TOKEN" "$err")|$(has "$KANBAN_WRITEBACK_TOKEN" "$summ")"

_summary "promote-token-role-selftest"
