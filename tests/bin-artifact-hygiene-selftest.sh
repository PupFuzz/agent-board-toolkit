#!/usr/bin/env bash
# bin-artifact-hygiene-selftest.sh — `bin/` is a PUBLISHED directory, not a build tree: running
# a tool out of it must not leave anything new inside it.
#
# WHAT IT GUARDS (card#6871). `docs/INSTALL.md` §2 installs the toolkit by globbing `bin/*` and
# symlinking each entry onto PATH one by one, and the framework's install arm does the same.
# Every entry of `bin/` is therefore a candidate PATH entry, so an entry that is not a tool is a
# defect the moment it exists. The `bin/*.py` helpers were minting one: three of them path-load a
# sibling with `importlib.util.spec_from_file_location`, and a by-path load CACHES the bytecode
# beside its TARGET, so one read-only `_kbc-may-archive.py` invocation created
# `bin/__pycache__/_kbc-archive-lib.cpython-312.pyc` — measured, rc 0, on a clean tree. Downstream
# of that: the framework's link arm symlinked `__pycache__` onto PATH and then REFUSED the whole
# directory on the next run, and `tests/lib-set-derivation-selftest.sh` had already had to grow a
# `grep -d skip` so its verdict would not depend on whether the maintainer had run a python
# helper. `__pycache__/` is gitignored, which is correct and is also what let this sit — an
# ignored artifact is invisible to `git status` while still being globbed by every consumer.
#
# ⛔ THIS FILE IS NOT THE RECIPE'S GUARD, and the recipe does not rely on it (card#7170). Keeping
# `bin/` clean and keeping the documented install loop correct are two independent obligations:
# the loop ran `ln -sf` over every glob member, and `ln -sf` FOLLOWS a symlink-to-directory rather
# than replacing it, so a second run planted `bin/__pycache__/__pycache__ -> bin/__pycache__` — a
# cycle inside the consumer's checkout, at rc 0. That is closed at the recipe (`[ -f "$t" ]` plus
# `-n`), guarded by `tests/path-link-recipe-selftest.sh`, and stated over ANY non-regular-file
# entry rather than over `__pycache__`. Neither guard subsumes the other: this one keeps the
# population empty, that one keeps the loop safe when it is not.
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
# THE POPULATION, AND WHY THE EXEMPTION IS WHAT GETS DERIVED. Every `bin/*.py`, globbed from the
# tree on each run — never a list in this file, which is the shape that cannot go red when `bin/`
# grows a helper. The rule then has to decide who is EXCUSED, and that is the only decision with
# an err-GREEN direction, so it is the one that is derived rather than pattern-matched:
#   * LIBRARY — a file some OTHER `bin/*.py` names AND that carries no `__main__` marker at all.
#     Both halves are required. Exempt: no process ever starts at it, so it has no "before the
#     load" to set the flag in.
#   * ENTRY POINT — anything carrying a `__main__` marker. Must carry the guard line.
#   * UNCLASSIFIED — no `__main__` marker and no sibling names it. Must carry the guard line AND
#     is reported RED on its own: it is a file this classifier does not recognise, and the answer
#     is a human decision, not a default.
#
# An earlier cut keyed the whole classification on `grep -qxF 'if __name__ == "__main__":'` — one
# exact spelling. That errs GREEN in the worst possible direction: a helper spelling it with
# single quotes, or with top-level code and no `__main__` at all, was filed as a LIBRARY, exempted
# from the rule, and dropped out of every dynamic leg as well, so nothing measured it. The
# classifier is now built so that NO recognition failure can exempt anything — the `__main__`
# probe is deliberately BROAD (any `__main__` token), because over-matching moves a file into
# ENTRY POINT and under-matching moves it into UNCLASSIFIED, and both of those must carry the
# guard. Only the LIBRARY conjunction excuses a file, and leg 1 tests that exemption's PREMISE
# dynamically rather than trusting the classification.
#
# ⛔ THE ONE RESIDUAL, stated rather than papered over: a file that carries no `__main__` marker,
# IS named by a sibling, and is nonetheless executed as a script. It would be exempted. Running
# it directly still caches nothing for itself (`python3 x.py` never caches `__main__`), so it can
# only leak through something IT loads. `tests/prelude-shadow-selftest.sh` is this repo's
# precedent for "a guard is worth only the spellings it recognises"; this is where the remaining
# gap in that principle sits here.
#
# HOW EACH LEG IS SEEN TO FAIL — every leg here is an assertion of ABSENCE, and those pass for
# free when the thing that would create the artifact never ran:
#   * leg 2 runs each entry point TWICE — as shipped, and from a copy with its guard line
#     deleted. The MINTERS (the ones whose mutant actually writes) are derived by that
#     measurement, not by grep, and every entry point is disposed either as a minter with a
#     paired control or as one this driver could not make write, named in the output.
#   * leg 3 covers the OTHER directory this `bin/` writes into and does not own — the framework
#     plugin's. Two routes reach it, and they need different fixes: our own helpers get there
#     through `_kbc-archive-lib.load_kanban_common` (closed in-process, by the same guard line),
#     and `board-session-close` hands the plugin's OWN `kanban-reconcile.py` to `python3`, a file
#     this repo cannot edit but whose invocation and environment it owns. So leg 3 derives EVERY
#     `python3` invocation site in `bin/` + `hooks/` and requires each to resolve to either a
#     guarded toolkit sibling or an explicit `PYTHONDONTWRITEBYTECODE=1`; a site it cannot
#     resolve is reported UNRESOLVED and reds, rather than counting as covered.
#   * leg 4 is the driver's own control: a synthetic helper with an unguarded by-path load, which
#     the same driver MUST mint against. Without it, "leaves nothing behind" could be a fact
#     about a driver that never reaches a load rather than about the tree.
#   * leg 5 pins that the guard is not "disable the thing" — rc and output byte-identical either
#     side of the deleted line, for every entry point on its refusal path, AND for one helper on
#     a path that does real work (the stub plugin), so the claim is not measured only on early
#     exits.
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

