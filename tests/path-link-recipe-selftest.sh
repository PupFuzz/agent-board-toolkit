#!/usr/bin/env bash
# path-link-recipe-selftest.sh — the `PATH` symlink loop that `docs/INSTALL.md` §2 tells every
# consumer to paste has ONE OWNER and ONE sanctioned second copy, and BOTH are executed here
# against a fixture rather than read.
#
# WHAT IT GUARDS (card#7170). The recipe globs `bin/*` and symlinks each entry onto `PATH` with
# `ln -sf`. `ln -sf` does not REPLACE a destination that is a symlink-to-directory — it FOLLOWS it
# and creates the new link INSIDE the target, at rc 0. So a directory in `bin/` (a `__pycache__/`
# left by a python helper is the one that has really happened, and it is gitignored, so
# `git status` shows nothing) was linked onto `PATH` on the first run and, on the SECOND run,
# linked back through that `PATH` entry into the source — planting
# `bin/__pycache__/__pycache__ -> bin/__pycache__`, a symlink cycle inside the consumer's own
# checkout. Measured on a sandbox before the fix: run 1 rc 0 with `dst/__pycache__` created, run 2
# rc 0 with the cycle present. Silent on both.
#
# WHY THE TEST IS ABOUT THE DOCS AND NOT ABOUT A BIN. There is no tool to test: the recipe IS the
# product here, three lines of shell a human pastes. It stood VERBATIM in three places
# (`docs/INSTALL.md` twice, `docs/UPGRADE.md` once) plus a fourth near-copy in `VERSIONING.md`
# against a different source checkout — and every one of the four carried the defect, which is
# how three copies of one recipe always end: a correction lands on one of them. The consolidation
# is the fix, and this file is what holds it:
#   * `docs/INSTALL.md` §2 is the ONE OWNER — the block, and the prose explaining both guards.
#   * `VERSIONING.md` step 11 is the ONE sanctioned second copy. It links the release-PINNED
#     checkout, not `~/agent-board-toolkit`, so it cannot be a pointer without a by-hand
#     substitution in a deploy step. It is executed here exactly as §2's is, so the two cannot
#     drift apart in behaviour.
#   * `docs/INSTALL.md`'s worked example and `docs/UPGRADE.md` §2 now POINT at §2 and carry no
#     copy. Leg 1 is what stops a third copy quietly growing back.
#
# ⛔ NOT NARROWED TO `__pycache__`. The fixture's refused set includes an ordinarily-named
# directory and a dangling symlink alongside `__pycache__/`, because the defect is "`bin/` holds
# something that is not a regular file", not "python wrote a cache". card#6871 closed the one
# known SOURCE of such an entry (`bin/*.py` no longer mint bytecode) and card#7207 closed the
# second — CI's own syntax gate, whose `py_compile` was re-minting it on every local gate run.
# `tests/bin-artifact-hygiene-selftest.sh` and `tests/python-syntax-gate-selftest.sh` are the
# guards on that side — that `bin/` stays clean. THIS file is the other side: the recipe stays
# correct even when it is not. Neither subsumes the other, and the recipe must not depend on
# the other guard holding.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# A RECIPE LINE is a line containing `ln -s` that sits INSIDE a fenced code block of a tracked
# `*.md` file. The population is re-derived from `git ls-files` on every run — there is no list in
# this file, which is the shape that cannot go red when a doc grows a copy.
#
# The fence half is what does the discriminating: this repository's prose talks about `ln -s`
# constantly (the Windows copies-not-symlinks note, the HOOKS install narrative, a dozen CHANGELOG
# entries), and all of that is commentary, not something a reader pastes. Leg 0 proves the
# distinction is real rather than assumed, on a fixture carrying one of each.
#
# ⚠ WHAT THIS PREDICATE STRUCTURALLY CANNOT SEE — stated so a green run is not over-cited:
#   * A recipe spelled without `ln -s` at all (`cp -s`, a `find -exec`, a loop calling a helper).
#     The population is keyed on the command, so a copy that installs `PATH` entries some other
#     way is invisible here and would need its own leg.
#   * A recipe split across MULTIPLE lines. Leg 2 refuses to silently drop anything it cannot
#     run — an unrunnable member is reported UNRESOLVED and reds — so such a copy fails loudly
#     rather than passing unmeasured, but it cannot be executed as-is.
#   * A fence opened with more than three backticks, or with `~~~`. Neither is used in this tree.
#   * Anything outside tracked `*.md`. `bin/install-board-hooks` legitimately calls `ln -sf` in
#     code and is guarded by its own selftest; it is not a recipe a human pastes.
#
# THE DEFECT HAS TWO ENDS, and the fixture exercises both. The SOURCE end is what the card
# reports and `[ -f "$t" ]` closes. The DESTINATION end is the same `ln -sf` behaviour one step
# over — a `~/.local/bin/<tool>` that is itself a symlink-to-directory swallows the link, so the
# tool never reaches PATH under an install that reported success — and only `-n` closes it, so
# the fixture pre-plants exactly that (leg 3d). Both are the SAME primitive misuse; fixing one
# would have left the other live in the recipe that had just been "fixed".
#
# ⛔ ONE RESIDUAL, measured and deliberately left open: a destination that is a REAL directory
# (not a symlink to one) is still written into — `-n` is defined over symlinks, and GNU coreutils
# 9.4 answers rc 0 there with the link created inside. It needs a directory in the PATH dir named
# exactly after a toolkit tool, and it is loud at first use (a directory does not execute) rather
# than silent forever, which is why it is stated in `docs/INSTALL.md` §2 rather than guarded.
#
# HOW EVERY LEG IS SEEN TO FAIL. Legs 3a/3b/3d are assertions of ABSENCE ("no cycle was planted",
# "nothing points into a directory", "nothing was written through the destination"), which pass
# for free against a driver that never ran the recipe at all. So leg 4 runs the PRE-FIX recipe
# text through the identical driver and requires it to be caught on BOTH ends: the control is the
# defect itself, and if it comes back clean the driver — not the tree — is broken. Leg 3c pairs
# the absences with a PRESENCE witness (the exact set of tools that DID get linked, and the skip
# lines naming what did not), so "refuses the right thing" is distinguishable from "refuses
# everything".
#
# THE REFUSAL'S CHANNEL IS ASSERTED, NOT ASSUMED. `docs/INSTALL.md` §2 and the changelog both claim
# each refusal is NAMED ON STDERR. While `_probe` merged the two streams with `2>&1`, that claim was
# the one property in this file still being read rather than executed — the three skip legs passed
# identically with the notice on stdout. The streams are now captured separately and each skip is
# asserted present on fd 2 and absent from fd 1. Seen to fail: changing the recipe's `>&2` to a
# plain `echo` reds all three presence legs plus the stdout-empty leg, and reds ONLY the copy that
# was mutated. The merged-stream shape is a CLASS, filed as card#7236 — a second live instance
# stands in `tests/kbc-stale-blocker-selftest.sh`, so do not re-merge these two streams here.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
_mktmp_scratch

