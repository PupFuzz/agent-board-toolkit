#!/usr/bin/env bash
# promote-revert-selftest.sh — deterministic, network-free end-to-end checks that
# bin/promote-released-cards does not promote what a revert took back (card#11602).
#
# THE DEFECT. A PR closing a card is squash-merged to the integration branch; later a `git revert`
# of it is pushed directly, with the subject `Revert "feat: x … (#21)"`. The mover derived its
# shipped set from every subject in the range — the original's trailing `(#21)` and both commits'
# DL tokens — so it moved the reverted card to its released stage. And it read a PR number off any
# trailing `(#N)`: git 2.43 and later writes a direct-push revert of revert-PR #25 as
# `Reapply "fix: y (#22)" (#25)`, which it read as #25, promoting revert-PR #25's card.
#
# THE FIX IS ONE IMPLEMENTATION, NOT A SECOND PARSER. The mover asks its sibling
# `release-pr-body --classify-commits` which commits ship (that file's commit_rows header is the
# contract), so these cells assert the MOVER's observable — the PATCH set and its stderr — over a
# real git range, and `tests/release-pr-body-selftest.sh` asserts the generator's over the same
# shapes. The `fix: a (#12) and b` cell is the cross-tool one: neither tool reads #12.
#
# SCOPE, at its weakest: one range per case, a canned board through the shared curl stub, the
# mover as a process. It proves nothing about a live board, and nothing about a revert whose
# message lost git's `This reverts commit` line (an edited message), which neither tool can tell
# from an ordinary commit.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"
_need -x "$HERE/../bin/release-pr-body"

_mktmp_scratch --home

# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export BOARD_FILE="$TMP/board.json"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

CFG="$TMP/release-pr.json"
jq -n '{ref_token_regex:"DL-[0-9]+",promote:{board_id:"12",released_stage_id:"85",api_base:"https://kanban.test/api/v3",source:"acme/widget"}}' > "$CFG"

# THE RANGE, oldest → newest, on separate files:
#   Z  `feat: z DL-2 (#11)` — tagged v0.1.0, so OUTSIDE the range
#   O  `feat: x DL-5 (closes card#7) (#21)` · K `fix: keep DL-6 (#23)`
#   R  O reverted by a direct push: `Revert "feat: x DL-5 (closes card#7) (#21)"`
#   P  `fix: a (#12) and b` — `(#12)` is not trailing: no PR number
#   Y  `fix: y (#22)` · Y1 = Y reverted through PR #25 · Y2 = Y1 reverted by a direct push, spelled
#      as git 2.43 and later spell it: `Reapply "fix: y (#22)" (#25)` — Y ships again; #25 does not
#   RZ Z reverted by a direct push: `Revert "feat: z DL-2 (#11)"` — its original is outside the range
G="$TMP/repo"; g init -q "$G"
_c() { echo "$RANDOM" >> "$G/$1"; g -C "$G" add "$1"; g -C "$G" commit -qm "$2"; g -C "$G" rev-parse HEAD; }
_r() { g -C "$G" revert --no-edit "$1" >/dev/null; g -C "$G" rev-parse HEAD; }
echo 0 > "$G/f"; g -C "$G" add f; g -C "$G" commit -qm "chore: init"
Z="$(_c z "feat: z DL-2 (#11)")"; g -C "$G" tag v0.1.0
O="$(_c o "feat: x DL-5 (closes card#7) (#21)")"; _c k "fix: keep DL-6 (#23)" >/dev/null
R="$(_r "$O")"
_c p "fix: a (#12) and b" >/dev/null
Y="$(_c y "fix: y (#22)")"
_r "$Y" >/dev/null
g -C "$G" commit -q --amend -m "Revert \"fix: y (#22)\" (#25)" -m "This reverts commit $Y."; Y1="$(g -C "$G" rev-parse HEAD)"
g -C "$G" revert --no-edit "$Y1" >/dev/null
g -C "$G" commit -q --amend -m "Reapply \"fix: y (#22)\" (#25)" -m "This reverts commit $Y1."
_r "$Z" >/dev/null

# THE BOARD — one card per ref the range could be read as shipping, every row load-bearing:
#   #1 PR 21 (O, reverted in range)   — must NOT move
#   #2 PR 23 (K)                      — moves: the control that the run promotes at all
#   #3 PR 12 (P's non-trailing mark)  — must NOT move
#   #4 PR 22 (Y, reapplied)           — moves
#   #5 PR 25 (revert-PR Y1, itself reverted; and Y2's trailing mark) — must NOT move
#   #6 DL-5 (O's DL, and R's quoted subject) — must NOT move
#   #7 DL-6 (K)                       — moves
#   #9 DL-2 (Z, outside the range; RZ's quoted subject) — must NOT move
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"pr_number":"21","pr_url":"https://github.com/acme/widget/pull/21"}},
  {"id":2,"workflow_stage_id":51,"payload":{"pr_number":"23","pr_url":"https://github.com/acme/widget/pull/23"}},
  {"id":3,"workflow_stage_id":51,"payload":{"pr_number":"12","pr_url":"https://github.com/acme/widget/pull/12"}},
  {"id":4,"workflow_stage_id":51,"payload":{"pr_number":"22","pr_url":"https://github.com/acme/widget/pull/22"}},
  {"id":5,"workflow_stage_id":51,"payload":{"pr_number":"25","pr_url":"https://github.com/acme/widget/pull/25"}},
  {"id":6,"workflow_stage_id":51,"payload":{"dl_number":"DL-5","repo":"acme/widget"}},
  {"id":7,"workflow_stage_id":51,"payload":{"dl_number":"DL-6","repo":"acme/widget"}},
  {"id":9,"workflow_stage_id":51,"payload":{"dl_number":"DL-2","repo":"acme/widget"}}
],"meta":{"last_page":1,"total":8}}
JSON

