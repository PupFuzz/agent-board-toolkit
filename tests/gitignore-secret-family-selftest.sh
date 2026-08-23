#!/usr/bin/env bash
# gitignore-secret-family-selftest.sh — the control for `bin/gitignore-secret-family-check`.
#
# WHY THIS FILE EXISTS. The tool's whole value is that it REDS when a secret-bearing .gitignore
# rule's backup family is not covered. A checker that silently derives an empty population, or
# whose sample instantiation resolves to a path nothing matches, reports "no findings" while
# having measured nothing — and that reads exactly like a clean repo. So every resolution rule
# gets a fixture pinning what it MUST see, every non-rule gets a fixture pinning what it must
# NOT see, and the verdict is driven to red and to green in both directions.
#
# THE FIXTURES ARE SYNTHETIC ON PURPOSE. Asserting an expected finding list for this repo's own
# .gitignore would be a hand list of rules — the defect one level up, and the thing the tool
# exists to remove. What is asserted against the REAL tree is the one property that needs no
# list: this repository's own .gitignore passes its own check.
#
# WHAT A GREEN RUN PROVES — the weakest reading the assertions support:
#   * that both classification routes (a keyword in the RULE, a keyword in the COMMENT BLOCK
#     above it) put a rule in the population, and that a comment block does not leak its
#     classification into a later, unrelated block;
#   * that a negation, a directory rule, a keyword-free rule, and a rule that IS itself a
#     backup-affix rule each contribute NO member;
#   * that an uncovered family member reds (rc 1) and naming it in the ignore file greens it;
#   * that a trailing-`*` rule covers its own suffix family, and that the emacs WRAPPER
#     spelling `#<name>#` is NOT covered by any `*.suffix` rule — the shape that made the
#     first pass of this fix incomplete;
#   * that an EMPTY derived population is a REFUSAL (rc 2), not a pass, and that --allow-empty
#     converts it to an explicit answer;
#   * that a family member which is TRACKED is not reported as a finding;
#   * that this repo's own .gitignore currently passes.
# It proves nothing about whether the affix table is COMPLETE — it cannot be, and the tool says
# so — and nothing about what .gitignore any deployed install actually runs.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
BIN="$ROOT/bin/gitignore-secret-family-check"
_need -x "$BIN"
_mktmp_scratch --home

_n=0
# _fx <gitignore-body> [extra-args...] — build a throwaway repo carrying that .gitignore, run
# the tool in it, and set RC/OUT. Each fixture gets its own repo so no rule leaks between them.
_fx() {
    local body="$1"; shift
    _n=$((_n + 1))
    local d="$TMP/fx$_n"
    mkdir -p "$d"
    git -C "$d" init -q .
    printf '%s\n' "$body" > "$d/.gitignore"
    RC=0; OUT="$("$BIN" --repo "$d" "$@" 2>&1)" || RC=$?
}

echo "== classification route 1 — a keyword in the RULE's own text =="
_fx '.env'
eq "a keyword-bearing rule enters the population" "true" "$(has 'secret-bearing rules derived: 1' "$OUT")"
eq "…and its uncovered family reds"               "1"    "$RC"
eq "…naming the rule that produced it"            "true" "$(has 'UNCOVERED' "$OUT")"
eq "…and tagging WHY it was classified"           "true" "$(has '[rule-text]' "$OUT")"

echo "== classification route 2 — a keyword in the COMMENT BLOCK above the rule =="
_fx '# per-environment secrets live here
.kanban-config'
eq "a keyword-free rule under a secrets heading is classified" "true" "$(has '[comment-block]' "$OUT")"
eq "…and is asserted, not skipped" "true" "$(has 'secret-bearing rules derived: 1' "$OUT")"

echo "== a comment block does NOT leak into the next block =="
# The defect this pins: a flag reset only on a blank line kept the first heading's
# classification alive over every later rule in the file, so `*.pyc` read as secret-bearing.
_fx '# secrets
.env*
# python bytecode
*.pyc'
eq "only the rule under the secrets heading is in the population" "true" \
   "$(has 'secret-bearing rules derived: 1' "$OUT")"

echo "== the negative controls — what must NOT become a member =="
_fx '!/.env'
eq "a NEGATION names no secret to protect" "2" "$RC"
eq "…and refuses rather than reporting clean over nothing" "true" "$(has 'ZERO secret-bearing rules' "$OUT")"
_fx '# secrets
secrets/'
eq "a DIRECTORY rule has no backup sibling" "true" "$(has 'SKIP dir-rule' "$OUT")"
_fx 'build/output.log'
eq "a keyword-free rule with no heading is invisible" "2" "$RC"
_fx '# secrets
.env*
*~
*.bak'
eq "a rule that IS a backup-affix rule is skipped by shape" "true" "$(has 'SKIP affix-rule' "$OUT")"

