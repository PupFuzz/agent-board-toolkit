#!/usr/bin/env bash
# kbcard-field-selftest.sh — deterministic, network-free unit checks for the
# `kbcard field` verb family: `field list` (schema read + option projection) and
# `field set-options` (the idempotent converge-to-set reconcile) from card #4939,
# plus the definition lifecycle — `field create` / `field delete` / `field retype`
# — from card#6525.
#
# Sources the bin (main-guarded) and exercises the pure sub-verb functions with a
# STUBBED kb_api — no network. What it guards:
#   - list projects id/key/label/type + the enum/multi_select {value,label} option
#     set (label defaults to value; a non-option-bearing type reports options null);
#   - set-options DRIFT writes a value-only options PATCH in the given order, and an
#     IDENTICAL set is a NO-OP (no PATCH) — the idempotency contract; reverting the
#     drift compare reds these two mutually (always-write reds the no-op case,
#     never-write reds the drift case);
#   - --field resolves by numeric id OR key, and an unresolved --field enumerates the
#     board's defined fields (rc 2), mirroring the unresolved-swimlane pattern;
#   - set-options refuses a non-enum/multi_select field, and empty / duplicate /
#     missing --options (a converge-to-set target must be a real set);
#   - a failing PATCH propagates non-zero AND its error body reaches stderr (the
#     lost-error-body defect class #4337 must not reappear on this path);
#   - `cmd_field`'s sub-verb dispatch, the one Preserve item of the flag-axis
#     consolidation: a MISSING sub-verb is pinned by its own message, because the
#     `*)` catch-all answers the same rc 2 and an rc-only check therefore stays
#     green with the guard deleted (measured).
#
# THE LIFECYCLE SECTION (card#6525) runs against a STATEFUL board fake — a mutable
# field index and card set in $TMP — rather than a per-call stub, because what those
# verbs must be judged on is an END STATE, not a call. Its DELETE arm deliberately
# does not cascade into the card payloads: that IS measured server behaviour (A), the
# reason `delete` is fail-closed, and a fake that cascaded it would let that refusal be
# deleted with every assertion still green.
#
# `retype` OWNS NO SEQUENCE: it is one call on the server's atomic conversion route, so
# there is no delete, no recreate, no per-card cast and no stranded-board state to
# report. The conversion route is MODELLED here rather than canned — the option rules,
# the pair matrix, the compare-and-swap, the no-op short-circuit and the offender scan
# are transcribed from CustomFieldMutator — so a client-side re-derivation creeping back
# in reds against the SERVER's rule and not against a fixture written to match the
# client. Only the outcomes a fake board cannot produce are canned bodies (the two 413
# rails, a concurrent 404, a transport 000, a server-capped offender list), and the
# archived/soft-deleted carriers the conversion also converts are DECLARED, since a fake
# board cannot hold a card its own fetch never returns. What it guards:
#   - create ECHOES the created field id (the write verification), sends the server's
#     [{value}] option shape, and refuses a duplicate key at rc 2 with ZERO POSTs —
#     the rc alone does not carry that guard, since the server's own 422 also fails;
#   - the census denominator states what it can SEE, at BOTH consumers of the one census
#     primitive rather than at whichever verb the fix was written for: the read is live +
#     non-archived while the routes its count is read against are not, so the scope rides
#     the denominator LINE (asserted as such, not as a substring of stderr at large) and
#     the delete gate is asserted UNCHANGED either side of it, with the gate moved both
#     ways as the control that those rc assertions can fail at all;
#   - the re-run a run prescribes when it could not read its own outcome is asserted on
#     BOTH branches of --options and at BOTH arms that print one (the 000 transport
#     failure and the unreadable 2xx echo), which do NOT say the same thing: with options
#     the identical command is refused as an options edit once the conversion has landed,
#     which is driven end to end — a landed --options conversion, then the same command
#     again — rather than asserted off a fixture, and the arm that refuses it is asserted
#     to enumerate no client-side copy of the server's option rules (the copy that omitted
#     this very rule). The 2xx arm KNOWS it landed (the server does not answer 2xx for a
#     refusal) and names one directive, asserted as an absence of the other's shape; the
#     000 arm cannot, so it prescribes the 'field list' READ first and branches on it —
#     one assertion per branch, the read pinned as the FIRST thing the sentence says, and
#     a second type pair as the control that the branches name THIS request's types;
#   - delete ALWAYS prints the `N of M board cards carry <key>` denominator, refuses a
#     populated field at rc 2 naming both consequences, warns loudly under
#     --orphan-values, and refuses at rc 1 on EVERY incomplete-read rc
#     fetch_board_cards defines (1/2/3/4) — carried by a positive control that deletes
#     at rc 0 off the SAME board and the SAME zero numerator with a complete read;
#   - retype's REQUEST and its reading of the answer: from_type always sent, --options
#     passed through untouched, the ref-impact handshake's two calls with the second
#     acknowledging exactly what the first reported, and every status reported as the
#     different board it is — including the two a green suite once let claim safety it
#     could not observe (a 000 transport failure, whose write may already have
#     committed, and a 413 whose rail the client used to name for the server);
#   - create's REFUSED POST, and the delete's two UNVERIFIED boards (a 2xx that removed
#     nothing vs a 2xx whose confirming re-read failed) — three arms whose fake knobs
#     existed with no leg assigning them, so they could never fire. The verb collapses
#     the delete's two to one rc, so the MESSAGE is what tells them apart here;
#   - the --restamp-dl pass's outcomes, each asserted on the resulting board rather than
#     on a call: a PATCH that 200s and silently does not land separates "migrated" from
#     "looks migrated", a verification read that observed nothing is not a wrong value,
#     and the conversion's population is LARGER than this census (it includes archived
#     and soft-deleted carriers). The remainder compare PROVES a remainder and can never
#     rule one out — the no-op re-run scans nothing, and live-side growth cancels the
#     count difference one for one — so every line that could read as "done" is asserted
#     to carry its census scope, on the no-op path and the proven-clean path alike;
#   - a message that names an OPTIONAL flag's pass is asserted on BOTH branches of that
#     flag, never only the one that passed it: the unreadable-2xx-echo arm's re-run
#     sentence is asserted to name the --restamp-dl pass WITH the flag and to name no
#     pass at all without it — a run that skipped none cannot say a re-run runs one, and
#     a leg taken only with the flag set is what let that claim ship;
#   - the option rules the client still owns vs the server's own, told apart in the
#     SUITE and not only in a comment: retype's --options passthrough has exactly one
#     exception (a duplicate value, refused at rc 2 by kbcard, which the server would
#     accept), and the refusal is asserted to say whose rule it is — while the empty-value
#     refusal beside it is asserted NOT to, because that one is the server's;
#   - --options between two option types DESTROYS the definition's explicit labels (the
#     server replaces the whole options column), which the run now names, with controls
#     for the three shapes that must stay silent.
#
# The mutation battery behind these assertions — how many mutations, which assertions
# each redded, and the ones no mutation could red (named, never counted as covered) —
# is recorded in docs/CHANGELOG.md under card#6525 and is deliberately NOT restated
# here: this header carried the previous cut's figure long after that cut's sequence was
# deleted, and a second copy of one number is exactly what let it go stale.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/kbcard"
_need -r "$BIN"
# ⛔ --home, AND BEFORE THE SOURCE — both halves are load-bearing (card#7245). bin/kbcard
# resolves `KB_LOG_FILE="${KBCARD_LOG_FILE:-$HOME/.kbcard-failures.log}"` at SOURCE time, so a
# scratch HOME established afterwards is too late: the path is already baked from the real one.
# Without this, running this file appended its fabricated HTTP-422/413/500 bodies to the
# operator's live ~/.kbcard-failures.log — measured, 20 records / 8746 bytes per run — which is
# a triage surface, so the suite was manufacturing evidence in it. The property is that the
# suite writes NOTHING outside its scratch, and a scratch HOME buys that for every $HOME-derived
# path in the bin at once, rather than one override per path as they are noticed.
_mktmp_scratch --home
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines the field fns without running main()

# The verb reads KB_BOARD_ID; kb_api is stubbed so KB_API/KB_TOKEN are never used.
export KB_BOARD_ID=1

# Board field fixture: an enum (with labels), a string (no options), a multi_select
# (value-only options). The GET stub returns this whole board index.
_GET_FIELDS='{"data":[
  {"id":10,"board_id":1,"key":"severity","label":"Severity","type":"enum","options":[{"value":"low","label":"Low"},{"value":"high","label":"High"}]},
  {"id":11,"board_id":1,"key":"note","label":"Note","type":"string","options":null},
  {"id":12,"board_id":1,"key":"labels","label":"Labels","type":"multi_select","options":[{"value":"a"},{"value":"b"}]}
]}'
_PATCH_FILE="$TMP/patch-body.json"

# Default stub: GET returns the fixture; PATCH records its body to a file (a $()-
# subshell side effect on a global can't survive, so use a file) and echoes back a
# {data:…} envelope with the sent options applied.
# THE INDEX REFLECTS THE LAST PATCH, because `set-options` now confirms its converge by
# re-reading the BOARD rather than by reading the PATCH's own echo (card#8556). A stub that
# answered the pre-write index on that second read would red every converge below for the
# FIXTURE's reason instead of the tool's — and, worse, could never exercise the confirming
# read in the agreeing direction. `_SO_STALE` is the disagreeing direction: a PATCH that
# answered 2xx over a board that did not move.
kb_api() {
    case "$1 $2" in
        "GET /boards/"*)
            if [[ -z "${_SO_STALE:-}" && -f "$_PATCH_FILE" ]]; then
                jq -c --argjson o "$(jq -c '.options' "$_PATCH_FILE")" \
                    '(.data[] | select(.id == 10) | .options) |= $o' <<<"$_GET_FIELDS"
            else
                printf '%s' "$_GET_FIELDS"
            fi ;;
        "PATCH /custom_fields/"*)
            printf '%s' "$3" > "$_PATCH_FILE"
            jq -nc --argjson body "$3" \
                '{data:{id:10,board_id:1,key:"severity",label:"Severity",type:"enum",options:$body.options}}' ;;
        *) printf '{"data":null}' ;;
    esac
}

# ---------------------------------------------------------------------------
echo "== field list — schema read + option projection =="
LST="$(_kbc_field_list)"
eq "list projects all three fields"              "3"    "$(jq 'length' <<<"$LST")"
eq "enum field surfaces its 2 options"           "2"    "$(jq '.[] | select(.key=="severity") | .options | length' <<<"$LST")"
eq "enum option keeps its explicit label"        '"Low"' "$(jq -c '.[] | select(.key=="severity") | .options[0].label' <<<"$LST")"
eq "string field options are null (not [])"      "null" "$(jq -c '.[] | select(.key=="note") | .options' <<<"$LST")"
eq "multi_select value-only option labels default to value" '"a"' \
   "$(jq -c '.[] | select(.key=="labels") | .options[0].label' <<<"$LST")"

rc=0; _kbc_field_list extra >/dev/null 2>&1 || rc=$?
eq "field list rejects stray args → rc 2"        "2"    "$rc"

# ---------------------------------------------------------------------------
echo "== field set-options — drift writes a value-only PATCH in order =="
rm -f "$_PATCH_FILE"
_kbc_field_set_options --field severity --options low,high,critical >/dev/null 2>&1
eq "drift wrote a PATCH"                          "true" "$( [[ -f "$_PATCH_FILE" ]] && echo true || echo false )"
eq "PATCH sends the values in the given order"    '["low","high","critical"]' "$(jq -c '.options | map(.value)' "$_PATCH_FILE")"
eq "PATCH options are value-only (no label key)"  "false" "$(jq -c '.options[0] | has("label")' "$_PATCH_FILE")"

rm -f "$_PATCH_FILE"
_kbc_field_set_options --field 10 --options low,high,critical >/dev/null 2>&1
eq "--field resolves by numeric id too"           '["low","high","critical"]' "$(jq -c '.options | map(.value)' "$_PATCH_FILE")"

rm -f "$_PATCH_FILE"
_kbc_field_set_options --field severity --options ' low , high , critical ' >/dev/null 2>&1
eq "outer whitespace trimmed per value"           '["low","high","critical"]' "$(jq -c '.options | map(.value)' "$_PATCH_FILE")"

# ---------------------------------------------------------------------------
echo "== field set-options — idempotent no-op on an identical set =="
rm -f "$_PATCH_FILE"
rc=0; OUT="$(_kbc_field_set_options --field severity --options low,high 2>/dev/null)" || rc=$?
eq "identical set exits 0"                        "0"     "$rc"
eq "identical set writes NO PATCH (idempotent)"   "false" "$( [[ -f "$_PATCH_FILE" ]] && echo true || echo false )"
eq "no-op still echoes the field on stdout"       '"severity"' "$(jq -c '.key' <<<"$OUT")"
ERR="$(_kbc_field_set_options --field severity --options low,high 2>&1 >/dev/null || true)"
eq "no-op says 'already match' on stderr"         "true"  "$(has 'already match' "$ERR")"

# ---------------------------------------------------------------------------
echo "== field set-options — resolution + type + input guards =="
rc=0; ERR="$(_kbc_field_set_options --field nope --options x 2>&1 >/dev/null)" || rc=$?
eq "unresolved --field → rc 2"                    "2"    "$rc"
eq "unresolved --field enumerates defined fields" "true" "$(has 'defined fields' "$ERR")"
eq "enumeration includes a real field key"        "true" "$(has 'severity' "$ERR")"

rc=0; ERR="$(_kbc_field_set_options --field note --options x,y 2>&1 >/dev/null)" || rc=$?
eq "set-options on a string field → rc 2"         "2"    "$rc"
eq "string-field refusal names the type"          "true" "$(has "type 'string'" "$ERR")"

rc=0; _kbc_field_set_options --field severity --options 'low,,high' >/dev/null 2>&1 || rc=$?
eq "empty value in --options → rc 2"              "2"    "$rc"
rc=0; _kbc_field_set_options --field severity --options 'low,low' >/dev/null 2>&1 || rc=$?
eq "duplicate value in --options → rc 2"          "2"    "$rc"
rc=0; _kbc_field_set_options --field severity >/dev/null 2>&1 || rc=$?
eq "missing --options → rc 2"                     "2"    "$rc"
rc=0; _kbc_field_set_options --options a,b >/dev/null 2>&1 || rc=$?
eq "missing --field → rc 2"                       "2"    "$rc"
rc=0; _kbc_field_set_options --field severity --bogus v >/dev/null 2>&1 || rc=$?
eq "unknown arg → rc 2"                           "2"    "$rc"

# ---------------------------------------------------------------------------
echo "== field verb dispatch =="
rc=0; cmd_field >/dev/null 2>&1 || rc=$?
eq "field with no sub-verb → rc 2"                "2"    "$rc"
# The rc above cannot tell the two arms apart, so it is NOT what pins the missing-sub-verb
# guard: measured with that guard deleted, an absent sub-verb falls through to the `*)`
# catch-all, which answers rc 2 as well — the whole suite stays green while `bin/kbcard field`
# driven as a PROCESS goes from a named rc 2 to a silent rc 1 (the arm's own `shift` failing on
# an exhausted stack under `set -e`). The MESSAGE is the only channel that separates them.
eq "field with no sub-verb names the missing sub-verb" \
   "kbcard: field requires a sub-verb: list | create | delete | retype | set-options" "$(cmd_field 2>&1)"
