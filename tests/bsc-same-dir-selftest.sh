#!/usr/bin/env bash
# bsc-same-dir-selftest.sh — the path-identity surface of board-session-close: `_bsc_same_dir`
# and the `_bsc_canon` it falls back to. Its own file rather than a seventh block in
# board-session-close-selftest.sh: nothing here needs that suite's git fixture repos, and this
# fixture (a chmod-000 directory, a symlink cycle, a 45-hop dangling chain, a newline in a
# component name) is built and torn down on terms of its own.
#
# WHAT IT GUARDS. `_bsc_same_dir` decides whether two path SPELLINGS name one directory. It used
# to answer with `readlink -m`, a GNU coreutils extension, behind a `|| <the raw path>` fallback —
# so on macOS/BSD/busybox the comparison silently became a string compare, which is the defect
# the function exists to prevent (a symlinked repo path or a trailing slash then read as "your
# .git is a file", asserting a falsehood about an ordinary checkout and withholding the command
# that works). The answer is now `-ef` where both paths exist and `_bsc_canon` where one does not.
#
# Four groups, in this order:
#   1. THE VERDICT PROPERTY CORPUS — spelling pairs with ground-truth verdicts. This is the
#      contract; every other group exists to keep it honest. Each pair is asserted in both
#      argument orders (identity is symmetric).
#   2. BRANCH CONSISTENCY — folded into group 1's pass rather than restating its population: for
#      every corpus pair whose two sides both EXIST, `_bsc_canon(a) == _bsc_canon(b)` must agree
#      with `a -ef b`, so the two branches cannot drift apart.
#   3. DIFFERENTIAL vs `readlink -m` — the oracle, demoted from runtime dependency to test tool.
#      Runs only where the oracle exists (GNU). Inputs where `_bsc_canon` KNOWINGLY departs from
#      it are listed explicitly with their reason, never quietly excluded, and the differential is
#      seen to fail: a deliberately-lexical canon fed the `..`-through-symlink case must diverge.
#   4. THE BSD SIMULATION — the whole corpus again with a PATH-front `readlink` that errors on
#      `-m` and delegates everything else. Pre-change, that stub reds 9 of the 11 pairs it was
#      first run against (recorded on card#5281); the permanent guard against reintroduction is
#      the source assertion at the end, which fails on any non-comment `readlink -m` in the bin.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/board-session-close"
_need -r "$BIN"

_mktmp_scratch          # TMP + EXIT-cleanup trap
# The fixture holds a mode-000 directory, which plain `rm -rf` cannot descend into (measured:
# "Permission denied", tree left behind). The mode is restored at the end of the chmod-000 block
# too; this trap covers the paths that never reach it.
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
UB="/usr/bin:/bin"

# shellcheck source=/dev/null
source "$BIN"           # main-guarded: defines the _bsc_* helpers, runs nothing

# ---------------------------------------------------------------------------
# Fixture — the shapes the two branches are made of.
# ---------------------------------------------------------------------------
L="$TMP/lab"
NL=$'\n'
mkdir -p "$L/base/real" "$L/base/other/dir" "$L/base/deep/a/b" "$L/priv/inner" \
         "$L/base/na${NL}me" "$L/base/name" "$L/dang"
ln -s "$L/base/other/dir" "$L/base/L"        # absolute symlink to a directory
ln -s real                "$L/base/L2"       # relative symlink to a directory
ln -s "$L/priv"           "$L/base/PL"       # symlink to the unreadable directory
ln -s /nowhere/gone       "$L/base/DANGLE"   # dangling symlink
ln -s loopY "$L/loopX"; ln -s loopZ "$L/loopY"; ln -s loopX "$L/loopZ"   # a 3-cycle
# A dangling chain LONGER than the 40-hop budget: the kernel never resolves it (so `cd -P` cannot
# short-circuit it) and each hop costs one unit, which is the only way to reach exhaustion.
ln -s /nowhere/gone "$L/dang/d44"
for _i in $(seq 43 -1 0); do ln -s "d$((_i + 1))" "$L/dang/d$_i"; done
chmod 000 "$L/priv"

