#!/usr/bin/env bash
# bin-artifact-hygiene-selftest.sh — `bin/` is a PUBLISHED directory, not a build tree: running
# a tool out of it must not leave anything new inside it.
#
# WHAT IT GUARDS (card#6871). `docs/INSTALL.md` §2 installs the toolkit by globbing `bin/*` and
# symlinking every entry onto PATH one by one, and the framework's install arm does the same.
# Every entry of `bin/` is therefore a PATH entry, so an entry that is not a tool is a defect the
# moment it exists. The `bin/*.py` helpers were minting one: three of them path-load a sibling
# with `importlib.util.spec_from_file_location`, and a by-path load CACHES the compiled bytecode
# beside its TARGET, so one read-only `_kbc-may-archive.py` invocation created
# `bin/__pycache__/_kbc-archive-lib.cpython-312.pyc` — measured, rc 0, on a clean tree. Downstream
# of that: the framework's link arm symlinked `__pycache__` onto PATH and then REFUSED the whole
# directory on the next run, and `tests/lib-set-derivation-selftest.sh` had already had to grow a
# `grep -d skip` so its verdict would not depend on whether the maintainer had run a python
# helper. `__pycache__/` is gitignored, which is correct and is also what let this sit — an
# ignored artifact is invisible to `git status` while still being globbed by every consumer.
#
# THE RULE, and why it is stated over entry points rather than over load sites. A module cannot
# suppress its own `.pyc`: the loader writes the cache file while it COMPILES, ahead of running
# the module body, so `sys.dont_write_bytecode = True` only ever takes effect for loads made
# AFTER it — which means the ENTRY POINT has to set it. Every `bin/*.py` entry point therefore
# carries the line, whether or not it path-loads anything today. Conditioning the rule on "has a
# load site" was tried first and is the weaker shape twice over: it exempts a helper that reaches
# a load THROUGH the shared lib (a grep cannot see that), and it demands the line from
# `_kbc-archive-lib.py`, where it could not work.
#
# THE POPULATION AND HOW A PASS COVERS IT. Every `bin/*.py`, globbed from the tree on each run —
# never a list in this file, which is the shape that cannot go red when `bin/` grows a helper.
# Each is classified from its own source and the split is PRINTED with its counts:
#   * ENTRY POINT (`if __name__ == "__main__":`) — must carry the guard line.
#   * LIBRARY — must not be required to, for the reason above.
# Leg 1 asserts the two classes partition the glob exactly, so a file neither branch recognises
# reds instead of vanishing from the denominator.
#
# HOW EACH LEG IS SEEN TO FAIL — every leg here is an assertion of ABSENCE, and those pass for
# free when the thing that would create the artifact never ran:
#   * leg 2 runs each entry point TWICE — as shipped, and from a copy with its guard line
#     deleted. The MINTERS (the ones whose mutant actually writes) are derived by that
#     measurement, not by grep, and every entry point is disposed either as a minter with a
#     paired control or as one this driver could not make write, named in the output.
#   * leg 3 does the same for the framework plugin's directory — the second directory these
#     helpers were writing into, which is not even ours.
#   * leg 4 is the driver's own control: a synthetic helper with an unguarded by-path load, which
#     the same driver MUST mint against. Without it, "leaves nothing behind" could be a fact
#     about a driver that never reaches a load rather than about the tree.
#   * leg 5 pins that the guard is not "disable the thing" — rc and output byte-identical either
#     side of the deleted line.
#   * leg 6 asserts the flag is in effect where it has to be: set by the helper's OWN module
#     body, read False before the load and True after.
#
# ⛔ PYTHONDONTWRITEBYTECODE IS CLEARED FOR EVERY PROBE, explicitly. `_selftest-prelude.sh`
# exports it for the suite (so running the tests does not dirty the maintainer's own `bin/`), and
# inheriting it here would suppress the mutants too — every control below would go green while
# measuring nothing, which is exactly the vacuous pass this file exists to prevent. Each probe
# runs under `env -u PYTHONDONTWRITEBYTECODE`, and leg 0 asserts that spelling really does hand
# the interpreter back its default.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }
_need -r "$ROOT/bin/_kbc-archive-lib.py"