rc=0; cmd_field bogus >/dev/null 2>&1 || rc=$?
eq "field with unknown sub-verb → rc 2"           "2"    "$rc"

# ---------------------------------------------------------------------------
echo "== field set-options — a failing PATCH preserves the error body (not #4337) =="
# Re-stub kb_api's PATCH to emulate the real lib's non-2xx path: print the HTTP
# line + JSON error body to stderr and return non-zero. The verb must propagate the
# failure AND let the body through (it must not `2>/dev/null` the write).
kb_api() {
    case "$1 $2" in
        "GET /boards/"*) printf '%s' "$_GET_FIELDS" ;;
        "PATCH /custom_fields/"*)
            echo "kbcard: HTTP 422 on PATCH $2" >&2
            echo '{"message":"The given data was invalid.","errors":{"options":["The options field is required when type is enum."]}}' >&2
            return 1 ;;
    esac
}
rc=0; ERR="$(_kbc_field_set_options --field severity --options low,high,critical 2>&1 >/dev/null)" || rc=$?
eq "failing PATCH propagates non-zero"            "1"    "$rc"
eq "error body reaches stderr (not swallowed)"    "true" "$(has 'given data was invalid' "$ERR")"

# ---------------------------------------------------------------------------
echo "== field lifecycle (create / delete / retype) — a STATEFUL board fake =="
# The lifecycle verbs are not independently checkable against a per-call stub: what
# `delete` refuses and what `retype --restamp-dl` leaves behind are properties of the
# END STATE (a board that READS migrated while every value still carries the old JSON
# type and the search index is purged is invisible in any single call). So the fake
# below holds real mutable state — the board's field index in $_FIELDS, its cards in
# $_BOARD — and every assertion below reads that state back, never the stub's own echo.
#
# The DELETE arm deliberately does NOT touch $_BOARD: that IS measured caveat (A), the
# server behaviour `delete`'s fail-closed refusal exists for. If this fake cascaded the
# delete into the payloads, that refusal could be deleted with the suite still green.
export KB_API="https://api.example/v3"
export KB_TOKEN="tok"
_FIELDS="$TMP/fields.json"
_BOARD="$TMP/board.json"
_CALLS="$TMP/calls.log"
_POST_BODY="$TMP/post-body.json"
_FETCH_RC=0
_POST_FAIL=""
_POST_NOID=""      # the POST 2xxs but its body carries no id (the unverified write)
_PATCH_FAIL=""     # space-separated task ids whose PATCH returns non-2xx
_PATCH_NOOP=""     # ids whose PATCH 200s but silently does NOT land the write
_DELETE_NOOP=""    # the DELETE 2xxs but the definition is STILL there on the re-read
_FIELDS_FAIL_AFTER_DELETE=""   # the field-index GET fails once the DELETE has landed
_FIELDS_UNREADABLE=""          # the field-index GET 2xxs with a body nothing reads out of
_POST_UNREADABLE=""            # the create POST 2xxs with a body nothing reads out of
_GET_TASK_UNREADABLE=""        # ids whose verification GET 2xxs with such a body
_GET_TASK_FAIL=""  # ids whose task-detail GET (the verification read) fails
_DELETED="$TMP/deleted.marker"
# --- change-type knobs (the conversion route) ------------------------------
# The fake below MODELS the conversion rather than replaying canned bodies, because
# what `retype` must be judged on is that it stopped holding opinions the server
# holds: the option rules, the pair matrix, the CAS and the offender scan are all
# re-implemented here from the server's own source, so a client-side re-derivation
# creeping back in reds against the SERVER's wording, not against a fixture. The
# three knobs below are for the outcomes a fake board genuinely cannot produce.
_CT_FORCE_HTTP=""      # answer every change-type call with this status …
_CT_FORCE_BODY=""      # … and this body (the 413 rails, a 404 race, a capped list)
_CT_UNREADABLE=""      # the conversion 2xxs with a body nothing can be read out of
_CT_REFIMPACT=""       # task ids whose external-reference correlation the conversion MOVES
_CT_REFIMPACT_SHIFT="" # the acknowledged set no longer matches (it moved under the lock)
_CT_REFIMPACT_GONE=""  # the ref impact DISAPPEARED under the row lock: the ack is refused
                       # against a scan that derived NONE, so the refusal carries
                       # offender_count 0 with an EMPTY offenders list (the server's
                       # `$expected === []` branch) — a real body, not a degenerate one
_CT_REFIMPACT_CAP=""   # name only this many offenders in the ref-impact refusal, while
                       # ref_impact_task_ids stays WHOLE: MAX_REPORTED_OFFENDERS caps the
                       # first key and not the second, which is the asymmetry the
                       # --accept-ref-impact path has to disclose
_CT_TYPE_MOVED=""      # a concurrent conversion committed between the read and this write
_CT_DEFINITION_STUCK="" # the conversion answers 2xx and the DEFINITION does not move — the
                        # board a run that reported off the write's own echo could not see
_POST_NOT_INDEXED=""   # the create POST echoes an id and the board does not define the key
_FIELDS_FAIL_ON_READ="" # fail the Nth `GET /boards/…/custom_fields.json` of this run, so a
                        # CONFIRMING re-read can fail while the resolve read before it does not
# Carriers the conversion converted that NO board read this client makes returns —
# archived and soft-deleted cards. The server's candidateQuery is
# `withTrashed()->where(board_id)->whereNotNull(payload->key)` with no archive filter,
# while the census reads /tasks/search.json, which excludes both. A fake board cannot
# hold a card its own fetch does not return, so the difference is declared here: it
# shows up exactly where the real one does, in meta.converted_task_count.
#
# ⚠ IT IS DELIBERATELY NOT CONSULTED ON THE NO-OP ARM, because the server does not
# consult its own scan there either: CustomFieldTypeChangeResult::noop() hardcodes
# convertedTaskCount 0 and typeGates returns it BEFORE any scan runs. A fake that let
# this knob leak into that arm would be inventing a number the server cannot send, and
# every assertion built on it would measure the fixture. The way a no-op meets an
# out-of-census carrier is the way it does in production — the TWO-RUN sequence: a real
# conversion first, then the re-run.
_CT_UNSEEN_CARRIERS=0
# Cards that appear in the LIVE set between the conversion and the census that follows
# it — an ordinary concurrent create, not a fixture convenience. It is a JSON array of
# cards appended to $_BOARD after the conversion has computed its count, which is
# exactly when the real ones appear, and it is what makes the count compare's blind
# spot expressible: converted_task_count is a measurement of ONE moment and the census
# of a LATER one, so live-side growth masks an archived carrier one for one.
_CT_LIVE_GROWTH=""

# _seed <fields-json> <board-json>: fresh board state + a fresh call log.
_seed() {
    : > "$_CALLS"; : > "$_POST_BODY"
    rm -f "$_DELETED" "$TMP"/task-patch-*.json "$TMP"/ct-body-*.json
    _FETCH_RC=0; _POST_FAIL=""; _POST_NOID=""; _PATCH_FAIL=""; _PATCH_NOOP=""
    _DELETE_NOOP=""; _FIELDS_FAIL_AFTER_DELETE=""; _GET_TASK_FAIL=""; _FIELDS_UNREADABLE=""
    _POST_UNREADABLE=""; _GET_TASK_UNREADABLE=""
    _CT_FORCE_HTTP=""; _CT_FORCE_BODY=""; _CT_UNREADABLE=""; _CT_REFIMPACT=""
    _CT_REFIMPACT_SHIFT=""; _CT_TYPE_MOVED=""; _CT_REFIMPACT_GONE=""
    _CT_REFIMPACT_CAP=""; _CT_UNSEEN_CARRIERS=0; _CT_LIVE_GROWTH=""
    _CT_DEFINITION_STUCK=""; _POST_NOT_INDEXED=""; _FIELDS_FAIL_ON_READ=""
    printf '%s' "$1" > "$_FIELDS"
    printf '%s' "$2" > "$_BOARD"
}
# _calls <prefix>: how many logged calls start with it (0 when none).
_calls() { grep -c "^$1" "$_CALLS" 2>/dev/null || true; }

fetch_board_cards() {
    echo "FETCH $3" >> "$_CALLS"
    # Mirrors the real primitive on an INCOMPLETE read: partial data IS emitted and the
    # rc is what carries the incompleteness. A caller that reads only stdout sees a
    # perfectly well-formed (and short) board — which is the trap being guarded.
    cat "$_BOARD"
    return "$_FETCH_RC"
}

kb_api() {
    local method="$1" path="$2" body="${3:-}" id key nf
    echo "$method $path" >> "$_CALLS"
    case "$method $path" in
        "GET /boards/"*"/custom_fields.json")
            # The field index is read TWICE on a retype — once to resolve the
            # definition, once to confirm the delete. This arm can fail only on the
            # second, which is the board state the delete's rc has to distinguish.
            if [[ -n "$_FIELDS_FAIL_AFTER_DELETE" && -f "$_DELETED" ]]; then
                echo "kbcard: HTTP 503 on GET $path" >&2
                return 1
            fi
            # A 2xx nothing can be read out of — a proxy's HTML, a truncated read. kb_api
            # decides success on the status class, so this arrives at the projection as a
            # SUCCESS and only _kbc_fetch_fields' own empty-value guard refuses it.
            [[ -z "$_FIELDS_UNREADABLE" ]] || { printf '<html>502 Bad Gateway</html>'; return 0; }
            # Fail one NUMBERED read. `_FIELDS_UNREADABLE` fails every one, which for the
            # create and retype verbs is refused BEFORE the write (they resolve against this
            # same index), so it can never reach their confirming re-read. The call is already
            # logged above, so `_calls` counts THIS one.
            if [[ -n "$_FIELDS_FAIL_ON_READ" && "$(_calls 'GET /boards')" == "$_FIELDS_FAIL_ON_READ" ]]; then
                echo "kbcard: HTTP 503 on GET $path" >&2
                return 1
            fi
            jq -c '{data: .}' "$_FIELDS" ;;
        "POST /boards/"*"/custom_fields.json")
            printf '%s' "$body" > "$_POST_BODY"
            [[ -z "$_POST_FAIL" ]] || { echo "kbcard: HTTP 500 on POST $path" >&2; return 1; }
            [[ -z "$_POST_NOID" ]] || { printf '{"data":{}}'; return 0; }
            [[ -z "$_POST_UNREADABLE" ]] || { printf '<html>502 Bad Gateway</html>'; return 0; }
            key="$(jq -r '.key' <<<"$body")"
            if jq -e --arg k "$key" 'any(.[]; .key == $k)' "$_FIELDS" >/dev/null; then
                echo "kbcard: HTTP 422 on POST $path" >&2
                echo '{"message":"The given data was invalid.","errors":{"key":["The key has already been taken."]}}' >&2
                return 1
            fi
            nf="$(jq -c --argjson b "$body" \
                '(([.[].id] | max // 90) + 1) as $id
                 | {id: $id, board_id: 1, key: $b.key, label: $b.label, type: $b.type,
                    options: ($b.options // null)}' "$_FIELDS")"
            # _POST_NOT_INDEXED: the 201 echoes the whole definition, id first, and the board
            # does not define it. The id alone cannot see that — only the index can.
            [[ -n "$_POST_NOT_INDEXED" ]] || { jq -c --argjson f "$nf" '. + [$f]' "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"; }
            jq -nc --argjson f "$nf" '{data: $f}' ;;
        "DELETE /custom_fields/"*)
            id="${path#/custom_fields/}"; id="${id%.json}"
            : > "$_DELETED"
            # _DELETE_NOOP is a 2xx that did NOT remove the definition — the arm the
            # delete's own re-read exists to catch, and the one a recreate must never
            # be attempted after (a POST on a live key 422s on the duplicate).
            [[ -n "$_DELETE_NOOP" ]] || { jq -c --argjson id "$id" 'map(select(.id != $id))' "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"; }
            printf '' ;;   # the real route answers 204 with an EMPTY body
        "PATCH /tasks/"*)
            id="${path#/tasks/}"; id="${id%.json}"
            # Record the body PER TASK: the fake MERGES per-key, so a body that
            # clobbered the card's other payload keys would leave the merged board
            # looking identical. Only the body itself can witness the per-key write.
            printf '%s' "$body" > "$TMP/task-patch-$id.json"
            case " $_PATCH_FAIL " in *" $id "*) echo "kbcard: HTTP 500 on PATCH $path" >&2; return 1 ;; esac
            case " $_PATCH_NOOP " in *" $id "*) jq -nc '{data: {}}'; return 0 ;; esac
            jq -c --argjson id "$id" --argjson b "$body" \
               'map(if .id == $id then .payload = ((.payload // {}) + $b.payload) else . end)' \
               "$_BOARD" > "$TMP/b.tmp" && mv "$TMP/b.tmp" "$_BOARD"
            jq -nc '{data: {}}' ;;
        "GET /tasks/"*)
            id="${path#/tasks/}"; id="${id%.json}"
            case " $_GET_TASK_FAIL " in *" $id "*) echo "kbcard: HTTP 503 on GET $path" >&2; return 1 ;; esac
            case " $_GET_TASK_UNREADABLE " in *" $id "*) printf '<html>502 Bad Gateway</html>'; return 0 ;; esac
            jq -c --argjson id "$id" '{data: (map(select(.id == $id)) | .[0])}' "$_BOARD" ;;
        *) printf '{"data":null}' ;;
    esac
}


