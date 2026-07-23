#!/usr/bin/env bash
# agent-dispatch-card-start-selftest.sh — deterministic, network-free checks for the
# PreToolUse agent-dispatch hook (`hooks/agent-dispatch-card-start`, card #4945).
#
# The hook is a straight script (no sourceable pure fns), so it is exercised as a
# subprocess: crafted stdin JSON is fed in and `kbcard` is replaced by a PATH shim that
# RECORDS its argv (never touches the network). HOME is a scratch dir so the only board-env
# files that exist are the ones this test creates. What it guards:
#   - the marker `BOARD-CARD: <key>#<id>` anchored at line START drives exactly one
#     `kbcard --board <key> move --task <id> --column in_progress` call (single hit);
#   - a prompt with NO marker — including one that merely mentions `card#1234` in prose —
#     makes NO call and exits 0 (the "not a bare number scan" contract);
#   - malformed stdin JSON exits 0 with no call (fail-soft);
#   - an unknown board key (no `~/.kanban-<key>-board.env`) exits 0, makes no call, and
#     writes a diagnostic (fail-soft-but-not-silent);
#   - multiple distinct markers each move; an exact duplicate marker moves once (dedupe);
#   - a marker mentioned MID-LINE (not at line start) is ignored (anchor test).
# Every path must exit 0 — the hook can never block a dispatch.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
HOOK="$HERE/../hooks/agent-dispatch-card-start"
_need -x "$HOOK"

_mktmp_scratch --home   # scratch HOME=$TMP so only the board-env files we create exist

# has <needle> <haystack> — literal-substring match (robust vs JSON/flag punctuation).
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# --- kbcard PATH shim: records each invocation's argv to $KBADS_REC, one line per call ----
export KBADS_REC="$TMP/kbcard.calls"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/kbcard" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KBADS_REC"
exit 0
STUB
chmod +x "$TMP/bin/kbcard"
export PATH="$TMP/bin:$PATH"

# Board-env fixtures the hook's unknown-key guard checks for (content is irrelevant — the
# stubbed kbcard never reads them; only their existence gates the call).
: > "$HOME/.kanban-toolkit-board.env"
: > "$HOME/.kanban-bridge-board.env"

# mk_input <prompt> — build a PreToolUse/Agent event JSON with the given prompt (jq escapes it).
mk_input() { jq -n --arg p "$1" '{hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{prompt:$p}}'; }

# run_raw <raw-stdin> — reset the record, run the hook, capture RC + stderr(ERR); stdout discarded.
run_raw() {
    : > "$KBADS_REC"
    local rc=0
    ERR="$(printf '%s' "$1" | bash "$HOOK" 2>&1 1>/dev/null)" || rc=$?
    RC=$rc
}
run_prompt() { run_raw "$(mk_input "$1")"; }

# recn — number of recorded kbcard invocations.
recn() { [[ -s "$KBADS_REC" ]] && wc -l < "$KBADS_REC" | tr -d ' ' || echo 0; }
recall() { cat "$KBADS_REC" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
echo "== single marker hit → one move with the right args =="
run_prompt "Build the widget.
BOARD-CARD: toolkit#4945
Do the thing."
eq "single marker exits 0"                 "0" "$RC"
eq "single marker → exactly one call"      "1" "$(recn)"
eq "call selects the board"                "true" "$(has -- '--board toolkit' "$(recall)")"
eq "call moves the right task to in_progress" "true" \
   "$(has 'move --task 4945 --column in_progress' "$(recall)")"

# ---------------------------------------------------------------------------
echo "== no marker → no call, exit 0 =="
run_prompt "Please refactor the thing. It relates to the widget subsystem."
eq "no-marker exits 0"                      "0" "$RC"
eq "no-marker → zero calls"                 "0" "$(recn)"

echo "== a bare 'card#1234' mention (no marker) → no call — NOT a number scan =="
run_prompt "Review the fix; see card#1234 and card 5678 for context, plus #91."
eq "bare card-mention exits 0"              "0" "$RC"
eq "bare card-mention → zero calls"         "0" "$(recn)"

# ---------------------------------------------------------------------------
echo "== malformed stdin JSON → exit 0, no call =="
run_raw "this is { not json"
eq "malformed JSON exits 0"                 "0" "$RC"
eq "malformed JSON → zero calls"            "0" "$(recn)"

# ---------------------------------------------------------------------------
echo "== unknown board key → exit 0, no call, diagnostic on stderr =="
run_prompt "BOARD-CARD: nosuchboard#4945"
eq "unknown-key exits 0"                    "0" "$RC"
eq "unknown-key → zero calls"               "0" "$(recn)"
eq "unknown-key writes a diagnostic"        "true" "$(has 'no board env' "$ERR")"

# ---------------------------------------------------------------------------
echo "== multiple distinct markers → each moves =="
run_prompt "BOARD-CARD: toolkit#4945
BOARD-CARD: bridge#100"
eq "multi-marker exits 0"                   "0" "$RC"
eq "multi-marker → two calls"               "2" "$(recn)"
eq "first board moved"                      "true" "$(has 'move --task 4945' "$(recall)")"
eq "second board moved"                     "true" "$(has 'move --task 100' "$(recall)")"

# ---------------------------------------------------------------------------
echo "== exact duplicate marker → deduped to one move =="
run_prompt "BOARD-CARD: toolkit#4945
BOARD-CARD: toolkit#4945"
eq "dup-marker exits 0"                     "0" "$RC"
eq "dup-marker → one call"                  "1" "$(recn)"

# ---------------------------------------------------------------------------
echo "== marker mid-line (not at line start) → ignored (anchor test) =="
run_prompt "please look at BOARD-CARD: toolkit#4945 later"
eq "mid-line marker exits 0"                "0" "$RC"
eq "mid-line marker → zero calls (anchored)" "0" "$(recn)"

# indented marker is still 'at line start' (leading whitespace tolerated) → it DOES fire.
echo "== leading-whitespace marker still fires (indentation tolerated) =="
run_prompt "  BOARD-CARD: toolkit#4945"
eq "indented marker → one call"             "1" "$(recn)"

_summary "agent-dispatch-card-start-selftest"
