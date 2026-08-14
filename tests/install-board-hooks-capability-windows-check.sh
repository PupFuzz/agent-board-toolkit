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
# WHAT IT NEEDS: this toolkit checkout, `bash`, `git`, and coreutils. NO network, no kanban host,
# no board env, no token, no configuration of any kind, and no path outside its own temp dir.
# WHAT IT TOUCHES: one temp directory (its own `git init` repos and a disposable copy of the
# toolkit), removed on exit. It never reads or writes any repo of yours, and installs nothing
# onto the seat.
#
# HOW TO READ THE OUTPUT: one `ok` / `FAIL` line per assertion, a stated verdict for this seat,
# and a final PASS/FAIL summary line. Exit 0 = every assertion passed. Report the whole output —
# the SEAT REPORT block at the top is what makes the assertions interpretable elsewhere.
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
printf 'uid            : %s\n' "$(id -u 2>/dev/null || echo unknown)"
printf 'MSYS           : %s\n' "${MSYS-<unset>}"
printf 'MSYS2_ARG_CONV : %s\n' "${MSYS2_ARG_CONV_EXCL-<unset>}"
printf 'toolkit        : %s\n' "$SRC_TOOLKIT"
printf 'toolkit version: %s\n' "$(cat "$SRC_TOOLKIT/VERSION" 2>/dev/null || echo unknown)"
printf 'temp root      : %s\n' "$TMP"

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
echo "== usage surface =="
_run --nope "$TMP"
eq "an unknown option is rc 2"    "2"    "$_rc"
eq "usage names --check"          "true" "$(has "[--check]" "$_err")"
eq "usage names --allow-copies"   "true" "$(has "[--allow-copies]" "$_err")"

echo
printf 'SEAT VERDICT: %s\n' "$VERDICT_LINE"
_summary "install-board-hooks-capability-windows-check ($VERDICT)"