_mktmp_scratch

GUARD_LINE='sys.dont_write_bytecode = True'
MAIN_GUARD='if __name__ == "__main__":'

# _py <args...> — a python3 that starts with bytecode writing ENABLED, whatever the suite
# exported. Every probe in this file goes through it.
_py() { env -u PYTHONDONTWRITEBYTECODE python3 "$@"; }

# _fresh_bin — a private copy of bin/ under $TMP, minus any __pycache__ the host already had.
# Prints the copy's path. Each probe gets its own, so one leg cannot seed another.
_fresh_bin() {
    local d
    d="$(mktemp -d "$TMP/bin.XXXXXX")"
    cp -a "$ROOT/bin/." "$d/"
    rm -rf "$d/__pycache__"
    printf '%s\n' "$d"
}

# _strip_guard <basename> <bin-dir> — write the guard-stripped mutant of one helper into <bin-dir>.
_strip_guard() { grep -vx -- "$GUARD_LINE" "$ROOT/bin/$1" > "$2/$1"; }

# _listing <dir> — every entry, C-collated. The assertion subject is the DIRECTORY'S CONTENTS,
# not the presence of one known name: a leg that only looked for `__pycache__` would miss any
# other artifact a future helper drops in beside the tools.
_listing() { ls -A "$1" | LC_ALL=C sort; }

# NO_PLUGIN — an unresolvable `$KBCARD_KANBAN_COMMON`. Every probe below runs under it, and that
# is a correctness requirement, not tidiness: the helpers resolve the plugin AFTER the by-path
# load this file is about, so pointing the locator at nothing stops each of them at its own
# documented "primitive not found" refusal — past the load site, before `load_config()` and the
# board fetch behind it. Left unset, this selftest would make live API calls on any seat where
# the plugin happens to be installed, and would then measure something else again in CI.
NO_PLUGIN="$TMP/no-such-plugin/kanban_common.py"

# _drive <bin-dir> <basename> — invoke one helper the way a caller does, from inside its own
# directory copy. stdin is a JSON object because `_kbc-may-archive.py` reads one; `--help` is
# what the others take. Output and status are discarded HERE — this driver exists to make the
# helper run, and every assertion about it is made on the filesystem afterwards (or, for
# behaviour, in leg 5).
_drive() {
    printf '{}' | KBCARD_KANBAN_COMMON="$NO_PLUGIN" _py "$1/$2" --help >/dev/null 2>&1 || true
}

echo "== leg 0: the probe interpreter starts with bytecode writing ENABLED (control) =="
# If this is ever false, every mutant leg below is measuring nothing.
eq "env -u PYTHONDONTWRITEBYTECODE really clears the flag" "False" \
   "$(_py -c 'import sys; print(sys.dont_write_bytecode)')"
eq "…and the suite's own export is what it clears (so the -u is not decoration)" "True" \
   "$(PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys; print(sys.dont_write_bytecode)')"

echo "== leg 1: the derived population, and the rule over it =="
PY_FILES="$(cd "$ROOT/bin" && for f in *.py; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
done | LC_ALL=C sort)"
eq "the glob derives a non-empty population of bin/*.py (positive control)" "false" \
   "$([[ -z "$PY_FILES" ]] && echo true || echo false)"

ENTRIES=""
LIBS=""
UNGUARDED=""
while read -r f; do
    [[ -n "$f" ]] || continue
    if grep -qxF -- "$MAIN_GUARD" "$ROOT/bin/$f"; then
        ENTRIES+="$f"$'\n'
        grep -qxF -- "$GUARD_LINE" "$ROOT/bin/$f" || UNGUARDED+="$f "
    else
        LIBS+="$f"$'\n'
    fi
