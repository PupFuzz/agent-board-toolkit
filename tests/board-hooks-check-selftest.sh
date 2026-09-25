#!/usr/bin/env bash
# board-hooks-check-selftest.sh — network-free tests for bin/board-hooks-check (card#10374).
#
# The subject answers "is each toolkit hook LIVE on this seat" with THREE verdicts — LIVE,
# NOT-LIVE (determined), UNMEASURED (indeterminate) — and an exit status that keeps the last two
# apart (1 vs 4, install-board-hooks' own split). Every case asserts on the VERDICT LINE the
# operator reads, not only on the rc, because an rc alone passes a tool that prints the wrong
# reason.
#
# The first two blocks are the card's "seen to fail on a deliberately-unwired seat": a scratch
# HOME with no settings and a repo with no hooks must read NOT-LIVE, and the SAME fixtures must
# flip to LIVE once registered, wired and armed — so the LIVE arm is shown to be reachable and
# the NOT-LIVE arm is shown not to be a constant.
#
# MUTANTS each watched red against this file when it was written (reproduce by applying one to
# bin/board-hooks-check and re-running): `_bhc_arm_state` returning 0 unconditionally; the
# unreadable-settings arm `continue`-ing without recording UNMEASURED; the matcher's rc-1
# (does-not-cover) arm disabled; the `board-card-start`-not-on-PATH leg dropped; the final
# `return 1` removed; the final `return 4` removed; the per-entry shape check (`all(...)`) and
# the extraction's failure arm reverted to `|| tsv=""` — which read a file holding a non-object
# PreToolUse entry as LIVE at rc 0, not merely as NOT-REGISTERED.
#
# Fixtures: a scratch HOME (no real settings or ~/.kanban-* file can taint a result), real
# `git init` repos wired by the real bin/install-board-hooks, and a PATH shim dir holding
# symlinks to this checkout's board-card-start and kbcard (so the on-PATH toolkit IS this
# checkout, and a hook symlinked into it is not clone drift). $BHC_MANAGED_SETTINGS points the
# managed-settings leg at a scratch path so a host that has /etc/claude-code stays out of it.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
BIN="$ROOT/bin/board-hooks-check"
IBH="$ROOT/bin/install-board-hooks"
SCRIPT="$ROOT/hooks/agent-dispatch-card-start"
_need -x "$BIN"
_need -x "$IBH"
_need -x "$SCRIPT"

_mktmp_scratch --home
export GIT_CONFIG_NOSYSTEM=1
SHIM="$TMP/shim"; mkdir -p "$SHIM"
ln -s "$ROOT/bin/board-card-start" "$SHIM/board-card-start"
ln -s "$ROOT/bin/kbcard" "$SHIM/kbcard"
FULLPATH="$SHIM:/usr/bin:/bin"
NOKB="$TMP/shim-nokb"; mkdir -p "$NOKB"
ln -s "$ROOT/bin/board-card-start" "$NOKB/board-card-start"
PROJ="$TMP/proj"; mkdir -p "$PROJ/.claude" "$HOME/.claude"
USER_SETTINGS="$HOME/.claude/settings.json"

# run [PATH] -- <args…> — run the subject from $PROJ; sets OUT (stdout+stderr) and RC.
run() {
    local p="$FULLPATH"
    if [[ "$1" != "--" ]]; then p="$1"; shift; fi
    shift
    OUT="$(cd "$PROJ" && HOME="$HOME" PATH="$p" BHC_MANAGED_SETTINGS="$TMP/no-managed.json" \
           "$BIN" "$@" 2>&1)"; RC=$?
}
# line <needle> — the first output line containing <needle> (empty when none).
line() { local l; while IFS= read -r l; do [[ "$l" == *"$1"* ]] && { printf '%s' "$l"; return; }; done <<< "$OUT"; }
# register <file> <matcher-json> <command-json> — write a settings file with one PreToolUse entry.
register() {
    jq -n --argjson m "$2" --argjson c "$3" \
       '{hooks: {PreToolUse: [{matcher: $m, hooks: [{type: "command", command: $c}]}]}}' > "$1"
}
mkrepo() { git init -q "$1"; }

