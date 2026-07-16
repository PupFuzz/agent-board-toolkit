#!/usr/bin/env bash
# board-snapshot-selftest.sh — network-free regression tests for board-snapshot's
# per-board env ISOLATION (card-4448). Board envs export their keys, so an operator
# shell that sourced board A carries A's KB_BOARD_ID / KB_STAGE_* into the next
# board; untriaged() unset only KBCARD_TOKEN_FILE, so a board B env that omitted a
# terminal stage id silently inherited A's — corrupting B's terminal-stage set and
# defeating the "triage is never silently missed" contract QUIETLY.
#
# fetch_board_cards is STUBBED, so no API is touched. Sources the bin (main-guarded)
# for its pure functions; matches the toolkit's runnable-script selftest convention.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BIN="$HERE/../bin/board-snapshot"
[[ -r "$BIN" ]] || { echo "selftest: $BIN not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines board_env_scrub/snap/untriaged, renders nothing

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"; }
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# Clean slate — the operator's shell may carry a real board env; scrub so no live id
# fakes a pass/fail. (This is exactly what board_env_scrub does per board at runtime.)
# shellcheck disable=SC2086
unset KBCARD_TOKEN_FILE KB_BOARD_ID ${!KB_STAGE_@}

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
echo "== untriaged — a sibling's leaked terminal id must NOT suppress a card (card-4448) =="
# Stub the paginated fetch: no API is touched; the render logic is what is under test.
fetch_board_cards() { printf '%s' "$STUB_DATA"; }

tokf="$(mktemp)"; printf 'test-token\n' > "$tokf"
# Board B's env sets its own id + token but OMITS KB_STAGE_SHIPPED_TO_DEV.
envB="$(mktemp)"; printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\n' "$tokf" > "$envB"

# The leak: this shell already sourced sibling board A, which exported its shipped id.
export KB_STAGE_SHIPPED_TO_DEV=999
# A card sitting at 999, untagged. Under the bug, B inherits 999 as terminal and
# SUPPRESSES it; fixed, B's terminal set is empty so it surfaces as UNTRIAGED.
STUB_DATA='[{"id":7,"workflow_stage_id":999,"name":"leaked-terminal card","tags":[]}]'
out="$(untriaged "$envB" "Board B")"
eq "card at the sibling's leaked terminal id is flagged UNTRIAGED" "true" "$(has '#7' "$out")"
eq "output names it UNTRIAGED"                                     "true" "$(has 'UNTRIAGED' "$out")"

# Positive control: a card at B's OWN (post-source) terminal stage IS suppressed —
# proves the surfacing above is real isolation, not blanket-broken suppression.
printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\nexport KB_STAGE_SHIPPED_TO_DEV=500\n' "$tokf" > "$envB"
STUB_DATA='[{"id":8,"workflow_stage_id":500,"name":"really shipped","tags":[]}]'
out="$(untriaged "$envB" "Board B")"
eq "a card at B's OWN terminal stage is suppressed (control)" "false" "$(has '#8' "$out")"

# ---------------------------------------------------------------------------
echo "== untriaged — missing KB_BOARD_ID ⇒ SILENT no-op, never a wrong-board fetch =="
envNoId="$(mktemp)"; printf 'export KBCARD_TOKEN_FILE=%s\n' "$tokf" > "$envNoId"   # no KB_BOARD_ID
errf="$(mktemp)"
STUB_DATA='[{"id":9,"workflow_stage_id":123,"name":"must never render","tags":[]}]'
out="$(untriaged "$envNoId" "Board NoId" 2>"$errf")"; err="$(cat "$errf")"
eq "no KB_BOARD_ID ⇒ empty stdout (guard returns before fetch/render)" "" "$out"
# Assert SILENCE, not just empty stdout: without the guard, set -u aborts the subshell
# on the unset KB_BOARD_ID with an 'unbound variable' line — empty stdout but NOISY
# stderr, which a fail-soft SessionStart tool must not emit. This is what reds on a
# guard removal (empty stdout alone does not — set -u masks it).
eq "no KB_BOARD_ID ⇒ empty stderr (clean guard, not a set -u abort)" "" "$err"

rm -f "$tokf" "$envB" "$envNoId" "$errf"

# ---------------------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
    echo "board-snapshot-selftest: $fails check(s) FAILED" >&2
    exit 1
fi
echo "board-snapshot-selftest: all checks passed"
