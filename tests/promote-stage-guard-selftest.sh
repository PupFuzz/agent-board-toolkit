#!/usr/bin/env bash
# promote-stage-guard-selftest.sh — deterministic, network-free end-to-end checks for the
# source-stage guard (--shipped-stages) in bin/promote-released-cards.
#
# WHY THIS FILE EXISTS. Promotion means Shipped→Released. A DL/PR-matched card that is NOT
# in a Shipped-class source stage must never be moved — otherwise a stale or RECYCLED DL/PR
# stamp left on a declined (wont_do) card resurrects it into Released (the incident this
# guard was added for: a wont_do card carrying a stale dl_number was promoted when a later
# release recycled the DL token). The guard is OPT-IN: with no --shipped-stages the run is
# byte-identical to the prior unconditional behavior (fleet consumers adopt on their own
# windows). The guard lives in the top-level move loop (not a liftable function), so this
# exercises the REAL script end-to-end with `curl` stubbed on PATH; --dls drives ref
# derivation so no git-range / merge-tip stubbing is needed.
#
# SCOPE, WIDER THAN THE FILENAME (card#5877). This file also owns the `--cards` id-correlation
# path and the every-value-taking-flag guard, both of which need exactly this harness — the
# real script as a process, over a canned board, with its PATCH set observable. Adding a third
# selftest would have meant a third bespoke `curl` stub in tests/ (this one and the shared
# `_kb-api-stub-curl.sh` are already two, for genuinely different callers), so the cases live
# with the harness they need. The filename is NOT renamed on purpose: it is a required status
# check name via ci.yml's matrix, and a rename leaves that context permanently unreported.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# --- fake curl on PATH: serves the canned board on a GET, records PATCH targets+bodies ----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Minimal curl stand-in for promote-released-cards' api(): a PATCH (via `-X PATCH`) is a card
# move — log "<url>\t<body>" and return success; anything else is the paged board GET.
method=GET; url=""; data=""; want_data=0
for a in "$@"; do
  if [ "$want_data" = 1 ]; then data="$a"; want_data=0; continue; fi
  case "$a" in
    -X) method=_next ;;
    PATCH|GET|POST) [ "$method" = _next ] && method="$a" ;;
    -d) want_data=1 ;;
    http://*|https://*) url="$a" ;;
  esac
done
if [ "$method" = PATCH ]; then
  printf '%s\t%s\n' "$url" "$data" >> "$PATCH_LOG"
  printf '{"data":{"id":0}}'
else
  cat "$BOARD_FILE"
fi
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

# --- config + board fixture -------------------------------------------------------------
cat > "$TMP/release-pr.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": {
    "board_id": "12",
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3"
  }
}
JSON

# Two matched cards: #1 sits in a Shipped-class stage (51); #2 sits in wont_do (99). Neither
# is at the released stage (85), so neither is an idempotent "already released" skip.
export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":99,"payload":{"dl_number":"DL-101"}}
],"meta":{"last_page":1,"total":2}}
JSON

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"

# run_promote <extra-args...> — invoke the real script (both DLs shipped), capturing
# rc / stdout(out) / stderr(err) / the PATCH log(patched).
run_promote() {
  : > "$PATCH_LOG"
  rc=0
  out="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100,DL-101" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"
  patched="$(cat "$PATCH_LOG")"
}

echo "== guard ON: matched card in an allowed stage promoted; disallowed-stage card skipped =="
run_promote --shipped-stages 51
eq "guard on → rc 0"                                "0"     "$rc"
eq "allowed-stage card #1 PATCHed (promoted)"       "true"  "$(has '/tasks/1.json' "$patched")"
eq "disallowed-stage card #2 NOT PATCHed (skipped)" "false" "$(has '/tasks/2.json' "$patched")"
eq "skip log names the card id"                     "true"  "$(has '(#2)' "$err")"
eq "skip log names its current stage"               "true"  "$(has 'stage 99' "$err")"
eq "skip log explains the reason"                   "true"  "$(has 'never resurrects declined/backlog cards' "$err")"
eq "summary surfaces the stage-guarded count"       "true"  "$(has '1 stage-guarded' "$out")"
eq "guard-on states stage-guard ON on stderr"      "true"  "$(has 'stage-guard ON' "$err")"
eq "guard-on ON line names the guarded stage ids"  "true"  "$(has 'Shipped-class source stages: 51' "$err")"

