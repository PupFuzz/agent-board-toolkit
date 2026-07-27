#!/usr/bin/env bash
# board-session-close-selftest.sh — network-free tests for the inverse-drift leg's
# adoption of the shipped kanban-reconcile.py --detect hook (card#4751).
#
# Two surfaces are covered:
#   1. resolve_reconcile_hook — the version-UNPINNED, fail-loud path resolver. It
#      must honor an explicit override, then derive the session-loaded plugin from
#      $PATH, then the marketplace clone, then the newest cached version (sort -V),
#      and return rc 1 (empty) when NONE has the hook — never a version-pinned path.
#   2. main's delegation — it must SURFACE the hook's ⚠ drift lines, FAIL LOUD (rc 1,
#      "DID NOT RUN") when the hook can't be found, and PROPAGATE a non-zero hook exit
#      (so a config/API failure isn't read as a clean board).
#   3. the git-hook DISPATCH leg (card#5200) — over REAL `git init` fixture repos, it must
#      resolve the dir git actually dispatches from (core.hooksPath and linked worktrees
#      included, via the shared install-board-hooks resolver) and report a hook that is
#      missing / dangling / non-executable / not reaching board-card-start / symlinked into
#      another toolkit checkout, while staying report-only.
#
# The bin is main-guarded, so sourcing it defines the functions and renders nothing.
# resolve_reconcile_hook is probed in a fresh `bash -c` per case (hermetic HOME/PATH/
# env). main is exercised by running the bin with a scratch HOME, PATH shims for
# git/gh, a board-snapshot stub, and a FAKE python hook via $KANBAN_RECONCILE_HOOK —
# no network, no live board.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/board-session-close"
_need -r "$BIN"

_mktmp_scratch          # TMP + EXIT-cleanup trap
UB="/usr/bin:/bin"

has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# run_resolve <HOME> <PATH> <OVERRIDE> — resolve in a hermetic env; echo "rc|stdout".
run_resolve() {
    local h="$1" p="$2" ov="$3" out rc
    out="$(HOME="$h" PATH="$p" KANBAN_RECONCILE_HOOK="$ov" \
           bash -c 'source "'"$BIN"'"; resolve_reconcile_hook' 2>/dev/null)"; rc=$?
    printf '%s|%s' "$rc" "$out"
}

mkhook() { mkdir -p "$(dirname "$1")"; : > "$1"; }   # create an empty hook file at $1

# ---------------------------------------------------------------------------
echo "== resolve_reconcile_hook — explicit \$KANBAN_RECONCILE_HOOK override =="
ovfile="$TMP/override/kanban-reconcile.py"; mkhook "$ovfile"
res="$(run_resolve "$TMP/empty" "$UB" "$ovfile")"
eq "override to an existing file resolves it (rc 0)" "0|$ovfile" "$res"
res="$(run_resolve "$TMP/empty" "$UB" "$TMP/nope.py")"
eq "override to a MISSING file fails loud (rc 1, empty) — no silent fallback" "1|" "$res"

# ---------------------------------------------------------------------------
echo "== resolve_reconcile_hook — derives the session plugin from \$PATH =="
# The plugin's bin dir is named on PATH as .../coord/<ver>/bin; the hook lives at the
# sibling hooks/bin/ (the coord/<ver>/bin dir itself need not even exist).
pver="$TMP/p/agent-board-framework/coord/0.13.0"
mkhook "$pver/hooks/bin/kanban-reconcile.py"
res="$(run_resolve "$TMP/empty" "$pver/bin:$UB" "")"
eq "PATH coord entry resolves to its sibling hooks/bin hook" \
   "0|$pver/hooks/bin/kanban-reconcile.py" "$res"

# ---------------------------------------------------------------------------
echo "== resolve_reconcile_hook — marketplace clone (PATH has no coord entry) =="
mkt="$TMP/mkt/.claude/plugins/marketplaces/agent-board-framework/plugins/coord/hooks/bin/kanban-reconcile.py"
mkhook "$mkt"
res="$(run_resolve "$TMP/mkt" "$UB" "")"
eq "marketplace clone resolves when \$PATH carries no coord dir" "0|$mkt" "$res"

# ---------------------------------------------------------------------------
echo "== resolve_reconcile_hook — newest cached version (sort -V, not lexical) =="
cbase="$TMP/cache/.claude/plugins/cache/agent-board-framework/coord"
mkhook "$cbase/0.9.0/hooks/bin/kanban-reconcile.py"
mkhook "$cbase/0.13.0/hooks/bin/kanban-reconcile.py"   # 0.13.0 > 0.9.0 numerically
res="$(run_resolve "$TMP/cache" "$UB" "")"
eq "cache fallback picks 0.13.0 over 0.9.0 (version sort, not string sort)" \
   "0|$cbase/0.13.0/hooks/bin/kanban-reconcile.py" "$res"

# ---------------------------------------------------------------------------
echo "== resolve_reconcile_hook — NONE available ⇒ rc 1, empty (caller fails loud) =="
res="$(run_resolve "$TMP/bare" "$UB" "")"
eq "no override, no PATH coord, no marketplace, no cache ⇒ rc 1 empty" "1|" "$res"