# The conversion route lives on kb_api_status (status + body, always rc 0), so it needs
# its own stub — and it is MODELLED, not canned: the option rules, the pair matrix, the
# compare-and-swap and the offender scan below are transcribed from the server's own
# CustomFieldMutator, so an assertion here fails against the SERVER's rule rather than
# against a fixture somebody wrote to match the client. That is the whole point of this
# rewrite: the client is supposed to have stopped re-deriving these.
kb_api_status() {
    local method="$1" path="$2" body="${3:-}" n id key from to opts ft ack ids carriers cap offenders
    echo "$method $path" >> "$_CALLS"
    case "$method $path" in
        "POST /custom_fields/"*"/change-type.json")
            # The call log IS the counter: a $()-subshell increment cannot survive back
            # to this shell, which is why every side effect in this file is a file.
            n="$(_calls 'POST /custom_fields')"
            printf '%s' "$body" > "$TMP/ct-body-$n.json"
            id="${path#/custom_fields/}"; id="${id%/change-type.json}"
            [[ -z "$_CT_FORCE_HTTP" ]] || { printf '%s\n%s' "$_CT_FORCE_HTTP" "$_CT_FORCE_BODY"; return 0; }
            # A concurrent conversion that committed between the caller's field read and
            # this write — the exact race from_type exists to catch.
            if [[ -n "$_CT_TYPE_MOVED" ]]; then
                jq -c --arg t "$_CT_TYPE_MOVED" 'map(.type = $t)' "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"
            fi
            key="$(jq -r --argjson id "$id" 'map(select(.id == $id)) | .[0].key' "$_FIELDS")"
            from="$(jq -r --argjson id "$id" 'map(select(.id == $id)) | .[0].type' "$_FIELDS")"
            to="$(jq -r '.type' <<<"$body")"
            opts="$(jq -c '.options // empty' <<<"$body")"

            # assertOptionsMatchTarget, verbatim in its three refusals.
            if [[ -n "$opts" && "$from" == "$to" ]]; then
                _ct_422 "$id" "$key" "$from" "$to" options \
                    "This request does not change the type, so it is an options edit — send it to PATCH /api/v3/custom_fields/{customField}.json."
                return 0
            fi
            if [[ -n "$opts" && "$to" != "enum" && "$to" != "multi_select" ]]; then
                _ct_422 "$id" "$key" "$from" "$to" options \
                    "Options are not accepted when converting to $to; the stored options column is left exactly as it is."
                return 0
            fi
            if [[ -z "$opts" && ( "$to" == "enum" || "$to" == "multi_select" ) \
                  && "$from" != "enum" && "$from" != "multi_select" ]]; then
                _ct_422 "$id" "$key" "$from" "$to" options \
                    "Options are required when converting to $to, and are never inherited from the stored column — create permits an uninterpreted options array on any type, so inheriting one would silently decide which values become offenders."
                return 0
            fi

            # The CAS, before the rails and before any scan.
            ft="$(jq -r '.from_type // empty' <<<"$body")"
            if [[ -n "$ft" && "$ft" != "$from" ]]; then
                printf '412\n%s' "$(jq -nc --arg a "$from" --arg e "$ft" \
                    '{message:"Custom field type has changed since you read it.", actual:$a, expected:$e}')"
                return 0
            fi

            # The no-op: same type, no scan, no write.
            if [[ "$from" == "$to" ]]; then
                _ct_200 "$id" "$from" "$to" 0
                return 0
            fi

            # P1: boolean is terminal in both directions — a PAIR refusal, decided
            # before a single task row is read, so it carries NO meta.offenders.
            if [[ "$to" == "boolean" || "$from" == "boolean" ]]; then
                printf '422\n%s' "$(jq -nc --argjson id "$id" --arg k "$key" --arg f "$from" --arg t "$to" \
                    '("Cannot convert a \($f) custom field to \($t): deciding which values mean true needs a truth table the server does not define. Edit the values, or create a new field.") as $m
                     | {message:$m, errors:{type:[$m]}, meta:{custom_field_id:$id, key:$k, from_type:$f, to_type:$t}}')"
                return 0
            fi

            # Phase 1's ref-impact step (step 4): the ids are declared by the knob, but
            # the RULE is the server's — refuse unless the caller enumerated exactly the
            # set this scan derived, and refuse again if that set moved.
            if [[ -n "$_CT_REFIMPACT" ]]; then
                ids="$(printf '%s' "$_CT_REFIMPACT" | jq -Rc 'split(" ") | map(tonumber)')"
                ack="$(jq -c '.acknowledge_ref_impact // empty' <<<"$body")"
                # MAX_REPORTED_OFFENDERS caps `offenders`; `ref_impact_task_ids` is
                # uncapped. Both refusals below build their offender list through this
                # one expression, so the cap cannot apply to one of them and not the
                # other — which is exactly the shape the client has to disclose.
                cap="${_CT_REFIMPACT_CAP:-$(jq 'length' <<<"$ids")}"
                offenders="$(jq -c --argjson n "$cap" \
                    'map({task_id:., value:"1", category:"ref_impact",
                          reason:"This conversion changes the card external-reference correlation.",
                          refs_before:["1|github_pr|acme/widgets|15"],
                          refs_after:["1|github_pr|acme/widgets|1"]}) | .[0:$n]' <<<"$ids")"
                if [[ -z "$ack" ]]; then
                    printf '422\n%s' "$(jq -nc --argjson id "$id" --arg k "$key" --arg f "$from" --arg t "$to" --argjson ids "$ids" --argjson off "$offenders" \
                        '("\($ids|length) card(s) would have their external-reference correlation moved by this conversion. Nothing was changed. To proceed, re-send with `acknowledge_ref_impact` listing exactly these card ids.") as $m
                         | {message:$m, errors:{type:[$m]},
                            meta:{custom_field_id:$id, key:$k, from_type:$f, to_type:$t,
                                  offender_count:($ids|length),
                                  offenders_truncated:(($off|length) < ($ids|length)),
                                  offenders:$off,
                                  ref_impact_task_ids:$ids}}')"
                    return 0
                fi
                # The ref impact VANISHED between the two calls: the scan under the lock
                # derives an EMPTY expected set, so the acknowledgement is refused with
                # the scan's own (empty) offender list and offender_count 0 — the
                # server's `$expected === []` branch, verbatim in its shape.
                if [[ -n "$_CT_REFIMPACT_GONE" ]]; then
                    printf '422\n%s' "$(jq -nc --argjson id "$id" --arg k "$key" --arg f "$from" --arg t "$to" --argjson ack "$ack" \
                        '("The acknowledged cards do not match the cards this conversion would affect — no card'"'"'s correlation would move. Re-run the preview and confirm the set it reports.") as $m
                         | {message:$m, errors:{acknowledge_ref_impact:[$m]},
                            meta:{custom_field_id:$id, key:$k, from_type:$f, to_type:$t,
                                  offender_count:0, offenders_truncated:false, offenders:[],
                                  acknowledged:$ack, ref_impact_task_ids:[]}}')"
                    return 0
                fi
                # The set MOVED. The server hands this refusal the SAME scan offenders
                # and the SAME count as any other — `assertOffendersClearOrAcknowledged`
                # passes `$scan['offenders']` / `$scan['offender_count']` through on every
                # throw — so a fixture answering `offender_count:0, offenders:[]` here
                # encodes a body the server does not send, and every assertion built on it
                # measures the fixture rather than the client.
                if [[ -n "$_CT_REFIMPACT_SHIFT" || "$ack" != "$ids" ]]; then
                    printf '422\n%s' "$(jq -nc --argjson id "$id" --arg k "$key" --arg f "$from" --arg t "$to" --argjson ids "$ids" --argjson ack "$ack" --argjson off "$offenders" \
                        '("The acknowledged cards no longer match the cards whose correlation this conversion would move — the set grew or changed since the preview. Nothing was changed. Re-run the preview and confirm the set it reports.") as $m
                         | {message:$m, errors:{acknowledge_ref_impact:[$m]},
                            meta:{custom_field_id:$id, key:$k, from_type:$f, to_type:$t,
                                  offender_count:($ids|length),
                                  offenders_truncated:(($off|length) < ($ids|length)),
                                  offenders:$off,
                                  acknowledged:$ack, ref_impact_task_ids:$ids}}')"
                    return 0
                fi
            fi

            # Phase 1's cast-acceptance step (step 3), for the one target these fixtures
            # exercise: a `number` target refuses a value that is not canonical numeric
            # text. Every offender is named at once — the refusal IS the preflight.
            if [[ "$to" == "number" ]]; then
                local bad
                bad="$(jq -c --arg k "$key" '[ .[] | select((.payload // {}) | has($k))
                        | select((.payload[$k] | tostring | test("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$")) | not)
                        | {task_id: .id, value: (.payload[$k] | tostring),
                           category: "target_rejects", reason: "Must be a number."} ]' "$_BOARD")"
                if [[ "$(jq 'length' <<<"$bad")" -gt 0 ]]; then
                    printf '422\n%s' "$(jq -nc --argjson id "$id" --arg k "$key" --arg f "$from" --arg t "$to" --argjson off "$bad" \
                        '("\($off|length) card values block this conversion. Nothing was changed.") as $m
                         | {message:$m, errors:{type:[$m]},
                            meta:{custom_field_id:$id, key:$k, from_type:$f, to_type:$t,
                                  offender_count:($off|length), offenders_truncated:false, offenders:$off}}')"
                    return 0
                fi
            fi

            [[ -z "$_CT_UNREADABLE" ]] || { printf '200\n<html>502 Bad Gateway</html>'; return 0; }

            # ---- phase 2: the definition AND every carrier, in one step ------------
            carriers="$(jq --arg k "$key" '[ .[] | select((.payload // {}) | has($k)) ] | length' "$_BOARD")"
            jq -c --arg k "$key" --arg t "$to" '
                map(if ((.payload // {}) | has($k)) then
                        .payload[$k] = (.payload[$k] as $v
                            | if $t == "multi_select" then (if ($v|type) == "array" then $v else [($v|tostring)] end)
                              elif ($v|type) == "array" then (if ($v|length) == 1 then $v[0] else $v end)
                              elif $t == "number" then (if ($v|type) == "number" then $v else ($v|tonumber) end)
                              else ($v|tostring) end)
                    else . end)' "$_BOARD" > "$TMP/b.tmp" && mv "$TMP/b.tmp" "$_BOARD"
            # _CT_DEFINITION_STUCK leaves the definition where it was while the call still
            # answers 200 with a converted-looking echo — the board a run reporting off that
            # echo describes and never reads.
            [[ -n "$_CT_DEFINITION_STUCK" ]] || { jq -c --argjson id "$id" --arg t "$to" --argjson o "${opts:-null}" \
                'map(if .id == $id then .type = $t | (if $o == null then . else .options = $o end) else . end)' \
                "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"; }
            # The conversion's count is fixed HERE, at the moment the transaction commits.
            # Anything the knob below adds to the live set lands after it, which is what
            # makes the client's later census a read of a different moment.
            n="$(( carriers + _CT_UNSEEN_CARRIERS ))"
            [[ -z "$_CT_LIVE_GROWTH" ]] || { jq -c --argjson g "$_CT_LIVE_GROWTH" '. + $g' "$_BOARD" > "$TMP/b.tmp" && mv "$TMP/b.tmp" "$_BOARD"; }
            # meta.converted_task_count is the SERVER's population, not this board read's:
            # the archived and soft-deleted carriers it also converted are declared by the
            # knob, since a fake board cannot hold a card its own fetch never returns.
            _ct_200 "$id" "$from" "$to" "$n" ;;
        *) printf '000\nkb_api_status: the stub was called on an unmodelled route: %s %s' "$method" "$path" ;;
    esac
}
# _ct_200 <field-id> <from> <to> <converted>: the CustomFieldResource + its meta.
_ct_200() {
    printf '200\n%s' "$(jq -c --argjson id "$1" --arg f "$2" --arg t "$3" --argjson n "$4" \
        'map(select(.id == $id)) | .[0] | {data: ., meta: {from_type: $f, to_type: $t, converted_task_count: $n}}' "$_FIELDS")"
}
# _ct_422 <field-id> <key> <from> <to> <error-key> <message>: the option-rule refusal.
# MEASURED on the sandbox instance: `assertOptionsMatchTarget` throws a PLAIN Laravel
# ValidationException, which renders `{message, errors}` and **no `meta` key at all** —
# unlike the two refusals CustomFieldTypeConversionException renders, which both carry
# meta. So there are THREE 422 shapes, not two, and the field ids handed in here are
# deliberately unused: a fixture that invented a meta the server does not send is what
# let the client report this refusal as something it is not.
# shellcheck disable=SC2317  # positional 1-4 are kept for call-site symmetry with the meta-carrying arms
_ct_422() {
    printf '422\n%s' "$(jq -nc --arg ek "$5" --arg m "$6" '{message:$m, errors:{($ek):[$m]}}')"
}

_F_DL_STR='[{"id":91,"board_id":1,"key":"dl_number","label":"DL Number","type":"string","options":null}]'
_F_DL_NUM='[{"id":91,"board_id":1,"key":"dl_number","label":"DL Number","type":"number","options":null}]'
# Card 8 carries NO dl_number: it is the denominator's other half. Without it every
# "N of M" assertion would read the same with the numerator computed as the board size.
# Card 7 carries dl_number AND a sibling key: the per-key write contract is only
# observable on a card that is BOTH restamped and carrying something else to lose.
_B_MIXED='[{"id":7,"payload":{"dl_number":1,"other":5}},{"id":8,"payload":{"other":5}},{"id":9,"payload":{"dl_number":42}}]'
# The enum/multi_select fixtures. `severity` carries EXPLICIT labels that differ from
# their values — the only shape in which a label the client never sends is observable:
# omitting --options between enum and multi_select must carry them over verbatim, and a
# client that flattened the option set to values would destroy them behind a 2xx.
_F_SEV_ENUM='[{"id":20,"board_id":1,"key":"severity","label":"Severity","type":"enum","options":[{"value":"low","label":"Low"},{"value":"high","label":"High"}]}]'
_B_SEV='[{"id":7,"payload":{"severity":"low"}},{"id":9,"payload":{"severity":"high"}}]'
# A string field whose server-returned options are an EMPTY ARRAY — a non-empty
# STRING, which is what makes a string-emptiness test on it answer wrongly.
_F_NOTE_EMPTYOPTS='[{"id":93,"board_id":1,"key":"note","label":"Note","type":"string","options":[]}]'
# A label holding an apostrophe and option values holding spaces: the shapes that
# break a printed remediation command that is not shell-quoted.
_F_ODD='[{"id":30,"board_id":1,"key":"weird","label":"Owner'"'"'s team","type":"enum","options":[{"value":"in progress"},{"value":"done"}]}]'
# An option value holding a COMMA — which `--options` (a comma list) cannot express
# at all, so no printed create command can be correct for it.
_F_COMMA='[{"id":31,"board_id":1,"key":"csvish","label":"CSV","type":"enum","options":[{"value":"a,b"},{"value":"c"}]}]'

echo "-- create --"
_seed "$_F_DL_STR" '[]'
rc=0; OUT="$(_kbc_field_create --key severity --label Severity --type enum --options low,high 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "create → rc 0"                                   "0"    "$rc"
eq "create ECHOES the created field id on stdout"    "92"   "$OUT"
eq "…which is the write verification, named as such" "true" "$(has "(id 92)" "$ERR")"
eq "…the POST carries key/label/type"                '["severity","Severity","enum"]' \
   "$(jq -c '[.key,.label,.type]' "$_POST_BODY")"
eq "…and options as the server's [{value}] objects"  '[{"value":"low"},{"value":"high"}]' \
   "$(jq -c '.options' "$_POST_BODY")"
eq "…and the field is really on the board now"       "2"    "$(jq 'length' "$_FIELDS")"

# A 2xx that echoes no id leaves the write UNVERIFIED — never printed as a plausible id.
_seed "$_F_DL_STR" '[]'
_POST_NOID=1
rc=0; ERR="$(_kbc_field_create --key severity --label S --type string 2>&1 >/dev/null)" || rc=$?
eq "create whose 2xx carries no id → rc 3"           "3"    "$rc"
eq "…and says the write is UNVERIFIED"               "true" "$(has 'UNVERIFIED WRITE' "$ERR")"
# The verb PROPAGATES the primitive's rc rather than collapsing it: rc 3 there is a write
# that went out and could not be confirmed, and reporting it as rc 1 would be a claim about
# a board nobody read.
eq "…and no confirming index read was even attempted" "1" "$(_calls 'GET /boards')"

# A 2xx NOTHING CAN BE READ OUT OF, at the two response reads these verbs own. THE
# ADOPTION of the shared tolerant parse (kb_parse_resp, card#6426) is what these two legs
# pin, not the arm it lands in: with a bare `jq` at either site the whole suite stayed
# GREEN — measured, both sites, one at a time — because every other fixture answers
# well-formed JSON, so nothing exercised the parse at all. A bare jq here exits 5 under
# `set -e` with jq's own parse error, and the verb's arm is never reached.
_seed "$_F_DL_STR" '[]'
_POST_UNREADABLE=1
rc=0; OUT="$(_kbc_field_create --key severity --label S --type string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "create on a 2xx nothing reads out of → rc 3, not jq's 5"  "3"     "$rc"
eq "…the SAME UNVERIFIED-write arm an id-less 2xx takes"      "true"  "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…leaks no raw jq parse error"                             "false" "$(has 'parse error' "$ERR")"
eq "…and prints no id on stdout"                              ""      "$OUT"

