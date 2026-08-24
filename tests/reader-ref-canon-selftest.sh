#!/usr/bin/env bash
# reader-ref-canon-selftest.sh — the one-decorated-integer rule as the LIB-SOURCING bins apply
# it: the shared `KB_JQ_REF_CANON` constant, held level with the vendored standalone's copy of
# the same jq text, and driven end-to-end through the two tools that act on its answer.
#
# WHY THIS FILE EXISTS (card#7592). `bin/board-card-start` selected which card to move by the
# FIRST DIGIT RUN of that card's stored `payload.dl_number` (`capture("(?<n>[0-9]+)")`), so a
# card stamped `2026-08-23` answered to **DL-2026** and the post-checkout hook **MOVED it** —
# the wrong card, on an ordinary branch checkout, landing in the board changelog as an event
# that looks legitimate afterwards. It is the OVER-matching member of the class card#7587
# opened: that one CONCATENATED the runs and could correlate a card to an unrelated shipped PR;
# this one TRUNCATES to the first run and fires without waiting for a release. Two siblings from
# the same audit are fixed with it — `bin/next-dl`s board DL-floor scan, which SPLIT a multi-run
# stamp and raised the floor to 2026 (safe direction, but the floor is shared state and every
# number under it is burned permanently), and `board-card-start`s own stamp-conflict comparison,
# which compared first-run-equal and SUPPRESSED the warning that tells an operator the card
# holds a value no correlating tool can read.
#
# ⛔ WHAT IT GUARDS THAT `promote-ref-canon-selftest.sh` CANNOT. That file owns the standalone
# `bin/promote-released-cards` (which must not source the lib) and the bash MINT predicate in
# `bin/kbcard`. This file owns the THIRD shipped spelling — `KB_JQ_REF_CANON` in
# `bin/_kb-board-lib.sh` — and the bins that prepend it. `tests/_ref-canon-cases.sh` is the
# shared table both files run, so no side can move alone; on top of it this file asserts the
# lib constant and the standalone jq text are BYTE-IDENTICAL, which is the strongest anti-drift
# claim available for a copy that cannot be deleted.
#
# LAYERS, and why each is not redundant:
#   1. the shared table, against the constant taken from the SHIPPED lib by sourcing it;
#   2. byte-identity with the standalone's inline `def norm:`, extracted from the shipped bin;
#   3. differentials against the THREE pre-fix expressions, kept verbatim — behaviour-neutrality
#      on well-formed values MEASURED against the old code rather than restated as expectations,
#      each with the control that proves the two sides are not simply the same expression;
#   4. a DERIVED census of every stored-stamp read in every lib-sourcing bin, so the N+1th
#      reader cannot join the tree unguarded and undeclared;
#   5. the two bins as PROCESSES against a faked board, with the PATCH set observable — the only
#      layer that can show the constant is WIRED. A unit-clean normaliser nothing calls looks
#      identical to a fixed tool at layers 1-4.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_ref-canon-cases.sh"
LIB="$HERE/../bin/_kb-board-lib.sh"
BCS="$HERE/../bin/board-card-start"
NDL="$HERE/../bin/next-dl"
PRC="$HERE/../bin/promote-released-cards"
_need -r "$LIB"
_need -x "$BCS"
_need -x "$NDL"
_need -r "$PRC"
# shellcheck source=/dev/null
source "$LIB"   # a pure function/constant library: sourcing it runs nothing

_mktmp_scratch --home

# ---------------------------------------------------------------------------
echo "== layer 1: the shared canon, taken from the SHIPPED lib, over the shared table =="
# POSITIVE CONTROL FIRST, and it is load-bearing here in a way it is not elsewhere: an UNSET or
# empty KB_JQ_REF_CANON makes every jq call below a syntax error whose stdout is empty — which
# every row expecting "" would accept. Two witnesses, because either alone is satisfiable by the
# broken state: the constant is non-empty, AND it answers a known well-formed value.
eq "the shipped lib defines KB_JQ_REF_CANON (positive control)" "false" \
   "$([ -z "${KB_JQ_REF_CANON:-}" ] && echo true || echo false)"

# jqnorm_s <string> — the shipped constant's answer for a raw string (jq --arg does the quoting,
# so an embedded newline reaches the reader intact).
jqnorm_s() { jq -rn --arg v "$1" "$KB_JQ_REF_CANON \$v|norm"; }
# jqnorm <json-literal> — the same, for a value already spelled as JSON.
jqnorm()   { jq -rn "$KB_JQ_REF_CANON ($1)|norm"; }
eq "…and it answers a known well-formed value (positive control)" "253" "$(jqnorm_s 'DL-0253')"