# ---------------------------------------------------------------------------
# main's delegation — run the real bin with stubs + a FAKE python hook.
# ---------------------------------------------------------------------------
SHIM="$TMP/shim"; mkdir -p "$SHIM"
for s in git gh; do printf '#!/bin/sh\nexit 0\n' > "$SHIM/$s"; chmod +x "$SHIM/$s"; done
SCRATCH="$TMP/run"; mkdir -p "$SCRATCH/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$SCRATCH/.local/bin/board-snapshot"
chmod +x "$SCRATCH/.local/bin/board-snapshot"

# run_main <fake-hook-or-missing> — run the bin; echo "rc" and leave out/err files.
OUTF="$TMP/out"; ERRF="$TMP/err"
run_main() {
    HOME="$SCRATCH" PATH="$SHIM:$UB" KANBAN_RECONCILE_HOOK="$1" \
        bash "$BIN" >"$OUTF" 2>"$ERRF"; echo $?
}

echo "== main — SURFACES the hook's drift lines (positive control) =="
goodhook="$TMP/good-hook.py"
printf '%s\n' '#!/usr/bin/env python3' \
              'print("⚠ verify + reconcile: SYNTHETIC stale card 999")' > "$goodhook"
rc="$(run_main "$goodhook")"
eq "exit 0 when the hook detects drift cleanly" "0" "$rc"
eq "the hook's drift line is surfaced (indented) in stdout" \
   "true" "$(has 'SYNTHETIC stale card 999' "$(cat "$OUTF")")"

echo "== main — FAILS LOUD when the hook can't be found =="
rc="$(run_main "$TMP/does-not-exist.py")"   # override to a missing file ⇒ no fallback
eq "exit 1 when the hook is unresolvable" "1" "$rc"
eq "stderr says the check DID NOT RUN" "true" "$(has 'DID NOT RUN' "$(cat "$ERRF")")"

echo "== main — PROPAGATES a non-zero hook exit (config/API failure not read as clean) =="
badhook="$TMP/bad-hook.py"
printf '%s\n' '#!/usr/bin/env python3' 'import sys' \
              'print("kanban-reconcile: boom", file=sys.stderr)' 'sys.exit(2)' > "$badhook"
rc="$(run_main "$badhook")"
eq "the hook's rc 2 propagates as the ritual's exit code" "2" "$rc"
eq "stderr flags the check as INCOMPLETE" "true" "$(has 'INCOMPLETE' "$(cat "$ERRF")")"

echo "== main — inverse check OFF is re-emitted as a LOUD ⚠ warning, not a silent pass =="
# The hook runs the forward leg + reports 'inverse check OFF' at rc 0 for a board
# lacking inverse_check_columns. main must scan the output and surface a ⚠ on stderr
# naming the board key, so the dropped inverse-drift check is not read as clean.
offhook="$TMP/off-hook.py"
printf '%s\n' '#!/usr/bin/env python3' \
              'print("\n[DETECT] board 5 (kanban): 0 item(s) to verify + reconcile by hand")' \
              'print("  notice: inverse check OFF — no inverse_check_columns declared for this board (declare the \x27In Review\x27-class column names in kanban.boards[] to arm it)")' \
              'print("  (no drift detected)")' > "$offhook"
rc="$(run_main "$offhook")"
eq "inverse-OFF board still exits 0 (OFF is not a hard error)" "0" "$rc"
eq "the OFF notice is surfaced in stdout (forward-leg output preserved)" \
   "true" "$(has 'inverse check OFF' "$(cat "$OUTF")")"
eq "OFF re-emitted as a ⚠ warning on STDERR" \
   "true" "$(has '⚠ inverse-drift check is OFF' "$(cat "$ERRF")")"
eq "the ⚠ warning names the board key" \
   "true" "$(has 'board kanban' "$(cat "$ERRF")")"

echo "== main — a SKIPPED board (absent/mis-declared in kanban.boards[]) is surfaced as ⚠ =="
skiphook="$TMP/skip-hook.py"
printf '%s\n' '#!/usr/bin/env python3' \
              'print("[DETECT] board (bridge): board_id not configured — skipped")' > "$skiphook"
rc="$(run_main "$skiphook")"
eq "a skipped board still exits 0" "0" "$rc"
eq "the skip is re-emitted as a ⚠ warning on STDERR naming the board key" \
   "true" "$(has '⚠ board bridge was SKIPPED' "$(cat "$ERRF")")"

# ---------------------------------------------------------------------------
# The git-hook DISPATCH check (card#5200). Real fixture repos (`git init` in a temp dir),
# never a mock: the whole point of the leg is what GIT actually dispatches, and a mocked
# `git config` / faked `.git` layout would assert the check's own assumptions back at it.
#
# THE LOAD-BEARING CASE is `core.hooksPath`. When a repo sets it, git dispatches hooks ONLY
# from there, so a checker that reads `.git/hooks` reports a repo healthy on the strength of
# a hook git never runs — the exact silent no-op install-board-hooks was fixed for (#4281).
# The two hooksPath cases below therefore assert BOTH directions against the naive
# `.git/hooks` answer, so "simplifying" the resolver back to `.git/hooks` goes red.
# ---------------------------------------------------------------------------
echo "== hook-dispatch check — fixture repos =="
if ! command -v git >/dev/null 2>&1; then
    echo "  skip (git not on PATH)"