# An existing key is refused BEFORE the POST — a key is unique per board, so "create
# over the top" is not a re-type (`field retype` is). rc-only would stay green
# with the guard deleted (the server's own 422 also fails the call), so the assertions
# that carry the guard are the ZERO POSTs and the rc 2 vs the server path's rc 1.
_seed "$_F_DL_STR" '[]'
rc=0; ERR="$(_kbc_field_create --key dl_number --label X --type string 2>&1 >/dev/null)" || rc=$?
eq "create on an EXISTING key → rc 2"                "2"    "$rc"
eq "…issues NO POST at all"                          "0"    "$(_calls POST)"
eq "…and names field retype as the re-type verb"     "true" "$(has "field retype --field dl_number" "$ERR")"

_seed "$_F_DL_STR" '[]'
rc=0; ERR="$(_kbc_field_create --key sev --label S --type enum 2>&1 >/dev/null)" || rc=$?
eq "create enum with no --options → rc 2"            "2"    "$rc"
eq "…issues no POST"                                 "0"    "$(_calls POST)"
_seed "$_F_DL_STR" '[]'
rc=0; ERR="$(_kbc_field_create --key note --label N --type string --options a,b 2>&1 >/dev/null)" || rc=$?
eq "create --options on a scalar type → rc 2"        "2"    "$rc"
eq "…names the silent no-effect, not just 'invalid'" "true" "$(has 'never interprets it' "$ERR")"
rc=0; _kbc_field_create --key n --label N --type bogus >/dev/null 2>&1 || rc=$?
eq "create with an unknown --type → rc 2"            "2"    "$rc"

# The POST itself refused. The knob for this arm existed in the fake and no leg ever set
# it, so the arm could never fire — a fixture that is scaffolding, not coverage.
_seed "$_F_DL_STR" '[]'
_POST_FAIL=1
rc=0; OUT="$(_kbc_field_create --key severity --label S --type string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "create whose POST is REFUSED → rc 1"             "1"    "$rc"
eq "…the server's own error line is what is read"    "true" "$(has 'HTTP 500 on POST' "$ERR")"
eq "…no created-field line is printed"               "false" "$(has 'created on board' "$ERR")"
eq "…nothing is echoed on stdout"                    ""     "$OUT"
eq "…and the board still has one field"              "1"    "$(jq 'length' "$_FIELDS")"

echo "-- delete — fail-closed on a populated field --"
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
eq "delete on a POPULATED field → rc 2"              "2"    "$rc"
eq "…prints the denominator (N of M), always"        "true" "$(has '2 of 3 board cards carry dl_number' "$ERR")"
eq "…names caveat A: values survive, unrevalidated"  "true" "$(has 'never revalidated' "$ERR")"
eq "…names caveat B: the search index is PURGED"     "true" "$(has 'PURGES the search index' "$ERR")"
eq "…points at field retype"                         "true" "$(has "field retype --field dl_number" "$ERR")"
eq "…and issues NO DELETE"                           "0"    "$(_calls DELETE)"
eq "…leaving the definition in place"                "1"    "$(jq 'length' "$_FIELDS")"

_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_delete --field dl_number --orphan-values 2>&1 >/dev/null)" || rc=$?
eq "delete --orphan-values → rc 0"                   "0"    "$rc"
eq "…still prints the denominator"                   "true" "$(has '2 of 3 board cards carry dl_number' "$ERR")"
eq "…warns that N values are now ORPHANED"           "true" "$(has 'ORPHANS 2 card value' "$ERR")"
eq "…and that the index for the key is purged"       "true" "$(has 'PURGES the search index' "$ERR")"
eq "…the definition is gone"                         "0"    "$(jq 'length' "$_FIELDS")"
eq "…while the card values SURVIVE (caveat A)"       "1"    "$(jq -c '.[0].payload.dl_number' "$_BOARD")"

# An unpopulated field deletes without an opt-in — and STILL prints its denominator,
# so "0 of M" is a measurement that ran, not a silence.
_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
eq "delete on an UNPOPULATED field → rc 0"           "0"    "$rc"
eq "…prints 0 of M rather than nothing"              "true" "$(has '0 of 1 board cards carry dl_number' "$ERR")"
eq "…and no orphan warning is printed"               "false" "$(has 'ORPHANS' "$ERR")"

# THE DELETE'S TWO UNVERIFIED BOARDS. _kbc_field_delete_call answers 3 and 4 for two
# genuinely different boards, and both were live production behaviour with no leg at all
# — their fake arms were reachable only by a knob nothing assigned. The verb collapses
# both to rc 1 (a delete that did not verify is one outcome at ITS boundary), so the rc
# cannot be what tells them apart here: the MESSAGE is, which is exactly what the
# operator reads, and asserting the rc alone would leave the two arms swappable.
_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
_DELETE_NOOP=1
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
eq "a DELETE that 2xx'd and removed nothing → rc 1"  "1"    "$rc"
eq "…the DELETE was really issued"                   "1"    "$(_calls DELETE)"
eq "…and the field really is still defined"          "1"    "$(jq 'length' "$_FIELDS")"
eq "…named as STILL DEFINED after a successful DELETE" "true" \
   "$(has 'is STILL defined on board' "$ERR")"
eq "…never as landed-but-unconfirmed (the other board)" "false" "$(has 'treat it as LANDED' "$ERR")"
eq "…and no success line is printed"                 "false" "$(has 'deleted from board' "$ERR")"

_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
_FIELDS_FAIL_AFTER_DELETE=1
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
# THE TWO BOARDS NO LONGER SHARE AN rc (card#8556). This one is a 2xx whose confirming
# re-read failed — the definition is gone as far as anything can tell — which is the
# UNVERIFIED outcome and NOT "the delete did not happen". Its sibling above (a 2xx that
# removed nothing) is KNOWN and stays rc 1. The message still tells them apart; the rc
# now does too, which is what a caller that must not act on an unconfirmed write reads.
eq "a DELETE whose CONFIRMING re-read fails → rc 3"  "3"    "$rc"
eq "…the DELETE was really issued"                   "1"    "$(_calls DELETE)"
eq "…and it really landed (the definition is gone)"  "0"    "$(jq 'length' "$_FIELDS")"
# The load-bearing half: a 2xx is the server saying it acted, so this board must be
# treated as LANDED-unverified. Reporting it as "nothing happened" describes a board that
# does not exist and hides the one state that still needs finishing.
eq "…is reported as UNVERIFIED but LANDED"           "true" "$(has 'treat it as LANDED' "$ERR")"
eq "…never as the field still being defined"         "false" "$(has 'is STILL defined on board' "$ERR")"
eq "…and no success line is printed"                 "false" "$(has 'deleted from board' "$ERR")"

echo "-- an unreadable field index refuses ONCE, in the READ's own words --"
# card#6426 ruled this shape at `set-options`: _kbc_fetch_fields speaks on BOTH of its
# failing paths (kb_api's error body on a non-2xx, its own refusal on a 2xx nothing can
# be read out of), so a second line at the call site names no cause the first did not.
# All three lifecycle verbs read the same index, so all three are bound by that ruling.
# The rc-only assertion cannot carry it: rc 1 is what the doubled version returned too.
for _verb in create delete retype; do
    _seed "$_F_DL_STR" "$_B_MIXED"
    _FIELDS_UNREADABLE=1
    rc=0
    case "$_verb" in
        create) ERR="$(_kbc_field_create --key k2 --label L --type string 2>&1 >/dev/null)" || rc=$? ;;
        delete) ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$? ;;
        retype) ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$? ;;
    esac
    eq "field $_verb on an unreadable field index → rc 1"    "1"    "$rc"
    eq "…in the READ's words ($_verb)"                       "true" \
       "$(has 'no custom-field set could be read out of its body' "$ERR")"
    eq "…exactly ONE kbcard: line, not two ($_verb)"         "1"    "$(grep -c '^kbcard:' <<<"$ERR")"
    eq "…and NO write is issued ($_verb)"                    "0"    "$(($(_calls POST) + $(_calls DELETE) + $(_calls PATCH)))"
done

echo "-- the census denominator states what it can SEE, at BOTH its consumers --"
# The census is GET /tasks/search.json, which applies the default SoftDeletes scope AND
# whereNull(archived_at); the routes its counts are read against are wider than that in
# both directions — candidateQuery is withTrashed() with no archive filter, and
# purgeField is board_id + field_key with no filter of either kind. So a zero numerator
# is what this tool can SEE and never "the key is unused", and a board whose only
# carriers are archived reaches delete's rc-0 path with nothing to warn about.
# THE GATE IS NOT TOUCHED — rc 0 here, exactly as before; what changed is the disclosure.
_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
eq "delete on a zero census → rc 0, the gate unchanged" "0"  "$rc"
eq "control: …and the DELETE really was issued"      "1"     "$(_calls DELETE)"
# Pinned to the DENOMINATOR LINE, not to stderr at large: that is what makes both
# consumers inherit it, and it is what the two previous fixes of this shape missed by
# hoisting a note and then wiring it to one consumer.
eq "…the scope rides the denominator line itself"    "true"  \
   "$(has '0 of 1 board cards carry dl_number — ⚠ SCOPE:' "$ERR")"
eq "…naming what that census reads"                  "true"  \
   "$(has 'census reads LIVE, NON-ARCHIVED cards only' "$ERR")"
eq "…and which carriers are in neither of its numbers" "true" \
   "$(has "an archived or trashed card carrying 'dl_number' is in neither the numerator nor the denominator" "$ERR")"
eq "…so a zero is not read as the key being unused"  "true"  \
   "$(has 'A zero numerator is therefore not evidence that the key is unused' "$ERR")"

# The populated REFUSAL carries it too — that refusal is gated on this same count, so
# "2 of 3" is a floor and the operator reading it is entitled to know which cards it omits.
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
eq "the populated refusal is unchanged → rc 2"       "2"     "$rc"
eq "…and its denominator carries the same scope"     "true"  \
   "$(has '2 of 3 board cards carry dl_number — ⚠ SCOPE:' "$ERR")"

# THE OTHER CONSUMER OF THE SAME PRIMITIVE, asserted here rather than assumed from the
# hoist: --restamp-dl's census is the same call, so its denominator line carries the same
# scope. (Its own per-outcome scope note is a different claim — the compare against the
# conversion's count — and is asserted on its own lines further down.)
_seed "$_F_DL_NUM" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "the restamp pass's census says the same → rc 0"  "0"     "$rc"
eq "…on its own denominator line"                    "true"  \
   "$(has '2 of 3 board cards carry dl_number — ⚠ SCOPE:' "$ERR")"

echo "-- delete — a truncated board read is not a denominator --"
# The dangerous shape is a truncated read whose VISIBLE cards carry nothing: it looks
# exactly like a safe delete. Every incomplete rc fetch_board_cards defines must refuse.
for _rc in 1 2 3 4; do
    _seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
    _FETCH_RC="$_rc"
    rc=0; ERR="$(_kbc_field_delete --field dl_number 2>&1 >/dev/null)" || rc=$?
    eq "delete on an incomplete board read (rc $_rc) → rc 1"  "1"    "$rc"
    eq "…says the denominator is truncated (rc $_rc)"         "true" "$(has 'truncated denominator' "$ERR")"
    eq "…and issues NO DELETE (rc $_rc)"                      "0"    "$(_calls DELETE)"
done
# Positive control: the SAME board and the SAME zero numerator DO delete at rc 0 — so
# the four refusals above are carried by the fetch rc and nothing else.
_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
rc=0; _kbc_field_delete --field dl_number >/dev/null 2>&1 || rc=$?
eq "control: complete read, same zero numerator → rc 0"       "0"    "$rc"
eq "control: …and the DELETE IS issued"                       "1"    "$(_calls DELETE)"

echo "-- retype — ONE atomic call on the server's conversion route --"
# The whole client-side sequence (capture → DELETE → recreate → restamp → verify) is
# GONE, and its absence is what the four call-count assertions below pin: a re-grown
# delete-and-recreate would still convert the fake's board and still report success,
# so only the calls it makes can witness which design is running.
_seed "$_F_DL_NUM" "$_B_MIXED"
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype number -> string → rc 0"                   "0"    "$rc"
eq "…issues exactly ONE change-type POST"             "1"    "$(_calls 'POST /custom_fields')"
eq "…and NO DELETE — nothing is deleted any more"     "0"    "$(_calls DELETE)"
eq "…no create POST either"                           "0"    "$(_calls 'POST /boards')"
eq "…and no per-card PATCH: the server converted them" "0"   "$(_calls PATCH)"
eq "…nor any board read (there is no client census)"  "0"    "$(_calls FETCH)"
eq "…the body carries the target type"                '"string"' "$(jq -c '.type' "$TMP/ct-body-1.json")"
eq "…and ALWAYS from_type — the CAS is free here"     '"number"' "$(jq -c '.from_type' "$TMP/ct-body-1.json")"
eq "…with no options key (none was asked for)"        "false" "$(jq -c 'has("options")' "$TMP/ct-body-1.json")"
eq "…and nothing acknowledged"                        "false" "$(jq -c 'has("acknowledge_ref_impact")' "$TMP/ct-body-1.json")"
eq "…the definition IS the target type"               '"string"' "$(jq -c '.[0].type' "$_FIELDS")"
eq "…key and label survive the conversion"            '["dl_number","DL Number"]' "$(jq -c '[.[0].key,.[0].label]' "$_FIELDS")"
eq "…card 7's value is converted, as a JSON string"   '"1"'  "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "…and its sibling payload key is untouched"        "5"    "$(jq -c '.[0].payload.other' "$_BOARD")"
eq "…the success line reports the SERVER's count"     "true" "$(has 'converted 2 card value(s) in the SAME transaction' "$ERR")"
eq "…and stdout echoes the converted field row"       '"string"' "$(jq -c '.type' <<<"$OUT")"

echo "-- retype — the same-type no-op is the SERVER's, not a client short-circuit --"
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype to the CURRENT type → rc 0"                "0"    "$rc"
# The call is the point: a client-side "already that type" arm would answer rc 0 with
# an identical message and no request — and would then be WRONG the moment --options
# rides along, which the server answers as an options edit sent to the wrong route.
eq "…still makes the call"                            "1"    "$(_calls 'POST /custom_fields')"
eq "…reports that the server converted nothing"       "true" "$(has 'the server converted nothing (no scan, no write)' "$ERR")"
eq "…never claims a conversion happened"              "false" "$(has 'in the SAME transaction' "$ERR")"
eq "…echoes the field row on stdout"                  '"dl_number"' "$(jq -c '.key' <<<"$OUT")"
eq "…and writes no card"                              "0"    "$(_calls PATCH)"

echo "-- retype — --options is a PASSTHROUGH; every option rule is the server's --"
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "enum -> multi_select with --options → rc 0"       "0"    "$rc"
eq "…the CSV reaches the wire as the server's [{value}] objects" '[{"value":"low"},{"value":"high"}]' \
   "$(jq -c '.options' "$TMP/ct-body-1.json")"
eq "…and the definition carries them"                 '[{"value":"low"},{"value":"high"}]' "$(jq -c '.[0].options' "$_FIELDS")"
# THE END STATE ABOVE IS LOSSY, and asserting it without asserting the disclosure is
# what pinned it: `severity` carried the labels Low/High, the server REPLACES the whole
# options column ($locked->options = $options), and a comma list carries no labels — so
# both are gone behind a 2xx. The deleted finish-command printer used to warn about
# exactly this; nothing in the thin-call path did.
eq "…and the run says the labels were DESTROYED"      "true" \
   "$(has "the label(s) 'severity' carried are GONE: low=Low, high=High" "$ERR")"