done <<< "$PY_FILES"

_count() { printf '%s' "$1" | grep -c . || true; }
printf '   population: %s bin/*.py — %s entry point(s), %s librar(y|ies)\n' \
    "$(_count "$PY_FILES")" "$(_count "$ENTRIES")" "$(_count "$LIBS")"
printf '   entry points: %s\n' "$(printf '%s' "$ENTRIES" | tr '\n' ' ')"
printf '   libraries:    %s\n' "$(printf '%s' "$LIBS" | tr '\n' ' ')"

# The partition must be exhaustive — a file in neither class means the classifier, not the tree,
# has changed, and every count printed above would be understating the population.
eq "the two classes partition the glob exactly" "$(_count "$PY_FILES")" \
   "$(( $(_count "$ENTRIES") + $(_count "$LIBS") ))"
eq "at least one entry point exists (positive control for legs 2, 5 and 6)" "false" \
   "$([[ -z "$ENTRIES" ]] && echo true || echo false)"

# THE RULE. An empty-set assertion so the failure message names the offending files.
eq "every bin/*.py entry point carries the guard line (add \`$GUARD_LINE\` to it)" "" \
   "${UNGUARDED% }"

echo "== leg 2: a real invocation leaves bin/ byte-identical — and the guard is what does it =="
MINTERS=""
INERT=""
while read -r f; do
    [[ -n "$f" ]] || continue

    clean="$(_fresh_bin)"
    before="$(_listing "$clean")"
    _drive "$clean" "$f"
    eq "$f: bin/ gains nothing after a real invocation" "$before" "$(_listing "$clean")"

    # The same invocation against a copy whose guard line is deleted. A mint here is the CONTROL
    # for the assertion above — it proves this driver reached a compile site in this file, and
    # that the deleted line is what suppresses it rather than some ambient condition.
    mut="$(_fresh_bin)"
    _strip_guard "$f" "$mut"
    eq "$f: the mutant differs from the shipped file (the deletion applied)" "false" \
       "$(cmp -s "$mut/$f" "$ROOT/bin/$f" && echo true || echo false)"
    _drive "$mut" "$f"
    if [[ -d "$mut/__pycache__" ]]; then
        MINTERS+="$f"$'\n'
        ok "$f: PROVE-IT-CAN-FAIL — without the guard line the same run mints __pycache__"
    else
        INERT+="$f "
    fi
done <<< "$ENTRIES"

# DISPOSE OF THE REMAINDER, out loud. An entry point whose mutant does not write is not a pass to
# be quiet about: it means this driver never reached a by-path load in it, so its clean run above
# is an unexercised assertion — true today (it path-loads nothing), and leg 4 is what shows the
# driver would have caught one. Named here so the coverage claim stays honest, and so a helper
# that stops being reachable shows up as a change in this line rather than as continued silence.
printf '   minters (mutant writes, so the clean run was measured): %s\n' \
    "$(printf '%s' "$MINTERS" | tr '\n' ' ')"
printf '   no reachable write on this driver: %s\n' "${INERT:-(none)}"
eq "at least one entry point's mutant mints (positive control for leg 2's pairs)" "false" \
   "$([[ -z "$MINTERS" ]] && echo true || echo false)"

echo "== leg 3: the framework plugin's directory is not ours to write into either =="
# `_kbc-archive-lib.py`'s `load_kanban_common` path-loads the plugin's `kanban_common.py` from
# wherever it lives — under `~/.claude/plugins/…` on a real seat. The same cache write landed
# THERE, in a directory this toolkit does not own. A stub stands in for the real plugin so the
# leg is deterministic and network-free; `$KBCARD_KANBAN_COMMON` is the shim's documented
# override and is exactly how a consumer points it at one.
_kc_probe() {   # _kc_probe <bin-dir> — true/false: did a __pycache__ appear beside the stub?
    local bindir="$1" kc
    kc="$(mktemp -d "$TMP/kc.XXXXXX")"
    cat > "$kc/kanban_common.py" <<'PY'
def may_archive(card, resolve, surviving_cards=None):
    return (True, "stub")


def _derive_card_source(card):
    return None
PY
    printf '{"card":{}}' | KBCARD_KANBAN_COMMON="$kc/kanban_common.py" \
        _py "$bindir/_kbc-may-archive.py" >/dev/null 2>&1 || true
    [ -d "$kc/__pycache__" ] && echo true || echo false
}

