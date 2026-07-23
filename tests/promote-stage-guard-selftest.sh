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
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# has <needle> <haystack> — literal-substring test (robust to JSON/emoji punctuation).
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

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

echo "== guard ON, whitespace in the input is tolerated (normalized) =="
run_promote --shipped-stages " 51 , 51 "
eq "whitespace-padded set still promotes #1"        "true"  "$(has '/tasks/1.json' "$patched")"
eq "whitespace-padded set still skips #2"           "false" "$(has '/tasks/2.json' "$patched")"

echo "== malformed --shipped-stages → fail loud (config error, not silent no-guard) =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" --shipped-stages "51,foo" 2>&1)" || rc=$?
eq "non-numeric token → dies rc 2"                  "2"     "$rc"
eq "die names the bad --shipped-stages value"       "true"  "$(has 'comma-separated list of numeric stage ids' "$err")"

echo "== guard OFF (input absent): SAME fixture → prior behavior, both cards promoted =="
# RED-when-reverted anchor: if the guard is removed, the guard-ON block above would ALSO
# promote #2 (its 'NOT PATCHed' assertion flips to true→fail, and the skip-log asserts fail).
run_promote
eq "guard off → rc 0"                               "0"     "$rc"
eq "card #1 promoted"                               "true"  "$(has '/tasks/1.json' "$patched")"
eq "card #2 ALSO promoted (unconditional prior)"    "true"  "$(has '/tasks/2.json' "$patched")"
eq "guard-off summary omits stage-guarded (byte-identical line)" "false" "$(has 'stage-guarded' "$out")"
eq "guard-off run logs no skip line"                "false" "$(has 'never resurrects' "$err")"


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