echo "== the verdict reds and greens in BOTH directions =="
_fx '.env'
eq "a bare literal rule is UNCOVERED" "1" "$RC"
eq "…and the emacs wrapper spelling is among the members named" "true" "$(has '#.env#' "$OUT")"
_fx '.env*'
eq "a trailing-* rule covers its whole SUFFIX family" "false" "$(has '.bak-20260717' "$OUT")"
eq "…but a *.suffix rule can never reach the WRAPPER spelling, so it still reds" "1" "$RC"
eq "…naming exactly that member" "true" "$(has '#.envx#' "$OUT")"
_fx '.env*
\#*#
.#*'
eq "adding the wrapper rules greens it" "0" "$RC"
eq "…over a non-zero assertion count (the run measured something)" "false" \
   "$(has 'family assertions made:       0' "$OUT")"

echo "== an UNESCAPED leading hash is a comment, not a rule — the second-pass defect =="
# `#*#` looks like the fix and does nothing at all. It must not green the wrapper leg.
_fx '.env*
#*#
.#*'
eq "an unescaped \`#*#\` leaves the wrapper member uncovered" "1" "$RC"

echo "== the affix TABLE parses as rows, not as its own prose =="
# THE BUG THIS PINS, measured: the table's provenance notes wrap onto INDENTED continuation
# lines, and a `read -r a _` reader strips leading whitespace — so `\`name (copy)\`` became an
# affix and the tool reported "`name" as an uncovered family member. Prose entering the
# population is the same class the tool exists to catch, one level up.
#
# Two independent counts of the same set: the tool's RUNTIME assertion count, and a count of
# column-0 rows taken from the tool's source here. They are compared, never hard-coded — a
# literal expected number would rot at the next affix added.
rows="$(awk '/^SUFFIX_AFFIXES=/{f=1;next} f && /^.$/{exit} f && /^[.~]/{c++} END{print c+0}' "$BIN")"
eq "witness: the affix table was actually read (non-zero row count)" "false" \
   "$([ "$rows" -eq 0 ] && echo true || echo false)"
_fx '# secrets
.env'
# one secret rule x (rows suffix affixes + 2 wrapper affixes)
eq "runtime assertion count equals the table's column-0 rows + the 2 wrappers" "true" \
   "$(has "family assertions made:       $((rows + 2))" "$OUT")"
# Scoped to the MEMBERS line alone. The remedy prose below it legitimately carries backticks,
# so scanning the whole output asserts nothing about the population — it just reads the advice.
members="$(printf '%s\n' "$OUT" | sed -n 's/.*family members NOT ignored://p')"
eq "witness: a members line was actually captured" "false" \
   "$([ -z "$members" ] && echo true || echo false)"
eq "no derived family member carries a backtick (prose cannot enter the population)" "false" \
   "$(has '`' "$members")"

echo "== the population's own positive control =="
_fx '# nothing secret here
build/'
eq "an EMPTY derived population is a REFUSAL, never a pass" "2" "$RC"
_fx '# nothing secret here
build/' --allow-empty
eq "…and --allow-empty turns it into an explicit answer" "0" "$RC"
eq "…that says so on the record" "true" "$(has 'ZERO secret-bearing rules derived' "$OUT")"

echo "== a TRACKED family member is not a finding (--no-index is load-bearing) =="
# `git check-ignore` suppresses INDEXED paths and answers rc 1 for them — "not ignored" — even
# where a rule plainly matches. Without --no-index a tracked `.env.example` would be reported as
# an uncovered member, which is a false finding this tool must never emit.
_n=$((_n + 1)); d="$TMP/fxtracked"; mkdir -p "$d"
git -C "$d" init -q .
printf '%s\n' '# secrets' '.env*' '\#*#' '.#*' > "$d/.gitignore"
printf 'PLACEHOLDER=dummy\n' > "$d/.envx.bak"
git -C "$d" add -f .gitignore .envx.bak
git -C "$d" -c user.email=t@t.t -c user.name=t commit -qm x
RC=0; OUT="$("$BIN" --repo "$d" 2>&1)" || RC=$?
eq "a tracked family member does not read as uncovered" "0" "$RC"

echo "== usage / refusal surface =="
RC=0; OUT="$("$BIN" --repo "$TMP" 2>&1)" || RC=$?
eq "a directory that is not a git work tree is a refusal" "2" "$RC"
RC=0; OUT="$("$BIN" --bogus 2>&1)" || RC=$?
eq "an unknown option is rc 2" "2" "$RC"
RC=0; OUT="$("$BIN" --help 2>&1)" || RC=$?
eq "--help exits 0" "0" "$RC"
eq "…and reproduces the file's own header" "true" "$(has 'THE TWO DERIVATIONS, STATED' "$OUT")"

echo "== against the real tree: this repository's own .gitignore passes its own check =="
RC=0; OUT="$("$BIN" --repo "$ROOT" 2>&1)" || RC=$?
eq "the toolkit's own .gitignore covers every derived family member" "0" "$RC"
# The witness, first: a green verdict over a population of zero would satisfy the line above
# while measuring nothing, and this repo's .gitignore is exactly the artifact whose rules could
# be renamed out from under the predicate.
eq "witness: the real-tree run derived a non-empty population" "false" \
   "$(has 'secret-bearing rules derived: 0' "$OUT")"
eq "witness: …and made assertions against it" "false" \
   "$(has 'family assertions made:       0' "$OUT")"

_summary "gitignore-secret-family-selftest"
