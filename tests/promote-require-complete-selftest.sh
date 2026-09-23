#!/usr/bin/env bash
# promote-require-complete-selftest.sh — `promote-released-cards --require-complete` (card#10176).
#
# WHAT THIS GUARDS. The flag makes a TERMINAL-stage write conditional on an answer from a
# separate tool. Two directions can each fail silently and they are not the same bug:
#   * the guard does not BITE — an INCOMPLETE card is promoted anyway, which is the defect
#     card#10176 exists to close, arriving again with a flag that looks like it is on;
#   * the guard bites when it was NEVER ASKED — an unflagged run changes, which breaks every
#     consumer that has this tool in release CI today.
# Both are driven below. ⛔ The `--require-complete` arms reach their red by moving the FAR END
# (what `card-completeness` answers), never by removing the flag — a guard verified only by
# "the flag is present and the tool ran" passes just as happily when its verdict is ignored.
#
# WHY A STUB `card-completeness` AND NOT THE REAL ONE. The real tool reads the GitHub API, so
# using it here would make this test a network test and its verdicts unfixable. The stub answers
# from a file, which is what lets each verdict — COMPLETE, INCOMPLETE, UNMEASURED, a missing row,
# and a tool that does not answer at all — be driven deliberately. The real tool's own predicate
# is not this file's subject; `tests/card-completeness-selftest.sh` holds that.
#
# THE STUB IS PLACED BESIDE A COPY OF THE MOVER, not on PATH, because beside-first is the
# resolution order the mover documents for a vendored standalone — so this also exercises that.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
_need -x "$ROOT/bin/promote-released-cards"

_mktmp_scratch --home
# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

# A scratch git repo so `git rev-parse HEAD` is deterministic and does not read this checkout.
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@e.i; git -C "$REPO" config user.name t
: > "$REPO/f"; git -C "$REPO" add -A; git -C "$REPO" commit -qm c1
HEADSHA="$(git -C "$REPO" rev-parse HEAD)"

cat > "$TMP/release-pr.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "dev_branch": "dev",
  "promote": {
    "board_id": "12",
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3",
    "source": "*"
  }
}
JSON
# Two matched cards, neither at the released stage (85), so neither is an idempotent skip.
export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-101"}}
],"meta":{"last_page":1,"total":2}}
JSON
export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export PATH="$TMP/bin:$PATH"

# ── a mover copy with a controllable card-completeness beside it ──────────────────────────
WITH="$TMP/with"; mkdir -p "$WITH"
cp "$ROOT/bin/promote-released-cards" "$WITH/"
cat > "$WITH/card-completeness" <<'SH'
#!/usr/bin/env bash
# stub: prints $CC_OUT verbatim on stdout, $CC_ERR on stderr, exits $CC_RC.
printf '%s' "${CC_ARGS_LOG:+}" ; [ -n "${CC_ARGS_LOG:-}" ] && printf '%s\n' "$*" >> "$CC_ARGS_LOG"
[ -n "${CC_ERR:-}" ] && printf '%s\n' "$CC_ERR" >&2
[ -n "${CC_OUT:-}" ] && printf '%b' "$CC_OUT"
exit "${CC_RC:-0}"
SH
chmod +x "$WITH/card-completeness"
# …and one with NO sibling, for the cannot-apply arm.
WITHOUT="$TMP/without"; mkdir -p "$WITHOUT"
cp "$ROOT/bin/promote-released-cards" "$WITHOUT/"

