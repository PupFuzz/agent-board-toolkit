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
# does not cascade into the card payloads: that IS the measured server behaviour that
# makes the restamp load-bearing, and a fake that cascaded it would let the restamp be
# deleted with every assertion still green. What it guards:
#   - create ECHOES the created field id (the write verification), sends the server's
#     [{value}] option shape, and refuses a duplicate key at rc 2 with ZERO POSTs —
#     the rc alone does not carry that guard, since the server's own 422 also fails;
#   - delete ALWAYS prints the `N of M board cards carry <key>` denominator, refuses a
#     populated field at rc 2 naming both consequences, warns loudly under
#     --orphan-values, and refuses at rc 1 on EVERY incomplete-read rc
#     fetch_board_cards defines (1/2/3/4) — carried by a positive control that deletes
#     at rc 0 off the SAME board and the SAME zero numerator with a complete read;
#   - retype's whole ordered sequence, asserted on the resulting board: the capture
#     precedes any mutation, the DELETE precedes the recreate, key/label survive, and
#     each card's value is re-read and asserted on VALUE AND JSON TYPE — the case
#     where a restamp PATCH 200s and silently does not land is the one that separates
#     "migrated" from "looks migrated", and it is exercised directly;
#   - the three states that must not strand the board: an uncastable value refuses
#     BEFORE the delete, a failed recreate names the state and the exact command that
#     finishes it, and a partial verify lists the ids and says re-running retype will
#     not finish them.
# All 16 mutations run over this file redded the assertions they target and nothing
# else; two assertions were found BLIND by that pass and rewritten (a bare `": 7"`
# needle that a proceeding run also satisfied, and a `--to number` case whose fixture
# hit the already-target no-op before the guard under test).
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
# The lifecycle verbs are not independently checkable against a per-call stub: the
# whole point of `retype` is the ORDER of a delete, a recreate and a per-card restamp,
# and the defect it exists to prevent (a board that READS migrated while every value
# still carries the old JSON type and the search index is purged) is only observable
# in the END STATE. So the fake below holds real mutable state — the board's field
# index in $_FIELDS, its cards in $_BOARD — and every assertion below reads that state
# back, never the stub's own echo.
#
# The DELETE arm deliberately does NOT touch $_BOARD: that IS measured caveat (A), the
# server behaviour that makes the restamp load-bearing. If this fake cascaded the
# delete into the payloads, the restamp assertions would pass with the restamp deleted.
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

# _seed <fields-json> <board-json>: fresh board state + a fresh call log.
_seed() {
    : > "$_CALLS"; : > "$_POST_BODY"
    _FETCH_RC=0; _POST_FAIL=""; _POST_NOID=""; _PATCH_FAIL=""; _PATCH_NOOP=""
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
            jq -c '{data: .}' "$_FIELDS" ;;
        "POST /boards/"*"/custom_fields.json")
            printf '%s' "$body" > "$_POST_BODY"
            [[ -z "$_POST_FAIL" ]] || { echo "kbcard: HTTP 500 on POST $path" >&2; return 1; }
            [[ -z "$_POST_NOID" ]] || { printf '{"data":{}}'; return 0; }
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
            jq -c --argjson id "$id" 'map(select(.id != $id))' "$_FIELDS" > "$TMP/f.tmp" && mv "$TMP/f.tmp" "$_FIELDS"
            printf '' ;;   # the real route answers 204 with an EMPTY body
        "PATCH /tasks/"*)
            id="${path#/tasks/}"; id="${id%.json}"
            case " $_PATCH_FAIL " in *" $id "*) echo "kbcard: HTTP 500 on PATCH $path" >&2; return 1 ;; esac
            case " $_PATCH_NOOP " in *" $id "*) jq -nc '{data: {}}'; return 0 ;; esac
            jq -c --argjson id "$id" --argjson b "$body" \
               'map(if .id == $id then .payload = ((.payload // {}) + $b.payload) else . end)' \
               "$_BOARD" > "$TMP/b.tmp" && mv "$TMP/b.tmp" "$_BOARD"
            jq -nc '{data: {}}' ;;
        "GET /tasks/"*)
            id="${path#/tasks/}"; id="${id%.json}"
            jq -c --argjson id "$id" '{data: (map(select(.id == $id)) | .[0])}' "$_BOARD" ;;
        *) printf '{"data":null}' ;;
    esac
}

