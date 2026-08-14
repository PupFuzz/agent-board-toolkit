#!/usr/bin/env bash
# install-board-hooks-capability-selftest.sh — the symlink-capability probe and the three
# dispositions the installer takes on its verdicts (card#6527).
#
# WHAT IT GUARDS. `install-board-hooks` installs by symlink, and that symlink IS the upgrade
# contract: a `git pull` in the toolkit checkout updates every installed hook only because each
# hook entry points at the source. A seat whose OS/filesystem cannot create symlinks does not
# report a failure — the POSIX-emulation layer on a Windows/MSYS seat (Developer Mode off, no
# elevation) answers `ln -s` with rc 0 after substituting a COPY, so the install reported plain
# success while the seat ran hooks `git pull` would never update again. That outcome was
# indistinguishable, in every log this tool writes, from a healthy install.
#
# THE REAL SURFACE IS A WINDOWS SEAT AND THIS TEST DOES NOT RUN ON ONE. Every NOT_CAPABLE and
# INDETERMINATE case here is produced by a FORCED condition — a stub `ln` on PATH reproducing
# the measured shape (rc 0, result is a copy), a stub `ln` that fails outright, a stub `ln` that
# links to a snapshot (a real symlink that does not track its source), and a stub `rm` whose
# unlink silently no-ops. A stub is a simulation of the seat, never evidence about it: the
# standalone `tests/install-board-hooks-capability-windows-check.sh` is what a real Windows seat
# runs to confirm the actual behaviour, and it uses no stubs at all.
#
# EVERY STUB IS POSITIVE-CONTROLLED BEFORE IT IS RELIED ON. An assertion that a run REFUSED is
# satisfied by any refusal, including one from a stub that never took effect and a `PATH` that
# never applied — so each stub is first witnessed changing the behaviour of a plain command, and
# the capable baseline is asserted on the same tree so "refuses everything" cannot pass.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
IBH="$HERE/../bin/install-board-hooks"
_need -r "$IBH"
_mktmp_scratch --home
# shellcheck source=/dev/null
source "$IBH"   # main-guarded — defines _ibh_symlink_probe without running an install

REAL_PATH="$PATH"

# _stub_dir <slot> <command> <body…> — a PATH-prepended stub for ONE command, in a directory
# keyed by SLOT rather than by command name. Three different `ln` stubs exist below, and keying
# by the command alone put all three in one directory: each new one silently overwrote the last,
# so every case ran the final stub while its label claimed otherwise. Echoes the directory.
_stub_dir() {
    local slot="$1" name="$2"; shift 2
    local d="$TMP/stubs/$slot"
    mkdir -p "$d"
    printf '%s\n' '#!/usr/bin/env bash' "$@" > "$d/$name"
    chmod +x "$d/$name"
    printf '%s' "$d"
}

# _use_stub <dir> / _use_real — swap the PATH. `hash -r` is load-bearing: bash caches the
# resolved path of every command it has run, so a PATH change alone can leave the ALREADY
# resolved `ln`/`rm` in use and the stub silently unexercised.
_use_stub() { PATH="$1:$REAL_PATH"; hash -r; }
_use_real() { PATH="$REAL_PATH"; hash -r; }

# An `ln -s` that reports success and produces a COPY — the shape measured on a real Windows
# seat. Written to survive any flag spelling the probe or the installer uses.
LN_COPY="$(_stub_dir ln-copy ln \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'cp -- "${args[0]}" "${args[1]}"; exit 0')"
# An `ln -s` that fails outright, with its own words on stderr.
LN_FAIL="$(_stub_dir ln-fail ln \
    'echo "ln: failed to create symbolic link: Operation not permitted" >&2; exit 1')"
# An `ln -s` that creates a REAL symlink — to a snapshot of the source. It is `-L`, so only the
# replacement-tracking clause can catch it. Its snapshot is named OUTSIDE the probe's `.ibhp*`
# namespace so the stub's own litter is never counted as probe residue.
LN_SNAPSHOT="$(_stub_dir ln-snapshot ln \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'snap="$(dirname -- "${args[0]}")/stub-snapshot.dat"' \
    'cp -- "${args[0]}" "$snap"; exec /bin/ln -s -- "$snap" "${args[1]}"')"