AS_ROOT=false; [[ "$(id -u)" == "0" ]] && AS_ROOT=true

# ---------------------------------------------------------------------------
# Invokers — the corpus is run twice, against the same pairs, through these.
# ---------------------------------------------------------------------------
sd_direct() { _bsc_same_dir "$1" "$2"; }
STUB="$TMP/bsdbin"                       # populated in group 4
sd_stub() {
    PATH="$STUB:$UB" bash -c 'source "$1" >/dev/null 2>&1; _bsc_same_dir "$2" "$3"' _ "$BIN" "$1" "$2"
}
INVOKE=sd_direct
BRANCH_CHECK=1          # group 2 rides group 1's pass; the stub pass repeats verdicts only

# vcase <label> <expected-rc> <a> <b> — one corpus pair.
vcase() {
    local label="$1" want="$2" a="$3" b="$4" got=0 rev=0 ef=1 ce=1
    "$INVOKE" "$a" "$b" || got=$?
    eq "$label" "$want" "$got"
    "$INVOKE" "$b" "$a" || rev=$?
    eq "$label — same answer with the arguments swapped" "$want" "$rev"
    if [[ "$BRANCH_CHECK" == 1 && -e "$a" && -e "$b" ]]; then
        # Group 2: this pair rides the -ef branch, so the canon branch is exercised on it here
        # and the two answers must match. A pair only one branch has ever seen is a pair the two
        # branches are free to disagree about.
        [[ "$a" -ef "$b" ]] && ef=0
        [[ "$(_bsc_canon "$a")" == "$(_bsc_canon "$b")" ]] && ce=0
        eq "branch consistency [$label]: _bsc_canon equality tracks -ef" "$ef" "$ce"
    fi
}

# corpus — every pair, run through $INVOKE. Called once per invoker.
corpus() {
    vcase "an absolute symlink to a dir vs the dir"        0 "$L/base/L"    "$L/base/other/dir"
    vcase "a relative symlink to a dir vs the dir"         0 "$L/base/L2"   "$L/base/real"
    vcase "a trailing slash"                               0 "$L/base/real/" "$L/base/real"
    vcase "a repeated slash"                               0 "$L/base//real" "$L/base/real"
    vcase "a sub-directory is NOT its root"                1 "$L/base/real" "$L/base"
    vcase "two different real dirs"                        1 "$L/base/real" "$L/base/other/dir"
    vcase ".. through a symlink lands in the TARGET's parent" 0 "$L/base/L/.." "$L/base/other"
    vcase ".. through real dirs"                           0 "$L/base/deep/a/b/../.." "$L/base/deep"
    vcase "the same missing tail, spelled identically"     0 "$L/base/real/nope" "$L/base/real/nope"
    vcase "a missing tail under a symlink vs under the target" \
                                                           0 "$L/base/L/nope" "$L/base/other/dir/nope"
    vcase "two different missing tails under one parent"   1 "$L/base/real/nope" "$L/base/real/nada"
    vcase "a missing dir is not its own missing child"     1 "$L/base/missing" "$L/base/missing/deeper"
    vcase "a path that exists nowhere, two spellings"      0 /nowhere/a/b /nowhere/a/b/
    # ACCEPTANCE CASES — the four the reviewer measured a purely-lexical tail collapse getting
    # wrong. Each is a WRONG VERDICT, not a cosmetic difference: every one of them answered
    # "different directories" about one directory.
    vcase "ACCEPTANCE 1: a MISSING component then .. then a symlink, vs the symlink's target" \
                                                           0 "$L/base/missing/../L" "$L/base/other/dir"
    vcase "ACCEPTANCE 2: a dangling symlink vs the target it names" \
                                                           0 "$L/base/DANGLE" /nowhere/gone
    vcase "ACCEPTANCE 2b: a path UNDER a dangling symlink" 0 "$L/base/DANGLE/x" /nowhere/gone/x
    if $AS_ROOT; then
        # SKIPPED AS ROOT, and stated rather than silently dropped: root traverses a mode-000
        # directory, so `-e` succeeds, the pair rides the -ef branch, and the case would assert
        # something other than the EACCES behaviour it exists for. CI runners are non-root.
        echo "  skip (running as root: a mode-000 directory does not deny root, so acceptance 3-4 would test a different scenario)"
    else
        vcase "ACCEPTANCE 3: a symlink to an unreadable dir vs the dir" 0 "$L/base/PL" "$L/priv"
        vcase "ACCEPTANCE 4: a path UNDER a symlink to an unreadable dir" \
                                                           0 "$L/base/PL/inner" "$L/priv/inner"
    fi
    vcase "a newline inside a component name"              0 "$L/base/na${NL}me/" "$L/base/na${NL}me"
    vcase "…and it is not collapsed onto the newline-less sibling" \
                                                           1 "$L/base/na${NL}me" "$L/base/name"
    # The two inputs where _bsc_canon knowingly departs from `readlink -m` (group 3 pins both):
    # the VERDICT is still right, because both spellings run the same code.
    vcase "a symlink cycle: two spellings still compare equal" 0 "$L/loopX" "$L/loopX/"
    vcase "a dangling chain past the hop budget: two spellings still compare equal" \
                                                           0 "$L/dang/d0" "$L/dang/d0/"
    vcase "an EMPTY argument is never equal to anything"    1 "" "$L/base/real"
}

