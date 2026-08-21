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
# unlink silently no-ops. THE TWO-READER cases need a second command stubbed as well, because
# the whole point of them is that the two readers answer differently and no single command can
# express that on Linux: a `cat` that resolves what the native reader cannot (paired with the
# snapshot `ln`, this is the `MSYS=winsymlinks:lnk` signature), a `cat` that fails to resolve
# what the native reader does, a `git` whose `hash-object` fatals, and a PATH on which `git` is
# genuinely absent. THE FAILED-READ cases need one more of each kind, because a read that FAILED
# and a read that SUCCEEDED and found nothing are the two states the probe must never confuse
# (card#6572): a `cat` that EXITS NON-ZERO on the probed entry, a `cat` that exits 0 having
# printed NOTHING, and an `ln -s` that makes a real but DANGLING link — the one case needing no
# stubbed reader at all, since neither reader can open an entry whose target does not exist.
# Two further stubs force paths a verdict cannot reach: an `ln` that is
# capable for the probe's destination and copies only for one named `post-checkout` (the sole way
# to red the installer's per-entry post-`ln` assertion, which by construction runs after a
# CAPABLE probe), and an `rm` that terminates the shell that ran it (the probe's signal path,
# which a race cannot test). ONE case is forced by a FIXTURE TOOLKIT rather than a `PATH` stub —
# an installer copy whose probe returns an UNMAPPED status — because the probe is an internal
# function and no stub of an external command can make it answer one. A stub is a simulation of
# the seat, never evidence about it: the standalone
# `tests/install-board-hooks-capability-windows-check.sh` is what a real Windows seat runs to
# confirm the actual behaviour, and it uses no stubs at all.
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
# _use_only <dir…> — a PATH that is ONLY these directories. Shadowing a command is not the same
# experiment as not having it: `git-read-failed` must be reachable by a git that is ABSENT.
_use_only() { PATH="$1"; hash -r; }
_use_real() { PATH="$REAL_PATH"; hash -r; }

# _stub_git <slot> <body…> — a `git` stub whose body reads the subcommand from `$sub`.
#
# IT OWNS THE `-C <dir>` SKIP, AND THAT IS THE POINT. Every git stub here shadows ONE subcommand
# and execs the real git for the rest, so each needs to know which subcommand it was handed — and
# the probe's read carries a leading `-C <dir>`, so `$1` is the flag and not the subcommand. The
# predecessor of this prologue matched `$1` alone and went blind the moment that flag was added:
# the arm each stub exists to force silently answered through the real git while the label still
# claimed otherwise. It was then written out VERBATIM in three stubs, i.e. three places for the
# next invocation change to go blind. It is one place now; a fourth git stub inherits it.
_stub_git() {
    local slot="$1"; shift
    _stub_dir "$slot" git \
        'sub="${1:-}"; if [ "$sub" = "-C" ]; then sub="${3:-}"; fi' \
        "$@"
}

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
# An `ln -s` that yields a HARD LINK (rc 0). It is the one seat on which TRUNCATING a file and
# REPLACING it (unlink + create, what `git pull` does to a hook source) give different answers —
# a hard link follows the first and never sees the second — so it is what pins any leg claiming
# to replace a source to actually doing it. The probe already refuses it at the `-L` clause.
LN_HARDLINK="$(_stub_dir ln-hardlink ln \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'exec /bin/ln -- "${args[0]}" "${args[1]}"')"
# An `rm` whose unlink silently does nothing — the probe cannot replace its own source, so the
# measurement never happens.
RM_NOOP="$(_stub_dir rm-noop rm 'exit 0')"
# An `ln -s` that is CAPABLE everywhere except on a destination named `post-checkout`, where it
# copies. It is what makes the installer's post-`ln` per-entry assertion able to fail at all: the
# probe (whose destination is `.ibhp<n>.d`) passes, so the install proceeds down the symlink
# branch, and the entry git will really dispatch is a copy — the exact disagreement between the
# stand-in the probe measured and the entry it stands in for.
LN_COPY_HOOK="$(_stub_dir ln-copy-hook ln \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'if [ "$(basename -- "${args[1]}")" = "post-checkout" ]; then' \
    '    rm -f -- "${args[1]}"; cp -- "${args[0]}" "${args[1]}"; exit 0' \
    'fi' \
    'exec /bin/ln -sf -- "${args[0]}" "${args[1]}"')"
# A `cat` that RESOLVES what the native reader cannot — the `MSYS=winsymlinks:lnk` signature,
# reproduced with the only two commands that can express it on Linux. Under that mode the
# emulation layer writes a Windows `.lnk` shortcut which its own `cat` follows to the LIVE
# source, while `git.exe` opens the file and reads shortcut bytes. Here: `LN_SNAPSHOT` gives the
# native reader a stale object (a link to a snapshot), and this `cat` answers for `<x>.d` by
# reading its sibling `<x>.s` — i.e. the live source, exactly as the layer's `cat` does. Paired,
# the two readers DISAGREE in the `lnk` direction, which no single-reader probe can see.
CAT_RESOLVE="$(_stub_dir cat-resolve cat \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'p="${args[0]:-}"' \
    'case "$p" in *.d) exec /usr/bin/cat -- "${p%.d}.s" ;; esac' \
    'exec /usr/bin/cat "$@"')"
# A `cat` that does NOT see through an entry the native reader does — the opposite direction.
# Hooks execute under that shell, so this fails closed too, and the token says which side.
CAT_STALE="$(_stub_dir cat-stale cat \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'p="${args[0]:-}"' \
    'case "$p" in *.d) printf "STALE\n"; exit 0 ;; esac' \
    'exec /usr/bin/cat "$@"')"
# A `cat` that FAILS on the probed entry — the shell's read not happening at all (an entry the
# process cannot open: permissions, a filesystem error, an emulation layer refusing the object).
# It is the reader-1 peer of GIT_FAIL below, and the pair is the point: a failed read is the
# measurement missing, and scoring it as content-that-did-not-match refuses a seat over a local
# fault. Its stdout is empty AND its status is 1 — only the status separates it from CAT_EMPTY.
CAT_FAIL="$(_stub_dir cat-fail cat \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'p="${args[0]:-}"' \
    'case "$p" in *.d) echo "cat: $p: Permission denied" >&2; exit 1 ;; esac' \
    'exec /usr/bin/cat "$@"')"
# A `cat` that SUCCEEDS and reads nothing — a genuine empty answer, and the negative control for
# the one above: an empty read is content that does not match, i.e. the seat's own answer, and a
# fix reading every empty result as a fault would turn a real NOT_CAPABLE into an INDETERMINATE
# the operator cannot act on.
CAT_EMPTY="$(_stub_dir cat-empty cat \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'p="${args[0]:-}"' \
    'case "$p" in *.d) exit 0 ;; esac' \
    'exec /usr/bin/cat "$@"')"
# An `ln -s` that makes a REAL symlink to a target that does not exist. Both readers then fail on
# the same real condition with neither of them stubbed — one broken entry, not a contrivance of
# two stubs.
LN_DANGLING="$(_stub_dir ln-dangling ln \
    'args=(); for a in "$@"; do case "$a" in -*) ;; *) args+=("$a") ;; esac; done' \
    'exec /bin/ln -s -- "${args[0]}.no-such-target" "${args[1]}"')"
