#!/usr/bin/env bash
# install-board-hooks-capability-windows-check.sh — run this ON THE REAL SEAT.
#
#     bash <toolkit>/tests/install-board-hooks-capability-windows-check.sh
#
# WHY IT EXISTS. `install-board-hooks` installs its git hooks by SYMLINK, and that symlink is
# the upgrade contract: a `git pull` in the toolkit checkout updates every installed hook only
# because each hook entry points at the source. On a symlink-incapable seat — the measured case
# is Windows with Developer Mode off and no elevation — the POSIX-emulation layer does not fail
# `ln -s`; it returns rc 0 having substituted a COPY. The installer used to report plain success
# there, and the seat then ran hook copies that never updated again. It now MEASURES capability
# before installing (CAPABLE / NOT_CAPABLE / INDETERMINATE) and refuses rather than pin silently.
#
# WHAT THIS SCRIPT IS FOR. The behaviour above was developed and tested on Linux, where the
# incapable seat can only be SIMULATED (`tests/install-board-hooks-capability-selftest.sh` forces
# it with stub commands on PATH). A simulation is evidence about the simulation. This script uses
# NO stubs: it reads the seat's real verdict and then asserts that what the installer actually
# does on this hardware matches that verdict — including the one invariant that must hold on
# every seat, capable or not: NO run that exits 0 leaves a hook that is not a tracking symlink.
#
# AND IT SETTLES THE QUESTION THE PROBE CAN ONLY INFER. The probe decides by READING the
# installed entry — with the shell's `cat` and with git's own `hash-object` — and concluding what
# git would dispatch. The `== THE ARBITER ==` section stops inferring: it makes an entry with the
# seat's own `ln -s`, REPLACES the hook source the way a toolkit upgrade does, runs a real
# `git checkout`, and reports which content actually executed. It carries its own control (the
# hook is fired once BEFORE the replacement and must leave a marker), because otherwise "nothing
# happened" is indistinguishable from "the replacement did not reach dispatch". Where the two
# disagree, the pairing is the whole point of the run and the output says so in full: a seat the
# probe REFUSES but that dispatches the replacement correctly means the refusal is wrong, and
# that outcome is more valuable than a green run.
#
# WHAT IT NEEDS: this toolkit checkout, `bash`, `git`, and coreutils. NO network, no kanban host,
# no board env, no token, no configuration of any kind, and no path outside its own temp dir.
# WHAT IT TOUCHES: one temp directory (its own `git init` repos and a disposable copy of the
# toolkit), removed on exit. It never reads or writes any repo of yours, and installs nothing
# onto the seat.
#
# HOW TO READ THE OUTPUT: one `ok` / `FAIL` line per assertion, a stated verdict for this seat,
# and a final PASS/FAIL summary line. Exit 0 = every assertion passed. Report the whole output —
# the SEAT REPORT block at the top is what makes the assertions interpretable elsewhere, and the
# two trailing `SEAT VERDICT:` / `SEAT DISPATCH:` lines are the result in one place. A `FAIL`
# here is a finding about the tool, not about your machine; do not adjust anything to make it
# green — send the output.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
SRC_TOOLKIT="$(cd "$HERE/.." && pwd)"
_need -r "$SRC_TOOLKIT/bin/install-board-hooks"
_need -r "$SRC_TOOLKIT/hooks/post-checkout"
_need -r "$SRC_TOOLKIT/hooks/pre-push"
command -v git >/dev/null 2>&1 || { echo "windows-check: git is not on PATH — cannot validate" >&2; exit 1; }
_mktmp_scratch --home

