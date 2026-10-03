#!/usr/bin/env bash
# xtrace-token-selftest.sh — `bash -x <tool>` must never print the board bearer token (card#11204).
#
# WHAT HAPPENED. A diagnostic agent ran `bash -x kbcard …` to see why a `list` was slow, and the
# trace printed a live board token into its transcript, which then had to be rotated (rt#592).
# xtrace prints every simple command with its words EXPANDED: the token-file read, the
# `kb_auth_header "$KB_TOKEN"` that builds the header, and the token argument of every
# fetch_board_cards / kb_mask_token call all went to stderr with the value in them. The
# herestring feeding curl was worse than visible: under kb_api's `2>&1` the trace of the
# `$(kb_auth_header …)` it expanded landed INSIDE the captured response, so a traced kbcard also
# misread every answer (`show` exited 1, `comment` 3).
#
# THE FIX this file holds is the lib's kb_xtrace_off / kb_xtrace_restore pair (its header owns the
# rule): every line that expands the token suspends xtrace on that same line, and the caller's own
# trace state comes back afterwards.
#
# THE LEGS, each answering a question the others cannot:
#   § 1–2  BEHAVIOUR. The real bins, as processes, under `bash -x`, against the stub API, with a
#          planted token whose bytes are asserted ABSENT from everything the run printed. Each
#          run carries two controls, without which the absence proves nothing: the stub RECEIVED
#          that token as the bearer (so it was read and sent, not skipped), and the trace is
#          still ON after the token was handled (so nothing simply turned tracing off).
#   § 3    THE HELPER'S SEMANTICS, in-process: re-entrancy, and that a caller's `set -x` is on
#          again when a token-handling lib call returns — and stays off for a caller without it.
#   § 4    THE CALL-SITE RULE, statically, over every shipped shell file (CI's own population,
#          `_shipped_shell_files`). § 1–2 can only see the verbs they run; this sees every line.
#   § 5    KBCARD_DEBUG=1, the per-request view offered instead of `-x`: present, and token-free.
#
# WHAT A GREEN RUN DOES NOT COVER — read before citing it:
#   * § 4's predicate is the expansion `$KB_TOKEN` / `${KB_TOKEN…}` and a CALL of
#     fetch_board_cards, kb_mask_token or kb_auth_header. A token held under ANOTHER name (a
#     `token` / `tok` local, a header variable) and expanded in a traced line is invisible to it;
#     only § 1–2's runs can catch that, and only on the paths they drive.
#   * A server that ECHOES the request's Authorization header into its response body (a debug
#     error page, measured once — card#9301) puts the token into the traced response variables.
#     That is a body the server sent back, not an expansion of the token, and nothing here
#     suppresses it; the stub never echoes.
#   * The standalone bins that cannot source the lib — promote-released-cards, card-completeness —
#     suspend xtrace by hand. Their `bash -x` legs live in their own selftests
#     (promote-refusal-detail-selftest.sh, card-completeness-selftest.sh), not here.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"

LIB="$ROOT/bin/_kb-board-lib.sh"
KBC="$ROOT/bin/kbcard"
SNAP="$ROOT/bin/board-snapshot"
_need -r "$LIB"
_need -x "$KBC"
_need -x "$SNAP"

_mktmp_scratch --home
kb_stub_scrub_env
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48' 'export KB_STAGE_IN_PROGRESS=84'
kb_stub_install

# Low-entropy and self-describing, so no secret scanner mistakes the fixture for a credential and
# no reader mistakes a hit for anything but this token.
TOK='FAKE-BOARD-TOKEN-NOT-SECRET-000'
printf '%s\n' "$TOK" > "$KB_STUB_TOKEN_FILE"

