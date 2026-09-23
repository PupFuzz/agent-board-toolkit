#!/usr/bin/env bash
# promote-completeness-gate-selftest.sh — deterministic, network-free end-to-end checks for the
# opt-in COMPLETENESS GATE (`--require-complete`) in bin/promote-released-cards (card#10176).
#
# WHY THIS FILE EXISTS. A card's `pr_number` holds ONE pull request, so a card whose work spans
# several reaches its shipped stage on whichever part merged first — and this mover then walks it
# into the TERMINAL released stage, the one nobody re-reads, while the rest is still open or
# unreleased. The gate refuses such a card. Both directions of the gate are expensive: a card
# wrongly promoted is unrecoverable in practice, and a card wrongly refused stalls forever, so
# every refusal here is paired with the run that must still promote.
#
# ⛔ WHAT THIS FILE DOES NOT TEST — and the boundary is the design's, not this file's. The
# PREDICATE (what "complete" means, which PRs it reads, everything it cannot see) belongs to
# `bin/card-completeness` and is driven by `tests/card-completeness-selftest.sh` against a
# stubbed GitHub. Here the oracle is a SCRIPTED STUB, because what is under test is the mover's
# half: which cards it asks about, when it asks, what it does with each answer, and what it does
# when the oracle cannot answer or cannot run at all. Asserting the predicate here too would
# create a second opinion about completeness, which is the defect the split exists to prevent.
#
# THE OFF CASE IS AN ASSERTION, NOT AN ASSUMPTION. `--require-complete` absent must leave the run
# byte-identical to a run of the tool before the flag existed, which is why the first block pins
# the WHOLE summary line and the absence of every new stderr line, rather than just an rc.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
PRC="$ROOT/bin/promote-released-cards"
_need -x "$PRC"
_need -x "$ROOT/bin/card-completeness"
_mktmp_scratch --home

# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

cat > "$TMP/release-pr.json" <<'JSON'
{
  "main_branch": "main",
  "dev_branch": "trunk",
  "ref_token_regex": "DL-[0-9]+",
  "promote": {
    "board_id": 12,
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3",
    "source": "*"
  }
}
JSON

# Three matched cards: #1 and #2 are promotable, #3 is already at the released stage (85), which
# is what lets the ORDER of the gate against the already-released check be observed.
export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-101"}},
  {"id":3,"workflow_stage_id":85,"payload":{"dl_number":"DL-102"}}
],"meta":{"last_page":1,"total":3}}
JSON

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
ORACLE_ARGV="$TMP/oracle-argv.log"
export ORACLE_ARGV

# _oracle <exit-rc> <verdict-line>... — write a SCRIPTED oracle: it records its own argv and
# prints the given TSV lines. It reads nothing, so every case below is about the mover.
_oracle() {
  local rc="$1"; shift
  { printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$ORACLE_ARGV"
    local line
    for line in "$@"; do printf 'printf %%s\\\\n %s\n' "$(printf '%q' "$line")"; done
    printf 'exit %s\n' "$rc"
  } > "$TMP/oracle"
  chmod +x "$TMP/oracle"
}

# run_promote <extra-args…> — the real script over the canned board, all three DLs shipped.
run_promote() {
  : > "$PATCH_LOG"; : > "$ORACLE_ARGV"
  rc=0
  out="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100,DL-101,DL-102" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"
  patched="$(cat "$PATCH_LOG")"
  argv="$(cat "$ORACLE_ARGV")"
}

echo "== the gate is OFF unless asked for: the run is what it was before the flag existed =="
# RED when: any part of the gate runs unconditionally — the summary grows a count, a state line
# appears on stderr, or the oracle is consulted.
_oracle 5 "1	INCOMPLETE	#99 card-1-part-two (open)"
run_promote
eq "gate off → rc 0"                                "0"    "$rc"
eq "both promotable cards PATCHed"                  "true" "$(has '/tasks/1.json' "$patched")"
eq "  … and the second one too"                     "true" "$(has '/tasks/2.json' "$patched")"
eq "the summary line is the pre-flag one"           "true" \
   "$(has_line 'promote-released-cards: 2 moved, 1 already-released, 0 no-card, 0 failed.' "$out")"
eq "no completeness count in the summary"           "false" "$(has 'completeness' "$out")"
eq "no completeness line on stderr"                 "false" "$(has 'completeness' "$err")"
eq "the oracle was NOT consulted"                   ""     "$argv"