else
# shellcheck source=/dev/null
source "$BIN"       # main-guarded: defines the _bsc_* helpers, runs nothing

H="$TMP/hooks"; mkdir -p "$H"
# Two toolkit checkouts: the "active" one (owns the on-PATH board-card-start) and a second
# clone — the observed drift shape is a hook symlinked into the wrong one.
for tkdir in "$H/toolkit" "$H/toolkit-other"; do
    mkdir -p "$tkdir/hooks" "$tkdir/bin"
    for hk in post-checkout pre-push; do
        printf '#!/bin/sh\ncommand -v board-card-start >/dev/null && board-card-start\n' > "$tkdir/hooks/$hk"
        chmod +x "$tkdir/hooks/$hk"
    done
    printf '#!/bin/sh\nexit 0\n' > "$tkdir/bin/board-card-start"; chmod +x "$tkdir/bin/board-card-start"
done
TK="$H/toolkit"; TKO="$H/toolkit-other"

IBH2="$HERE/../bin/install-board-hooks"; _need -r "$IBH2"
mkrepo()  { git init -q "$1"; }                      # <dir>
# _ibh_hooks_dir_probe <repo-root> <RAW hooksPath> — what the resolver answers for an
# UNEXPANDED value; the B2 pin compares the real answer against it. Sourced in a subshell
# because install-board-hooks sets -e and this harness deliberately does not.
# shellcheck source=/dev/null
_ibh_hooks_dir_probe() { ( . "$IBH2" >/dev/null 2>&1; _ibh_hooks_dir "$1" "$2" "$1/.git" 1 ); }
wire()    { ln -sf "$2/hooks/post-checkout" "$1/post-checkout"; ln -sf "$2/hooks/pre-push" "$1/pre-push"; }
state()   { _bsc_hook_state "$1" "${2:-post-checkout}" "$TK"; }
# report <repo…> — run the leg IN THIS SHELL (a $(…) call would lose both globals): leaves the
# finding count in $RN and the printed text in $ROUT. The leg resolves the active toolkit from
# PATH itself, so the fixture toolkit's bin/ goes on PATH inside the substitution subshell (the
# assignment cannot leak back out). report_nopath runs the same leg with the tool ABSENT.
ROUT=""; RN=0
report()        { RN=0; ROUT="$(PATH="$TK/bin:$UB"; _bsc_hook_dispatch_report "$@")" || RN=$?; }
report_nopath() { RN=0; ROUT="$(PATH="$UB"; _bsc_hook_dispatch_report "$@")" || RN=$?; }
saw()     { case "$ROUT" in *"$1"*) echo true ;; *) echo false ;; esac; }

# --- healthy: both hooks symlinked from the active toolkit ------------------
r="$H/healthy"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
eq "healthy: dispatch dir is .git/hooks"  "$r/.git/hooks" "$(_bsc_hooks_dir "$r")"
eq "healthy: post-checkout OK"            "OK" "$(state "$r/.git/hooks")"
eq "healthy: pre-push OK"                 "OK" "$(state "$r/.git/hooks" pre-push)"
report "$r"
eq "healthy: report finds NOTHING" "0" "$RN"
eq "healthy: reported as ✓"               "true" "$(saw "✓")"

# PROVE-IT-CAN-FAIL for the whole leg: break the SAME fixture and it must go red.
rm -f "$r/.git/hooks/post-checkout"
report "$r"
eq "prove-it-can-fail: same repo, hook removed ⇒ finding" "1" "$RN"
eq "prove-it-can-fail: names the dead auto-move"          "true" "$(saw "auto-move is DEAD")"
wire "$r/.git/hooks" "$TK"                                  # restore

# --- no hook at all (the observed ~kanbanboard case) ------------------------
r="$H/nohooks"; mkrepo "$r"
eq "no hook at all: post-checkout MISSING" "MISSING" "$(state "$r/.git/hooks")"
report "$r"
eq "no hook at all: 2 findings (both hooks)" "2" "$RN"
eq "no hook at all: names the remediation"   "true" "$(saw "fix: install-board-hooks $r")"

# --- hook symlinked into a DIFFERENT toolkit clone (the observed -prod/dev case) ---
r="$H/otherclone"; mkrepo "$r"; wire "$r/.git/hooks" "$TKO"
eq "wrong toolkit clone: CLONE-DRIFT"        "CLONE-DRIFT" "$(state "$r/.git/hooks")"
report "$r"
eq "wrong toolkit clone: report finds it" "2" "$RN"
eq "wrong toolkit clone: names the clone"    "true" "$(saw "$TKO/hooks/post-checkout")"
# M3 — drift is NOT death: the hook still fires, and the docs say so. Labelling it DEAD would
# make the report contradict itself two lines from the ✗/⚠ legend.
eq "wrong toolkit clone: NOT reported as a dead auto-move" "false" "$(saw "auto-move is DEAD")"
eq "wrong toolkit clone: says it still fires"              "true"  "$(saw "it still fires")"