kb_stub_route() {
    case "$1 $2" in
        "POST "*/tasks/505/comments.json)
            printf '201\n{"data":{"id":13,"task_id":505,"content":"hi"}}' ;;
        "GET "*/tasks/search.json*)
            printf '200\n{"data":[{"id":505,"name":"probe","workflow_stage_id":84,"tags":[]}],"meta":{"total":1,"last_page":1}}' ;;
        "GET "*/preload.json*)
            printf '200\n{"data":{"workflows":[{"stages":[{"id":84,"name":"In Progress"}]}]}}' ;;
        "GET "*/tasks/505.json*)
            printf '200\n{"data":{"id":505,"name":"probe","workflow_stage_id":48,"comments":[{"id":13,"task_id":505,"user_id":1,"content":"hi","deleted_at":null,"created_at":"t","updated_at":"t"}]}}' ;;
    esac
}
export -f kb_stub_route

# _resumed <stderr-file> — `true` when the trace has a line AFTER its last suspension: xtrace came
# back on once the token was handled. `false` when no suspension is in the trace at all, so a run
# that never reached a token line cannot pass this as "resumed".
_resumed() {
    awk '/^\++ kb_xtrace_off/ { last = NR } /^\++ / { if (last && NR > last) after = 1 }
         END { print (last && after) ? "true" : "false" }' "$1"
}

# _traced_leg <label> <bin> <args…> — run <bin> twice, plain and under `bash -x`, and assert the
# token is nowhere in what the traced run printed, with the controls that make that absence
# mean something.
_traced_leg() {
    local label="$1" bin="$2"; shift 2
    local rc_plain=0 rc_x=0
    kb_stub_reset
    bash "$bin" "$@" >"$TMP/plain.out" 2>"$TMP/plain.err" || rc_plain=$?
    kb_stub_reset
    bash -x "$bin" "$@" >"$TMP/x.out" 2>"$TMP/x.err" || rc_x=$?
    eq "$label: the token is NOT in the traced run's stderr"   "false" "$(_contains "$TOK" "$TMP/x.err")"
    eq "$label: …nor in its stdout"                            "false" "$(_contains "$TOK" "$TMP/x.out")"
    # Every request carried exactly the planted token — the auth log's third field is the bearer.
    eq "$label: control — the stub RECEIVED that token as the bearer" "$TOK" \
        "$(cut -f3 "$KB_STUB_AUTH_LOG" | sort -u | tr -d '\n')"
    eq "$label: control — the run WAS traced"                  "true"  "$(grep -q '^+ ' "$TMP/x.err" && echo true || echo false)"
    eq "$label: control — tracing RESUMED after the token was handled" "true" "$(_resumed "$TMP/x.err")"
    eq "$label: the traced run answers as the plain one does"  "$rc_plain" "$rc_x"
    eq "$label: …and the plain one succeeded"                  "0"     "$rc_plain"
}

echo "== § 1. kbcard under bash -x: a read, a write, and a whole-board walk =="
# RED on the pre-fix lib: every verb printed the token (the file read alone traces it), and the
# `show`/`comment` rc rows red too, because the traced herestring corrupted the response.
_traced_leg "kbcard show"    "$KBC" --board dev show --task 505
_traced_leg "kbcard comment" "$KBC" --board dev comment --task 505 --content hi
eq "kbcard comment: control — the write was really sent" "1" "$(kb_stub_count POST /tasks/505/comments.json)"
_traced_leg "kbcard list"    "$KBC" --board dev list
eq "kbcard list: control — the walk really read the board" "true" \
    "$([[ "$(kb_stub_count GET /tasks/search.json)" -ge 1 ]] && echo true || echo false)"

echo "== § 2. another lib-sourcing bin: board-snapshot under bash -x =="
printf 'dev:D\n' > "$HOME/.kanban-snapshot-boards"
export KANBAN_SNAPSHOT_BOARDS="$HOME/.kanban-snapshot-boards"
# The staleness guard board-snapshot folds in depends on the HOST, not on this test.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/agent-board-toolkit-runtime-check"
chmod +x "$TMP/bin/agent-board-toolkit-runtime-check"
_traced_leg "board-snapshot" "$SNAP"
eq "board-snapshot: control — the card is in the snapshot" "true" "$(_contains '#505' "$TMP/x.out")"

