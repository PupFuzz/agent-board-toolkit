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

mkrepo()  { git init -q "$1"; }                      # <dir>
wire()    { ln -sf "$2/hooks/post-checkout" "$1/post-checkout"; ln -sf "$2/hooks/pre-push" "$1/pre-push"; }
state()   { _bsc_hook_state "$1" "${2:-post-checkout}" "$TK"; }
# report <repo…> — run the leg IN THIS SHELL (a $(…) call would lose both globals):
# leaves the finding count in $RN and the printed text in $ROUT.
ROUT=""; RN=0
report()  { RN=0; ROUT="$(_bsc_hook_dispatch_report "$TK" "$@")" || RN=$?; }
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

# --- present but NOT executable (git skips it without a word) ---------------
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
eq "path exists but is not a git work tree ⇒ finding" "1" "$RN"
eq "…and says why"                               "true" "$(saw "not a git work tree")"

# --- the resolver itself missing ⇒ the check reports DID NOT RUN (fail loud) ---
mkdir -p "$H/lonely"; cp "$BIN" "$H/lonely/board-session-close"   # no install-board-hooks sibling
_rc=0; bash -c 'source "$1/lonely/board-session-close"; _bsc_hooks_dir "$1/healthy"' _ "$H" >/dev/null 2>&1 || _rc=$?
eq "resolver unavailable ⇒ rc 4 (never a guessed .git/hooks answer)" "4" "$_rc"
_out="$(bash -c 'source "$1/lonely/board-session-close"; _bsc_hook_dispatch_report "" "$1/healthy"' _ "$H" 2>&1 || true)"
eq "resolver unavailable ⇒ the report says the CHECK DID NOT RUN" \
   "true" "$(case "$_out" in *"CHECK DID NOT RUN"*) echo true ;; *) echo false ;; esac)"

# …and a resolver that loads but yields NOTHING must report the same, never a false MISSING
# (an empty dispatch dir would otherwise make every hook look absent and call the auto-move dead).
mkdir -p "$H/broken"; cp "$BIN" "$H/broken/board-session-close"
printf '#!/usr/bin/env bash\n# a resolver with no _ibh_hooks_dir in it\n' > "$H/broken/install-board-hooks"
_out="$(bash -c 'source "$1/broken/board-session-close"; _bsc_hook_dispatch_report "" "$1/healthy"' _ "$H" 2>&1 || true)"
eq "broken resolver ⇒ CHECK DID NOT RUN" "true" \
   "$(case "$_out" in *"CHECK DID NOT RUN"*) echo true ;; *) echo false ;; esac)"
eq "broken resolver ⇒ does NOT invent a dead auto-move" "false" \
   "$(case "$_out" in *"auto-move is DEAD"*) echo true ;; *) echo false ;; esac)"

# --- _bsc_active_toolkit — the clone that owns the on-PATH board-card-start ---
eq "active toolkit resolves from PATH" "$TK" \
   "$(PATH="$TK/bin:$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN")"
_rc=0; PATH="$UB" bash -c 'source "$1"; _bsc_active_toolkit' _ "$BIN" >/dev/null 2>&1 || _rc=$?
eq "board-card-start absent from PATH ⇒ rc 1 (caller warns, never guesses)" "1" "$_rc"

# --- multi-repo run: the summary line reports the total ---------------------
report "$H/healthy" "$H/dangling" "$H/nohooks" "$H/hookspath"   # 0 + 1 + 2 + 0
eq "multi-repo: findings accumulate across repos" "3" "$RN"
eq "multi-repo: summary states it is report-only" "true" "$(saw "REPORT-ONLY")"
fi

# ---------------------------------------------------------------------------
_summary "board-session-close-selftest"