echo "== gate ON, every card COMPLETE: nothing changes but the report =="
# The pass side of the gate. Without it, every refusal below could be a gate that blocks on
# anything, which would stall every release instead of promoting one.
_oracle 0 "1	COMPLETE	-" "2	COMPLETE	-" "3	COMPLETE	-"
run_promote --require-complete --completeness "$TMP/oracle"
eq "all complete → rc 0"                            "0"    "$rc"
eq "card #1 promoted"                               "true" "$(has '/tasks/1.json' "$patched")"
eq "card #2 promoted"                               "true" "$(has '/tasks/2.json' "$patched")"
eq "summary carries a zero refusal count"           "true" "$(has '0 completeness-refused' "$out")"
eq "the gate says it is ON, naming the oracle"      "true" "$(has "completeness-gate ON (oracle $TMP/oracle)" "$err")"
eq "no FAILED line when nothing was refused"        "false" "$(has 'REFUSED by the completeness gate' "$err")"

echo "== what the oracle is ASKED: the matched cards, this release's head, the integration branch =="
# The mover owns the QUESTION; a wrong question is a right answer about the wrong release.
# RED when: --release-head/--integration stop being passed, the head stops being a resolved sha,
# `.dev_branch` stops being read, or an unmatched card joins the id list.
eq "the oracle is asked once"                       "1"    "$(printf '%s\n' "$argv" | grep -c .)"
eq "  … for the matched card ids, in plan order"    "true" "$(has '--cards 1,2,3' "$argv")"
eq "  … with the release head as a resolved sha"    "true" "$(has "--release-head $(git -C "$ROOT" rev-parse HEAD)" "$argv")"
eq "  … and .dev_branch as the integration branch"  "true" "$(has '--integration trunk' "$argv")"
# The default for that key is the same one release-pr-body uses, so one key has one reading.
sed 's/"dev_branch": "trunk",//' "$TMP/release-pr.json" > "$TMP/release-pr-nodev.json"
: > "$ORACLE_ARGV"
"$PRC" --config "$TMP/release-pr-nodev.json" --dls "DL-100" --require-complete --completeness "$TMP/oracle" >/dev/null 2>&1 || true
eq "an absent .dev_branch defaults to 'dev'"        "true" "$(has '--integration dev' "$(cat "$ORACLE_ARGV")")"

echo "== INCOMPLETE: that card is refused BY NAME, its siblings still promote =="
# RED when: an INCOMPLETE verdict is treated as a warning, or one refusal aborts the whole run.
_oracle 5 "1	INCOMPLETE	#99 card-1-part-two (open); #98 card-1-docs (merged to trunk, not in the release head)" "2	COMPLETE	-" "3	COMPLETE	-"
run_promote --require-complete --completeness "$TMP/oracle"
eq "an incomplete card → rc 5"                      "5"    "$rc"
eq "the incomplete card is NOT PATCHed"             "false" "$(has '/tasks/1.json' "$patched")"
eq "its complete sibling still is"                  "true" "$(has '/tasks/2.json' "$patched")"
eq "the refusal names the card"                     "true" "$(has '(#1): INCOMPLETE' "$err")"
eq "  … and the PRs the oracle named"               "true" "$(has '#99 card-1-part-two (open)' "$err")"
eq "  … and says why a terminal move is refused"    "true" "$(has 'partial implementation' "$err")"
eq "the summary counts the refusal"                 "true" "$(has '1 completeness-refused' "$out")"
eq "  … and does not count it as a move"            "true" "$(has '1 moved' "$out")"
eq "a FAILED line names the count and the remedy"   "true" "$(has '1 card(s) were REFUSED by the completeness gate' "$err")"

echo "== UNMEASURED is refused too: a silence is not an answer =="
# RED when: any not-COMPLETE verdict falls through to a move — the whole point is that "no
# unreleased PR names this card" and "the PRs could not be read" must not read the same.
_oracle 6 "1	UNMEASURED	the open-PR read of acme/widget returned HTTP 403" "2	UNMEASURED	x" "3	UNMEASURED	x"
run_promote --require-complete --completeness "$TMP/oracle"
eq "unmeasured → rc 5"                              "5"    "$rc"
eq "nothing was PATCHed"                            ""     "$patched"
eq "the refusal carries the oracle's own reason"    "true" "$(has 'returned HTTP 403' "$err")"
eq "  … and names the silence it refuses on"        "true" "$(has 'the same silence' "$err")"
eq "the summary counts both refusals"               "true" "$(has '2 completeness-refused' "$out")"

echo "== a card the oracle SILENTLY OMITTED is UNMEASURED, never promoted =="
# The failure that would un-gate a terminal write: an answer sheet missing a row must not read
# as a clean row. RED when: complete_verdict's END arm is dropped, or a missing line defaults.
_oracle 0 "2	COMPLETE	-"
run_promote --require-complete --completeness "$TMP/oracle"
eq "the omitted card is not PATCHed"                "false" "$(has '/tasks/1.json' "$patched")"
eq "  … and says no verdict came back for it"       "true"  "$(has 'returned no verdict for this card' "$err")"
eq "the card that WAS answered is promoted"         "true"  "$(has '/tasks/2.json' "$patched")"
eq "rc 5"                                           "5"     "$rc"

