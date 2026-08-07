#!/usr/bin/env bash
# drift-check-fixture-selftest.sh — exercise `agent-board-toolkit-drift-check` against REAL
# fixture repos, so each of its three legs is observed both FIRING and staying silent.
#
# WHY THIS FILE EXISTS. The tool's only CI exercise was the `drift-check-selftest` job's
# `./bin/agent-board-toolkit-drift-check . .` — TOOLKIT and REPO the same directory. Two of its
# three legs cannot fail in that shape (card#5356, measured):
#   * CONTENT-DRIFT `diff -q "$TOOLKIT/bin/$name" "$REPO/bin/$name"` compares every file to
#                   ITSELF. It can never report drift. Dead.
#   * VERSION-SKEW  is gated on `[ -f "$REPO/.agent-board-toolkit-version" ]` and the toolkit
#                   root carries no such file, so the whole block is skipped. Dead.
#   * MISSING-LIB   IS live there: it asserts the shipped tree still carries
#                   `bin/_kb-board-lib.sh` beside its sourcers.
# So the green tick on that job certifies exactly one thing. This file supplies the two dead
# legs with fixtures that can fail, and re-checks the third away from the shipped tree.
#
# IT ADDS A JOB, IT DOES NOT REPLACE ONE. The self-run stays: its MISSING-LIB leg is the only
# assertion anywhere that the SHIPPED tree carries the lib, and a temp-dir fixture cannot make
# that claim. Deleting the self-run in favour of this file would trade a narrow live check for
# no check at all.
#
# NAMING. This is `drift-check-FIXTURE-selftest`, deliberately not `drift-check-selftest`: the
# CI job of that name is the self-run and executes no `tests/` file, so a file with the
# matching name would read as that job's script and is not. The JOB is what keeps its name —
# it is a required status check on `main`, so renaming it would leave that required context
# permanently unreported and every release PR sitting on a check that can never be satisfied
# (the same reason the #137 CI dedup renamed no required check).
#
# THE BIN HAS NO MAIN-GUARD, so it is exercised as a PROCESS. Sourcing it would run its
# argument guards and `exit` inside this shell.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that on
# temp-dir fixtures, each leg reports its own defect by name and exits 1, and that a clean
# co-vendored fixture exits 0 silently. It says nothing about the shipped tree (the self-run
# owns that), nothing about any real consumer repo, and nothing about whether a consumer's CI
# invokes the tool at all.
#
# EVERY rc-0/"not named" ASSERTION BELOW IS AN ASSERTION OF ABSENCE, and drift-check answers OK
# vacuously for a repo that vendors nothing — so an empty or mis-built fixture would pass every
# one of them. Each is therefore paired with a mutation of the SAME directory whose message is
# observed PRESENT. The pairing is the point; read the two assertions together or neither means
# anything.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

TOOLKIT="$(cd "$HERE/.." && pwd)"
DRIFT="$TOOLKIT/bin/agent-board-toolkit-drift-check"
SOURCER="kbcard"                      # a lib-sourcing bin
STANDALONE="promote-released-cards"   # the documented standalone exception
_need -x "$DRIFT"
_need -r "$TOOLKIT/bin/_kb-board-lib.sh"
_need -r "$TOOLKIT/bin/$SOURCER"
_need -r "$TOOLKIT/bin/$STANDALONE"
_need -r "$TOOLKIT/VERSION"
_mktmp_scratch

WANT="$(cat "$TOOLKIT/VERSION")"

# _run <repo-dir> — run drift-check as a process against the real toolkit; sets RC/OUT/ERR.
# Globals on purpose: every case reads all three.
_run() {
    RC=0
    OUT="$("$DRIFT" "$TOOLKIT" "$1" 2>"$TMP/stderr")" || RC=$?
    ERR="$(cat "$TMP/stderr")"
}