# A `git` whose `hash-object` fatals — the read the native clause depends on, failing. A failed
# READ is not a measurement of the seat, so it must land on INDETERMINATE and never on
# NOT_CAPABLE. Every other git subcommand is the real one. (`$sub` — the subcommand read past a
# leading `-C <dir>` — comes from `_stub_git`, the one owner of that parse.)
GIT_FAIL="$(_stub_git git-fail \
    'if [ "$sub" = "hash-object" ]; then' \
    '    echo "fatal: could not open '"'"'x'"'"' for reading: Permission denied" >&2; exit 128' \
    'fi' \
    'exec /usr/bin/git "$@"')"
# A `git` whose `hash-object` answers a DIFFERENT hash on every call — so the native reader can
# never see the two probe paths as equal, while the shell's `cat` (the real one) resolves a real
# symlink that really does track. That pair — the probe refusing a seat whose actual dispatch
# follows the source — is the one no combination of real commands produces on Linux, and it is
# the branch the single Windows run exists to obtain. Every other subcommand is the real git.
GIT_FRESH_HASH="$(_stub_git git-fresh-hash \
    "n_file=\"$TMP/git-fresh-hash.n\"" \
    'if [ "$sub" = "hash-object" ]; then' \
    '    n="$(cat "$n_file" 2>/dev/null || echo 0)"; n=$((n + 1)); printf "%s" "$n" > "$n_file"' \
    '    printf "%040x\n" "$n"; exit 0' \
    'fi' \
    'exec /usr/bin/git "$@"')"
# A `git` whose FIRST `checkout` is the real one and every later one is a silent no-op — so the
# arbiter's control fires and nothing runs after the replacement. That is its `broken` outcome,
# which no race can produce on demand, and it is a distinct classification from `frozen`: nothing
# executed, so no content was observed and no pairing claim can be made from it.
GIT_ONE_CHECKOUT="$(_stub_git git-one-checkout \
    "n_file=\"\${IBH_CHECKOUT_COUNTER:-$TMP/git-one-checkout.n}\"" \
    'if [ "$sub" = "checkout" ]; then' \
    '    n="$(cat "$n_file" 2>/dev/null || echo 0)"; n=$((n + 1)); printf "%s" "$n" > "$n_file"' \
    '    if [ "$n" != 1 ]; then exit 0; fi' \
    'fi' \
    'exec /usr/bin/git "$@"')"
# A PATH on which git is genuinely ABSENT (not stubbed): the probe's other three external
# commands, and nothing else. `_use_only` — not `_use_stub` — is what makes it absence rather
# than shadowing.
NOGIT="$TMP/stubs/nogit"
mkdir -p "$NOGIT"
for _b in ln rm cat; do ln -s "/usr/bin/$_b" "$NOGIT/$_b"; done
# An `rm` that terminates the shell that invoked it — the only way to observe the probe's SIGNAL
# path deterministically (a real race is not a test). It stubs `rm` rather than `ln` for a
# measured reason: `$PPID` is the PROBE's shell only for a command the probe runs DIRECTLY, and
# its `ln` runs inside a command substitution, so an `ln` killer signals that substitution's own
# subshell instead — which reads back as an ordinary `ln-failed-rc143` NOT_CAPABLE and never
# reaches the trap at all. The source-replacement `rm` is the probe's one direct external call,
# and it lands mid-window with BOTH probe entries on disk. It fires ONCE per marker file and is a
# real `rm` thereafter: a killer that also killed the trap's own cleanup would prove nothing.
RM_KILL="$(_stub_dir rm-kill rm \
    "once=\"$TMP/rm-kill.fired\"" \
    'if [ ! -e "$once" ]; then : > "$once"; kill -TERM "$PPID"; exit 0; fi' \
    'exec /bin/rm "$@"')"

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
# `ctl_rc`, not the harness's `_rc`: these controls run before the first `_probe`/`_run`, and
# borrowing that variable here would leave a later assertion reading a status nothing set.
ctl_rc=0; _use_stub "$LN_FAIL"; ln -s -- "$ctl/src" "$ctl/fail-dst" 2>"$TMP/ctl-fail.err" || ctl_rc=$?; _use_real
eq "the fail-stub's 'ln -s' exits non-zero" "1" "$ctl_rc"
eq "…and creates no entry at all" "false" \
   "$(if [ -e "$ctl/fail-dst" ] || [ -L "$ctl/fail-dst" ]; then echo true; else echo false; fi)"
eq "…with its own words on stderr" "true" \
   "$(has "Operation not permitted" "$(cat "$TMP/ctl-fail.err")")"
# The snapshot stub gets its own directory: it litters a `stub-snapshot.dat` beside the source.
snapctl="$TMP/ctl-snap"; mkdir -p "$snapctl"; echo one > "$snapctl/src"
_use_stub "$LN_SNAPSHOT"; ln -s -- "$snapctl/src" "$snapctl/snap-dst"; _use_real
eq "the snapshot-stub's 'ln -s' DOES yield a symlink" "true" \
   "$([ -L "$snapctl/snap-dst" ] && echo true || echo false)"
eq "…but not one pointing at the source" "false" \
   "$([ "$(readlink -- "$snapctl/snap-dst")" = "$snapctl/src" ] && echo true || echo false)"
/bin/rm -f -- "$snapctl/src"; echo two > "$snapctl/src"
eq "…so REPLACING the source never reaches it (the property the probe measures)" "one" \
   "$(cat "$snapctl/snap-dst")"
# The hard-link stub, and with it the TRUNCATE-vs-REPLACE distinction the whole card turns on.
hlctl="$TMP/ctl-hardlink"; mkdir -p "$hlctl"; echo one > "$hlctl/src"
_use_stub "$LN_HARDLINK"; ln -s -- "$hlctl/src" "$hlctl/hl-dst"; _use_real
eq "the hardlink-stub's 'ln -s' yields a NON-symlink" "false" \
   "$([ -L "$hlctl/hl-dst" ] && echo true || echo false)"
eq "…sharing the source's inode (a hard link, not a copy)" "true" \
   "$([ "$hlctl/hl-dst" -ef "$hlctl/src" ] && echo true || echo false)"
