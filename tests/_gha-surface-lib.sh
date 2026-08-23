# shellcheck shell=bash
# _gha-surface-lib.sh — the ONE derivation of "which YAML documents does GitHub Actions execute
# in this repository?", for the gates whose population IS that surface.
# Sourced after `_selftest-prelude.sh`, alongside it.
#
# WHY THIS EXISTS (card#7207, review round). Three gates in `tests/` derive that population and
# they had TWO predicates between them: `ci-matrix-parity-selftest.sh` and
# `shellcheck-pin-selftest.sh` each globbed `*.yml` AND `*.yaml`, while
# `python-syntax-gate-selftest.sh` — the newest copy — globbed `*.yml` only. Measured: a planted
# `.github/workflows/sneak.yaml` running `python3 -m py_compile bin/*.py` was INVISIBLE to it
# (`all checks passed`), and the identical file renamed `.yml` reds. GitHub Actions loads both
# spellings, so the narrow copy's absence verdict was over a population smaller than the one it
# said it covered. Fixing the third copy without hoisting leaves the divergence itself standing
# — three implementations of one rule, which is how the next one gets it wrong (canon #5, well
# past the second caller).
#
# THE PREDICATE IS THE SPELLING SET, AND IT IS DECIDED HERE ONCE:
#   * a WORKFLOW is any `*.yml` or `*.yaml` file directly in the scanned directory. GitHub reads
#     `.github/workflows/` one level deep and accepts both extensions; nothing else there runs.
#   * a COMPOSITE ACTION is any file named `action.yml` or `action.yaml` at ANY depth under the
#     scanned root (`.git` pruned). Depth is not the repo's choice: `uses: ./x/y` resolves to
#     `x/y/action.yml`, so a nested action is as executable as a top-level one. The two live
#     actions here sit at depth 1 today; a `.github/actions/foo/action.yml` tomorrow is covered
#     with no edit.
#
# THE POPULATION IS A PARAMETER, never a constant baked in here — every caller passes the
# directory or root to scan. That is what lets a gate point the SAME derivation at a planted
# fixture tree, so what its control certifies is the code path the live assertion runs
# (`ci-matrix-parity-selftest.sh` and `shellcheck-pin-selftest.sh` both do exactly this).
#
# ORDER IS C-COLLATED, matching `sorted()` in the python the callers feed: codepoint order, so a
# caller that hands these paths to a parser and compares the result against another C-collated
# stream is comparing two identically-ordered streams (`ci-matrix-parity-selftest.sh` runs
# `comm` over one). A locale sort would reorder punctuated names and corrupt that diff.
#
# ⛔ WHERE THIS PREDICATE IS WATCHED, because it is watched in ONE place and not three.
# `python-syntax-gate-selftest.sh`'s leg 1 plants a fixture triple — `dirty.yml`, `dirty.yaml` and
# a NESTED `action.yaml` — through this derivation and asserts the derived list itself. Measured:
# narrowing the loop below back to `*.yml` reds that gate and leaves BOTH siblings green, because
# their own fixtures are `.yml` files and nothing there would notice. That is the shape of one
# owner with one guard, not a gap to close by copying the fixture into three files — but it does
# mean an edit HERE is answered by THAT file, and a future gate that stops calling it silently
# leaves the rule behind.
#
# ⛔ WHAT THIS DOES NOT DECIDE, stated so it is not over-cited. It answers WHICH FILES, and
# nothing about what any caller then looks for inside them — the `run:`-block walk, the trigger
# predicate and the token scans stay at their own call sites, where each is reasoned. Adopting
# this changes which line computes a population, not what any gate asserts.

# _gha_workflow_files <dir> — every workflow document directly in <dir>, C-collated, absolute or
# relative exactly as <dir> was given. Empty output (no trailing blank line) when the directory
# holds none or does not exist — every caller asserts non-emptiness itself, because "the glob
# found nothing" and "the tree is clean" are the two answers an absence gate must not confuse.
_gha_workflow_files() {
    local d="$1" f
    local -a out=()
    for f in "$d"/*.yml "$d"/*.yaml; do
        [[ -f "$f" ]] || continue          # an unmatched glob arrives as its own literal text
        out+=("$f")
    done
    [[ "${#out[@]}" -gt 0 ]] || return 0
    printf '%s\n' "${out[@]}" | LC_ALL=C sort
}

# _gha_action_files <root> — every composite-action document under <root>, at any depth, with
# `.git` pruned. C-collated.
_gha_action_files() {
    find "$1" -name .git -prune -o -type f \( -name action.yml -o -name action.yaml \) -print \
        2>/dev/null | LC_ALL=C sort
}
