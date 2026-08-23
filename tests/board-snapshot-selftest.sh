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
echo "== board_report untriaged — missing KB_BOARD_ID ⇒ no wrong-board CARD, and the channel SAYS SO =="
envNoId="$(mktemp)"; printf 'export KBCARD_TOKEN_FILE=%s\n' "$tokf" > "$envNoId"   # no KB_BOARD_ID
errf="$(mktemp)"
STUB_DATA='[{"id":9,"workflow_stage_id":123,"name":"must never render","tags":[]}]'
out="$(board_report "$envNoId" "L" 3>&1 1>/dev/null 2>"$errf")"; err="$(cat "$errf")"
# The load-bearing half is that NO CARD from the un-selected board reaches the untriaged
# channel — the card-4448 protection. It used to be asserted as "fd 3 is EMPTY", which is a
# stronger claim than the protection needs and, until card#6365's second pass, was also the
# defect: an empty untriaged section under a header that says "none may be silently missed"
# is a completeness claim about a board whose cards were never read. An absence assertion
# alone certifies whatever replaces it (including nothing), so it is paired with a presence
# witness: the reason, on the same channel.
eq "no KB_BOARD_ID ⇒ no card reaches the untriaged channel" "false" "$(has '#9' "$out")"
eq "no KB_BOARD_ID ⇒ the untriaged channel says the board was NOT read" "true" \
   "$(has 'sets no KB_BOARD_ID' "$out")"
eq "no KB_BOARD_ID ⇒ …and says no untriaged card from it appears" "true" \
   "$(has 'NOT read' "$out")"
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

# ===========================================================================
# card#6365 review — EVERY arm that ends a board's pass without a card list must
# mark the UNTRIAGED channel, not just the two rcs that render a partial array.
#
# The rc-3/rc-4 note above exists because "nothing to triage" is a claim a partial
# read may not make. The arms below make a STRONGER version of it: they read zero
# rows and, before this block, contributed NOTHING to fd 3 — so the untriaged
# section rendered empty, under a header asserting that none may be silently
# missed, for a board nobody read. Same header, same channel, weaker evidence.
#
# The population is the arms that can end board_report without a card list. It is
# DERIVED here rather than listed: every `return 0` guard in board_report plus the
# two render fallbacks. The count is asserted below so a new arm reds this file.
# ===========================================================================
echo "== board_report — an UNREAD board marks the untriaged channel too (card#6365 review) =="

# The four setup/read arms, each driven through the real function. `unread <envf>`
# returns the fd-3 (untriaged) channel only, which is the channel under test.
unread() { board_report "$1" "L" 3>&1 1>/dev/null 2>/dev/null; }

tokf2="$(mktemp)"; printf 'test-token\n' > "$tokf2"
envOK="$(mktemp)"; printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\n' "$tokf2" > "$envOK"
envBadTok="$(mktemp)"; printf 'export KB_BOARD_ID=88\nexport KBCARD_TOKEN_FILE=%s\n' "/nonexistent/token" > "$envBadTok"

fetch_board_cards() { printf '%s' '[]'; }

out="$(unread "/nonexistent/board.env")"
eq "arm: env file missing → the untriaged channel names it"      "true" "$(has 'missing' "$out")"
eq "arm: env file missing → …and says the board was NOT read"    "true" "$(has 'NOT read' "$out")"

out="$(unread "$envBadTok")"
eq "arm: token unreadable → the untriaged channel names it"      "true" "$(has 'token file unreadable' "$out")"
eq "arm: token unreadable → …and says the board was NOT read"    "true" "$(has 'NOT read' "$out")"