printf 'two\n' > "$hlctl/src"
eq "…so TRUNCATING the source in place does reach it" "two" "$(cat "$hlctl/hl-dst")"
/bin/rm -f -- "$hlctl/src"; printf 'three\n' > "$hlctl/src"
eq "…while REPLACING it (unlink+create, what 'git pull' does) does NOT" "two" "$(cat "$hlctl/hl-dst")"
catctl="$TMP/ctl-cat"; mkdir -p "$catctl"
printf 'live\n' > "$catctl/x.s"; printf 'stale\n' > "$catctl/x.d"
_use_stub "$CAT_RESOLVE"
eq "the resolve-stub's 'cat' answers a .d path with its .s sibling" "live" "$(cat -- "$catctl/x.d")"
eq "…and is the real 'cat' for every other path"                    "live" "$(cat -- "$catctl/x.s")"
_use_stub "$CAT_STALE"
eq "the stale-stub's 'cat' answers a .d path with neither file's bytes" "STALE" "$(cat -- "$catctl/x.d")"
eq "…and is the real 'cat' for every other path"                       "live" "$(cat -- "$catctl/x.s")"
_use_stub "$CAT_FAIL"
catfail_rc=0
cat -- "$catctl/x.d" >"$TMP/ctl-cat-fail.out" 2>"$TMP/ctl-cat-fail.err" || catfail_rc=$?
eq "the fail-stub's 'cat' exits non-zero on a .d path" "1" "$catfail_rc"
eq "…printing nothing on stdout (only the STATUS separates it from an empty read)" "" \
   "$(cat "$TMP/ctl-cat-fail.out")"
eq "…with its own words on stderr" "true" "$(has "Permission denied" "$(cat "$TMP/ctl-cat-fail.err")")"
eq "…and is the real 'cat' for every other path" "live" "$(cat -- "$catctl/x.s")"
_use_stub "$CAT_EMPTY"
catempty_rc=0
catempty_out="$(cat -- "$catctl/x.d" 2>/dev/null)" || catempty_rc=$?
eq "the empty-stub's 'cat' SUCCEEDS on a .d path" "0" "$catempty_rc"
eq "…having read nothing"                        ""  "$catempty_out"
eq "…and is the real 'cat' for every other path" "live" "$(cat -- "$catctl/x.s")"
_use_real
eq "…and OFF the stub PATH, 'cat' reads the file it is given" "stale" "$(cat -- "$catctl/x.d")"
# The dangling-link stub, and the two reads it breaks — witnessed here so the probe leg below is
# not the first place either failure is observed.
dngctl="$TMP/ctl-dangling"; mkdir -p "$dngctl"; printf 'one\n' > "$dngctl/src"
_use_stub "$LN_DANGLING"; ln -s -- "$dngctl/src" "$dngctl/dng-dst"; _use_real
eq "the dangling-stub's 'ln -s' DOES yield a symlink" "true" \
   "$([ -L "$dngctl/dng-dst" ] && echo true || echo false)"
eq "…whose target does not exist" "false" \
   "$([ -e "$dngctl/dng-dst" ] && echo true || echo false)"
dng_cat_rc=0; cat -- "$dngctl/dng-dst" >/dev/null 2>&1 || dng_cat_rc=$?
eq "…so the shell's reader fails on it" "1" "$dng_cat_rc"
dng_git_rc=0
git -C "$dngctl" hash-object --no-filters -- "$dngctl/dng-dst" >/dev/null 2>&1 || dng_git_rc=$?
eq "…and git's reader fails on it too (rc 128)" "128" "$dng_git_rc"
gitctl_rc=0
_use_stub "$GIT_FAIL"
git hash-object --no-filters -- "$catctl/x.s" >/dev/null 2>"$TMP/ctl-git.err" || gitctl_rc=$?
eq "the git-stub's 'hash-object' fatals (rc 128)" "128" "$gitctl_rc"
gitctlc_rc=0
git -C "$catctl" hash-object --no-filters -- "$catctl/x.s" >/dev/null 2>&1 || gitctlc_rc=$?
eq "…including through the '-C <dir>' form the probe uses" "128" "$gitctlc_rc"
eq "…with git's own fatal on stderr" "true" "$(has "fatal:" "$(cat "$TMP/ctl-git.err")")"
eq "…while another subcommand is still the real git" "true" "$(has "git version" "$(git --version)")"
_use_stub "$GIT_FRESH_HASH"
fh1="$(git hash-object --no-filters -- "$catctl/x.s")"
fh2="$(git hash-object --no-filters -- "$catctl/x.s")"
fh3="$(git -C "$catctl" hash-object --no-filters -- "$catctl/x.s")"
fhv="$(git --version)"
_use_real
eq "the fresh-hash stub answers the SAME file with a different hash each call" "false" \
   "$([ "$fh1" = "$fh2" ] && echo true || echo false)"
eq "…each answer non-empty (a failed read is a different experiment)" "true" \
   "$([ -n "$fh1" ] && [ -n "$fh2" ] && echo true || echo false)"
eq "…including through the '-C <dir>' form the probe uses" "true" \
   "$([ -n "$fh3" ] && [ "$fh3" != "$fh2" ] && echo true || echo false)"
eq "…while another subcommand is still the real git" "true" "$(has "git version" "$fhv")"
# The one-checkout stub, controlled against a throwaway repo and its OWN counter file, so the
# control does not consume the count the leg that relies on it needs.
ckctl="$TMP/ctl-checkout"; git init -q "$ckctl"
git -C "$ckctl" -c user.email=t@invalid -c user.name=t commit -q --allow-empty -m x
git -C "$ckctl" branch cb1; git -C "$ckctl" branch cb2
_use_stub "$GIT_ONE_CHECKOUT"
IBH_CHECKOUT_COUNTER="$TMP/ctl-checkout.n" git -C "$ckctl" checkout -q cb1 2>/dev/null || :
ck_first="$(git -C "$ckctl" rev-parse --abbrev-ref HEAD)"
IBH_CHECKOUT_COUNTER="$TMP/ctl-checkout.n" git -C "$ckctl" checkout -q cb2 2>/dev/null || :
ck_second="$(git -C "$ckctl" rev-parse --abbrev-ref HEAD)"
_use_real
eq "the one-checkout stub performs the FIRST checkout for real" "cb1" "$ck_first"
eq "…and silently no-ops every later one"                       "cb1" "$ck_second"
# …and with its counter PRE-SEEDED past the first, the same stub no-ops EVERY checkout — which is
# what makes the arbiter's `control-failed` state (the hook does not fire even BEFORE the source
# is replaced) forceable without a fourth git stub. Witnessed here, on the same throwaway repo,
# because "no checkout ran" is otherwise indistinguishable from "the stub never took effect".
printf '1' > "$TMP/ctl-checkout-preseed.n"
_use_stub "$GIT_ONE_CHECKOUT"
IBH_CHECKOUT_COUNTER="$TMP/ctl-checkout-preseed.n" git -C "$ckctl" checkout -q cb2 2>/dev/null || :
ck_preseeded="$(git -C "$ckctl" rev-parse --abbrev-ref HEAD)"
_use_real
eq "…and with its counter pre-seeded, no-ops the FIRST checkout too" "cb1" "$ck_preseeded"
_use_only "$NOGIT"
eq "on the NOGIT path, git is genuinely absent" "false" \
   "$(command -v git >/dev/null 2>&1 && echo true || echo false)"
eq "…while ln/rm/cat are still there (so the probe reaches its native read)" "true" \
   "$(command -v ln >/dev/null 2>&1 && command -v rm >/dev/null 2>&1 && command -v cat >/dev/null 2>&1 && echo true || echo false)"
_use_real
eq "…and back on the real PATH, git resolves again" "true" \
   "$(command -v git >/dev/null 2>&1 && echo true || echo false)"
