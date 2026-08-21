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

# ---------------------------------------------------------------------------
echo "== board_report — a failed board read names the RC and asserts no cause (card#6594) =="
# This arm catches every paginator failure the snapshot does not render: rc 1 (page 1
# failed — no response, a non-2xx status, or since card#6594 a 2xx carrying no card
# array) AND rc 2 (a later page failed on a board that answered page 1). It said
# "(board API unreachable)", which is a claim about the world that is false for three
# of those four causes. board-snapshot does not set KB_FETCH_LOUD, so the paginator's
# own precise line is suppressed and THIS line is the operator's only diagnostic —
# which is why it must name the rc and name no cause.
envR="$(mkenv)"
_FRC=0
fetch_board_cards() { return "$_FRC"; }
for _FRC in 1 2; do
    out="$(board_report "$envR" "L" 3>/dev/null 2>/dev/null)"
    eq "fetch rc=$_FRC → the line names the rc"            "true"  "$(has "fetch rc=$_FRC" "$out")"
    eq "fetch rc=$_FRC → it claims no cause (unreachable)" "false" "$(has 'unreachable' "$out")"
done
# Control on the same route: a rc 0 read still renders the snapshot, so the two legs
# above are a refusal that discriminates rather than a board_report broken outright.
_FRC=0
fetch_board_cards() { printf '%s' '[{"id":11,"workflow_stage_id":84,"name":"y","tags":[]}]'; }
out="$(board_report "$envR" "L" 3>/dev/null 2>/dev/null)"
eq "CONTROL: rc 0 still renders the in-flight line" "true" "$(has 'in-flight' "$out")"
eq "CONTROL: rc 0 prints no failure line"           "false" "$(has 'board read failed' "$out")"

rm -f "$tokf" "$envB" "$envC" "$envNoId" "$errf" "$envF" "$envR" "$FETCH_LOG"

# ===========================================================================
# card#6365 — a PARTIAL read must not render as a complete one, ON STDOUT.
#
# WHY THIS BLOCK RUNS THE BIN AS A PROCESS against a stubbed `curl`, when the
# blocks above stub `fetch_board_cards` as a shell function: the defect is about
# WHICH CHANNEL the incompleteness reaches, and the consumer is a SessionStart
# hook that surfaces STDOUT and discards STDERR. A stubbed shell function can
# return 3 or 4, but it cannot produce them the way the real paginator does (a
# page cap actually hit; a `meta.total` the delivered rows fall short of), and it
# leaves the render path — where the count is printed — reached by a fake. So the
# rcs are driven through the REAL fetch_board_cards over a faked API, and EVERY
# assertion below reads the process's STDOUT with STDERR discarded, which is
# exactly what the hook sees. An assertion on the exit code would pass on the
# defect: the exit code was already 0 and always must be.
# ===========================================================================
echo "== board-snapshot(1) — an INCOMPLETE read is marked on STDOUT (card#6365) =="
_mktmp_scratch --home
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
kb_stub_scrub_env
kb_stub_board_config bstest 42 \
    'export KB_STAGE_IN_PROGRESS=84' \
    'export KB_STAGE_SHIPPED_TO_DEV=90'
kb_stub_install
printf 'bstest:T\n' > "$HOME/.kanban-snapshot-boards"
export KANBAN_SNAPSHOT_BOARDS="$HOME/.kanban-snapshot-boards"
# The staleness guard the bin folds into its output is not under test here and its
# line depends on the HOST. Shadow it with a silent no-op so the byte-identity
# control below compares the SNAPSHOT, not this machine.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/agent-board-toolkit-runtime-check"
chmod +x "$TMP/bin/agent-board-toolkit-runtime-check"

# One in-progress, untriaged card; a 200-row page for the cap scenario.
export KB_STUB_PRELOAD='{"data":{"workflows":[{"stages":[{"id":84,"name":"In Progress"}]}]}}'
KB_STUB_ONE="$(jq -cn '{data:[{id:101,workflow_stage_id:84,name:"card one",tags:[]}],meta:{total:1,last_page:1}}')"
KB_STUB_FULLPAGE="$(jq -cn '{data:[range(101;301)|{id:.,workflow_stage_id:84,name:"card \(.)",tags:[]}],meta:{total:400,last_page:2}}')"
KB_STUB_SHORT="$(jq -cn '{data:[range(101;103)|{id:.,workflow_stage_id:84,name:"card \(.)",tags:[]}],meta:{total:5,last_page:1}}')"
export KB_STUB_ONE KB_STUB_FULLPAGE KB_STUB_SHORT
# Scenario switching is by exported variable — the stub is a fresh process per request.
kb_stub_route() {
    local url="$2"
    case "$url" in
        */preload.json*) printf '200\n%s\n' "$KB_STUB_PRELOAD" ;;
        *tasks/search.json*)
            case "$KB_STUB_SCENARIO" in
                complete) printf '200\n%s\n' "$KB_STUB_ONE" ;;
                cap)      printf '200\n%s\n' "$KB_STUB_FULLPAGE" ;;
                short)    printf '200\n%s\n' "$KB_STUB_SHORT" ;;
                dead)     printf '500\n%s\n' '{"error":"boom"}' ;;
            esac ;;
    esac
}
export -f kb_stub_route