# --- present but NOT executable (git ignores it; only a suppressible hint says so) ---
r="$H/noexec"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
rm -f "$r/.git/hooks/post-checkout"
cp "$TK/hooks/post-checkout" "$r/.git/hooks/post-checkout"; chmod -x "$r/.git/hooks/post-checkout"
eq "not executable: NOT-EXECUTABLE"          "NOT-EXECUTABLE" "$(state "$r/.git/hooks")"
report "$r"
eq "not executable: exactly 1 finding" "1" "$RN"
chmod +x "$r/.git/hooks/post-checkout"
eq "…and a COPY (not a symlink) of the same hook is OK — the Windows topology is not drift" \
   "OK" "$(state "$r/.git/hooks")"

# --- core.hooksPath → a custom OUT-OF-TREE dir holding a correct hook ⇒ NO finding ---
r="$H/hookspath"; mkrepo "$r"; hp="$H/custom-hooks"; mkdir -p "$hp"; wire "$hp" "$TK"
git -C "$r" config core.hooksPath "$hp"
eq "core.hooksPath: resolver returns the custom dir" "$hp" "$(_bsc_hooks_dir "$r")"
report "$r"
eq "core.hooksPath: no finding" "0" "$RN"
# The regression pin, direction 1: a .git/hooks-only checker would call this repo BROKEN.
eq "REGRESSION PIN: .git/hooks says MISSING while git dispatches a healthy hook" \
   "MISSING" "$(state "$r/.git/hooks")"

# --- core.hooksPath set, hook absent there, a stale CORRECT hook in .git/hooks ⇒ finding ---
r="$H/hookspath-stale"; mkrepo "$r"; hp2="$H/empty-hooks"; mkdir -p "$hp2"
wire "$r/.git/hooks" "$TK"                       # the stale, no-longer-dispatched copy
git -C "$r" config core.hooksPath "$hp2"
eq "stale .git/hooks: dispatch dir is the hooksPath" "$hp2" "$(_bsc_hooks_dir "$r")"
eq "stale .git/hooks: post-checkout MISSING where git looks" "MISSING" "$(state "$hp2")"
report "$r"
eq "stale .git/hooks: report finds it" "2" "$RN"
# The regression pin, direction 2: a .git/hooks-only checker would call this repo HEALTHY.
eq "REGRESSION PIN: .git/hooks says OK while git dispatches nothing" \
   "OK" "$(state "$r/.git/hooks")"

# --- core.hooksPath SET but EMPTY ⇒ git dispatches NOTHING (B1) --------------
# Verified against git 2.43: an empty value does NOT fall back to .git/hooks — hook dispatch is
# OFF for the repo. `git config --get` separates it from UNSET by EXIT STATUS ONLY (unset → 1,
# empty → 0 + empty output), so a resolver that tests the VALUE for emptiness certifies a repo
# whose auto-move is dead. This fixture wires a PERFECT .git/hooks precisely so that the only
# thing standing between it and a false ✓ is the rc discriminator.
r="$H/hookspath-empty"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
git -C "$r" config core.hooksPath ""
_rc=0; _d="$(_bsc_hooks_dir "$r")" || _rc=$?
eq "empty hooksPath: rc 4 (hooks DISABLED, a state of its own)" "4" "$_rc"
eq "empty hooksPath: no directory is echoed — there is none"    ""  "$_d"
report "$r"
eq "empty hooksPath: IS a finding"                    "1" "$RN"
eq "empty hooksPath: says dispatch is off, not that a file is missing" "true" "$(saw "EMPTY value")"
eq "empty hooksPath: remediation is --unset, not install" "true" "$(saw "config --unset core.hooksPath")"
# The pin: a perfectly-wired .git/hooks sits right there, so anything that reads emptiness as
# "unset" reports this repo ✓.
eq "REGRESSION PIN: .git/hooks is perfectly wired, and git still runs NOTHING" \
   "OK" "$(state "$r/.git/hooks")"
# install-board-hooks must refuse rather than plant into a directory git never reads.
_rc=0; _out="$(bash "$IBH2" "$r" 2>&1)" || _rc=$?
eq "installer refuses an empty hooksPath (rc 1)" "1" "$_rc"
eq "installer names the --unset fix"             "true" \
   "$(case "$_out" in *"--unset core.hooksPath"*) echo true ;; *) echo false ;; esac)"