hookctl="$TMP/ctl-hook"; mkdir -p "$hookctl"; echo one > "$hookctl/src"
_use_stub "$LN_COPY_HOOK"
ln -sf "$hookctl/src" "$hookctl/other"; ln -sf "$hookctl/src" "$hookctl/post-checkout"
_use_real
eq "the hook-stub's 'ln -s' is capable for an ordinary destination" "true" \
   "$([ -L "$hookctl/other" ] && echo true || echo false)"
eq "…and yields a COPY for one named post-checkout" "false" \
   "$([ -L "$hookctl/post-checkout" ] && echo true || echo false)"
eq "…carrying the source's bytes" "one" "$(cat "$hookctl/post-checkout")"
# The kill stub is witnessed against a THROWAWAY shell, never this one: in `bash -c 'cmd; cmd'`
# the first command is that shell's child, so the stub's $PPID is it and not the selftest. The
# `2>/dev/null` on the GROUP is what suppresses this shell's own `Terminated` job message —
# emitted by the parent, so redirecting the inner command's stderr would not catch it.
kill_rc=0
_use_stub "$RM_KILL"
{ bash -c 'rm -f -- "$1"; echo alive' _ "$ctl/kill-victim" >"$TMP/ctl-kill.out" 2>&1 \
    || kill_rc=$?; } 2>/dev/null
_use_real
eq "the kill-stub terminates the shell that ran it (SIGTERM)" "143" "$kill_rc"
eq "…before that shell can reach its next command" "false" \
   "$(has "alive" "$(cat "$TMP/ctl-kill.out")")"
# …and it is a REAL `rm` from here on, which is what lets the trap it interrupts clean up. The
# marker is reset so the one firing left is the probe's.
_use_stub "$RM_KILL"; printf 'x\n' > "$ctl/rm-me"; rm -f -- "$ctl/rm-me"; _use_real
eq "…and removes for real on every later call" "false" \
   "$([ -e "$ctl/rm-me" ] && echo true || echo false)"
/bin/rm -f -- "$TMP/rm-kill.fired"
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

echo "== the probe — the two readers DISAGREE: the winsymlinks:lnk signature =="
# The defect this arm exists for: read only through the shell and this seat answers CAPABLE,
# because the emulation layer resolves an object `git.exe` reads as opaque bytes. The verdict
# must be NOT_CAPABLE and the token must name WHICH reader failed — one run on a real seat is
# all there is, so an unattributable refusal would waste it.
rd="$TMP/readers-disagree"; mkdir -p "$rd"
PATH="$CAT_RESOLVE:$LN_SNAPSHOT:$REAL_PATH"; hash -r
_probe "$rd"; _use_real
eq "verdict" "NOT_CAPABLE"                                  "$(_verdict "$_out")"
eq "rc"      "1"                                            "$_rc"
eq "reason"  "readers-disagree-native-git-does-not-track"   "$(_reason "$_out")"
eq "…and NOT the both-readers-agree token (the direction is the finding)" "false" \
   "$(has "REASON=link-does-not-track-source-across-replacement" "$_out")"
eq "leaves no residue" "0" "$(_residue "$rd")"

echo "== the probe — the OTHER direction is refused too, and says so =="
# git sees through the entry and the shell does not. Hooks execute under that shell, so this
# fails closed as well; the two are distinguished only by the token.
rs="$TMP/readers-disagree-shell"; mkdir -p "$rs"
_use_stub "$CAT_STALE"; _probe "$rs"; _use_real
eq "verdict" "NOT_CAPABLE"                             "$(_verdict "$_out")"
eq "rc"      "1"                                       "$_rc"
eq "reason"  "readers-disagree-shell-does-not-track"   "$(_reason "$_out")"
eq "leaves no residue" "0" "$(_residue "$rs")"

echo "== the probe — a FAILED native read is INDETERMINATE, never NOT_CAPABLE =="
# An absent or erroring `git hash-object` means the measurement did not happen. Scoring it as
# "does not track" would report a fact about the seat that was never established — and would
# route the operator to --allow-copies, i.e. into a degradation, over a local git fault.
gf="$TMP/git-fail"; mkdir -p "$gf"
_use_stub "$GIT_FAIL"; _probe "$gf"; _use_real
eq "hash-object fatals: verdict" "INDETERMINATE"    "$(_verdict "$_out")"
eq "hash-object fatals: rc"      "2"                "$_rc"
eq "hash-object fatals: reason"  "git-read-failed"  "$(_reason "$_out")"
eq "…and it is not reported as a measured absence" "false" "$(has "NOT_CAPABLE" "$_out")"
eq "leaves no residue" "0" "$(_residue "$gf")"
ga="$TMP/git-absent"; mkdir -p "$ga"
_use_only "$NOGIT"; _probe "$ga"; _use_real
eq "git absent from PATH: verdict" "INDETERMINATE"   "$(_verdict "$_out")"
eq "git absent from PATH: rc"      "2"               "$_rc"
eq "git absent from PATH: reason"  "git-read-failed" "$(_reason "$_out")"
eq "leaves no residue" "0" "$(_residue "$ga")"

echo "== the probe — a FAILED SHELL read is INDETERMINATE too: ONE rule, BOTH readers =="
# The rule above is not the native reader's rule, it is the probe's. `cat` swallowing its status
# made an entry the shell cannot OPEN indistinguishable from one it read and found other content
# in — so the pair read `yes:no`, the seat was refused NOT_CAPABLE with a token naming a mechanism
# nobody measured (`the shell does not track`), and the operator was routed into --allow-copies
# over a local fault. The TOKEN asserted here is what says the diagnosis changed, not the verdict.
sf="$TMP/shell-fail"; mkdir -p "$sf"
_use_stub "$CAT_FAIL"; _probe "$sf"; _use_real
eq "cat fails: verdict" "INDETERMINATE"      "$(_verdict "$_out")"
eq "cat fails: rc"      "2"                  "$_rc"
eq "cat fails: reason"  "shell-read-failed"  "$(_reason "$_out")"
eq "…spelled on the one-line contract, not merely in the probed path" "true" \
   "$(has "REASON=shell-read-failed" "$_out")"
eq "…and it is not reported as a measured absence" "false" "$(has "NOT_CAPABLE" "$_out")"
eq "…nor with a reader-disagreement token, which asserts a measurement nobody made" "false" \
   "$(has "readers-disagree" "$_out")"
eq "leaves no residue" "0" "$(_residue "$sf")"
# The baseline on the SAME directory: off the stub it is CAPABLE, so the refusal above is the
# stub's doing and not this tree's.
_probe "$sf"
eq "…while the same directory with a working 'cat' is CAPABLE" "CAPABLE" "$(_verdict "$_out")"

