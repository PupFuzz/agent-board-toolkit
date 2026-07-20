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
_summary "board-session-close-selftest"
