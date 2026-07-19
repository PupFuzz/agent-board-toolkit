#!/usr/bin/env bash
# board-snapshot-selftest.sh — network-free tests for board_report's per-board
# ISOLATION (card-4448) and its SINGLE-FETCH dedup (card-4447).
#
# board_report does one setup+fetch per board, rendering the in-flight snapshot to
# stdout and the untriaged list to fd 3. Board envs export their keys, so an
# operator shell that sourced board A carries A's KB_BOARD_ID / KB_STAGE_* into the
# next board; a board B env that omitted a terminal stage id used to inherit A's,
# corrupting B's terminal set and defeating "triage is never silently missed"
# QUIETLY. And the snapshot + untriaged renders used to fetch the SAME board twice.
#
# fetch_board_cards and kb_api (the preload read) are STUBBED, so no API is touched.
# Sources the bin (main-guarded) for its pure functions.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/board-snapshot"
_need -r "$BIN"
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines board_env_scrub/board_report, renders nothing

has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# Stubs — network-free. fetch_board_cards logs each call to a file so the count
# survives board_report's subshell (a var would not). kb_api stubs the preload.
FETCH_LOG="$(mktemp)"
STUB_DATA='[]'
fetch_board_cards() { echo x >> "$FETCH_LOG"; printf '%s' "$STUB_DATA"; }
kb_api() { printf '%s' '{}'; }

# Clean slate — the operator's shell may carry a real board env; scrub so no live
# id fakes a pass/fail (this is what board_env_scrub does per board at runtime).
# shellcheck disable=SC2086
unset KBCARD_TOKEN_FILE KB_BOARD_ID ${!KB_STAGE_@}

tokf="$(mktemp)"; printf 'test-token\n' > "$tokf"
mkenv() { local f; f="$(mktemp)"; printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\n' "$tokf" > "$f"; printf '%s' "$f"; }
# untri <envf> : the untriaged section only (fd 3 → capture; snapshot fd 1 → /dev/null)
untri() { board_report "$1" "L" 3>&1 1>/dev/null 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "== board_env_scrub — clears an inherited sibling board's exported keys =="
export KB_BOARD_ID=5 KBCARD_TOKEN_FILE=/x/y \
       KB_STAGE_SHIPPED_TO_DEV=99 KB_STAGE_HELD=42 KB_STAGE_TECH_DEBT=7
board_env_scrub
eq "KB_BOARD_ID unset"                       "" "${KB_BOARD_ID:-}"
eq "KBCARD_TOKEN_FILE unset"                 "" "${KBCARD_TOKEN_FILE:-}"
eq "KB_STAGE_SHIPPED_TO_DEV unset"           "" "${KB_STAGE_SHIPPED_TO_DEV:-}"
eq "KB_STAGE_HELD unset"                     "" "${KB_STAGE_HELD:-}"
# The whole point of the glob over an enumerated list: a KB_STAGE_* the function
# does not name is STILL scrubbed, so the list can never drift back into the bug.
eq "non-enumerated KB_STAGE_* unset (glob)"  "" "${KB_STAGE_TECH_DEBT:-}"

# ---------------------------------------------------------------------------
echo "== board_report untriaged — a sibling's leaked terminal id must NOT suppress a card (card-4448) =="
envB="$(mkenv)"   # B sets its own id + token but OMITS KB_STAGE_SHIPPED_TO_DEV
export KB_STAGE_SHIPPED_TO_DEV=999   # the leak: this shell already sourced sibling board A
STUB_DATA='[{"id":7,"workflow_stage_id":999,"name":"leaked-terminal card","tags":[]}]'
out="$(untri "$envB")"
eq "card at the sibling's leaked terminal id is flagged UNTRIAGED" "true" "$(has '#7' "$out")"
eq "output names it UNTRIAGED"                                     "true" "$(has 'UNTRIAGED' "$out")"

# Positive control: a card at B's OWN (post-source) terminal stage IS suppressed —
# proves the surfacing above is real isolation, not blanket-broken suppression.
envC="$(mktemp)"; printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\nexport KB_STAGE_SHIPPED_TO_DEV=500\n' "$tokf" > "$envC"
STUB_DATA='[{"id":8,"workflow_stage_id":500,"name":"really shipped","tags":[]}]'
out="$(untri "$envC")"
eq "a card at B's OWN terminal stage is suppressed (control)" "false" "$(has '#8' "$out")"

# ---------------------------------------------------------------------------
echo "== board_report untriaged — missing KB_BOARD_ID ⇒ SILENT no-op, never a wrong-board fetch =="
envNoId="$(mktemp)"; printf 'export KBCARD_TOKEN_FILE=%s\n' "$tokf" > "$envNoId"   # no KB_BOARD_ID
errf="$(mktemp)"
STUB_DATA='[{"id":9,"workflow_stage_id":123,"name":"must never render","tags":[]}]'
out="$(board_report "$envNoId" "L" 3>&1 1>/dev/null 2>"$errf")"; err="$(cat "$errf")"
eq "no KB_BOARD_ID ⇒ empty untriaged channel (guard returns before render)" "" "$out"
# Assert SILENCE on stderr too: without the guard, set -u aborts the subshell on the
# unset KB_BOARD_ID with an 'unbound variable' line — empty fd 3 but NOISY stderr,
# which a fail-soft SessionStart tool must not emit. This reds on a guard removal.
eq "no KB_BOARD_ID ⇒ empty stderr (clean guard, not a set -u abort)" "" "$err"

# ---------------------------------------------------------------------------
echo "== board_report — ONE fetch per board (card-4447 dedup; snapshot + untriaged share it) =="
: > "$FETCH_LOG"
STUB_DATA='[{"id":10,"workflow_stage_id":500,"name":"x","tags":[]}]'
envF="$(mkenv)"
board_report "$envF" "L" 3>/dev/null >/dev/null
eq "board_report calls fetch_board_cards exactly once" "1" "$(wc -l < "$FETCH_LOG" | tr -d ' ')"

rm -f "$tokf" "$envB" "$envC" "$envNoId" "$errf" "$envF" "$FETCH_LOG"

# ---------------------------------------------------------------------------
_summary "board-snapshot-selftest"