echo "===== SEAT REPORT ====="
printf 'uname          : %s\n' "$(uname -a 2>/dev/null || echo unknown)"
printf 'bash           : %s\n' "${BASH_VERSION:-unknown}"
printf 'git            : %s\n' "$(git --version 2>/dev/null || echo unknown)"
# WHICH BINARY answers `git` here is load-bearing, not trivia. The probe's native reader is
# `git hash-object`, and the whole claim is that it reads the way the binary that DISPATCHES
# hooks reads. On a Git-for-Windows seat that is `git.exe`; if this line names a shim, a
# wrapper, or something inside an emulation layer's own bin directory, the claim needs
# re-checking rather than assuming.
printf 'git binary     : %s\n' "$(command -v git 2>/dev/null || echo '<not on PATH>')"
printf 'uid            : %s\n' "$(id -u 2>/dev/null || echo unknown)"
printf 'MSYS           : %s\n' "${MSYS-<unset>}"
printf 'MSYS2_ARG_CONV : %s\n' "${MSYS2_ARG_CONV_EXCL-<unset>}"
printf 'toolkit        : %s\n' "$SRC_TOOLKIT"
printf 'toolkit version: %s\n' "$(cat "$SRC_TOOLKIT/VERSION" 2>/dev/null || echo unknown)"
printf 'temp root      : %s\n' "$TMP"
# core.symlinks is what git ITSELF concluded about this seat. `git init` probes for symlink
# support and writes `core.symlinks=false` into a repository created on a seat that lacks it, so
# the value a FRESH repo carries is git's own verdict — independent of this tool's probe, and
# the first thing to compare against it when the two disagree.
cs_repo="$TMP/core-symlinks-probe"
git init -q "$cs_repo" 2>/dev/null || :
printf 'core.symlinks  : global=%s · fresh-repo=%s\n' \
    "$(git config --global --get core.symlinks 2>/dev/null || echo '<unset>')" \
    "$(git -C "$cs_repo" config --get core.symlinks 2>/dev/null || echo '<unset>')"

# A DISPOSABLE COPY of the toolkit is what gets run, for one reason: the CAPABLE arm proves
# tracking by REPLACING a hook source and reading it back through the installed entry, and doing
# that to your real checkout would be a write to the tool under test. The installer resolves its
# own toolkit root from its own path, so a copy is a complete, self-consistent toolkit.
TK="$TMP/toolkit"
mkdir -p "$TK/bin" "$TK/hooks"
cp "$SRC_TOOLKIT/bin/install-board-hooks" "$TK/bin/install-board-hooks"
cp "$SRC_TOOLKIT/hooks/post-checkout" "$SRC_TOOLKIT/hooks/pre-push" "$TK/hooks/"
IBH="$TK/bin/install-board-hooks"
HOOKS=(post-checkout pre-push)

# The seat's verdict, from the shipped probe itself — not a re-implementation of it here.
# shellcheck source=/dev/null
source "$IBH"   # main-guarded: defines the probe without running an install
probe_target="$TMP/probe-target"; mkdir -p "$probe_target"
VERDICT_LINE=""; VERDICT_RC=0
VERDICT_LINE="$(_ibh_symlink_probe "$probe_target" 2>"$TMP/probe.err")" || VERDICT_RC=$?
VERDICT="$(printf '%s' "${VERDICT_LINE#VERDICT=}" | cut -d' ' -f1)"
REASON="$(printf '%s' "$VERDICT_LINE" | sed 's/.*REASON=//')"
printf 'probe          : %s (rc %s)\n' "$VERDICT_LINE" "$VERDICT_RC"
if [ -s "$TMP/probe.err" ]; then printf 'probe stderr   : %s\n' "$(cat "$TMP/probe.err")"; fi
echo "======================="
echo

_fresh_repo() { local r="$TMP/repos/$1"; rm -rf "$r"; mkdir -p "$r"; git init -q "$r"; printf '%s' "$r"; }
_run() {   # <args…> — run the installer for real; sets _rc/_out/_err
    _rc=0
    _out="$(bash "$IBH" "$@" 2>"$TMP/run.err")" || _rc=$?
    _err="$(cat "$TMP/run.err")"
}
_hooks_present() {   # count of installed hook entries (symlink or file)
    local r="$1" n=0 h
    for h in "${HOOKS[@]}"; do if [ -e "$r/.git/hooks/$h" ] || [ -L "$r/.git/hooks/$h" ]; then n=$((n + 1)); fi; done
    printf '%s' "$n"
}
# _tracks <repo> <hook> — the ONLY property that matters: does the installed entry still deliver
# the toolkit's content after the SOURCE FILE IS REPLACED (which is what `git pull` does to it)?
_tracks() {
    local r="$1" h="$2" marker="tracking-marker-$RANDOM-$$"
    local src="$TK/hooks/$h" dst="$r/.git/hooks/$h" saved="$TMP/saved-$h"
    cp "$src" "$saved"
    rm -f -- "$src"
    printf '#!/bin/sh\n# %s\n' "$marker" > "$src"
    local got=no
    if grep -q "$marker" "$dst" 2>/dev/null; then got=yes; fi
    rm -f -- "$src"; cp "$saved" "$src"; chmod +x "$src"
    printf '%s' "$got"
}

echo "== the probe answered with one of the three defined verdicts =="
case "$VERDICT" in
    CAPABLE|NOT_CAPABLE|INDETERMINATE) ok "verdict is '$VERDICT'" ;;
    *) bad "verdict is not one of CAPABLE/NOT_CAPABLE/INDETERMINATE — got '$VERDICT_LINE'" ;;