# _vendor <dir> <tool>... — a fixture repo whose bin/ holds verbatim toolkit copies.
_vendor() {
    local d="$1" t; shift
    mkdir -p "$d/bin"
    for t in "$@"; do cp "$TOOLKIT/bin/$t" "$d/bin/$t"; done
}

# ---------------------------------------------------------------------------
# Premises. Both fixtures below are built on which bins do and do not source the lib. If that
# ever changes, the MISSING-LIB cases would keep passing while testing nothing — so the
# premises are asserted rather than assumed, against the same anchored pattern the tool uses.
# ---------------------------------------------------------------------------
echo "== premises: the fixture bins are the shapes this test needs them to be =="
_sources_lib() { grep -qE '^[[:space:]]*source "\$KB_LIB"' "$TOOLKIT/bin/$1" && echo true || echo false; }
eq "premise: bin/$SOURCER sources the lib (what the MISSING-LIB probe triggers on)" \
   "true" "$(_sources_lib "$SOURCER")"
eq "premise: bin/$STANDALONE does not source the lib (the documented exception)" \
   "false" "$(_sources_lib "$STANDALONE")"

# ---------------------------------------------------------------------------
# Bad invocation — the documented rc 2 contract.
# ---------------------------------------------------------------------------
echo "== bad invocation exits 2 =="
# _bad <label> <expected-stderr-substring> [argv...] — assert BOTH the rc and the message.
# rc ALONE CANNOT DISCRIMINATE HERE: every argument-shape below exits 2, so an rc-only
# assertion passes just as well when the refusal came from the wrong guard, or from a guard
# that named nothing. The message is the only part that distinguishes them, which is why the
# empty-argument cases stayed anonymous under a green suite from v0.1.0 until card#5429.
_bad() {
    local label="$1" want="$2"; shift 2
    local rc=0
    "$DRIFT" "$@" >/dev/null 2>"$TMP/stderr" || rc=$?
    eq "$label: rc 2" "2" "$rc"
    eq "$label: says '$want'" "true" "$(has "$want" "$(cat "$TMP/stderr")")"
}

USAGE="usage: agent-board-toolkit-drift-check <toolkit-dir> <repo-dir>"
_bad "no arguments" "$USAGE"
_bad "one argument" "$USAGE" "$TOOLKIT"

# An ABSENT argument is a usage error; an argument explicitly PRESENT and empty is the
# unexpanded-variable hazard, and must name WHICH slot — with two positionals a bare usage line
# leaves the caller to guess. Both slots are covered because a guard naming only the first would
# satisfy a single-slot test.
_bad "empty toolkit dir" "<toolkit-dir> is empty (an unexpanded variable?)" "" "$TMP"
_bad "empty repo dir" "<repo-dir> is empty (an unexpanded variable?)" "$TOOLKIT" ""
_bad "both empty: reports the FIRST" "<toolkit-dir> is empty" "" ""

# A third positional is REFUSED, not discarded. This tool is the drift GATE: silently dropping
# `--some-flag` and reporting OK is a green report about something other than what was asked for.
_bad "extra positional" "unexpected extra argument: IGNORED-THIRD" "$TOOLKIT" "$TMP" "IGNORED-THIRD"
_bad "extra positional, empty" "unexpected extra argument: (empty" "$TOOLKIT" "$TMP" ""
_bad "two extra positionals" "unexpected extra argument: c" "$TOOLKIT" "$TMP" "c" "d"
# Ordering: an empty slot AND an extra argument in one call reports the EMPTY. Not cosmetic —
# the empty slot is the unexpanded-variable diagnosis, and it is also the ordering the shared
# primitive documents. Nothing else in this file can observe which of the two guards runs first.
_bad "empty slot + extra: reports the EMPTY" "<toolkit-dir> is empty" "" "$TMP" "x"

_bad "repo dir does not exist" "no such repo dir" "$TOOLKIT" "$TMP/does-not-exist"
mkdir -p "$TMP/no-bin"   # its own dir, not $TMP: $TMP gains files as the cases below run
_bad "toolkit dir has no bin/" "no bin/ under toolkit dir" "$TMP/no-bin" "$TMP/no-bin"