echo "== the probe — the OTHER row the acceptance change moves: git measured 'no', cat FAILED =="
# `no:unmeasured`. This is the second of the two rows whose exit status this change moves, and
# it is the one that reads as an OVER-refusal, so it is pinned deliberately rather than left to
# look accidental. The native reader — the authoritative one, the binary that dispatches hooks —
# has MEASURED that the entry does not track, and `no:no` and `no:yes` both map to NOT_CAPABLE,
# so the reader that failed could not have changed the verdict. The probe refuses INDETERMINATE
# anyway: a verdict is not assembled out of a measurement that did not happen, and the operator
# loses the copies escape hatch on this seat until the local fault is fixed. That is exactly the
# precedent card#6527 set in the mirror image — a failed NATIVE read short-circuited to
# `git-read-failed` even when the shell had already answered `no` — and the symmetry is the
# point: one rule, both readers, including where the rule costs something.
#   PRE-FIX on this same pair: rc 1, REASON=link-does-not-track-source-across-replacement, i.e.
#   the seat was told it cannot symlink on the strength of one measurement and one silence.
nu="$TMP/native-no-shell-fail"; mkdir -p "$nu"
PATH="$CAT_FAIL:$LN_SNAPSHOT:$REAL_PATH"; hash -r
_probe "$nu"; _use_real
eq "verdict" "INDETERMINATE"                         "$(_verdict "$_out")"
eq "rc"      "2"                                     "$_rc"
eq "reason"  "shell-read-failed"                     "$(_reason "$_out")"
eq "…and NOT the both-readers-agree token it used to carry" "false" \
   "$(has "link-does-not-track-source-across-replacement" "$_out")"
eq "…nor NOT_CAPABLE on the strength of one reader" "false" "$(has "NOT_CAPABLE" "$_out")"
eq "leaves no residue" "0" "$(_residue "$nu")"

echo "== the probe — an EMPTY shell read is still a MEASURED absence, not a failed read =="
# The other half of the same rule, and the half a careless fix breaks: `cat` exited 0 and read
# nothing, which IS the seat answering — the entry does not deliver the replaced source. That is
# NOT_CAPABLE with the disagreement token, exactly as any other non-matching content; making it
# INDETERMINATE would replace a verdict the operator can act on with one they cannot.
se="$TMP/shell-empty"; mkdir -p "$se"
_use_stub "$CAT_EMPTY"; _probe "$se"; _use_real
eq "cat reads nothing: verdict" "NOT_CAPABLE"                            "$(_verdict "$_out")"
eq "cat reads nothing: rc"      "1"                                      "$_rc"
eq "cat reads nothing: reason"  "readers-disagree-shell-does-not-track"  "$(_reason "$_out")"
eq "…and NOT the failed-read token" "false" "$(has "REASON=shell-read-failed" "$_out")"
eq "leaves no residue" "0" "$(_residue "$se")"

echo "== the probe — when BOTH reads fail, the token names both =="
# One broken entry and no stubbed reader: a real symlink whose target does not exist. Answering
# it `git-read-failed` would be true and incomplete — the operator fixes git, re-runs, and is
# refused again by the reader nobody named.
bf="$TMP/both-fail"; mkdir -p "$bf"
_use_stub "$LN_DANGLING"; _probe "$bf"; _use_real
eq "both reads fail: verdict" "INDETERMINATE"     "$(_verdict "$_out")"
eq "both reads fail: rc"      "2"                 "$_rc"
eq "both reads fail: reason"  "both-reads-failed" "$(_reason "$_out")"
eq "…not the reader that happens to be named first" "false" "$(has "REASON=git-read-failed" "$_out")"
eq "…and not a measured absence" "false" "$(has "NOT_CAPABLE" "$_out")"
eq "leaves no residue" "0" "$(_residue "$bf")"

echo "== the probe — a read that SUCCEEDS with the replaced content is untouched by all of this =="
# The happy path is what must not have moved: a real `ln`, a real `cat`, a real `git`.
hp="$TMP/happy"; mkdir -p "$hp"
_probe "$hp"
eq "verdict"                  "CAPABLE" "$(_verdict "$_out")"
eq "rc"                       "0"       "$_rc"
eq "reason"                   "ok"      "$(_reason "$_out")"
eq "no INDETERMINATE anywhere in the line" "false" "$(has "INDETERMINATE" "$_out")"
eq "writes nothing to stderr" ""        "$_err"
eq "leaves no residue"        "0"       "$(_residue "$hp")"

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

echo "== the probe — a SIGNAL leaves no residue either ('removed on every path' is the claim) =="
# The probe writes into a directory it does not own, so cleanup is a contract rather than
# tidiness — and a claim of "every path" that excludes the signal path is a false claim, not a
# small one: `--check` performs this same write on a directory the operator never asked to have
# written. The stub kills the probe's shell between the source write and the cleanup tail, which
# is the whole window.
sig="$TMP/sig"; mkdir -p "$sig"
_use_stub "$RM_KILL"; { _probe "$sig"; } 2>/dev/null; _use_real
eq "the probe dies on the signal (rc 143)" "143" "$_rc"
eq "…and still leaves no .ibhp residue" "0" "$(_residue "$sig")"
/bin/rm -f -- "$TMP/rm-kill.fired"

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

echo "== installer — the per-entry post-'ln' assertion catches what the probe's stand-in cannot =="
# The probe measures a `.ibhp<n>.d` stand-in; THIS asserts the entry git will really dispatch. It
# is the last backstop of the whole invariant, and the only stub that can red it is one that is
# capable for the probe's destination and copies for the hook's — anything cruder refuses at the
# probe and never reaches this branch.
r="$(_fresh_repo entry-contradicts-probe)"
_run "$LN_COPY_HOOK" "$r"
eq "rc is the refusal"                    "1"    "$_rc"
eq "it names the contradiction"           "true" "$(has "reported success but $r/.git/hooks/post-checkout is not a symlink" "$_err")"
eq "…and says the two disagree"           "true" "$(has "the install is NOT trustworthy" "$_err")"
eq "…and names the deliberate opt-in"     "true" "$(has "--allow-copies" "$_err")"
eq "the entry is left in place, as stated" "true" \
   "$([ -e "$r/.git/hooks/post-checkout" ] && echo true || echo false)"
eq "…and it really is not a symlink"      "false" \
   "$([ -L "$r/.git/hooks/post-checkout" ] && echo true || echo false)"

echo "== installer — a refusal is ALL-OR-NOTHING: no hook is written before the SET is checked =="
# A guard that refused mid-loop had already installed the earlier hooks: rc 1 (a refusal) with a
# copy on disk, and the rc-3 summary that carries the `rm` recipe and the re-run obligation never
# printed. The operator's own hook is the natural way in — it is the second of the two.
r="$(_fresh_repo partial)"
mkdir -p "$r/.git/hooks"
printf '#!/bin/sh\n# a hook the operator wrote\n' > "$r/.git/hooks/pre-push"
_run "$LN_COPY" --allow-copies "$r"
eq "rc is the refusal"                  "1"    "$_rc"
eq "it refuses the operator's own hook" "true" "$(has "refusing to overwrite an existing non-symlink hook" "$_err")"
eq "NOTHING was installed for the hook it had not reached yet" "false" \
   "$(if [ -e "$r/.git/hooks/post-checkout" ] || [ -L "$r/.git/hooks/post-checkout" ]; then echo true; else echo false; fi)"