# The files allowed to carry a recipe line, and why each one is not a pointer. Two entries, both
# argued in the docs themselves — this is the sanctioned-copy set the consolidation established,
# and it is the one thing here that is declared rather than derived, because it IS the decision.
SANCTIONED_OWNER="docs/INSTALL.md"
SANCTIONED_SECOND="VERSIONING.md"

# _recipe_lines <repo-root> — every recipe line in the tree, as "path<TAB>lineno<TAB>text".
_recipe_lines() {
    local root="$1" f
    while IFS= read -r f; do
        awk -v F="$f" '
            /^[[:space:]]*```/ { fence = !fence; next }
            fence && /ln -s/   { printf "%s\t%d\t%s\n", F, NR, $0 }
        ' "$root/$f"
    done < <(cd "$root" && git ls-files '*.md')
}

# _fixture <dir> — a source `bin/` holding one of every shape the loop must dispose of, plus the
# destination directory, under a scratch HOME.
_fixture() {
    local d="$1"
    rm -rf "$d"; mkdir -p "$d/src/bin" "$d/home/.local/bin"
    printf '#!/bin/sh\necho a\n' > "$d/src/bin/tool-a"; chmod +x "$d/src/bin/tool-a"
    printf '# a sourced lib, not executable\n' > "$d/src/bin/_tool-lib.sh"   # regular, non-exec
    ln -s "$d/src/bin/tool-a" "$d/src/bin/alias-tool"                        # → regular file: LINK
    ln -s "$d/src/bin/nowhere" "$d/src/bin/dangling"                         # broken: SKIP
    mkdir -p "$d/src/bin/__pycache__"; printf 'x\n' > "$d/src/bin/__pycache__/some.pyc"
    mkdir -p "$d/src/bin/helpers";     printf 'x\n' > "$d/src/bin/helpers/inner"
    # THE DESTINATION END, which the source filter cannot reach and only `-n` closes: a PATH entry
    # standing where a tool goes, that is a SYMLINK TO A DIRECTORY. `ln -sf` follows it and writes
    # the link inside, at rc 0, leaving the tool off PATH under a clean-looking install.
    mkdir -p "$d/stray-dir"
    ln -s "$d/stray-dir" "$d/home/.local/bin/tool-a"
}

# _runnable <text> — the recipe rewritten to point at the fixture, or "" if the shape is one this
# driver cannot execute. Only the SOURCE glob is substituted (structurally, on the `for … in …; do`
# header, never on a spelling of the path); the destination is reached by overriding HOME, so the
# `~/.local/bin/` half of the line under test runs exactly as written.
_runnable() {
    local text="$1" prog
    prog="$(printf '%s\n' "$text" | sed -E 's|for ([A-Za-z_][A-Za-z0-9_]*) in [^;]*; do|for \1 in "$SRCBIN"/*; do|')"
    # The rewrite MUST have applied. A sed that matched nothing returns its input unchanged, which
    # would run the recipe against the maintainer's REAL `~/agent-board-toolkit` and report on it.
    [[ "$prog" == *'"$SRCBIN"/*'* ]] || { printf '%s' ""; return; }
    printf '%s' "$prog"
}

# _probe <fixture-dir> <recipe-text> — run the recipe TWICE and print the three measurements the
# assertions are made on. Two runs, because the cycle only appears on the second.
_probe() {
    local d="$1" text="$2" prog n
    prog="$(_runnable "$text")"
    # THE TWO STREAMS ARE KEPT APART, deliberately. They used to be merged (`2>&1`) into one log,
    # and under a merge the three skip legs below pass IDENTICALLY whether the refusal goes to
    # stdout or to stderr — so "each refusal is NAMED on stderr", the property `docs/INSTALL.md`
    # §2 and the changelog both assert, was the one thing here still being READ rather than run.
    # Separate files make the CHANNEL assertable: presence on fd 2, absence on fd 1.
    : > "$d/stderr.log"; : > "$d/stdout.log"
    for n in 1 2; do
        ( export HOME="$d/home" SRCBIN="$d/src/bin"; cd "$d" && bash -c "$prog" ) \
            >>"$d/stdout.log" 2>>"$d/stderr.log"
    done
    # 1. anything the run planted INSIDE the source checkout, over the fixture's own two symlinks.
    printf 'PLANTED=%s\n' "$(cd "$d/src" && find . -type l -printf '%p\n' 2>/dev/null \
        | LC_ALL=C sort | LC_ALL=C comm -13 <(printf './bin/alias-tool\n./bin/dangling\n') - | tr '\n' ' ')"
    # 2. destination entries that resolve to a DIRECTORY — a `PATH` entry that is not a tool.
    printf 'DIRDEST=%s\n' "$(find "$d/home/.local/bin" -mindepth 1 -maxdepth 1 \
        -exec bash -c '[ -d "$(readlink -f "$1")" ] && basename "$1"' _ {} \; 2>/dev/null \
        | LC_ALL=C sort | tr '\n' ' ')"
    # 3. destination entries that are symlinks resolving to a regular file — the tools installed.
    printf 'LINKED=%s\n' "$(find "$d/home/.local/bin" -mindepth 1 -maxdepth 1 -type l \
        -exec bash -c '[ -f "$(readlink -f "$1")" ] && basename "$1"' _ {} \; 2>/dev/null \
        | LC_ALL=C sort | tr '\n' ' ')"
    # 4. the destination end: what the pre-planted symlink-to-directory now points at, and
    #    whether anything was written through it into the directory it named.
    printf 'STRAYTGT=%s\n' "$(readlink -f "$d/home/.local/bin/tool-a" 2>/dev/null)"
    printf 'STRAYIN=%s\n' "$(find "$d/stray-dir" -mindepth 1 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
}

_field() { printf '%s\n' "$2" | sed -n "s/^$1=//p"; }

echo "== leg 0: the derivation runs, and the fence predicate discriminates =="

POP="$(_recipe_lines "$ROOT")"
eq "the recipe population is non-empty (a zero-member population measures nothing)" "false" \
   "$([[ -z "$POP" ]] && echo true || echo false)"
eq "the owner's copy is in the population" "true" \
   "$(has "$SANCTIONED_OWNER"$'\t' "$POP")"
eq "the sanctioned second copy is in the population" "true" \
   "$(has "$SANCTIONED_SECOND"$'\t' "$POP")"

# CONTROL for the predicate itself: a throwaway repo carrying one fenced recipe and one prose
# mention of `ln -s`. Without this, "prose is excluded" is an assumption, and a scanner that
# matched nothing at all would satisfy every absence leg below.
CTL="$TMP/predicate-control"
mkdir -p "$CTL" && ( cd "$CTL" && git init -q . )
{ echo 'Prose about `ln -s` that nobody pastes, mentioning ~/.local/bin for good measure.'
  echo '```bash'
  echo 'for t in /some/where/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done'
  echo '```'
  echo 'More prose: `ln -s` again, outside any fence.'; } > "$CTL/doc.md"