# The fixture itself, by the same rule — a table that loaded as the empty array satisfies every
# comparison below by running none. The witness is a ROW, not a count: a count pins this file to
# a past table size and rots the moment a case is added.
eq "the shared fixture loaded (positive control)" "false" \
   "$([ "${#REF_CANON_CASES[@]}" -eq 0 ] && echo true || echo false)"
eq "…and carries the flagship defect case"        "true"  \
   "$(has_line '2026-08-23||2026 8 23|refuse-multirun' "$(printf '%s\n' "${REF_CANON_CASES[@]}")")"

correlated=0; uncorrelated=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ _ <<< "$row"
    val="$(printf '%b' "$raw")"
    eq "lib canon: '$raw' → '$want_norm'" "$want_norm" "$(jqnorm_s "$val")"
    if [ -n "$want_norm" ]; then correlated=$((correlated + 1)); else uncorrelated=$((uncorrelated + 1)); fi
done
# BOTH ARMS ARE POPULATED. A table that had drifted to all-correlate or all-refuse would satisfy
# every row above while measuring one direction of the rule.
eq "the table exercises the CORRELATE arm"   "false" "$([ "$correlated"   -eq 0 ] && echo true || echo false)"
eq "the table exercises the UNCORRELATED arm" "false" "$([ "$uncorrelated" -eq 0 ] && echo true || echo false)"

echo "== JSON types the table cannot spell: a number, an absent key, a bool =="
# `payload.dl_number` is stamped as a STRING by this toolkit but reaches the reader as a JSON
# NUMBER on any board whose field is declared numeric, and as `null` when the key is absent.
eq "a numeric stamp normalises like its string form" "312" "$(jqnorm '312')"
eq "a numeric multi-run stamp correlates to nothing" ""    "$(jqnorm '1.5')"
eq "an ABSENT key (null) correlates to nothing"      ""    "$(jqnorm 'null')"
eq "a JSON true correlates to nothing"               ""    "$(jqnorm 'true')"

echo "== non-ASCII: the rule is ASCII digits, and no collation widens it =="
# `[^0-9]` is a NEGATED ASCII set, so a locale that widens a RANGE cannot widen this. Asserted
# rather than assumed; tests/locale-range-guard-selftest.sh owns the range class itself.
AI3=$'٣'
eq "a bare U+0663 correlates to nothing"        ""  "$(jqnorm_s "$AI3")"
eq "'4<U+0663>' is 4 decorated (control)"       "4" "$(jqnorm_s "4$AI3")"

# ---------------------------------------------------------------------------
echo "== layer 2: the lib constant and the vendored standalone are BYTE-IDENTICAL =="
# The rule is expressed in jq TWICE and cannot be expressed once: promote-released-cards is
# vendored standalone into consumer repos and must not source the lib, so it cannot read the
# constant. What it CAN be held to is sameness. The extraction is asserted to have found exactly
# one line — none would compare an empty string and two would compare a concatenation.
prc_norm="$(awk '/^[[:space:]]*def norm:/ {print}' "$PRC")"
eq "extracted exactly one 'def norm:' from the standalone" "1" \
   "$(printf '%s\n' "$prc_norm" | awk 'NF' | wc -l | tr -d ' ')"
eq "the standalone's jq text IS KB_JQ_REF_CANON, byte for byte" \
   "$KB_JQ_REF_CANON" "${prc_norm#"${prc_norm%%[![:space:]]*}"}"
# ⛔ AND THE APOSTROPHE RULE, on the value that now travels through TWO single-quoted shell
# strings. An apostrophe inside either ends its string and re-parses the rest as shell — a
# RUNTIME failure that shellcheck does not see (card#7587 recorded it; this is the guard).
eq "KB_JQ_REF_CANON carries no apostrophe" "false" "$(has "'" "$KB_JQ_REF_CANON")"

# ---------------------------------------------------------------------------
echo "== layer 3a: neutrality vs the PRE-FIX board-card-start SELECTION expression =="
# THE PRE-FIX SELECTION KEY, verbatim as it shipped through v0.30.0:
#     | (.payload.dl_number // empty) as $raw
#     | ($raw | tostring) as $s
#     | select($s | test("[0-9]"))
#     | select(($s | capture("(?<n>[0-9]+)").n | tonumber) == $want)
# i.e. the FIRST digit run, read as a number. Spelled below as a function of the stored value so
# the two keys can be compared directly; an absent key took `// empty` there and `// ""` here,
# which reach the same outcome (no digits ⇒ no key ⇒ the row selects nothing).
PRE_BCS_SELECT='def norm: (. // "")|tostring|if test("[0-9]") then (capture("(?<n>[0-9]+)").n|tonumber|tostring) else "" end;'
pre_select_s() { jq -rn --arg v "$1" "$PRE_BCS_SELECT \$v|norm"; }

# THE WHOLE COMPATIBILITY CLAIM, as a differential rather than as this file's expectations: a
# card stamped `DL-0253`, `093`, `#178` or a bare id selects exactly the card it selected before.
changed=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ _ <<< "$row"
    [ -n "$want_norm" ] || continue
    val="$(printf '%b' "$raw")"
    eq "selection unchanged vs pre-fix: '$raw'" "$(pre_select_s "$val")" "$(jqnorm_s "$val")"
    [ "$(pre_select_s "$val")" = "$(jqnorm_s "$val")" ] || changed=$((changed + 1))
done
eq "no well-formed value changed which card it selects" "0" "$changed"

# CONTROL FOR THAT DIFFERENTIAL, and it is not optional: the block above is satisfied by two
# IDENTICAL expressions, i.e. by a fix that was never applied. The pre-fix side must still
# produce the old wrong keys, and the disagreement must be exactly the uncorrelated digit-bearing
# rows. The expectation is DERIVED from the table's own counts, not written as a figure.
eq "pre-fix selection still truncates '2026-08-23'"  "2026" "$(pre_select_s '2026-08-23')"
eq "pre-fix selection still truncates '1.5'"         "1"    "$(pre_select_s '1.5')"
eq "pre-fix selection still truncates 'PR 12 of 34'" "12"   "$(pre_select_s 'PR 12 of 34')"
disagreed=0; nodigits=0; nocorrelate=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ want_mint <<< "$row"
    [ "$want_mint" = refuse-nodigits ] && nodigits=$((nodigits + 1))
    [ -z "$want_norm" ] || continue
    nocorrelate=$((nocorrelate + 1))
    val="$(printf '%b' "$raw")"
    [ "$(pre_select_s "$val")" = "$(jqnorm_s "$val")" ] || disagreed=$((disagreed + 1))
done
# A row carrying NO digits already answered "" pre-fix, so the two agree there and always did.
# Every OTHER uncorrelated row is one the pre-fix key answered a NUMBER for — that difference IS
# the fix, and it is the population that used to move the wrong card.
eq "the two keys disagree on every DIGIT-bearing uncorrelated row" \
   "$((nocorrelate - nodigits))" "$disagreed"

echo "== layer 3b: neutrality vs the PRE-FIX stamp-CONFLICT comparison =="
# THE PRE-FIX COMPARISON, verbatim as it shipped through v0.30.0 — a bash pipeline, not jq:
#     curdl_num="$(printf '%s' "$curdl" | grep -oE '[0-9]+' | head -1 | sed 's/^0*//')"
#     … elif [ "$curdl_num" != "$dl" ]; then <warn>
pre_conflict() { printf '%s' "$1" | grep -oE '[0-9]+' | head -1 | sed 's/^0*//' || true; }

# ⚠ THE OBSERVABLE IS THE BRANCH TAKEN, NOT THE INTERMEDIATE STRING, and the difference matters
# on exactly two rows. `0` and `000` gave "" pre-fix (the zero-strip consumed the whole value)
# and give "0" now. Neither is reachable as an OUTCOME: `$dl` comes from `kb_dl_num`, which
# REFUSES 0, so `$dl` is always >= 1 and both spellings compare unequal to it. The claim below is
# therefore made on the branch, over every DL a real branch could name, rather than on the string
# — a string-level assertion here would have to declare a divergence that no run can observe.
warn_pre() { [ "$(pre_conflict "$1")" != "$2" ] && echo warn || echo silent; }
warn_new() { [ "$(jqnorm_s "$1")"    != "$2" ] && echo warn || echo silent; }
conflict_changed=0
for row in "${REF_CANON_CASES[@]}"; do
    IFS='|' read -r raw want_norm _ _ <<< "$row"
    [ -n "$want_norm" ] || continue
    val="$(printf '%b' "$raw")"
    # Every DL a branch could name against this stamp: the one it means, its neighbours, and a
    # far-away control. 0 is deliberately absent — kb_dl_num cannot produce it.
    for d in 1 5 42 253 7592; do
        [ "$(warn_pre "$val" "$d")" = "$(warn_new "$val" "$d")" ] || conflict_changed=$((conflict_changed + 1))
    done
    # …plus the DL this very stamp names, when it names one >= 1 (the silent arm).
    if [ "$want_norm" != "0" ]; then
        eq "conflict arm unchanged on its own DL: '$raw'" \
           "$(warn_pre "$val" "$want_norm")" "$(warn_new "$val" "$want_norm")"
        eq "…and that arm is SILENT (the stamp agrees with the branch): '$raw'" \
           "silent" "$(warn_new "$val" "$want_norm")"
    fi
done
eq "no well-formed stamp changed the conflict branch, for any reachable DL" "0" "$conflict_changed"

# CONTROL: the two sides are NOT the same expression. On a multi-run stamp whose first run IS
# the branch DL, the pre-fix comparison went SILENT — the operator was never told the card holds
# a stamp no correlating tool can read — and the fixed one WARNS.
eq "pre-fix: '1.5' against DL-1 was SILENT"          "silent" "$(warn_pre '1.5' 1)"
eq "fixed:   '1.5' against DL-1 WARNS"               "warn"   "$(warn_new '1.5' 1)"
eq "pre-fix: '2026-08-23' against DL-2026 was SILENT" "silent" "$(warn_pre '2026-08-23' 2026)"
eq "fixed:   '2026-08-23' against DL-2026 WARNS"      "warn"   "$(warn_new '2026-08-23' 2026)"

echo "== layer 3c: neutrality vs the PRE-FIX next-dl DL-floor scan =="
# THE PRE-FIX SCAN, verbatim as it shipped through v0.30.0:
#     printf '%s' "$cards" | jq -r '.[]?.payload.dl_number // empty' | max_int
# `max_int` is unchanged and is LIFTED FROM THE SHIPPED BIN rather than restated, so this
# measures the change to the jq leg and nothing else. The extraction is asserted to have found
# it — a rename would otherwise leave every row below running against an undefined function.
ndl_maxint="$(grep -E '^max_int\(\) \{' "$NDL")"
eq "lifted exactly one 'max_int()' from the shipped bin" "1" \
   "$(printf '%s\n' "$ndl_maxint" | awk 'NF' | wc -l | tr -d ' ')"
eval "$ndl_maxint"
eq "…and it is the shipped max (positive control)" "90" "$(printf '7\n90\n3\n' | max_int)"

pre_floor() { printf '%s' "$1" | jq -r '.[]?.payload.dl_number // empty' | max_int || true; }
new_floor() { printf '%s' "$1" | jq -r "$KB_JQ_REF_CANON"'.[]? | .payload.dl_number | norm | select(. != "")' | max_int || true; }

WELLFORMED_BOARD='[{"id":1,"payload":{"dl_number":"DL-0219"}},{"id":2,"payload":{"dl_number":"93"}},{"id":3,"payload":{"dl_number":312}},{"id":4,"payload":{}},{"id":5,"payload":{"dl_number":"#7"}}]'
eq "a well-formed board yields the SAME floor as pre-fix" "$(pre_floor "$WELLFORMED_BOARD")" "$(new_floor "$WELLFORMED_BOARD")"
eq "…and that floor is the real max (positive control)"   "312" "$(new_floor "$WELLFORMED_BOARD")"
eq "an empty board is empty on both sides"                "$(pre_floor '[]')" "$(new_floor '[]')"
eq "…and that is the empty answer (positive control)"     ""    "$(new_floor '[]')"

# CONTROL: one multi-run stamp used to raise the floor by four orders of magnitude and burn
# every number under it. `max_int` split `2026-08-23` into 2026 / 8 / 23 and took the max.
DRIFTED_BOARD='[{"id":1,"payload":{"dl_number":"2026-08-23"}},{"id":2,"payload":{"dl_number":"DL-0219"}}]'
eq "pre-fix: one '2026-08-23' stamp raised the floor to 2026" "2026" "$(pre_floor "$DRIFTED_BOARD")"
eq "fixed:   it contributes nothing; the floor is the real one" "219" "$(new_floor "$DRIFTED_BOARD")"

# ---------------------------------------------------------------------------
echo "== layer 4: the DERIVED census of stored-stamp reads in lib-sourcing bins =="
# ⛔ WHAT THIS ASSERTS, stated as the predicate it actually runs and no wider. Over the
# LIB-SOURCING bins — derived by the same anchored pattern _kb-board-lib.sh's own header
# publishes, never a list — take every NON-COMMENT line mentioning `.payload.dl_number`,
# `.payload.pr_number`, `.payload.issue_number` or `.external_id`. Each such line must be
# either:
#   (a) CANON-GUARDED — the line names `KB_JQ_REF_CANON` (the jq invocation that prepends it)
#       or pipes the field through `norm` (a continuation line of such an invocation, which is
#       how a multi-line jq program spells the same thing); or
#   (b) DECLARED in the disposition set below, with the reason it does not have to be.
# Arm (a) rests on `norm` meaning the shared constant and nothing else in these bins, which is
# NOT assumed — the assertion below it is that no lib-sourcing bin defines its own `def norm:`,
# so the only definition any of these programs can be carrying is the one layer 2 pins.
# It says nothing about a reader that spells the field some other way, and nothing about the
# non-sourcing standalone (layer 2 owns that one).
#
# WHY IT IS WORTH A GATE. This class has now been minted three times in this tree by three
# different hands (card#7587, card#7592 twice), because a stamp read is two characters of jq and
# nothing objects. Fixing the N call-sites without a guard leaves the N+1th to mint it again.
mapfile -t LIB_SOURCERS < <(grep -lE '^[[:space:]]*source "\$KB_LIB"' "$HERE/../bin/"* | sort)
eq "the lib-sourcer derivation matched bins (positive control)" "false" \
   "$([ "${#LIB_SOURCERS[@]}" -eq 0 ] && echo true || echo false)"
eq "…and it found board-card-start among them (named witness)" "true" \
   "$(has_line "$HERE/../bin/board-card-start" "$(printf '%s\n' "${LIB_SOURCERS[@]}")")"

# The census, as `<bin>:<line-text-with-leading-space-collapsed>`. Comment-only lines are
# excluded: prose naming a field is not a read of one.
census="$(grep -nE '\.payload\.(dl_number|pr_number|issue_number)|\.external_id' "${LIB_SOURCERS[@]}" \
          | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
          | sed -E 's|^.*/bin/|bin/|; s/^([^:]+):[0-9]+:[[:space:]]*/\1: /' | sort)"
eq "the census is non-empty (positive control)" "false" \
   "$([ -z "$census" ] && echo true || echo false)"

# THE DISPOSITION SET — one entry per census member that does NOT go through the canon, each
# with the reason it does not have to. A new member reds this file until somebody rules on it.
DISPOSITIONED=(
  # A raw read whose ONLY consumer is the operator-facing conflict message, which quotes the
  # stamp VERBATIM (`has dl_number=2026-08-23`). Normalising it would print a value the card
  # does not hold. It is never compared and never written; the line below it does the compare,
  # through the canon.
  "bin/board-card-start: curdl=\"\$(printf '%s' \"\$card\" | jq -r '.data.payload.dl_number // empty' 2>/dev/null)\""
  # DECLINED, card#7592, with the ruling already written where the divergence lives: this reads
  # through kb_dl_int_lenient, which CONCATENATES runs on purpose, and its docblock in
  # _kb-board-lib.sh dispositions this exact caller. The caller is fail-CLOSED — a multi-run
  # stamp yields a non-empty int, which the already-adopted guard reads as "already adopted" and
  # REFUSES on, so there is no write and no wrong card. The cost is a diagnostic naming a DL that
  # does not exist. Narrowing it is a behaviour change to the adoption guard, not this class.
  "bin/adopt-to-dl: existing_int=\"\$(kb_dl_int_lenient \"\$(kb_parse_resp \"\$card\" -r '.data.payload.dl_number // empty')\")\""
  # PROJECTIONS, not correlations: kbcard renders these fields for a human or for `--json`. A
  # projection MUST show what is stored — normalising it would hide from the operator that the
  # card holds a stamp the correlating tools refuse, which is the one place they need to see it.
  "bin/kbcard: [[ -n \"\$ext_id\" ]] && echo_extra=\"\$echo_extra, external_id: (.external_id // null)\""
  "bin/kbcard: external_id: (.external_id // null),"
  "bin/kbcard: dl: .payload.dl_number, pr: .payload.pr_number})'"
)
undeclared=""; canon_n=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Arm (a): the invocation line, or a continuation line piping the field through `norm`.
    if [ "$(has 'KB_JQ_REF_CANON' "$line")" = true ] || [ "$(has '| norm' "$line")" = true ]; then
        canon_n=$((canon_n + 1)); continue
    fi
    hit=false
    for d in "${DISPOSITIONED[@]}"; do [ "$d" = "$line" ] && hit=true && break; done
    [ "$hit" = true ] || undeclared="$undeclared"$'\n'"$line"
done <<< "$census"
eq "every stored-stamp read is canon-guarded or DECLARED" "" "$undeclared"
# WHAT MAKES ARM (a) MEAN ANYTHING: `norm` in a lib-sourcing bin can only be the shared
# constant, because none of them defines one. Without this, a bin could ship its own `def norm:`
# and satisfy the census while implementing whatever it liked.
eq "no lib-sourcing bin defines its own 'def norm:'" "" \
   "$(grep -hE '^[^#]*def[[:space:]]+norm[[:space:]]*:' "${LIB_SOURCERS[@]}" || true)"
# …and the canon arm is populated, so a tree that had lost the constant entirely (every read
# falling into the disposition set) cannot satisfy the line above by having nothing to check.
eq "the census contains canon-guarded reads (positive control)" "false" \
   "$([ "$canon_n" -eq 0 ] && echo true || echo false)"
# NEGATIVE CONTROL for the census predicate itself — the assertion above is an ABSENCE, and an
# absence over a population the grep failed to build is vacuous. A planted unguarded read must
# be reported.
planted="bin/planted: cid=\"\$(jq -r '.payload.dl_number' <<< \"\$c\")\""
_undeclared_probe=""
for d in "${DISPOSITIONED[@]}"; do [ "$d" = "$planted" ] && _undeclared_probe=hit; done
eq "CONTROL: a planted unguarded read is NOT in the disposition set" "" "$_undeclared_probe"

# ---------------------------------------------------------------------------
# --- layers 5: the bins as PROCESSES, against a faked board -------------------------------
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
kb_stub_scrub_env
unset KB_DL_CHECKOUT_GLOBS NEXT_DL_PAGE_CAP KB_BCS_LOG
kb_stub_board_config t 42 \
    'export KB_STAGE_IN_PROGRESS=84' \
    'export KB_STAGE_BACKLOG=81' \
    'export KB_STAGE_PRIORITIZED=82' \
    'export KB_STAGE_HELD=83'
kb_stub_install

echo "== layer 5a: board-card-start — a multi-run stamp selects NO card, so nothing moves =="
# The board every branch below is run against. Cards 1 and 5 carry multi-run stamps whose FIRST
# RUN is the DL a branch names; cards 2, 3, 4 and 6 are the controls — four spellings that
# genuinely name their DL, including the JSON-number form, a legacy 3-pad and the canonical
# 4-pad. Every card is in Backlog (81) on board 42, i.e. every one of them is movable, which is
# what makes "did not move" a decision rather than a stage gate.
BCS_BOARD='{"data":[
  {"id":1,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"2026-08-23"}},
  {"id":2,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-0253"}},
  {"id":3,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"093"}},
  {"id":4,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":312}},
  {"id":5,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"1.5"}},
  {"id":6,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-0409"}}
],"meta":{"last_page":1,"total":6}}'
export BCS_BOARD
BCS_CARD=""
export BCS_CARD