eq "…and no COPY was reported"          "false" "$(has "COPY" "$_out")"
eq "the operator's hook is untouched"   "true"  "$(has "a hook the operator wrote" "$(cat "$r/.git/hooks/pre-push")")"
# The same set on a CAPABLE seat: the symlink branch refuses whole too (it was benign there —
# `ln -sf` is idempotent — but the refusal is one guard, not one per branch).
r="$(_fresh_repo partial-capable)"
mkdir -p "$r/.git/hooks"
printf '#!/bin/sh\n# a hook the operator wrote\n' > "$r/.git/hooks/pre-push"
_run - "$r"
eq "capable seat: rc is the refusal" "1" "$_rc"
eq "…and post-checkout was not symlinked" "false" \
   "$(if [ -e "$r/.git/hooks/post-checkout" ] || [ -L "$r/.git/hooks/post-checkout" ]; then echo true; else echo false; fi)"

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

echo "== installer — a FAILED SHELL read refuses at rc 4 and is NOT offered --allow-copies =="
# The disposition is what the defect actually cost: the NOT_CAPABLE refusal prints the flag as
# the remedy, so a shell read that merely FAILED handed the operator a permanent pin to stale
# hook copies as the fix for a local fault. Asserted on the words, not on the status alone.
# The fixture's name is deliberately NOT the token: the NOT_CAPABLE refusal quotes the repo
# PATH, so a repo named `shell-read-failed` satisfies the reason assertion below on every
# verdict — watched, on the unfixed installer, to pass while everything around it failed.
r="$(_fresh_repo catfail)"
_run "$CAT_FAIL" "$r"
eq "rc"                                      "4"     "$_rc"
eq "nothing installed"                       "0"     "$(_installed "$r")"
eq "the verdict is quoted"                   "true"  "$(has "VERDICT=INDETERMINATE" "$_err")"
eq "…with the reader-specific reason"        "true"  "$(has "REASON=shell-read-failed" "$_err")"
eq "says it could not DETERMINE"             "true"  "$(has "could not DETERMINE" "$_err")"
eq "does NOT claim symlinks are unavailable" "false" "$(has "cannot create tracking symlinks" "$_err")"
eq "…and never offers the copies opt-in as the remedy" "false" \
   "$(has "install-board-hooks --allow-copies $r" "$_err")"
eq "…it says the flag does not apply instead" "true" "$(has "--allow-copies does not apply" "$_err")"
eq "…and the remediation names a READER, not git alone" "true" \
   "$(has "a reader — git or the shell — that cannot read" "$_err")"
_run "$CAT_FAIL" --allow-copies "$r"
eq "carrying the flag does not unblock it"   "4" "$_rc"
eq "…and still installs nothing"             "0" "$(_installed "$r")"

echo "== installer — a probe KILLED before it reports is refused without inventing a reason =="
# The rc-4 message quotes the probe's one-line verdict, and on this path there is none: the
# probe's own TERM trap exits 143 BEFORE it reports, so the refusal rendered "…symlinks ()." and
# then named four local faults, not one of which can be the cause. That is a refusal the operator
# cannot act on, and the fail-closed default (commit 2) is what made this arm reachable. Only the
# words change here — same arm, same rc 4, same vocabulary.
r="$(_fresh_repo probe-killed)"
_run "$RM_KILL" "$r"
eq "rc is still the INDETERMINATE refusal" "4" "$_rc"
eq "nothing installed"                     "0" "$(_installed "$r")"
eq "it no longer quotes an empty verdict"  "false" "$(has "tracking symlinks ()." "$_err")"
eq "…it says the probe never reported"     "true"  "$(has "exited 143 without reporting" "$_err")"
eq "…and drops the fault list none of whose entries can be the cause" "false" \
   "$(has "Fix the reason named above" "$_err")"
/bin/rm -f -- "$TMP/rm-kill.fired"
# The other half of the same branch, so this is a case split and not a deletion: a refusal that
# DOES carry a reason token keeps the fault list, unchanged.
_run "$RM_NOOP" "$r"
eq "a reported INDETERMINATE still names its reason" "true" "$(has "source-unlink-failed" "$_err")"
eq "…and still carries the fault list"               "true" "$(has "Fix the reason named above" "$_err")"

echo "== installer — the native read is pinned to the ENTRY's dir, not the caller's cwd =="
# `git hash-object` resolves a repository context from ITS OWN cwd, and a BROKEN context there is
# fatal — rc 128 → `git-read-failed` → INDETERMINATE → the whole install refuses at rc 4, naming
# faults that are none of them the cause, so the operator re-runs from the same cwd forever. The
# measured way in is a `.git` GITFILE naming a directory that does not exist. Symlink capability
# is a property of the probed DIRECTORY; where the caller happens to be standing must not enter.
bad_cwd="$TMP/broken-context"; mkdir -p "$bad_cwd"
printf 'gitdir: %s\n' "$TMP/no-such-git-dir" > "$bad_cwd/.git"
printf 'x\n' > "$TMP/hashme"
# POSITIVE CONTROL: the context really is fatal to an unpinned read from there, and really is not
# to a pinned one. Without this the assertions below pass on a cwd that was never broken.
bc_rc=0; ( cd "$bad_cwd" && git hash-object --no-filters -- "$TMP/hashme" ) >/dev/null 2>&1 || bc_rc=$?
eq "the broken cwd fatals a BARE 'git hash-object' (rc 128)" "128" "$bc_rc"
bcp_rc=0; ( cd "$bad_cwd" && git -C "$TMP" hash-object --no-filters -- "$TMP/hashme" ) >/dev/null 2>&1 || bcp_rc=$?
eq "…while the same read pinned with -C answers"             "0"   "$bcp_rc"
bcv_rc=0
bcv_out="$( cd "$bad_cwd" && bash -c 'source "$1"; _ibh_symlink_probe "$2"' _ "$IBH" "$cap" )" || bcv_rc=$?
eq "the probe still answers CAPABLE from that cwd" "CAPABLE" "$(_verdict "$bcv_out")"
eq "…at rc 0"                                      "0"       "$bcv_rc"
r="$(_fresh_repo broken-context)"
bci_rc=0; ( cd "$bad_cwd" && bash "$IBH" "$r" ) >/dev/null 2>"$TMP/run.err" || bci_rc=$?
eq "…and the install from that cwd succeeds"       "0"       "$bci_rc"
eq "…having installed both hooks"                  "2"       "$(_installed "$r")"