eq "…naming the way to keep them"                     "true" "$(has 'OMITTING --options carries the existing set over verbatim' "$ERR")"
# It costs no extra request: the definition read that resolves --field already carried
# the labels, so the disclosure rides a read the verb makes either way.
# The DISCLOSURE still costs no request of its own — it is projected off the definition the
# --field resolution already read. The count is 2 rather than 1 because the verb now makes a
# CONFIRMING re-read of its own after the conversion (card#8556); neither read belongs to the
# label warning, which is what this leg pins. RED if the disclosure grows a read: 3.
eq "…off the resolve read, adding no read of its own (2 = resolve + confirm)" "2" \
   "$(_calls 'GET /boards')"

# The same conversion with no labels to lose says nothing — a warning that fires on
# every --options is noise, and would not distinguish the state it exists to report.
_seed '[{"id":20,"board_id":1,"key":"severity","label":"Severity","type":"enum","options":[{"value":"low"},{"value":"high"}]}]' "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "control: no explicit labels → rc 0"               "0"     "$rc"
eq "control: …and NO label-loss warning"              "false" "$(has 'are GONE' "$ERR")"

# A label EQUAL to its value is not a label the operator loses — the server writes
# label=value for an omitted label, so the end state is identical.
_seed '[{"id":20,"board_id":1,"key":"severity","label":"Severity","type":"enum","options":[{"value":"low","label":"low"},{"value":"high","label":"high"}]}]' "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "control: label == value → no warning"             "false" "$(has 'are GONE' "$ERR")"

# A SCALAR target never reaches the warning: the server refuses --options there, and the
# options column is left exactly as it is, so nothing is destroyed to report.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to string --options a,b 2>&1 >/dev/null)" || rc=$?
eq "control: a scalar target warns about no loss"     "false" "$(has 'are GONE' "$ERR")"
eq "control: …and the labels really are still there"  '"Low"' "$(jq -c '.[0].options[0].label' "$_FIELDS")"

# THE CONTROL THAT PINS *WHEN* IT IS SAID, not just whether. The same option→option
# request with the same --options and the same labels at stake, REFUSED: nothing was
# written, the labels are still on the definition, and a run claiming they are GONE
# would be describing a board that does not exist. A pre-flight warning cannot tell
# this apart from the leg above — which is why the disclosure is emitted after the 2xx.
_seed "$_F_SEV_ENUM" "$_B_SEV"
_CT_FORCE_HTTP=413
_CT_FORCE_BODY='{"message":"This board has 9000 cards, over the 5000-card scan rail for a type change."}'
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "control: a REFUSED option→option retype → rc 1"   "1"     "$rc"
eq "control: …claims no label was destroyed"          "false" "$(has 'are GONE' "$ERR")"
eq "control: …because none was — they are still there" '"Low"' "$(jq -c '.[0].options[0].label' "$_FIELDS")"

_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; _kbc_field_retype --field severity --to multi_select >/dev/null 2>&1 || rc=$?
eq "enum -> multi_select WITHOUT --options → rc 0 (server carries them over)" "0" "$rc"
eq "…and the client sends no options key at all"      "false" "$(jq -c 'has("options")' "$TMP/ct-body-1.json")"
eq "…the labels the definition carried are still there" '"Low"' "$(jq -c '.[0].options[0].label' "$_FIELDS")"

# THE TWO REFUSALS THE CLIENT USED TO OWN. Both were client-side guards (a
# takes-options gate and a []-blind emptiness test); both are now the server's, and
# the assertion that carries the change is that the request REACHES THE WIRE and the
# caller reads the SERVER's wording. An rc-only check cannot: the old refusals were
# rc 2 and these are rc 1, but a re-grown client guard would simply move the rc back.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to string --options a,b 2>&1 >/dev/null)" || rc=$?
eq "a SCALAR target carrying --options → rc 1"        "1"    "$rc"
eq "…the request WAS made (no client re-derivation)"  "1"    "$(_calls 'POST /custom_fields')"
eq "…and the server's own message is what is read"    "true" \
   "$(has 'Options are not accepted when converting to string' "$ERR")"
eq "…never the client's old 'silent no-effect' line"  "false" "$(has 'never interprets it' "$ERR")"
# The option rules throw a PLAIN ValidationException — `{message, errors}` with NO meta —
# so a client that discriminates on `meta.offenders` alone falls into its PAIR-refusal arm
# and tells the operator that string -> string carries no conversion, which is a wrong claim
# about the server AND sends them to fix the wrong thing. Measured live on the sandbox.
eq "…and is NOT mis-reported as a type-pair refusal"  "false" "$(has 'refused on the TYPE PAIR' "$ERR")"
eq "…it is named as a request the server rejected as invalid" "true" \
   "$(has 'REFUSED this request as invalid' "$ERR")"

# THE PASSTHROUGH CLAIM HAS EXACTLY ONE EXCEPTION, and this pins it as an exception
# rather than letting it read as a server rule. assertOptionsMatchTarget validates
# `options => array|min:1`, `options.*.value => required|string|max:128` and an optional
# label — and NO uniqueness — so a duplicate value would be accepted on the wire, and the
# rc 2 below is kbcard's own ruling carried over from `set-options`. Changing it would
# change what this verb ACCEPTS, which is not this suite's to decide; what IS asserted is
# that the refusal SAYS whose rule it is, so nobody is sent to argue with the server about
# a rule the server does not have.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,low 2>&1 >/dev/null)" || rc=$?
eq "a DUPLICATE --options value on retype → rc 2"     "2"    "$rc"
eq "…before any request"                              "0"    "$(_calls 'POST /custom_fields')"
eq "…and the refusal names it as kbcard's own rule"   "true" \
   "$(has "This is kbcard's own rule, not the server's" "$ERR")"
eq "…naming what the API actually validates"          "true" \
   "$(has 'the API has no uniqueness rule on an option set' "$ERR")"
# The two refusals that are NOT exceptions, asserted alongside so the distinction is
# visible in the suite and not only in a comment: an empty value and an empty list are
# the server's own rules, so refusing them early refuses nothing the wire would take.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options 'low,,high' 2>&1 >/dev/null)" || rc=$?
eq "an EMPTY --options value on retype → rc 2"        "2"    "$rc"
eq "…before any request"                              "0"    "$(_calls 'POST /custom_fields')"
eq "…and it does NOT claim to be kbcard's own rule"   "false" \
   "$(has "kbcard's own rule" "$ERR")"
# The same rule, same owner, at the two verbs it was written for — a control that the
# refusal is shared rather than three copies.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_set_options --field severity --options low,low 2>&1 >/dev/null)" || rc=$?
eq "control: set-options refuses a duplicate → rc 2"  "2"    "$rc"
eq "control: …in the same shared wording"             "true" "$(has "This is kbcard's own rule" "$ERR")"
rc=0; ERR="$(_kbc_field_create --key sev2 --label Sev --type enum --options low,low 2>&1 >/dev/null)" || rc=$?
eq "control: create refuses a duplicate → rc 2"       "2"    "$rc"
eq "control: …in the same shared wording"             "true" "$(has "This is kbcard's own rule" "$ERR")"

_seed "$_F_NOTE_EMPTYOPTS" '[{"id":7,"payload":{"note":"x"}}]'
rc=0; ERR="$(_kbc_field_retype --field note --to enum 2>&1 >/dev/null)" || rc=$?
eq "an option target from a NON-option source, no --options → rc 1" "1" "$rc"
eq "…the request WAS made"                            "1"    "$(_calls 'POST /custom_fields')"
eq "…and the server says options are never inherited" "true" \
   "$(has 'never inherited from the stored column' "$ERR")"
eq "…never the client's old 'never invents them' line" "false" "$(has 'never invents them' "$ERR")"
eq "…and is NOT mis-reported as a type-pair refusal"  "false" "$(has 'refused on the TYPE PAIR' "$ERR")"
eq "…and the definition is untouched"                 '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

echo "-- retype — 412: the field's type moved under the run (the free CAS) --"
# from_type is what makes this observable at all: the fake converts the definition
# out from under the caller between its field read and this write, exactly as a
# racing conversion would. With from_type dropped from the body the same race is a
# SILENT conversion of a definition this run never saw.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_TYPE_MOVED="date"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "a type that moved under the run → rc 1"           "1"    "$rc"
eq "…reported as its OWN outcome"                     "true" "$(has 'CHANGED UNDER YOU' "$ERR")"
eq "…naming both sides of the compare-and-swap"       "true" \
   "$(has "the board says 'date' where this call was sent against 'number'" "$ERR")"
eq "…never as a card-value refusal"                   "false" "$(has 'block this conversion' "$ERR")"
eq "…and the definition is left as the racer set it"  '"date"' "$(jq -c '.[0].type' "$_FIELDS")"

echo "-- retype — 413: the board is over the server's scan rail --"
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_FORCE_HTTP=413
_CT_FORCE_BODY='{"message":"This board has 41000 cards, over the 20000-card scan rail for a type change (a resource rail, not a business limit - the scan holds row locks for its whole duration). Run it operator-supervised and uncapped: php artisan kanban:change-custom-field-type 91 --to=string --actor=<user id>."}'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "over the scan rail → rc 1"                        "1"    "$rc"
eq "…named as a RESOURCE rail, not a refusal of the conversion" "true" "$(has 'RESOURCE rail' "$ERR")"
# The escape hatch rides in the server's message, so the raw body has to reach the
# caller: paraphrasing the refusal would drop the only command that finishes the job.
eq "…and the artisan escape hatch reaches the caller" "true" \
   "$(has 'php artisan kanban:change-custom-field-type 91 --to=string' "$ERR")"
eq "…nothing was written"                             '"number"' "$(jq -c '.[0].type' "$_FIELDS")"
# THE CLIENT NAMES NO RAIL. There are two, and they measure different populations —
# this one is the board's card count, the next leg's is the cards holding a value for
# the field — so any client sentence naming one of them is a false claim on the other.
eq "…and the CLIENT attributes no particular rail"    "false" "$(has 'card-scan rail' "$ERR")"

# THE SECOND RAIL, which nothing covered: max_examined_carriers, counted over the cards
# CARRYING THE KEY, not over the board. A 6000-card board is nowhere near the 20000-card
# board rail and can still be refused here — which is exactly the run on which a client
# line saying "the board is over the card-scan rail" is a wrong statement about the board.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_FORCE_HTTP=413
_CT_FORCE_BODY='{"message":"This conversion examines more than the 5000 cards holding a value for this field allowed per request (a resource rail, not a business limit - one transaction holds the write locks for every card it examines, whether or not its value converts). Run it operator-supervised and uncapped: php artisan kanban:change-custom-field-type 91 --to=string --actor=<user id>."}'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "over the EXAMINED-CARRIERS rail → rc 1"           "1"    "$rc"
eq "…is framed as a RESOURCE rail too"                "true" "$(has 'RESOURCE rail' "$ERR")"
eq "…and is NOT reported as the board-scan rail"      "false" "$(has 'card-scan rail' "$ERR")"
# The client says the server's message names which rail; that has to be true of BOTH.
eq "…the server's message names WHICH rail"           "true" \
   "$(has 'cards holding a value for this field' "$ERR")"
eq "…the escape hatch still reaches the caller"       "true" \
   "$(has 'php artisan kanban:change-custom-field-type 91' "$ERR")"
eq "…and nothing was written"                         '"number"' "$(jq -c '.[0].type' "$_FIELDS")"

echo "-- retype — 404: the definition was deleted concurrently --"
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_FORCE_HTTP=404
_CT_FORCE_BODY='{"message":"Not Found"}'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "a concurrent DELETE → rc 1"                       "1"    "$rc"
eq "…says the field is GONE"                          "true" "$(has 'is GONE' "$ERR")"
eq "…and never reports it as a card-value refusal"    "false" "$(has 'block this conversion' "$ERR")"
# Implicit route-model binding answers 404 BEFORE changeType is entered, so the lock is
# not reached on that path — while the mutator's own re-read under the lock throws the
# same 404 from inside the transaction. The client cannot tell them apart and must not
# pick one: "nothing was written" is true either way, "caught under the row lock" is not.
eq "…and claims no mechanism it cannot observe"       "false" "$(has 'under the row lock' "$ERR")"

echo "-- retype — 000: the request never completed, so its outcome is UNKNOWN --"
# kb_api_status maps EVERY non-zero curl exit to 000 — a refused connection, a --max-time
# 28 and a reset mid-response alike — and the last two are states in which the server may
# already have COMMITTED. "Nothing was written" is therefore a claim about a request whose
# answer nobody read, told to an operator deciding whether to re-run.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_FORCE_HTTP=000
_CT_FORCE_BODY='curl: (28) Operation timed out after 30001 milliseconds with 0 bytes received'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "a transport failure → rc 1"                       "1"     "$rc"
eq "…claims UNCERTAINTY about the write"              "true"  "$(has 'CANNOT say whether it landed' "$ERR")"
eq "…and never claims the board is untouched"         "false" "$(has 'was written' "$ERR")"
eq "…names the idempotent re-run as the resolution"   "true"  "$(has 'Re-run this exact command' "$ERR")"
eq "…which is why a landed conversion is safe to re-send" "true" "$(has 'server-side no-op' "$ERR")"

echo "-- retype — the two 422s are told apart by meta.offenders --"
# A PAIR refusal: no conversion exists between these types at all (boolean needs a
# truth table the server does not define), decided before a single task row is read.
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to boolean 2>&1 >/dev/null)" || rc=$?
eq "a pair with no conversion → rc 1"                 "1"    "$rc"
eq "…is reported as a TYPE PAIR refusal"              "true" "$(has 'refused on the TYPE PAIR' "$ERR")"
eq "…stating no card is at fault"                     "true" "$(has 'nothing on the board is at fault' "$ERR")"
eq "…never as N cards blocking it"                    "false" "$(has 'block this conversion' "$ERR")"
eq "…and the server's own reason is surfaced"         "true" "$(has 'needs a truth table the server does not define' "$ERR")"

