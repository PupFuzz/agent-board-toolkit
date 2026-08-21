#!/usr/bin/env bash
# board-session-close-selftest.sh — network-free tests for the board-session-close ritual.
# It began as coverage of the inverse-drift leg's adoption of the shipped
# kanban-reconcile.py --detect hook (card#4751) and has grown a leg at a time since.
#
# Six surfaces are covered:
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
#   4. the Open-PRs leg (card#5358) — which repos it queries, that each queried repo's output
#      is labelled with that repo's name, that a repo with no local checkout is skipped, and
#      that a failing `gh` is swallowed without stopping the repos after it.
#   5. the branch-reality leg (card#5370) — the OTHER BSC_WORKTREES consumer: that every present
#      checkout gets one line under its own name in list order, that the dirty suffix tracks the
#      porcelain output in both directions, that an unresolvable branch renders `?` whether git
#      answered empty or refused, and that a checkout-less entry is skipped rather than queried.
#   6. the ADVISORY SIBLING DELEGATIONS — one block per leg: `_kbc-archive-eligible.py`
#      (card#5371), `dependabot-deploy-reconcile` (card#6277) and `_kbc-stale-blocker.py`
#      (card#7113). Their shared rc contract INVERTS surface 2's: a missing sibling and a
#      non-zero helper each WARN on stderr and leave the ritual's exit code alone, where the
#      reconcile hook propagates. Each is run against a COPY of the bin with FAKE siblings —
#      the real ones are resolved by path beside the bin with no env override — and each block
#      plants a QUIET fixture for the OTHER legs, so a broad `sibling not found` absence needle
#      still discriminates instead of being satisfied by a neighbour's warning.
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
# The Open-PRs leg (card#5358) — the `gh pr list` loop, since card#5227 over a query set
# DERIVED from BSC_WORKTREES by de-duplicating on the remote URL rather than its own
# literal repo list. The cases above never reach it: $SCRATCH holds no checkouts, so the
# leg's `-e .git` guard skips every entry and $SHIM/gh is never executed. Its repo set,
# its per-repo label and its skip guard were therefore free to change with a green suite
# — which is why this block exists, and it is what card#5227's derivation was validated
# against.
#
# Its OWN shim dir, deliberately. The gh above is a silent `exit 0` and the cases above
# were written against that; a recording stub that also PRINTS would become a live input
# to them the moment anyone gives $SCRATCH a checkout — an unobserved change of stub
# contract is exactly how a stub starts lying about a leg nobody is asserting on.
# ---------------------------------------------------------------------------
echo "== Open-PRs leg — fixture =="
PRHOME="$TMP/prs"; mkdir -p "$PRHOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$PRHOME/.local/bin/board-snapshot"
chmod +x "$PRHOME/.local/bin/board-snapshot"
# All FIVE BSC_WORKTREES entries exist here ON PURPOSE: the two -prod clones must be
# absent from the query because the PR list excludes them, not because the `-e .git`
# skip guard fired. Without them present, the absence assertions below would pass on a
# leg that queried every repo it was given.
for d in agent-webhook-bridge-dev agent-webhook-bridge-prod kanbanboard \
         agent-board-toolkit agent-board-toolkit-prod; do
    mkdir -p "$PRHOME/$d/.git"
done

PRSHIM="$TMP/prshim"; mkdir -p "$PRSHIM"
# git answers `remote get-url origin` and NOTHING else — the leg derives its query set from
# that URL, so a silent `exit 0` would hand every entry an empty key. Empty is not "no
# duplicate"; it is the leg's UNREADABLE signal, so all five would take their own slot and
# the dedupe would never be exercised at all. Every other subcommand stays the silent
# `exit 0` the branch-reality and hook-dispatch legs in this same invocation were written
# against — they are not this block's subject.
#
# The two -prod clones deliberately return the SAME url as their siblings. That byte-for-byte
# identity is the entire input to the dedupe; if these ever diverge, the -prod absence
# assertions below would pass for the wrong reason.
#
# PR_NOREMOTE_REPO makes one checkout's remote unreadable (git REFUSING, the real-world
# shape: no origin configured, or a broken repo), for the fail-closed case.
cat > "$PRSHIM/git" <<'EOF'
#!/bin/sh
_d=''
[ "$1" = '-C' ] && { _d="$(basename "$2")"; shift 2; }
case "$1 ${2:-} ${3:-}" in
  'remote get-url origin')
    for _n in ${PR_NOREMOTE_REPO:-}; do
        [ "$_d" = "$_n" ] && { echo "error: No such remote 'origin'" >&2; exit 2; }
    done
    case "$_d" in
      agent-webhook-bridge-dev|agent-webhook-bridge-prod)
        echo https://github.com/PupFuzz/agent-webhook-bridge.git ;;
      kanbanboard)
        echo https://github.com/PupFuzz/kanban-board.git ;;
      agent-board-toolkit|agent-board-toolkit-prod)
        echo https://github.com/PupFuzz/agent-board-toolkit.git ;;
    esac ;;
esac
exit 0
EOF
chmod +x "$PRSHIM/git"
cat > "$PRSHIM/gh" <<'EOF'
#!/bin/sh
# Records "<cwd basename>|<argv>" per call — the cwd IS the evidence of which repo was
# queried, since the leg identifies the repo by cd-ing into it. Then emits TWO lines, so
# an assertion can tell a label applied to every line from one applied to the first.
_r="$(basename "$(pwd)")"
printf '%s|%s\n' "$_r" "$*" >> "$GH_LOG"
case "$_r" in
    "${GH_FAIL_REPO:-__no_such_repo__}") echo "gh: boom" >&2; exit 1 ;;
esac
echo "11 OPEN first-pr"
echo "22 OPEN second-pr"
EOF
chmod +x "$PRSHIM/gh"
GH_LOG="$TMP/gh.log"

# run_prs [fail-repo] — run the ritual against $PRHOME with the recording gh, on a hook
# that detects cleanly (so the ritual's own rc is 0 and any change to it is this leg's).
run_prs() {
    : > "$GH_LOG"
    HOME="$PRHOME" PATH="$PRSHIM:$UB" KANBAN_RECONCILE_HOOK="$goodhook" \
        GH_LOG="$GH_LOG" GH_FAIL_REPO="${1:-}" PR_NOREMOTE_REPO="${2:-}" \
        bash "$BIN" >"$OUTF" 2>"$ERRF"; echo $?
}

echo "== Open-PRs leg — queries exactly the three unique GitHub repos, in list order =="
rc="$(run_prs)"
eq "the ritual still exits 0" "0" "$rc"
eq "exactly the three unique repos are queried, in BSC_WORKTREES order, with the same argv" \
"agent-webhook-bridge-dev|pr list --state open --limit 10
kanbanboard|pr list --state open --limit 10
agent-board-toolkit|pr list --state open --limit 10" "$(cat "$GH_LOG")"

# ABSENCE + WITNESS, same run. A second checkout of an already-queried repo reports the
# same open PRs twice, so the -prod clones must not be queried. Since card#5227 they are
# excluded BY THE DEDUPE — their remote URL is byte-identical to their sibling's — not by
# a literal list that omitted them. Each absence is paired with the non--prod sibling of
# the SAME repo observed present in the SAME log, so a gh that never ran at all cannot
# read as a pass.
eq "witness: agent-board-toolkit WAS queried" "true" \
   "$(has 'agent-board-toolkit|' "$(cat "$GH_LOG")")"
eq "the -prod toolkit clone is NOT queried" "false" \
   "$(has 'agent-board-toolkit-prod|' "$(cat "$GH_LOG")")"
eq "witness: agent-webhook-bridge-dev WAS queried" "true" \
   "$(has 'agent-webhook-bridge-dev|' "$(cat "$GH_LOG")")"
eq "the -prod bridge clone is NOT queried" "false" \
   "$(has 'agent-webhook-bridge-prod|' "$(cat "$GH_LOG")")"
# …and it is the LIST that excluded them, not the skip guard: both -prod checkouts are
# present in the fixture. Without this the two assertions above are decorations.
eq "witness: the -prod toolkit checkout IS present in the fixture" "true" \
   "$([[ -e "$PRHOME/agent-board-toolkit-prod/.git" ]] && echo true || echo false)"
eq "witness: the -prod bridge checkout IS present in the fixture" "true" \
   "$([[ -e "$PRHOME/agent-webhook-bridge-prod/.git" ]] && echo true || echo false)"

echo "== Open-PRs leg — an UNREADABLE remote keeps its own slot; it is never deduped away =="
# The load-bearing case, and the one that inverts the naive derivation. Dropping an entry
# whose remote cannot be read would fail OPEN: the section would render clean having
# silently queried fewer repos. So an unreadable remote must land in the query set on its
# own AND be named. Directly paired with the assertion above that the SAME checkout is
# absent when its remote IS readable — so this cannot pass on a leg that simply queries
# everything.
rc="$(run_prs "" agent-board-toolkit-prod)"
eq "an unreadable remote does not change the ritual's exit code" "0" "$rc"
eq "the unreadable checkout IS queried, on its own slot, after the three it could not join" \
"agent-webhook-bridge-dev|pr list --state open --limit 10
kanbanboard|pr list --state open --limit 10
agent-board-toolkit|pr list --state open --limit 10
agent-board-toolkit-prod|pr list --state open --limit 10" "$(cat "$GH_LOG")"
eq "…and the unreadable checkout is NAMED, not silently absorbed" "true" \
   "$(has '⚠ agent-board-toolkit-prod: could not read' "$(cat "$OUTF")")"
# The warning is on STDOUT, inside this leg's own section — deliberately not stderr. The
# failure direction here is safe by construction (an extra query, never a drop), so it is
# not the canon-#9 'degraded coverage must not read as a clean pass' class this file
# reserves stderr + ⚠ for; and stderr is shared by every leg, so a per-leg diagnostic
# there would couple every other block's $ERRF assertions to THIS leg's stub fidelity.
eq "the warning does not leak onto the shared stderr channel" "false" \
   "$(has 'could not read' "$(cat "$ERRF")")"