( cd "$CTL" && git add doc.md >/dev/null 2>&1 )
CTLPOP="$(_recipe_lines "$CTL")"
eq "control: the fenced recipe is found (1 member)" "1" "$(printf '%s\n' "$CTLPOP" | awk 'NF' | wc -l | tr -d ' ')"
eq "control: neither prose mention is picked up" "false" "$(has 'Prose about' "$CTLPOP")"

echo "== leg 1: no THIRD copy — every member sits in a sanctioned file =="

STRAY="$(printf '%s\n' "$POP" | awk -F'\t' -v a="$SANCTIONED_OWNER" -v b="$SANCTIONED_SECOND" \
    'NF && $1 != a && $1 != b { printf "%s:%s\n", $1, $2 }')"
eq "a recipe copy outside docs/INSTALL.md + VERSIONING.md (point it at INSTALL §2 instead)" "" "$STRAY"
eq "docs/INSTALL.md carries exactly ONE copy (the §2 owner; the worked example points at it)" "1" \
   "$(printf '%s\n' "$POP" | awk -F'\t' -v a="$SANCTIONED_OWNER" '$1 == a' | wc -l | tr -d ' ')"
eq "VERSIONING.md carries exactly ONE copy (the release-pin deploy step)" "1" \
   "$(printf '%s\n' "$POP" | awk -F'\t' -v b="$SANCTIONED_SECOND" '$1 == b' | wc -l | tr -d ' ')"