# An OFFENDER refusal: the pair exists, named cards block it, and the whole board was
# scanned to say so — which is why there is no separate check mode.
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"not-a-number"}},{"id":9,"payload":{"dl_number":"also bad"}},{"id":8,"payload":{"dl_number":"12"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "card values blocking the conversion → rc 1"       "1"    "$rc"
eq "…names EVERY offender, with category and reason"  "true" \
   "$(has 'card 7 [target_rejects] Must be a number. — value: not-a-number' "$ERR")"
eq "…including the second, in the SAME refusal"       "true" \
   "$(has 'card 9 [target_rejects] Must be a number. — value: also bad' "$ERR")"
eq "…and calls that refusal the preflight"            "true" "$(has 'refusal IS the preflight' "$ERR")"
eq "…nothing was written: the definition stands"      '"string"' "$(jq -c '.[0].type' "$_FIELDS")"
eq "…and the castable card is untouched too"          '"12"' "$(jq -c '.[2].payload.dl_number' "$_BOARD")"

# The server CAPS the list, so a truncated report must say so — otherwise "2 cards
# block this" reads as the whole population when it is a sample of 60.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_FORCE_HTTP=422
_CT_FORCE_BODY='{"message":"60 card values block this conversion. Nothing was changed.","errors":{"type":["60 card values block this conversion. Nothing was changed."]},"meta":{"custom_field_id":91,"key":"dl_number","from_type":"string","to_type":"number","offender_count":60,"offenders_truncated":true,"offenders":[{"task_id":42,"value":"x","category":"target_rejects","reason":"Must be a number."},{"task_id":43,"value":"y","category":"source_nonconformant","reason":"Must be a string."}]}}'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "a capped offender list → rc 1"                    "1"    "$rc"
eq "…says how many of how many are named"             "true" "$(has 'the server caps the list: 2 of 60 offender(s) are named above' "$ERR")"
eq "…and still reports the true count"                "true" "$(has '60 card value(s) block this conversion' "$ERR")"
# These offenders ARE fixable card values (no meta.ref_impact_task_ids on this body), so
# "fix the named ones and re-run" is advice that works — but only alongside the rule it
# used to contradict: the cap is a property of the refusal, so a bare re-run shows the
# same 2 again.
eq "…the advice is fix-then-re-run"                   "true" "$(has 'Fix the named ones and re-run: the next refusal names the next batch' "$ERR")"
eq "…qualified by what re-running alone does NOT do"  "true" "$(has 'so re-running unchanged does not widen it' "$ERR")"

# THE CLASS THIS NOTICE MOST OFTEN FIRES ON, and the one its old tail was false for. A
# ref-impact refusal has nothing to FIX — the offender is not a bad value, it is a
# correlation the operator either accepts or does not — and re-running names the same 50
# forever. Reaching the ref-impact branch also means every BLOCKING offender is one
# (assertOffendersClearOrAcknowledged throws the value refusal first whenever
# blocking > |ref_impact_ids|), so the branch is exact and not a guess.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
_CT_REFIMPACT_CAP=1
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "a CAPPED ref-impact refusal (no flag) → rc 1"     "1"    "$rc"
eq "…discloses the cap"                               "true" "$(has 'the server caps the list it names: 1 of 2 offender(s) are named above' "$ERR")"
eq "…never tells the operator to FIX them"            "false" "$(has 'Fix the named ones' "$ERR")"
eq "…says a ref-impact refusal is acknowledged, not repaired" "true" \
   "$(has 'nothing to FIX here' "$ERR")"
eq "…and points at the uncapped id set it prints"     "true" "$(has 'full uncapped card-id set is named below' "$ERR")"
# The claim above is only honest because that set really is printed, uncapped, below it.
eq "control: …which is both ids, not the capped one"  "true" "$(has 'would MOVE: 7, 9' "$ERR")"

# A 422 whose body is valid JSON but NOT an object. Every arm below the readability
# test indexes the body, so a shape test that only asks "is this JSON" hands a scalar
# to `has("meta")` and lands in an arm that CLAIMS things — "no card value was
# examined" — about a refusal it never read. The same assumption about body shape is
# what the live probe caught in the meta discriminator, so it is tested here rather
# than assumed away.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_FORCE_HTTP=422
_CT_FORCE_BODY='"just a string"'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "a 422 body that is JSON but not an object → rc 1"  "1"     "$rc"
eq "…claims nothing about which rule refused it"       "true"  "$(has 'no refusal could be read out of the body' "$ERR")"
eq "…and never claims no card value was examined"      "false" "$(has 'no card value was examined' "$ERR")"
eq "…leaks no raw jq parse error"                      "false" "$(has 'parse error' "$ERR")"

echo "-- retype — the ref-impact handshake is TWO calls, and the first is never skipped --"
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "a ref-impact refusal without the flag → rc 1"     "1"    "$rc"
eq "…exactly ONE call"                                "1"    "$(_calls 'POST /custom_fields')"
eq "…the ids the server derived are printed"          "true" "$(has 'would MOVE: 7, 9' "$ERR")"
eq "…the opt-in is NAMED, not performed"              "true" "$(has 're-run with --accept-ref-impact' "$ERR")"
eq "…and nothing was written"                         '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --accept-ref-impact 2>&1 >/dev/null)" || rc=$?
eq "--accept-ref-impact → rc 0"                       "0"    "$rc"
eq "…makes TWO calls: the flag never skips the preview" "2"  "$(_calls 'POST /custom_fields')"
# The load-bearing pair. The server re-derives the set under the row lock and refuses
# one that changed, so acknowledging a set this client GUESSED would either be refused
# or — if it happened to match — would launder the one gate that makes a correlation
# move deliberate. The first body must acknowledge nothing; the second must carry
# exactly what the FIRST call reported.
eq "…the FIRST body acknowledges nothing"             "false" "$(jq -c 'has("acknowledge_ref_impact")' "$TMP/ct-body-1.json")"
eq "…the SECOND carries exactly the ids that call reported" '[7,9]' \
   "$(jq -c '.acknowledge_ref_impact' "$TMP/ct-body-2.json")"
eq "…and still carries the same type + CAS"           '["number","string"]' \
   "$(jq -c '[.type,.from_type]' "$TMP/ct-body-2.json")"
eq "…the run names the cards whose correlation moved" "true" "$(has 'card 7: 1|github_pr' "$ERR")"
eq "…and the conversion landed"                       '"number"' "$(jq -c '.[0].type' "$_FIELDS")"
# Control for the truncation leg below: nothing was capped here, so nothing is disclosed.
eq "…with no truncation notice, since nothing was capped" "false" \
   "$(has 'moves being acknowledged are shown above' "$ERR")"

# meta.offenders is capped at MAX_REPORTED_OFFENDERS; meta.ref_impact_task_ids is NOT.
# This path prints from the capped key and acknowledges the uncapped one, and it never
# calls _kbc_field_change_type_report, so that arm's truncation notice cannot fire here:
# without one of its own the operator is shown 1 move and agrees to 2 — at scale, 50 and
# 200 — against the one property the flag claims for itself.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
_CT_REFIMPACT_CAP=1
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --accept-ref-impact 2>&1 >/dev/null)" || rc=$?
eq "a CAPPED ref-impact list under --accept-ref-impact → rc 0" "0" "$rc"
eq "…discloses that it acknowledges more than it showed" "true" \
   "$(has '1 of the 2 moves being acknowledged are shown above' "$ERR")"
eq "…and still acknowledges the WHOLE uncapped set"   '[7,9]' \
   "$(jq -c '.acknowledge_ref_impact' "$TMP/ct-body-2.json")"
eq "…the conversion landed"                           '"number"' "$(jq -c '.[0].type' "$_FIELDS")"

# The set moved between the preview and the acknowledgement: the server refuses, and
# that refusal must reach the caller unlaundered — re-sending the NEW set from inside
# this run would make the flag mean "accept whatever moves", which is the whole thing
# the handshake exists to prevent.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
_CT_REFIMPACT_SHIFT=1
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --accept-ref-impact 2>&1 >/dev/null)" || rc=$?
eq "an acknowledged set that no longer matches → rc 1" "1"   "$rc"
eq "…stops at TWO calls (no third, self-answering, try)" "2" "$(_calls 'POST /custom_fields')"
eq "…and the server's refusal is what is read"        "true" "$(has 'the set grew or changed since the preview' "$ERR")"
eq "…nothing was written"                             '"string"' "$(jq -c '.[0].type' "$_FIELDS")"
# The scan's OWN offenders ride every one of these refusals (the server passes
# $scan['offenders'] / $scan['offender_count'] through on each throw), so this body names
# the moves it re-derived — the fixture that answered offender_count 0 / offenders [] here
# encoded a body the server does not send.
eq "…naming the moves the re-derived scan found"      "true" \
   "$(has '2 card value(s) block this conversion' "$ERR")"

# THE OTHER acknowledgement refusal, and the one that makes offender_count 0 a REAL body:
# the ref impact DISAPPEARED between the two calls, so the scan under the lock derives an
# empty expected set and refuses the acknowledgement with no offender at all. The offender
# arm then reported "0 card value(s) block this conversion" — sending the operator to look
# for cards that do not exist, on a run whose fault is the request.
_seed "$_F_DL_STR" "$_B_MIXED"
_CT_REFIMPACT="7 9"
_CT_REFIMPACT_GONE=1
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --accept-ref-impact 2>&1 >/dev/null)" || rc=$?
eq "an acknowledgement whose ref impact VANISHED → rc 1" "1"  "$rc"
eq "…is never reported as N cards blocking it"        "false" "$(has 'block this conversion' "$ERR")"
eq "…it says NO offending card was named"             "true"  "$(has 'naming NO offending card' "$ERR")"
eq "…and points at the plain re-run"                  "true"  "$(has 're-run PLAIN' "$ERR")"
eq "…the server's own refusal still reaches the caller" "true" \
   "$(has "no card's correlation would move" "$ERR")"
eq "…and nothing was written"                         '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

# The flag is inert where there is nothing to acknowledge — it can never ADD a call.
_seed "$_F_DL_NUM" "$_B_MIXED"
rc=0; _kbc_field_retype --field dl_number --to string --accept-ref-impact >/dev/null 2>&1 || rc=$?
eq "--accept-ref-impact on a clean conversion → rc 0" "0"    "$rc"
eq "…and makes exactly ONE call"                      "1"    "$(_calls 'POST /custom_fields')"

echo "-- retype — a conversion 2xx whose body nothing can be read out of --"
# kb_api decides success on the status class, so this arrives as a SUCCESS: the
# conversion LANDED and this run cannot say what it landed as. A bare jq here would
# exit 5 with jq's own parse error; through kb_parse_resp it is the verb's own arm.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_UNREADABLE=1
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "an unreadable conversion echo → rc 3, not jq's 5" "3"     "$rc"
eq "…calls it an UNVERIFIED WRITE"                    "true"  "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…leaks no raw jq parse error"                     "false" "$(has 'parse error' "$ERR")"
eq "…prints no field row on stdout"                   ""      "$OUT"
# It must not restamp: the pass is scoped to a conversion this run never read.
eq "…and does NOT run the --restamp-dl pass"          "0"     "$(_calls PATCH)"
eq "…nor even read the board for it"                  "0"     "$(_calls FETCH)"
# The label used to read "…and finishes it", which was both wider than the assertion
# under it and wider than the truth: this run has no census at all, so it knows nothing
# about whether the pass it skipped would finish. What a re-run does is RUN that pass.
eq "…while naming the re-run as safe"                "true"  "$(has 'Re-run this exact command' "$ERR")"
eq "…because the conversion half is a no-op"         "true"  "$(has 'answers as a server-side no-op' "$ERR")"
eq "…and says the re-run RUNS the skipped pass"      "true"  "$(has 'RUNS the --restamp-dl pass this run skipped' "$ERR")"
eq "…never that it FINISHES it"                      "false" "$(has 'finishes any --restamp-dl pass' "$ERR")"
eq "…naming the outcome no run of that pass repairs" "true"  \
   "$(has 'a stored value that is not a DL number is canonicalized by no run of it' "$ERR")"

# THE SAME ARM WITHOUT THE FLAG — the branch every assertion above skips. All of them
# are taken with --restamp-dl PASSED, so the case where the restamp half of that
# sentence is FALSE had no leg at all: no pass was requested, so this run skipped none
# and a re-run runs none either. Naming one here is the same over-claim one size down,
# and the trailing non-DL-value clause is a fact about a pass that does not exist on
# this branch. The rc is asserted too — the wording is conditional, the outcome is not.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_UNREADABLE=1
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "the same arm without --restamp-dl → rc 3"        "3"     "$rc"
eq "…still calls it an UNVERIFIED WRITE"             "true"  "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…still prints no field row on stdout"            ""      "$OUT"
eq "…still names the re-run as safe"                 "true"  "$(has 'Re-run this exact command' "$ERR")"
eq "…because the conversion half is a no-op"         "true"  "$(has 'answers as a server-side no-op' "$ERR")"
eq "…but claims NO skipped --restamp-dl pass"        "false" "$(has 'RUNS the --restamp-dl pass this run skipped' "$ERR")"
eq "…and does not name that pass at ALL"             "false" "$(has 'restamp' "$ERR")"
eq "…nor the non-DL-value clause only that pass has" "false" \
   "$(has 'canonicalized by no run of it' "$ERR")"
eq "…and runs no restamp pass"                       "0"     "$(_calls PATCH)"
eq "…nor reads the board for one"                    "0"     "$(_calls FETCH)"

# THE SAME ARM ON A COMMAND CARRYING --options — the one board on which "re-run this
# exact command" is advice the SERVER refuses. CustomFieldMutator::typeGates calls
# assertOptionsMatchTarget BEFORE the $from === $toType no-op short-circuit, so once the
# conversion has landed the identical command is a 422 options edit — and this arm is
# reached precisely when the run cannot tell whether it landed. The two legs above are
# the control: without --options the sentence is unchanged, so what these pin is the
# predicate and not the wording.
_seed "$_F_SEV_ENUM" "$_B_SEV"
_CT_UNREADABLE=1
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "an unreadable echo on a command carrying --options → rc 3" "3" "$rc"
eq "…still calls it an UNVERIFIED WRITE"             "true"  "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…names the re-run WITHOUT --options"             "true"  "$(has 'Re-run it WITHOUT --options' "$ERR")"
eq "…never tells the operator to re-run it as typed" "false" "$(has 'Re-run this exact command' "$ERR")"
eq "…nor calls re-running it safe"                   "false" "$(has 'so re-running is safe' "$ERR")"
eq "…naming the refusal that re-run would meet"      "true"  "$(has 'OPTIONS EDIT' "$ERR")"
eq "…and the route an option-set change belongs to"  "true"  "$(has 'the PATCH route' "$ERR")"
# THE RULING FOR THIS ARM, asserted as an ABSENCE. A 2xx is the server's landed-ness
# guarantee (it does not answer 2xx for a refusal), so this arm KNOWS the conversion
# landed and names one directive. The 000 arm's read-then-branch shape does not belong
# here: prescribing a 'field list' read would offer to resolve a question this arm has
# already answered, and its second branch — "if it still reads <from>, it did NOT land" —
# is a state this arm's own 2xx says cannot be the one it is in.
eq "…prescribes NO definition read, having a 2xx"    "false" "$(has 'Re-read the definition' "$ERR")"
eq "…and branches on no landing its 2xx settles"     "false" "$(has 'it did NOT land' "$ERR")"

# THE SAME CLAIM AT THE OTHER SITE, which is where it survived three fix rounds: the 000
# transport arm, whose whole job is to resolve "did the write land?" and which prescribed
# a resolution the server refuses. _kbc_field_change_type_report reports a RESPONSE and
# cannot see the request's flags, so this leg is what pins the predicates being plumbed to
# it — the sibling 000 leg above (no --options, same arm) is its control.
#
# AND THE SHAPE IS DIFFERENT HERE, which is the point of the leg. Every earlier round gave
# this arm ONE directive, and with --options on the command there is none that is true
# whichever way the write went: drop them and it is right only if the conversion landed,
# keep them and it is right only if it did not — and this arm exists precisely because it
# cannot tell. So it prescribes the READ first and branches on what the read shows, which
# is why each branch gets its own assertion below rather than one substring for the line.
_seed "$_F_SEV_ENUM" "$_B_SEV"
_CT_FORCE_HTTP=000
_CT_FORCE_BODY='curl: (28) Operation timed out after 30001 milliseconds with 0 bytes received'
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "a transport failure on a command carrying --options → rc 1" "1" "$rc"
eq "…still claims UNCERTAINTY about the write"       "true"  "$(has 'CANNOT say whether it landed' "$ERR")"
# THE READ IS THE FIRST THING THE RE-RUN SENTENCE SAYS, asserted against the tail of the
# uncertainty note it follows — not merely present somewhere in the line. A read named
# after the directives is decoration; a read named before them is what makes the
# directives conditional on something the operator has actually established.
eq "…and prescribes the definition READ first"       "true"  \
   "$(has "never arrived does. Re-read the definition FIRST ('field list')" "$ERR")"