kb_stub_route() {
    local _id _body
    case "$1 $2" in
        "GET "*/tasks/search.json*)
            printf '%s\n%s' 200 "$BCS_BOARD" ;;
        "GET "*/tasks/*.json)
            if [ -n "${BCS_CARD:-}" ]; then printf '%s\n%s' 200 "$BCS_CARD"; return 0; fi
            _id="${2##*/tasks/}"; _id="${_id%%.json}"
            _body="$(printf '%s' "$BCS_BOARD" | jq -c --argjson i "$_id" '{data: ([.data[]|select(.id==$i)]|.[0] // null)}')"
            printf '%s\n%s' 200 "$_body" ;;
        "PATCH "*/tasks/*.json)
            printf '%s\n%s' 200 '{"data":{"id":0}}' ;;
    esac
}
export -f kb_stub_route

# run_bcs <branch> — a fresh git repo checked out on <branch>, board 42 declared host-locally,
# board-card-start run as a PROCESS against the stub. A fresh repo per run because the Held-stage
# arm reads the branch reflog; nothing here depends on that, and a shared repo would make it a
# hidden input.
BCS_N=0
run_bcs() {
    local br="$1" d
    BCS_N=$((BCS_N + 1)); d="$TMP/bcsrepo$BCS_N"
    mkdir -p "$d"
    git -C "$d" init -q -b main
    git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
    git -C "$d" checkout -q -b "$br"
    git -C "$d" config kanban.board-id 42
    kb_stub_reset
    rm -f "$TMP/bcs.log"
    rc=0
    out="$(cd "$d" && KB_BCS_LOG="$TMP/bcs.log" "$BCS" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
}
# moved <id> → true/false: was card <id> PATCHed on the last run?
moved() { [ "$(kb_stub_count PATCH "/tasks/$1.json")" != 0 ] && echo true || echo false; }
# patched_body <id> — the PATCH body sent to card <id>.
patched_body() { kb_stub_bodies PATCH "/tasks/$1.json"; }

if command -v git >/dev/null 2>&1; then
    run_bcs "feature/dl2026-fix"
    eq "the run exits 0 (a hook must never block a checkout)" "0" "$rc"
    eq "the board WAS read (positive control)" "1" "$(kb_stub_count_any /tasks/search.json)"
    eq "'2026-08-23' is NOT moved by DL-2026"  "false" "$(moved 1)"
    eq "…and NO card at all was moved"         "0" "$(kb_stub_count PATCH /tasks/)"
    eq "…and the miss is LOUD, naming the DL"  "true" \
       "$(has 'branch names DL-2026 but no card carries that dl_number' "$err")"
    eq "…and it reached the durable log too"   "true" "$(has 'DL-2026' "$(cat "$TMP/bcs.log")")"

    run_bcs "feature/dl1-x"
    eq "'1.5' is NOT moved by DL-1"            "false" "$(moved 5)"
    eq "…and the miss is LOUD"                 "true" \
       "$(has 'branch names DL-1 but no card carries that dl_number' "$err")"

    echo "== layer 5b: CONTROLS — every well-formed spelling still selects and moves =="
    # Without these, a board-card-start that had stopped selecting ANYTHING would satisfy every
    # assertion above. Each control is one stored spelling the fix must not have touched.
    run_bcs "feature/dl253-x"
    eq "control: 'DL-0253' IS moved by DL-253"   "true" "$(moved 2)"
    eq "control: …to the In Progress stage id"   "true" "$(has '"workflow_stage_id":84' "$(patched_body 2)")"
    eq "control: …and no other card moved"       "1"    "$(kb_stub_count PATCH /tasks/)"
    run_bcs "feature/dl93-x"
    eq "control: legacy 3-pad '093' IS moved by DL-93" "true" "$(moved 3)"
    run_bcs "feature/dl312-x"
    eq "control: a JSON-NUMBER 312 IS moved by DL-312" "true" "$(moved 4)"
    run_bcs "feature/dl409-x"
    eq "control: canonical 'DL-0409' IS moved by DL-409" "true" "$(moved 6)"
    run_bcs "feature/dl888-x"
    eq "control: an unrelated DL-888 moves nothing"      "0"    "$(kb_stub_count PATCH /tasks/)"
    eq "control: …and says so"                           "true" \
       "$(has 'branch names DL-888 but no card carries that dl_number' "$err")"

    echo "== layer 5c: the stamp-CONFLICT warning fires on a stamp no tool can read =="
    # Reached through the card-id FALLBACK: the branch names DL-1 and card 4242, DL-1 now selects
    # nothing, so the run falls through to the card id and the stamp step compares the card's own
    # dl_number against the branch DL. Both arms there are write-free — the stamp is only written
    # when the card carries NONE — so the whole cost of the old first-run compare was the
    # operator not being told.
    BCS_BOARD='{"data":[
      {"id":4242,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"1.5"}}
    ],"meta":{"last_page":1,"total":1}}'
    export BCS_BOARD
    run_bcs "fix/card4242-dl1-x"
    eq "the DL falls through to the card id"          "true" \
       "$(has 'DL-1 matches no card — falling through to #4242' "$err")"
    eq "the unreadable stamp is REPORTED as a conflict" "true" \
       "$(has 'card #4242 has dl_number=1.5 but branch names DL-1 — NOT overwriting (stamp conflict)' "$err")"
    eq "…quoting the stamp VERBATIM, not a normalised form" "false" "$(has 'dl_number=1 but' "$err")"
    eq "…and NO payload stamp was written"            "false" "$(has 'dl_number' "$(patched_body 4242)")"
    eq "…while the card itself still moves"           "true"  "$(has '"workflow_stage_id":84' "$(patched_body 4242)")"

    # A second spelling of the same defect, because ONE case here is one case: the pre-fix
    # comparison went silent on any stamp whose FIRST RUN happens to equal the branch DL, and
    # a date-shaped stamp is the spelling that actually turned up in the audit.
    BCS_BOARD='{"data":[
      {"id":4243,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"2026-08-23"}}
    ],"meta":{"last_page":1,"total":1}}'
    export BCS_BOARD
    run_bcs "fix/card4243-dl2026-x"
    eq "a date-shaped stamp is REPORTED as a conflict too" "true" \
       "$(has 'card #4243 has dl_number=2026-08-23 but branch names DL-2026' "$err")"
    eq "…and it is not silently read as DL-2026"           "false" "$(has 'dl_number=2026 but' "$err")"

    # CONTROL — the SILENT arm, which is only reachable when the board list does not carry the
    # card the branch names (a card past the page cap, or archived out of the list). The stamp
    # and the branch agree, so there is nothing to warn about, and the fix must not have turned
    # that into a warning.
    BCS_BOARD='{"data":[],"meta":{"last_page":1,"total":0}}'
    BCS_CARD='{"data":{"id":4242,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-0001"}}}'
    export BCS_BOARD BCS_CARD
    run_bcs "fix/card4242-dl1-x"
    eq "control: an AGREEING stamp warns about nothing" "false" "$(has 'stamp conflict' "$err")"
    eq "control: …and the card still moves"             "true"  "$(has '"workflow_stage_id":84' "$(patched_body 4242)")"
    # CONTROL — a genuinely CONFLICTING well-formed stamp still warns, exactly as before.
    BCS_CARD='{"data":{"id":4242,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-0007"}}}'
    export BCS_CARD
    run_bcs "fix/card4242-dl1-x"
    eq "control: a well-formed CONFLICT still warns"     "true"  \
       "$(has 'card #4242 has dl_number=DL-0007 but branch names DL-1' "$err")"
    BCS_CARD=""
    export BCS_CARD
else
    bad "git is not on PATH — the board-card-start process layer could not be exercised"
fi

echo "== layer 5d: next-dl — a multi-run stamp does not raise this board's DL floor =="
# The allocator, driven the way next-dl-selftest drives it: the claim endpoint answers 404 so
# the run reaches the offline scan, and a LOCAL floor of DL-0300 makes the difference an
# observable MINT rather than two identical refusals. Board floor 219 (< 300) ⇒ DL-0301; the
# pre-fix split of `2026-08-23` gave 2026 (> 300) ⇒ DL-2027.
_ndl_checkout="$TMP/pm-checkout"
mkdir -p "$_ndl_checkout"
printf '## DL-0300 — a local header the offline scan will find\n' > "$_ndl_checkout/CLAUDE_DECISIONS.md"
export KB_DL_CHECKOUT_GLOBS="$_ndl_checkout"

kb_stub_route() {
    case "$1 $2" in
        "POST "*/dl-sequence/claim.json)  printf '%s\n%s' 404 '{"message":"not found"}' ;;
        "GET "*/tasks/search.json*)       printf '%s\n%s' 200 "$NDL_BOARD" ;;
    esac
}
export -f kb_stub_route