echo "== leg 2: every member is RUNNABLE by this driver (an unrunnable one reds) =="

UNRESOLVED=""
while IFS=$'\t' read -r f n text; do
    [[ -n "${f:-}" ]] || continue
    [[ -n "$(_runnable "$text")" ]] || UNRESOLVED+="$f:$n "
done <<< "$POP"
eq "UNRESOLVED member (this driver cannot execute it, so nothing below measured it)" "" "$UNRESOLVED"

echo "== leg 3: each copy, executed twice against a fixture bin/ =="

while IFS=$'\t' read -r f n text; do
    [[ -n "${f:-}" ]] || continue
    D="$TMP/run-$(echo "$f:$n" | tr '/:.' '___')"
    _fixture "$D"
    OUT="$(_probe "$D" "$text")"
    # 3a POSITIVE — the reported defect: nothing new inside the consumer's own checkout.
    eq "$f:$n — nothing planted inside the source checkout after two runs" "" "$(_field PLANTED "$OUT")"
    # 3b POSITIVE — and no PATH entry pointing at a directory (run 1's half of the defect).
    eq "$f:$n — no destination entry resolves to a directory" "" "$(_field DIRDEST "$OUT")"
    # 3c NEGATIVE + WITNESS — it skips the right things and ONLY those. A fix that skipped
    # everything would satisfy 3a and 3b perfectly.
    eq "$f:$n — every regular-file tool is linked, and nothing else" "_tool-lib.sh alias-tool tool-a " \
       "$(_field LINKED "$OUT")"
    # The refusals are asserted ON FD 2 — the channel is part of the claim, not incidental. A
    # recipe that announced them on stdout would satisfy "not silent" and still break the stated
    # contract (and pollute a caller that pipes the loop), so each presence on stderr is paired
    # with the matching ABSENCE on stdout below.
    eq "$f:$n — the skip of __pycache__ is announced on STDERR, not silent" "true" \
       "$(has '__pycache__' "$(cat "$D/stderr.log")")"
    eq "$f:$n — an ordinarily-named directory is refused too, on STDERR (not narrowed to __pycache__)" "true" \
       "$(has 'helpers' "$(cat "$D/stderr.log")")"
    eq "$f:$n — a dangling symlink is refused, on STDERR" "true" "$(has 'dangling' "$(cat "$D/stderr.log")")"
    # The discriminating half: NOTHING the loop refuses may land on stdout. Asserted over the
    # whole stream rather than per-name — the loop writes nothing at all to fd 1, so any content
    # here is either a misrouted refusal or new output nobody declared.
    eq "$f:$n — the loop writes NOTHING to stdout (every refusal is on fd 2)" "" \
       "$(tr -d '[:space:]' < "$D/stdout.log")"
    # 3d — the destination end (`-n`): the pre-planted symlink-to-directory is REPLACED by the
    # tool, and nothing was written through it into the directory it pointed at.
    eq "$f:$n — a symlink-to-directory destination is replaced by the tool, not followed" \
       "$D/src/bin/tool-a" "$(_field STRAYTGT "$OUT")"
    eq "$f:$n — nothing was written into the directory that destination pointed at" "" "$(_field STRAYIN "$OUT")"
