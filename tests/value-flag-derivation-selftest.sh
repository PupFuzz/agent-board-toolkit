#!/usr/bin/env bash
# value-flag-derivation-selftest.sh — the control for `_value_flags` / `expect_value_flags`,
# the prelude helpers that ten selftests now trust to tell them what their bin's value-taking
# flag population IS.
#
# WHY THIS FILE EXISTS. Those ten blocks used to enumerate the population by hand, and a hand
# list cannot red when the bin grows a flag — promote-stage-guard-selftest named five of
# promote-released-cards' six and said "the whole class" while `--cards` went undriven
# (card#6645). Replacing ten hand lists with one derivation only moves the risk if the
# derivation is trusted unmeasured: a predicate that silently resolves nothing answers the
# empty set, and an empty set satisfies every two-way comparison made against it. So each
# resolution rule gets a fixture that pins what it MUST see, each non-rule gets a fixture that
# pins what it must NOT see, and the assertion itself is driven to red in both directions.
#
# THE FIXTURES ARE SYNTHETIC ON PURPOSE. Asserting the derived set of a real bin here would
# just be an eleventh hand list of flags, re-minting the defect one layer up — the mistake leg 3
# of `lib-set-derivation-selftest.sh` shipped. What is asserted against the REAL tree is the one
# property that needs no list: no bin in `bin/` contains a guard call this predicate fails to
# resolve.
#
# WHAT A GREEN RUN PROVES — the weakest reading the assertions support:
#   * that each of the three resolution rules, plus the literal-argument form, resolves the arm
#     shape its fixture spells, in both guard spellings;
#   * that a guard call mentioned in a COMMENT contributes no member;
#   * that an arm shape none of the rules resolves surfaces as an `UNRESOLVED:` member rather
#     than being dropped;
#   * that `expect_value_flags` reds when the list is short AND when the list is long, and that
#     it reds on an empty derivation;
#   * that no bin in `bin/` currently carries an unresolvable guard call.
# It proves nothing about whether any block DRIVES the flags it names, and nothing about any
# flag's behaviour — the derivation compares names.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
_mktmp_scratch

# _derived <fixture-body> — write the body to a scratch file and return its derived set as one
# space-separated line, so a whole set is one `eq` with the full diff visible on failure.
_derived() { printf '%s\n' "$1" > "$TMP/fixture"; _value_flags "$TMP/fixture" | tr '\n' ' ' | sed 's/ $//'; }

# _probe <bin> <flag>... — the number of `expect_value_flags` legs that FAIL for this input.
# Run in a subshell so the prelude's own `fails` counter is untouched: this file asserts on the
# assertion's verdict, so its failures are data here, not failures of this run.
_probe() { ( fails=0; expect_value_flags "$@" >/dev/null 2>&1; printf '%s' "$fails" ); }

# ---------------------------------------------------------------------------
echo "== rule 2 — the case pattern opening the SAME line, in both guard spellings =="
eq "same-line arms, require_value" "--base --config" "$(_derived '
  case "$1" in
    --base)   require_value "$1" "${2:-}"; BASE="$2"; shift 2;;
    --config) require_value "$1" "${2:-}"; CONFIG="$2"; shift 2;;
  esac')"
eq "same-line arms, kb_require_value" "--dl --repo" "$(_derived '
  case "$1" in
    --repo) kb_require_value "$1" "${2:-}" || exit 2; shift; repo="$1" ;;
    --dl)   kb_require_value "$1" "${2:-}" || exit 2; shift; req_dl="$1" ;;
  esac')"
# An alias arm is TWO members, not one: `-b ""` and `--board ""` are two inputs, and a block
# claiming the population must answer for both spellings.
eq "an alias arm contributes every spelling" "--board -b" "$(_derived '
  case "$1" in
    -b|--board) kb_require_value "$1" "${2:-}" || exit 2; shift; board="$1" ;;
  esac')"

echo "== rule 3 — the multi-line arm, and the \`if\` that is not a case arm at all =="
eq "the guard on a later line than its pattern" "--board --since" "$(_derived '
  case "$1" in
    --board)
        kb_require_value "$1" "${2:-}" || exit 2
        shift
        board="$1" ;;
    --since)
        kb_require_value "$1" "${2:-}" || exit 2
        shift; since="$1" ;;
  esac')"
# kbcard s global --board lives here, ahead of the verb dispatch: an if, no case in sight.
eq "an if-guarded global flag" "--board" "$(_derived '
  if [[ "${1:-}" == "--board" ]]; then
      kb_require_value "$1" "${2:-}" || exit 2
      board_name="$2"
      shift 2
  fi')"