esac
case "$VERDICT:$VERDICT_RC" in
    CAPABLE:0|NOT_CAPABLE:1|INDETERMINATE:2) ok "the printed verdict and the returned status agree (rc $VERDICT_RC)" ;;
    *) bad "verdict/status mismatch: '$VERDICT' with rc $VERDICT_RC" ;;
esac
# Residue is asserted only where the measurement COMPLETED. An INDETERMINATE seat may be
# indeterminate precisely because unlink does not work there (`source-unlink-failed`), and on
# such a seat no implementation can remove its own probe entries — asserting it would restate an
# already-reported local fault as a second, misleading failure. So it is reported instead.
probe_residue="$(find "$probe_target" -maxdepth 1 -name '.ibhp*' | wc -l | tr -d ' ')"
if [ "$VERDICT" = "INDETERMINATE" ]; then
    printf '   probe residue: %s entr(ies) left in %s — expected when the reason names a failed\n' \
           "$probe_residue" "$probe_target"
    printf '   unlink or an unwritable directory; they are disposable (.ibhp*).\n'
else
    eq "the probe left no residue in the directory it probed" "0" "$probe_residue"
fi

echo
echo "== THE INVARIANT — asserted on this seat whatever its verdict is =="
# A default run either exits 0 having installed TRACKING symlinks, or it does not exit 0. There
# is no third outcome. This is the whole point of the change, and it is checkable everywhere.
r="$(_fresh_repo invariant)"
_run "$r"
printf '   [default run] rc=%s\n' "$_rc"
printf '%s\n' "$_err" | sed 's/^/   [stderr] /'
if [ "$_rc" = "0" ]; then
    for h in "${HOOKS[@]}"; do
        eq "rc 0 ⇒ $h is a symlink" "true" "$([ -L "$r/.git/hooks/$h" ] && echo true || echo false)"
        eq "rc 0 ⇒ $h TRACKS its source across a replacement" "yes" "$(_tracks "$r" "$h")"
    done
else
    eq "a non-zero run installed nothing" "0" "$(_hooks_present "$r")"
    ok "rc $_rc — no hook was installed, so no untracked copy can be running (this IS the fix)"
fi

echo
echo "== the disposition matches the verdict =="
case "$VERDICT" in
CAPABLE)
    eq "CAPABLE ⇒ the default run succeeds"    "0" "$_rc"
    eq "…and --check agrees"                   "0" "$( _run --check "$r"; printf '%s' "$_rc")"
    r2="$(_fresh_repo capable-flagged)"
    _run --allow-copies "$r2"
    eq "--allow-copies on a CAPABLE seat still exits 0" "0" "$_rc"
    eq "…and still installs a SYMLINK (the flag permits the fallback, it does not select it)" "true" \
       "$([ -L "$r2/.git/hooks/post-checkout" ] && echo true || echo false)"
    ;;