# --- core.hooksPath with a leading ~ ⇒ git EXPANDS it (B2) -------------------
# Verified: core.hooksPath is a path-type variable, a hook in ~/<dir> fires. Reading the raw
# value makes `~/x` look RELATIVE, which yields a false RED (a working repo called dead, and
# mis-flagged as an in-tree path so the operator is told to hand-chain a hook it doesn't need)
# AND a false GREEN (planting at <root>/~/x while the real dir stays empty).
THOME="$H/tilde-home"; mkdir -p "$THOME/tildehooks"; wire "$THOME/tildehooks" "$TK"
r="$H/hookspath-tilde"; mkrepo "$r"
# shellcheck disable=SC2088  # the literal, shell-UNexpanded ~ is the fixture: git expands it
git -C "$r" config core.hooksPath '~/tildehooks'
_rc=0; _d="$(HOME="$THOME" _bsc_hooks_dir "$r")" || _rc=$?
eq "tilde hooksPath: expanded to the real dir" "$THOME/tildehooks" "$_d"
eq "tilde hooksPath: rc 0 — NOT the in-tree refuse"    "0" "$_rc"
_saveH="$HOME"; export HOME="$THOME"
report "$r"
eq "tilde hooksPath: no finding (the hook is genuinely wired)" "0" "$RN"
export HOME="$_saveH"
# The pin: unexpanded, this resolves under the work tree and reports rc 3 + a dead hook.
# shellcheck disable=SC2088  # the literal, shell-UNexpanded ~ is the fixture
eq "REGRESSION PIN: the raw value would resolve inside the work tree" \
   "$r/~/tildehooks" "$(_ibh_hooks_dir_probe "$r" '~/tildehooks')"

# --- core.hooksPath git cannot expand ⇒ report GIT'S OWN cause, never a guessed one ---
# Verified: such a value fatals EVERY git command in the repo — `rev-parse` included, which is
# why the resolver's own dedicated arm is not what surfaces it. The failure mode that matters is
# the DIAGNOSIS: "not a git work tree" would be a confident wrong cause (the repo is fine; its
# config is not), and it points the operator at the wrong fix. A wired .git/hooks sits there to
# prove the check is not merely reading the filesystem.
r="$H/hookspath-baduser"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
git -C "$r" config core.hooksPath '~nosuchuser-abc/x'
_rc=0; _d="$(_bsc_hooks_dir "$r")" || _rc=$?
eq "unexpandable hooksPath: rc 1 — git refuses the checkout"  "1" "$_rc"
eq "unexpandable hooksPath: carries out the message git itself printed" "true" \
   "$(case "$_d" in *"expand user dir"*) echo true ;; *) echo false ;; esac)"
report "$r"
eq "unexpandable hooksPath: IS a finding"                     "1" "$RN"
eq "unexpandable hooksPath: the report quotes that refusal"    "true" "$(saw "expand user dir")"
# The cause must be git's, and it must be the FIRST thing the line says — an assertion on the
# absence of some wording we no longer emit anywhere could never go red.
eq "unexpandable hooksPath: the line leads with 'git refuses this checkout'" "true" \
   "$(saw "✗ git refuses this checkout")"

# --- in-tree core.hooksPath: git dispatches from it, install-board-hooks refuses it ---
r="$H/hookspath-intree"; mkrepo "$r"; mkdir -p "$r/.githooks"; wire "$r/.githooks" "$TK"
git -C "$r" config core.hooksPath .githooks
_rc=0; _d="$(_bsc_hooks_dir "$r")" || _rc=$?
eq "in-tree hooksPath: resolved (relative to the work-tree top)" "$r/.githooks" "$_d"
eq "in-tree hooksPath: flagged rc 3 (installer refuses that target)" "3" "$_rc"
report "$r"
eq "in-tree hooksPath: a wired hook is still NO finding" "0" "$RN"
rm -f "$r/.githooks/post-checkout"
report "$r"
eq "in-tree hooksPath: a missing hook IS a finding" "1" "$RN"
eq "in-tree hooksPath: remediation is chain-by-hand, not install-board-hooks" \
   "true" "$(saw "chain the toolkit hook")"

# --- linked worktree (.git is a FILE; hooks come from the MAIN checkout) ----
r="$H/wt-main"; mkrepo "$r"
git -C "$r" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
git -C "$r" worktree add -q "$H/wt-linked" -b wtbranch
eq "worktree: .git is a file, not a dir" "true" "$([ -f "$H/wt-linked/.git" ] && echo true || echo false)"
eq "worktree: dispatch dir is the MAIN checkout's hooks dir" \
   "$r/.git/hooks" "$(_bsc_hooks_dir "$H/wt-linked")"
report "$H/wt-linked"
eq "worktree: unwired main ⇒ finding on the worktree too" "2" "$RN"
eq "worktree: remediation names the MAIN checkout"         "true" "$(saw "fix: install-board-hooks $r")"
eq "worktree: and says why that path is the one that installs" "true" "$(saw "dispatches from that one")"
wire "$r/.git/hooks" "$TK"
report "$H/wt-linked"
eq "worktree: wiring the main checkout clears the worktree's finding" "0" "$RN"

# --- a hook that exists but does not reach board-card-start (foreign hook) ---
r="$H/foreign"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\nexec ./scripts/local-secret-scan --staged\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "foreign hook: NO-REACH"           "NO-REACH" "$(state "$r/.git/hooks")"
report "$r"
eq "foreign hook: 1 finding" "1" "$RN"
# …and the documented in-tree remedy — a committed hook that CHAINS to the toolkit hook —
# does reach it (one level of indirection is followed).
printf '#!/bin/sh\nexec "%s/hooks/post-checkout" "$@"\n' "$TK" > "$r/.git/hooks/post-checkout"
eq "chained hook reaches board-card-start ⇒ OK" "OK" "$(state "$r/.git/hooks")"