# run_in <dir> <bin> [args...] — the mover over <dir>'s range v0.1.0..HEAD.
run_in() {
  local dir="$1" bin="$2"; shift 2
  : > "$PATCH_LOG"; rc=0
  out="$( (cd "$dir" && env GITHUB_ACTIONS=1 GITHUB_REPOSITORY=acme/widget "$bin" --config "$CFG" --base v0.1.0 "$@") 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}
moved() { has "/tasks/$1.json" "$patched"; }

echo "== a direct-push revert of a card's PR, in the range: the card is not promoted =="
run_in "$G" "$PRC"
eq "the run exits 0"                                              "0"     "$rc"
eq "control: K's PR card (#2) moves"                              "true"  "$(moved 2)"
eq "control: K's DL card (#7) moves"                              "true"  "$(moved 7)"
eq "O's PR card (#1) is NOT promoted — O was reverted in the range" "false" "$(moved 1)"
eq "O's DL card (#6) is NOT promoted"                             "false" "$(moved 6)"
eq "stderr names O as reverted, and by which commit" \
   "true" "$(has "⊘ $(g -C "$G" rev-parse --short "$O"): reverted in this range by $(g -C "$G" rev-parse --short "$R")" "$err")"

echo "== \`Reapply \"… (#22)\" (#25)\` is attributed to #22, never to #25 =="
eq "Y's card (#4) moves — the reapply makes it live again"        "true"  "$(moved 4)"
eq "revert-PR #25's card (#5) is NOT promoted"                    "false" "$(moved 5)"

echo "== a revert whose original is outside the range ships nothing =="
eq "Z's DL card (#9), named only by RZ's quoted subject, is NOT promoted" "false" "$(moved 9)"

echo "== \`fix: a (#12) and b\` is no PR number, in this tool as in release-pr-body =="
eq "the #12 card (#3) is NOT promoted"                            "false" "$(moved 3)"
eq "…and release-pr-body credits no PR to that commit either" \
   "" "$(cd "$G" && "$HERE/../bin/release-pr-body" --classify-commits --base v0.1.0 --head HEAD | awk 'BEGIN { FS = "\037" } $1 == "shipped" && $5 == "fix: a (#12) and b" { print $3 }')"

echo "== a mover vendored WITHOUT its sibling refuses a range-derived run =="
mkdir -p "$TMP/alone"; cp "$PRC" "$TMP/alone/promote-released-cards"
run_in "$G" "$TMP/alone/promote-released-cards"
eq "no release-pr-body beside it → rc 2"                          "2"     "$rc"
eq "…before any card is moved"                                    ""      "$patched"
eq "…naming the missing sibling"                                  "true"  "$(has 'release-pr-body is missing or not executable' "$err")"
run_in "$G" "$TMP/alone/promote-released-cards" --dls DL-6
eq "an explicit --dls run does not need it, and moves its card"   "0|true" "$rc|$(moved 7)"

echo "== a squash whose branch reverted a dev commit still ships its own refs =="
# GitHub's squash body (COMMIT_MESSAGES) keeps the branch revert's `This reverts commit W.`, W being
# an ancestor, so the squash IS a revert by its body line — and its own title still ships.
Q="$TMP/squash"; g init -q "$Q"
echo 0 > "$Q/f"; g -C "$Q" add f; g -C "$Q" commit -qm "chore: init"; g -C "$Q" tag v0.1.0
echo 1 > "$Q/w"; g -C "$Q" add w; g -C "$Q" commit -qm "feat: temp workaround DL-3 (#30)"; QW="$(g -C "$Q" rev-parse HEAD)"
g -C "$Q" rm -q w; echo 2 > "$Q/n"; g -C "$Q" add n
g -C "$Q" commit -qm "feat: new thing DL-77 (closes card#50) (#40)" -m "This reverts commit $QW."
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":7,"workflow_stage_id":51,"payload":{"dl_number":"DL-77","repo":"acme/widget"}},
  {"id":8,"workflow_stage_id":51,"payload":{"pr_number":"40","pr_url":"https://github.com/acme/widget/pull/40"}},
  {"id":9,"workflow_stage_id":51,"payload":{"dl_number":"DL-3","repo":"acme/widget"}}
],"meta":{"last_page":1,"total":3}}
JSON
run_in "$Q" "$PRC"
eq "the squash's DL card (#7) moves"                              "0|true" "$rc|$(moved 7)"
eq "…and its PR card (#8)"                                        "true"  "$(moved 8)"
eq "…while the workaround it took back (#9) does not"             "false" "$(moved 9)"