# An `rm` whose unlink silently does nothing — the probe cannot replace its own source, so the
# measurement never happens.
RM_NOOP="$(_stub_dir rm-noop rm 'exit 0')"

# _probe <dir> — run the probe, capture stdout/rc into _out/_rc (stderr to _err).
_probe() {
    _rc=0
    _out="$(_ibh_symlink_probe "$1" 2>"$TMP/probe.err")" || _rc=$?
    _err="$(cat "$TMP/probe.err")"
}
# _verdict / _reason — projections of the one-line contract.
_verdict() { printf '%s' "${1#VERDICT=}" | cut -d' ' -f1; }
_reason()  { printf '%s' "$1" | sed 's/.*REASON=//'; }
# _residue <dir> — probe entries left behind. The probe writes into a directory it does not own,
# so "leaves it as it found it" is a contract, not tidiness: --check performs this same write.
_residue() { find "$1" -maxdepth 1 -name '.ibhp*' 2>/dev/null | wc -l | tr -d ' '; }

# ---------------------------------------------------------------------------
echo "== positive control — the stubs actually take effect on this PATH =="
# Without these, every NOT_CAPABLE assertion below could be passing on a stub that was never
# reached (a hashed `ln`, a PATH that did not apply), i.e. for the wrong reason.
ctl="$TMP/ctl"; mkdir -p "$ctl"; echo one > "$ctl/src"
_use_stub "$LN_COPY"; ln -s -- "$ctl/src" "$ctl/copy-dst"; _use_real
eq "the copy-stub's 'ln -s' yields a NON-symlink" "false" \
   "$([ -L "$ctl/copy-dst" ] && echo true || echo false)"
eq "…and a real file with the source's bytes" "one" "$(cat "$ctl/copy-dst")"
_use_stub "$RM_NOOP"; rm -f -- "$ctl/src"; _use_real
eq "the rm-stub's unlink leaves the file in place" "true" \
   "$([ -e "$ctl/src" ] && echo true || echo false)"
_use_real; /bin/rm -f -- "$ctl/copy-dst"
ln -s -- "$ctl/src" "$ctl/real-dst"
eq "…and OFF the stub PATH, a real 'ln -s' makes a symlink" "true" \
   "$([ -L "$ctl/real-dst" ] && echo true || echo false)"

# ---------------------------------------------------------------------------
echo "== the probe — CAPABLE on an ordinary directory (the baseline that must not refuse) =="
cap="$TMP/cap"; mkdir -p "$cap"
_probe "$cap"
eq "verdict"                "CAPABLE" "$(_verdict "$_out")"
eq "rc"                     "0"       "$_rc"
eq "reason"                 "ok"      "$(_reason "$_out")"
eq "exactly one line"       "1"       "$(printf '%s\n' "$_out" | wc -l | tr -d ' ')"
eq "names the probed dir"   "true"    "$(has "DIR=$cap" "$_out")"
eq "leaves no residue"      "0"       "$(_residue "$cap")"
eq "writes nothing to stderr" ""      "$_err"

echo "== the probe — NOT_CAPABLE: 'ln -s' succeeds and yields a copy (the measured shape) =="
nc="$TMP/nc"; mkdir -p "$nc"
_use_stub "$LN_COPY"; _probe "$nc"; _use_real
eq "verdict"           "NOT_CAPABLE"                                        "$(_verdict "$_out")"
eq "rc"                "1"                                                  "$_rc"
eq "reason"            "ln-reported-success-but-result-is-not-a-symlink"    "$(_reason "$_out")"
eq "leaves no residue" "0"                                                  "$(_residue "$nc")"