echo "== guard ON, whitespace in the input is tolerated (normalized) =="
run_promote --shipped-stages " 51 , 51 "
eq "whitespace-padded set still promotes #1"        "true"  "$(has '/tasks/1.json' "$patched")"
eq "whitespace-padded set still skips #2"           "false" "$(has '/tasks/2.json' "$patched")"

echo "== malformed --shipped-stages → fail loud (config error, not silent no-guard) =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" --shipped-stages "51,foo" 2>&1)" || rc=$?
eq "non-numeric token → dies rc 2"                  "2"     "$rc"
eq "die names the bad --shipped-stages value"       "true"  "$(has 'comma-separated list of numeric stage ids' "$err")"

echo "== whitespace-ONLY --shipped-stages → normalizes to empty and dies (the '' case arm) =="
# Pins that the '' arm in the validation case is REACHABLE and doing work: this input passes
# require_value (non-empty as typed) and only becomes empty after the whitespace strip. It is
# the reason that arm must not be deleted as dead code once require_value covers "".
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" --shipped-stages " " 2>&1)" || rc=$?
eq "whitespace-only → dies rc 2"                    "2"     "$rc"
eq "die reports the normalized-empty value"         "true"  "$(has "(got '')" "$err")"

echo "== EXPLICITLY EMPTY --shipped-stages → dies; never a silent unguarded promote (#5144) =="
# RED-when-reverted: drop require_value from the --shipped-stages arm and this block fails on
# every assertion — rc becomes 0, the wont_do card #2 is PATCHed (resurrected off its stale
# stamp), and the summary is byte-identical to a run with no guard at all. That silence is the
# defect: an unexpanded shell variable or an empty CI input selected the unguarded default.
run_promote --shipped-stages ""
eq "explicit empty → dies rc 2"                     "2"     "$rc"
eq "die names the flag, not an unbound variable"    "true"  "$(has '--shipped-stages requires a non-empty value' "$err")"
eq "no card was PATCHed (died before any move)"     ""      "$patched"
eq "no summary line was printed"                    "false" "$(has 'moved,' "$out")"

echo "== every value-taking flag rejects an empty value (the whole class, not one instance) =="
# "The whole class" is now an assertion rather than a claim. The list below was hand-typed and
# said five while the bin guarded six: `--cards` arrived in v0.26.0 and nothing here could go
# red about it, so this block asserted totality over 5/6 for two minor versions (card#6645).
# expect_value_flags derives the population from the bin's own guard call sites and reds in both
# directions, so the seventh flag cannot join in silence.
VALUE_FLAGS=(--dls --cards --base --head --shipped-stages --config)
expect_value_flags "$PRC" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
  rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" "$f" "" 2>&1)" || rc=$?
  eq "$f \"\" → dies rc 2"                          "2"     "$rc"
  eq "$f \"\" die names the flag"                   "true"  "$(has "$f requires a non-empty value" "$err")"
done

echo "== a trailing flag with no argument dies by flag name, not 'unbound variable' =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls 2>&1)" || rc=$?
eq "trailing --dls → dies rc 2"                     "2"     "$rc"
eq "die names the flag"                             "true"  "$(has '--dls requires a non-empty value' "$err")"
eq "no raw set -u unbound-variable leak"            "false" "$(has 'unbound variable' "$err")"

