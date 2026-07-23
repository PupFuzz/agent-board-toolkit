#!/usr/bin/env bash
# kbcard-field-selftest.sh — deterministic, network-free unit checks for the
# `kbcard field` verb family (card #4939): `field list` (schema read + option
# projection) and `field set-options` (the idempotent converge-to-set reconcile).
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
#     lost-error-body defect class #4337 must not reappear on this path).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/kbcard"
_need -r "$BIN"
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines the field fns without running main()

_mktmp_scratch
# has <needle> <haystack> → true/false on a LITERAL substring match (robust against
# the JSON quotes/braces in captured output).
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

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

_summary "kbcard-field-selftest"