echo "== § 3. the helper: re-entrant, and the caller's own trace state survives a lib call =="
# Run in a child bash so `set -x` here cannot leak into this file's own output.
# shellcheck disable=SC2016
h="$(bash -c '
    source "$1"
    KB_API="$2"; KB_TOKEN="$3"
    say() { printf "%s=%s\n" "$1" "$(case $- in *x*) echo on ;; *) echo off ;; esac)"; } 2>/dev/null
    set -x
    f() { local a b
          kb_xtrace_off a; say outer-off
          kb_xtrace_off b; say inner-off
          kb_xtrace_restore b; say inner-restored
          kb_xtrace_restore a; say outer-restored; }
    f
    kb_token_file_read t "$4"; say after-token-read
    kb_api GET /tasks/505.json >/dev/null; say after-kb_api
    out="$(kb_xtrace_off; fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"; say after-fetch
    set +x
    kb_token_file_read t "$4"; say untraced-after-token-read
    kb_xtrace_off c; kb_xtrace_restore c; say untraced-after-pair
' _ "$LIB" "$KB_STUB_API" "$TOK" "$KB_STUB_TOKEN_FILE" 2>"$TMP/h.err")"
eq "a pair turns tracing off"                                 "true" "$(has 'outer-off=off' "$h")"
eq "a NESTED pair's restore leaves it off (the outer one is still open)" "true" "$(has 'inner-restored=off' "$h")"
eq "the OUTERMOST restore turns it back on"                   "true" "$(has 'outer-restored=on' "$h")"
eq "the caller's set -x is on after kb_token_file_read"       "true" "$(has 'after-token-read=on' "$h")"
eq "…after kb_api"                                            "true" "$(has 'after-kb_api=on' "$h")"
eq "…after a fetch_board_cards call made the documented way"  "true" "$(has 'after-fetch=on' "$h")"
eq "a caller WITHOUT -x does not get it turned on by a token read" "true" "$(has 'untraced-after-token-read=off' "$h")"
eq "…nor by a pair"                                           "true" "$(has 'untraced-after-pair=off' "$h")"
eq "control: the in-process run printed no token"             "false" "$(_contains "$TOK" "$TMP/h.err")"
eq "control: …and its trace was live"                         "true"  "$(grep -q '^+ ' "$TMP/h.err" && echo true || echo false)"

