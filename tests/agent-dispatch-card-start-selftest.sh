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
eq "call selects the board"                "true" "$(has '--board toolkit' "$(recall)")"
eq "call moves the right task to in_progress" "true" \
   "$(has 'move --task 4945 --column in_progress' "$(recall)")"
eq "call asks kbcard to stamp the seat owner tag" "true" \
   "$(has 'move --task 4945 --column in_progress --stamp-owner' "$(recall)")"

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
eq "first call routes to toolkit board"     "true" "$(has '--board toolkit' "$(recall)")"
eq "second board moved"                     "true" "$(has 'move --task 100' "$(recall)")"
eq "second call routes to bridge board"     "true" "$(has '--board bridge' "$(recall)")"

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

# ---------------------------------------------------------------------------
echo "== kbcard exit 1 (failure) → hook exits 0, diagnostic on stderr =="
# Temporarily replace kbcard with a stub that exits 1 on the marker.
cat > "$TMP/bin/kbcard" <<'STUB_FAIL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KBADS_REC"
# Exit 1 if this is a move for toolkit#4945.
if [[ "$*" == *"--task 4945"* ]]; then
    exit 1
fi
exit 0
STUB_FAIL
chmod +x "$TMP/bin/kbcard"
run_prompt "BOARD-CARD: toolkit#4945"
eq "kbcard failure exits hook 0"            "0" "$RC"
eq "kbcard failure records the call"        "1" "$(recn)"
eq "kbcard failure writes diagnostic"       "true" "$(has 'kbcard move failed' "$ERR")"

# ---------------------------------------------------------------------------
echo "== kbcard's owner-tag lines are relayed; the rest of its output stays suppressed =="
cat > "$TMP/bin/kbcard" <<'STUB_OWNER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KBADS_REC"
echo "kbcard: HTTP 200 noise that must stay suppressed" >&2
echo "kbcard: owner tag owner:acme/builder NOT stamped on task 4945 — the card is already held by owner:other/reviewer." >&2
echo '{"id":4945}'
exit 0
STUB_OWNER
chmod +x "$TMP/bin/kbcard"
run_prompt "BOARD-CARD: toolkit#4945"
eq "owner relay exits 0"                         "0" "$RC"
eq "the owner-tag refusal reaches the hook's stderr, naming the holder" "true" \
   "$(has 'agent-dispatch-card-start: kbcard: owner tag owner:acme/builder NOT stamped on task 4945 — the card is already held by owner:other/reviewer.' "$ERR")"
eq "…the other kbcard stderr does not"           "false" "$(has 'noise that must stay suppressed' "$ERR")"
eq "…nor does kbcard's stdout"                   "false" "$(has '"id":4945' "$ERR")"
eq "…and it is not reported as a failed move"    "false" "$(has 'kbcard move failed' "$ERR")"

# ---------------------------------------------------------------------------
echo "== end to end: the REAL kbcard against a faked kanban API stamps the owner tag =="
# The shim above proves the relay; this proves the hook's argv drives the real primitive to the
# PATCH the owner rule promises. Only `curl` is faked.
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
kb_stub_scrub_env
kb_stub_board_config toolkit 42 'export KB_STAGE_IN_PROGRESS=49'
kb_stub_install
ln -sf "$(readlink -f "$HERE/../bin/kbcard")" "$TMP/bin/kbcard"
printf '{"project":"acme","roster":[{"name":"builder"}]}\n' > "$TMP/coordination.config.json"
kb_stub_route() {
    case "$1 $2" in
        "GET "*/tasks/4945.json*) printf '200\n{"data":{"id":4945,"workflow_stage_id":48,"tags":["fr"]}}' ;;
        "PATCH "*/tasks/4945.json) printf '200\n'; jq -cn --argjson b "$3" '{data: ({id:4945,name:"probe"} + $b)}' ;;
        *) printf '404\n{"message":"unrouted"}' ;;
    esac
}
export -f kb_stub_route
kb_stub_reset
COORD_CONFIG="$TMP/coordination.config.json" COORD_AGENT=builder run_prompt "BOARD-CARD: toolkit#4945"
eq "end to end exits 0"                          "0" "$RC"
eq "…ONE PATCH carries the move and the card's tags plus the owner tag" \
   '{"tags":["fr","owner:acme/builder"],"workflow_stage_id":49}' "$(kb_stub_bodies PATCH /tasks/4945.json | jq -cS .)"
eq "…and the hook relays that it stamped"        "true" "$(has 'kbcard: owner tag owner:acme/builder stamped on task 4945' "$ERR")"
kb_stub_reset
COORD_CONFIG="$TMP/coordination.config.json" COORD_AGENT=ghost run_prompt "BOARD-CARD: toolkit#4945"
eq "an unresolvable seat still MOVES the card"   '{"workflow_stage_id":49}' "$(kb_stub_bodies PATCH /tasks/4945.json | jq -cS .)"
eq "…and the hook relays why it did not stamp"   "true" "$(has "COORD_AGENT 'ghost' is not a roster[].name" "$ERR")"
unset -f kb_stub_route

_summary "agent-dispatch-card-start-selftest"