run_ndl() { kb_stub_reset; rc=0; out="$("$NDL" "$@" 2>"$TMP/err")" || rc=$?; err="$(cat "$TMP/err")"; }

NDL_BOARD='{"data":[{"id":1,"payload":{"dl_number":"2026-08-23"}},{"id":2,"payload":{"dl_number":"DL-0219"}}],"meta":{"last_page":1,"total":2}}'
export NDL_BOARD
run_ndl --board t
eq "the run succeeds"                                "0" "$rc"
eq "the board WAS read (positive control)"           "1" "$(kb_stub_count_any /tasks/search.json)"
eq "'2026-08-23' does not raise the floor to 2026"   "false" "$(has 'DL-2027' "$out")"
eq "the floor is the local one, so the mint is 301"  "DL-0301" "$out"

# CONTROL — the same fixture with the multi-run card REMOVED must mint the same thing, which is
# what makes the assertion above about the guard rather than about the local floor winning
# anyway. And a board whose real floor is ABOVE the local one must still win, or this test would
# be green against a next-dl that had stopped reading the board at all.
NDL_BOARD='{"data":[{"id":2,"payload":{"dl_number":"DL-0219"}}],"meta":{"last_page":1,"total":1}}'
export NDL_BOARD
run_ndl --board t
eq "control: without the drifted card the mint is unchanged" "DL-0301" "$out"
NDL_BOARD='{"data":[{"id":2,"payload":{"dl_number":"DL-0876"}},{"id":3,"payload":{"dl_number":93}}],"meta":{"last_page":1,"total":2}}'
export NDL_BOARD
run_ndl --board t
eq "control: a well-formed board floor ABOVE the local one still wins" "DL-0877" "$out"

# The case the bin's own exit-code note now names: a board that READ cleanly and carries only
# stamps that name no DL reaches the SAME arm as a board carrying no stamp at all — it mints
# from the local sources at rc 0, rather than refusing. Asserted because the note is a claim
# about an rc, and an unrun claim about an rc is a guess.
NDL_BOARD='{"data":[{"id":1,"payload":{"dl_number":"2026-08-23"}},{"id":2,"payload":{"dl_number":"1.5"}}],"meta":{"last_page":1,"total":2}}'
export NDL_BOARD
run_ndl --board t
eq "a board of ONLY uncorrelatable stamps still mints (rc 0)" "0" "$rc"
eq "…from the local floor alone"                              "DL-0301" "$out"
eq "…and it does NOT refuse as an unreadable board would"     "false" "$(has 'could not be read at all' "$err")"

_summary reader-ref-canon-selftest