# --- a hook that only MENTIONS the tool in a comment does NOT reach it (M4) ---
r="$H/commentonly"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\n# we used to call board-card-start here; removed 2026-01\nexit 0\n' \
    > "$r/.git/hooks/post-checkout"; chmod +x "$r/.git/hooks/post-checkout"
eq "comment-only mention: NO-REACH (comments are stripped before matching)" \
   "NO-REACH" "$(state "$r/.git/hooks")"
report "$r"
eq "comment-only mention: IS a finding"          "1" "$RN"
# …and the same text as real code is a reach — proving the strip is what decided it, not the
# absence of the string.
printf '#!/bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
eq "the same call as CODE reaches it"            "OK" "$(state "$r/.git/hooks")"

# --- a chain to a NON-EXECUTABLE toolkit hook is broken, not OK -------------
# git execs the chained hook; a non-executable target fails there exactly as it does for a
# direct hook. The direct path checked -x from the start and the chained path did not, so a
# broken chain reported healthy — a false GREEN, the defect class this whole check exists for.
r="$H/chain-noexec"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
cp "$TK/hooks/post-checkout" "$TK/hooks/chain-target-src"
mkdir -p "$H/toolkit-chain/hooks"
cp "$TK/hooks/post-checkout" "$H/toolkit-chain/hooks/post-checkout"; chmod -x "$H/toolkit-chain/hooks/post-checkout"
rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\nexec "%s/hooks/post-checkout" "$@"\n' "$H/toolkit-chain" > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "chain to a NON-executable hook: CHAIN-BROKEN" "CHAIN-BROKEN" "$(state "$r/.git/hooks")"
report "$r"
eq "chain to a NON-executable hook: IS a finding"  "1" "$RN"
eq "…and names the target it cannot exec"          "true" "$(saw "$H/toolkit-chain/hooks/post-checkout")"
chmod +x "$H/toolkit-chain/hooks/post-checkout"
eq "…the SAME chain with the target executable is OK" "OK" "$(state "$r/.git/hooks")"

# --- DISCLOSED BOUNDS: two shapes that read as OK on purpose ----------------
# Both are documented in bin/board-session-close and docs/HOOKS.md as accepted false-OK bounds:
# closing either requires EXECUTING an arbitrary hook, which a read-only session check must not
# do. They are pinned so the disclosure and the behaviour can never drift apart.
r="$H/bound-string"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\necho "run board-card-start yourself"\nexit 0\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "DISCLOSED BOUND: a string-literal mention reads as a reach" "OK" "$(state "$r/.git/hooks")"
r="$H/bound-dead"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\nexit 0\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "DISCLOSED BOUND: a call after an early exit 0 reads as a reach" "OK" "$(state "$r/.git/hooks")"

# --- the remediation line must name a command that actually works -----------
# A `.git` FILE (linked worktree, --separate-git-dir, submodule) makes install-board-hooks
# target an un-creatable <repo>/.git/hooks and exit 1. Printing it anyway is worse than
# printing nothing, so the line is derived from the topology, not assumed.
r="$H/fixline-plain"; mkrepo "$r"
report "$r"
eq "plain repo: names install-board-hooks on the repo itself" "true" "$(saw "fix: install-board-hooks $r")"
git init -q --separate-git-dir="$H/sgd-gitdir" "$H/sgd" 2>/dev/null
eq "separate-git-dir: .git really is a file" "true" "$([ -f "$H/sgd/.git" ] && echo true || echo false)"
eq "separate-git-dir: dispatch dir is the EXTERNAL git dir" "$H/sgd-gitdir/hooks" "$(_bsc_hooks_dir "$H/sgd")"
report "$H/sgd"
eq "separate-git-dir: does NOT print an install command that would exit 1" "false" \
   "$(saw "fix: install-board-hooks")"
eq "separate-git-dir: says the installer cannot service it, and names the manual wiring" "true" \
   "$(saw "cannot service this checkout")"
eq "separate-git-dir: the manual wiring names the real dispatch dir" "true" \
   "$(saw "ln -s <toolkit>/hooks/post-checkout $H/sgd-gitdir/hooks/")"

# --- EXECUTABLE but not EXEC-ABLE: the bit is not the ability (round-3 MAJOR 2) ---
# Verified against git 2.43: both shapes are -x, look perfect, and make git fail with
# `fatal: cannot exec '<hook>': No such file or directory`. CRLF is the native hazard of the
# Windows/MSYS COPY install topology this toolkit supports, so this is a supported-platform
# failure, not a hypothetical. Catching it is a PURE READ of line 1 — which is exactly why it
# is NOT covered by the "closing it would require executing the hook" rationale that makes the
# other two false-OK bounds acceptable.
r="$H/crlf"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\r\nboard-card-start\r\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "CRLF shebang (and -x): BAD-SHEBANG"  "BAD-SHEBANG" "$(state "$r/.git/hooks")"
report "$r"
eq "CRLF shebang: IS a finding"          "1" "$RN"
eq "CRLF shebang: names CRLF as the cause" "true" "$(saw "CRLF")"
# The positive control: the SAME hook with LF endings is OK, so the line endings are what
# decided it — not the content, the bit, or the path.
printf '#!/bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
eq "the SAME hook with LF endings is OK"  "OK" "$(state "$r/.git/hooks")"