# Captured the instant the prelude has been sourced and before anything in this file touches it:
# leg 0 asserts the SUITE-WIDE export is still there. Nothing else can see its loss — this file
# clears the variable per probe by design, so deleting the prelude's export would leave this
# selftest at exit 0 while `kbc-may-archive-selftest.sh` quietly re-created `bin/__pycache__`.
INHERITED_PDWB="${PYTHONDONTWRITEBYTECODE:-<unset>}"

ROOT="$(cd "$HERE/.." && pwd)"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }
_need -r "$ROOT/bin/_kbc-archive-lib.py"

_mktmp_scratch

GUARD_LINE='sys.dont_write_bytecode = True'
ENV_GUARD='PYTHONDONTWRITEBYTECODE=1'
# Deliberately BROAD — see the header. Over-matching files a helper as an ENTRY POINT and
# under-matching files it as UNCLASSIFIED; both must carry the guard line, so no spelling this
# misses can ever be excused by missing it.
MAIN_MARK='__main__'
LOAD_SITE='spec_from_file_location'

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

# _pyc_present <dir> <module-name> — true/false: is there a cached .pyc for <module-name> under
# <dir>/__pycache__? A `[ -f "$d/__pycache__/$m."*.pyc ]` reads naturally and is wrong: with no
# match the word stays literal (false for the right reason, by luck) and with two it is
# `[: too many arguments` (false for the WRONG reason, i.e. err-green on a leg asserting
# PRESENCE). shellcheck SC2144 named it; the loop is the fix, not a suppression.
_pyc_present() {
    local d="$1" m="$2" f
    for f in "$d"/__pycache__/"$m".*.pyc; do
        [[ -f "$f" ]] && { echo true; return; }
    done
    echo false
}

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
# The other half of the fix, and the only leg that can see it: leg 0's first two checks prove the
# SPELLING is honoured by the interpreter, which stays true whether or not the suite still sets
# it. This one asserts `_selftest-prelude.sh` still does.
eq "the suite prelude still exports PYTHONDONTWRITEBYTECODE=1 to every selftest" "1" \
   "$INHERITED_PDWB"

echo "== leg 1: the derived population, the derived EXEMPTION, and the rule over both =="
PY_FILES="$(cd "$ROOT/bin" && for f in *.py; do
    [[ -e "$f" ]] && printf '%s\n' "$f"
done | LC_ALL=C sort)"
eq "the glob derives a non-empty population of bin/*.py (positive control)" "false" \
   "$([[ -z "$PY_FILES" ]] && echo true || echo false)"