echo "== guard OFF (input absent): SAME fixture → prior behavior, both cards promoted =="
# RED-when-reverted anchor: if the guard is removed, the guard-ON block above would ALSO
# promote #2 (its 'NOT PATCHed' assertion flips to true→fail, and the skip-log asserts fail).
run_promote
eq "guard off → rc 0"                               "0"     "$rc"
eq "card #1 promoted"                               "true"  "$(has '/tasks/1.json' "$patched")"
eq "card #2 ALSO promoted (unconditional prior)"    "true"  "$(has '/tasks/2.json' "$patched")"
eq "guard-off summary omits stage-guarded (byte-identical line)" "false" "$(has 'stage-guarded' "$out")"
# card#5152: the summary stays byte-identical (above) AND the guard's state is stated on
# its own stderr line, every run. Before this, an ABSENT guard produced a summary
# indistinguishable from a guarded one — an unguarded promote that reads as clean.
eq "guard-off states stage-guard OFF on stderr"     "true"  "$(has 'stage-guard OFF' "$err")"
eq "guard-off OFF line names the remedy"            "true"  "$(has 'Pass --shipped-stages' "$err")"
eq "guard-off OFF line is not on stdout"            "false" "$(has 'stage-guard OFF' "$out")"
eq "guard-off run logs no skip line"                "false" "$(has 'never resurrects' "$err")"


echo "== --cards correlates on the card's own id, never on dl_number (card#5877) =="
# WHY THIS EXISTS. `ref_token_regex` and the card-id spelling are two id spaces with one
# comparison. Re-spelling that key as `card#[0-9]+` was the tempting one-line fix and is a
# live defect, shown here rather than argued: card #1's dl_number is DL-100, so asking about
# CARD id 100 under the old single-key scheme moved card #1. The `--cards` path compares the
# id instead, so card 100 (which does not exist on this board) is reported as no-card and
# card #1 is left alone.
CARDS_BOARD="$TMP/board-cards.json"
cat > "$CARDS_BOARD" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":99,"payload":{"dl_number":"DL-101"}}
],"meta":{"last_page":1,"total":2}}
JSON
run_cards() { # <extra-args...> — same shape as run_promote, but driven by --cards
  : > "$PATCH_LOG"; rc=0
  BOARD_FILE="$CARDS_BOARD" out="$("$PRC" --config "$TMP/release-pr.json" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}

run_cards --cards "100"
eq "an id matching only a DL NUMBER moves nothing"   ""      "$patched"
eq "…and is reported as no-card, by id spelling"     "true"  "$(has 'card#100' "$err")"
eq "…the DL-100 card was not silently promoted"      "false" "$(has '/tasks/1.json' "$patched")"
# CONTROL — same flag, same board, an id that DOES exist. Without it every assertion above is
# satisfied by a --cards path that matches nothing at all.
run_cards --cards "1"
eq "control: an existing id IS promoted"             "true"  "$(has '/tasks/1.json' "$patched")"
eq "control: it is labelled by its id, not a DL"     "true"  "$(has 'card#1 (#1)' "$out")"
eq "control: nothing is reported no-card"            "false" "$(has 'matched NO card' "$err")"

echo "== --cards composes with --dls, and the source-stage guard still applies =="
run_cards --dls "DL-100" --cards "2"
eq "the DL leg promotes card #1"                     "true"  "$(has '/tasks/1.json' "$patched")"
eq "the id leg promotes card #2"                     "true"  "$(has '/tasks/2.json' "$patched")"
run_cards --dls "DL-100" --cards "2" --shipped-stages 51
eq "guard still skips the wont_do card matched by id" "false" "$(has '/tasks/2.json' "$patched")"
eq "…and says so"                                     "true"  "$(has 'never resurrects declined/backlog cards' "$err")"

echo "== --cards is STRICTLY numeric — a token spelling is a config error, not a parse =="
# `--dls` is a token stream that gets grepped, so junk degrades to "matched nothing". An id
# list is different: junk that greps down to a number would move a card nobody named.
for bad_in in "card#1" "#1" "1,foo" "1;2"; do
  rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --cards "$bad_in" 2>&1)" || rc=$?
  eq "--cards '$bad_in' → dies rc 2"                 "2"     "$rc"
  eq "--cards '$bad_in' names the expected shape"    "true"  "$(has 'comma-separated list of numeric card ids' "$err")"