run() { # run <mover-dir> <extra-args...>
  local d="$1"; shift
  : > "$PATCH_LOG"; rc=0
  out="$(cd "$REPO" && "$d/promote-released-cards" --config "$TMP/release-pr.json" --dls "DL-100,DL-101" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}

echo "== PRESENCE WITNESS: with NO flag, both cards are promoted (the status quo) =="
# Every red below is only meaningful because this arm is green over the same fixture.
unset CC_OUT CC_RC CC_ERR
run "$WITH"
eq "rc 0"                       "0"    "$rc"
eq "card 1 moved"               "true" "$(has '(#1): moved 51 → 85' "$out")"
eq "card 2 moved"               "true" "$(has '(#2): moved 51 → 85' "$out")"
eq "both PATCHed"               "2"    "$(printf '%s\n' "$patched" | command grep -c 'tasks/[12].json' || true)"
eq "no completeness line at all" "false" "$(has 'card-completeness' "$err")"
noflag_out="$out"; noflag_err="$err"

echo "== BYTE-IDENTITY: an unflagged run is unchanged by this feature existing =="
# The contract card#10176 states. Asserted on the SUMMARY line, which is the declared stable
# parse target, and on the whole of stderr, which is where a stray declaration line would land.
eq "summary carries no incomplete term" "false" "$(has 'incomplete,' "$noflag_out")"
eq "summary is the documented shape"    "true"  "$(has 'promote-released-cards: 2 moved, 0 already-released, 0 no-card, 0 failed.' "$noflag_out")"

echo "== the flag ON, every card COMPLETE: the guard passes and both still move =="
export CC_OUT='1\tCOMPLETE\t-\n2\tCOMPLETE\t-\n'; export CC_RC=0
run "$WITH" --require-complete
eq "rc 0"                       "0"    "$rc"
eq "card 1 moved"               "true" "$(has '(#1): moved 51 → 85' "$out")"
eq "card 2 moved"               "true" "$(has '(#2): moved 51 → 85' "$out")"
eq "summary counts 0 incomplete" "true" "$(has '0 incomplete,' "$out")"
eq "declares the guard ON"      "true" "$(has 'card-completeness ON' "$err")"
eq "…naming the integration branch" "true" "$(has "integration 'dev'" "$err")"
eq "…and the release head sha"  "true" "$(has "release head $HEADSHA" "$err")"

echo "== FAR-END ARM: card 2 is INCOMPLETE — it must NOT move, and card 1 must still move =="
# The defect itself. The flag, the config and the board are identical to the green arm above;
# the ONLY thing that moved is the far end's answer.
export CC_OUT='1\tCOMPLETE\t-\n2\tINCOMPLETE\t#990 card-2-part-2 (open)\n'; export CC_RC=5
run "$WITH" --require-complete
eq "card 1 still moved"         "true" "$(has '(#1): moved 51 → 85' "$out")"
eq "card 2 NOT moved"           "false" "$(has '(#2): moved' "$out")"
eq "…and NO PATCH was issued for it" "false" "$(has 'tasks/2.json' "$patched")"
eq "…card 1's PATCH did go"     "true"  "$(has 'tasks/1.json' "$patched")"
eq "reports it INCOMPLETE"      "true" "$(has '(#2): INCOMPLETE' "$out$err")"
eq "…naming the blocking PR"    "true" "$(has '#990 card-2-part-2 (open)' "$err")"
eq "summary counts it"          "true" "$(has '1 incomplete,' "$out")"
eq "…and only 1 moved"          "true" "$(has '1 moved,' "$out")"

echo "== FAIL-CLOSED: UNMEASURED is not COMPLETE =="
export CC_OUT='1\tUNMEASURED\tthe open-PR read returned HTTP 403\n2\tUNMEASURED\tthe open-PR read returned HTTP 403\n'; export CC_RC=6
run "$WITH" --require-complete
eq "nothing moved"              "false" "$(has 'moved 51 → 85' "$out")"
eq "no PATCH at all"            ""      "$patched"
eq "names UNMEASURED"           "true"  "$(has 'UNMEASURED' "$err")"
eq "…and carries the reason"    "true"  "$(has 'HTTP 403' "$err")"
eq "summary counts both"        "true"  "$(has '2 incomplete,' "$out")"

echo "== FAIL-CLOSED: a card the tool returned NO ROW for =="
# A silently short table must not read as a clean bill of health for the missing card.
export CC_OUT='1\tCOMPLETE\t-\n'; export CC_RC=0
run "$WITH" --require-complete
eq "card 1 moved"               "true"  "$(has '(#1): moved' "$out")"
eq "card 2 did NOT"             "false" "$(has '(#2): moved' "$out")"
eq "…reported as NO VERDICT"    "true"  "$(has '(#2): NO VERDICT' "$err")"
eq "…with a reason, not silence" "true" "$(has 'returned no row for this card' "$err")"

echo "== the id match is exact, not a substring =="
# A row for 10176 must not answer for card 1 (nor 176 for 10176): field 1, whole-field.
export CC_OUT='10001\tCOMPLETE\t-\n10002\tCOMPLETE\t-\n'; export CC_RC=0
run "$WITH" --require-complete
eq "neither card is answered"   "false" "$(has 'moved 51 → 85' "$out")"
eq "both read NO VERDICT"       "2"     "$(printf '%s\n' "$err" | command grep -c 'NO VERDICT' || true)"

echo "== a tool that did not ANSWER is not a tool that passed =="
# rc 2 is card-completeness' own refusal (bad usage, missing jq). Promote must refuse, not run
# on with the guard silently off — and must not have written anything.
export CC_OUT=''; export CC_RC=2; export CC_ERR='card-completeness: no --integration'
run "$WITH" --require-complete
eq "promote refuses at rc 2"    "2"  "$rc"
eq "…naming the un-run guard"   "true" "$(has 'exited 2 without answering' "$err")"
eq "…and REFUSING to promote"   "true" "$(has 'REFUSING to promote with the guard un-run' "$err")"
eq "…having PATCHed nothing"    ""   "$patched"
unset CC_ERR

echo "== a guard that CANNOT be applied is a refusal, before any request (card#9756) =="
export CC_OUT='1\tCOMPLETE\t-\n'; export CC_RC=0
run "$WITHOUT" --require-complete
eq "rc 2"                       "2"    "$rc"
eq "names the missing sibling"  "true" "$(has 'needs `card-completeness`' "$err")"
eq "…and says where it looked"  "true" "$(has 'nor on PATH' "$err")"
eq "…and why it refuses"        "true" "$(has 'rather than promoting with the guard silently off' "$err")"
eq "…having PATCHed nothing"    ""     "$patched"
# …and the SAME copy, unflagged, is unaffected: the dependency is the flag's, not the tool's.
run "$WITHOUT"
eq "no flag ⇒ no dependency, rc 0" "0" "$rc"
eq "…and it promotes normally"  "true" "$(has '(#1): moved' "$out")"

echo "== an integration branch is never guessed =="
command grep -v '"dev_branch"' "$TMP/release-pr.json" > "$TMP/nodev.json"
: > "$PATCH_LOG"; rc=0
out="$(cd "$REPO" && "$WITH/promote-released-cards" --config "$TMP/nodev.json" --dls "DL-100" --require-complete 2>"$TMP/err")" || rc=$?
err="$(cat "$TMP/err")"
eq "rc 2"                       "2"    "$rc"
eq "names .dev_branch"          "true" "$(has '`.dev_branch` is absent' "$err")"
eq "…and refuses to guess"      "true" "$(has 'it is never guessed' "$err")"
eq "…having PATCHed nothing"    ""     "$(cat "$PATCH_LOG")"

_summary "promote-require-complete-selftest"
