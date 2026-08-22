#!/usr/bin/env bash
# runtime-check-selftest.sh — decision-matrix checks for bin/agent-board-toolkit-runtime-check
# (card #4361). The guard judges WHAT EXECUTES; these drive it against synthetic topologies
# under a scratch HOME + PATH: pinned-current, pinned-STALE, dev-ahead, copies-current,
# copies-STALE, copies-unverifiable, mixed-runtimes. Network-free: the tag fetch inside the
# guard fails against the file-path-less origin and is tolerated as a named warn.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_bin-set-lib.sh"
CHECK="$HERE/../bin/agent-board-toolkit-runtime-check"
_need -x "$CHECK"

_mktmp_scratch
export HOME="$TMP/home"; mkdir -p "$HOME"   # scratch HOME under TMP (not =TMP: fixtures live in TMP)

# A minimal toolkit-shaped repo with two release tags.
mk_repo() { # <dir>
    git init -q "$1"
    mkdir -p "$1/bin"
    printf '#!/bin/sh\necho v1\n' > "$1/bin/kbcard"; chmod +x "$1/bin/kbcard"
    printf '0.1.0\n' > "$1/VERSION"
    git -C "$1" -c user.email=t@t -c user.name=t add -A
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm one
    git -C "$1" tag v0.1.0
    printf '#!/bin/sh\necho v2\n' > "$1/bin/kbcard"
    printf '0.2.0\n' > "$1/VERSION"
    git -C "$1" -c user.email=t@t -c user.name=t add -A
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm two
    git -C "$1" tag v0.2.0
}

run_check() { # <bindir> [extra args...] -> sets RC, ERR
    local bindir="$1"; shift
    RC=0
    ERR="$(PATH="$bindir:/usr/bin:/bin" "$CHECK" "$@" 2>&1 >/dev/null)" || RC=$?
}

echo "== pinned runtime at the newest tag → ok =="
mk_repo "$TMP/repo1"
git -C "$TMP/repo1" checkout -q v0.2.0
mkdir -p "$TMP/bin1"; ln -s "$TMP/repo1/bin/kbcard" "$TMP/bin1/kbcard"
run_check "$TMP/bin1"
eq "current pin → rc 0" "0" "$RC"

echo "== pinned runtime BEHIND the newest tag → loud rc 1 =="
mk_repo "$TMP/repo2"
git -C "$TMP/repo2" checkout -q v0.1.0
mkdir -p "$TMP/bin2"; ln -s "$TMP/repo2/bin/kbcard" "$TMP/bin2/kbcard"
run_check "$TMP/bin2"
eq "stale pin → rc 1" "1" "$RC"
grep -q "STALE runtime" <<<"$ERR" && ok "names the staleness" || bad "missing STALE runtime message"
grep -q "v0.1.0.*v0.2.0" <<<"$ERR" && ok "names both versions" || bad "missing version pair"
grep -q "checkout v0.2.0" <<<"$ERR" && ok "detached pin → advance-the-pin remedy" || bad "pinned remedy lost its checkout"

echo "== clone TRACKING a branch, behind the newest tag → rc 1, remedy must not detach it =="
# INSTALL §1 Option A: a clone whose HEAD stays on its branch, upgraded by `git pull`. Telling
# this topology to `checkout <tag>` converts a self-advancing install into a detached pin — the
# very state INSTALL §2's warning box tells the reader to stay out of, and the state in which
# UPGRADE §2's own `git pull --ff-only` exits 1 (`You are not currently on a branch.`).
mk_repo "$TMP/repo2b-origin"
git clone -q "$TMP/repo2b-origin" "$TMP/repo2b"
git -C "$TMP/repo2b" reset --hard -q v0.1.0    # on its branch, behind origin's v0.2.0
mkdir -p "$TMP/bin2b"; ln -s "$TMP/repo2b/bin/kbcard" "$TMP/bin2b/kbcard"
run_check "$TMP/bin2b"
eq "stale clone → rc 1" "1" "$RC"
grep -q "STALE runtime" <<<"$ERR" && ok "names the staleness" || bad "missing STALE runtime message"
grep -q "pull --ff-only" <<<"$ERR" && ok "remedy is the topology-preserving pull" || bad "remedy does not name pull --ff-only"
grep -q "checkout v0.2.0" <<<"$ERR" && bad "remedy would DETACH a branch-tracking clone" || ok "remedy does not detach the clone"

