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
#   - the --restamp-dl pass's outcomes, each asserted on the resulting board rather than
#     on a call: a PATCH that 200s and silently does not land separates "migrated" from
#     "looks migrated", a verification read that observed nothing is not a wrong value,
#     and the conversion's population is LARGER than this census (it includes archived
#     and soft-deleted carriers), so a run with a remainder reports it and claims no
#     completeness.
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
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines the field fns without running main()

_mktmp_scratch

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
kb_api() {
    case "$1 $2" in
        "GET /boards/"*) printf '%s' "$_GET_FIELDS" ;;
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
# Carriers the conversion converted that NO board read this client makes returns —
# archived and soft-deleted cards. The server's candidateQuery is
# `withTrashed()->where(board_id)->whereNotNull(payload->key)` with no archive filter,
# while the census reads /tasks/search.json, which excludes both. A fake board cannot
# hold a card its own fetch does not return, so the difference is declared here: it
# shows up exactly where the real one does, in meta.converted_task_count.
_CT_UNSEEN_CARRIERS=0

# _seed <fields-json> <board-json>: fresh board state + a fresh call log.
_seed() {
    : > "$_CALLS"; : > "$_POST_BODY"
    rm -f "$_DELETED" "$TMP"/task-patch-*.json "$TMP"/ct-body-*.json
    _FETCH_RC=0; _POST_FAIL=""; _POST_NOID=""; _PATCH_FAIL=""; _PATCH_NOOP=""
    _DELETE_NOOP=""; _FIELDS_FAIL_AFTER_DELETE=""; _GET_TASK_FAIL=""; _FIELDS_UNREADABLE=""
    _POST_UNREADABLE=""; _GET_TASK_UNREADABLE=""
    _CT_FORCE_HTTP=""; _CT_FORCE_BODY=""; _CT_UNREADABLE=""; _CT_REFIMPACT=""
    _CT_REFIMPACT_SHIFT=""; _CT_TYPE_MOVED=""; _CT_REFIMPACT_GONE=""
    _CT_REFIMPACT_CAP=""; _CT_UNSEEN_CARRIERS=0
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
            jq -c --argjson f "$nf" '. + [$f]' "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"
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
            jq -c --argjson id "$id" --arg t "$to" --argjson o "${opts:-null}" \
                'map(if .id == $id then .type = $t | (if $o == null then . else .options = $o end) else . end)' \
                "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"
            # meta.converted_task_count is the SERVER's population, not this board read's:
            # the archived and soft-deleted carriers it also converted are declared by the
            # knob, since a fake board cannot hold a card its own fetch never returns.
            _ct_200 "$id" "$from" "$to" "$(( carriers + _CT_UNSEEN_CARRIERS ))" ;;
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
eq "create whose 2xx carries no id → rc 1"           "1"    "$rc"
eq "…and says the write is UNVERIFIED"               "true" "$(has 'UNVERIFIED' "$ERR")"

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
eq "create on a 2xx nothing reads out of → rc 1, not jq's 5"  "1"     "$rc"
eq "…the SAME UNVERIFIED-write arm an id-less 2xx takes"      "true"  "$(has 'UNVERIFIED' "$ERR")"
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
rc=0; _kbc_field_retype --field severity --to multi_select --options low,high >/dev/null 2>&1 || rc=$?
eq "enum -> multi_select with --options → rc 0"       "0"    "$rc"
eq "…the CSV reaches the wire as the server's [{value}] objects" '[{"value":"low"},{"value":"high"}]' \
   "$(jq -c '.options' "$TMP/ct-body-1.json")"
eq "…and the definition carries them"                 '[{"value":"low"},{"value":"high"}]' "$(jq -c '.[0].options' "$_FIELDS")"

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
eq "an unreadable conversion echo → rc 1, not jq's 5" "1"     "$rc"
eq "…calls the conversion UNCONFIRMED"                "true"  "$(has 'the conversion is UNCONFIRMED' "$ERR")"
eq "…leaks no raw jq parse error"                     "false" "$(has 'parse error' "$ERR")"
eq "…prints no field row on stdout"                   ""      "$OUT"
# It must not restamp: the pass is scoped to a conversion this run never read.
eq "…and does NOT run the --restamp-dl pass"          "0"     "$(_calls PATCH)"
eq "…nor even read the board for it"                  "0"     "$(_calls FETCH)"
eq "…while saying a re-run is safe and finishes it"   "true"  "$(has 'Re-run this exact command' "$ERR")"

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
# The remainder is REPORTED, not chased: the visible carriers are still canonicalized,
# and no card outside the census is written (this pass never PATCHes a card it did not read).
eq "control: the visible carriers were canonicalized" '"DL-0001"' "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "control: …and only they were written"             "2"     "$(_calls PATCH)"

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
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"DL-0001"}},{"id":9,"payload":{"dl_number":"DL-0042"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a re-run over canonical values → rc 0"            "0"    "$rc"
eq "…issues NO task PATCH at all"                     "0"    "$(_calls PATCH)"
eq "…and says so as its own outcome"                  "true" \
   "$(has '0 of 2 card value(s) canonicalized and verified, 2 already canonical' "$ERR")"

# A restamp PATCH that FAILED leaves a card that was never written — never verifiable,
# and never counted as done (the pass-1 defect that must not come back).
_seed "$_F_DL_NUM" "$_B_MIXED"
_PATCH_FAIL="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a FAILING restamp PATCH → rc 1"                   "1"    "$rc"
eq "…names it as a PATCH failure"                     "true" "$(has 'the restamp PATCH FAILED on 1 card(s): 9' "$ERR")"
# kb_api returns 1 for a TIMED-OUT PATCH exactly as it does for a refused one, and a
# timed-out write may already be committed — so "this run never wrote them, so each still
# holds the value the conversion left it with" is a claim about a board nothing read. Same
# transport, same owner, same wording as the conversion's own 000 arm.
eq "…claims UNCERTAINTY, not safety, about the write" "true"  "$(has 'CANNOT say whether it landed' "$ERR")"
eq "…never claims the card was left untouched"        "false" "$(has 'never wrote them' "$ERR")"
eq "…counts only the card that was written"           "true" "$(has '1 of 2 card value(s) canonicalized and verified' "$ERR")"
eq "…and the conversion itself is still reported as landed" "true" "$(has 'the conversion LANDED' "$ERR")"

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

_seed "$_F_DL_NUM" '[{"id":8,"payload":{"other":5}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "--restamp-dl with nothing populated → rc 0"       "0"    "$rc"
eq "…says so rather than staying silent"              "true" "$(has 'no card carries' "$ERR")"
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

_summary "kbcard-field-selftest"