clean="$(_fresh_bin)"
eq "no __pycache__ beside the plugin's kanban_common.py after an archive-gate call" "false" \
   "$(_kc_probe "$clean")"
mut="$(_fresh_bin)"
_strip_guard "_kbc-may-archive.py" "$mut"
eq "PROVE-IT-CAN-FAIL — without the guard line the same call writes into the plugin's dir" "true" \
   "$(_kc_probe "$mut")"

echo "== leg 4: the driver DOES catch an unguarded by-path load (control for leg 2) =="
synth="$(mktemp -d "$TMP/synth.XXXXXX")"
printf 'VALUE = 1\n' > "$synth/_synth-lib.py"
cat > "$synth/_synth-helper.py" <<'PY'
import importlib.util
import os
import sys

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_synth-lib.py")
spec = importlib.util.spec_from_file_location("synth_lib", _LIB)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
sys.stdout.write(str(m.VALUE))
PY
_drive "$synth" "_synth-helper.py"
eq "a synthetic unguarded helper mints under the same driver" "true" \
   "$([ -d "$synth/__pycache__" ] && echo true || echo false)"

echo "== leg 5: the guard changes NOTHING a caller can observe =="
# The fix must not be "stop doing the work". Each entry point is run as shipped and as its
# guard-stripped mutant, and stdout, stderr and rc must be byte-identical across the pair — the
# same fixture on both sides, so the deleted line is the only difference between the two runs.
_capture() {   # _capture <bin-dir> <basename> — "<rc>|<stdout+stderr>"
    local out rc=0
    out="$(printf '{"card":{}}' | KBCARD_KANBAN_COMMON="$NO_PLUGIN" \
        _py "$1/$2" --help 2>&1)" || rc=$?
    printf '%s|%s' "$rc" "$out"
}

while read -r f; do
    [[ -n "$f" ]] || continue
    clean="$(_fresh_bin)"
    mut="$(_fresh_bin)"
    _strip_guard "$f" "$mut"
    shipped="$(_capture "$clean" "$f")"
    eq "$f: rc + output are byte-identical with and without the guard" \
       "$shipped" "$(_capture "$mut" "$f")"
    # …and that comparison is only worth something if the runs produced something to compare.
    eq "$f: the captured run is non-empty (positive control for the comparison above)" "false" \
       "$([[ "$shipped" == *"|" ]] && echo true || echo false)"
done <<< "$ENTRIES"

echo "== leg 6: sys.dont_write_bytecode is in effect AT MODULE SCOPE, before any load =="
# The flag is asserted where it has to hold — set by the helper's own module body, not merely
# exported by something upstream. The probe reads it before and after loading the helper; the
# BEFORE reading is the control (it must be False, or the AFTER reading is inherited, not set).
while read -r f; do
    [[ -n "$f" ]] || continue
    clean="$(_fresh_bin)"
    eq "$f: sys.dont_write_bytecode False before the load, True after it" "False True" \
       "$(_py - "$clean/$f" <<'PY'
import importlib.util
import sys

sys.dont_write_bytecode = False
before = sys.dont_write_bytecode
spec = importlib.util.spec_from_file_location("probe_target", sys.argv[1])
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except SystemExit:
    pass
print(before, sys.dont_write_bytecode)
PY
)"
done <<< "$ENTRIES"

_summary "bin-artifact-hygiene-selftest"