# ---------------------------------------------------------------------------
echo "== a deliberately-UNWIRED seat reads NOT-LIVE, by name =="
mkrepo "$TMP/r1"
run -- "$TMP/r1"
eq "unwired seat exits 1 (determined not live)" "1" "$RC"
eq "the dispatch hook is NOT-LIVE / NOT-REGISTERED" "true" \
   "$(has 'agent-dispatch-card-start: NOT-LIVE — NOT-REGISTERED' "$(line 'agent-dispatch-card-start:')")"
eq "post-checkout is NOT-LIVE, not wired" "true" \
   "$(has 'NOT-LIVE — WIRED=NOT-WIRED ARMED=no' "$(line 'post-checkout:')")"
eq "pre-push is NOT-LIVE, not wired" "true" \
   "$(has 'NOT-LIVE — WIRED=NOT-WIRED' "$(line 'pre-push:')")"
eq "the tally agrees with the lines" "true" "$(has '0 LIVE · 3 NOT-LIVE · 0 UNMEASURED' "$OUT")"

# ---------------------------------------------------------------------------
echo "== the same seat, registered + wired + armed, reads LIVE (the LIVE arm is reachable) =="
register "$USER_SETTINGS" '"Agent"' "\"$SCRIPT\""
"$IBH" "$TMP/r1" >/dev/null 2>&1 || bad "fixture: install-board-hooks failed on r1"
git -C "$TMP/r1" config kanban.automove-on-checkout true
run -- "$TMP/r1"
eq "fully live seat exits 0" "0" "$RC"
eq "the dispatch hook is LIVE, naming where it is registered" "true" \
   "$(has "LIVE — $SCRIPT (registered in $USER_SETTINGS, entry #0, matcher 'Agent')" "$(line 'agent-dispatch-card-start:')")"
eq "the LIVE line carries the marker obligation" "true" \
   "$(has "BOARD-CARD: <board>#<id>" "$(line 'agent-dispatch-card-start:')")"
eq "post-checkout LIVE with WIRED and ARMED reported separately" "true" \
   "$(has 'LIVE — WIRED=WIRED ARMED=yes' "$(line 'post-checkout:')")"
eq "pre-push LIVE, needing no arming" "true" "$(has 'LIVE — WIRED=WIRED (needs no arming)' "$(line 'pre-push:')")"

# ---------------------------------------------------------------------------
echo "== WIRED-but-UNARMED is NOT-LIVE — the state that reads as working =="
git -C "$TMP/r1" config --unset kanban.automove-on-checkout
run -- "$TMP/r1"
eq "unarmed repo exits 1" "1" "$RC"
eq "post-checkout: wired, not armed, with the arming command" "true" \
   "$(has "NOT-LIVE — WIRED=WIRED ARMED=no; not armed: kanban.automove-on-checkout is unset (unset means OFF) — arm it with: git -C $TMP/r1 config kanban.automove-on-checkout true" "$(line 'post-checkout:')")"
eq "pre-push stays LIVE (arming is post-checkout's alone)" "true" "$(has 'pre-push: LIVE' "$OUT")"
git -C "$TMP/r1" config kanban.automove-on-checkout false
run -- "$TMP/r1"
eq "arming=false reads as not armed" "true" "$(has 'kanban.automove-on-checkout is false' "$(line 'post-checkout:')")"
git -C "$TMP/r1" config kanban.automove-on-checkout maybe
run -- "$TMP/r1"
eq "a non-boolean arming value is OFF, in git's own words" "true" \
   "$(has "git cannot read kanban.automove-on-checkout as a boolean (fatal: bad boolean config value 'maybe'" "$(line 'post-checkout:')")"
git -C "$TMP/r1" config kanban.automove-on-checkout yes
run -- "$TMP/r1"
eq "any git-true spelling arms it (yes)" "0" "$RC"

# ---------------------------------------------------------------------------
echo "== git hooks resolve where git DISPATCHES from (core.hooksPath), not .git/hooks =="
mkdir -p "$TMP/elsewhere"
git -C "$TMP/r1" config core.hooksPath "$TMP/elsewhere"
run -- "$TMP/r1"
eq "hooks in .git/hooks under a hooksPath elsewhere read NOT wired" "true" \
   "$(has 'WIRED=NOT-WIRED' "$(line 'post-checkout:')")"
eq "the dispatch dir named is the hooksPath" "true" "$(has "dispatch dir: $TMP/elsewhere" "$OUT")"
git -C "$TMP/r1" config core.hooksPath ""
run -- "$TMP/r1"
eq "an EMPTY hooksPath is NOT-LIVE (no fallback)" "true" \
   "$(has 'core.hooksPath is set to an EMPTY value' "$(line 'post-checkout:')")"
git -C "$TMP/r1" config --unset core.hooksPath

# ---------------------------------------------------------------------------
echo "== board-card-start off PATH makes both git hooks NOT-LIVE =="
run "/usr/bin:/bin" -- "$TMP/r1"
eq "post-checkout NOT-LIVE naming the missing tool" "true" \
   "$(has 'board-card-start is not on PATH' "$(line 'post-checkout:')")"
eq "pre-push NOT-LIVE naming the missing tool" "true" \
   "$(has 'board-card-start is not on PATH' "$(line 'pre-push:')")"

# ---------------------------------------------------------------------------
echo "== UNMEASURED is its own verdict and its own exit status =="
run --
eq "no repo named: git hooks UNMEASURED, rc 4 (dispatch hook LIVE)" "4" "$RC"
eq "the unmeasured line names why" "true" "$(has 'UNMEASURED — no <repo-dir> named' "$OUT")"
run -- "$TMP/does-not-exist"
eq "a path with nothing there is UNMEASURED, rc 4" "4|true" \
   "$RC|$(has 'UNMEASURED — nothing exists at' "$(line 'post-checkout:')")"
mkrepo "$TMP/r2"; mkdir -p "$TMP/r2/sub"
run -- "$TMP/r2/sub"
eq "a directory inside a work tree is UNMEASURED (not a checkout)" "true" \
   "$(has 'UNMEASURED — not a checkout' "$(line 'post-checkout:')")"
run -- "$TMP/r1" "$TMP/r2"
eq "NOT-LIVE outranks UNMEASURED in the exit status" "1" "$RC"
run -- "$TMP/does-not-exist" "$TMP/r2"
eq "…and the per-hook lines still carry both" "true|true" \
   "$(has 'UNMEASURED — nothing exists at' "$OUT")|$(has 'post-checkout: NOT-LIVE' "$OUT")"

# ---------------------------------------------------------------------------
echo "== Claude Code matcher evaluation =="
for m in '"*"' '""' '".*"' '"Task|Agent"' '"Bash, Agent"'; do
    register "$USER_SETTINGS" "$m" "\"$SCRIPT\""
    run -- "$TMP/r1"
    eq "matcher $m covers Agent → LIVE" "true" "$(has 'agent-dispatch-card-start: LIVE' "$OUT")"
done
jq -n --arg c "$SCRIPT" '{hooks: {PreToolUse: [{hooks: [{type: "command", command: $c}]}]}}' > "$USER_SETTINGS"
run -- "$TMP/r1"
eq "an ABSENT matcher matches every tool → LIVE" "true" "$(has 'agent-dispatch-card-start: LIVE' "$OUT")"
register "$USER_SETTINGS" '"Bash"' "\"$SCRIPT\""
run -- "$TMP/r1"
eq "registered under a matcher that never covers Agent → NOT-REGISTERED, saying where it is" "true" \
   "$(has "NOT-REGISTERED in any settings file read above (it IS named under a matcher that does not cover Agent" "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"^Ag.*"' "\"$SCRIPT\""
run -- "$TMP/r1"
eq "a regex matcher is UNMEASURED, rc 4" "4|true" \
   "$RC|$(has "matcher '^Ag.*' is a regular expression" "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"Task"' "\"$SCRIPT\""
run -- "$TMP/r1"
eq "the legacy Task name alone is UNMEASURED" "true" \
   "$(has 'names the legacy tool name Task' "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"Agentx"' "\"$SCRIPT\""
run -- "$TMP/r1"
eq "a literal that merely CONTAINS Agent does not cover it" "true" \
   "$(has 'NOT-REGISTERED' "$(line 'agent-dispatch-card-start:')")"

# ---------------------------------------------------------------------------
echo "== Claude Code command evaluation =="
mkdir -p "$HOME/tk/hooks"; ln -s "$SCRIPT" "$HOME/tk/hooks/agent-dispatch-card-start"
for c in '"~/tk/hooks/agent-dispatch-card-start"' '"$HOME/tk/hooks/agent-dispatch-card-start"' \
         "\"\\\"$SCRIPT\\\"\""; do
    register "$USER_SETTINGS" '"Agent"' "$c"
    run -- "$TMP/r1"
    eq "command $c resolves → LIVE" "true" "$(has 'agent-dispatch-card-start: LIVE' "$OUT")"
done
ln -s "$SCRIPT" "$HOME/renamed-hook"
register "$USER_SETTINGS" '"Agent"' "\"$HOME/renamed-hook\""
run -- "$TMP/r1"
eq "a differently-named symlink TO the script is recognised → LIVE" "true" "$(has 'agent-dispatch-card-start: LIVE' "$OUT")"
register "$USER_SETTINGS" '"Agent"' "\"bash $SCRIPT\""
run -- "$TMP/r1"
eq "an interpreter-prefixed command is UNMEASURED, rc 4" "4|true" \
   "$RC|$(has 'is not a bare path' "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"Agent"' '"hooks/agent-dispatch-card-start"'
run -- "$TMP/r1"
eq "a relative command is UNMEASURED" "true" "$(has 'is a relative path' "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"Agent"' "\"$TMP/gone/agent-dispatch-card-start\""
run -- "$TMP/r1"
eq "a registration whose file is gone is NOT-LIVE, rc 1" "1|true" \
   "$RC|$(has 'registered but cannot run' "$(line 'agent-dispatch-card-start:')")"
cp "$SCRIPT" "$TMP/agent-dispatch-card-start"; chmod -x "$TMP/agent-dispatch-card-start"
register "$USER_SETTINGS" '"Agent"' "\"$TMP/agent-dispatch-card-start\""
run -- "$TMP/r1"
eq "a registration whose file is not executable is NOT-LIVE" "true" \
   "$(has 'is not executable' "$(line 'agent-dispatch-card-start:')")"
register "$USER_SETTINGS" '"Agent"' '"/usr/bin/true"'
run -- "$TMP/r1"
eq "an Agent hook that is some OTHER command is not this hook → NOT-REGISTERED" "true" \
   "$(has 'NOT-REGISTERED' "$(line 'agent-dispatch-card-start:')")"

# ---------------------------------------------------------------------------
echo "== the settings population: project files, dedupe, unreadable/invalid, restricting keys =="
rm -f "$USER_SETTINGS"
register "$PROJ/.claude/settings.local.json" '"Agent"' "\"$SCRIPT\""
run -- "$TMP/r1"
eq "a registration in the project's settings.local.json → LIVE" "true" \
   "$(has "registered in $PROJ/.claude/settings.local.json" "$(line 'agent-dispatch-card-start:')")"
run -- --project "$TMP/r1" "$TMP/r1"
eq "--project moves the project leg (the registration is no longer read)" "true" \
   "$(has 'NOT-REGISTERED' "$(line 'agent-dispatch-card-start:')")"
printf '{}' > "$USER_SETTINGS"
run -- --project "$HOME" "$TMP/r1"
eq "a \$HOME project reads ~/.claude/settings.json once, not twice" "true" "$(has 'same file as one above' "$OUT")"
printf '{not json' > "$USER_SETTINGS"
run -- "$TMP/r1"
eq "an invalid settings file makes the verdict UNMEASURED, even beside a live registration" "4|true" \
   "$RC|$(has "$USER_SETTINGS does not parse as a JSON object" "$(line 'agent-dispatch-card-start:')")"
if [[ "$(id -u)" != 0 ]]; then
    printf '{}' > "$USER_SETTINGS"; chmod 000 "$USER_SETTINGS"
    run -- "$TMP/r1"
    eq "an UNREADABLE settings file is UNMEASURED, never LIVE" "4|true" \
       "$RC|$(has "$USER_SETTINGS is not a readable file" "$(line 'agent-dispatch-card-start:')")"
    chmod 600 "$USER_SETTINGS"
else
    echo "  skip unreadable-file case (running as root: chmod 000 does not deny root)"
fi
jq -n '{hooks: {PreToolUse: {matcher: "Agent"}}}' > "$USER_SETTINGS"
run -- "$TMP/r1"
eq "a malformed hooks.PreToolUse is UNMEASURED" "true" "$(has 'hooks.PreToolUse that is not an array' "$OUT")"
jq -n --arg c "$SCRIPT" '{hooks: {PreToolUse: ["Agent", {matcher: "Agent", hooks: [{type: "command", command: $c}]}]}}' > "$USER_SETTINGS"
run -- "$TMP/r1"
eq "a non-object PreToolUse entry is UNMEASURED, never NOT-REGISTERED" "4|true" \
   "$RC|$(has 'hooks.PreToolUse that is not an array of entries' "$(line 'agent-dispatch-card-start:')")"
jq -n '{hooks: {PreToolUse: [{matcher: "Agent", hooks: "nope"}]}}' > "$USER_SETTINGS"
run -- "$TMP/r1"
eq "an entry whose hooks is not an array is UNMEASURED" "4" "$RC"
for k in disableAllHooks allowManagedHooksOnly; do
    jq -n --arg k "$k" '{($k): true}' > "$USER_SETTINGS"
    run -- "$TMP/r1"
    eq "$k=true makes the verdict UNMEASURED by name" "4|true" \
       "$RC|$(has "sets $k" "$(line 'agent-dispatch-card-start:')")"
done
rm -f "$USER_SETTINGS" "$PROJ/.claude/settings.local.json"
register "$TMP/managed.json" '"Agent"' "\"$SCRIPT\""
OUT="$(cd "$PROJ" && PATH="$FULLPATH" BHC_MANAGED_SETTINGS="$TMP/managed.json" "$BIN" "$TMP/r1" 2>&1)"; RC=$?
eq "a managed-settings registration is read → LIVE" "0|true" \
   "$RC|$(has "registered in $TMP/managed.json" "$OUT")"
eq "the unread sources are named on every run" "true" \
   "$(has 'not read — a registration made only there reads NOT-REGISTERED here: hooks from plugins' "$OUT")"

# ---------------------------------------------------------------------------
echo "== kbcard off PATH: a registered hook that would skip every marker is NOT-LIVE =="
register "$USER_SETTINGS" '"Agent"' "\"$SCRIPT\""
run "$NOKB:/usr/bin:/bin" -- "$TMP/r1"
eq "kbcard missing → NOT-LIVE naming it" "true" \
   "$(has 'kbcard is not on PATH' "$(line 'agent-dispatch-card-start:')")"

# ---------------------------------------------------------------------------
echo "== a hook COMMAND is never printed (it can carry an env-prefixed secret) =="
SECRET="s3cr3t-$RANDOM-token"
register "$USER_SETTINGS" '"Agent"' "\"KB_TOKEN=$SECRET $SCRIPT\""
jq --arg s "$SECRET" '. + {env: {KANBAN_TOKEN: $s}}' "$USER_SETTINGS" > "$TMP/s.json" && mv "$TMP/s.json" "$USER_SETTINGS"
run -- "$TMP/r1"
eq "the command was evaluated (UNMEASURED: not a bare path)" "true" "$(has 'is not a bare path' "$OUT")"
eq "the planted secret appears nowhere in the output" "false" "$(has "$SECRET" "$OUT")"

# ---------------------------------------------------------------------------
echo "== usage =="
run -- --bogus
eq "an unknown flag is rc 2" "2" "$RC"
run -- --project
eq "--project without a dir is rc 2" "2" "$RC"
run -- --help
eq "--help is rc 0 and prints the header" "0|true" "$RC|$(has 'THREE VERDICTS PER HOOK' "$OUT")"

_summary "board-hooks-check-selftest"