echo "== installer — an UNEXPECTED probe status is REFUSED, never installed on =="
# THE DEFAULT WAS FAIL-OPEN. The dispatch enumerated rc 2 (INDETERMINATE) and rc 1
# (NOT_CAPABLE) and let every OTHER status fall through to the capable install path — so a
# status nobody mapped installed symlinks on the strength of a measurement that never said
# CAPABLE. Those statuses are not hypothetical: the probe's own INT/TERM traps exit 130/143,
# and a signal the traps do not catch (SIGHUP, SIGKILL) reads back off the command
# substitution as 129/137. The default is now the EXISTING exit-4 refusal — no new message,
# no new verdict, no new exit status.
#
# Forcing it needs the PROBE to answer something else, and no PATH stub can do that: the probe
# is an internal function, not an external command. So a FIXTURE TOOLKIT is built — a copy of
# the installer whose one-tail mapping returns 3 where it returned 0, beside a copy of the hook
# sources — and the installer is run FROM it. The shipped tree is never edited.
fx="$TMP/fixture-probe-rc3"
mkdir -p "$fx/bin"
cp -R "$TOOLKIT/hooks" "$fx/hooks"
sed 's/^\(        CAPABLE)     return \)0\( ;;\)$/\13\2/' "$IBH" > "$fx/bin/install-board-hooks"
chmod +x "$fx/bin/install-board-hooks"
# POSITIVE CONTROL, the same bar every stub above meets: the fixture must actually produce the
# unexpected status, and must do it on a seat that is otherwise CAPABLE. Without this, the rc-4
# assertion below is satisfied by a fixture that broke the script some other way — a refusal
# for the wrong reason, which is the failure mode this file exists to keep out.
eq "the fixture differs from the shipped installer by exactly one line" "1" \
   "$(diff "$IBH" "$fx/bin/install-board-hooks" | grep -c '^<')"
fxp_rc=0
fxp_out="$(bash -c 'source "$1"; _ibh_symlink_probe "$2"' _ "$fx/bin/install-board-hooks" "$TMP")" || fxp_rc=$?
eq "…and its probe returns the unexpected status 3"                  "3"       "$fxp_rc"
eq "…while still reporting CAPABLE (so a fall-through WOULD install)" "CAPABLE" "$(_verdict "$fxp_out")"
r="$(_fresh_repo unexpected-rc)"
_rc=0
_out="$(bash "$fx/bin/install-board-hooks" "$r" 2>"$TMP/run.err")" || _rc=$?
_err="$(cat "$TMP/run.err")"
eq "rc"                "4" "$_rc"
eq "nothing installed" "0" "$(_installed "$r")"
eq "it takes the EXISTING indeterminate refusal, not a new one" "true" \
   "$(has "could not DETERMINE" "$_err")"
eq "no probe residue"  "0" "$(_residue "$r/.git/hooks")"

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
# Its END-TO-END leg is the one that stops inferring dispatch from a read, so its presence is
# asserted too — a rot that silently dropped it would leave the seat run answering the same
# question twice.
eq "…and RAN the end-to-end dispatch arbiter"  "true" "$(has "DISPATCH RESULT: tracks" "$wc_out")"
eq "…reporting the pair on one line"           "true" \
   "$(has "SEAT DISPATCH: tracks — probe says tracking=yes, real git dispatch says tracking=yes" "$wc_out")"
# AND ITS NOT_CAPABLE ARM IS EXECUTED ONCE, HERE, BEFORE THE REAL SEAT IS SPENT. That arm — and
# the arbiter's `frozen` classification — is the branch a Windows seat takes, and there is one
# Windows run to spend: shipping a branch nothing has ever executed risks spending it on a
# scripting error instead of the measurement. The stub makes this a simulation, so it is
# evidence that the BRANCH RUNS, never evidence about Windows; the script itself remains
# stub-free, and this PATH is imposed by the caller for one invocation.
wcn_rc=0
wcn_out="$(PATH="$LN_COPY:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wcn_rc=$?
eq "its NOT_CAPABLE arm runs clean under a forced incapable seat" "0" "$wcn_rc"
eq "…reporting that verdict"       "true" "$(has "SEAT VERDICT: VERDICT=NOT_CAPABLE" "$wcn_out")"
eq "…and the arbiter measures a FROZEN dispatch, agreeing with the probe" "true" \
   "$(has "SEAT DISPATCH: frozen — probe says tracking=no, real git dispatch says tracking=no" "$wcn_out")"
# AND ITS INDETERMINATE ARM, which had never executed: the seven paths this file drives the
# check down all land on CAPABLE or NOT_CAPABLE, so its rc-4 disposition and the NOTE that tells
# the operator what to fix were both shipping unrun. The NOTE is also a THIRD restatement of the
# installer's own rc-4 remediation (the installer's text, this file's text, docs/HOOKS.md's
# INDETERMINATE row), and a restatement with neither a delete nor a guard is the defect — so the
# shared fault phrase is asserted in BOTH files here: reword the installer and the count reds;
# let the NOTE drift and the substring reds.
IBH_FAULT_PHRASE="a reader — git or the shell — that cannot read"
wci_rc=0
wci_out="$(PATH="$CAT_FAIL:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wci_rc=$?
eq "its INDETERMINATE arm runs clean under a seat whose shell cannot read the entry" "0" "$wci_rc"
eq "…reporting that verdict, with the reader-specific token"  "true" \
   "$(has $'SEAT VERDICT: VERDICT=INDETERMINATE DIR=' "$wci_out")"
eq "…naming the reader that failed"                           "true" \
   "$(has $'REASON=shell-read-failed\n' "$wci_out")"
eq "…and asserting the rc-4 disposition on that seat"         "true" \
   "$(has "INDETERMINATE ⇒ the default run fails closed with rc 4" "$wci_out")"
eq "…while claiming NOTHING about what dispatch delivers"     "false" \
   "$(has "THIS IS THE FINDING" "$wci_out")"
eq "the installer's rc-4 remediation spells the shared fault phrase exactly once" "1" \
   "$(grep -c -- "$IBH_FAULT_PHRASE" "$IBH" || true)"
eq "…and this check's source spells the SAME one, exactly once"  "1" \
   "$(grep -c -- "$IBH_FAULT_PHRASE" "$HERE/install-board-hooks-capability-windows-check.sh" || true)"
# ON THE NOTE BLOCK, NOT ON THE WHOLE RUN. The check echoes the installer's own stderr, which
# carries this phrase — so a `has` over `$wci_out` is satisfied by the installer's copy and can
# never red on a drifted NOTE. Watched: with the NOTE reworded and the installer untouched, the
# whole-output form passed. The block is cut from the NOTE marker so the assertion is about the
# text this file prints.
wci_note="$(printf '%s\n' "$wci_out" | sed -n '/NOTE: an INDETERMINATE seat/,+2p')"
eq "…and the NOTE that actually PRINTS carries it"  "true" "$(has "$IBH_FAULT_PHRASE" "$wci_note")"
eq "…the block was really cut (an empty haystack passes a 'false' test for free)" "true" \
   "$(has "LOCAL FAULT the reason names" "$wci_note")"
# AND THE ARBITER IS HELD TO THE OPERATION IT ARBITRATES. It is authorised to overrule the probe,
# so it must test the same property: the hook source is REPLACED (unlink + create — what `git
# pull` does), never truncated in place. A hard link follows a truncate and never sees a
# replacement, so on that seat a truncating arbiter reports `tracks` while the probe correctly
# refuses — and fires its "the refusal is WRONG" banner over a correct refusal, which is a wrong
# instruction produced by the one Windows dispatch there is to spend. Nothing else reds that.
wch_rc=0
wch_out="$(PATH="$LN_HARDLINK:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wch_rc=$?
eq "a hard-linking seat: the check runs clean"            "0"    "$wch_rc"
eq "…the probe refuses it (the entry is not a symlink)"   "true" \
   "$(has "SEAT VERDICT: VERDICT=NOT_CAPABLE" "$wch_out")"