# ---------------------------------------------------------------------------
echo "== the fixture denies what it claims to deny (witnesses for the cases below) =="
eq "the symlink-to-dir really is a symlink" "true" \
   "$([[ -L "$L/base/L" ]] && echo true || echo false)"
eq "the dangling symlink really dangles"    "true" \
   "$([[ -L "$L/base/DANGLE" && ! -e "$L/base/DANGLE" ]] && echo true || echo false)"
if $AS_ROOT; then
    echo "  skip (running as root: the mode-000 witness cannot hold)"
else
    eq "the mode-000 dir denies traversal, so its child is unstatable (acceptance 3-4's premise)" \
       "false" "$([[ -e "$L/base/PL/inner" ]] && echo true || echo false)"
fi

echo "== verdict corpus (+ branch consistency) =="
corpus

# ---------------------------------------------------------------------------
# Group 3 — the differential against the GNU oracle.
# ---------------------------------------------------------------------------
# _bsc_canon_lexical — the WRONG implementation, kept only as group 3's discriminating control:
# a pure lexical collapse, which is what the substitute for `readlink -m` must NOT be (#180).
_bsc_canon_lexical() {
    local rest="$1" resolved="" seg
    while [[ -n "$rest" ]]; do
        while [[ "$rest" == /* ]]; do rest="${rest#/}"; done
        [[ -n "$rest" ]] || break
        seg="${rest%%/*}"
        if [[ "$seg" == "$rest" ]]; then rest=""; else rest="${rest#*/}"; fi
        case "$seg" in ''|.) continue ;; ..) resolved="${resolved%/*}"; continue ;; esac
        resolved="$resolved/$seg"
    done
    printf '%s' "${resolved:-/}"
}

# _diff_row <canon-fn> <path> — "same", or "<canon output>|<oracle output>" when they differ.
_diff_row() {
    local got ora
    got="$("$1" "$2")"
    ora="$(readlink -m -- "$2")"
    [[ "$got" == "$ora" ]] && printf 'same' || printf '%s|%s' "$got" "$ora"
}