r="$H/nointerp"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/usr/bin/nosuchinterp-abc\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "missing shebang interpreter (and -x): BAD-SHEBANG" "BAD-SHEBANG" "$(state "$r/.git/hooks")"
eq "…and it names the interpreter"       "true" \
   "$(case "$(_bsc_state_reason BAD-SHEBANG "$r/.git/hooks/post-checkout" post-checkout)" in *nosuchinterp-abc*) echo true ;; *) echo false ;; esac)"
# A hook with NO shebang claims nothing: it may be a binary, or run by the shell.
printf 'board-card-start\n' > "$r/.git/hooks/post-checkout"
eq "no shebang at all ⇒ nothing is claimed (OK)" "OK" "$(state "$r/.git/hooks")"

# …and the CHAIN path must apply the same rule — the -x sibling was fixed in only one of the
# two places once already, and this is that shape's next sibling (canon #7).
r="$H/chain-crlf"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
mkdir -p "$H/toolkit-crlf/hooks"
printf '#!/bin/sh\r\nboard-card-start\r\n' > "$H/toolkit-crlf/hooks/post-checkout"
chmod +x "$H/toolkit-crlf/hooks/post-checkout"
printf '#!/bin/sh\nexec "%s/hooks/post-checkout" "$@"\n' "$H/toolkit-crlf" > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "chain to an -x but CRLF target: CHAIN-BROKEN" "CHAIN-BROKEN" "$(state "$r/.git/hooks")"
report "$r"
eq "chain to a CRLF target: IS a finding"         "1" "$RN"
eq "…and the reason names CRLF, not just 'not executable'" "true" "$(saw "CRLF")"

# --- a fix-line target that string-matches but is NOT creatable -------------
# "Same path" is not "creatable": a core.hooksPath naming a regular file makes the installer
# exit 1, and the fix-line contract is never to print a command that does that.
r="$H/hookspath-isfile"; mkrepo "$r"; : > "$H/not-a-dir"
git -C "$r" config core.hooksPath "$H/not-a-dir"
report "$r"
eq "hooksPath is a regular file: does NOT print an install command that exits 1" "false" \
   "$(saw "fix: install-board-hooks")"

# --- MAJOR 1: a non-canonical path spelling must not be told its .git is a file ---
# `--git-common-dir` answers relative to the path the caller typed; `--show-toplevel` is always
# canonical. Comparing the two as STRINGS made every alternate spelling of an ordinary checkout
# fall into the "your .git is a file" arm — asserting a falsehood AND withholding the command
# that works (the installer canonicalizes, so it succeeds rc 0 on all of these).
r="$H/canon"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; mkdir -p "$r/sub"; ln -s "$r" "$H/canon-link"
for spelling in "$r" "$H/canon-link" "$r/" "$r/sub"; do
    report "$spelling"
    eq "spelling [${spelling#"$H/"}]: no finding" "0" "$RN"
    eq "spelling [${spelling#"$H/"}]: the hooks are found where git dispatches" "true" \
       "$(saw "✓ post-checkout pre-push dispatch from")"
done
rm -f "$r/.git/hooks/post-checkout"      # force the fix-line to print for each spelling
for spelling in "$r" "$H/canon-link" "$r/" "$r/sub"; do
    report "$spelling"
    eq "spelling [${spelling#"$H/"}]: names install-board-hooks, not the .git-is-a-file arm" "true" \
       "$(saw "fix: install-board-hooks")"
    eq "spelling [${spelling#"$H/"}]: never claims .git is a file" "false" \
       "$(saw "cannot service this checkout")"
done
wire "$r/.git/hooks" "$TK"

# --- dangling symlink (the toolkit clone it pointed at is gone) -------------
r="$H/dangling"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
ln -sf "$H/deleted-toolkit/hooks/post-checkout" "$r/.git/hooks/post-checkout"
eq "dangling symlink: DANGLING"       "DANGLING" "$(state "$r/.git/hooks")"
report "$r"
eq "dangling symlink: 1 finding" "1" "$RN"

# --- a configured repo whose path does not exist / is not a repo ------------
report "$H/does-not-exist"
eq "absent checkout: skipped, NOT a finding" "0" "$RN"
eq "absent checkout: says so"                "true" "$(saw "no checkout at")"
mkdir -p "$H/notarepo"
report "$H/notarepo"
eq "path exists but git refuses it ⇒ finding" "1" "$RN"
eq "…and says why, in git's own words"       "true" "$(saw "not a git repository")"