_F_DL_STR='[{"id":91,"board_id":1,"key":"dl_number","label":"DL Number","type":"string","options":null}]'
_F_DL_NUM='[{"id":91,"board_id":1,"key":"dl_number","label":"DL Number","type":"number","options":null}]'
# Card 8 carries NO dl_number: it is the denominator's other half. Without it every
# "N of M" assertion would read the same with the numerator computed as the board size.
_B_MIXED='[{"id":7,"payload":{"dl_number":1}},{"id":8,"payload":{"other":5}},{"id":9,"payload":{"dl_number":42}}]'

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

# An existing key is refused BEFORE the POST — a key is unique per board and its type
# is immutable, so "create over the top" is not a re-type. rc-only would stay green
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

echo "-- retype — no-op when already the target type --"
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype to the CURRENT type → rc 0"               "0"    "$rc"
eq "…says it is already that type"                   "true" "$(has "already type 'string'" "$ERR")"
eq "…echoes the field row on stdout"                 '"dl_number"' "$(jq -c '.key' <<<"$OUT")"
eq "…issues no DELETE"                               "0"    "$(_calls DELETE)"
eq "…and does not even read the board"               "0"    "$(_calls FETCH)"

echo "-- retype — the full ordered sequence, with --restamp-dl --"
_seed "$_F_DL_NUM" "$_B_MIXED"
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype number -> string → rc 0"                  "0"    "$rc"
eq "…CAPTURES one line per populated card on stdout" "2"    "$(jq -s 'length' <<<"$OUT")"
eq "…each capture carries the pre-mutation value"    "1"    "$(jq -s -r '.[0].from' <<<"$OUT")"
eq "--restamp-dl canonicalizes the bare int 1"       '"DL-0001"' "$(jq -s -c '.[0].to' <<<"$OUT")"
eq "…and the bare int 42"                            '"DL-0042"' "$(jq -s -c '.[1].to' <<<"$OUT")"
eq "…reports restamped and verified N/N"             "true" "$(has 'restamped and verified 2/2' "$ERR")"
eq "…the DELETE precedes the recreate"               "DELETE POST " \
   "$(grep -E '^(DELETE|POST) ' "$_CALLS" | awk '{print $1}' | tr '\n' ' ')"
eq "…exactly ONE definition survives"                "1"    "$(jq 'length' "$_FIELDS")"
eq "…and it is the target type"                      '"string"' "$(jq -c '.[0].type' "$_FIELDS")"
eq "…carrying the SAME key"                          '"dl_number"' "$(jq -c '.[0].key' "$_FIELDS")"
eq "…and the SAME label"                             '"DL Number"' "$(jq -c '.[0].label' "$_FIELDS")"
eq "…card 7's value is RESTAMPED canonical"          '"DL-0001"' "$(jq -c '.[0].payload.dl_number' "$_BOARD")"
eq "…as a JSON string, not a number (caveat A)"      '"string"'  "$(jq -c '.[0].payload.dl_number | type' "$_BOARD")"
eq "…card 9 likewise"                                '"DL-0042"' "$(jq -c '.[2].payload.dl_number' "$_BOARD")"
eq "…and an unrelated payload key is untouched"      "5"    "$(jq -c '.[1].payload.other' "$_BOARD")"

# An UNPOPULATED retype still runs the whole sequence — the empty-plan path, which
# --restamp-dl's per-row loop and the verify loop both have to survive at length 0.
_seed "$_F_DL_NUM" '[{"id":8,"payload":{"other":5}}]'
rc=0; OUT="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>"$TMP/e")" || rc=$?
ERR="$(cat "$TMP/e")"
eq "retype of an UNPOPULATED field → rc 0"           "0"    "$rc"
eq "…captures nothing on stdout"                     ""     "$OUT"
eq "…and reports 0/0 rather than staying silent"     "true" "$(has 'restamped and verified 0/0' "$ERR")"
eq "…the definition IS retyped"                      '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

echo "-- retype — a restamp that does not land is caught by the VERIFY --"
# The whole defect in one case: the PATCH 200s and the value silently does NOT land, so
# the definition reads migrated while the card still holds a JSON number. Only the
# re-read (value AND type) can tell those apart.
_seed "$_F_DL_NUM" "$_B_MIXED"
_PATCH_NOOP="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a silently-lost restamp → rc 1"                  "1"    "$rc"
eq "…names the failing task id"                      "true" "$(has 'NOT verified: 9' "$ERR")"
eq "…reports the partial count"                      "true" "$(has 'only 1 of 2' "$ERR")"
eq "…states the definition IS recreated"             "true" "$(has 'IS recreated' "$ERR")"
eq "…states what the board's state now IS"           "true" "$(has 'carries NO search-index row' "$ERR")"
eq "…and that re-running retype will NOT finish it"  "true" "$(has 'will NOT do it' "$ERR")"