echo "== the probe — NOT_CAPABLE: 'ln -s' fails, and its OWN words survive on stderr =="
nf="$TMP/nf"; mkdir -p "$nf"
_use_stub "$LN_FAIL"; _probe "$nf"; _use_real
eq "verdict"                "NOT_CAPABLE"   "$(_verdict "$_out")"
eq "rc"                     "1"             "$_rc"
eq "reason carries ln's rc" "ln-failed-rc1" "$(_reason "$_out")"
eq "ln's message is on stderr, verbatim" "true" "$(has "Operation not permitted" "$_err")"
eq "…and NOT folded into the one-line contract" "false" "$(has "Operation not permitted" "$_out")"
eq "leaves no residue"      "0"             "$(_residue "$nf")"

echo "== the probe — NOT_CAPABLE: a REAL symlink that does not track its source =="
# `-L` alone is not the property: `git pull` REPLACES the hook source (new inode), so a link to
# a snapshot passes the is-it-a-link clause and still goes permanently stale.
ns="$TMP/ns"; mkdir -p "$ns"
_use_stub "$LN_SNAPSHOT"; _probe "$ns"; _use_real
eq "verdict" "NOT_CAPABLE"                                    "$(_verdict "$_out")"
eq "rc"      "1"                                              "$_rc"
eq "reason"  "link-does-not-track-source-across-replacement"  "$(_reason "$_out")"

echo "== the probe — INDETERMINATE is its own verdict, never folded into NOT_CAPABLE =="
_probe ""
eq "empty argument: verdict" "INDETERMINATE" "$(_verdict "$_out")"
eq "empty argument: rc"      "2"             "$_rc"
eq "empty argument: reason"  "no-target-dir" "$(_reason "$_out")"
_probe "$TMP/does-not-exist"
eq "missing dir: verdict"    "INDETERMINATE"    "$(_verdict "$_out")"
eq "missing dir: rc"         "2"                "$_rc"
eq "missing dir: reason"     "not-a-directory"  "$(_reason "$_out")"
printf 'x\n' > "$TMP/a-file"
_probe "$TMP/a-file"
eq "a file, not a dir: verdict" "INDETERMINATE"   "$(_verdict "$_out")"
eq "a file, not a dir: reason"  "not-a-directory" "$(_reason "$_out")"
ui="$TMP/ui"; mkdir -p "$ui"
_use_stub "$RM_NOOP"; _probe "$ui"; _use_real
eq "unlink no-ops: verdict" "INDETERMINATE"        "$(_verdict "$_out")"
eq "unlink no-ops: rc"      "2"                    "$_rc"
eq "unlink no-ops: reason"  "source-unlink-failed" "$(_reason "$_out")"

# The unwritable-directory arm cannot fail for root, so it is not run for root — and says so
# rather than reporting a pass it did not earn.
uw="$TMP/uw"; mkdir -p "$uw"; chmod 500 "$uw"
if [ "$(id -u)" = "0" ]; then
    printf '  ARM NOT EXERCISED: unwritable-directory (running as uid 0; chmod 500 does not bind)\n' >&2
else
    _probe "$uw"
    eq "unwritable dir: verdict" "INDETERMINATE"            "$(_verdict "$_out")"
    eq "unwritable dir: rc"      "2"                        "$_rc"
    eq "unwritable dir: reason"  "target-dir-not-writable"  "$(_reason "$_out")"
fi
chmod 700 "$uw"

echo "== the probe — the printed token and the returned status are ONE mapping =="
# The caller branches on the status while the operator reads the token; a drift between them is
# a wrong branch reported with the right words (or the reverse). Re-derived from the runs above.
_probe "$cap";                       eq "CAPABLE ⇒ 0"       "0" "$_rc"
_use_stub "$LN_COPY"; _probe "$nc"; _use_real
                                     eq "NOT_CAPABLE ⇒ 1"   "1" "$_rc"
_probe "$TMP/does-not-exist";        eq "INDETERMINATE ⇒ 2" "2" "$_rc"

# ---------------------------------------------------------------------------
# The installer end-to-end. Everything above is the primitive; these are the dispositions.
# ---------------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "install-board-hooks-capability-selftest: git not on PATH" >&2
    exit 1
fi

