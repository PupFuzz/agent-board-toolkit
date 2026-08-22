#!/usr/bin/env bash
# prelude-shadow-selftest.sh — assert that no tests/*-selftest.sh re-declares a helper
# `_selftest-prelude.sh` already defines, except the variants sanctioned below.
#
# WHY THIS FILE EXISTS. `has()` — a literal-substring assertion helper — was hand-copied into
# ten selftests, and one copy took its arguments in the opposite order. That divergence cannot
# go red: reversing the arguments of a substring test is neither a syntax nor a type error, so
# `has <haystack> <needle>` under a needle-first definition compares two unrelated strings,
# answers `false`, and EVERY assertion expecting `false` keeps passing while testing nothing.
# Per-file review could not see it either — the inverted file was internally consistent across
# its own eight call sites, so only comparing two definitions could reveal it (card#5740).
#
# THE COPIES WERE DELETED; THE RULE THAT KEEPS THEM DELETED WAS NOT WRITTEN. Card#5740 left
# `has()` with exactly one definition and a prelude comment saying it "lives here and nowhere
# else" — enforced by nothing. A comment is not a gate (the lesson `ci-matrix-parity-selftest`
# was built on), and the eleventh copy would be re-minted in silence with the whole suite
# green. Fixing N copies without the guard that forbids the N+1th leaves the defect's cause in
# place, so this is the closure of that class rather than a new one.
#
# WHAT IS FORBIDDEN IS SILENT DISAGREEMENT, NOT LOCAL DEFINITION. A selftest that needs a
# genuine variant may define one — the prelude's own docblock says so. What must not happen is
# a second definition of the SAME behaviour drifting from the shared one unobserved. The
# sanctioned variants are therefore allow-listed BY NAME here, one line each with its reason:
# adding a shadow costs an explicit edit to this file, which is exactly the review moment the
# ten silent copies never got.
#
# THE HELPER SET IS DERIVED FROM THE PRELUDE, NEVER RESTATED. A hardcoded list here would be a
# second copy of the prelude's own function list — this repo's recurring defect, and the one
# `ci-matrix-parity-selftest` and `help-output-selftest` each closed on their own registry. Add
# a helper to the prelude and it is guarded on the next run with no edit here.
#
# BOUND, STATED SO IT IS NOT OVER-CITED: this compares NAMES, not behaviour. It catches a
# re-declared helper; it cannot catch a selftest that hand-rolls the same logic inline under a
# different name, and it says nothing about whether the prelude's own argument order is right.
# It closes the copy channel that actually minted the bug, not every conceivable one.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

PRELUDE="$HERE/_selftest-prelude.sh"
_need -r "$PRELUDE"

# Sanctioned shadows: "<selftest basename>:<helper>" — one line per variant, with its reason.
# kb-board-lib-selftest's pair route their failures through the shared `eq` so the prelude's
# PASS/FAIL counter still sees them; they differ in reporting, not in what they assert.
SANCTIONED=(
    "kb-board-lib-selftest:expect_rc"
    "kb-board-lib-selftest:expect_out"
)

# _defs_in <file> — every top-level function that file defines, C-collated. ONE extractor,
# used for the prelude and for each selftest alike: a second copy specialised to the prelude is
# the duplication this very test forbids, and it would drift the moment one side learned a
# spelling the other did not.
#
# All three bash spellings are matched, and that is not padding. The guard is worth only the
# spellings it recognises: `has ()` (a space before the parens) and `function has {` (no parens
# at all) are valid bash and define exactly the same shadow as `has()`. A name-only regex would
# have let the next copy evade the guard by a keystroke while reading as covered.
#
# Anchored at column zero on purpose: a nested definition is indented, and only a top-level one
# shadows the sourced prelude for the rest of the script.
_defs_in() {
    sed -nE \
        -e 's/^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\).*/\2/p' \
        -e 's/^function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\{.*/\1/p' \
        "$1" | LC_ALL=C sort -u
}

_is_sanctioned() {
    local pair="$1" s
    for s in "${SANCTIONED[@]}"; do
        [[ "$s" == "$pair" ]] && return 0
    done
    return 1
}

mapfile -t HELPERS < <(_defs_in "$PRELUDE")
[[ "${#HELPERS[@]}" -gt 0 ]] || bad "prelude defines no helpers — the derivation is broken, not the tree"

echo "== no selftest re-declares a prelude helper =="

shadows=""
for f in "$HERE"/*-selftest.sh; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f" .sh)"
    while read -r fn; do
        [[ -n "$fn" ]] || continue
        for h in "${HELPERS[@]}"; do
            if [[ "$fn" == "$h" ]]; then
                pair="${base}:${fn}"
                _is_sanctioned "$pair" || shadows+="${pair}"$'\n'
            fi
        done
    done < <(_defs_in "$f")
done

eq "no unsanctioned prelude-helper shadows" "" "${shadows%$'\n'}"

# The allow-list must not outlive what it excuses: a sanctioned entry naming a shadow that no
# longer exists is a stale exception that would silently re-permit a future copy of that name.
echo "== every sanctioned shadow still exists =="
for s in "${SANCTIONED[@]}"; do
    base="${s%%:*}" fn="${s##*:}"
    if [[ -e "$HERE/${base}.sh" && "$(has_line "$fn" "$(_defs_in "$HERE/${base}.sh")")" == true ]]; then
        ok "sanctioned $s is live"
    else
        bad "sanctioned $s no longer exists — remove the allow-list entry"
    fi
done

# The helper set is derived, so a prelude that stopped defining `has` would silently stop
# guarding the exact helper this class was minted on. Pin that one by name.
echo "== the helper this class was minted on is still derived =="
[[ "$(has_line has "$(printf '%s\n' "${HELPERS[@]}")")" == true ]] \
    && ok "has is in the derived helper set" \
    || bad "has is not in the derived helper set — the prelude no longer defines it"

_summary "prelude-shadow-selftest"