echo "== an oracle that cannot run is an UNANSWERED QUESTION, not an absent problem =="
# RED when: a missing or failing oracle degrades to "no gate" — which is the silent-green the
# flag exists to remove, and worse than not having the flag, because the log says gate ON.
run_promote --require-complete --completeness "$TMP/not-a-file"
eq "a non-executable oracle → rc 5"                 "5"    "$rc"
eq "nothing was PATCHed"                            ""     "$patched"
eq "the refusal names the path it looked at"        "true" "$(has "not executable at $TMP/not-a-file" "$err")"
eq "  … and how to proceed anyway"                  "true" "$(has 'drop --require-complete' "$err")"
_oracle 2 "1	COMPLETE	-"
run_promote --require-complete --completeness "$TMP/oracle"
eq "an oracle REFUSING to run (rc 2) → rc 5"        "5"    "$rc"
eq "  … its own COMPLETE line is discarded"         ""     "$patched"
eq "  … and the exit status is reported"            "true" "$(has 'refused to run, exit 2' "$err")"

echo "== the oracle is a SIBLING of the mover, resolved from the script's own path =="
# It is vendored into a consumer's bin/ and run from the repo root, so $PWD cannot decide this.
# RED when: the default path is built from $PWD, or from a hardcoded directory.
mkdir -p "$TMP/vendor/bin"
cp "$PRC" "$TMP/vendor/bin/promote-released-cards"
printf '#!/usr/bin/env bash\ntouch "%s"\nprintf "1\\tCOMPLETE\\t-\\n"\n' "$TMP/sibling-ran" > "$TMP/vendor/bin/card-completeness"
chmod +x "$TMP/vendor/bin/card-completeness"
rm -f "$TMP/sibling-ran"; : > "$PATCH_LOG"
rc=0; "$TMP/vendor/bin/promote-released-cards" --config "$TMP/release-pr.json" --dls "DL-100" --require-complete >/dev/null 2>&1 || rc=$?
eq "the sibling oracle was executed"                "true" "$([ -f "$TMP/sibling-ran" ] && echo true || echo false)"
eq "  … and its COMPLETE verdict promoted the card" "true" "$(has '/tasks/1.json' "$(cat "$PATCH_LOG")")"
eq "  … rc 0"                                       "0"    "$rc"

echo "== ORDER: the gate runs after already-released and the stage guard, before --dry-run =="
# Each earlier check answers a different question, and the operator acts differently on each:
# an idempotent re-run must keep reading as "already released" rather than as a refusal, and a
# preview must show the refusal the real run would make instead of a move it would not.
_oracle 5 "1	INCOMPLETE	#99 card-1-part-two (open)" "2	INCOMPLETE	#97 card-2-part-two (open)" "3	INCOMPLETE	#96 card-3-x (open)"
run_promote --require-complete --completeness "$TMP/oracle" --shipped-stages 51
eq "the already-released card reads already-released" "true" "$(has '(#3): already released' "$out")"
eq "  … not as a completeness refusal"              "false" "$(has '(#3): INCOMPLETE' "$err")"
run_promote --require-complete --completeness "$TMP/oracle" --shipped-stages 99
eq "a stage-guarded card reads stage-guarded"       "true" "$(has '(#1): current stage 51 not in a Shipped-class' "$err")"
eq "  … not as a completeness refusal"              "false" "$(has '(#1): INCOMPLETE' "$err")"
run_promote --require-complete --completeness "$TMP/oracle" --dry-run
eq "a dry run shows the refusal"                    "true" "$(has '(#1): INCOMPLETE' "$err")"
eq "  … and does not preview a move of it"          "false" "$(has '(#1): would move' "$out")"
eq "  … and PATCHes nothing, gate or no gate"       ""     "$patched"
eq "  … rc 5"                                       "5"    "$rc"

echo "== --completeness is a value-taking flag like every other =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls DL-100 --completeness "" 2>&1)" || rc=$?
eq "--completeness \"\" → rc 2"                     "2"    "$rc"
eq "  … named, never read as absent"                "true" "$(has '--completeness requires a non-empty value' "$err")"
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls DL-100 --completeness 2>&1)" || rc=$?
eq "trailing --completeness → rc 2"                 "2"    "$rc"
eq "  … no set -u unbound-variable leak"            "false" "$(has 'unbound variable' "$err")"
# --require-complete takes NO value: a following argument must still be parsed as an argument.
_oracle 0 "1	COMPLETE	-" "2	COMPLETE	-" "3	COMPLETE	-"
run_promote --require-complete --dry-run --completeness "$TMP/oracle"
eq "--require-complete consumes no argument"        "0"    "$rc"
eq "  … the flag after it still took effect"        "true" "$(has '(dry-run)' "$out")"

_summary "promote-completeness-gate-selftest"