eq "…the LANDED branch, named by the TARGET type"    "true"  \
   "$(has "if it now reads 'multi_select', the conversion LANDED, so re-run it WITHOUT --options" "$ERR")"
eq "…the NOT-LANDED branch, named by the SOURCE type" "true" \
   "$(has "if it still reads 'enum', it did NOT land, so re-run this exact command" "$ERR")"
eq "…naming the refusal the first branch avoids"     "true"  "$(has 'OPTIONS EDIT' "$ERR")"
# The three shapes the previous rounds shipped, each an UNCONDITIONAL directive on an arm
# that cannot know which branch the operator is on. All three are absences here.
eq "…never the unconditional 'drop the options'"     "false" \
   "$(has 'Re-run it WITHOUT --options:' "$ERR")"
eq "…never the unconditional 'run it as typed'"      "false" "$(has 'Re-run this exact command:' "$ERR")"
eq "…nor calls re-running it safe"                   "false" "$(has 'so re-running is safe' "$ERR")"
eq "…nor promises a server-side no-op either way"    "false" "$(has 'answers as a server-side no-op' "$ERR")"

# THE SAME ARM ON A DIFFERENT TYPE PAIR — the control that the two branches name the types
# THIS request was made with rather than a pair spelled into the sentence. Every --options
# leg above converts enum -> multi_select, so a hardcoded pair would be green across all of
# them; number -> enum shares neither end.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_FORCE_HTTP=000
_CT_FORCE_BODY='curl: (7) Failed to connect to localhost port 8080: Connection refused'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to enum --options low,high 2>&1 >/dev/null)" || rc=$?
eq "the same arm on a number -> enum request → rc 1" "1"     "$rc"
eq "…reads the LANDED branch against 'enum'"         "true"  \
   "$(has "if it now reads 'enum', the conversion LANDED" "$ERR")"
eq "…and the NOT-LANDED branch against 'number'"     "true"  \
   "$(has "if it still reads 'number', it did NOT land" "$ERR")"
eq "…naming the other request's types nowhere"       "false" "$(has 'multi_select' "$ERR")"

# THE RULE ITSELF, DRIVEN END TO END rather than asserted off a fixture: a landed
# --options conversion, then the EXACT same command again. Run 2 is a same-type request
# still carrying options, which assertOptionsMatchTarget refuses before the no-op
# short-circuit — the arm of this fake that no invocation in the suite had ever reached
# (every other --options leg targets a type the field is not). It is what makes the two
# legs above a repair of a real failure rather than a wording preference.
_seed "$_F_SEV_ENUM" "$_B_SEV"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "run 1: the --options conversion lands → rc 0"    "0"     "$rc"
eq "control: …the definition really IS the target type" '"multi_select"' "$(jq -c '.[0].type' "$_FIELDS")"
rc=0; ERR="$(_kbc_field_retype --field severity --to multi_select --options low,high 2>&1 >/dev/null)" || rc=$?
eq "run 2: the IDENTICAL command is REFUSED → rc 1"  "1"     "$rc"
eq "…as an options edit, in the server's own words"  "true"  \
   "$(has 'This request does not change the type, so it is an options edit' "$ERR")"
eq "…never as the no-op the re-run advice used to promise" "false" "$(has 'server-side no-op' "$ERR")"
eq "…and not mis-reported as a type-pair refusal"    "false" "$(has 'refused on the TYPE PAIR' "$ERR")"
# The client used to answer this refusal with its own three-item list of the server's
# option rules — which omitted THIS one, the fourth, and so enumerated rules none of
# which had fired. The echoed body names the rule that did.
eq "…and the client enumerates no rule set of its own" "false" "$(has 'prohibited on a scalar target' "$ERR")"
eq "…it points at the server's message instead"      "true"  \
   "$(has 'The message above IS the rule that refused it' "$ERR")"

echo "-- retype --restamp-dl — the post-conversion canonicalization pass --"
# The conversion alone leaves the bare int 1 as the STRING "1" (the cast matrix's text
# rule for a number source is json_encode), not "DL-0001". Correlation survives that,
# but a custom-field DSL filter spelled DL-0001 string-misses it — so this pass runs
# AFTER the conversion, through the one canonical DL renderer.
_seed "$_F_DL_NUM" "$_B_MIXED"
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "number -> string --restamp-dl → rc 0"             "0"    "$rc"
eq "…card 7's value is canonical"                     '"DL-0001"' "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "…as a JSON string"                                '"string"'  "$(jq -c '.[0].payload.dl_number | type' "$_BOARD")"
eq "…card 9 likewise"                                 '"DL-0042"' "$(jq -c '.[2].payload.dl_number' "$_BOARD")"
# The per-key write contract, asserted on the BODY: the fake merges per-key exactly as
# the v3 route does, so a body that carried the whole payload would leave the merged
# board reading identical. Only the request can witness it.
eq "…the restamp PATCH body is FLAT, one key deep"    '{"payload":{"dl_number":"DL-0001"}}' \
   "$(jq -c . "$TMP/task-patch-7.json")"
eq "…so card 7's sibling payload key survives"        "5"    "$(jq -c '.[0].payload.other' "$_BOARD")"
eq "…and card 8, carrying no dl_number, is never written" "false" \
   "$( [[ -f "$TMP/task-patch-8.json" ]] && echo true || echo false )"
eq "…the pass reports both counts"                    "true" \
   "$(has '2 of 2 card value(s) canonicalized and verified, 0 already canonical' "$ERR")"
eq "…and the conversion is still reported separately" "true" "$(has 'in the SAME transaction' "$ERR")"
# The control for the two legs below: the completeness claim above is emitted only
# because the server's own converted count EQUALS this census. Nothing is outside it.
eq "…and reports no out-of-census remainder"          "false" "$(has 'OUTSIDE THIS PASS' "$ERR")"

# THE CONVERSION'S POPULATION IS LARGER THAN THIS PASS'S, and only the server's own
# converted_task_count can see it. candidateQuery is withTrashed() with no archive
# filter, so every archived and every trashed carrier was converted; the census reads
# /tasks/search.json, which returns neither. Un-noticed, the run reports "N of N
# canonicalized and verified" and exits 0 while an arbitrary number of cards keep "1".
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_UNSEEN_CARRIERS=3
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a conversion that touched cards this pass cannot see → rc 1" "1" "$rc"
eq "…emits NO completeness claim on that run"         "false" \
   "$(has 'canonicalized and verified, 0 already canonical (left unwritten)' "$ERR")"
eq "…reports the remainder as its OWN outcome"        "true"  "$(has 'OUTSIDE THIS PASS ENTIRELY' "$ERR")"
eq "…naming both populations"                         "true"  \
   "$(has 'converted 5 card value(s), 3 more than the 2 this board read returns' "$ERR")"
eq "…and what those cards are"                        "true"  "$(has 'archived and soft-deleted' "$ERR")"
eq "…and that no re-run reaches them"                 "true"  "$(has 'no re-run reaches the 3 carrier(s)' "$ERR")"
# This arm already carved out the archived carriers and nothing else. Every visible card
# here canonicalized, so there is nothing a re-run repairs at all — and the line must not
# imply otherwise. The notdl carve-out is absent because no card here is one: same
# conditionality as the sibling control on the PATCH-failure leg.
eq "…and promises no repair it cannot make"          "true"  \
   "$(has 'would change NOTHING: nothing reported above is something a re-run acts on' "$ERR")"
eq "control: …with no non-DL exception, there being none" "false" \
   "$(has 'NOT-a-DL-number value(s) are not among them' "$ERR")"

# The remainder is REPORTED, not chased: the visible carriers are still canonicalized,
# and no card outside the census is written (this pass never PATCHes a card it did not read).
eq "control: the visible carriers were canonicalized" '"DL-0001"' "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "control: …and only they were written"             "2"     "$(_calls PATCH)"

# BOTH carve-outs at once, which is the only shape that shows they are independent: an
# out-of-census remainder AND a value no pass canonicalizes. Before this, the line read
# "finishes the VISIBLE rest" — and the non-DL card is squarely inside the visible set.
_seed "$_F_DL_NUM" '[{"id":7,"payload":{"dl_number":"not-a-dl"}},{"id":9,"payload":{"dl_number":42}}]'
_CT_UNSEEN_CARRIERS=3
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "an unseen remainder AND a non-DL value → rc 1"   "1"     "$rc"
eq "control: both are really reported"               "true"  "$(has 'OUTSIDE THIS PASS ENTIRELY' "$ERR")"
eq "control: …and the non-DL card by value"          "true"  "$(has "NOT a DL number, so nothing was written: 7 ('not-a-dl')" "$ERR")"
eq "…the VISIBLE rest is no longer promised"         "false" "$(has 'finishes the VISIBLE rest' "$ERR")"
eq "…the archived carriers are carved out"           "true"  "$(has 'no re-run reaches the 3 carrier(s) above at all' "$ERR")"
eq "…and so is the visible card no re-run repairs"   "true"  \
   "$(has 'The 1 NOT-a-DL-number value(s) are not among them' "$ERR")"

# The same defect at the other end of the census: NOTHING visible carries the key, so the
# run's line was "no card carries <key> — nothing to canonicalize" at rc 0 — a completeness
# claim over an empty denominator while the conversion had just rewritten N archived cards.
_seed "$_F_DL_NUM" '[{"id":8,"payload":{"other":5}}]'
_CT_UNSEEN_CARRIERS=2
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "an EMPTY census over a conversion that converted 2 → rc 1" "1" "$rc"
eq "…never reads as nothing-to-do"                    "false" "$(has 'nothing to canonicalize' "$ERR")"
eq "…says it canonicalized NOTHING"                   "true"  "$(has 'canonicalized NOTHING' "$ERR")"
eq "…and names the carriers it could not see"         "true"  "$(has 'All 2 of them are archived or soft-deleted' "$ERR")"
eq "…while writing no card"                           "0"     "$(_calls PATCH)"