# card#7245: a board that DECLARES no token file used to fall through to ~/.kanban-dev-token —
# a credential nobody chose for it and every other board shared. It is now its own arm. The
# host tier is unset in the subshell, because that is the tier this case is about; with a host
# default present the board is legitimately covered and there is nothing to report.
envNoTok="$(mktemp)"; printf 'export KB_BOARD_ID=88\n' > "$envNoTok"
out="$(unset KB_HOST_TOKEN_FILE; unread "$envNoTok")"
eq "arm: no token DECLARED → the untriaged channel names it"     "true" "$(has 'no KBCARD_TOKEN_FILE declared' "$out")"
eq "arm: no token DECLARED → …and says the board was NOT read"   "true" "$(has 'NOT read' "$out")"
eq "arm: no token DECLARED → …and does NOT name ~/.kanban-dev-token" "false" "$(has '.kanban-dev-token' "$out")"
# WITNESS: the same env with the host tier supplied is read normally, so the arm above is
# about a missing DECLARATION and not about this fixture being unreadable in general.
out="$(KB_HOST_TOKEN_FILE="$tokf2" unread "$envNoTok")"
eq "  …while a host-declared token file covers that same board (witness)" "false" "$(has 'NOT read' "$out")"

_FRC2=0
fetch_board_cards() { return "$_FRC2"; }
for _FRC2 in 1 2; do
    out="$(unread "$envOK")"
    eq "arm: fetch rc=$_FRC2 → the untriaged channel names the rc"  "true" "$(has "fetch rc=$_FRC2" "$out")"
    eq "arm: fetch rc=$_FRC2 → …and says the board was NOT read"    "true" "$(has 'NOT read' "$out")"
    # The message rule the paginator's contract puts on a MULTI-RC arm binds this
    # channel exactly as it binds stdout: name the rc, name no cause.
    eq "arm: fetch rc=$_FRC2 → claims no cause on fd 3"             "false" "$(has 'unreachable' "$out")"
done

# CONTROL — a COMPLETE read must not emit the unread note on either channel, or the
# six assertions above would pass on a board_report that shouted on every pass.
_FRC2=0
fetch_board_cards() { printf '%s' '[{"id":12,"workflow_stage_id":84,"name":"z","tags":[]}]'; }
out="$(unread "$envOK")"
eq "CONTROL rc 0: the untriaged channel carries NO unread note" "false" "$(has 'NOT read' "$out")"
eq "CONTROL rc 0: it still carries the untriaged card"          "true"  "$(has '#12' "$out")"

# DENOMINATOR — the population this block covers, re-derived from the bin on every
# run rather than recalled. Every `return 0` early exit inside board_report is an
# arm that ends the pass without a card list; each one must report through
# board_unread, and a new arm that echoes to stdout instead reds here. The two jq
# render fallbacks are counted separately below because they exit through the
# pipeline, not through a `return`.
_bs_body() { sed -n '/^board_report() {/,/^}/p' "$BIN"; }
early_exits="$(_bs_body | command grep -c 'return 0; }')"
via_unread="$(_bs_body | command grep -c 'board_unread "\$label"')"
eq "denominator: every early-exit arm in board_report reports through board_unread" \
   "$early_exits" "$via_unread"
[[ "$early_exits" -ge 4 ]] || bad "denominator: only $early_exits early-exit arms derived — the sed window stopped covering board_report"
ok "denominator: $early_exits early-exit arms derived from the bin, all routed through board_unread"
# The renders are the other half: each of the two jq programs owns a fallback on ITS
# OWN channel, so a render that dies contributes a line to the section it failed to
# fill instead of leaving it silently empty.
eq "render fallback: the in-flight jq reports on stdout" "true" \
   "$(has 'parse error' "$(_bs_body | command grep '|| echo "• ${label}: (parse error)"')")"
eq "render fallback: the untriaged jq reports on fd 3"   "true" \
   "$(has '>&3' "$(_bs_body | command grep 'untriaged list could not be rendered')")"

rm -f "$tokf2" "$envOK" "$envBadTok"