echo "== dev checkout AHEAD of the newest tag → ok (maintainer topology) =="
mk_repo "$TMP/repo3"
printf 'x\n' > "$TMP/repo3/extra"; git -C "$TMP/repo3" -c user.email=t@t -c user.name=t add -A
git -C "$TMP/repo3" -c user.email=t@t -c user.name=t commit -qm three   # v0.2.0-1-g…
mkdir -p "$TMP/bin3"; ln -s "$TMP/repo3/bin/kbcard" "$TMP/bin3/kbcard"
run_check "$TMP/bin3"
eq "dev-ahead → rc 0" "0" "$RC"

echo "== copies topology: byte-match vs stale vs unverifiable =="
mk_repo "$HOME/agent-board-toolkit"     # auto-derived reference
mkdir -p "$TMP/bin4"; cp "$HOME/agent-board-toolkit/bin/kbcard" "$TMP/bin4/kbcard"; chmod +x "$TMP/bin4/kbcard"
run_check "$TMP/bin4"
eq "matching copy → rc 0" "0" "$RC"

printf '#!/bin/sh\necho OLD\n' > "$TMP/bin4/kbcard"   # stale copy
run_check "$TMP/bin4"
eq "stale copy → rc 1" "1" "$RC"
grep -q "STALE COPIES" <<<"$ERR" && ok "names the stale copy" || bad "missing STALE COPIES message"

# ── the verdict must survive a reader that stops reading (card#6911) ────────────────────────
#
# This is the SAME stale-copies topology one assertion above — a REAL rc-1 verdict with its ✗
# line — driven through a consumer that stops consuming stdout. Measured before the fix:
# `rc 141, 0 B of stderr`, i.e. the verdict AND the explanation both destroyed, while the
# invocation looked like it had worked. The general gate for this class over every shipped bin
# is tests/verdict-through-truncating-reader-selftest.sh; this block is the one thing that gate
# structurally cannot reach — this tool's actual VERDICT path, which needs the fixture above.
#
# ⛔ ASSERTED ON rc PRESERVATION, NEVER ON A SIGNAL NUMBER. A GitHub Actions runner starts bash
# from Node with SIGPIPE set to SIG_IGN, and that disposition survives execve — so in CI the
# write returns EPIPE and the rc is 1, where a developer box gives 141. `expected == direct` is
# the same sentence under both dispositions; `expected == 141` reds in CI only.
# run_truncated <bindir> <reader...> -- <check args...> -> sets TRC_DFL, TRC_IGN, TERR_BYTES
#
# BOTH SIGPIPE DISPOSITIONS, PINNED. A GitHub Actions runner starts bash from Node with SIGPIPE
# already SIG_IGN, and an ignored disposition is inherited across execve — so the runner sees a
# write that RETURNS EPIPE where a developer terminal sees the process killed by the signal.
# The two produce different rcs (1 vs 141) and, for a bin with no errexit, different OUTCOMES.
# Neither is inherited here: each leg sets the disposition it names, so this assertion means the
# same thing wherever it runs, and SAFE means safe under both — which is exactly what the
# tool's two mechanisms are for (the trap answers the signal, the tolerated write answers the
# EPIPE rc; either alone leaves one disposition uncovered).
#
# `set +e` is load-bearing: under `pipefail` the pipeline's status IS the writer's own verdict
# (rc 1 here), so errexit would kill the suite on a PASSING assertion. `|| true` would not do —
# `true` is itself a pipeline and resets PIPESTATUS before it can be read.
run_truncated() {
    local bindir="$1"; shift
    local reader=(); while [ "$1" != "--" ]; do reader+=("$1"); shift; done; shift
    # ⛔ `env`, NOT `trap`: a signal IGNORED on entry to a non-interactive shell cannot be
    # reset from inside it, so `trap - PIPE` is a silent no-op on a CI runner and both legs
    # would measure SIG_IGN. `env --default-signal` sets the disposition in the child, after
    # fork and before exec. Measured: from an ignoring parent, `trap - PIPE` gave rc 1 where
    # `env --default-signal=PIPE` gave 141 on the same command.
    set +e
    TRC_DFL="$( env --default-signal=PIPE env "PATH=$bindir:/usr/bin:/bin" "$CHECK" "$@" 2>"$TMP/trunc.err" \
                | "${reader[@]}" >/dev/null 2>&1; printf '%s' "${PIPESTATUS[0]}" )"
    TERR_BYTES="$(wc -c <"$TMP/trunc.err" | tr -d ' ')"
    TRC_IGN="$( env --ignore-signal=PIPE env "PATH=$bindir:/usr/bin:/bin" "$CHECK" "$@" 2>/dev/null \
                | "${reader[@]}" >/dev/null 2>&1; printf '%s' "${PIPESTATUS[0]}" )"
    set -e
}