NOT_CAPABLE)
    eq "NOT_CAPABLE ⇒ the default run refuses with rc 1" "1" "$_rc"
    eq "…the refusal quotes the verdict"                 "true" "$(has "VERDICT=NOT_CAPABLE" "$_err")"
    eq "…and names the opt-in flag"                      "true" "$(has "--allow-copies" "$_err")"
    eq "…and stdout stays silent"                        ""     "$_out"
    _run --check "$r"
    eq "--check refuses the same way"                    "1"    "$_rc"
    eq "…with empty stdout"                              ""     "$_out"
    r2="$(_fresh_repo copies)"
    _run --allow-copies "$r2"
    printf '   [--allow-copies] rc=%s\n' "$_rc"
    eq "--allow-copies exits 3, NOT 0"                   "3"    "$_rc"
    eq "…and installs both hooks"                        "${#HOOKS[@]}" "$(_hooks_present "$r2")"
    for h in "${HOOKS[@]}"; do
        eq "…$h is a real file, not a symlink" "false" "$([ -L "$r2/.git/hooks/$h" ] && echo true || echo false)"
        eq "…$h carries the source's bytes"    "true"  "$(cmp -s "$TK/hooks/$h" "$r2/.git/hooks/$h" && echo true || echo false)"
        eq "…$h is executable (git ignores a hook that is not)" "true" \
           "$([ -x "$r2/.git/hooks/$h" ] && echo true || echo false)"
        eq "…$h is reported AS a copy"         "true"  "$(has "COPY $r2/.git/hooks/$h" "$_out")"
        eq "…and does NOT track its source (which is why it exits 3)" "no" "$(_tracks "$r2" "$h")"
    done
    eq "…and the run states the re-install obligation" "true" "$(has "AFTER EVERY TOOLKIT UPGRADE" "$_err")"
    ;;
INDETERMINATE)
    eq "INDETERMINATE ⇒ the default run fails closed with rc 4" "4" "$_rc"
    eq "…reported as undetermined, not as incapable" "true" "$(has "could not DETERMINE" "$_err")"
    eq "…and NOT as a finding that symlinks are unavailable" "false" \
       "$(has "cannot create tracking symlinks" "$_err")"
    _run --allow-copies "$r"
    eq "--allow-copies does not unblock it"          "4" "$_rc"
    eq "…and still installs nothing"                 "0" "$(_hooks_present "$r")"
    printf '   NOTE: an INDETERMINATE seat has a LOCAL FAULT the reason names (permissions, a stray\n'
    printf '   probe file, an unreadable directory). Report the probe line above — it is the finding.\n'
    ;;
*)
    bad "no disposition could be checked: the probe returned '$VERDICT_LINE'"
    ;;
esac