# Witness that the dedupe still ran in the SAME run: the bridge -prod clone, whose remote
# is still readable, is still absent. Without this, the assertion above would also pass on
# a leg whose dedupe had been disabled outright.
eq "witness: the still-readable -prod bridge clone is STILL deduped away in that run" "false" \
   "$(has 'agent-webhook-bridge-prod|' "$(cat "$GH_LOG")")"

# TWO unreadable remotes must NOT collapse into each other. The empty key is deliberately
# never recorded as a seen key — recording it would make the FIRST unreadable entry dedupe
# away every later one, which is the same silent-drop this whole branch exists to prevent,
# and the single-unreadable case above cannot tell the two implementations apart.
rc="$(run_prs "" "agent-webhook-bridge-prod agent-board-toolkit-prod")"
eq "two unreadable remotes each keep their own slot — an empty key is not a dedup key" \
"agent-webhook-bridge-dev|pr list --state open --limit 10
agent-webhook-bridge-prod|pr list --state open --limit 10
kanbanboard|pr list --state open --limit 10
agent-board-toolkit|pr list --state open --limit 10
agent-board-toolkit-prod|pr list --state open --limit 10" "$(cat "$GH_LOG")"
eq "…and BOTH are named, not just the first" "true" \
   "$([[ $(grep -c '⚠ agent-.*: could not read' "$OUTF") == 2 ]] && echo true || echo false)"

echo "== Open-PRs leg — every emitted line carries its own '  <repo>: ' label =="
rc="$(run_prs)"
eq "the FIRST line of a repo's output is labelled" "true" \
   "$(has '  agent-board-toolkit: 11 OPEN first-pr' "$(cat "$OUTF")")"
eq "…and so is the SECOND — the label is per LINE, not per repo" "true" \
   "$(has '  agent-board-toolkit: 22 OPEN second-pr' "$(cat "$OUTF")")"
eq "six labelled PR lines in all (2 per queried repo), each under its own repo's name" "6" \
   "$(grep -cE '^  (agent-webhook-bridge-dev|kanbanboard|agent-board-toolkit): [0-9]+ OPEN ' "$OUTF")"

echo "== Open-PRs leg — a repo with no local checkout is SKIPPED, the rest still run =="
mv "$PRHOME/kanbanboard/.git" "$PRHOME/kanbanboard/.git-off"
rc="$(run_prs)"
eq "a missing checkout does not change the ritual's exit code" "0" "$rc"
eq "the checkout-less repo is not queried; the other two still are (witness in the same log)" \
"agent-webhook-bridge-dev|pr list --state open --limit 10
agent-board-toolkit|pr list --state open --limit 10" "$(cat "$GH_LOG")"
eq "…and the skipped repo produces no labelled output either" "false" \
   "$(has '  kanbanboard: ' "$(cat "$OUTF")")"
mv "$PRHOME/kanbanboard/.git-off" "$PRHOME/kanbanboard/.git"

echo "== Open-PRs leg — a failing gh is swallowed and does NOT stop the repos after it =="
# WITNESS for the stderr-suppression assertion below: the stub really does write that
# string to stderr, so its absence from the ritual's stderr is SUPPRESSION and not a stub
# that stayed silent.
ghwit="$(cd "$PRHOME/kanbanboard" && GH_LOG=/dev/null GH_FAIL_REPO=kanbanboard \
         "$PRSHIM/gh" pr list 2>&1 >/dev/null)"
eq "witness: the failing stub writes 'gh: boom' to STDERR" "true" "$(has 'gh: boom' "$ghwit")"
rc="$(run_prs kanbanboard)"
eq "a failing gh does not change the ritual's exit code" "0" "$rc"
eq "the repo AFTER the failing one is still queried" "true" \
   "$(has 'agent-board-toolkit|' "$(cat "$GH_LOG")")"
eq "…and its PR lines still reach stdout" "true" \
   "$(has '  agent-board-toolkit: 11 OPEN first-pr' "$(cat "$OUTF")")"
eq "the failing repo emits no labelled output" "false" \
   "$(has '  kanbanboard: ' "$(cat "$OUTF")")"
eq "gh's stderr is suppressed, so its failure never reaches the ritual's stderr" "false" \
   "$(has 'gh: boom' "$(cat "$ERRF")")"

# ---------------------------------------------------------------------------
# The '── Local branch reality ──' leg (card#5370) — main's FIRST loop, and the OTHER
# consumer of BSC_WORKTREES (so card#5227's dedupe-on-remote-URL lands on this leg's input
# too, and the Open-PRs block above pinned only the PR side).
#
# Nothing asserted on it before: every case above runs main with a HOME holding no
# checkouts, so `[[ -e $wt/.git ]]` skips every entry and the silent `exit 0` git stub is
# never executed — from there, a leg that works and a leg that renders nothing are
# indistinguishable.
#
# The CHECKOUT TREE is reused — $PRHOME already creates all five BSC_WORKTREES entries, and
# a second one would be a second thing to keep in step with that list. The SHIM is its own:
# $PRSHIM/git answers `remote get-url origin` and stays a silent `exit 0` for everything
# else ON PURPOSE, and a git that answered `branch --show-current` or `status --porcelain`
# there would become an unobserved live input to the cases above, which were written
# against silence for exactly those two subcommands.
#
# The converse holds here and is why this shim is NOT given a `remote get-url` answer: the
# Open-PRs leg runs inside these same invocations, so under $BRSHIM every entry's remote
# reads UNREADABLE and each takes its own slot. That is inert for this block — the
# assertions below read the branch-reality section and $BR_LOG, and the leg's warning is
# confined to its own stdout section — and it is deliberate: it keeps this block's
# subject the branch-reality leg, not a second copy of the dedupe's coverage.
# ---------------------------------------------------------------------------
echo "== branch-reality leg — fixture =="
BRSHIM="$TMP/brshim"; mkdir -p "$BRSHIM"
BR_LOG="$TMP/br-git.log"
# Per-repo answers, so ONE run carries every rendering this leg can produce: a clean repo on
# a branch, a dirty one, and the two distinct ways `branch=?` is reached — git answering
# EMPTY (detached HEAD) and git REFUSING. Every other subcommand stays the silent `exit 0`
# the hook-dispatch leg in the same invocation was written against.
cat > "$BRSHIM/git" <<'EOF'
#!/bin/sh
# Records "<repo>|<argv after -C>" so the SKIP case can assert git was never ASKED about a
# checkout-less entry — a stronger claim than "nothing was printed for it".
_d=''
[ "$1" = '-C' ] && { _d="$(basename "$2")"; shift 2; }
printf '%s|%s\n' "$_d" "$*" >> "$BR_LOG"
case "$1 ${2:-}" in
  'branch --show-current')
    case "$_d" in
      agent-webhook-bridge-dev)  echo dev ;;
      agent-webhook-bridge-prod) echo release/v1.2.3 ;;
      kanbanboard)               echo main ;;
      agent-board-toolkit)       : ;;          # empty stdout at rc 0 — detached HEAD
      agent-board-toolkit-prod)  exit 128 ;;   # git refused this checkout outright
    esac ;;
  'status --porcelain')
    case "$_d" in
      agent-webhook-bridge-prod) echo ' M bin/board-session-close' ;;
    esac ;;
esac
exit 0
EOF
chmod +x "$BRSHIM/git"
# gh is stubbed silent as well: the Open-PRs leg runs in these same invocations, and a real
# gh on $UB would turn this block into a network test the moment it is found.
printf '#!/bin/sh\nexit 0\n' > "$BRSHIM/gh"; chmod +x "$BRSHIM/gh"

run_br() {
    : > "$BR_LOG"
    HOME="$PRHOME" PATH="$BRSHIM:$UB" KANBAN_RECONCILE_HOOK="$goodhook" \
        BR_LOG="$BR_LOG" bash "$BIN" >"$OUTF" 2>"$ERRF"; echo $?
}
# The leg's own section, bounded by its header and the blank line that closes it — NOT a
# grep for 'branch=', under which a mutated label would read as an empty section rather
# than a changed one, and the ORDER and COUNT of the lines would go unpinned.
brblock() { sed -n '/── Local branch reality/,/^$/p' "$OUTF" | sed '1d;$d'; }
# Only this leg issues these two subcommands; the hook-dispatch leg's rev-parse/config calls
# share the log and are not this block's subject.
brcalls() { grep -E '\|(branch --show-current|status --porcelain)$' "$BR_LOG" || true; }

echo "== branch-reality leg — one line per PRESENT checkout, in BSC_WORKTREES order =="
rc="$(run_br)"
eq "the branch-reality run exits 0" "0" "$rc"
eq "every present checkout gets exactly one line, in list order, under its OWN name" \
"• agent-webhook-bridge-dev: branch=dev
• agent-webhook-bridge-prod: branch=release/v1.2.3 (uncommitted changes)
• kanbanboard: branch=main
• agent-board-toolkit: branch=?
• agent-board-toolkit-prod: branch=?" "$(brblock)"
eq "git is asked for BOTH the branch and the dirty state of every one of the five" \
"agent-webhook-bridge-dev|branch --show-current
agent-webhook-bridge-dev|status --porcelain
agent-webhook-bridge-prod|branch --show-current
agent-webhook-bridge-prod|status --porcelain
kanbanboard|branch --show-current
kanbanboard|status --porcelain
agent-board-toolkit|branch --show-current
agent-board-toolkit|status --porcelain
agent-board-toolkit-prod|branch --show-current
agent-board-toolkit-prod|status --porcelain" "$(brcalls)"

echo "== branch-reality leg — the dirty suffix, and its ABSENCE on a clean tree =="
eq "a tree with porcelain output carries the ' (uncommitted changes)' suffix" "true" \
   "$(has '• agent-webhook-bridge-prod: branch=release/v1.2.3 (uncommitted changes)' "$(brblock)")"
eq "witness: the CLEAN repo's line is rendered in that same run" "true" \
   "$(has '• agent-webhook-bridge-dev: branch=dev' "$(brblock)")"