# ===========================================================================
# card#6365 review — the `≥` claim has a DENOMINATOR: EVERY count this pass
# prints, not the two that were easy to name.
#
# The changelog and the plan entry both say "a ≥ prefix on every count this pass
# prints". The untriaged list's overflow tail ("… +194 more") shipped bare, which
# made that sentence false — and the tail is a floor for exactly the same reason
# the other two counts are. Two legs: the rendered OUTPUT on a partial read, and a
# source-derived leg over the render programs so a FOURTH count added without
# $floor reds without anyone remembering this rule.
# ===========================================================================
echo "== board-snapshot(1) — every printed count carries the floor marker (card#6365 review) =="
out="$(snap cap 1)"
eq "rc 3: the untriaged overflow tail is marked as a floor" "true" "$(has '… +≥194 more' "$out")"
eq "rc 3: the overflow tail is never printed unqualified"   "false" "$(has '… +194 more' "$out")"

# The source leg. Every jq render line that INTERPOLATES a `length` must interpolate
# $floor too — the predicate is `\(` + `length` on one line, which selects the three
# printed counts and excludes the bare `($u | length) > 0` predicates that print
# nothing. Derived from the bin, so a new count is in the population the day it lands.
count_lines="$(command grep -n 'length' "$BIN" | command grep '\\(')"
eq "source: three count interpolations derived from the bin" "3" \
   "$(printf '%s\n' "$count_lines" | command grep -c .)"
bare="$(printf '%s\n' "$count_lines" | command grep -v '\\(\$floor)' || true)"
eq "source: no count is interpolated without \$floor" "" "$bare"
# CONTROL for the source leg — it must be able to fail. A synthetic render line with a
# bare count must be selected by the predicate and rejected by it.
_ctl='| "• \($label): in-flight \([$t[]]|length)",'
eq "CONTROL: the source predicate SELECTS a bare count line" "true" \
   "$(has 'length' "$(printf '%s\n' "$_ctl" | command grep 'length' | command grep '\\(' || true)")"
eq "CONTROL: …and REJECTS it for missing \$floor" "true" \
   "$(has 'length' "$(printf '%s\n' "$_ctl" | command grep -v '\\(\$floor)' || true)")"

# ===========================================================================
echo "== board-snapshot(1) — the api-host preflight refuses BEFORE any board is read (card#7245) =="
# Same stub, same roster; the ONLY thing that moves is which host the host env declares. The
# request log is the observable: a "refusal" that still fetched would leave lines in it. And rc
# stays 0 either way — this runs from SessionStart and must never block it, so the exit code is
# not the discriminator and asserting on it alone would pass on the defect.
kb_stub_reset
_sp_ok="$(snap complete)"
eq "control: the declared host renders a snapshot" "true"  "$(has '── Dev board snapshot' "$_sp_ok")"
eq "  …and it issued requests"                     "false" "$([[ "$(kb_stub_total)" -eq 0 ]] && echo true || echo false)"
eq "  …and did NOT print the skip line"            "false" "$(has 'SKIPPED' "$_sp_ok")"

sed 's/^export KANBAN_EXPECTED_HOST=.*/export KANBAN_EXPECTED_HOST="somewhere.else.invalid"/' \
    "$KANBAN_HOST_ENV" > "$TMP/host-mismatch.env"
eq "the mismatch fixture really differs (control)" "false" \
   "$(cmp -s "$KANBAN_HOST_ENV" "$TMP/host-mismatch.env" && echo true || echo false)"