echo "== differential vs \`readlink -m\` =="
if ! readlink -m -- / >/dev/null 2>&1; then
    echo "  skip (no \`readlink -m\` on this host — the oracle is GNU-only, which is the whole point)"
else
    for p in "$L/base/real" "$L/base/real/" "$L/base//real" "$L/base/L" "$L/base/L2" \
             "$L/base/L/.." "$L/base/deep/a/b/../.." "$L/base/real/nope" "$L/base/L/nope" \
             "$L/base/missing/../L" "$L/base/missing/deeper" "$L/base/DANGLE" "$L/base/DANGLE/x" \
             "$L/base/PL" "$L/base/PL/inner" "$L/priv/inner" "$L/base/na${NL}me" \
             "$L/base/L/../.." /nowhere/gone/x /; do
        eq "agrees with the oracle: ${p#"$L/"}" "same" "$(_diff_row _bsc_canon "$p")"
    done

    # PINNED DEPARTURES — listed, with the reason, rather than dropped from the loop above.
    # (a) Leading `//`. POSIX leaves a path beginning with exactly two slashes
    #     implementation-defined; `_bsc_canon` normalises it to one. GNU on glibc measurably does
    #     the same today, so this is pinned as OUR output rather than as a difference — a host
    #     whose `-m` keeps `//` is not a defect here, and both compared spellings normalise
    #     identically, so no verdict can turn on it.
    eq "pinned: leading // normalises to one slash"     "$L/base/real" "$(_bsc_canon "//$L/base/real")"
    eq "pinned: // alone is the root"                   "/"            "$(_bsc_canon //)"
    # (b) Symlink-budget exhaustion. Past 40 hops `_bsc_canon` stops resolving and appends the
    #     remainder lexically; `-m` answers with a hop of its own choosing. Both outputs are
    #     arbitrary, and asserting the DIFFERENCE (not just our value) is what keeps this pinned
    #     to a measured fact — if the oracle ever agrees, this reds and the pin gets re-derived
    #     rather than quietly rotting.
    eq "pinned: a 3-cycle stops on OUR hop"             "$L/loopY"     "$(_bsc_canon "$L/loopX")"
    eq "…and that is a real departure from the oracle"  "false" \
       "$([[ "$(_diff_row _bsc_canon "$L/loopX")" == same ]] && echo true || echo false)"
    eq "pinned: a dangling chain stops at hop 40"       "$L/dang/d40"  "$(_bsc_canon "$L/dang/d0")"
    eq "…and that is a real departure from the oracle"  "false" \
       "$([[ "$(_diff_row _bsc_canon "$L/dang/d0")" == same ]] && echo true || echo false)"

    # THE DISCRIMINATING CONTROL (canon #9). Every agreement above is worthless if the comparison
    # cannot report a disagreement. A purely-lexical canon — the substitute this design refused —
    # pops the symlink itself instead of resolving it, and the row must show that, exactly.
    eq "control: a purely-lexical canon DIVERGES on ..-through-a-symlink (the differential can fail)" \
       "$L/base|$L/base/other" "$(_diff_row _bsc_canon_lexical "$L/base/L/..")"
    eq "control: …and it also diverges on ACCEPTANCE 1" \
       "$L/base/L|$L/base/other/dir" "$(_diff_row _bsc_canon_lexical "$L/base/missing/../L")"
fi

# ---------------------------------------------------------------------------
# Group 4 — the BSD/busybox simulation.
# ---------------------------------------------------------------------------
echo "== BSD-simulation \`readlink\` (no -m) — fixture =="
mkdir -p "$STUB"
REAL_READLINK="$(command -v readlink)"
_need -x "$REAL_READLINK" "readlink"
cat > "$STUB/readlink" <<EOF
#!/bin/sh
# Errors on -m the way a BSD/busybox readlink does; everything else is the real tool.
case "\$1" in
  -m|--canonicalize-missing) echo "readlink: illegal option -- m" >&2; exit 1 ;;