eq "…and it does NOT carry the suffix — the suffix is keyed on the porcelain output" "false" \
   "$(has '• agent-webhook-bridge-dev: branch=dev (uncommitted changes)' "$(brblock)")"

echo "== branch-reality leg — an unresolvable branch renders '?', not an empty value =="
# Witnessed against the stub ITSELF, so 'the fallback fired' is distinguishable from 'the
# stub never ran' — the failure mode this whole block exists to close.
brwit="$(BR_LOG=/dev/null "$BRSHIM/git" -C "$PRHOME/agent-board-toolkit" branch --show-current)"; brwrc=$?
eq "witness: the stub answers EMPTY at rc 0 for the detached-HEAD repo" "0|" "$brwrc|$brwit"
brwit="$(BR_LOG=/dev/null "$BRSHIM/git" -C "$PRHOME/agent-board-toolkit-prod" branch --show-current)"; brwrc=$?
eq "witness: …and REFUSES at rc 128 for the other one" "128|" "$brwrc|$brwit"
eq "an EMPTY branch answer renders 'branch=?'" "true" \
   "$(has '• agent-board-toolkit: branch=?' "$(brblock)")"
eq "a REFUSED branch query renders 'branch=?' as well" "true" \
   "$(has '• agent-board-toolkit-prod: branch=?' "$(brblock)")"

echo "== branch-reality leg — a checkout-less entry is SKIPPED, not rendered as unknown =="
mv "$PRHOME/kanbanboard/.git" "$PRHOME/kanbanboard/.git-off"
rc="$(run_br)"
eq "a missing checkout leaves the branch-reality run's exit code alone" "0" "$rc"
eq "witness: that entry really has no checkout in this run" "false" \
   "$([[ -e "$PRHOME/kanbanboard/.git" ]] && echo true || echo false)"
eq "witness: …while the entries around it still do" "true" \
   "$([[ -e "$PRHOME/agent-board-toolkit/.git" ]] && echo true || echo false)"
eq "the checkout-less entry gets NO line — not even a 'branch=?' one" "false" \
   "$(has '• kanbanboard: ' "$(brblock)")"
eq "…and git is never asked about it, while the other four still are" \
"agent-webhook-bridge-dev|branch --show-current
agent-webhook-bridge-dev|status --porcelain
agent-webhook-bridge-prod|branch --show-current
agent-webhook-bridge-prod|status --porcelain
agent-board-toolkit|branch --show-current
agent-board-toolkit|status --porcelain
agent-board-toolkit-prod|branch --show-current
agent-board-toolkit-prod|status --porcelain" "$(brcalls)"
mv "$PRHOME/kanbanboard/.git-off" "$PRHOME/kanbanboard/.git"

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
# PATH is scoped to each substitution ON PURPOSE: every probe needs its own, and none may leak
# into the next.
# shellcheck disable=SC2030,SC2031
report()        { RN=0; ROUT="$(PATH="$TK/bin:$UB"; _bsc_hook_dispatch_report "$@")" || RN=$?; }
# shellcheck disable=SC2030,SC2031
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
eq "not executable: NOT-RUNNABLE"            "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
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

# --- core.hooksPath git cannot expand ⇒ a REFUSAL with a specific cause, by either route ---
# WHICH arm reports this is git-version-dependent, so this block asserts the BEHAVIOUR both arms
# must guarantee and accepts either route to it. The history is the reason it is written this
# way: on git 2.43.0 an unexpandable path-type value is expanded during the general config read,
# so every command in the repo fatals and the rc-1 arm reports it in git's own words; on git
# 2.54.0 `rev-parse` succeeds and only the explicit `--path` read fatals, so the rc-6 arm
# reports it. This test previously pinned rc 1 — it passed four review rounds on one host and
# failed on CI's first run in a second environment. Pinning the arm was the defect; the
# guarantee is what matters, and it is the same either way:
#   * NEVER folded into "unset" (rc 0/2 here would mean the repo was read as ordinarily
#     configured, and a perfectly-wired .git/hooks sits in this fixture to make that a ✓);
#   * reported as a FINDING, with a cause specific enough to act on.
r="$H/hookspath-baduser"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
git -C "$r" config core.hooksPath '~nosuchuser-abc/x'
_rc=0; _d="$(_bsc_hooks_dir "$r")" || _rc=$?
case "$_rc" in
  1) ok "unexpandable hooksPath: refused via the rc-1 arm (git fatals repo-wide on this build)" ;;
  6) ok "unexpandable hooksPath: refused via the rc-6 arm (only the --path read fatals here)" ;;
  *) bad "unexpandable hooksPath: expected a refusal (rc 1 or 6), got rc=$_rc — rc 0/2 would mean it was folded into 'unset'" ;;
esac
eq "unexpandable hooksPath: a cause is carried out, not an empty answer" "true" \
   "$([ -n "$_d" ] && echo true || echo false)"
case "$_d" in
  *"expand user dir"*|*"cannot expand"*) ok "unexpandable hooksPath: the cause names the expansion failure" ;;
  *) bad "unexpandable hooksPath: cause did not name the expansion failure: $_d" ;;
esac
report "$r"
eq "unexpandable hooksPath: IS a finding"                     "1" "$RN"
case "$ROUT" in
  *"expand user dir"*|*"cannot expand"*) ok "unexpandable hooksPath: the report states the cause" ;;
  *) bad "unexpandable hooksPath: the report did not state the cause" ;;
esac
# The guarantee that actually matters: a wired .git/hooks must NOT let this read as healthy.
eq "unexpandable hooksPath: never reported ✓ despite a perfect .git/hooks" "false" \
   "$(saw "✓ post-checkout")"

# …and the OTHER arm, on every host. The block above exercises whichever route the local git
# takes; this one forces the other with a `git` shim that reproduces the newer build's shape
# (rev-parse succeeds, only the explicit --path read fatals), so both arms are covered wherever
# the suite runs. Without this, an arm is only ever exercised on the git versions that happen to
# route to it — which is precisely how it stayed uncovered while four review passes on one host
# called it dead code.
shimdir="$TMP/gitshim"; mkdir -p "$shimdir"
# shellcheck disable=SC2016  # the unexpanded $ are the SHIM's own source, not this script's
{ printf '#!/bin/sh\n'
  printf 'for a in "$@"; do case "$a" in --path) p=1 ;; core.hooksPath) k=1 ;; esac; done\n'
  printf 'if [ -n "$p" ] && [ -n "$k" ]; then echo "fatal: failed to expand user dir in: '"'"'~nosuchuser-abc/x'"'"'" >&2; exit 128; fi\n'
  printf 'exec %s "$@"\n' "$(command -v git)"
} > "$shimdir/git"; chmod +x "$shimdir/git"
r="$H/hookspath-baduser-shim"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"
# shellcheck disable=SC2031  # the "modified in a subshell" chain is report()'s, not this line's
_savedpath="$PATH"; PATH="$shimdir:$PATH"    # restored below
_rc=0; _d="$(_bsc_hooks_dir "$r")" || _rc=$?
eq "forced rc-6 arm: refused, not folded into 'unset'" "6" "$_rc"
eq "forced rc-6 arm: carries a cause out, like the rc-1 arm does" "true" \
   "$(case "$_d" in *"cannot expand"*) echo true ;; *) echo false ;; esac)"
_out="$(_bsc_hook_dispatch_report "$r" 2>&1)"
PATH="$_savedpath"
eq "forced rc-6 arm: the report states the cause" "true" \
   "$(case "$_out" in *"cannot expand"*) echo true ;; *) echo false ;; esac)"
eq "forced rc-6 arm: never reported ✓ despite a perfect .git/hooks" "false" \
   "$(case "$_out" in *"✓ post-checkout"*) echo true ;; *) echo false ;; esac)"

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

# The extraction closed a gap nobody had reported: a DIRECTORY named post-checkout is -e and
# -x, so only a file-type test catches it. It is covered here because the ONE predicate now
# owns every runnability fact — this is the property the extraction was for.
r="$H/hook-is-a-dir"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
mkdir -p "$r/.git/hooks/post-checkout"
eq "a DIRECTORY where the hook should be: NOT-RUNNABLE" "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
eq "…and the reason says so"  "true" \
   "$(case "$(_bsc_state_reason NOT-RUNNABLE "$r/.git/hooks/post-checkout" post-checkout)" in *"is a directory"*) echo true ;; *) echo false ;; esac)"
rm -rf "$r/.git/hooks/post-checkout"

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

# --- the four bounds that were claimed as pinned but were not (M3) ----------
# docs/HOOKS.md asserts every disclosed bound is fixture-pinned. Three were. These are the rest,
# so the claim is now true rather than aspirational.
r="$H/bound-hashquote"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\necho "#"; board-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "BOUND: the # strip blanks a line that quotes # (errs to a FINDING)" \
   "NO-REACH" "$(state "$r/.git/hooks")"
r="$H/bound-varchain"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
# shellcheck disable=SC2016  # $TOOLKIT must reach the hook UNexpanded — that is the fixture
printf '#!/bin/sh\nTOOLKIT=%s\nexec "$TOOLKIT/hooks/post-checkout" "$@"\n' "$TK" > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "BOUND: a VARIABLE chain target reads as a finding though it works" \
   "NO-REACH" "$(state "$r/.git/hooks")"
# The target must EXIST, or this is green for the wrong reason: with no ../tk the hook is just
# `exec: not found` (rc 127), and the assertion cannot tell "relative chains are not followed"
# from "the target is absent" — an implementation of relative-chain resolution would flip real
# behaviour while this stayed green. git runs hooks with CWD at the work-tree root
# (githooks(5)), so ../tk resolves beside the repo; it is created and exercised here.
r="$H/bound-relchain"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
mkdir -p "$H/tk/hooks"
printf '#!/bin/sh\nboard-card-start\n' > "$H/tk/hooks/post-checkout"; chmod +x "$H/tk/hooks/post-checkout"
printf '#!/bin/sh\nexec ../tk/hooks/post-checkout "$@"\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "witness: the relative chain target exists and RUNS from the work-tree root" "0" \
   "$(cd "$r" && PATH="$TK/bin:$UB" ./.git/hooks/post-checkout >/dev/null 2>&1; echo $?)"