echo "== a shallow clone that cannot read what a revert reverts: NOT MEASURED, not promoted =="
# init · T `feat: t DL-9 (#60)` · B (tagged v0.1.0) · RT = T reverted by a direct push ·
# Q `feat: q DL-6 (#23)`; a depth-3 clone holds Q, RT and B, not T.
S="$TMP/shal-src"; g init -q "$S"
echo 0 > "$S/f"; g -C "$S" add f; g -C "$S" commit -qm "chore: init"
echo 1 > "$S/t"; g -C "$S" add t; g -C "$S" commit -qm "feat: t DL-9 (#60)"; ST="$(g -C "$S" rev-parse HEAD)"
echo 2 > "$S/b"; g -C "$S" add b; g -C "$S" commit -qm "chore: base"; g -C "$S" tag v0.1.0
g -C "$S" revert --no-edit "$ST" >/dev/null; SRT="$(g -C "$S" rev-parse HEAD)"
echo 3 > "$S/q"; g -C "$S" add q; g -C "$S" commit -qm "feat: q DL-6 (#23)"
g clone -q --depth 3 "file://$S" "$TMP/shal" 2>/dev/null
eq "fixture: the clone is shallow and cannot read T" \
   "true|false" "$(g -C "$TMP/shal" rev-parse --is-shallow-repository)|$(g -C "$TMP/shal" cat-file -e "$ST^{commit}" 2>/dev/null && echo true || echo false)"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":7,"workflow_stage_id":51,"payload":{"dl_number":"DL-6","repo":"acme/widget"}},
  {"id":8,"workflow_stage_id":51,"payload":{"dl_number":"DL-9","repo":"acme/widget"}}
],"meta":{"last_page":1,"total":2}}
JSON
run_in "$TMP/shal" "$PRC"
eq "shallow: the run exits 0 and the control card (#7) moves"     "0|true" "$rc|$(moved 7)"
eq "shallow: the unmeasured revert's DL card (#8) is NOT promoted" "false" "$(moved 8)"
eq "shallow: stderr names the revert NOT MEASURED, by short sha" \
   "true" "$(has "⚠ $(g -C "$TMP/shal" rev-parse --short "$SRT"): NOT MEASURED" "$err")"
eq "shallow: the summary line counts the unmeasured commit" "true" "$(has "1 commits-unmeasured, " "$out")"

_summary "promote-revert-selftest"