echo "== § 4. the call-site rule, over every shipped shell file =="
# _xt_members <file…> — "<file>:<line>:<text>" for every non-comment line that expands
# $KB_TOKEN / ${KB_TOKEN…} or CALLS one of the three functions that take the token by value. A
# call is the name in command position — line start, or after `;` `&` `|` `(` `{` `$(`, or after
# `then`/`do`/`else` — followed by whitespace. A name in an argument list (`declare -F
# kb_mask_token`, a loop's word list, a message) is not a call, and neither is its definition
# (`kb_mask_token() {`): neither is a member.
_xt_members() {
    awk '
        /^[[:space:]]*#/ { next }
        {
            hit = ($0 ~ /\$\{?KB_TOKEN([^A-Za-z0-9_]|$)/)
            if (!hit && $0 ~ /(^|[;&|({]|\$\(|then|do|else)[[:space:]]*(fetch_board_cards|kb_mask_token|kb_auth_header)[[:space:]]/) hit = 1
            if (hit) printf "%s:%d:%s\n", FILENAME, FNR, $0
        }
    ' "$@"
}
# _xt_violations — the members whose line does not suspend xtrace.
_xt_violations() { grep -v 'kb_xtrace_off' || true; }

mapfile -t SHIPPED < <(_shipped_shell_files "$ROOT")
eq "the population of shipped shell files is non-empty" "true" "$([[ ${#SHIPPED[@]} -gt 0 ]] && echo true || echo false)"
members="$(cd "$ROOT" && _xt_members "${SHIPPED[@]}")"
echo "  denominator — every token-expanding line in the shipped shell (re-derived each run):"
printf '%s\n' "$members" | cut -d: -f1,2 | sed 's/^/    /'
eq "the rule has members to hold (an empty set would pass vacuously)" "true" "$([[ -n "$members" ]] && echo true || echo false)"
eq "every member suspends xtrace on its own line" "" "$(printf '%s\n' "$members" | _xt_violations)"

# CONTROLS on the predicate, each a planted line in a scratch file — the rule must see an
# unguarded call in each spelling, and must NOT count a name that is only mentioned.
cat > "$TMP/plant.sh" <<'PLANT'
cards="$(fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"
x=1; kb_mask_token out "$tok" "$body"
hdr="$(kb_auth_header "$t")"
tok_copy="$KB_TOKEN"
declare -F kb_mask_token >/dev/null
for f in kb_mask_token fetch_board_cards; do :; done
# fetch_board_cards "$KB_API" "$KB_TOKEN" in a comment
cards="$(kb_xtrace_off; fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"
kb_mask_token() {
PLANT
planted="$(_xt_members "$TMP/plant.sh")"
eq "control: an unguarded fetch_board_cards call is a member"  "true"  "$(has ':1:' "$planted")"
eq "control: an unguarded kb_mask_token after ';' is a member" "true"  "$(has ':2:' "$planted")"
eq "control: a kb_auth_header inside \$( is a member"          "true"  "$(has ':3:' "$planted")"
eq "control: a bare \$KB_TOKEN expansion is a member"          "true"  "$(has ':4:' "$planted")"
eq "control: declare -F naming it is NOT a member"             "false" "$(has ':5:' "$planted")"
eq "control: a loop word list naming it is NOT a member"       "false" "$(has ':6:' "$planted")"
eq "control: a comment naming it is NOT a member"              "false" "$(has ':7:' "$planted")"
eq "control: its own definition line is NOT a member"          "false" "$(has ':9:' "$planted")"
eq "control: the four unguarded members are the violations"    "4" \
    "$(printf '%s\n' "$planted" | _xt_violations | grep -c . || true)"
eq "control: the guarded spelling is a member"                 "true"  "$(has ':8:' "$planted")"
eq "control: …and NOT a violation"                             "false" "$(has ':8:' "$(printf '%s\n' "$planted" | _xt_violations)")"

echo "== § 5. KBCARD_DEBUG=1: the request a trace would show, without the token =="
# The alternative this card offers to reaching for `-x`: one stderr line per request. RED when the
# line is missing, carries the bearer, or prints when the knob is unset.
kb_stub_reset
rc=0; KBCARD_DEBUG=1 bash "$KBC" --board dev show --task 505 >/dev/null 2>"$TMP/dbg.err" || rc=$?
eq "debug: the verb still succeeds"                       "0"     "$rc"
eq "debug: the request is named with its method, url and status" "true" \
    "$(grep -qE '^kbcard: debug: GET https://kanban\.test/api/v3/tasks/505\.json -> HTTP 200 \([0-9]+ ms\)$' "$TMP/dbg.err" && echo true || echo false)"
eq "debug: …and the token is not in it"                   "false" "$(_contains "$TOK" "$TMP/dbg.err")"
kb_stub_reset
KBCARD_DEBUG=1 bash "$KBC" --board dev list >/dev/null 2>"$TMP/dbg-list.err" || true
eq "debug: control — the walk read at least one page"     "true" \
    "$([[ "$(kb_stub_count GET /tasks/search.json)" -ge 1 ]] && echo true || echo false)"
eq "debug: a whole-board walk prints one line per page it read" \
    "$(kb_stub_count GET /tasks/search.json)" "$(grep -c 'debug: GET .*/tasks/search\.json' "$TMP/dbg-list.err" || true)"
kb_stub_reset
bash "$KBC" --board dev show --task 505 >/dev/null 2>"$TMP/nodbg.err" || true
eq "control: without the knob there is no debug line"     "false" "$(_contains 'debug:' "$TMP/nodbg.err")"

_summary "xtrace-token-selftest"
