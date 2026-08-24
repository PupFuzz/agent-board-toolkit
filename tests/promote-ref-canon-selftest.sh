#!/usr/bin/env bash
# promote-ref-canon-selftest.sh — the one-decorated-integer rule, held level across the TWO
# runtimes that express it, and driven end-to-end through the tool that acts on its answer.
#
# WHY THIS FILE EXISTS (card#7587). `bin/promote-released-cards` correlated a card by stripping
# every non-digit out of its stored `payload.dl_number` / `pr_number` / `id`, which CONCATENATES
# the digit runs of a multi-run value: a card holding `1.5` normalised to `15` and was correlated
# against genuinely-shipped PR **15** — a real but unrelated pull request — and the release sweep
# **PATCHed that card** to the released stage. The stamp needed no bad tool to get there: the
# board UI, another tool, an API caller and a human can all write one. The reader now applies the
# rule the board itself applies (kanban DL-251, `^\D*(\d+)\D*$`) and answers "" for anything that
# is not one integer, so such a card correlates to nothing and is left alone.
#
# ⛔ WHAT IT GUARDS THAT NO SINGLE-SIDED TEST CAN. The rule now lives in two places that cannot
# share code — `_kbc_require_ref_int` (bash, the MINT site in `bin/kbcard`) and the `def norm:`
# (jq, the READ site here) — and a second expression of one rule drifts. `tests/_ref-canon-cases.sh`
# is the shared fixture both are asserted against, so neither can move alone. ⚠ It does NOT hold
# the two accept sets EQUAL — card#7536 narrowed the mint site below the board's own rule while
# this reader is pinned to that rule — it holds the CONTAINMENT that matters and requires every
# divergence to be declared with a reason (the fixture header owns that reasoning). Both expressions are
# EXTRACTED FROM THE SHIPPED FILES rather than restated here: a copy in this test would be a third
# expression of the rule, and it would stay green while the tool it claims to be about rotted.
#
# LAYERS, and why each is not redundant:
#   1. the fixture, against the extracted jq reader, the extracted shipped-side `numlist`, and
#      the real bash mint predicate — the containment claim (every value the mint site writes is
#      one the reader correlates) plus the DECLARED divergence set;
#   2. a differential against the PRE-FIX jq expression — behaviour-neutrality on well-formed
#      values, measured rather than asserted;
#   3. the non-ASCII cases the fixture deliberately excludes;
#   4. the real script, as a process, over a canned board with its PATCH set observable — which
#      is the only layer that can show the def is WIRED. A unit-clean normaliser the correlation
#      no longer calls looks identical to a fixed tool at layers 1-3.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_ref-canon-cases.sh"
PRC="$HERE/../bin/promote-released-cards"
KBC="$HERE/../bin/kbcard"
_need -x "$PRC"
_need -r "$KBC"

_mktmp_scratch --home

# --- the two implementations, LIFTED OUT OF THE SHIPPED FILES -----------------------------
# A `def norm:` line in the correlation jq, and the `numlist()` definition in the shell. Both
# extractions are asserted to have found EXACTLY ONE line: an extraction that silently found
# none would make every assertion below run against an empty program, and an extraction that
# found two would be testing whichever one it happened to concatenate.
norm_lines="$(awk '/^[[:space:]]*def norm:/ {print}' "$PRC")"
numlist_lines="$(awk '/^numlist\(\) \{/ {print}' "$PRC")"
eq "extracted exactly one 'def norm:' from the bin" "1" "$(printf '%s\n' "$norm_lines" | awk 'NF' | wc -l)"
eq "extracted exactly one 'numlist()' from the bin" "1" "$(printf '%s\n' "$numlist_lines" | awk 'NF' | wc -l)"
NORM_DEF="$norm_lines"
eval "$numlist_lines"

# THE PRE-FIX EXPRESSION, verbatim as it shipped through v0.30.0. It is here for ONE purpose —
# the neutrality differential below — and is never the thing under test. Keeping it means the
# claim "nothing well-formed changed" is a measurement against the old code rather than a
# restatement of the new code's expectations.
PRE_FIX_NORM='def norm: (. // "")|tostring|gsub("[^0-9]";"")|sub("^0+(?=.)";"");'

# jqnorm <json-literal> — the shipped reader's answer for a value already spelled as JSON.
jqnorm() { jq -rn "$NORM_DEF ($1)|norm"; }
# jqnorm_s <string> — the same, for a raw string (jq --arg does the quoting, so an embedded
# newline or quote reaches the reader intact).
jqnorm_s() { jq -rn --arg v "$1" "$NORM_DEF \$v|norm"; }
# prefixnorm_s <string> — the pre-fix reader's answer for the same raw string.
prefixnorm_s() { jq -rn --arg v "$1" "$PRE_FIX_NORM \$v|norm"; }