done
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --cards "" 2>&1)" || rc=$?
eq "--cards \"\" → dies rc 2"                        "2"     "$rc"
eq "--cards \"\" names the flag"                     "true"  "$(has '--cards requires a non-empty value' "$err")"

echo "== --cards ABSENT is byte-identical to the pre-flag behavior =="
# The whole opt-in claim. The flag touched the correlation jq, the no-card report and the exit
# policy — all three on the SHARED path — so "absent = unchanged" is a property to assert, not
# to assume. The literal below is the summary this fixture produced BEFORE the flag existed,
# read off the pre-change script over this same board rather than written from expectation; it
# was additionally diffed (stdout, stderr and PATCH set) against the pre-change script across
# five invocation shapes: multi-DL with a cardless ref, the stage guard, an already-released
# card, a no-match set, and --dry-run. Pinning the literal here rather than re-deriving it in
# CI is deliberate — re-deriving would mean reading an old blob out of git history, which
# returns 128 in a depth-1 checkout and would turn this into a check that cannot run.
run_promote; base_out="$out"; base_err="$err"; base_patched="$patched"
run_promote --shipped-stages 51; guard_out="$out"; guard_err="$err"; guard_patched="$patched"
eq "unguarded stdout unchanged"  "2 moved, 0 already-released, 0 no-card, 0 failed." \
   "$(printf '%s' "$base_out" | sed -n 's/^promote-released-cards: //p')"
eq "unguarded no-card report is DL-only spelling"  "false" "$(has 'card#' "$base_err")"
eq "unguarded PATCH set is both cards"             "true"  \
   "$( [ "$(has '/tasks/1.json' "$base_patched")" = true ] && [ "$(has '/tasks/2.json' "$base_patched")" = true ] && echo true || echo false )"
eq "guarded summary still names the guarded count" "true"  "$(has '1 stage-guarded' "$guard_out")"
eq "guarded PATCH set is card #1 only"             "true"  \
   "$( [ "$(has '/tasks/1.json' "$guard_patched")" = true ] && [ "$(has '/tasks/2.json' "$guard_patched")" = false ] && echo true || echo false )"
eq "guard-state line still emitted"                "true"  "$(has 'stage-guard ON' "$guard_err")"

echo "== derive path: non-merge tip + all matches stage-guarded → the die STILL fires =="
# The 0-promoted/non-merge-tip die guards PR-MARKER completeness; a guarded skip proves
# only that a DL survived the squash and canNOT disprove a dropped sibling (#NNN) ref —
# so the die must fire even when every match was a deliberate decline-skip. RED-when-
# reverted: re-adding `[ "$guarded" = 0 ]` to the die's conjuncts turns this rc into 0.
GITDIR="$TMP/gitfx"; mkdir -p "$GITDIR"
git -C "$GITDIR" init -q -b main
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
git -C "$GITDIR" tag v0.0.1
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "release: v0.0.2 DL-101 squashed"
# Board: the only derivable match (DL-101 → card #2) sits in a DISALLOWED stage.
rc=0; err2="$(cd "$GITDIR" && "$PRC" --config "$TMP/release-pr.json" --shipped-stages 51 2>&1)" || rc=$?
eq "derive path, guarded-only matches, squash tip → still dies rc 2" "2" "$rc"
eq "die names the squash cause"                     "true"  "$(has 'not a merge commit' "$err2")"
eq "the guarded skip itself was logged first"       "true"  "$(has 'never resurrects declined/backlog cards' "$err2")"

_summary "promote-stage-guard-selftest"