# _named_by_a_loader <basename> — true/false: does some OTHER bin/*.py both NAME this file and
# contain a by-path load site? The naming file has to be a loader, so a file mentioned only in a
# sibling's prose does not collect a library exemption on the strength of the mention.
_named_by_a_loader() {
    local me="$1" other
    for other in "$ROOT"/bin/*.py; do
        [[ "$(basename "$other")" == "$me" ]] && continue
        grep -qF -- "$me" "$other" || continue
        grep -qF -- "$LOAD_SITE" "$other" || continue
        echo true; return
    done
    echo false
}

ENTRIES=""        # carries a __main__ marker            -> must guard
LIBS=""           # named by a loader AND no __main__    -> EXEMPT (the only exemption)
UNCLASSIFIED=""   # neither                              -> must guard, AND reds on its own
MUST_GUARD=""
UNGUARDED=""
while read -r f; do
    [[ -n "$f" ]] || continue
    if grep -qF -- "$MAIN_MARK" "$ROOT/bin/$f"; then
        ENTRIES+="$f"$'\n'; MUST_GUARD+="$f"$'\n'
    elif [[ "$(_named_by_a_loader "$f")" == "true" ]]; then
        LIBS+="$f"$'\n'
    else
        UNCLASSIFIED+="$f"$'\n'; MUST_GUARD+="$f"$'\n'
    fi
done <<< "$PY_FILES"
while read -r f; do
    [[ -n "$f" ]] || continue
    grep -qxF -- "$GUARD_LINE" "$ROOT/bin/$f" || UNGUARDED+="$f "
done <<< "$MUST_GUARD"

_count() { printf '%s' "$1" | grep -c . || true; }
printf '   population: %s bin/*.py — %s entry point(s), %s exempt librar(y|ies), %s unclassified\n' \
    "$(_count "$PY_FILES")" "$(_count "$ENTRIES")" "$(_count "$LIBS")" "$(_count "$UNCLASSIFIED")"
printf '   entry points (must guard): %s\n' "$(printf '%s' "$ENTRIES" | tr '\n' ' ')"
printf '   exempt libraries:          %s\n' "$(printf '%s' "$LIBS" | tr '\n' ' ')"

# THE RULE. An empty-set assertion so the failure message names the offending files.
eq "every non-exempt bin/*.py carries the guard line (add \`$GUARD_LINE\` to it)" "" \
   "${UNGUARDED% }"

# THE CLASSIFIER'S OWN RED, and the reason there is no "partition adds up" check here: with the
# buckets defined as a total if/elif/else, `ENTRIES + LIBS + UNCLASSIFIED == PY_FILES` is an
# arithmetic identity that cannot fail, and an earlier cut shipped exactly that as if it were a
# guard. THIS is the leg that fires on a file the classifier does not recognise — a helper with
# top-level code, no `__main__` marker and no sibling naming it, which the previous cut filed as a
# LIBRARY and excused.
eq "no bin/*.py is unclassified (neither a __main__ marker nor a loader sibling names it)" "" \
   "$(printf '%s' "$UNCLASSIFIED" | tr '\n' ' ' | sed 's/ *$//')"

eq "at least one entry point exists (positive control for legs 2, 5 and 6)" "false" \
   "$([[ -z "$ENTRIES" ]] && echo true || echo false)"

# THE EXEMPTION'S PREMISE, TESTED — not assumed from the classification. A library is excused
# because a guard line inside it could not suppress its own `.pyc`: the loader writes the cache
# while it compiles, before the module body runs. Path-load each claimed library with writing
# enabled and confirm the `.pyc` appears anyway. An exempt file this does NOT hold for is not a
# library; it is a file that got out of the rule for free.
# _pyc_present is asserting PRESENCE below, so pin first that it can say "no" — otherwise a
# helper that answered true unconditionally would certify every exemption for free.
eq "_pyc_present discriminates: no cached .pyc in a freshly copied bin/ (control)" "false" \
   "$(_pyc_present "$(_fresh_bin)" "_kbc-archive-lib")"
while read -r f; do
    [[ -n "$f" ]] || continue
    libdir="$(_fresh_bin)"
    _py - "$libdir/$f" <<'PY' >/dev/null 2>&1 || true
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("premise_target", sys.argv[1])
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except Exception:
    pass
PY
    eq "$f: EXEMPTION PREMISE — a by-path load caches its .pyc regardless, so a guard line inside it could not help" \
       "true" "$(_pyc_present "$libdir" "${f%.py}")"
done <<< "$LIBS"

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

echo "== leg 3: no invocation out of bin/ writes bytecode into a directory we do not own =="
# TWO ROUTES, TWO FIXES. (a) Our own helpers reach the framework plugin through
# `_kbc-archive-lib.load_kanban_common`, which path-loads the plugin's `kanban_common.py` — closed
# in-process by the guard line, asserted below against a stub. (b) `board-session-close` hands the
# plugin's OWN `kanban-reconcile.py` to `python3`; that file `sys.path.insert`s its own directory
# and imports a sibling BY NAME, so the load caches a `.pyc` in the plugin's `hooks/bin/`
# (reproduced: `_stdio.cpython-312.pyc`). It is foreign and cannot carry the guard line, but this
# repo owns the invocation, so the fix is `PYTHONDONTWRITEBYTECODE=1` on the call.
#
# 3a derives EVERY `python3` invocation site in `bin/` and `hooks/` and requires each to resolve
# to one of the two. 3b and 3c prove each mechanism actually suppresses a write.

# _logical_lines <file> — "<first-physical-line>\t<text>", backslash continuations joined.
# Physical-line matching is what made this hard to state: `_bsc_advisory_leg`'s `python3` sits on
# a continuation line four lines below the `.py` name it is being given, so a per-line scan sees a
# bare `python3` with no target and would have to be told to ignore it.
_logical_lines() {
    awk '
    { line = $0
      if (pending) { sub(/^[[:space:]]+/, "", line); cur = cur " " line }
      else         { cur = line; start = NR }
      if (cur ~ /\\$/) { sub(/\\$/, "", cur); pending = 1; next }
      pending = 0
      print start "\t" cur }
    END { if (pending) print start "\t" cur }' "$1"
}

PY_SITES=""       # every resolved site, for the report
UNRESOLVED=""     # sites this predicate cannot dispose of -> RED
SIBLING_TGTS=""   # sibling targets, checked back against leg 1's rule
ENV_SITES=""
for src_file in "$ROOT"/bin/* "$ROOT"/hooks/*; do
    [[ -f "$src_file" ]] || continue
    case "$src_file" in *.py) continue ;; esac    # the .py helpers are leg 1's population
    rel="${src_file#"$ROOT"/}"
    while IFS=$'\t' read -r lno text; do
        # a comment line invokes nothing; `python3` must be a bare word, not part of a name
        [[ "$text" =~ ^[[:space:]]*# ]] && continue
        [[ "$text" =~ (^|[^A-Za-z0-9_/.-])python3([^A-Za-z0-9_-]|$) ]] || continue

        if [[ "$text" == *"$ENV_GUARD"* ]]; then
            PY_SITES+="$rel:$lno ENV"$'\n'; ENV_SITES+="$rel:$lno "; continue
        fi
        # a literal sibling name on the same logical line
        tgt="$(printf '%s' "$text" | grep -oE '_[A-Za-z0-9._-]+\.py' | head -1)"
        if [[ -z "$tgt" ]]; then
            # `python3 "$VAR"` — resolve VAR through its assignment anywhere in this file, the
            # same backward-resolution idiom `_selftest-prelude.sh` uses for a flag's case arm.
            var="$(printf '%s' "$text" | grep -oE 'python3[[:space:]]+"?\$\{?[A-Za-z_][A-Za-z0-9_]*' \
                   | head -1 | grep -oE '[A-Za-z_][A-Za-z0-9_]*$')"
            [[ -n "$var" ]] && tgt="$(grep -E "^[[:space:]]*(local[[:space:]]+)?$var=" "$src_file" \
                   | grep -oE '_[A-Za-z0-9._-]+\.py' | head -1)"
        fi
        if [[ -n "$tgt" && -f "$ROOT/bin/$tgt" ]]; then
            PY_SITES+="$rel:$lno SIBLING($tgt)"$'\n'; SIBLING_TGTS+="$tgt"$'\n'; continue
        fi
        PY_SITES+="$rel:$lno UNRESOLVED"$'\n'
        UNRESOLVED+="$rel:$lno "
    done < <(_logical_lines "$src_file")
done

printf '%s' "$PY_SITES" | sed 's/^/   /'
eq "the python3-invocation scan found sites at all (positive control)" "false" \
   "$([[ -z "$PY_SITES" ]] && echo true || echo false)"

# THE RULE. An UNRESOLVED site is NOT a pass: it is an invocation whose target this predicate
# cannot name, so it cannot say whether a foreign file is about to be compiled. Fix it by adding
# `PYTHONDONTWRITEBYTECODE=1` to the call, or by making the target resolvable.
eq "every python3 invocation in bin/ + hooks/ resolves to a guarded sibling or carries $ENV_GUARD" "" \
   "${UNRESOLVED% }"

# …and a sibling-resolved site only counts because leg 1's rule covers that sibling. Asserted
# here so the two legs are actually joined rather than each assuming the other.
while read -r t; do
    [[ -n "$t" ]] || continue
    eq "the sibling target $t carries the guard line (so a SIBLING disposition means something)" \
       "true" "$(grep -qxF -- "$GUARD_LINE" "$ROOT/bin/$t" && echo true || echo false)"
done <<< "$(printf '%s' "$SIBLING_TGTS" | LC_ALL=C sort -u)"

echo "-- 3b: route (a), the plugin's kanban_common.py, closed in-process by the guard line --"
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

echo "-- 3c: route (b), a FOREIGN python file, closed only by the invocation's environment --"
# A stand-in for the plugin's `kanban-reconcile.py`: it lives outside bin/, cannot be edited from
# here, and imports a sibling by name off its own directory — the shape that was writing
# `_stdio.cpython-312.pyc` into the plugin's `hooks/bin/`. The two runs differ ONLY in the
# environment the invocation passes, which is the whole claim.
#
# ⛔ BOUND, stated: this proves the MECHANISM (the env prefix is what suppresses the write) and
# 3a proves the real call site carries it. It does not run `board-session-close`'s inverse-drift
# section end to end — that needs a configured board and a live API.
foreign="$(mktemp -d "$TMP/foreign.XXXXXX")"
printf 'MARK = "ok"\n' > "$foreign/_foreignlib.py"
cat > "$foreign/foreign-hook.py" <<'PY'
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _foreignlib import MARK  # noqa: E402

sys.stdout.write(MARK)
PY
_foreign_probe() {   # _foreign_probe <env-prefixed?> — true/false: __pycache__ beside the foreign file?
    rm -rf "$foreign/__pycache__"
    if [[ "$1" == "prefixed" ]]; then
        # NOT through `_py`: that helper's whole job is `env -u PYTHONDONTWRITEBYTECODE`, which
        # would strip the very prefix under test. This is the bin's own spelling, verbatim.
        PYTHONDONTWRITEBYTECODE=1 python3 "$foreign/foreign-hook.py" >/dev/null 2>&1 || true
    else
        _py "$foreign/foreign-hook.py" >/dev/null 2>&1 || true
    fi
    [ -d "$foreign/__pycache__" ] && echo true || echo false
}
eq "PROVE-IT-CAN-FAIL — an unprefixed invocation DOES cache a .pyc in the foreign directory" \
   "true" "$(_foreign_probe bare)"
eq "…and the same invocation under $ENV_GUARD writes nothing there" \
   "false" "$(_foreign_probe prefixed)"

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
#
# ⛔ THE POPULATION THIS SPANS, named rather than left to be assumed. Under `$NO_PLUGIN` all four
# helpers stop at a usage refusal or a "primitive not found" refusal — past the load site this
# card is about, but short of any real work. So the sweep below compares REFUSAL paths, and the
# pair at the end compares a run that actually reaches the primitive and returns a decision. A
# fully-exercised comparison of the board-reading paths is out of reach offline (it needs a
# configured board and a live API) and is not claimed.
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

# …and one pair on a path that DOES the work: the stub plugin from 3b makes `_kbc-may-archive.py`
# resolve the primitive, call `may_archive` and emit a real decision line, so the byte-identical
# claim is not measured only on early exits.
_capture_working() {   # _capture_working <bin-dir> — "<rc>|<stdout+stderr>" through the stub plugin
    local out rc=0 kc
    kc="$(mktemp -d "$TMP/kcw.XXXXXX")"
    cat > "$kc/kanban_common.py" <<'PY'
def may_archive(card, resolve, surviving_cards=None):
    return (True, "stub decided")


def _derive_card_source(card):
    return None
PY
    out="$(printf '{"card":{"id":1},"surviving_cards":[],"repo":"","board_id":"12"}'         | KBCARD_KANBAN_COMMON="$kc/kanban_common.py" _py "$1/_kbc-may-archive.py" 2>&1)" || rc=$?
    printf '%s|%s' "$rc" "$out"
}
clean="$(_fresh_bin)"; mut="$(_fresh_bin)"; _strip_guard "_kbc-may-archive.py" "$mut"
working="$(_capture_working "$clean")"
eq "_kbc-may-archive.py: a WORKING invocation is byte-identical either side of the guard" \
   "$working" "$(_capture_working "$mut")"
eq "…and that invocation really reached the primitive (positive control, not a refusal)" "true" \
   "$(has "stub decided" "$working")"

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