# The positive complement: two good positionals must still REACH the checks. Without this, every
# assertion above is satisfied by a bin that refuses everything.
rc=0; "$DRIFT" "$TOOLKIT" "$TMP/no-bin" >/dev/null 2>&1 || rc=$?
eq "two good positionals: not refused as a bad invocation" "0" "$rc"

# ---------------------------------------------------------------------------
# A repo that vendors nothing is OK — stated here, up front, because it is why every rc-0
# assertion in this file needs a mutation witness beside it.
# ---------------------------------------------------------------------------
echo "== a repo that vendors nothing is trivially OK =="
mkdir -p "$TMP/empty"
_run "$TMP/empty"
eq "empty repo: rc 0" "0" "$RC"
eq "empty repo: says OK" "drift-check: OK" "$OUT"

# ---------------------------------------------------------------------------
# CONTENT DRIFT — the leg the self-run cannot exercise at all.
# ---------------------------------------------------------------------------
echo "== content drift: clean co-vendored copy, then the same dir diverged =="
CLEAN="$TMP/clean"
_vendor "$CLEAN" "$SOURCER" "_kb-board-lib.sh"
cp "$TOOLKIT/VERSION" "$CLEAN/.agent-board-toolkit-version"
_run "$CLEAN"
eq "clean co-vendored copy: rc 0" "0" "$RC"
eq "clean co-vendored copy: says OK" "drift-check: OK" "$OUT"
eq "clean co-vendored copy: stderr silent" "" "$ERR"

# The witness for all three assertions above: one appended line in the SAME directory, and the
# tool names that file. Without this the clean result is indistinguishable from a fixture the
# tool never looked at.
printf '\n# fixture divergence\n' >> "$CLEAN/bin/$SOURCER"
_run "$CLEAN"
eq "diverged vendored tool: rc 1" "1" "$RC"
eq "diverged vendored tool: DRIFT names it" "true" "$(has "DRIFT  bin/$SOURCER" "$ERR")"
eq "diverged vendored tool: prints the re-vendor remedy" "true" \
   "$(has "drift-check: FAILED" "$ERR")"
eq "diverged vendored tool: the untouched lib is NOT named" "false" \
   "$(has "DRIFT  bin/_kb-board-lib.sh" "$ERR")"
eq "diverged vendored tool: MISSING-LIB stays silent (the legs are independent)" "false" \
   "$(has "MISSING-LIB" "$ERR")"

# ...and the witness for "the untouched lib is NOT named": restore the tool, diverge the LIB,
# and the same leg names the lib instead. So that absence was an observation about the fixture,
# not a file the walk skips.
cp "$TOOLKIT/bin/$SOURCER" "$CLEAN/bin/$SOURCER"
printf '\n# fixture divergence\n' >> "$CLEAN/bin/_kb-board-lib.sh"
_run "$CLEAN"
eq "diverged lib: rc 1" "1" "$RC"
eq "diverged lib: DRIFT names the lib" "true" "$(has "DRIFT  bin/_kb-board-lib.sh" "$ERR")"
eq "diverged lib: the restored tool is not named" "false" "$(has "DRIFT  bin/$SOURCER" "$ERR")"

# ---------------------------------------------------------------------------
# MISSING-LIB — live in the self-run, but only ever observed passing there.
# ---------------------------------------------------------------------------
echo "== missing co-vendored lib =="
NOLIB="$TMP/nolib"
_vendor "$NOLIB" "$SOURCER"
_run "$NOLIB"
eq "sourcing bin vendored without the lib: rc 1" "1" "$RC"
eq "sourcing bin vendored without the lib: MISSING-LIB names it" "true" \
   "$(has "MISSING-LIB  bin/$SOURCER" "$ERR")"
eq "sourcing bin vendored without the lib: no DRIFT (the copy is verbatim)" "false" \
   "$(has "DRIFT " "$ERR")"