esac
exec "$REAL_READLINK" "\$@"
EOF
chmod +x "$STUB/readlink"

eq "positive control: the stub PATH genuinely has no working \`readlink -m\`" "false" \
   "$(PATH="$STUB:$UB" bash -c 'readlink -m -- / >/dev/null 2>&1' && echo true || echo false)"
eq "…while a flagless read still delegates to the real tool (the stub is not just broken)" \
   "$(readlink "$L/base/L")" \
   "$(PATH="$STUB:$UB" bash -c 'readlink "$1"' _ "$L/base/L")"
eq "…and so does -f" "$(readlink -f "$L/base/L")" \
   "$(PATH="$STUB:$UB" bash -c 'readlink -f "$1"' _ "$L/base/L")"

echo "== the whole verdict corpus again, on a host with no \`readlink -m\` =="
INVOKE=sd_stub
BRANCH_CHECK=0          # the -ef/-canon agreement is a property of the code, not of the PATH
corpus
INVOKE=sd_direct
BRANCH_CHECK=1

# ---------------------------------------------------------------------------
# The PERMANENT can-fail guard. The stub run above passes today because the bin no longer calls
# `readlink -m`; it would pass again for a reintroduction that kept a `|| <raw path>` fallback on
# some other line, because a fallback's whole nature is to answer anyway. So the reintroduction
# itself is what is asserted against, in the source — the same shape as the suite's other source
# checks (`grep -qF 'BSC_ADVISORY_TIMEOUT:-60'`).
# ---------------------------------------------------------------------------
echo "== the bin carries no non-comment \`readlink -m\` =="
# _rl_m_hits <file> — `path:lineno:` hits for a -m-bearing readlink call, comment lines dropped.
_rl_m_hits() {
    grep -HnE 'readlink[[:space:]]+(-[a-zA-Z]*m\b|--canonicalize-missing)' "$1" 2>/dev/null \
    | while IFS= read -r hit; do
        content="${hit#*:}"; content="${content#*:}"          # strip `path:` then `lineno:`
        trimmed="${content#"${content%%[![:space:]]*}"}"      # left-trim whitespace
        [[ "$trimmed" == \#* ]] && continue                   # drop comment lines
        printf '%s\n' "$hit"
      done || true
    return 0
}
eq "no non-comment \`readlink -m\` in bin/board-session-close" "" "$(_rl_m_hits "$BIN")"
# The scanner must be able to SEE one. Both shapes in one fixture: a live call (which must be
# reported) and the commented mention the bin genuinely carries (which must not be).
FIX="$TMP/rlm-fixture"
{
    printf '%s\n' '# `readlink -m` is not used at runtime — this line is a comment and must not hit'
    printf '%s\n' '  p="$(readlink -m -- "$1" 2>/dev/null || printf %s "$1")"'
    printf '%s\n' '  q="$(readlink -f -- "$1")"   # -f is not the extension in question'
} > "$FIX"
eq "positive control: a live \`readlink -m\` call IS reported" "1" \
   "$(_rl_m_hits "$FIX" | grep -c ':2:' || true)"
eq "…and exactly that one line (the comment and the -f call are not hits)" "1" \
   "$(_rl_m_hits "$FIX" | grep -c . || true)"

chmod 755 "$L/priv"     # let the harness's own cleanup descend

# ⛔⛔ DELIBERATE, TEMPORARY BREAKAGE — card#8261 fail-first evidence ONLY (canon #9).
# `ci-gate` is about to become this repository's single required status context, and an
# aggregator that has only ever been observed GREEN is a decoration. This planted failure exists
# to watch a red matrix leg actually turn `ci-gate` RED on a real runner. REVERTED in the very
# next commit; if you are reading this on any branch, it escaped and must be removed.
bad "DELIBERATE card#8261 fail-first probe — this assertion is planted and must be reverted"

_summary "bsc-same-dir-selftest"