TOOLKIT="$(cd "$HERE/.." && pwd)"
_fresh_repo() {   # <name> → an ordinary checkout with no hooks installed
    local r="$TMP/repos/$1"
    rm -rf "$r"; mkdir -p "$r"; git init -q "$r"
    printf '%s' "$r"
}
_run() {   # <stub-dir|-> <args…> — run the BIN as a subprocess; sets _rc/_out/_err
    local stub="$1"; shift
    _rc=0
    if [ "$stub" = "-" ]; then
        _out="$(bash "$IBH" "$@" 2>"$TMP/run.err")" || _rc=$?
    else
        _out="$(PATH="$stub:$REAL_PATH" bash "$IBH" "$@" 2>"$TMP/run.err")" || _rc=$?
    fi
    _err="$(cat "$TMP/run.err")"
}
_installed() { find "$1/.git/hooks" -maxdepth 1 \( -name post-checkout -o -name pre-push \) | wc -l | tr -d ' '; }

echo "== installer — a CAPABLE seat is unchanged: symlinks, rc 0 =="
r="$(_fresh_repo capable)"
_run - "$r"
eq "rc"                       "0"    "$_rc"
eq "post-checkout is a symlink" "true" "$([ -L "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "pre-push is a symlink"      "true" "$([ -L "$r/.git/hooks/pre-push" ] && echo true || echo false)"
eq "…pointing at the toolkit source" "$TOOLKIT/hooks/post-checkout" \
   "$(readlink -- "$r/.git/hooks/post-checkout")"
eq "no probe residue in the hooks dir" "0" "$(_residue "$r/.git/hooks")"

echo "== installer — --allow-copies PERMITS the fallback, it does not SELECT it =="
# An operator carrying the flag in a shared script must not pin a capable seat to stale copies.
r="$(_fresh_repo capable-flagged)"
_run - --allow-copies "$r"
eq "rc is plain success"        "0"    "$_rc"
eq "still a symlink"            "true" "$([ -L "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "says nothing about copies"  "false" "$(has "COPY" "$_out")"

echo "== installer — NOT_CAPABLE refuses by default, installs NOTHING, and names the opt-in =="
r="$(_fresh_repo notcapable)"
_run "$LN_COPY" "$r"
eq "rc"                          "1" "$_rc"
eq "nothing installed"           "0" "$(_installed "$r")"
eq "stdout is silent"            ""  "$_out"
eq "the verdict is quoted"       "true" "$(has "VERDICT=NOT_CAPABLE" "$_err")"
eq "…with the measured reason"   "true" "$(has "ln-reported-success-but-result-is-not-a-symlink" "$_err")"
eq "names the opt-in flag"       "true" "$(has "--allow-copies" "$_err")"
eq "first line is self-contained (board-session-close quotes only that one)" "true" \
   "$(has "install-board-hooks: " "$(printf '%s\n' "$_err" | head -1)")"
eq "no probe residue left behind" "0" "$(_residue "$r/.git/hooks")"

echo "== installer — --allow-copies installs COPIES, reports them AS copies, and exits 3 =="
# The whole point of the card: there is no outcome that produces copies and reports what
# producing symlinks reports.
_run "$LN_COPY" --allow-copies "$r"
eq "rc is 3, NOT 0"                 "3"    "$_rc"
eq "post-checkout exists"           "true" "$([ -e "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "…and is NOT a symlink"          "false" "$([ -L "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "…carries the source's bytes"    "true" \
   "$(cmp -s "$TOOLKIT/hooks/post-checkout" "$r/.git/hooks/post-checkout" && echo true || echo false)"
eq "…and is executable (git ignores a hook that is not)" "true" \
   "$([ -x "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "both hooks installed"           "2"    "$(_installed "$r")"
eq "each line says COPY"            "true" "$(has "COPY $r/.git/hooks/post-checkout" "$_out")"
eq "the summary states the re-run obligation" "true" "$(has "AFTER EVERY TOOLKIT UPGRADE" "$_err")"
eq "…and never reads as a symlink install" "false" "$(has "-> $TOOLKIT/hooks/post-checkout" "$_out")"