eq "BOUND: a RELATIVE chain target reads as a finding though it works" \
   "NO-REACH" "$(state "$r/.git/hooks")"
r="$H/bound-wrapper"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
mkdir -p "$H/wrapdir"; printf '#!/bin/sh\nboard-card-start\n' > "$H/wrapdir/run-hooks.sh"
chmod +x "$H/wrapdir/run-hooks.sh"
printf '#!/bin/sh\nexec %s/wrapdir/run-hooks.sh "$@"\n' "$H" > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "BOUND: a chain through a non-hooks/<name> wrapper reads as a finding" \
   "NO-REACH" "$(state "$r/.git/hooks")"

# BOUND: an interpreter name that does not TERMINATE within the kernel's shebang buffer
# (BINPRM_BUF_SIZE, 256 bytes on Linux). The check reads the whole line and answers "runnable";
# the kernel truncates, and on the kernel verified here (6.8, git 2.43) the named interpreter is
# then silently ignored and the shell runs the file — a wrong-interpreter hazard, not a dead
# hook. The trigger is the interpreter not terminating in 256 bytes, NOT the line being long.
r="$H/bound-binprm"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
longdir="$H/$(printf 'd%.0s' $(seq 1 250))"; mkdir -p "$longdir"
cp "$TK/bin/board-card-start" "$longdir/sh"; chmod +x "$longdir/sh"
printf '#!%s/sh\nboard-card-start\n' "$longdir" > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
_first="$(head -1 "$r/.git/hooks/post-checkout")"
eq "witness: the interpreter does NOT terminate within 256 bytes" "true" \
   "$([ "${#_first}" -gt 256 ] && echo true || echo false)"
eq "witness: that interpreter is itself a real executable" "true" \
   "$([ -x "$longdir/sh" ] && echo true || echo false)"
eq "BOUND: over-long interpreter reads as runnable — disclosed, not detected" \
   "OK" "$(state "$r/.git/hooks")"
# BOUND (broader than the truncation case, and the reason the previous "safe half" assertion
# here was WRONG): the shebang ARGUMENT is never judged. `#!/bin/sh zzz` is twelve bytes, reads
# as runnable, and is DEAD — /bin/sh treats zzz as a script path and exits "cannot open zzz".
# The old assertion claimed a 500-byte argument was "genuinely runnable"; run for real it dies
# the same way, so that fixture pinned a dead hook as healthy and blocked the correct fix.
r="$H/bound-shebang-arg"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh zzz\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "BOUND: an interpreter ARGUMENT that kills the hook reads as runnable" \
   "OK" "$(state "$r/.git/hooks")"
# The control that keeps the bound honest: an argument the interpreter ACCEPTS is genuinely
# fine, so the bound is about the argument not being judged — not about arguments per se.
printf '#!/bin/sh -e\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "an interpreter flag argument (-e) is genuinely runnable" "OK" "$(state "$r/.git/hooks")"

# --- the remediation line must name a command that actually works -----------
# The line is derived from the INSTALLER's own disposition, never assumed from the path shape.
# Until card#5311 a `--separate-git-dir` checkout was refused, so the right answer here was "it
# cannot fix this, wire it by hand". That topology now installs, so the right answer is the
# installer itself — and these assertions moved with the behaviour rather than being relaxed:
# each still pins an exact string, and the by-hand fallback is now asserted ABSENT.
r="$H/fixline-plain"; mkrepo "$r"
report "$r"
eq "plain repo: names install-board-hooks on the repo itself" "true" "$(saw "fix: install-board-hooks $r")"
git init -q --separate-git-dir="$H/sgd-gitdir" "$H/sgd" 2>/dev/null
eq "separate-git-dir: .git really is a file" "true" "$([ -f "$H/sgd/.git" ] && echo true || echo false)"
eq "separate-git-dir: dispatch dir is the EXTERNAL git dir" "$H/sgd-gitdir/hooks" "$(_bsc_hooks_dir "$H/sgd")"
eq "separate-git-dir: the INSTALLER view names that same dir (card#5311)" "$H/sgd-gitdir/hooks" \
   "$(_bsc_hooks_dir "$H/sgd" installer)"
report "$H/sgd"
eq "separate-git-dir: the installer IS the fix, named on this repo" "true" \
   "$(saw "fix: install-board-hooks $H/sgd")"
eq "separate-git-dir: no longer claims it cannot fix this" "false" \
   "$(saw "cannot fix this")"
eq "separate-git-dir: does NOT fall back to manual wiring" "false" \
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
eq "CRLF shebang (and -x): NOT-RUNNABLE"  "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
report "$r"
eq "CRLF shebang: IS a finding"          "1" "$RN"
eq "CRLF shebang: names CRLF as the cause" "true" "$(saw "CRLF")"
# The positive control: the SAME hook with LF endings is OK, so the line endings are what
# decided it — not the content, the bit, or the path.
printf '#!/bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
eq "the SAME hook with LF endings is OK"  "OK" "$(state "$r/.git/hooks")"

# Tabs: the kernel skips leading whitespace after `#!` and ends the interpreter at the next
# one. git RUNS both of these (verified); calling them DEAD is a false red on a healthy repo,
# and it used to be followed by a remediation that fails.
for tabcase in leading trailing; do
    r="$H/tab-$tabcase"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
    if [[ "$tabcase" == leading ]]; then printf '#!\t/bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
    else printf '#!/bin/sh\t\nboard-card-start\n' > "$r/.git/hooks/post-checkout"; fi
    chmod +x "$r/.git/hooks/post-checkout"
    eq "tab ($tabcase) in the shebang is NOT a finding — git runs it" "OK" "$(state "$r/.git/hooks")"
done
# …and the separator set is SPACE AND TAB ONLY. A POSIX [[:space:]] class also matches CR, VT,
# NL and FF, which silently trimmed a broken interpreter name down to a runnable one: git said
# "cannot exec" while we said healthy. Both verified against real dispatch.
for wscase in cr vt; do
    r="$H/ws-$wscase"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
    if [[ "$wscase" == cr ]]; then printf '#!/bin/sh\r -e\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
    else printf '#!\v/bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"; fi
    chmod +x "$r/.git/hooks/post-checkout"
    eq "shebang separated by $wscase is NOT runnable (git: cannot exec)" \
       "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
done
# The control that keeps the fix honest: space and tab still separate, so these stay runnable.
r="$H/ws-ok"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!  /bin/sh\nboard-card-start\n' > "$r/.git/hooks/post-checkout"; chmod +x "$r/.git/hooks/post-checkout"
eq "leading SPACES still separate (runnable)" "OK" "$(state "$r/.git/hooks")"

# A shebang naming a DIRECTORY is not runnable, though -x is true for one.
r="$H/interp-dir"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/tmp\nboard-card-start\n' > "$r/.git/hooks/post-checkout"; chmod +x "$r/.git/hooks/post-checkout"
eq "a shebang interpreter that is a DIRECTORY: NOT-RUNNABLE" "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
# A first line with NO trailing newline must still be judged.
r="$H/nonewline"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/usr/bin/nosuchinterp-xyz' > "$r/.git/hooks/post-checkout"; chmod +x "$r/.git/hooks/post-checkout"
eq "an unterminated first line is still judged" "NOT-RUNNABLE" "$(state "$r/.git/hooks")"

r="$H/nointerp"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/usr/bin/nosuchinterp-abc\nboard-card-start\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
eq "missing shebang interpreter (and -x): NOT-RUNNABLE" "NOT-RUNNABLE" "$(state "$r/.git/hooks")"
eq "…and it names the interpreter"       "true" \
   "$(case "$(_bsc_state_reason NOT-RUNNABLE "$r/.git/hooks/post-checkout" post-checkout)" in *nosuchinterp-abc*) echo true ;; *) echo false ;; esac)"
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

# --- the fix-line must never name a command that exits 1 --------------------
# It gates on install-board-hooks' OWN `--check` dry run rather than modelling its
# preconditions: a partial copy proved 2 of 9 and put a failing command in front of the MOST
# COMMON finding. Every case below asserts the TEXT that is printed, not merely the absence of
# the wrong text — an absence-only assertion let incoherent operator-facing wording through
# twice in this suite.
#
# THE MODAL CASE: a repo carrying its own committed post-checkout. That is the likeliest real
# cause of a dead auto-move, and the installer refuses to clobber it.
r="$H/ownhook"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
printf '#!/bin/sh\nexec ./scripts/local-secret-scan\n' > "$r/.git/hooks/post-checkout"
chmod +x "$r/.git/hooks/post-checkout"
_rc=0; bash "$IBH2" --check "$r" >/dev/null 2>&1 || _rc=$?
eq "own committed hook: install-board-hooks --check REFUSES it (rc 1)" "1" "$_rc"
report "$r"
eq "own committed hook: the finding is reported"       "1" "$RN"
eq "own committed hook: no install command is offered" "false" "$(saw "fix: install-board-hooks")"
eq "own committed hook: quotes the installer's OWN refusal" "true" \
   "$(saw "refusing to overwrite an existing non-symlink hook")"
eq "own committed hook: tells the operator to resolve it and re-run" "true" \
   "$(saw "resolve that, then re-run it")"
# …and NEVER suggests an ln -s here: on this case it would destroy the operator's own hook.
eq "own committed hook: no ln -s suggestion (it would destroy that hook)" "false" "$(saw "ln -s")"

# An UNWRITABLE dispatch dir — the second instance of the same class.
r="$H/unwritable"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/post-checkout"
chmod a-w "$r/.git/hooks"
report "$r"
eq "unwritable hooks dir: no install command is offered" "false" "$(saw "fix: install-board-hooks")"
eq "unwritable hooks dir: names writability as the obstacle" "true" "$(saw "not writable")"
chmod u+w "$r/.git/hooks"

# A core.hooksPath naming a REGULAR FILE: same path on both sides, so the old arm asserted the
# two "differ" while printing one path twice. It must name the real obstacle instead.
r="$H/hookspath-isfile"; mkrepo "$r"; : > "$H/not-a-dir"
git -C "$r" config core.hooksPath "$H/not-a-dir"
report "$r"
eq "hooksPath is a regular file: no install command is offered" "false" "$(saw "fix: install-board-hooks")"
eq "hooksPath is a regular file: names the real obstacle"       "true" \
   "$(saw "exists but is not a directory")"
eq "hooksPath is a regular file: does NOT claim the two paths differ" "false" \
   "$(saw "but git dispatches from")"

# --check must NEVER write, from any argument position, and a mis-invocation must not be read
# as an install. Accepting the flag only in position 1 made `install-board-hooks <repo> --check`
# perform a real install — the one contract this flag has, broken by its likeliest mis-spelling.
mkrepo "$H/argpos"
_rc=0; bash "$IBH2" "$H/argpos" --check >/dev/null 2>&1 || _rc=$?
eq "--check AFTER the repo: rc 0"              "0" "$_rc"
eq "--check AFTER the repo: still wrote NOTHING" "false" \
   "$([ -e "$H/argpos/.git/hooks/post-checkout" ] && echo true || echo false)"
_rc=0; bash "$IBH2" "$H/argpos" extra-arg >/dev/null 2>&1 || _rc=$?
eq "an extra positional is rejected (rc 2), not ignored" "2" "$_rc"
eq "…and the extra-positional refusal installed nothing" "false" \
   "$([ -e "$H/argpos/.git/hooks/post-checkout" ] && echo true || echo false)"
_rc=0; bash "$IBH2" --bogus "$H/argpos" >/dev/null 2>&1 || _rc=$?
eq "an unknown option is rejected (rc 2)"      "2" "$_rc"

# An explicitly-empty positional must not be invisible: it used to be swallowed, so the NEXT
# positional silently became the repo and the rc-2 guarantee above was defeated. Each guard is
# asserted by its OWN message, so mutating either one changes which message appears.
_rc=0; _o="$(bash "$IBH2" "" 2>&1)" || _rc=$?
eq "a lone EMPTY positional is rejected (rc 2), not treated as a repo" "2" "$_rc"
eq "…and says the argument was empty"  "true" \
   "$(case "$_o" in *"is empty"*) echo true ;; *) echo false ;; esac)"
_rc=0; _o="$(bash "$IBH2" "" "$H/argpos" 2>&1)" || _rc=$?
eq "an empty positional does not let the NEXT one become the repo (rc 2)" "2" "$_rc"
eq "…and the empty-positional refusal installed nothing" "false" \
   "$([ -e "$H/argpos/.git/hooks/post-checkout" ] && echo true || echo false)"
_rc=0; _o="$(bash "$IBH2" --check "" "$H/argpos" 2>&1)" || _rc=$?
eq "…the same with --check in front (rc 2)"    "2" "$_rc"
_rc=0; _o="$(bash "$IBH2" "$H/argpos" "$H/healthy" 2>&1)" || _rc=$?
eq "two non-empty positionals: rejected as an extra argument (rc 2)" "2" "$_rc"
eq "…and says WHICH guard fired (extra, not empty)" "true" \
   "$(case "$_o" in *"unexpected extra argument"*) echo true ;; *) echo false ;; esac)"

# A symlink-to-DIRECTORY at the hook path: `ln -sf` dereferences it, so the hook lands INSIDE
# the directory, the installer reports success, and git never sees a hook — #4281 again.
mkrepo "$H/symdir"; mkdir -p "$H/symdir-target"
ln -sfn "$H/symdir-target" "$H/symdir/.git/hooks/post-checkout"
_rc=0; bash "$IBH2" "$H/symdir" >/dev/null 2>&1 || _rc=$?
eq "symlink-to-directory at the hook path: REFUSED (rc 1)" "1" "$_rc"
eq "…and nothing was installed inside that directory" "false" \
   "$([ -e "$H/symdir-target/post-checkout" ] && echo true || echo false)"
eq "…and --check refuses it too (the consolidation working)" "1" \
   "$(_rc2=0; bash "$IBH2" --check "$H/symdir" >/dev/null 2>&1 || _rc2=$?; echo "$_rc2")"

# install-board-hooks --check itself: the contract the fix-line depends on.
_rc=0; _out="$(bash "$IBH2" --check "$H/healthy" 2>/dev/null)" || _rc=$?
eq "--check on a healthy repo: rc 0"                    "0" "$_rc"
eq "--check prints the target dir and nothing else"     "$H/healthy/.git/hooks" "$_out"
mkrepo "$H/fresh-probe"
bash "$IBH2" --check "$H/fresh-probe" >/dev/null 2>&1
eq "--check on a fresh repo installs NOTHING" "false" \
   "$([ -e "$H/fresh-probe/.git/hooks/post-checkout" ] && echo true || echo false)"

# --- the fix-line names the hook that is actually broken --------------------
# Hardcoding post-checkout told the operator to re-wire a hook that was already fine, never
# named the broken one, and (its target existing) named a command that exits 1.
r="$H/only-prepush"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; rm -f "$r/.git/hooks/pre-push"
# A topology needing MANUAL wiring. It used to be a --separate-git-dir checkout; card#5311 made
# that install, so the fixture moved to one the installer still cannot service: a linked worktree
# (refused on blast radius) whose MAIN checkout is also unserviceable — its post-checkout is a
# COPY, which reaches board-card-start (so that hook is healthy and must not be named) while the
# installer's refuse-to-clobber guard stops it there too. Only pre-push is broken.
mkrepo "$H/opp-main"; ( cd "$H/opp-main" && echo a > a && git add a && git commit -qm a ) >/dev/null 2>&1
cp "$TK/hooks/post-checkout" "$H/opp-main/.git/hooks/post-checkout"
chmod +x "$H/opp-main/.git/hooks/post-checkout"
git -C "$H/opp-main" worktree add -q "$H/opp" -b oppb >/dev/null 2>&1
report "$H/opp"
eq "only pre-push broken: the manual wiring names pre-push"      "true" "$(saw "hooks/pre-push")"
eq "only pre-push broken: it does NOT name the healthy post-checkout" "false" \
   "$(saw "ln -s <toolkit>/hooks/post-checkout")"

# --- MAJOR 1: a non-canonical path spelling must not be told its .git is a file ---
# `--git-common-dir` answers relative to the path the caller typed; `--show-toplevel` is always
# canonical. Comparing the two as STRINGS made every alternate spelling of an ordinary checkout
# fall into the "your .git is a file" arm — asserting a falsehood AND withholding the command
# that works (the installer canonicalizes, so it succeeds rc 0 on all of these).
# NOTE: `$r/sub` was a case here until the misattribution rule above superseded it — a
# sub-directory is no longer resolved to its enclosing repo at all, so it is skipped rather than
# given a fix-line. The symlink and trailing-slash spellings still name the SAME work tree, so
# they must still resolve and still get the working command.
r="$H/canon"; mkrepo "$r"; wire "$r/.git/hooks" "$TK"; mkdir -p "$r/sub"; ln -s "$r" "$H/canon-link"
report "$r/sub"
eq "spelling [canon/sub]: a sub-directory is skipped, not attributed to canon" "true" \
   "$(saw "not a checkout root")"
for spelling in "$r" "$H/canon-link" "$r/"; do
    report "$spelling"
    eq "spelling [${spelling#"$H/"}]: no finding" "0" "$RN"
    eq "spelling [${spelling#"$H/"}]: the hooks are found where git dispatches" "true" \
       "$(saw "✓ post-checkout pre-push dispatch from")"
done
rm -f "$r/.git/hooks/post-checkout"      # force the fix-line to print for each spelling
for spelling in "$r" "$H/canon-link" "$r/"; do
    report "$spelling"
    eq "spelling [${spelling#"$H/"}]: names install-board-hooks, not the .git-is-a-file arm" "true" \
       "$(saw "fix: install-board-hooks")"
    eq "spelling [${spelling#"$H/"}]: never falls into the wrong-target arm" "false" \
       "$(saw "but git dispatches from")"
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

# --- a bare repo, and a plain directory nested inside someone else's work tree ---
# `-e "$repo"` alone attributed a nested plain directory to the ENCLOSING repo: it reported that
# repo's hooks under this path's name and named this path in the fix-line — a false statement
# about the repo the operator actually asked about.
git init -q --bare "$H/bare-repo"
report "$H/bare-repo"
eq "bare repo: skipped, not a finding"       "0" "$RN"
eq "bare repo: says it has no work tree"     "true" "$(saw "no work tree")"
eq "bare repo: does NOT claim git refused it" "false" "$(saw "git refuses this checkout")"
mkdir -p "$H/healthy/plain-subdir"
report "$H/healthy/plain-subdir"
eq "nested plain dir: skipped, not a finding"        "0" "$RN"
eq "nested plain dir: says it is not a checkout root" "true" "$(saw "not a checkout root")"
eq "nested plain dir: names the work tree it sits in" "true" "$(saw "$H/healthy")"
eq "nested plain dir: does NOT report the enclosing repo's hooks under this name" "false" \
   "$(saw "✓ post-checkout")"

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

# --- the remedy line tracks the INSTALLER's disposition, never a model of it (card#5311) ----
# This check used to substitute <root>/.git for the installer view under the claim that was "the
# only place it ever installs". Once a --separate-git-dir checkout and a submodule began
# installing into their real common dir, that model would have told an operator to wire by hand
# the very repos the installer now fixes — and, for a linked worktree, would have named a target
# the installer has refused outright since card#5226. Both are asserted here on the MESSAGE.
TOPO="$TMP/topo"; mkdir -p "$TOPO"
git init -q "$TOPO/main"; ( cd "$TOPO/main" && echo a > a && git add a && git commit -qm a ) >/dev/null 2>&1
git -C "$TOPO/main" worktree add -q "$TOPO/wt" -b wtb >/dev/null 2>&1
git init -q --separate-git-dir="$TOPO/sepgit" "$TOPO/sep" >/dev/null 2>&1
( cd "$TOPO/sep" && echo x > x && git add x && git commit -qm x ) >/dev/null 2>&1

# The sep-git-dir repo's hook is BROKEN (absent from the dir git dispatches from), which is the
# state the remedy line answers.
_fix() { bash -c 'source "$1" >/dev/null 2>&1; d="$(_bsc_hooks_dir "$2" 2>/dev/null)"; _bsc_fix_line "$2" "$d" post-checkout' _ "$BIN" "$1"; }

_o="$(_fix "$TOPO/sep")"
eq "sep-git-dir: the remedy is the installer itself, run against this repo" "true" \
   "$(case "$_o" in "fix: install-board-hooks $TOPO/sep"*) echo true ;; *) echo false ;; esac)"
eq "sep-git-dir: does NOT tell the operator to wire it by hand" "false" \
   "$(case "$_o" in *"by hand"*) echo true ;; *) echo false ;; esac)"

# The installer view must be EMPTY + non-zero for the topology the installer refuses, so
# _bsc_same_dir fails and the main-checkout branch (the correct remedy) is reached.
_rc=0; _iv="$(bash -c 'source "$1" >/dev/null 2>&1; _bsc_hooks_dir "$2" installer' _ "$BIN" "$TOPO/wt" 2>/dev/null)" || _rc=$?
eq "linked worktree: installer view is rc 9 (refused outright)" "9" "$_rc"
eq "linked worktree: installer view names NO target directory"  ""  "$_iv"
_o="$(_fix "$TOPO/wt")"
eq "linked worktree: remedy redirects to the main checkout" "true" \
   "$(case "$_o" in *"install-board-hooks $TOPO/main"*) echo true ;; *) echo false ;; esac)"
eq "linked worktree: never claims the installer 'would target' a dir it refuses" "false" \
   "$(case "$_o" in *"would target"*) echo true ;; *) echo false ;; esac)"

# …and when the main checkout is ALSO unserviceable, the fall-through must quote the installer's
# own refusal rather than invent a target. Without this the rc-9 tail is never exercised.
printf '#!/bin/sh\n# a hook the operator wrote\n' > "$TOPO/main/.git/hooks/post-checkout"
chmod +x "$TOPO/main/.git/hooks/post-checkout"
_o="$(_fix "$TOPO/wt")"
eq "worktree + unserviceable main: quotes the installer's refusal" "true" \
   "$(case "$_o" in *"refuses this checkout"*) echo true ;; *) echo false ;; esac)"
eq "worktree + unserviceable main: invents no target"             "false" \
   "$(case "$_o" in *"would target"*) echo true ;; *) echo false ;; esac)"

# THE DISPOSITION IS CONSULTED ONLY WHILE core.hooksPath IS UNSET — the installer's own gate. A
# set hooksPath wins on every topology, so a worktree that configures one INSTALLS, and this view
# must say so. Asking the topology question before reading hooksPath made this view answer
# "refused" for a checkout the installer services (caught in build; the two views must diverge
# exactly where the installer does, and nowhere else).
mkdir -p "$TOPO/outhooks"; git -C "$TOPO/wt" config core.hooksPath "$TOPO/outhooks"
eq "worktree + hooksPath SET: installer view agrees with the installer, no refusal" \
   "$TOPO/outhooks" "$(bash -c 'source "$1" >/dev/null 2>&1; _bsc_hooks_dir "$2" installer' _ "$BIN" "$TOPO/wt" 2>/dev/null)"
_o="$(_fix "$TOPO/wt")"
eq "worktree + hooksPath SET: the remedy is the installer on THIS checkout" "true" \
   "$(case "$_o" in "fix: install-board-hooks $TOPO/wt"*) echo true ;; *) echo false ;; esac)"
git -C "$TOPO/wt" config --unset core.hooksPath
_rc=0; bash -c 'source "$1" >/dev/null 2>&1; _bsc_hooks_dir "$2" installer' _ "$BIN" "$TOPO/wt" >/dev/null 2>&1 || _rc=$?
eq "…and unsetting it restores the refusal (the gate, not a one-way door)" "9" "$_rc"
fi

# ---------------------------------------------------------------------------
# The '── Archive-eligible done cards ──' leg (card#5371) — main's SECOND delegation, to
# the `_kbc-archive-eligible.py` sibling, and the one whose rc contract INVERTS the
# inverse-drift leg's: a failing archive helper WARNS and leaves the ritual's exit code
# alone, where a failing reconcile hook PROPAGATES. Nothing asserted that difference
# before, so the two legs were free to converge on either answer with a green suite.
#
# The helper is resolved as a SIBLING OF THE BIN (`dirname $(readlink -f $BASH_SOURCE)`),
# never from $HOME or $PATH — there is no env override pointing it elsewhere. So these
# cases run a COPY of the bin from a scratch dir (the $H/lonely pattern) with a FAKE
# sibling beside it: that copy is the only way to reach the missing-sibling arm at all,
# and it turns the delegate's rc/stdout/stderr into an INPUT instead of an observation.
#
# The REAL helper is never executed here. The main-delegation cases far above DO execute
# it — on a scratch HOME it finds no token and exits non-zero — so they have been
# traversing this leg's failure arm all along with nothing asserting on it, which is
# exactly the hole this block closes.
# ---------------------------------------------------------------------------
echo "== Archive-eligible leg — fixture =="
AEDIR="$TMP/ae/bin"; mkdir -p "$AEDIR"
cp "$BIN" "$AEDIR/board-session-close"
AEBIN="$AEDIR/board-session-close"
AEHELPER="$AEDIR/_kbc-archive-eligible.py"
# The OTHER advisory sibling must exist and be quiet here — mirroring what the Dependabot block
# below does for this one. Without it that leg warns on every run in this block, and the
# absence assertions at the end could only ever be written narrowly enough to exclude its
# warning. With both siblings present-and-quiet the broad needle discriminates again.
printf '%s\n' '#!/bin/sh' 'echo "dr fixture: quiet"' > "$AEDIR/dependabot-deploy-reconcile"
chmod +x "$AEDIR/dependabot-deploy-reconcile"
printf '%s\n' '#!/usr/bin/env python3' 'print("sb fixture: quiet")' > "$AEDIR/_kbc-stale-blocker.py"

# run_ae <fake-reconcile-hook> — run the COPIED bin; echo rc, leave out/err in $OUTF/$ERRF.
run_ae() {
    HOME="$SCRATCH" PATH="$SHIM:$UB" KANBAN_RECONCILE_HOOK="$1" \
        bash "$AEBIN" >"$OUTF" 2>"$ERRF"; echo $?
}

echo "== Archive-eligible leg — the fixture's rc channel is LIVE (witness for the claims below) =="
# Every rc claim below is "a failing archive helper does NOT change the ritual's exit code" —
# an ABSENCE claim, and worthless if this fixture cannot produce a non-zero rc at all. Same
# copied bin, same fake sibling, a FAILING reconcile hook ⇒ rc 2 must be observed here first.
printf '%s\n' '#!/usr/bin/env python3' 'print("ae fixture: helper ran")' > "$AEHELPER"
rc="$(run_ae "$badhook")"
eq "a failing reconcile hook still exits 2 THROUGH the copied bin (rc channel is live)" "2" "$rc"

echo "== Archive-eligible leg — a MISSING sibling warns and does NOT block the close =="
rm -f "$AEHELPER"
rc="$(run_ae "$goodhook")"
eq "missing sibling: the ritual still exits 0 (advisory, not blocking)" "0" "$rc"
eq "…stderr names the missing sibling" \
   "true" "$(has '_kbc-archive-eligible.py sibling not found' "$(cat "$ERRF")")"
eq "…and says the surfacing DID NOT RUN, so an absent leg is never read as 'nothing to archive'" \
   "true" "$(has 'archive-eligible surfacing DID NOT RUN' "$(cat "$ERRF")")"
eq "…naming the path it looked for, so the fix is actionable" \
   "true" "$(has "$AEHELPER" "$(cat "$ERRF")")"

echo "== Archive-eligible leg — a non-zero helper WARNS but does not fail the ritual =="
# The deliberate contrast with the inverse-drift leg, which propagates. Both answers are
# defensible; the point is that the difference is a decision, and nothing pinned it.
printf '%s\n' '#!/usr/bin/env python3' 'import sys' \
              'print("archive-eligible: boom", file=sys.stderr)' 'sys.exit(3)' > "$AEHELPER"
rc="$(run_ae "$goodhook")"
eq "helper rc 3 does NOT become the ritual's exit code (inverse-drift's rc 2 above DOES)" "0" "$rc"
# The head is pinned WHOLE — not just `exited 3` — so that the absence assertion at the end of
# this block ('_kbc-archive-eligible.py exited') is a strict PREFIX of a string observed present
# here. A witness that merely overlaps the absence target leaves the absence able to pass
# vacuously after a reword, which is the failure mode the witness exists to rule out.
eq "…stderr names the helper AND its exit status" \
   "true" "$(has '_kbc-archive-eligible.py exited 3' "$(cat "$ERRF")")"
eq "…and flags the surfacing as INCOMPLETE, so degraded coverage is not read as clean" \
   "true" "$(has 'archive-eligible surfacing may be' "$(cat "$ERRF")")"
# The INCOMPLETE token itself sits on the continuation line, so the assertion above stops one
# word short of the property its label claims; this pins the rest of it. The reconcile leg's
# near-identical warning splits the two across a newline, so this needle matches only here.
eq "…the INCOMPLETE token itself, with the advisory framing that keeps it non-blocking" \
   "true" "$(has 'INCOMPLETE (config/API error above); it is advisory and does not block close.' "$(cat "$ERRF")")"

echo "== Archive-eligible leg — the helper's output is INDENTED into the report =="
printf '%s\n' '#!/usr/bin/env python3' 'import sys' \
              'print("SYNTHETIC board 5: 7 done card(s), 2 eligible")' \
              'print("SYNTHETIC note on stderr", file=sys.stderr)' > "$AEHELPER"
rc="$(run_ae "$goodhook")"
eq "a clean helper leaves the ritual at 0" "0" "$rc"
eq "the section header renders" "true" "$(has '── Archive-eligible done cards' "$(cat "$OUTF")")"
eq "the helper's stdout is indented by exactly two spaces (line-exact)" "true" \
   "$(grep -qxF '  SYNTHETIC board 5: 7 done card(s), 2 eligible' "$OUTF" && echo true || echo false)"
eq "…and the UN-indented form does not appear (the indent is what is asserted)" "false" \
   "$(grep -qxF 'SYNTHETIC board 5: 7 done card(s), 2 eligible' "$OUTF" && echo true || echo false)"
# The delegate's stderr is folded into its captured stdout (`2>&1`), so it lands INDENTED in
# the report rather than on the ritual's stderr — where it would read as a ritual-level ⚠.
eq "the helper's STDERR is folded into the report, indented the same way" "true" \
   "$(grep -qxF '  SYNTHETIC note on stderr' "$OUTF" && echo true || echo false)"
eq "…and does NOT leak to the ritual's own stderr" \
   "false" "$(has 'SYNTHETIC note on stderr' "$(cat "$ERRF")")"
# Both needles below were OBSERVED PRESENT two cases up, each as a strict prefix of the string
# asserted there — so these are assertions about this run rather than about a string the suite
# can no longer produce.
eq "a clean helper emits NO exit-status ⚠ on stderr" \
   "false" "$(has '_kbc-archive-eligible.py exited' "$(cat "$ERRF")")"
# BROAD AGAIN, and that is the assertion: this needle was once narrowed to the tool name because
# the fixture dir held only the archive sibling, so once main grew a second delegate the
# unqualified `sibling not found` matched THAT leg's warning and the line failed on a run where
# the archive leg was perfectly quiet. The fix is the FIXTURE, not the needle — both siblings are
# now present and quiet here — so this asserts what it always meant to: NO leg reports a missing
# sibling on a healthy run. The needle is a substring of a string observed present two cases up.
eq "…and no missing-sibling ⚠ from ANY leg" \
   "false" "$(has 'sibling not found' "$(cat "$ERRF")")"

# ---------------------------------------------------------------------------
# The '── Dependabot fixed-alert vs deployed-tree reconciliation ──' leg (card#6277) — main's
# THIRD delegation, to the `dependabot-deploy-reconcile` sibling. Its rc contract is the
# archive leg's, not the inverse-drift leg's: a failing reconciler WARNS and leaves the
# ritual's exit code alone. That is asserted rather than assumed, because the tool it
# delegates to has an exit contract of its own (rc 1 = the INSTRUMENT failed; a STILL_EXPOSED
# finding rides the report at rc 0), and folding either into the close would be wrong in a
# different way — one blocks a close over an unreadable input, the other over a finding the
# operator is supposed to read and act on.
#
# Same fixture shape as the archive block above: the sibling is resolved beside the BIN, so a
# copied bin with a fake sibling is the only way to drive the delegate's rc/stdout as an input.
# The real reconciler is never executed here (the main-delegation cases far above DO reach it,
# on a scratch HOME with no .mcp.json, so they have been traversing its failure arm with
# nothing asserted on it — which is the hole this block closes).
# ---------------------------------------------------------------------------
echo "== Dependabot-reconcile leg — fixture =="
DRDIR="$TMP/dr/bin"; mkdir -p "$DRDIR"
cp "$BIN" "$DRDIR/board-session-close"
DRBIN="$DRDIR/board-session-close"
DRTOOL="$DRDIR/dependabot-deploy-reconcile"
# The archive sibling must exist and be quiet here, or its own warnings would be the reason
# any absence assertion below passes.
printf '%s\n' '#!/usr/bin/env python3' 'print("ae fixture: quiet")' > "$DRDIR/_kbc-archive-eligible.py"
printf '%s\n' '#!/usr/bin/env python3' 'print("sb fixture: quiet")' > "$DRDIR/_kbc-stale-blocker.py"

run_dr_leg() {
    HOME="$SCRATCH" PATH="$SHIM:$UB" KANBAN_RECONCILE_HOOK="$1" \
        BSC_ADVISORY_TIMEOUT="${BSC_ADVISORY_TIMEOUT:-60}" \
        bash "$DRBIN" >"$OUTF" 2>"$ERRF"; echo $?
}

echo "== Dependabot-reconcile leg — the fixture's rc channel is LIVE (witness) =="
printf '%s\n' '#!/bin/sh' 'echo "dr fixture: ran"' > "$DRTOOL"; chmod +x "$DRTOOL"
rc="$(run_dr_leg "$badhook")"
eq "a failing reconcile hook still exits 2 THROUGH the copied bin (rc channel is live)" "2" "$rc"

echo "== Dependabot-reconcile leg — a MISSING sibling warns and does NOT block the close =="
rm -f "$DRTOOL"
rc="$(run_dr_leg "$goodhook")"
eq "missing sibling: the ritual still exits 0 (advisory, not blocking)" "0" "$rc"
eq "…stderr names the missing sibling" \
   "true" "$(has 'dependabot-deploy-reconcile sibling not found' "$(cat "$ERRF")")"
eq "…and says the reconciliation DID NOT RUN, so an absent leg is never read as 'no exposure'" \
   "true" "$(has 'deploy reconciliation DID NOT RUN' "$(cat "$ERRF")")"
eq "…naming the path it looked for, so the fix is actionable" \
   "true" "$(has "$DRTOOL" "$(cat "$ERRF")")"

echo "== Dependabot-reconcile leg — a non-zero tool WARNS but does not fail the ritual =="
printf '%s\n' '#!/bin/sh' 'echo "dr: boom" >&2' 'exit 1' > "$DRTOOL"; chmod +x "$DRTOOL"
rc="$(run_dr_leg "$goodhook")"
eq "tool rc 1 does NOT become the ritual's exit code" "0" "$rc"
eq "…stderr names the tool AND its exit status" \
   "true" "$(has 'dependabot-deploy-reconcile exited 1' "$(cat "$ERRF")")"
eq "…flags the reconciliation as INCOMPLETE rather than clean" \
   "true" "$(has 'deploy reconciliation may be' "$(cat "$ERRF")")"
# The distinction the whole leg turns on: a non-zero here is the INSTRUMENT, never a finding.
eq "…and says a STILL_EXPOSED row is not what a non-zero means" \
   "true" "$(has 'A STILL_EXPOSED row is NOT this' "$(cat "$ERRF")")"

echo "== Dependabot-reconcile leg — the tool's output is INDENTED into the report =="
printf '%s\n' '#!/bin/sh' 'echo "SYNTHETIC ✗ #17 npm hono STILL_EXPOSED"' \
              'echo "SYNTHETIC dr note on stderr" >&2' > "$DRTOOL"; chmod +x "$DRTOOL"
rc="$(run_dr_leg "$goodhook")"
eq "a clean tool leaves the ritual at 0" "0" "$rc"
eq "the section header renders" "true" \
   "$(has '── Dependabot fixed-alert vs deployed-tree reconciliation' "$(cat "$OUTF")")"
eq "the tool's stdout is indented by exactly two spaces (line-exact)" "true" \
   "$(grep -qxF '  SYNTHETIC ✗ #17 npm hono STILL_EXPOSED' "$OUTF" && echo true || echo false)"
eq "…and the UN-indented form does not appear (the indent is what is asserted)" "false" \
   "$(grep -qxF 'SYNTHETIC ✗ #17 npm hono STILL_EXPOSED' "$OUTF" && echo true || echo false)"
eq "the tool's STDERR is folded into the report, indented the same way" "true" \
   "$(grep -qxF '  SYNTHETIC dr note on stderr' "$OUTF" && echo true || echo false)"
eq "…and does NOT leak to the ritual's own stderr" \
   "false" "$(has 'SYNTHETIC dr note on stderr' "$(cat "$ERRF")")"
# A STILL_EXPOSED finding at rc 0 must leave the ritual completely quiet on stderr — the
# needles below were both observed PRESENT two cases up, so these are claims about this run.
eq "a rc-0 run carrying a FINDING emits no exit-status ⚠" \
   "false" "$(has 'dependabot-deploy-reconcile exited' "$(cat "$ERRF")")"
# Broad for the same reason as its twin in the archive block: this dir carries a quiet archive
# sibling too, so a healthy run must leave BOTH legs silent about a missing sibling.
eq "…and no missing-sibling ⚠ from ANY leg" \
   "false" "$(has 'sibling not found' "$(cat "$ERRF")")"

echo "== Advisory legs are bounded in WALL-CLOCK, not just in exit code =="
# "Advisory — never blocks the close" was true of the rc and false of the clock: a leg that
# reaches the network (the reconciler makes five sequential `gh api` calls) could hang the
# ritual indefinitely on a stalled connection, and a close that never returns is not one the
# advisory contract protected. The bound lives in `_bsc_advisory_leg`, so every leg inherits it.
#
# BSC_ADVISORY_TIMEOUT is overridden to 1s here for exactly one reason: to test the bound
# without making this suite wait out the real 60s budget. The real default is asserted below.
printf '%s\n' '#!/bin/sh' 'sleep 30' 'echo "never reached"' > "$DRTOOL"; chmod +x "$DRTOOL"
_t0=$SECONDS
rc="$(BSC_ADVISORY_TIMEOUT=1 run_dr_leg "$goodhook")"
_elapsed=$((SECONDS - _t0))
eq "a hanging leg does NOT hang the close — it still exits 0" "0" "$rc"
eq "…and the ritual returns in about the budget, not the delegate's own runtime" "true" \
   "$([ "$_elapsed" -lt 15 ] && echo true || echo false)"
eq "…with a ⚠ naming the kill and the budget that caused it" "true" \
   "$(has 'dependabot-deploy-reconcile was KILLED after 1s' "$(cat "$ERRF")")"
eq "…said as an INCOMPLETE partial answer, not as a finished one" "true" \
   "$(has 'a partial answer, not a finished one' "$(cat "$ERRF")")"
# The timeout is the HELPER's doing, so the helper explains it: the per-leg <cause> text
# describes that leg's own failure modes and would be simply wrong about a clock kill.
eq "…and NOT mis-attributed to the leg's own input/gate failure modes" "false" \
   "$(has 'an input was unreadable' "$(cat "$ERRF")")"
# THE DISCRIMINATOR: the same 1s budget with a fast delegate must stay completely quiet. Without
# it, this block would also pass for a helper that warns on every run under a short budget.
printf '%s\n' '#!/bin/sh' 'echo "dr fixture: fast"' > "$DRTOOL"; chmod +x "$DRTOOL"
rc="$(BSC_ADVISORY_TIMEOUT=1 run_dr_leg "$goodhook")"
eq "control: a FAST leg under the same 1s budget exits 0" "0" "$rc"
eq "…and emits no kill ⚠ at all (the warning tracks the hang, not the budget)" "false" \
   "$(has 'was KILLED after' "$(cat "$ERRF")")"
eq "…while still rendering its output into the report" "true" \
   "$(grep -qxF '  dr fixture: fast' "$OUTF" && echo true || echo false)"
# The default is what a real close actually runs under, and nothing above exercises it because
# every case overrides it. Asserted against the bin so the override cannot hide a changed default.
eq "the real default budget is 60s, not whatever a test happened to set" "true" \
   "$(grep -qF 'BSC_ADVISORY_TIMEOUT:-60' "$BIN" && echo true || echo false)"

echo "== a host with no \`timeout\` still RUNS the leg, and says the bound is gone =="
# `timeout` is coreutils and not universal — macOS ships none by default, and the MSYS install
# INSTALL.md §2 warns about is another. The bound was added to a helper extracted from two
# legs, one of which PRE-DATES it, so a hard dependency would have broken a working leg on
# those hosts in order to add a guarantee they cannot have. Unbounded-but-running beats
# bounded-and-dead for an advisory leg — but never silently.
NOTO="$TMP/no-timeout-bin"; mkdir -p "$NOTO"
# Everything the ritual needs EXCEPT timeout, so the only variable is the missing bound.
for _b in bash sh env python3 dirname readlink sed cat grep date git ln mkdir rm chmod find sort; do
    _p="$(command -v "$_b" 2>/dev/null)" && ln -sf "$_p" "$NOTO/$_b"
done
printf '%s\n' '#!/bin/sh' 'echo "dr fixture: ran unbounded"' > "$DRTOOL"; chmod +x "$DRTOOL"
# Positive control FIRST: this stripped PATH really has no timeout, so the arm below is
# reached because of that and not because of some other breakage in the fixture.
eq "positive control: the stripped PATH genuinely has no timeout" "false" \
   "$(PATH="$NOTO" command -v timeout >/dev/null 2>&1 && echo true || echo false)"
rc="$(HOME="$SCRATCH" PATH="$NOTO" KANBAN_RECONCILE_HOOK="$goodhook" \
        bash "$DRBIN" >"$OUTF" 2>"$ERRF"; echo $?)"
eq "with no timeout the close still completes at rc 0" "0" "$rc"
eq "…the leg still RAN (its output is in the report)" "true" \
   "$(grep -qxF '  dr fixture: ran unbounded' "$OUTF" && echo true || echo false)"
eq "…and the lost bound is stated, not silent" "true" \
   "$(has 'no `timeout` on PATH' "$(cat "$ERRF")")"
eq "…naming the consequence precisely (clock, not exit code)" "true" \
   "$(has 'it can hang its clock' "$(cat "$ERRF")")"
eq "…and NOT mis-reported as the leg exiting 127" "false" \
   "$(has 'exited 127' "$(cat "$ERRF")")"
# Control: the same fixture WITH timeout on PATH emits no such warning.
rc="$(run_dr_leg "$goodhook")"
eq "control: with timeout present the close is still 0" "0" "$rc"
eq "…and no missing-timeout warning appears" "false" \
   "$(has 'no `timeout` on PATH' "$(cat "$ERRF")")"


# ---------------------------------------------------------------------------
# The '── Stale blocker citations ──' leg (card#7113) — main's FOURTH delegation, to the
# `_kbc-stale-blocker.py` sibling. Its rc contract is the archive leg's: a failing helper
# WARNS and leaves the ritual's exit code alone. Asserted rather than inherited, because
# that tool has an exit contract of its own — a FLAGGED stale citation rides the report at
# rc 0, and only an unreadable board makes it non-zero — so folding its rc into the close
# would block a session on the very finding the operator is meant to read and fix.
#
# Same fixture shape as the two blocks above, and for the same reason: the sibling is
# resolved beside the BIN, so a copied bin with a fake sibling is the only way to make the
# delegate's rc/stdout an input. Both other siblings are planted quiet here.
# ---------------------------------------------------------------------------
echo "== Stale-blocker leg — fixture =="
SBDIR="$TMP/sb/bin"; mkdir -p "$SBDIR"
cp "$BIN" "$SBDIR/board-session-close"
SBBIN="$SBDIR/board-session-close"
SBHELPER="$SBDIR/_kbc-stale-blocker.py"
printf '%s\n' '#!/usr/bin/env python3' 'print("ae fixture: quiet")' > "$SBDIR/_kbc-archive-eligible.py"
printf '%s\n' '#!/bin/sh' 'echo "dr fixture: quiet"' > "$SBDIR/dependabot-deploy-reconcile"
chmod +x "$SBDIR/dependabot-deploy-reconcile"

run_sb_leg() {
    HOME="$SCRATCH" PATH="$SHIM:$UB" KANBAN_RECONCILE_HOOK="$1" \
        bash "$SBBIN" >"$OUTF" 2>"$ERRF"; echo $?
}

echo "== Stale-blocker leg — the fixture's rc channel is LIVE (witness) =="
printf '%s\n' '#!/usr/bin/env python3' 'print("sb fixture: ran")' > "$SBHELPER"
rc="$(run_sb_leg "$badhook")"
eq "a failing reconcile hook still exits 2 THROUGH the copied bin (rc channel is live)" "2" "$rc"

echo "== Stale-blocker leg — a MISSING sibling warns and does NOT block the close =="
rm -f "$SBHELPER"
rc="$(run_sb_leg "$goodhook")"
eq "missing sibling: the ritual still exits 0 (advisory, not blocking)" "0" "$rc"
eq "…stderr names the missing sibling" \
   "true" "$(has '_kbc-stale-blocker.py sibling not found' "$(cat "$ERRF")")"
eq "…and says the scan DID NOT RUN, so an absent leg is never read as 'no stale citations'" \
   "true" "$(has 'stale-blocker-citation scan DID NOT RUN' "$(cat "$ERRF")")"
eq "…naming the path it looked for, so the fix is actionable" \
   "true" "$(has "$SBHELPER" "$(cat "$ERRF")")"

echo "== Stale-blocker leg — a non-zero helper WARNS but does not fail the ritual =="
printf '%s\n' '#!/usr/bin/env python3' 'import sys' \
              'print("stale-blocker: boom", file=sys.stderr)' 'sys.exit(2)' > "$SBHELPER"
rc="$(run_sb_leg "$goodhook")"
eq "helper rc 2 does NOT become the ritual's exit code" "0" "$rc"
eq "…stderr names the helper AND its exit status" \
   "true" "$(has '_kbc-stale-blocker.py exited 2' "$(cat "$ERRF")")"
eq "…flags the scan as INCOMPLETE rather than clean" \
   "true" "$(has 'stale-blocker-citation scan may be' "$(cat "$ERRF")")"
# The distinction the leg turns on, same shape as the reconciler's: a non-zero is the
# INSTRUMENT (a board it could not read), never the finding it exists to report.
eq "…and says a flagged card is not what a non-zero means" \
   "true" "$(has 'A flagged card is NOT this' "$(cat "$ERRF")")"

echo "== Stale-blocker leg — the helper's output is INDENTED into the report =="
printf '%s\n' '#!/usr/bin/env python3' 'import sys' \
              'print("SYNTHETIC card#1 cites card#2 as a blocker")' \
              'print("SYNTHETIC sb note on stderr", file=sys.stderr)' > "$SBHELPER"
rc="$(run_sb_leg "$goodhook")"
eq "a clean helper leaves the ritual at 0" "0" "$rc"
eq "the section header renders" "true" \
   "$(has '── Stale blocker citations' "$(cat "$OUTF")")"
eq "the helper's stdout is indented by exactly two spaces (line-exact)" "true" \
   "$(grep -qxF '  SYNTHETIC card#1 cites card#2 as a blocker' "$OUTF" && echo true || echo false)"
eq "…and the UN-indented form does not appear (the indent is what is asserted)" "false" \
   "$(grep -qxF 'SYNTHETIC card#1 cites card#2 as a blocker' "$OUTF" && echo true || echo false)"
eq "the helper's STDERR is folded into the report, indented the same way" "true" \
   "$(grep -qxF '  SYNTHETIC sb note on stderr' "$OUTF" && echo true || echo false)"
eq "…and does NOT leak to the ritual's own stderr" \
   "false" "$(has 'SYNTHETIC sb note on stderr' "$(cat "$ERRF")")"
# A FINDING at rc 0 must leave the ritual silent on stderr. Both needles below were observed
# PRESENT two cases up, so these are claims about this run and not about an unusable needle.
eq "a rc-0 run carrying a FINDING emits no exit-status ⚠" \
   "false" "$(has '_kbc-stale-blocker.py exited' "$(cat "$ERRF")")"
eq "…and no missing-sibling ⚠ from ANY leg" \
   "false" "$(has 'sibling not found' "$(cat "$ERRF")")"

# ---------------------------------------------------------------------------
_summary "board-session-close-selftest"