echo
echo "== THE ARBITER — a REAL git operation, dispatching a REPLACED hook =="
# EVERYTHING ABOVE INFERS DISPATCH FROM A READ. The probe reads the installed entry (with the
# shell's `cat` and with git's own `hash-object`) and concludes what git WOULD dispatch. This
# section stops inferring: it puts a hook entry in place the way an install does, replaces the
# hook SOURCE the way a toolkit upgrade does, runs a real `git checkout`, and asks which
# content actually EXECUTED. That is the property the whole card is about, measured directly.
#
# IT IS DELIBERATELY INDEPENDENT OF THE INSTALLER, and it has to be: on a seat the installer
# REFUSES, the installer never creates an entry, so there would be nothing to dispatch and the
# one question worth spending this seat's run on would go unasked. So the entry here is made
# with the seat's own `ln -s` — the same call the installer would make — and the leg runs on
# every seat, whatever the verdict.
#
# IT CARRIES ITS OWN CONTROL. Before the source is replaced, the hook is fired once and must
# leave a PRE marker. Without that, "no marker after the replacement" is unreadable: it could
# mean the replacement did not reach dispatch (the finding) or that the hook never ran at all
# (no measurement). Three outcomes are therefore distinguished, and only the first is tracking:
#     tracks  — the POST content executed: dispatch follows the source across a replacement
#     frozen  — the PRE content executed: the entry is a snapshot, dispatch is pinned
#     broken  — nothing executed after the replacement, though the control fired
dsrc="$TMP/dispatch-src"; mkdir -p "$dsrc"
dhook="$dsrc/post-checkout"
dmark="$TMP/dispatch-marker"
_write_dhook() {   # <PRE|POST> — the hook SOURCE; it records which generation of it ran
    printf '#!/bin/sh\nprintf %%s %s > "%s"\n' "$1" "$dmark" > "$dhook"
    chmod +x "$dhook"
}
_fire() {   # <branch> — a real git operation that dispatches post-checkout; echoes the marker
    rm -f -- "$dmark"
    git -C "$dr" checkout -q "$1" 2>>"$TMP/dispatch.err" || :
    cat -- "$dmark" 2>/dev/null || :
}
dr="$(_fresh_repo dispatch)"
git -C "$dr" -c user.email=windows-check@invalid -c user.name=windows-check \
    commit -q --allow-empty -m 'dispatch fixture' 2>>"$TMP/dispatch.err" || :
git -C "$dr" branch b1 2>>"$TMP/dispatch.err" || :
git -C "$dr" branch b2 2>>"$TMP/dispatch.err" || :
_write_dhook PRE
rm -f -- "$dr/.git/hooks/post-checkout"
dln_rc=0; ln -s -- "$dhook" "$dr/.git/hooks/post-checkout" 2>>"$TMP/dispatch.err" || dln_rc=$?
d_entry_is_link="$([ -L "$dr/.git/hooks/post-checkout" ] && echo true || echo false)"
DISPATCH=""
if [ "$dln_rc" != 0 ]; then
    DISPATCH="no-entry"
else
    d_control="$(_fire b1)"
    if [ "$d_control" != "PRE" ]; then
        DISPATCH="control-failed"
    else
        _write_dhook POST
        d_observed="$(_fire b2)"
        case "$d_observed" in
            POST) DISPATCH=tracks ;;
            PRE)  DISPATCH=frozen ;;
            *)    DISPATCH=broken ;;
        esac
    fi
fi
printf '   entry made by this seat'"'"'s own `ln -s`: rc=%s, is-a-symlink=%s\n' "$dln_rc" "$d_entry_is_link"
printf '   DISPATCH RESULT: %s\n' "$DISPATCH"
[ ! -s "$TMP/dispatch.err" ] || sed 's/^/   [git stderr] /' "$TMP/dispatch.err"

# probe_tracking — what the PROBE claims about dispatch, in the dispatch leg's own vocabulary.
case "$VERDICT" in
    CAPABLE)     probe_tracking=yes ;;
    NOT_CAPABLE) probe_tracking=no ;;
    *)           probe_tracking=unknown ;;
esac
case "$DISPATCH" in
    tracks)          dispatch_tracking=yes ;;
    frozen|broken)   dispatch_tracking=no ;;
    *)               dispatch_tracking=unknown ;;
esac

case "$DISPATCH" in
control-failed)
    # An unfired hook is not a pass. The leg produced no measurement, so it reds rather than
    # letting an absent marker read as "the replacement did not reach dispatch".
    bad "the dispatch leg measured NOTHING: the hook did not fire even BEFORE the source was replaced"
    printf '   The entry exists but running `git checkout` produced no marker, so this seat cannot\n'
    printf '   answer the dispatch question at all. Likely causes: the entry is not executable by\n'
    printf '   git, hooks are disabled (core.hooksPath), or `git checkout` failed — see the git\n'
    printf '   stderr above. Report this whole output; the arbiter did not run.\n'
    ;;