# --- the resolver itself missing ⇒ the check reports DID NOT RUN (fail loud) ---
mkdir -p "$H/lonely"; cp "$BIN" "$H/lonely/board-session-close"   # no install-board-hooks sibling
_rc=0; bash -c 'source "$1/lonely/board-session-close"; _bsc_hooks_dir "$1/healthy"' _ "$H" >/dev/null 2>&1 || _rc=$?
eq "resolver unavailable ⇒ rc 5 (never a guessed .git/hooks answer)" "5" "$_rc"
_out="$(bash -c 'source "$1/lonely/board-session-close"; _bsc_hook_dispatch_report "$1/healthy"' _ "$H" 2>&1 || true)"
eq "resolver unavailable ⇒ the report says the CHECK DID NOT RUN" \
   "true" "$(case "$_out" in *"CHECK DID NOT RUN"*) echo true ;; *) echo false ;; esac)"

# …and a resolver that loads but yields NOTHING must report the same, never a false MISSING
# (an empty dispatch dir would otherwise make every hook look absent and call the auto-move dead).
mkdir -p "$H/broken"; cp "$BIN" "$H/broken/board-session-close"
printf '#!/usr/bin/env bash\n# a resolver with no _ibh_hooks_dir in it\n' > "$H/broken/install-board-hooks"
_out="$(bash -c 'source "$1/broken/board-session-close"; _bsc_hook_dispatch_report "$1/healthy"' _ "$H" 2>&1 || true)"
eq "broken resolver ⇒ CHECK DID NOT RUN" "true" \
   "$(case "$_out" in *"CHECK DID NOT RUN"*) echo true ;; *) echo false ;; esac)"
eq "broken resolver ⇒ does NOT invent a dead auto-move" "false" \
   "$(case "$_out" in *"auto-move is DEAD"*) echo true ;; *) echo false ;; esac)"

# --- _bsc_active_toolkit — the clone that owns the on-PATH board-card-start ---
eq "active toolkit resolves from PATH" "$TK" \
   "$(PATH="$TK/bin:$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN")"
_rc=0; PATH="$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN" >/dev/null 2>&1 || _rc=$?
eq "board-card-start absent from PATH ⇒ rc 1 (caller warns, never guesses)" "1" "$_rc"
# N2 — the root is confirmed by LAYOUT, not by a `bin` path literal: a copy install under any
# other directory name must still resolve, or every correctly-wired repo reports CLONE-DRIFT.
mkdir -p "$TK/localbin"; cp "$TK/bin/board-card-start" "$TK/localbin/"
eq "a non-'bin' install dir still resolves the toolkit root" "$TK" \
   "$(PATH="$TK/localbin:$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN")"
# …and a tool that is NOT inside a toolkit checkout is reported as underivable (rc 2), never
# as a confident wrong root — which would turn every healthy repo into a CLONE-DRIFT finding.
mkdir -p "$H/strayb"; cp "$TK/bin/board-card-start" "$H/strayb/"
_rc=0; PATH="$H/strayb:$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN" >/dev/null 2>&1 || _rc=$?
eq "a board-card-start outside any toolkit checkout ⇒ rc 2, not a guessed root" "2" "$_rc"

# --- M1 — board-card-start off PATH is a FINDING, not a footnote ------------
# Every post-checkout is a trampoline into a tool that does not exist, so the leg must not
# print an all-clear whose text asserts the very thing the warning above it denies.
report_nopath "$H/healthy"
eq "off-PATH: counted as a finding"            "1" "$RN"
eq "off-PATH: says the tool is not on PATH"    "true" "$(saw "NOT on PATH")"
eq "off-PATH: does NOT print the all-clear"    "false" "$(saw "no findings")"
# POSITIVE CONTROL for the two absence assertions in this block and the next: the exact strings
# they assert the ABSENCE of must be strings the healthy fixture PRODUCES — otherwise rewording
# the summary leaves both green and the invariants become decorations.
report "$H/healthy"
eq "witness: a healthy run really does print 'no findings'"          "true" "$(saw "no findings")"
eq "witness: …and the 'every INSPECTED checkout' wording"            "true" "$(saw "every INSPECTED checkout")"

# --- M2 — zero inspected checkouts must NOT read as clean (canon #9) --------
report "$H/does-not-exist" "$H/also-not-here"
eq "0 inspected: no findings (an absent checkout is not a defect)" "0" "$RN"
eq "0 inspected: says NOTHING was verified"                        "true" "$(saw "NOTHING was verified")"
# A bare/refused path yields findings while inspecting nothing; the summary is the line an
# operator skims, so it must not drop the count in that branch.
report "$H/notarepo" "$H/does-not-exist"
eq "0 inspected WITH a finding: the count survives in the summary" "true" "$(saw "1 finding(s)")"
eq "0 inspected: does NOT claim every checkout dispatches"         "false" "$(saw "every INSPECTED checkout")"

# --- multi-repo run: the summary counts inspected / skipped / findings ------
report "$H/healthy" "$H/dangling" "$H/nohooks" "$H/hookspath" "$H/does-not-exist"   # 0+1+2+0
eq "multi-repo: findings accumulate across repos" "3" "$RN"
eq "multi-repo: summary states it is report-only" "true" "$(saw "REPORT-ONLY")"
eq "multi-repo: summary reports the inspected/skipped split" "true" "$(saw "4 inspected / 1 skipped")"
fi

# ---------------------------------------------------------------------------
_summary "board-session-close-selftest"