eq "…and the ARBITER agrees: a REPLACED source never reaches a hard link" "true" \
   "$(has "SEAT DISPATCH: frozen — probe says tracking=no, real git dispatch says tracking=no" "$wch_out")"
eq "…so no 'the refusal is WRONG' banner is raised over a correct refusal" "false" \
   "$(has "THIS IS THE FINDING" "$wch_out")"
# THE BRANCH THE SINGLE WINDOWS RUN IS SPENT TO OBTAIN — probe=no while a real dispatch=yes — is
# executed here too, and it had never run: both forced-incapable legs above land on `frozen`, so
# the highest-value arm of the arbiter (and the mechanism paragraph keyed on the reason token)
# was shipping unexecuted. Forcing it needs the NATIVE reader to disagree with a dispatch that
# really works, which no real command does on Linux — hence a `git` whose `hash-object` never
# answers the same thing twice, paired with the seat's real `ln -s` and real `cat`.
# THE RUN REDS BY DESIGN HERE: the pairing assertion is what fires the banner, and the banner —
# not the exit status — is the deliverable on such a seat.
wcf_rc=0
wcf_out="$(PATH="$GIT_FRESH_HASH:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wcf_rc=$?
eq "a seat the probe refuses but that really DISPATCHES the replacement" "true" \
   "$(has "SEAT DISPATCH: tracks — probe says tracking=no, real git dispatch says tracking=yes" "$wcf_out")"
eq "…reds the pairing assertion (the disagreement IS the finding)" "1" "$wcf_rc"
# A non-zero rc is satisfied by ANY failure, including one from a leg this stub broke by
# accident, so the count is pinned too: exactly one assertion fails, and it is that one.
eq "…and reds THERE ONLY — one FAIL line in the whole run"          "1" \
   "$({ printf '%s\n' "$wcf_out" | grep -c '^  FAIL'; } || true)"
eq "…which is the pairing assertion by name"                        "true" \
   "$(has "FAIL the PROBE's answer and what git ACTUALLY dispatches agree" "$wcf_out")"
eq "…and renders the banner that says the refusal is wrong there"  "true" \
   "$(has "THIS IS THE FINDING, AND IT IS WORTH MORE THAN A PASS" "$wcf_out")"
# The mechanism paragraph is selected by the probe's REASON token, which is spelled in
# `bin/install-board-hooks` and matched in the windows check — two files, and nothing else binds
# them. A rename touching one would keep every existing assertion green while silently dropping
# the paragraph from the one Windows run, so the token and the paragraph it selects are asserted
# together, in a run that actually produces both.
# Pinned WITH its line terminator: the token sits at end of line, and a plain substring test is
# satisfied by any token that merely STARTS with it — a rename by suffix would pass it.
eq "…quoting the reason token both files spell"      "true" \
   "$(has $'REASON=readers-disagree-native-git-does-not-track\n' "$wcf_out")"
eq "…and the mechanism paragraph that token selects" "true" \
   "$(has "git's own binary reading the entry as opaque and the shell resolving it" "$wcf_out")"
# THE THIRD ARBITER OUTCOME, `broken`: the control fired and then NOTHING executed after the
# replacement. It is not a `no`. Folded into one it asserted a pairing nobody measured and, on a
# CAPABLE seat, printed "a real `git checkout` dispatched the OLD content" — which did not
# happen, since nothing was dispatched at all. It now makes no pairing claim.
wcb_rc=0
wcb_out="$(PATH="$GIT_ONE_CHECKOUT:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wcb_rc=$?
eq "a seat whose hook stops firing: the check runs clean" "0" "$wcb_rc"
eq "…the arbiter classifies it broken, and claims NOTHING about dispatch" "true" \
   "$(has "SEAT DISPATCH: broken — probe says tracking=yes, real git dispatch says tracking=unknown" "$wcb_out")"
eq "…landing on the no-pairing-assertion arm"  "true" \
   "$(has "NO pairing assertion was made: probe=yes dispatch=unknown" "$wcb_out")"
eq "…and never claiming the OLD content ran"   "false" \
   "$(has "dispatched the OLD content" "$wcb_out")"
# THE TWO NON-MEASUREMENT CLASSIFICATIONS, `no-entry` and `control-failed`. They were the only
# arbiter arms with no leg here, and both are reachable on the seat this ships for: an `ln -s`
# that refuses outright is that seat's other documented answer, and a hook entry git will not
# execute produces a control that never fires. Neither is a defect — each is exercised because an
# unexecuted arm is a scripting error waiting to consume the single Windows dispatch.
wcne_rc=0
wcne_out="$(PATH="$LN_FAIL:$REAL_PATH" bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wcne_rc=$?
eq "an 'ln -s' that refuses outright: the check runs clean"  "0"    "$wcne_rc"
eq "…the arbiter classifies it no-entry"                     "true" \
   "$(has "DISPATCH RESULT: no-entry" "$wcne_out")"
# The arm's own assertion is what makes this a leg rather than a smoke test: it must PASS, i.e.
# the seat whose `ln -s` refused is a seat the probe refused too.
eq "…and its arm asserts the probe refused that seat as well" "true" \
   "$(has "ok   an 'ln -s' that fails outright" "$wcne_out")"
eq "…while claiming nothing about what dispatch delivers"     "true" \
   "$(has "SEAT DISPATCH: no-entry — probe says tracking=no, real git dispatch says tracking=unknown" "$wcne_out")"
# `control-failed` REDS BY DESIGN, and that is the arm's contract: the leg produced no measurement
# at all, so an absent marker must not read as "the replacement did not reach dispatch".
wccf_rc=0
printf '1' > "$TMP/wc-control-failed.n"
wccf_out="$(IBH_CHECKOUT_COUNTER="$TMP/wc-control-failed.n" PATH="$GIT_ONE_CHECKOUT:$REAL_PATH" \
    bash "$HERE/install-board-hooks-capability-windows-check.sh" 2>&1)" || wccf_rc=$?
eq "a seat whose hook never fires at all: classified control-failed" "true" \
   "$(has "DISPATCH RESULT: control-failed" "$wccf_out")"
eq "…and it REDS — an unfired hook is not a pass"                    "1"    "$wccf_rc"
eq "…there only, one FAIL line in the whole run"                     "1" \
   "$({ printf '%s\n' "$wccf_out" | grep -c '^  FAIL'; } || true)"
eq "…which is the measured-NOTHING assertion by name"                "true" \
   "$(has "FAIL the dispatch leg measured NOTHING" "$wccf_out")"
eq "…and it makes no pairing claim either"                           "true" \
   "$(has "SEAT DISPATCH: control-failed — probe says tracking=yes, real git dispatch says tracking=unknown" "$wccf_out")"

echo "== installer — the usage line carries the flag it accepts =="
_run - --nope "$r"
eq "unknown option is still rc 2" "2" "$_rc"
eq "usage names --check"          "true" "$(has "[--check]" "$_err")"
eq "usage names --allow-copies"   "true" "$(has "[--allow-copies]" "$_err")"

_summary "install-board-hooks-capability-selftest"