kb_stub_reset
export KB_STUB_SCENARIO=complete
_sp_rc=0
_sp_out="$(KANBAN_HOST_ENV="$TMP/host-mismatch.env" bash "$BIN" 2>/dev/null)" || _sp_rc=$?
eq "an undeclared api host still exits 0 (never blocks SessionStart)" "0" "$_sp_rc"
eq "  and NOTHING was requested"                   "0"     "$(kb_stub_total)"
eq "  and the reader is TOLD the section was skipped" "true" "$(has 'SKIPPED' "$_sp_out")"
eq "  …rather than shown an empty board list"      "false" "$(has '── Untriaged cards' "$_sp_out")"
# ⛔ THE REMEDIATION MUST BE ON THE LINE ITSELF, and $_sp_out is captured with 2>/dev/null
# for exactly that reason — it is the channel pair board-session-close:825 uses
# (`board-snapshot 2>/dev/null`), and README.md's own rule is that stdout is the only stream
# the SessionStart hook surfaces. This line used to end in "(see stderr)" and say nothing
# else: through the real consumer that is a pointer at a discarded stream, i.e. an operator
# told a board was skipped and given no way to find out why. card#6365 already decided this
# channel question for this tool; the rc-7 token arm above ("no KBCARD_TOKEN_FILE declared
# in <file>") is the shape being matched.
eq "  …and the SKIP LINE ITSELF names the variable to set" "true" \
   "$(has 'KANBAN_EXPECTED_HOST' "$_sp_out")"
eq "  …and the file to set it in"                          "true" \
   "$(has '.kanban-host.env' "$_sp_out")"
# The REFUSED host is the stub api's ($KB_STUB_HOST) — the fixture moved the DECLARED one to
# somewhere.else.invalid, so naming that would assert the operator's own typo back at them.
eq "  …and the host it actually refused"                   "true" \
   "$(has "$KB_STUB_HOST" "$_sp_out")"
eq "  …and NOT the declared host it was measured against"  "false" \
   "$(has 'somewhere.else.invalid' "$_sp_out")"
# CONTROL: the three assertions above are host/var/file strings, not words that appear in
# any skip line — the discarded STDERR does carry all three, so a `has` run against the
# stderr-inclusive capture must find them. If this control fails, the rows above are
# measuring the wrong stream rather than the wrong content.
_sp_both="$(KANBAN_HOST_ENV="$TMP/host-mismatch.env" bash "$BIN" 2>&1)" || true
eq "CONTROL: stderr does carry the remediation"            "true" \
   "$(has 'KANBAN_EXPECTED_HOST' "$_sp_both")"

echo "== …and an UNCONFIGURED install is refused, not defaulted into looking configured =="
# ⛔ THE PREFLIGHT USED TO PASS ON A BOX WITH NO HOST ENV. This bin defaulted API to
# `https://YOUR-KANBAN-HOST/api/v3`, which is the literal KBCARD_API in
# examples/kanban-host.env.example — whose KANBAN_EXPECTED_HOST is `YOUR-KANBAN-HOST`. So the
# placeholder matched itself and the guard that exists to refuse an endpoint nobody declared
# said yes to the one nobody had configured at all. The fallback is gone; unset is unset.
sed 's/^export KBCARD_API=.*//' "$KANBAN_HOST_ENV" > "$TMP/host-noapi.env"
eq "the no-API fixture really dropped it (control)" "false" \
   "$(has 'KBCARD_API' "$(cat "$TMP/host-noapi.env")")"
kb_stub_reset
export KB_STUB_SCENARIO=complete
_na_rc=0
_na_out="$(KANBAN_HOST_ENV="$TMP/host-noapi.env" bash "$BIN" 2>/dev/null)" || _na_rc=$?
eq "no KBCARD_API still exits 0 (never blocks SessionStart)" "0" "$_na_rc"
eq "  and NOTHING was requested"                            "0" "$(kb_stub_total)"
eq "  and it is NOT silently treated as configured"     "true" "$(has 'SKIPPED' "$_na_out")"
eq "  …naming the variable that is missing"             "true" "$(has 'KBCARD_API' "$_na_out")"
eq "  …and the file to create"                          "true" "$(has '.kanban-host.env' "$_na_out")"
eq "  …and never the placeholder host it used to invent" "false" \
   "$(has 'YOUR-KANBAN-HOST' "$_na_out")"