echo "== installer — a copies install does not write THROUGH a previous symlink =="
# `cp src dst` with dst an existing symlink writes into the link's TARGET: re-installing over a
# symlink install would rewrite this toolkit's own hook source.
r="$(_fresh_repo overwrite)"
mkdir -p "$r/.git/hooks"
printf 'original\n' > "$TMP/link-target"
ln -s -- "$TMP/link-target" "$r/.git/hooks/post-checkout"
_run "$LN_COPY" --allow-copies "$r"
eq "the previous link's target is untouched" "original" "$(cat "$TMP/link-target")"
eq "…and the hook is now a real file"        "false"    "$([ -L "$r/.git/hooks/post-checkout" ] && echo true || echo false)"

echo "== installer — INDETERMINATE fails closed at rc 4, distinctly from NOT_CAPABLE =="
r="$(_fresh_repo indeterminate)"
_run "$RM_NOOP" "$r"
eq "rc"                              "4" "$_rc"
eq "nothing installed"               "0" "$(_installed "$r")"
eq "the verdict is quoted"           "true"  "$(has "VERDICT=INDETERMINATE" "$_err")"
eq "…with its own reason"            "true"  "$(has "source-unlink-failed" "$_err")"
eq "says it could not DETERMINE"     "true"  "$(has "could not DETERMINE" "$_err")"
eq "does NOT claim symlinks are unavailable" "false" "$(has "cannot create tracking symlinks" "$_err")"
eq "…and says so explicitly"         "true"  "$(has "NOT a finding that symlinks" "$_err")"

echo "== installer — --allow-copies does NOT unblock INDETERMINATE =="
# The flag opts into a KNOWN degradation. Letting it swallow an unknown state would re-mint,
# one size smaller, the information loss this whole change exists to end.
_run "$RM_NOOP" --allow-copies "$r"
eq "rc is still 4"        "4" "$_rc"
eq "still nothing installed" "0" "$(_installed "$r")"
eq "and it says why the flag does not apply" "true" "$(has "--allow-copies does not apply" "$_err")"

echo "== installer — the dry run answers the SAME verdict, and stdout stays the contract =="
r="$(_fresh_repo dryrun)"
_run "$LN_COPY" --check "$r"
eq "refuses (rc 1)"        "1" "$_rc"
eq "stdout empty on refusal" "" "$_out"
eq "nothing installed"     "0" "$(_installed "$r")"
_run "$LN_COPY" --check --allow-copies "$r"
eq "would-be copies install answers 3" "3" "$_rc"
eq "stdout is ONLY the target dir"     "$r/.git/hooks" "$_out"
eq "the warning is on stderr"          "true" "$(has "would install COPIES" "$_err")"
eq "still nothing installed"           "0" "$(_installed "$r")"
eq "and no probe residue"              "0" "$(_residue "$r/.git/hooks")"
_run - --check "$r"
eq "a capable seat's dry run is unchanged (rc 0)" "0" "$_rc"
eq "…and prints the target dir"                   "$r/.git/hooks" "$_out"

echo "== the standalone Windows check still RUNS on this seat =="
# `tests/install-board-hooks-capability-windows-check.sh` is a deliverable: it is handed to an
# agent on a real Windows seat, which is the surface neither this suite nor CI can reach. It is
# deliberately NOT a `*-selftest.sh` (the CI matrix-parity registry's population is exactly that
# glob, and a matrix entry with no matching file is reported as dangling), so nothing else would
# notice it rotting. Running it here is that guard: on this seat it takes its CAPABLE arm, which
# proves the script executes and self-reports — not that it says anything about Windows.
wc_rc=0
wc_out="$(bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wc_rc=$?
eq "the windows check runs clean on this seat" "0"    "$wc_rc"
eq "…and reports the seat's verdict"           "true" "$(has "SEAT VERDICT: VERDICT=" "$wc_out")"
eq "…having asserted the invariant"            "true" "$(has "TRACKS its source across a replacement" "$wc_out")"

echo "== installer — the usage line carries the flag it accepts =="
_run - --nope "$r"
eq "unknown option is still rc 2" "2" "$_rc"
eq "usage names --check"          "true" "$(has "[--check]" "$_err")"
eq "usage names --allow-copies"   "true" "$(has "[--allow-copies]" "$_err")"

_summary "install-board-hooks-capability-selftest"