eq "…and comments between the pattern and the guard do not break the walk" "--board" "$(_derived '
  if [[ "${1:-}" == "--board" ]]; then
      # The highest-stakes instance of the empty-value class: an empty --board falls
      # through to the DEFAULT board.
      kb_require_value "$1" "${2:-}" || exit 2
  fi')"

echo "== rule 1 — a literal flag as the guard call s own first argument =="
eq "literal first argument" "--dl" "$(_derived '  require_value "--dl" "${2:-}"')"

echo "== the negative controls — what must NOT become a member =="
# Every bin in this repo narrates its own guard in its header. If prose counted, the derived
# set would carry flags the parser never sees and every gate would red on documentation.
eq "a guard call inside a COMMENT contributes nothing" "" "$(_derived '
  # Mirrors kb_require_value in _kb-board-lib.sh — this script is vendored standalone.
  #     --dls) require_value "$1" "${2:-}"; DLS_IN="$2"; shift 2;;
  # keep the two in sync.')"
eq "the guard s own DEFINITION is not an arm" "" "$(_derived '
  require_value() { [ -n "${2:-}" ] || die "$1 requires a non-empty value"; }')"
eq "a flagless arm contributes nothing" "" "$(_derived '
  case "$1" in
    --dry-run) DRY=1; shift;;
  esac')"

echo "== an unresolvable arm SURFACES, it does not shrink the population =="
# The failure mode this guards is the one that makes a derived gate worse than a hand list: a
# new arm shape the predicate cannot parse would otherwise leave the population one member
# short with everything green. An UNRESOLVED member is in no hand list, so the gate reds.
unres="$(_derived '
  while getopts "b:" opt; do
      require_value "$opt" "${OPTARG:-}"
  done')"
eq "an unrecognised shape is reported, not dropped" "true" "$(has 'UNRESOLVED:' "$unres")"
eq "…and it names the line it could not resolve"    "true" "$(has 'UNRESOLVED:3' "$unres")"

echo "== expect_value_flags reds in BOTH directions =="
printf '%s\n' '
  case "$1" in
    --base)   require_value "$1" "${2:-}"; shift 2;;
    --config) require_value "$1" "${2:-}"; shift 2;;
  esac' > "$TMP/bin-two-flags"
eq "an exact list passes all three legs"          "0" "$(_probe "$TMP/bin-two-flags" --base --config)"
eq "a list SHORT one flag reds (the card#6645 defect)" "1" "$(_probe "$TMP/bin-two-flags" --base)"
eq "a list naming a flag the bin dropped reds"    "1" "$(_probe "$TMP/bin-two-flags" --base --config --gone)"
eq "both directions wrong at once reds twice"     "2" "$(_probe "$TMP/bin-two-flags" --gone)"
eq "order and duplicates in the list are immaterial" "0" \
   "$(_probe "$TMP/bin-two-flags" --config --base --config)"
# The positive control's own control, and the reason it exists: a file with no guard at all
# derives the EMPTY set, and an empty derivation compared against an empty list satisfies both
# comm legs — a gate reporting "nothing unaccounted" while having measured nothing. Exactly
# one leg must red here, and it is the control.
: > "$TMP/bin-no-flags"
eq "an empty derivation vs an empty list reds — once, on the control" "1" \
   "$(_probe "$TMP/bin-no-flags")"
eq "…and vs a non-empty list reds twice (control + parity)" "2" \
   "$(_probe "$TMP/bin-no-flags" --base)"

echo "== against the real tree: no bin/ carries a guard call this predicate cannot resolve =="
# The one leg asserted against the live tree, and deliberately not a list of flags: it needs no
# expected set, so it cannot rot, and it is what tells a future arm shape apart from a silent
# under-count. The witness first — an absence assertion over a scan that found no files is not
# a measurement.
scanned=0; unresolved=""
for b in "$ROOT"/bin/*; do
    [[ -f "$b" ]] || continue
    scanned=$((scanned + 1))
    while read -r m; do
        [[ "$m" == UNRESOLVED:* ]] && unresolved="$unresolved $(basename "$b"):$m"
    done < <(_value_flags "$b")
done
eq "witness: bin/ was actually scanned" "false" "$([[ "$scanned" -eq 0 ]] && echo true || echo false)"
eq "unresolvable guard call sites in bin/" "" "$unresolved"

_summary "value-flag-derivation-selftest"