# ===========================================================================
echo "== board-snapshot(1) — a runtime guard that DID NOT COMPLETE is not reported as clean (card#7305) =="
# `agent-board-toolkit-runtime-check --quiet` prints nothing when the runtime is current, so
# SILENCE IS THE CLEAN SIGNAL on this leg — and that guard buffers its whole report and writes
# it once at the end (deliberately: progressive output is what let a truncating reader destroy
# its verdict, card#6911). A run that dies before that single write therefore emits nothing at
# all, byte-identical to a healthy one. The leg used to end `… 2>&1 || true`, discarding the
# status the guard's own header calls the channel its verdict rides on, so both outcomes
# reached the operator as the same clean silence.
#
# THE THREE ARMS ARE THE WHOLE PREDICATE — silent-and-current, silent-and-dead,
# loud-and-failing. The middle one is the finding; the other two are what stop the fix being a
# decoration (arm 1 would still pass if the new line were unconditional) or a new source of
# noise on the case that was already working (arm 3). Every capture goes through `snap`, i.e.
# the bin's STDOUT with stderr discarded — the stream the SessionStart hook actually surfaces.
_rtc() {
    printf '%s\n' "$1" > "$TMP/bin/agent-board-toolkit-runtime-check"
    chmod +x "$TMP/bin/agent-board-toolkit-runtime-check"
}
_RTC_NEEDLE='runtime-staleness check DID NOT COMPLETE'

# arm 1 — CONTROL: a current runtime. Silent, rc 0; must stay silent.
_rtc '#!/usr/bin/env bash
exit 0'
_rtc_ok="$(snap complete)"
eq "control: a CURRENT runtime adds no line"                 "false" "$(has "$_RTC_NEEDLE" "$_rtc_ok")"
eq "  …and the snapshot exits 0"                             "0"     "$SNAP_RC"

# arm 2 — THE FINDING. SIGKILL is untrappable, so the stub does not simulate the event, it IS
# the event: the guard dies before its write and the caller sees 0 bytes at status 137.
_rtc '#!/usr/bin/env bash
kill -9 $$
echo "runtime-check: ✗ STALE COPIES" >&2'
_rtc_dead="$(snap complete)"
eq "a KILLED runtime guard is reported, not swallowed"       "true"  "$(has "$_RTC_NEEDLE" "$_rtc_dead")"
eq "  …and the line names the status it exited with"         "true"  "$(has 'exited 137' "$_rtc_dead")"
eq "  …and names the command to re-run"                      "true"  "$(has 'Re-run it directly' "$_rtc_dead")"
eq "  …and it STILL never blocks SessionStart"               "0"     "$SNAP_RC"
# ⛔ THE DISCRIMINATOR ITSELF, as one assertion: these two renders used to be byte-identical,
# which is the entire defect. Asserting only on the needle above would still pass if the line
# were also being printed on the healthy run.
eq "  …and no longer renders identically to the CURRENT run" "false" \
   "$([[ "$_rtc_dead" == "$_rtc_ok" ]] && echo true || echo false)"

# arm 3 — CONTROL: a guard that found something and said so. The fix must not make this case
# quieter, and must not bolt a second line onto a report that already carried its finding.
_rtc '#!/usr/bin/env bash
echo "runtime-check: ✗ STALE COPIES vs /ref: kbcard" >&2
exit 1'
_rtc_loud="$(snap complete)"
eq "control: a real STALE finding still reaches stdout"      "true"  \
   "$(has 'STALE COPIES vs /ref: kbcard' "$_rtc_loud")"
eq "  …and is NOT softened into 'did not complete'"          "false" "$(has "$_RTC_NEEDLE" "$_rtc_loud")"
eq "  …and STILL never blocks SessionStart"                  "0"     "$SNAP_RC"

# leave the silent stub in place for anything added after this block
_rtc '#!/usr/bin/env bash
exit 0'

# ---------------------------------------------------------------------------
_summary "board-snapshot-selftest"