echo "== the STALE-COPIES verdict survives a truncating reader =="
run_check "$TMP/bin4"                       # re-establish DIRECT rc + stderr for comparison
eq "witness: the direct run still carries the verdict" "1" "$RC"
eq "…and real stderr with it" "true" "$([ "${#ERR}" -gt 100 ] && echo true || echo false)"

# ⛔ `head -n 0` ONLY, AND THE OMISSIONS ARE MEASURED RATHER THAN ASSUMED. `head -1` and
# `head -c 1` were both here and were both DROPPED: this fixture's stdout is a single short
# line, so those readers consume the whole of it before exiting and the writer never meets a
# closed pipe. Run against the defect with `trap '' PIPE` deleted, they PASSED while `head -n 0`
# reported 141 — they cannot fail on this payload, which makes them decorations, not checks.
# The wider reader set is exercised where the payload is big enough to make it mean something
# (tests/gh-code-search-selftest.sh, on an 11 KB page).
run_truncated "$TMP/bin4" head -n 0 --
eq "through \`head -n 0\` at SIG_DFL: rc is the verdict, not a signal death" "$RC" "$TRC_DFL"
eq "…and at SIG_IGN (the CI disposition) too"                               "$RC" "$TRC_IGN"
eq "…and the ✗ explanation still reaches stderr" "true" \
   "$([ "$TERR_BYTES" -gt 100 ] && echo true || echo false)"

echo "== …and so does the rc-0 verdict on a PASSING tree =="
# The card measured this half separately, and it is the one that hides: a truncated rc 141 in
# place of a clean rc 0 says "this runtime is broken" about a runtime that is fine.
run_check "$TMP/bin1"
eq "witness: the passing topology is rc 0 directly" "0" "$RC"
run_truncated "$TMP/bin1" head -n 0 --
eq "through \`head -n 0\` at SIG_DFL: still rc 0" "0" "$TRC_DFL"
eq "…and at SIG_IGN too"                          "0" "$TRC_IGN"

rm -rf "$HOME/agent-board-toolkit"
run_check "$TMP/bin4"
eq "unverifiable copy → rc 0 (warn, honest UNKNOWN)" "0" "$RC"
grep -q "CANNOT BE VERIFIED" <<<"$ERR" && ok "says UNKNOWN, not ok" || bad "missing cannot-verify warn"

echo "== mixed runtimes → loud rc 1 =="
mkdir -p "$TMP/bin5"
ln -s "$TMP/repo1/bin/kbcard" "$TMP/bin5/kbcard"
printf '#!/bin/sh\necho x\n' > "$TMP/repo2/bin/next-dl"; chmod +x "$TMP/repo2/bin/next-dl"
git -C "$TMP/repo2" -c user.email=t@t -c user.name=t add -A
git -C "$TMP/repo2" -c user.email=t@t -c user.name=t commit -qm nd
ln -s "$TMP/repo2/bin/next-dl" "$TMP/bin5/next-dl"
run_check "$TMP/bin5"
eq "mixed runtimes → rc 1" "1" "$RC"
grep -q "MIXED runtimes" <<<"$ERR" && ok "names the split" || bad "missing MIXED runtimes message"

echo "== ships-but-missing symlink → warn, rc stays 0 =="
run_check "$TMP/bin1"   # repo1 also ships only kbcard; simulate by adding a tool to the repo
printf '#!/bin/sh\n' > "$TMP/repo1/bin/adopt-to-dl"; chmod +x "$TMP/repo1/bin/adopt-to-dl"
run_check "$TMP/bin1"
eq "install gap → rc 0 (warn-only)" "0" "$RC"
grep -q "ships adopt-to-dl but PATH lacks" <<<"$ERR" && ok "names the install gap" || bad "missing install-gap warn"

echo "== board-snapshot surfaces the guard on STDOUT, not stderr (card #4393) =="
# The channel is the whole point: board-snapshot runs inside a SessionStart hook whose
# consumer reads STDOUT. A stderr-only warning is discarded — the guard would be
# installed, correct, and silent (board-card-start ate this exact trap). Drive the real
# snapshot line against a STALE pin and assert the warning is on stdout.
SNAP="$HERE/../bin/board-snapshot"
if [[ -r "$SNAP" ]]; then
    # The exact invocation from board-snapshot's tail, run against the stale repo2 pin.
    line="$(grep -A1 'command -v agent-board-toolkit-runtime-check' "$SNAP" | tail -1)"
    grep -q '2>&1' <<<"$line" && ok "snapshot folds the guard's stderr into stdout" \
        || bad "snapshot invocation lacks 2>&1 — a stale-pin warning would be discarded by the hook"
    # Empirical: stdout ALONE (stderr dropped, as a stdout-capturing hook sees it) must
    # still carry the STALE warning. $CHECK by absolute path = board-snapshot's line with
    # the guard resolved. It DOES scan itself (card#5389), but through `command -v` on the
    # fixture PATH, which lacks it — so it lands in `missing`, the fixture repos ship no
    # such file, and neither a second root nor a gap warning can be manufactured here.
    # NB the first draft of this test used the bare name on a fixture PATH lacking the
    # guard: it returned EMPTY and read as a pass-shaped failure — the same
    # can't-bootstrap trap the guard exists for. Hence the positive control below.
    out="$(PATH="$TMP/bin2:/usr/bin:/bin" sh -c "$CHECK --quiet 2>&1 || true" 2>/dev/null)"
    grep -q "STALE runtime" <<<"$out" && ok "stale pin warns ON STDOUT (survives a stderr-dropping consumer)" \
        || bad "stale-pin warning did not reach stdout: [$out]"
    # Positive control for the channel itself: WITHOUT the 2>&1 fold, that same warning
    # must VANISH from stdout — proving the assertion above tests the fold, not luck.
    out="$(PATH="$TMP/bin2:/usr/bin:/bin" sh -c "$CHECK --quiet || true" 2>/dev/null)"
    [[ -z "$out" ]] && ok "control: without 2>&1 the warning is INVISIBLE to a stdout consumer" \
        || bad "control failed — warning reached stdout without the fold: [$out]"
    # Control: a CURRENT, fully-installed pin stays silent on stdout (no cry-wolf at every
    # SessionStart). Its OWN fixture — repo1/bin1 were mutated by the ships-but-missing
    # case above, and reusing them made this control fire that warn instead (a fixture
    # dependency, not a code fault; caught by this control's own failure).
    mk_repo "$TMP/repo_ch"
    git -C "$TMP/repo_ch" checkout -q v0.2.0
    mkdir -p "$TMP/bin_ch"; ln -s "$TMP/repo_ch/bin/kbcard" "$TMP/bin_ch/kbcard"
    out="$(PATH="$TMP/bin_ch:/usr/bin:/bin" sh -c "$CHECK --quiet 2>&1 || true" 2>/dev/null)"
    [[ -z "$out" ]] && ok "current pin prints nothing (quiet when healthy)" || bad "current pin should be silent, got: [$out]"
else
    bad "board-snapshot not found next to the selftest"
fi

echo "== TOOLS probes exactly bin/'s public tool set (card#5389) =="
# WHY THIS LEG EXISTS. TOOLS was a hand-maintained enumeration of bin/ that had drifted to 10 of
# 13 — dl-a0-backfill-triaged, dl-a1-register-field and this check itself were structurally
# invisible to BOTH failure legs above, so the tool that exists to prove an install is honest
# could not see three of the tools it installs and said nothing about the gap. Nothing reported
# it: the README gate (readme-bin-coverage-selftest.sh) covers the doc inventory, not this array.
#
# THE SET IS READ BACK FROM THE TOOL, never parsed out of its source. On a PATH carrying none of
# the tools, every name lands in `missing` and the no-roots arm prints the whole array on stdout.
# So this asserts the set the check ACTUALLY probes and survives any refactor of how the array is
# spelled — a source grep would instead assert the spelling and could pass over an array the code
# no longer reads.
#
# WHAT A GREEN RUN HERE PROVES — the weakest property these assertions support: that two NAME
# SETS agree. It says nothing about whether probing a given name is USEFUL, whether the legs that
# consume TOOLS are correct, or whether the set is the right one to probe — in particular
# `_`-prefixed entries are outside it by construction, so `_kb-board-lib.sh` staying unchecked in
# the copies topology (card#5414) is invisible to this leg and always will be.
# Its OWN scratch HOME, like the channel control above: the cases before this one create and
# delete $HOME/agent-board-toolkit, and a readback that silently depended on which of them ran
# last is the fixture-ordering dependency this file has already been bitten by once.
_probed_tools() {
    HOME="$TMP/nohome" PATH=/usr/bin:/bin "$CHECK" 2>/dev/null \
        | sed -n 's/^runtime-check: not on PATH (fine if unused): //p' | tr ' ' '\n' | LC_ALL=C sort
}
mkdir -p "$TMP/nohome"
probed="$(_probed_tools)"

# Positive control FIRST. Both live assertions below are assertions of ABSENCE, and their shared
# failure mode is an EMPTY readback — a reworded line, a moved channel, or a non-zero exit would
# make both pass by comparing nothing against nothing.
eq "probe readback is non-empty" "false" "$([ -z "$probed" ] && echo true || echo false)"
# A named member, not a count: a count pins the check to a past value and rots as bin/ grows.
eq "probe readback carries a known member" "true" \
   "$(has_line 'kbcard' "$probed")"
eq "witness: the bin/ side is non-empty too" "true" \
   "$([ -n "$(_public_bin_names "$HERE/../bin")" ] && echo true || echo false)"

eq "every public bin/ tool is probed (add the name below to TOOLS)" "" \
   "$(LC_ALL=C comm -23 <(_public_bin_names "$HERE/../bin") <(printf '%s\n' "$probed"))"
eq "every probed name is a public bin/ tool (drop the name below from TOOLS)" "" \
   "$(LC_ALL=C comm -13 <(_public_bin_names "$HERE/../bin") <(printf '%s\n' "$probed"))"

# PROVE IT CAN FAIL. Each direction is pointed at a fixture bin/ carrying the exact defect it
# claims to catch, compared against the REAL readback — so a fixture that produced no comparison
# at all would fail its own witness rather than read as clean.
echo "== prove-it-can-fail: a bin/ tool absent from TOOLS is REPORTED =="
mkdir -p "$TMP/bin-extra"; touch "$TMP/bin-extra/kbcard" "$TMP/bin-extra/ghost-tool"
eq "the unprobed tool is named" "ghost-tool" \
   "$(LC_ALL=C comm -23 <(_public_bin_names "$TMP/bin-extra") <(printf '%s\n' "$probed"))"
eq "the probed sibling is NOT named (witness: the comparison saw the real readback)" "" \
   "$(LC_ALL=C comm -23 <(_public_bin_names "$TMP/bin-extra") <(printf '%s\n' "$probed") | grep -x 'kbcard' || true)"

echo "== prove-it-can-fail: a probed name with no bin/ tool is REPORTED =="
mkdir -p "$TMP/bin-min"; touch "$TMP/bin-min/kbcard"
eq "witness: the fixture holds exactly the one tool" "kbcard" "$(_public_bin_names "$TMP/bin-min")"
extra="$(LC_ALL=C comm -13 <(_public_bin_names "$TMP/bin-min") <(printf '%s\n' "$probed"))"
eq "every other probed name is reported" "false" "$([ -z "$extra" ] && echo true || echo false)"
eq "…and the name the fixture DOES hold is not among them" "" \
   "$(printf '%s\n' "$extra" | grep -x 'kbcard' || true)"

_summary "runtime-check-selftest"