no-entry)
    printf '   `ln -s` REFUSED to make the entry at all, so no dispatch could be measured here.\n'
    eq "an 'ln -s' that fails outright ⇒ the probe must have refused too" "no" "$probe_tracking"
    ;;
*)
    ok "the dispatch leg produced a real measurement (control fired, then the replacement was tried)"
    ;;
esac

if [ "$dispatch_tracking" != "unknown" ] && [ "$probe_tracking" != "unknown" ]; then
    eq "the PROBE's answer and what git ACTUALLY dispatches agree" "$dispatch_tracking" "$probe_tracking"
    if [ "$probe_tracking" = "no" ] && [ "$dispatch_tracking" = "yes" ]; then
        echo
        echo "   ############################################################################"
        echo "   #  READ THIS FIRST — THIS IS THE FINDING, AND IT IS WORTH MORE THAN A PASS #"
        echo "   ############################################################################"
        printf '   The probe REFUSED this seat (%s)\n' "$VERDICT_LINE"
        printf '   but a real `git checkout` DID dispatch the replaced hook content.\n'
        echo
        echo "   That means the refusal is WRONG on this seat: the upgrade contract the installer"
        echo "   refuses to trust actually holds here, and install-board-hooks is blocking a seat"
        echo "   it should install on."
        if [ "$REASON" = "readers-disagree-native-git-does-not-track" ]; then
            echo
            echo "   The reason token makes the mechanism specific: the two readers disagreed, with"
            echo "   git's own binary reading the entry as opaque and the shell resolving it. A"
            echo "   dispatch that nonetheless delivered the new content confirms that git dispatches"
            echo "   hooks through a shell that resolves what raw git does not — the hypothesis this"
            echo "   run exists to settle. The predicate must then MOVE to this dispatch test rather"
            echo "   than be inferred from a read."
        fi
        echo
        echo "   DO NOT 'fix' this by loosening the probe. Report this entire output — the seat"
        echo "   report, the probe line, and the DISPATCH RESULT — to whoever owns the change."
        echo "   ############################################################################"
    fi
    if [ "$probe_tracking" = "yes" ] && [ "$dispatch_tracking" = "no" ]; then
        echo
        echo "   ############################################################################"
        echo "   #  READ THIS FIRST — A FALSE 'CAPABLE': THE WORST OUTCOME FOR THIS TOOL    #"
        echo "   ############################################################################"
        printf '   The probe answered CAPABLE (%s)\n' "$VERDICT_LINE"
        printf '   but a real `git checkout` dispatched the OLD content (%s).\n' "$DISPATCH"
        echo "   An install on this seat would report success and pin it to hooks no upgrade"
        echo "   reaches — the exact silent degrade the probe exists to prevent, reproduced"
        echo "   inside the probe. Report this entire output."
        echo "   ############################################################################"
    fi
else
    printf '   NO pairing assertion was made: probe=%s dispatch=%s. One side has no answer, and an\n' \
           "$probe_tracking" "$dispatch_tracking"
    printf '   equivalence asserted over an unknown is not a check. Both values are reported above.\n'
fi

echo
echo "== usage surface =="
_run --nope "$TMP"
eq "an unknown option is rc 2"    "2"    "$_rc"
eq "usage names --check"          "true" "$(has "[--check]" "$_err")"
eq "usage names --allow-copies"   "true" "$(has "[--allow-copies]" "$_err")"

echo
printf 'SEAT VERDICT: %s\n' "$VERDICT_LINE"
# THE PAIR IS THE RESULT, so it is restated on one line: what the probe INFERS about dispatch,
# beside what a real dispatch DID. A reader with none of this context needs both, together.
printf 'SEAT DISPATCH: %s — probe says tracking=%s, real git dispatch says tracking=%s\n' \
       "$DISPATCH" "$probe_tracking" "$dispatch_tracking"
_summary "install-board-hooks-capability-windows-check ($VERDICT)"