# Witness that the probe is not simply on for everything: drop the lib in beside it, same dir.
cp "$TOOLKIT/bin/_kb-board-lib.sh" "$NOLIB/bin/_kb-board-lib.sh"
_run "$NOLIB"
eq "lib copied in beside it: rc 0" "0" "$RC"

echo "== the standalone bin is excluded from the probe =="
ALONE="$TMP/standalone"
_vendor "$ALONE" "$STANDALONE"
_run "$ALONE"
eq "standalone bin vendored without the lib: rc 0" "0" "$RC"
eq "standalone bin vendored without the lib: no MISSING-LIB" "false" "$(has "MISSING-LIB" "$ERR")"
# Witness: a sourcing bin added to the SAME lib-less dir does fire, and names only itself.
cp "$TOOLKIT/bin/$SOURCER" "$ALONE/bin/$SOURCER"
_run "$ALONE"
eq "sourcing bin added to the same lib-less dir: MISSING-LIB names it" "true" \
   "$(has "MISSING-LIB  bin/$SOURCER" "$ERR")"
eq "sourcing bin added to the same lib-less dir: the standalone is still not named" "false" \
   "$(has "MISSING-LIB  bin/$STANDALONE" "$ERR")"

# ---------------------------------------------------------------------------
# VERSION SKEW — the leg the plan doc missed. Dead in the self-run because the gate file is
# absent, which is asserted here as its own case so the reason is on the record.
# ---------------------------------------------------------------------------
echo "== version skew =="
SKEW="$TMP/skew"
_vendor "$SKEW" "$SOURCER" "_kb-board-lib.sh"
echo "0.0.0-fixture" > "$SKEW/.agent-board-toolkit-version"
_run "$SKEW"
eq "recorded version disagrees: rc 1" "1" "$RC"
# The toolkit side is read from VERSION, not pinned to a literal: a tool that hardcoded a
# version would go red here, and this assertion cannot go stale on the next release.
eq "recorded version disagrees: SKEW names both versions" "true" \
   "$(has "SKEW  repo records v0.0.0-fixture but toolkit is v$WANT" "$ERR")"
eq "recorded version disagrees: no DRIFT (the copies are verbatim)" "false" "$(has "DRIFT " "$ERR")"

cp "$TOOLKIT/VERSION" "$SKEW/.agent-board-toolkit-version"
_run "$SKEW"
eq "recorded version agrees: rc 0" "0" "$RC"

# The self-run's state: no gate file at all, so the block is skipped and cannot fail. Asserted
# so that making the file mandatory (a plausible future change) cannot land unnoticed.
rm "$SKEW/.agent-board-toolkit-version"
_run "$SKEW"
eq "no recorded version: rc 0 — the skew block is skipped, as in the self-run" "0" "$RC"

# ---------------------------------------------------------------------------
# A repo-local bin with no toolkit counterpart is skipped.
# ---------------------------------------------------------------------------
echo "== a bin that is not a toolkit tool is skipped =="
STRAY="$TMP/stray"
_vendor "$STRAY" "$SOURCER" "_kb-board-lib.sh"
printf '#!/usr/bin/env bash\n# repo-local, not a toolkit tool\n' > "$STRAY/bin/repo-local-helper"
_run "$STRAY"
eq "repo-local bin: rc 0" "0" "$RC"
eq "repo-local bin: never named" "false" "$(has "repo-local-helper" "$ERR")"
# Witness that the walk was live on THIS dir: diverge the vendored tool beside it.
printf '\n# fixture divergence\n' >> "$STRAY/bin/$SOURCER"
_run "$STRAY"
eq "repo-local bin: the vendored sibling still drifts (the walk ran here)" "true" \
   "$(has "DRIFT  bin/$SOURCER" "$ERR")"
eq "repo-local bin: still never named, even on a failing run" "false" \
   "$(has "repo-local-helper" "$ERR")"

_summary "drift-check-fixture-selftest"