_seed "$_F_DL_NUM" "$_B_MIXED"
_PATCH_FAIL="9"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "a FAILING restamp PATCH → rc 1"                  "1"    "$rc"
eq "…names the failing PATCH separately"             "true" "$(has 'restamp PATCH failed on 1 card(s): 9' "$ERR")"
eq "…and still lists it as unverified"               "true" "$(has 'NOT verified: 9' "$ERR")"

echo "-- retype — the failure modes that must not strand the board --"
# An uncastable value is decided BEFORE the delete, so the board is left whole.
_seed "$_F_DL_STR" '[{"id":7,"payload":{"dl_number":"not-a-dl"}}]'
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number 2>&1 >/dev/null)" || rc=$?
eq "an uncastable value → rc 2"                      "2"    "$rc"
# The id must be named BY THE REFUSAL. A bare `has ": 7"` would also match the capture
# line and the unverified-list of a run that went ahead — i.e. it stays green with the
# refusal deleted (measured), so the needle carries the refusal's own wording.
eq "…names the task id holding it, in the refusal"   "true" \
   "$(has "cannot be cast to 'number': 7" "$ERR")"
eq "…says nothing has been mutated"                  "true" "$(has 'Nothing has been mutated' "$ERR")"
eq "…and no DELETE was issued"                       "0"    "$(_calls DELETE)"
# Likewise the definition: a COUNT of 1 survives a delete-then-recreate unchanged, so
# the assertion has to be on the TYPE, which is the thing the refusal protects.
eq "…and the definition still has its old type"      '"string"' "$(jq -c '.[0].type' "$_FIELDS")"

# Seeded from the STRING definition on purpose: against the number definition `--to
# number` would hit the already-target no-op first, so the zero-DELETE assertion would
# be carried by that no-op and stay green with this guard deleted (measured).
_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field dl_number --to number --restamp-dl 2>&1 >/dev/null)" || rc=$?
eq "--restamp-dl with a non-string target → rc 2"    "2"    "$rc"
eq "…and issues no request at all"                   "0"    "$(_calls DELETE)"

# The recreate failing after the delete is the one genuinely stranded state. It must
# name the state AND the exact command that finishes it — the remediation string is a
# doc surface, and here it is the only record of the label/options to restore.
_seed "$_F_DL_NUM" "$_B_MIXED"
_POST_FAIL=1
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "delete OK + recreate failed → rc 1"              "1"    "$rc"
eq "…says the field is DELETED and NOT recreated"    "true" "$(has 'is DELETED and was NOT recreated' "$ERR")"
eq "…names the surviving orphaned value count"       "true" "$(has '2 card payload value(s) survive' "$ERR")"
eq "…and prints the exact create that finishes it"   "true" \
   "$(has "field create --key dl_number --label 'DL Number' --type string" "$ERR")"
eq "…the board really is left without the field"     "0"    "$(jq 'length' "$_FIELDS")"

_seed "$_F_DL_NUM" "$_B_MIXED"
_FETCH_RC=4
rc=0; ERR="$(_kbc_field_retype --field dl_number --to string 2>&1 >/dev/null)" || rc=$?
eq "retype on an incomplete board read → rc 1"       "1"    "$rc"
eq "…and issues NO DELETE"                           "0"    "$(_calls DELETE)"

_seed "$_F_DL_STR" "$_B_MIXED"
rc=0; ERR="$(_kbc_field_retype --field nope --to number 2>&1 >/dev/null)" || rc=$?
eq "retype on an unresolved --field → rc 2"          "2"    "$rc"
eq "…enumerates the board's defined fields"          "true" "$(has 'defined fields' "$ERR")"
rc=0; _kbc_field_retype --field dl_number --to bogus >/dev/null 2>&1 || rc=$?
eq "retype to an unknown type → rc 2"                "2"    "$rc"
rc=0; _kbc_field_retype --to string >/dev/null 2>&1 || rc=$?
eq "retype with no --field → rc 2"                   "2"    "$rc"
rc=0; _kbc_field_delete >/dev/null 2>&1 || rc=$?
eq "delete with no --field → rc 2"                   "2"    "$rc"

_summary "kbcard-field-selftest"