# The bash half of the rule, from the shipped bin (main-guarded, so sourcing defines it without
# running anything). Loaded AFTER the jq legs so nothing kbcard sources can affect them.
# shellcheck source=/dev/null
source "$KBC"
eq "the bash mint predicate is defined by the shipped bin" "true" \
   "$(declare -F _kbc_require_ref_int >/dev/null && echo true || echo false)"
# kbc_accepts <value> → true/false. `--pr` is one of the two flags that carry the rule; the
# predicate takes the flag name only to name it in its diagnostic.
kbc_accepts() { _kbc_require_ref_int --pr "$1" >/dev/null 2>&1 && echo true || echo false; }

# ---------------------------------------------------------------------------
echo "== the shared fixture: one table, three implementations, containment + declared divergence =="
# POSITIVE CONTROL FIRST. Every row below is a comparison, and a fixture that loaded as the
# empty array satisfies all of them by running none. The named witness is a row, not a count —
# a count pins this to a past table size and rots the moment a case is added.
eq "the shared fixture loaded (positive control)" "false" \
   "$([ "${#REF_CANON_CASES[@]}" -eq 0 ] && echo true || echo false)"
eq "…and carries the flagship defect case"        "true"  \
   "$(has_line '1.5||1 5|refuse-multirun' "$(printf '%s\n' "${REF_CANON_CASES[@]}")")"

accepted=0; refused=0; uncorrelatable=""; divergent=""; declared=""
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm want_numlist want_mint <<< "$row"
    val="$(printf '%b' "$raw")"
    label="$(printf '%s' "$raw")"   # the row's own spelling, so a newline case stays one line

    eq "jq reader: '$label' → '$want_norm'" "$want_norm" "$(jqnorm_s "$val")"
    eq "shipped-side numlist: '$label' → '$want_numlist'" "$want_numlist" \
       "$(printf '%s' "$val" | numlist | tr '\n' ' ' | sed 's/ *$//')"
    eq "mint site on '$label' → $want_mint" \
       "$([ "$want_mint" = accept ] && echo true || echo false)" "$(kbc_accepts "$val")"

    if [ "$want_mint" = accept ]; then
        accepted=$((accepted + 1))
        # THE INVARIANT: a value the MINT site writes must be one the READER correlates. The
        # other direction is not an invariant (see the fixture header) and is handled below.
        [ -n "$want_norm" ] || uncorrelatable="$uncorrelatable $label"
    else
        refused=$((refused + 1))
        [ -z "$want_norm" ] || declared="$declared $label"
    fi
    # The MEASURED divergence set, taken from the two implementations rather than from the
    # table: values the mint site refuses and the reader nonetheless correlates.
    if [ "$(kbc_accepts "$val")" = false ] && [ -n "$(jqnorm_s "$val")" ]; then
        divergent="$divergent $label"
    fi
done
# CONTAINMENT — the whole ordering claim, and the one a drift would break silently: a stamp
# `kbcard` accepted that the release sweep would then skip is a card stranded by two tools that
# each think they are right.
eq "every value the mint site accepts is one the reader correlates" "" "$uncorrelatable"
# THE DIVERGENCE SET IS EXACTLY THE DECLARED ONE. `$divergent` is MEASURED off the two shipped
# implementations; `$declared` is what the fixture's reason tags say. Equality in both
# directions is what survives the two sides being ruled on separately: a new divergence nobody
# named reds here, and a tag left behind after a divergence closes reds here too.
eq "the measured divergence set is exactly the tagged one" "$declared" "$divergent"
# BOTH ARMS OF THE TABLE ARE POPULATED. A fixture that had drifted to all-accept or all-refuse
# would still pass every row above while measuring only one direction of the rule.
eq "the fixture exercises the ACCEPT arm" "false" "$([ "$accepted" -eq 0 ] && echo true || echo false)"
eq "the fixture exercises the REFUSE arm" "false" "$([ "$refused" -eq 0 ] && echo true || echo false)"

echo "== behaviour-neutrality: on every value the rule ACCEPTS, the answer is byte-identical =="
# The whole compatibility claim, as a differential against the pre-fix expression rather than
# against this test's expectations. A card stamped `#178`, `DL-0253`, `093` or a bare id
# correlates to exactly what it correlated to before.
changed_on_accept=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ _ <<< "$row"
    [ -n "$want_norm" ] || continue
    val="$(printf '%b' "$raw")"
    eq "unchanged vs pre-fix: '$raw'" "$(prefixnorm_s "$val")" "$(jqnorm_s "$val")"
    [ "$(prefixnorm_s "$val")" = "$(jqnorm_s "$val")" ] || changed_on_accept=$((changed_on_accept + 1))
done
eq "no accepted value changed answer" "0" "$changed_on_accept"

# CONTROL FOR THAT DIFFERENTIAL, and it is not optional: the block above is satisfied by two
# IDENTICAL expressions, i.e. by a fix that was never applied. The refused rows must be exactly
# where the two disagree, and the pre-fix side must still produce the old wrong answers.
eq "pre-fix expression still concatenates '1.5'"        "15"       "$(prefixnorm_s '1.5')"
eq "pre-fix expression still concatenates '2026-08-23'" "20260823" "$(prefixnorm_s '2026-08-23')"
eq "pre-fix expression still concatenates 'PR 12 of 34'" "1234"    "$(prefixnorm_s 'PR 12 of 34')"
disagreed=0; nocorrelate=0; nodigits=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ want_mint <<< "$row"
    [ "$want_mint" = refuse-nodigits ] && nodigits=$((nodigits + 1))
    [ -z "$want_norm" ] || continue
    nocorrelate=$((nocorrelate + 1))
    val="$(printf '%b' "$raw")"
    [ "$(prefixnorm_s "$val")" = "$(jqnorm_s "$val")" ] || disagreed=$((disagreed + 1))
done
# A row carrying NO digits ('TBD', '', 'v') already answered "" under the pre-fix expression, so
# the two agree there and always did. Every OTHER row the reader correlates to nothing is a row
# the pre-fix expression answered a number for — that difference IS the fix. The expectation is
# DERIVED from the table's own two counts rather than written as a figure, so adding a case to
# either group moves it automatically instead of rotting.
eq "the two expressions disagree on every DIGIT-bearing uncorrelated row" \
   "$((nocorrelate - nodigits))" "$disagreed"

echo "== JSON types the fixture cannot spell: a number, and an absent key =="
# `payload.pr_number` is declared a `number` field, so a well-formed stamp reaches the reader as
# a JSON NUMBER, not a string — the fixture is string-typed and cannot cover that. `null` is
# what an ABSENT key reaches it as, and it must correlate to nothing rather than to "".
eq "a numeric stamp normalises like its string form" "85"  "$(jqnorm '85')"
eq "a numeric multi-run stamp correlates to nothing" ""    "$(jqnorm '1.5')"
eq "an ABSENT key (null) correlates to nothing"      ""    "$(jqnorm 'null')"
eq "a JSON true correlates to nothing"               ""    "$(jqnorm 'true')"

echo "== non-ASCII: the rule is ASCII digits, in BOTH runtimes =="
# The board derives its ref with PCRE `\d` and no `/u`, i.e. ASCII digits only, so a value whose
# only "digit" is U+0663 names nothing there and must name nothing here. Both implementations use
# a NEGATED ASCII set (`[^0-9]`), which no collation widens — asserted rather than assumed,
# because a RANGE in either would silently accept it (tests/locale-range-guard-selftest.sh owns
# that class; `numlist` is deliberately excluded here, see the fixture header).
AI3=$'٣'
eq "jq reader: a bare U+0663 correlates to nothing" ""      "$(jqnorm_s "$AI3")"
eq "mint site: a bare U+0663 is refused"            "false" "$(kbc_accepts "$AI3")"
eq "jq reader: '4<U+0663>' is 4 decorated (control)" "4"    "$(jqnorm_s "4$AI3")"
eq "mint site: '4<U+0663>' is accepted (control)"    "true" "$(kbc_accepts "4$AI3")"

# ---------------------------------------------------------------------------
# --- the tool as a process: fake curl on PATH, PATCH set observable ------------------------
# Same harness shape as promote-stage-guard-selftest.sh: a PATCH is a card move, anything else
# is the paged board GET.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
method=GET; url=""; want_data=0
for a in "$@"; do
  if [ "$want_data" = 1 ]; then want_data=0; continue; fi
  case "$a" in
    -X) method=_next ;;
    PATCH|GET|POST) [ "$method" = _next ] && method="$a" ;;
    -d) want_data=1 ;;
    http://*|https://*) url="$a" ;;
  esac