# Idempotence: a re-run canonicalizes nothing and WRITES nothing. The census read is
# an authoritative board read, so an already-canonical card is measured, not assumed.
#
# ⚠ THIS LEG'S OUTCOME ASSERTION IS TIGHTENED, and the tightening is the point. The
# field is ALREADY `string`, so this run is the server's same-type NO-OP: nothing is
# scanned, converted_task_count is hardcoded 0, `n_conv > len` is structurally false and
# the pass's remainder instrument reads 0 whatever the board holds. The leg's intent —
# a re-run canonicalizes nothing and writes nothing — is legitimate and survives
# verbatim (rc 0, zero PATCHes, the same counted line). What it may no longer do is let
# that line stand ALONE, because on this exact path the run measured no population at
# all. This is not an assertion weakened to go green; it is an assertion that pinned a
# bug being made to require what the run can actually support.
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"DL-0001"}},{"id":9,"payload":{"dl_number":"DL-0042"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a re-run over canonical values → rc 0"            "0"    "$rc"
eq "…issues NO task PATCH at all"                     "0"    "$(_calls PATCH)"
eq "…and says so as its own outcome"                  "true" \
   "$(has '0 of 2 card value(s) canonicalized and verified, 2 already canonical' "$ERR")"
eq "…which is scoped to the cards it can SEE"         "true" \
   "$(has 'this is a statement about the cards this pass can SEE' "$ERR")"
eq "…naming what the census does not read"            "true" \
   "$(has 'census reads LIVE, NON-ARCHIVED cards only' "$ERR")"
# The no-op branch of the note, which the SCANNED branch must never be able to satisfy:
# a converted count of 0 that came from the no-op factory is not a measurement, and
# saying "0 is not more than 2" here would be arithmetic dressed as evidence.
eq "…and saying the server scanned NOTHING on this run" "true" \
   "$(has 'the server converted NOTHING on this run' "$ERR")"
eq "…never the scanned wording"                       "false" \
   "$(has 'is not more than this census returned' "$ERR")"

# INSTANCE (a) — the two-run sequence the tool's OWN remediation lines prescribe, which
# is the only way a no-op meets an out-of-census carrier without the fake lying. Run 1
# is a real conversion whose population exceeds the census: it proves 3 archived
# carriers exist and refuses to claim completeness. Run 2 is the prescribed re-run —
# same board, same archived carriers, still out there — and it is the run that gets to
# speak last. No re-seed between them, and _CT_UNSEEN_CARRIERS stays set: the no-op arm
# ignores it exactly as the server's noop() factory ignores its own scan.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_UNSEEN_CARRIERS=3
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "run 1 (a real conversion) proves the remainder → rc 1" "1" "$rc"
eq "…and names it"                                    "true" "$(has 'OUTSIDE THIS PASS ENTIRELY' "$ERR")"
# The call log is cumulative across both runs (there is no re-seed, deliberately), so
# run 2's write count is a DELTA, not a total.
_patches_after_run1="$(_calls PATCH)"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "run 2 (the prescribed re-run) is the server's no-op → rc 0" "0" "$rc"
eq "…the server reports converting nothing"           "true" "$(has 'the server converted nothing (no scan, no write)' "$ERR")"
eq "…and the counted line is emitted"                 "true" \
   "$(has '2 card value(s) canonicalized and verified' "$ERR")"
# The defect: run 2's remainder instrument reads 0 because nothing was scanned, not
# because nothing is left — the 3 carriers run 1 proved are still there, unwritten.
eq "…but it does NOT read as a clean field"           "true" \
   "$(has 'A remainder can be PROVEN by this pass and never ruled out by it' "$ERR")"
eq "…and it says the server scanned nothing"          "true" \
   "$(has 'the server converted NOTHING on this run' "$ERR")"
eq "…while still writing no card"                     "$_patches_after_run1" "$(_calls PATCH)"

# INSTANCE (b) — the empty census on that same no-op path: every carrier of the key is
# archived, so the census returns zero and the old line said "no card carries 'dl_number'".
_seed "$_F_DL_STR" '[{"id":8,"payload":{"other":5}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "an empty census on the no-op path → rc 0"         "0"    "$rc"
eq "…never claims the BOARD carries nothing"          "false" "$(has "no card carries 'dl_number'" "$ERR")"
eq "…says only what it read"                          "true"  "$(has 'no card this pass can SEE carries' "$ERR")"
eq "…carries the census scope"                        "true"  "$(has 'census reads LIVE, NON-ARCHIVED cards only' "$ERR")"
eq "…and the no-op clause, not the scanned one"       "true"  "$(has 'the server converted NOTHING on this run' "$ERR")"
eq "…writing no card"                                 "0"     "$(_calls PATCH)"

# INSTANCE (c) — the count compare is blind by CONSTRUCTION, not only on the no-op path.
# converted_task_count is measured when the transaction commits; the census is a read of
# a later moment. Two live carriers converted plus THREE archived ones, then three new
# live carriers appear before the census: len 5, n_conv 5, unseen 0 — and the archived
# three are untouched. This is why the scope note is unconditional rather than printed
# only where the pass cannot prove a zero remainder: on this run it "proved" one that
# does not exist.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_UNSEEN_CARRIERS=3
_CT_LIVE_GROWTH='[{"id":21,"payload":{"dl_number":"DL-0021"}},{"id":22,"payload":{"dl_number":"DL-0022"}},{"id":23,"payload":{"dl_number":"DL-0023"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "live-side growth masking an archived remainder → rc 0" "0" "$rc"
# The control that makes this leg mean something: the arithmetic really did cancel, so
# the run reaches the completeness arm and NOT the proven-remainder one.
eq "control: the counts cancel, so no remainder is proven" "false" "$(has 'OUTSIDE THIS PASS' "$ERR")"
eq "control: …and the completeness arm is what fired"  "true" \
   "$(has '2 of 5 card value(s) canonicalized and verified, 3 already canonical' "$ERR")"
eq "…yet the claim is scoped to what was read"         "true" \
   "$(has 'this is a statement about the cards this pass can SEE' "$ERR")"
eq "…and the count compare is called a floor, not a proof" "true" \
   "$(has 'a FLOOR, not a proof' "$ERR")"

# A restamp PATCH that FAILED leaves a card that was never written — never verifiable,
# and never counted as done (the pass-1 defect that must not come back).
_seed "$_F_DL_NUM" "$_B_MIXED"
_PATCH_FAIL="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a FAILING restamp PATCH → rc 1"                   "1"    "$rc"
eq "…names it as a PATCH failure"                     "true" "$(has 'the restamp PATCH FAILED on 1 card(s): 9' "$ERR")"
# kb_api answers a TIMED-OUT PATCH with the same $KB_API_RC_TRANSPORT as a connection it
# never opened (both read no answer), and a timed-out write may already be committed — and
# this bucket's bare `||` catches an ANSWERED non-2xx alike (card#6680, the caller-side half
# left open there) — so "this run never wrote them, so each still holds the value the
# conversion left it with" is a claim about a board nothing read. Same transport, same
# owner, same wording as the conversion's own 000 arm.
eq "…claims UNCERTAINTY, not safety, about the write" "true"  "$(has 'CANNOT say whether it landed' "$ERR")"
eq "…never claims the card was left untouched"        "false" "$(has 'never wrote them' "$ERR")"
# The re-run SENTENCE is the caller's here, not the shared note's — on this pass "this
# exact command" is honest (--restamp-dl forces --to string, on which the server refuses
# --options twice over, so no run reaching this line carried them), and that is exactly
# the condition the conversion's own arms cannot meet. Asserted so the sentence cannot be
# dropped by an edit to the owner it is handed to.
eq "…and names the idempotent re-run it CAN make"     "true"  \
   "$(has 'Re-run this exact command: a card already holding the canonical form' "$ERR")"
eq "…counts only the card that was written"           "true" "$(has '1 of 2 card value(s) canonicalized and verified' "$ERR")"
eq "…and the conversion itself is still reported as landed" "true" "$(has 'the conversion LANDED' "$ERR")"
# THE CARVE-OUT IS CONDITIONAL, and this is what proves it. No card here is a non-DL
# value, so naming that exception would be describing something that did not happen —
# the same defect one size down, and the one the offender-cap notice was fixed for.
# (Contrast the census-scope note, which IS unconditional: that fact holds on every run
# of this pass on every board, while this one is measured per run.)
eq "…and names NO non-DL exception, because there is none" "false" \
   "$(has 'NOT-a-DL-number value(s) are not among them' "$ERR")"
eq "control: …while still promising the finishable card" "true" \
   "$(has 'finishes the 1 card(s) above that a re-run can finish' "$ERR")"

# A PATCH that 200s and silently does not land: only the re-read separates "migrated"
# from "looks migrated".
_seed "$_F_DL_NUM" "$_B_MIXED"
_PATCH_NOOP="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a silently-lost restamp → rc 1"                   "1"    "$rc"
eq "…is reported as read back DIFFERENT"              "true" "$(has 'read back a DIFFERENT value on 1 card(s): 9' "$ERR")"
eq "…and named as a DSL-filter miss"                  "true" "$(has 'DSL filter spelled DL-NNNN will silently skip' "$ERR")"

# A verification read that could not observe the card is UNKNOWN state — not a wrong
# value. Folding the two together asserts a board this run never read.
_seed "$_F_DL_NUM" "$_B_MIXED"
_GET_TASK_FAIL="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a FAILED verification GET → rc 1"                 "1"    "$rc"
eq "…is reported as an unobserved card"               "true" "$(has 'the verification read could not observe 1 card(s): 9' "$ERR")"
eq "…whose state is called UNKNOWN"                   "true" "$(has 'their state is UNKNOWN' "$ERR")"
eq "…never claimed to have read back a wrong value"   "false" "$(has 'read back a DIFFERENT value' "$ERR")"

# The same arm, reached the other way: a 2xx whose body carries no value. The old
# code folded this into "read back a DIFFERENT value", which claimed the card still
# held its old value — a statement about a board nothing had read.
_seed "$_F_DL_NUM" "$_B_MIXED"
_GET_TASK_UNREADABLE="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "an unreadable verification body → rc 1, not jq's 5" "1"   "$rc"
eq "…lands in the same UNOBSERVED arm"                "true"  "$(has 'the verification read could not observe 1 card(s): 9' "$ERR")"
eq "…and claims nothing about that card's value"      "false" "$(has 'read back a DIFFERENT value' "$ERR")"
eq "…leaks no raw jq parse error"                     "false" "$(has 'parse error' "$ERR")"
# Control: the write itself DID land, so the refusal above is about the read-back only.
eq "control: …the restamp landed on that card"        '"DL-0042"' "$(jq -c '.[2].payload.dl_number' "$_BOARD")"

# A value that is not a DL at all cannot be canonicalized — and the conversion has
# already committed, so this can only be reported, never refused in advance.
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"not-a-dl"}},{"id":9,"payload":{"dl_number":"42"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a value that is not a DL number → rc 1"           "1"    "$rc"
eq "…is named with its value, as its own outcome"     "true" "$(has "NOT a DL number, so nothing was written: 7 ('not-a-dl')" "$ERR")"
eq "…is never counted as canonicalized"               "true" "$(has '1 of 2 card value(s) canonicalized and verified' "$ERR")"
eq "…that card is left exactly as it was"             '"not-a-dl"' "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "…and it is never PATCHed"                         "false" "$( [[ -f "$TMP/task-patch-7.json" ]] && echo true || echo false )"
eq "…while the DL-shaped sibling IS canonicalized"    '"DL-0042"' "$(jq -c '.[1].payload.dl_number' "$_BOARD")"
# THE RE-RUN LINE, ON THE RUN THAT MOTIVATES IT. notdl is the ONLY non-empty bucket
# here (card 9 canonicalized, nothing failed, nothing unseen), so a re-run repairs
# NOTHING — kb_dl_canon refuses 'not-a-dl' identically on every pass. The old line said
# "Re-running this exact command finishes the rest", i.e. told the operator to run a
# command that provably does nothing, at the one moment they most need to be told the
# VALUE is what has to change.
eq "…and the run does NOT promise a re-run finishes it" "false" "$(has 'finishes the' "$ERR")"
eq "…it says a re-run would change nothing"           "true"  \
   "$(has 'would change NOTHING: nothing reported above is something a re-run acts on' "$ERR")"
eq "…and names the non-DL value as the reason"        "true"  \
   "$(has 'The 1 NOT-a-DL-number value(s) are not among them' "$ERR")"
eq "…naming what would actually fix it"               "true"  \
   "$(has 'those need the VALUE corrected, never another run' "$ERR")"
eq "control: the rc is unchanged by any of that"      "1"     "$rc"

# The same bucket ALONGSIDE one a re-run does repair: the promise must survive, scoped
# to the count it is true of, and carry the carve-out beside it rather than instead of it.
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"not-a-dl"}},{"id":9,"payload":{"dl_number":"42"}}]'
_PATCH_FAIL="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a notdl card beside a FAILED PATCH → rc 1"        "1"     "$rc"
eq "…the promise is scoped to the finishable count"   "true"  \
   "$(has 'finishes the 1 card(s) above that a re-run can finish' "$ERR")"
eq "…and never to an unqualified 'the rest'"          "false" "$(has 'finishes the rest' "$ERR")"
eq "…with the non-DL card carved OUT of that count"   "true"  \
   "$(has 'The 1 NOT-a-DL-number value(s) are not among them' "$ERR")"
eq "control: both buckets really were reported"       "true"  \
   "$(has 'the restamp PATCH FAILED on 1 card(s): 9' "$ERR")"

_seed "$_F_DL_NUM" '[{"id":8,"payload":{"other":5}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "--restamp-dl with nothing populated → rc 0"       "0"    "$rc"
eq "…says so rather than staying silent"              "true" "$(has 'no card this pass can SEE carries' "$ERR")"
# TIGHTENED, not weakened. "no card carries 'dl_number'" is a statement about the BOARD,
# and this pass reads a strict subset of it — every carrier of the key can be archived
# while this census returns zero. The rc, the write count and the fact that the line is
# emitted at all are unchanged; what is now also required is that the line does not
# claim more than the read supports.
eq "…and never claims that of the BOARD"             "false" "$(has "no card carries 'dl_number'" "$ERR")"
eq "…the census scope rides the line"                "true" "$(has 'census reads LIVE, NON-ARCHIVED cards only' "$ERR")"
eq "…this run DID scan, so it says the count is a floor" "true" \
   "$(has 'is not more than this census returned' "$ERR")"
eq "…and writes no card"                              "0"    "$(_calls PATCH)"
eq "…the conversion still landed"                     '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

# An incomplete board read AFTER the conversion: the pass cannot run over a partial
# board, and the report must not read as "nothing happened" — the conversion HAS
# committed at that point, which is the one thing this ordering makes true.
_seed "$_F_DL_NUM" "$_B_MIXED"
_FETCH_RC=4
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "an incomplete board read under --restamp-dl → rc 1" "1"  "$rc"
eq "…says the conversion LANDED but the pass did not run" "true" \
   "$(has 'the conversion LANDED, but --restamp-dl did NOT run' "$ERR")"
eq "…and no card was rewritten"                       "0"    "$(_calls PATCH)"
eq "…the definition really IS converted"              '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

echo "-- retype — input guards --"
# --restamp-dl renders the DL-NNNN string form, so a non-string target is refused
# BEFORE the wire: seeded from the STRING definition on purpose, since against the
# number definition `--to number` would be the server's no-op and the zero-call
# assertion would be carried by that instead of by this guard.
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "--restamp-dl with a non-string target → rc 2"     "2"    "$rc"
eq "…and issues no request at all"                    "0"    "$(_calls 'POST /custom_fields')"
eq "…naming the flag's own constraint"                "true" "$(has 'requires --to string' "$ERR")"

_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field nope --to number 2>&1 >/dev/null)" || rc=$?
eq "retype on an unresolved --field → rc 2"           "2"    "$rc"
eq "…enumerates the board's defined fields"           "true" "$(has 'defined fields' "$ERR")"
eq "…and issues no request"                           "0"    "$(_calls 'POST /custom_fields')"
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; _kbc_field_retype --field dl_number --to bogus >/dev/null 2>&1 || rc=$?
eq "retype to an unknown type → rc 2"                 "2"    "$rc"
eq "…before any request"                              "0"    "$(_calls 'POST /custom_fields')"
rc=0; _kbc_field_retype --to string >/dev/null 2>&1 || rc=$?
eq "retype with no --field → rc 2"                    "2"    "$rc"
rc=0; _kbc_field_retype --field dl_number >/dev/null 2>&1 || rc=$?
eq "retype with no --to → rc 2"                       "2"    "$rc"
rc=0; _kbc_field_retype --field dl_number --to string --bogus >/dev/null 2>&1 || rc=$?
eq "retype with an unknown arg → rc 2"                "2"    "$rc"
rc=0; _kbc_field_retype --field dl_number --to string --options '' >/dev/null 2>&1 || rc=$?
eq "retype with an explicitly-empty --options → rc 2" "2"    "$rc"
rc=0; _kbc_field_delete >/dev/null 2>&1 || rc=$?
eq "delete with no --field → rc 2"                    "2"    "$rc"

# ---------------------------------------------------------------------------
echo "== create / retype are reported from the BOARD'S INDEX, not from the write's echo =="
# THE CLASS (card#8556): a mutating verb reports success it never read back. `field delete`
# already re-read the index; `create` reported off the id in its 201 and `retype` off the row
# in its 200 — both the write's own answer. The index is the ONLY read surface a custom field
# has (there is no per-field GET), which is why it is the surface all three now confirm on.

echo "-- create: a 201 with an id for a field the board does not define --"
_seed "$_F_DL_STR" '[]'
_POST_NOT_INDEXED=1
rc=0; OUT="$(_kbc_field_create --key severity --label S --type string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "create the index does not confirm → rc 1"        "1"     "$rc"
eq "…named as a HARD FAILURE"                        "true"  "$(has 'HARD FAILURE' "$ERR")"
eq "…and prints no id (the 201 carried one)"         ""      "$OUT"
eq "…and no success line"                            "false" "$(has 'created on board' "$ERR")"
# The control on the same route: the identical call over a board that DOES index it.
_seed "$_F_DL_STR" '[]'
rc=0; OUT="$(_kbc_field_create --key severity --label S --type string 2>/dev/null)" || rc=$?
eq "control: the same create over an indexing board → rc 0" "0"  "$rc"
eq "control: …and prints the id"                            "92" "$OUT"
eq "control: …off TWO index reads (uniqueness, then confirm)" "2" "$(_calls 'GET /boards')"

echo "-- create: an index that cannot be re-read is UNVERIFIED, not a failure --"
_seed "$_F_DL_STR" '[]'
_FIELDS_FAIL_ON_READ=2
rc=0; ERR="$(_kbc_field_create --key severity --label S --type string 2>&1 >/dev/null)" || rc=$?
eq "create whose confirming index read fails → rc 3" "3"    "$rc"
eq "…named as an UNVERIFIED WRITE"                   "true" "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…and says to treat it as LANDED"                 "true" "$(has 'treat it as LANDED' "$ERR")"
eq "…the POST really was issued"                     "1"    "$(_calls 'POST /boards')"

echo "-- retype: a 200 over a definition that did not move --"
# The sharpest of the three. A conversion that did not take leaves every DSL filter on the key
# matching the OLD JSON type while `field list` is never consulted — invisible from every
# surface an operator looks at, which is why the run has to look at it.
_seed "$_F_DL_NUM" "$_B_MIXED"
_CT_DEFINITION_STUCK=1
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype the index does not confirm → rc 1"        "1"     "$rc"
eq "…named as a HARD FAILURE naming both types"      "true"  "$(has "still declares 'dl_number' as type 'number', not the 'string'" "$ERR")"
eq "…prints no field row on stdout"                  ""      "$OUT"
# And it must not restamp: canonicalizing card values against a type this run could not
# confirm would be rewriting them on a guess.
eq "…and does NOT run the --restamp-dl pass"         "0"     "$(_calls PATCH)"

echo "-- retype: a confirming index read that fails is UNVERIFIED --"
_seed "$_F_DL_NUM" "$_B_MIXED"
_FIELDS_FAIL_ON_READ=2
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "retype whose confirming index read fails → rc 3" "3"    "$rc"
eq "…named as an UNVERIFIED WRITE"                   "true" "$(has 'UNVERIFIED WRITE' "$ERR")"
eq "…and says to treat the conversion as LANDED"     "true" "$(has 'Treat the conversion as LANDED' "$ERR")"
eq "…and still does NOT run the --restamp-dl pass"   "0"    "$(_calls PATCH)"

_summary "kbcard-field-selftest"