# snap <scenario> [page-cap] — the bin's STDOUT only, stderr discarded exactly as the
# SessionStart hook discards it. Its exit status lands in $SNAP_RC.
SNAP_RC=0
snap() {
    export KB_STUB_SCENARIO="$1" SNAPSHOT_PAGE_CAP="${2:-25}"
    kb_stub_reset
    local out; out="$(bash "$BIN" 2>/dev/null)"; SNAP_RC=$?
    printf '%s' "$out"
}
# untriaged_section <output> — the part below the untriaged header. The two sections are
# rendered from the SAME partial read but printed under different headers, so a marker in
# one says nothing about the other.
untriaged_section() { printf '%s' "$1" | awk '/^── Untriaged cards/{f=1;next} f'; }

# --- control 3 FIRST: a COMPLETE read renders exactly as it always did ------
# Byte equality, not a substring: a fix that marked every snapshot incomplete would
# be worse than the defect, and only an exact comparison can see that.
out="$(snap complete)"
expected="── Dev board snapshot — boards are the source of truth (memory is a cache) ──
• T: in-flight 1
    #101 [In Progress] card one
── Untriaged cards — triage is my responsibility; none may be silently missed ──
⚠ T: 1 UNTRIAGED — run the /triage-cards skill (newest first):
    #101 [stage 84] card one"
eq "CONTROL rc 0: the complete-read render is byte-identical" "$expected" "$out"
eq "CONTROL rc 0: exits 0"                                    "0" "$SNAP_RC"

# --- positive 1: the page cap (rc 3) ---------------------------------------
out="$(snap cap 1)"
eq "rc 3: the in-flight COUNT itself is marked as a floor" "true" "$(has 'in-flight ≥200' "$out")"
eq "rc 3: STDOUT names the read INCOMPLETE and the rc"     "true" "$(has 'card list INCOMPLETE (fetch rc=3)' "$out")"
eq "rc 3: the count is never printed unqualified"          "false" "$(has 'in-flight 200' "$out")"
eq "rc 3: the UNTRIAGED section carries its own marker"    "true" \
   "$(has 'INCOMPLETE (fetch rc=3)' "$(untriaged_section "$out")")"
eq "rc 3: the untriaged COUNT is marked too"               "true" "$(has '≥200 UNTRIAGED' "$out")"
eq "rc 3: fail-soft — still exits 0"                       "0" "$SNAP_RC"

# --- positive 2: the short read (rc 4) -------------------------------------
out="$(snap short)"
eq "rc 4: the in-flight COUNT itself is marked as a floor" "true" "$(has 'in-flight ≥2' "$out")"
eq "rc 4: STDOUT names the read INCOMPLETE and the rc"     "true" "$(has 'card list INCOMPLETE (fetch rc=4)' "$out")"
eq "rc 4: the count is never printed unqualified"          "false" "$(has 'in-flight 2' "$out")"
eq "rc 4: the UNTRIAGED section carries its own marker"    "true" \
   "$(has 'INCOMPLETE (fetch rc=4)' "$(untriaged_section "$out")")"
eq "rc 4: fail-soft — still exits 0"                       "0" "$SNAP_RC"

# --- control 4: a hard read failure is still fail-soft ----------------------
# The contract in this file's header: a slow/down API prints a notice and exits 0,
# never blocking startup. Asserted on the RENDER, not on the status alone.
out="$(snap dead)"
eq "CONTROL rc 1: exits 0 (SessionStart is never blocked)"  "0" "$SNAP_RC"
eq "CONTROL rc 1: still prints the snapshot header"         "true" "$(has 'Dev board snapshot' "$out")"
eq "CONTROL rc 1: reports the board, naming the rc"         "true" "$(has '• T: (board read failed — fetch rc=1)' "$out")"
eq "CONTROL rc 1: claims no completeness it does not have"  "false" "$(has 'in-flight' "$out")"

# ---------------------------------------------------------------------------
_summary "board-snapshot-selftest"