done
if [ "$method" = PATCH ]; then printf '%s\n' "$url" >> "$PATCH_LOG"; printf '{"data":{"id":0}}'; else cat "$BOARD_FILE"; fi
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

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
export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export BOARD_FILE="$TMP/board.json"

# moved <id> → true/false: was card <id> PATCHed on the last run?
moved() { has_line "https://kanban.test/api/v3/tasks/$1.json" "$patched"; }
run_prc() { : > "$PATCH_LOG"; rc=0; out="$("$PRC" --config "$TMP/release-pr.json" "$@" 2>"$TMP/err")" || rc=$?
            err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"; }

echo "== end to end, pr_number: PR 15 ships; only the cards that genuinely NAME 15 move =="
# Cards 1-3 hold values whose digit runs CONCATENATE to 15 — three different spellings of the
# defect, all of which the pre-fix reader PATCHed onto this release. Cards 4-7 are the controls:
# four spellings that genuinely name PR 15, including the JSON-number form and a zero-padded one.
# Card 8 names a different PR and must be untouched either way, which is what separates "the
# guard works" from "the run matched nothing at all".
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"pr_number":"1.5"}},
  {"id":2,"workflow_stage_id":51,"payload":{"pr_number":"1,5"}},
  {"id":3,"workflow_stage_id":51,"payload":{"pr_number":"PR 1 of 5"}},
  {"id":4,"workflow_stage_id":51,"payload":{"pr_number":"15"}},
  {"id":5,"workflow_stage_id":51,"payload":{"pr_number":15}},
  {"id":6,"workflow_stage_id":51,"payload":{"pr_number":"#015"}},
  {"id":7,"workflow_stage_id":51,"payload":{"pr_number":"PR-15"}},
  {"id":8,"workflow_stage_id":51,"payload":{"pr_number":"99"}}
],"meta":{"last_page":1,"total":8}}
JSON
# The PR leg has no flag: shipped PR numbers are derived from the trailing `(#NNN)` squash marker
# in `git log <base>..<head>`. The tip is a MERGE commit so the completeness die (which fires on
# a 0-promoted run behind a non-merge tip) has nothing to say about this fixture either way.
GITDIR="$TMP/gitfx"; mkdir -p "$GITDIR"
git -C "$GITDIR" init -q -b main
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
git -C "$GITDIR" tag v0.0.1
git -C "$GITDIR" -c user.email=t@t -c user.name=t checkout -q -b feat
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: a thing (#15)"
git -C "$GITDIR" -c user.email=t@t -c user.name=t checkout -q main
git -C "$GITDIR" -c user.email=t@t -c user.name=t merge -q --no-ff feat -m "Merge feat"

run_prc_git() { : > "$PATCH_LOG"; rc=0
                out="$(cd "$GITDIR" && GITHUB_ACTIONS=1 "$PRC" --config "$TMP/release-pr.json" "$@" 2>"$TMP/err")" || rc=$?
                err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"; }
run_prc_git
eq "the derive run succeeds"                                  "0"     "$rc"
eq "'1.5' is NOT promoted onto PR 15"                         "false" "$(moved 1)"
eq "'1,5' is NOT promoted onto PR 15"                         "false" "$(moved 2)"
eq "'PR 1 of 5' is NOT promoted onto PR 15"                   "false" "$(moved 3)"
eq "control: '15' IS promoted"                                "true"  "$(moved 4)"
eq "control: a JSON-NUMBER 15 IS promoted"                    "true"  "$(moved 5)"
eq "control: '#015' IS promoted (decoration + leading zero)"  "true"  "$(moved 6)"
eq "control: 'PR-15' IS promoted"                             "true"  "$(moved 7)"
eq "control: an unrelated PR 99 stays put"                    "false" "$(moved 8)"
eq "the summary counts exactly the four real matches"         "true"  "$(has '4 moved,' "$out")"

echo "== end to end, dl_number: a multi-run stamp is not silently correlated, and is REPORTED =="
# The DL leg of the same def, driven by an explicit --dls set (no git range needed). It also
# pins the OPERATOR-FACING half: the shipped DL now matches no card, and the tool says so on
# stderr instead of quietly moving the wrong one. That line is the recovery path — an
# un-promoted card is moved by hand, which is only possible if someone is told.
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"2026-08-23"}},
  {"id":2,"workflow_stage_id":51,"payload":{"dl_number":"DL-0253"}}
],"meta":{"last_page":1,"total":2}}
JSON
run_prc --dls "DL-20260823,DL-253"
eq "the --dls run succeeds"                            "0"     "$rc"
eq "the '2026-08-23' card is NOT promoted"             "false" "$(moved 1)"
eq "control: 'DL-0253' IS promoted by DL-253"          "true"  "$(moved 2)"
eq "the unmatched DL is reported to the operator"      "true"  "$(has 'DL-20260823' "$err")"
eq "…as a no-card WARNING, not a silent skip"          "true"  "$(has 'matched NO card' "$err")"
eq "the summary counts one no-card ref"                "true"  "$(has '1 no-card' "$out")"

echo "== end to end: the card ID leg keeps working (the def is shared by all three) =="
# `norm` is single-sourced across dl_number, pr_number and id precisely so they cannot strip
# differently, so the id leg travels through the new guard too. A board id is always one digit
# run, which makes the guard a no-op there — asserted, because "no-op" is the claim that would
# make applying one def to all three legs safe, and an untested no-op is a hope.
run_prc --cards "2"
eq "the --cards run succeeds"                          "0"     "$rc"
eq "control: card 2 IS promoted by its own id"         "true"  "$(moved 2)"
eq "control: card 1 is untouched"                      "false" "$(moved 1)"

_summary promote-ref-canon-selftest