done <<< "$POP"

echo "== leg 4: CONTROL — the pre-fix recipe must be CAUGHT by the legs above =="

# Verbatim what `docs/INSTALL.md` §2 carried before card#7170. If this comes back clean, the
# driver is measuring nothing and every green tick above is worthless.
PREFIX_RECIPE='for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done'
DC="$TMP/control-prefix"
_fixture "$DC"
COUT="$(_probe "$DC" "$PREFIX_RECIPE")"
eq "control: the unguarded recipe DOES plant a symlink inside the checkout" "false" \
   "$([[ -z "$(_field PLANTED "$COUT")" ]] && echo true || echo false)"
eq "control: the unguarded recipe DOES leave a destination entry resolving to a directory" "false" \
   "$([[ -z "$(_field DIRDEST "$COUT")" ]] && echo true || echo false)"
eq "control: the planted entry is the self-referential one the card reports" "true" \
   "$(has './bin/__pycache__/__pycache__' "$(_field PLANTED "$COUT")")"
# ...and the destination end, which only `-n` closes: without it the tool is written INSIDE the
# symlinked directory and never reaches PATH. Without this pair, leg 3d could pass on a driver
# that never planted the stray destination.
eq "control: without -n the tool is written INTO the symlinked directory instead of onto PATH" "false" \
   "$([[ -z "$(_field STRAYIN "$COUT")" ]] && echo true || echo false)"
eq "control: without -n the destination still points at the stray directory" "$DC/stray-dir" \
   "$(_field STRAYTGT "$COUT")"

_summary "path-link-recipe-selftest"
