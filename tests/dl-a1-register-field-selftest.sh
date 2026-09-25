#!/usr/bin/env bash
# dl-a1-register-field-selftest.sh — deterministic, network-free end-to-end checks for
# bin/dl-a1-register-field, which had ZERO test coverage while CREATING and DELETING a card on a
# live board.
#
# WHY THIS FILE EXISTS. Before it, `grep -rn dl-a1-register-field tests/` returned nothing. The
# tool registers the `dl_number` custom field and then real-surface-verifies the server's by-ref
# index by creating a THROWAWAY card carrying a sentinel dl_number, reading it back, clearing it
# and deleting it. Two claims in its own header were asserted by nothing:
#   * "One-shot, IDEMPOTENT … a re-run is a clean no-op" — the 409/422 arm that makes a re-run
#     succeed is the headline guarantee, and it is one `elif` away from a FATAL.
#   * "cleanup runs even if the verify failed … a leaked sentinel card would poison the DL
#     minter's max(dl_number) seed" — the EXIT trap that owns that is the least-exercised code in
#     the file, because it only runs on the failure paths.
# Neither failure announces itself: the tool's own header names the consequence of the second,
# and it is silent until a later mint reads the leaked value (card#5357).
#
# WHAT IS EXERCISED, and how. The bin is NOT main-guarded — sourcing it RUNS it — so it is driven
# as a PROCESS with `curl` stubbed on PATH (tests/_kb-api-stub.sh). The seam sits BELOW the lib,
# so kb_load_config, kb_api, kb_api_status, kb_by_ref_hit and the EXIT trap all run for real and
# the assertions are made against the HTTP requests the tool actually issued.
#
# THE REQUEST LOG IS THE WITNESS. Most of what matters here is what the tool did NOT do — did not
# create a card after a fatal registration, did not leave the throwaway behind, did not re-issue
# the teardown after a successful one. Each such assertion is paired with an observed non-zero
# count of a request from the SAME run, so "it never happened" is never confused with "the run
# never started". The stub logs every request before choosing a response and nothing under test
# can truncate that log.
#
# WHAT A GREEN RUN PROVES — the weakest property the assertions support: that against a faked
# kanban API the tool issues the documented request sequence, branches on the exact status codes
# its header names, and always attempts the throwaway teardown. It proves nothing about the real
# server: whether a real 409 is what a duplicate field registration returns, and whether the real
# by-ref index derives from payload.dl_number at all, is exactly what this tool exists to measure
# against a live board and cannot be established here.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"

A1="$HERE/../bin/dl-a1-register-field"
_need -x "$A1"

_mktmp_scratch --home
kb_stub_scrub_env
unset KB_A1_STAGE KB_A1_SWIMLANE KB_A1_SENTINEL KB_STAGE_BACKLOG
kb_stub_board_config dev     42 'export KB_STAGE_BACKLOG=51'
kb_stub_board_config alt     77 'export KB_STAGE_BACKLOG=51'   # proves --board routes
kb_stub_board_config nostage 88                                # no stage anywhere → refusal
kb_stub_install

export KB_STUB_TASK_ID=777
export KB_STUB_FOREIGN_ID=5
export KB_STUB_BYREF="hit miss miss"   # one answer per by-ref read, in order; the last repeats

USAGE='usage: dl-a1-register-field [--board NAME] [--stage ID] [--swimlane ID] [--sentinel N]'
SENTINEL_DEFAULT=999001
SENTINEL_DL_DEFAULT=DL-999001   # what the tool actually STAMPS: kb_dl_canon's output

# --- route table ------------------------------------------------------------------------------
# Prints "<http>\n<body>"; an unmatched request is answered 599 by the stub itself. The knobs are
# per-step so a scenario can fail exactly one leg: KB_STUB_REGISTER_HTTP, KB_STUB_CREATE_HTTP /
# KB_STUB_CREATE_BODY, KB_STUB_BYREF, KB_STUB_CLEAR_HTTP, KB_STUB_DELETE_HTTP.
REG_OK_BODY='{"data":{"id":9}}'
export REG_OK_BODY
kb_stub_route() {
    local method="$1" url="$2" data="$3" route_n="$4" http body
    local -a byref
    case "$method $url" in
        "GET "*/custom_fields.json)
            # The board's field INDEX — read only on the 409/422 arm, to decide whether the
            # pre-existing dl_number definition is the string-typed one this toolkit writes.
            # KB_STUB_FIELDS_HTTP fails the read; KB_STUB_FIELD_TYPE selects the declared type,
            # and the literal `none` stands for an index carrying no dl_number at all.
            http="${KB_STUB_FIELDS_HTTP:-200}"
            if [[ "$http" != 2* ]]; then
                printf '%s\n%s' "$http" '{"message":"nope"}'
            elif [[ "${KB_STUB_FIELD_TYPE:-string}" == none ]]; then
                printf '%s\n%s' "$http" '{"data":[{"id":8,"key":"pr_number","type":"number"}]}'
            else
                printf '%s\n%s' "$http" \
                    "{\"data\":[{\"id\":9,\"key\":\"dl_number\",\"type\":\"${KB_STUB_FIELD_TYPE:-string}\"}]}"
            fi ;;
        "POST "*/custom_fields.json)
            http="${KB_STUB_REGISTER_HTTP:-201}"
            if [[ "$http" == 2* ]]; then body="${KB_STUB_REGISTER_BODY:-$REG_OK_BODY}"
            else body='{"message":"the dl_number field already exists"}'; fi
            printf '%s\n%s' "$http" "$body" ;;
        "POST "*/tasks.json)
            body="${KB_STUB_CREATE_BODY:-}"
            [[ -n "$body" ]] || body="{\"data\":{\"id\":$KB_STUB_TASK_ID}}"
            printf '%s\n%s' "${KB_STUB_CREATE_HTTP:-201}" "$body" ;;
        "GET "*/tasks/by-ref.json*)
            # One answer per by-ref read, in order; the last repeats. `hit`/`miss` are the two
            # READABLE answers; the rest are the shapes a read can take that say NOTHING about
            # the index (card#10241).
            #
            # ⛔ THE UNDECODABLE `2xx` SHAPES ARE ENUMERATED RATHER THAN REPRESENTED — they do
            # not share one path and a single fixture would certify the others by association.
            # `html`, `trunc` and `nobody` never reach a jq verdict at all; `jsonerr` PARSES
            # PERFECTLY and is the one jq's own exit status cannot see — measured on jq 1.7, it
            # scored the pre-change predicate's rc 1, byte-identical to a genuinely empty
            # `{"data":[]}`, so a fix that only plumbed jq's rc outward would have left this
            # shape reading as a clean board. `trailing` is a complete `{"data":[]}` FOLLOWED by a
            # gateway's HTML: jq streams, so it printed the first text's ABSENT verdict before
            # faulting on the rest, and the fault was discarded. `http500` is a producer of the
            # same state from a different layer: the request was ANSWERED and not with a 2xx.
            read -r -a byref <<<"$KB_STUB_BYREF"
            case "${byref[$((route_n - 1))]:-${byref[-1]}}" in
                hit)     printf '%s\n%s' 200 "{\"data\":[{\"id\":$KB_STUB_TASK_ID}]}" ;;
                miss)    printf '%s\n%s' 200 '{"data":[]}' ;;
                # READABLE answers naming a card that is NOT this run's throwaway — the shape a
                # sentinel card leaked by an earlier run's failed teardown takes (card#10426).
                # `both` carries the throwaway AND the foreign card; the foreign id is pinned so
                # an assertion can require the tool to NAME it.
                foreign) printf '%s\n%s' 200 "{\"data\":[{\"id\":$KB_STUB_FOREIGN_ID}]}" ;;
                both)    printf '%s\n%s' 200 "{\"data\":[{\"id\":$KB_STUB_TASK_ID},{\"id\":$KB_STUB_FOREIGN_ID}]}" ;;
                html)    printf '%s\n%s' 200 '<html><body>502 Bad Gateway</body></html>' ;;
                trunc)   printf '%s\n%s' 200 "{\"data\":[{\"id\":$KB_STUB_TASK_ID" ;;
                jsonerr) printf '%s\n%s' 200 '{"message":"your session has expired"}' ;;
                nobody)  printf '%s\n%s' 200 '' ;;
                trailing) printf '%s\n%s' 200 '{"data":[]}<html><body>502 Bad Gateway</body></html>' ;;
                http500) printf '%s\n%s' 500 '{"message":"nope"}' ;;
                # The stub's TRANSPORT-failure spelling (tests/_kb-api-stub-curl.sh): curl exits
                # with that status having written nothing, so no HTTP status is read at all.
                curlfail) printf '!curl 7' ;;
                # A knob value this route does not know answers LOUDLY rather than plausibly:
                # 599 is outside every arm the tool branches on, so a typo in a scenario reds
                # the scenario instead of quietly re-running one of the arms above.
                *)       printf '%s\n%s' 599 '{"message":"unknown KB_STUB_BYREF token"}' ;;
            esac ;;
        "PATCH "*/tasks/*)
            # The two teardown writes are distinguished by their bodies, not their URLs — they
            # target the same card — so a scenario can fail the clear without failing the delete.
            if [[ "$data" == *'"_action"'* ]]; then http="${KB_STUB_DELETE_HTTP:-200}"
            else http="${KB_STUB_CLEAR_HTTP:-200}"; fi
            if [[ "$http" == 2* ]]; then body='{"data":{"id":0}}'
            else body='{"message":"refused"}'; fi
            printf '%s\n%s' "$http" "$body" ;;
    esac
}
export -f kb_stub_route

# run_a1 <args…> — invoke the real bin against a FRESH request log, capturing rc/out/err.
# Scenario knobs are passed as an assignment PREFIX on this call. Measured on bash 5.2: the
# assignment is exported for the duration of the call and the caller's previous value is restored
# afterwards, so a knob cannot leak into a later case.
run_a1() {
    kb_stub_reset
    rc=0
    out="$("$A1" "$@" 2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
}
REGISTER=(POST /custom_fields.json)
CREATE=(POST /tasks.json)
BYREF=(GET /tasks/by-ref.json)
TEARDOWN=(PATCH /tasks/777.json)

# ---------------------------------------------------------------------------
echo "== happy path: register → create → verify → clear → delete → prove no residue =="
run_a1
eq "happy path → rc 0"                    "0" "$rc"
eq "registration reports the new field id" "true" "$(has 'registered dl_number as a STRING field (field id 9)' "$out")"
eq "the throwaway is announced with the CANONICAL sentinel it stamped" "true" \
   "$(has "throwaway card 777 created with dl_number=$SENTINEL_DL_DEFAULT" "$out")"
eq "by-ref resolves the throwaway"        "true" "$(has "by-ref system=dl ref=$SENTINEL_DEFAULT: FOUND (card 777)" "$out")"
eq "by-ref is empty once dl_number is cleared" "true" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT empty" "$out")"
eq "the throwaway is reported deleted"    "true" "$(has 'throwaway 777 deleted' "$out")"
eq "the acceptance line claims zero residue" "true" "$(has 'zero residue' "$out")"
eq "the run ends OK"                      "true" "$(has 'OK (field registered + by-ref verified + throwaway removed)' "$out")"

echo "== …and the request sequence is exactly the documented one =="
eq "one field registration"               "1" "$(kb_stub_count "${REGISTER[@]}")"
eq "one throwaway created"                "1" "$(kb_stub_count "${CREATE[@]}")"
eq "three by-ref reads (verify, after-clear, after-delete)" "3" "$(kb_stub_count "${BYREF[@]}")"
eq "two teardown writes (clear, delete)"  "2" "$(kb_stub_count "${TEARDOWN[@]}")"
# The EXIT trap re-issues the clear+delete pair unless the explicit delete already succeeded. The
# count above is that assertion: 2, not 4. Its witness is that those 2 writes are present at all.
eq "the EXIT trap did NOT re-issue the teardown after a successful one" "2" \
   "$(kb_stub_count "${TEARDOWN[@]}")"
eq "every by-ref read carries system=dl and the sentinel" "3" \
   "$(kb_stub_count GET "by-ref.json?system=dl&ref=$SENTINEL_DEFAULT")"
eq "the board id reaches every board-scoped path" "4" "$(kb_stub_count_any /boards/42/)"

echo "== the bodies the tool puts on the wire =="
# THE TYPE IS THE ASSERTION, not decoration on one. Every toolkit write of dl_number is the
# canonical DL-NNNN string (kb_dl_canon), and kanban validates a payload value against the
# field's DECLARED type — so a `number` here is a board that 422s "Must be a number." on every
# `kbcard --dl`, which is exactly what this literal used to say (card#6517).
eq "the registration body declares dl_number as a STRING field" \
   '{"key":"dl_number","label":"DL","type":"string"}' "$(kb_stub_bodies "${REGISTER[@]}")"
CREATE_BODY="$(kb_stub_bodies "${CREATE[@]}")"
eq "the throwaway targets the configured board"    "42" "$(jq -r '.board_id' <<<"$CREATE_BODY")"
eq "the throwaway lands in the configured stage"   "51" "$(jq -r '.workflow_stage_id' <<<"$CREATE_BODY")"
# ABSENT, not null, and not a fabricated id. A board that defines no swimlanes refuses
# `swimlane_id: 1` with
# `422 The selected swimlane is not on this board.`, and there is no id the caller could pass
# instead, so the tool's own documented setup step could not run at all (card#7464). `has()`
# is the assertion because it is the ONE test that separates an omitted key from a null-valued
# one; `jq -r '.swimlane_id'` prints `null` for both and would pass over either.
eq "no --swimlane ⇒ the create body carries NO swimlane_id key at all" "false" \
   "$(jq -c 'has("swimlane_id")' <<<"$CREATE_BODY")"
eq "the throwaway carries payload.dl_number = the CANONICAL DL-NNNN sentinel" "$SENTINEL_DL_DEFAULT" \
   "$(jq -r '.payload.dl_number' <<<"$CREATE_BODY")"
# This step is the setup path's ONLY acceptance test, so the value shape it puts on the wire has
# to be the shape production puts on the wire. While it was a JSON NUMBER it tested the one shape
# no toolkit writer produces, and it passed on a board where every real --dl write was rejected.
eq "the sentinel is a JSON string, as every production dl_number write is" "string" \
   "$(jq -r '.payload.dl_number | type' <<<"$CREATE_BODY")"
eq "the throwaway names itself as disposable"      "[A1-verify] dl_number throwaway — delete me" \
   "$(jq -r '.name' <<<"$CREATE_BODY")"
# The v0.20.0 flat-body cutover, asserted on the WIRE. tests/no-task-wrapper-selftest.sh scans the
# source text for the wrapper's three re-introduction shapes; this pins what is actually sent.
eq "the create body is FLAT (no {task:{…}} envelope)" "false" "$(jq -c 'has("task")' <<<"$CREATE_BODY")"
eq "the teardown clears dl_number first, then deletes" \
   '{"payload":{"dl_number":null}}
{"_action":"delete"}' "$(kb_stub_bodies "${TEARDOWN[@]}")"

# ---------------------------------------------------------------------------
echo "== idempotence: a re-run against an already-registered field still succeeds =="
# The headline "a re-run is a clean no-op" guarantee. 409 and 422 are asserted separately because
# they are separate literals in the arm, and dropping either would leave the other passing.
KB_STUB_REGISTER_HTTP=409 run_a1
eq "409 → rc 0 (idempotent success, not a fatal)" "0" "$rc"
eq "409 is reported as already-registered, with the type it read back" "true" \
   "$(has 'dl_number already registered, STRING-typed (HTTP 409) — idempotent OK' "$out")"
eq "409 still runs the whole verification"        "true" "$(has 'zero residue' "$out")"
eq "409 still created and removed a throwaway"    "2" "$(kb_stub_count "${TEARDOWN[@]}")"
eq "409 READ the board's field index before claiming the board is set up" "1" \
   "$(kb_stub_count GET /custom_fields.json)"
KB_STUB_REGISTER_HTTP=422 run_a1
eq "422 → rc 0 (idempotent success, not a fatal)" "0" "$rc"
eq "422 is reported as already-registered, with the type it read back" "true" \
   "$(has 'dl_number already registered, STRING-typed (HTTP 422) — idempotent OK' "$out")"
# The witness for the zeros in the block below: the SAME arm, over a string-typed definition,
# does create and tear down a throwaway. Without it "no card was created" could pass because
# the arm never ran at all.
eq "witness: a string-typed pre-existing definition DOES reach the create" "1" \
   "$(kb_stub_count "${CREATE[@]}")"

echo "== …but a pre-existing definition of the WRONG TYPE is refused, not certified (card#6517) =="
# The defect this closes: the 409/422 arm reported "idempotent OK" on the strength of the STATUS
# alone, which says the key is taken and nothing about the type it was taken with. A number-typed
# dl_number rejects every `kbcard --dl` write with 422 "Must be a number.", and this tool — the
# only surface positioned to catch that — had already declared the board set up.
for wrong_http in 409 422; do
    KB_STUB_REGISTER_HTTP=$wrong_http KB_STUB_FIELD_TYPE=number run_a1
    eq "HTTP $wrong_http over a NUMBER-typed dl_number → rc 1" "1" "$rc"
    eq "…the refusal names the declared type and the required one" "true" \
       "$(has "declares dl_number as 'number', and it must be 'string'" "$err")"
    eq "…and names the 422 the board would answer every --dl write with" "true" \
       "$(has 'Must be a number.' "$err")"
    eq "…and prints the in-place remedy as a runnable command" "true" \
       "$(has 'kbcard field retype --field dl_number --to string --restamp-dl' "$err")"
    eq "…NO throwaway card was created" "0" "$(kb_stub_count "${CREATE[@]}")"
    eq "…and nothing was torn down (there is nothing to tear down)" "0" "$(kb_stub_count PATCH /tasks/)"
    eq "…witness: the registration and the index read both happened" "2" \
       "$(( $(kb_stub_count "${REGISTER[@]}") + $(kb_stub_count GET /custom_fields.json) ))"
done
# The remedy command carries the run's OWN --board, so it targets the board this run targeted
# rather than the default one.
KB_STUB_REGISTER_HTTP=409 KB_STUB_FIELD_TYPE=number run_a1 --board alt
eq "the remedy on a --board run names that board" "true" \
   "$(has 'kbcard --board alt field retype --field dl_number --to string --restamp-dl' "$err")"
# Any non-string type, not a number special case.
KB_STUB_REGISTER_HTTP=409 KB_STUB_FIELD_TYPE=enum run_a1
eq "an ENUM-typed dl_number is refused too → rc 1" "1" "$rc"
eq "…naming the type it actually found" "true" "$(has "declares dl_number as 'enum'" "$err")"

echo "== an already-registered claim this tool cannot VERIFY is refused, not assumed =="
KB_STUB_REGISTER_HTTP=409 KB_STUB_FIELDS_HTTP=500 run_a1
eq "an unreadable field index on the 409 arm → rc 1" "1" "$rc"
eq "…and says the existing declaration's type is UNKNOWN, not OK" "true" \
   "$(has "the EXISTING declaration's type is unknown" "$err")"
eq "…creating no throwaway over a board it could not read" "0" "$(kb_stub_count "${CREATE[@]}")"
# A 409/422 whose index carries no dl_number at all is not "already registered" — it is a
# registration that failed for some other reason, and it used to be reported as a success.
KB_STUB_REGISTER_HTTP=422 KB_STUB_FIELD_TYPE=none run_a1
eq "a 422 with no dl_number in the index → rc 1" "1" "$rc"
eq "…and says so rather than claiming idempotence" "true" \
   "$(has 'carries NO dl_number definition' "$err")"
eq "…and echoes the body it was refused with" "true" "$(has 'the dl_number field already exists' "$err")"
eq "…creating no throwaway" "0" "$(kb_stub_count "${CREATE[@]}")"

echo "== a registration failure that is NOT 409/422 is fatal, and creates nothing =="
KB_STUB_REGISTER_HTTP=500 run_a1
eq "500 on register → rc 1"               "1" "$rc"
eq "the fatal names the REGISTER step and its status" "true" "$(has 'FATAL register: HTTP 500' "$err")"
eq "no throwaway was created"             "0" "$(kb_stub_count "${CREATE[@]}")"
eq "no teardown was attempted (there is nothing to tear down)" "0" "$(kb_stub_count "${TEARDOWN[@]}")"
eq "witness: the registration WAS attempted" "1" "$(kb_stub_count "${REGISTER[@]}")"

# ---------------------------------------------------------------------------
echo "== the throwaway is torn down even when the verification FAILS =="
# A leaked sentinel card poisons the DL minter's max(dl_number) seed, so teardown is
# unconditional. This is the case the header promises and the trap exists for.
KB_STUB_BYREF="miss miss miss" run_a1
eq "by-ref never resolving → rc 1"        "1" "$rc"
eq "the miss is reported"                 "true" "$(has "by-ref system=dl ref=$SENTINEL_DEFAULT: NOT FOUND" "$err")"
eq "the verdict names both flags"         "true" "$(has 'verification failed (found=0 still_present=0)' "$err")"
eq "the throwaway was still cleared and deleted" "2" "$(kb_stub_count "${TEARDOWN[@]}")"
eq "the delete really was issued"         "true" "$(has '{"_action":"delete"}' "$(kb_stub_bodies "${TEARDOWN[@]}")")"

echo "== a dl_number that survives the clear is reported, not swallowed =="
KB_STUB_BYREF="hit hit miss" run_a1
eq "still-present after clear → rc 1"     "1" "$rc"
eq "the still-present state is named"     "true" "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT STILL PRESENT" "$err")"
eq "the verdict carries still_present=1"  "true" "$(has 'verification failed (found=1 still_present=1)' "$err")"
eq "the throwaway was still deleted"      "2" "$(kb_stub_count "${TEARDOWN[@]}")"

echo "== residue after the delete is a failure, however clean the earlier steps looked =="
KB_STUB_BYREF="hit miss hit" run_a1
eq "residue after delete → rc 1"          "1" "$rc"
eq "the residue is named with the card id" "true" "$(has 'residue — by-ref still resolves 777 after delete' "$err")"
eq "residue is decided AFTER the delete (3 reads happened)" "3" "$(kb_stub_count "${BYREF[@]}")"
eq "residue never prints the zero-residue acceptance" "false" "$(has 'zero residue' "$out")"

# ---------------------------------------------------------------------------
echo "== a by-ref read that MEASURED NOTHING is rc 3 UNMEASURED, never a pass (card#10241) =="
# THE DEFECT. Two of this tool's three by-ref dispositions treat a non-hit as their PASS
# condition — `after clear: … empty` and `zero residue` — and every unreadable answer arrived at
# them as a non-hit, so a board behind an SSO gateway, a WAF or a maintenance page (each of which
# answers 200 with HTML) was CERTIFIED: both pass lines printed, exit 0, nothing measured. The
# caller of a setup tool has to be able to tell "I checked and it is clean" from "I could not
# check", so those are now different exit codes and different lines.
#
# THE POPULATION IS (undecodable shape × read position), not one of each. The shapes are the
# undecodable tokens `kb_stub_route` above answers, and the positions are this tool's three by-ref
# reads, because the dispositions differ per position: position 1's non-hit was already a reported
# FAILURE, while 2 and 3 were the fail-open pair. Every SCENARIO (shape × position) below has at
# least one row observed RED against the pre-change binary over the identical fixtures. Not every
# row is: the teardown rows and the "no OK verdict" rows hold of the pre-change binary too, and are
# there to pin that the new arm did not lose them. The control is the block after the loop: the
# same positions, answered readably, still pass.
for shape in html trunc jsonerr nobody trailing http500; do
    # Position 1 — the verify. A non-hit here was always non-fatal-but-reported; what changes is
    # that the tool no longer reports NOT FOUND, which is a claim about the index, for a read
    # that never happened.
    KB_STUB_BYREF="$shape miss miss" run_a1
    eq "[$shape] undecodable at the VERIFY read → rc 3, not 0 and not 1" "3" "$rc"
    eq "[$shape] …the verify line says UNMEASURED"  "true" \
       "$(has "by-ref system=dl ref=$SENTINEL_DEFAULT: UNMEASURED" "$err")"
    eq "[$shape] …and never claims NOT FOUND"       "false" \
       "$(has "by-ref system=dl ref=$SENTINEL_DEFAULT: NOT FOUND" "$err")"
    eq "[$shape] …the verdict names the read that measured nothing" "true" \
       "$(has 'UNMEASURED — the by-ref read(s) verify' "$err")"
    eq "[$shape] …and never claims the route is verified" "false" \
       "$(has 'OK (field registered' "$out")"
    eq "[$shape] …the throwaway is still cleared and deleted" "2" "$(kb_stub_count "${TEARDOWN[@]}")"

    # Position 2 — after the clear. THE FAIL-OPEN: `empty` is the pass condition.
    KB_STUB_BYREF="hit $shape miss" run_a1
    eq "[$shape] undecodable AFTER THE CLEAR → rc 3" "3" "$rc"
    eq "[$shape] …and the after-clear line does NOT say empty" "false" \
       "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT empty" "$out")"
    eq "[$shape] …it says UNMEASURED"               "true" \
       "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT UNMEASURED" "$err")"
    eq "[$shape] …the verdict names that read"      "true" \
       "$(has 'UNMEASURED — the by-ref read(s) after-clear' "$err")"
    eq "[$shape] …and the still_present column says UNMEASURED, not 0" "true" \
       "$(has 'still_present=UNMEASURED' "$err")"

    # Position 3 — the acceptance. THE OTHER FAIL-OPEN: `zero residue` is a POSITIVE claim about
    # the board, and it may only be made from a read that succeeded.
    KB_STUB_BYREF="hit miss $shape" run_a1
    eq "[$shape] undecodable at the ACCEPTANCE read → rc 3" "3" "$rc"
    eq "[$shape] …NO zero-residue claim is printed"  "false" "$(has 'zero residue' "$out")"
    eq "[$shape] …the acceptance line says UNMEASURED" "true" \
       "$(has "acceptance: by-ref ref=$SENTINEL_DEFAULT UNMEASURED" "$err")"
    eq "[$shape] …and the run still deleted the throwaway" "true" \
       "$(has 'throwaway 777 deleted' "$out")"

    # All three unreadable — the whole run measured nothing, and says so once per read.
    KB_STUB_BYREF="$shape $shape $shape" run_a1
    eq "[$shape] every by-ref read undecodable → rc 3" "3" "$rc"
    eq "[$shape] …all three reads are named in the verdict" "true" \
       "$(has 'the by-ref read(s) verify after-clear acceptance' "$err")"
    eq "[$shape] …with no zero-residue claim on stdout"  "false" "$(has 'zero residue' "$out")"
    eq "[$shape] …and no OK verdict on stdout"           "false" "$(has 'OK (field registered' "$out")"
    eq "[$shape] …and the teardown still ran" "2" "$(kb_stub_count "${TEARDOWN[@]}")"
done
# THE CONTROL, at each of the three positions: the identical harness, answered READABLY, still
# reaches the pass lines and rc 0. Without it every row above could be passing because the tool
# refuses everything.
KB_STUB_BYREF="hit miss miss" run_a1
eq "control: readable answers at all three positions → rc 0" "0" "$rc"
eq "control: …the after-clear line reads empty"  "true" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT empty" "$out")"
eq "control: …the acceptance claims zero residue" "true" "$(has 'zero residue' "$out")"

# ⛔ THE PRODUCER IS NAMED, not folded into one "could not read" sentence, because the three lead
# an operator to three different next actions — and this tool is the only surface that can say
# which: KB_API_QUIET=1 keeps the lib's own non-2xx line off stderr, and KB_HTTP does not cross
# the `$(…)` the body capture needs, so nothing else in the run carries it.
KB_STUB_BYREF="html miss miss" run_a1
eq "an undecodable 2xx blames the BODY"        "true"  "$(has 'NOT a by-ref result' "$err")"
eq "…and not the status"                       "false" "$(has 'not with a 2xx' "$err")"
KB_STUB_BYREF="http500 miss miss" run_a1
eq "a non-2xx blames the STATUS"               "true"  "$(has 'ANSWERED the by-ref read and not with a 2xx' "$err")"
eq "…and not the body"                         "false" "$(has 'NOT a by-ref result' "$err")"
KB_STUB_BYREF="curlfail miss miss" run_a1
eq "a request that never completed → rc 3"     "3"     "$rc"
eq "…and says no HTTP status came back at all" "true"  "$(has 'DID NOT COMPLETE' "$err")"
eq "…and blames neither the status nor the body" "false" \
   "$(has 'ANSWERED the by-ref read' "$err")"
# The cause does not leak from an earlier read into a later one: the verify is readable here and
# the acceptance is not, so the acceptance line must carry the acceptance's own producer.
KB_STUB_BYREF="hit miss http500" run_a1
eq "the acceptance line carries ITS OWN cause" "true" \
   "$(has "acceptance: by-ref ref=$SENTINEL_DEFAULT UNMEASURED — the server ANSWERED" "$err")"

# ⭐ THE DISCRIMINATOR, stated as an assertion rather than as prose: a MEASURED failure and an
# unmeasured read are different exit codes, so a caller can act on the difference. Both are
# non-zero, which is why the ordering below is free — when a run sees both, the measured failure
# outranks (bin/run-coverage-check's MISSING-outranks-UNMEASURED ruling).
KB_STUB_BYREF="miss miss miss" run_a1
eq "a MEASURED miss is still rc 1, not rc 3" "1" "$rc"
eq "…and reports a verification failure, not an unmeasured one" "true" \
   "$(has 'verification failed (found=0 still_present=0)' "$err")"
eq "…and never prints the UNMEASURED verdict" "false" "$(has 'dl-a1-register-field: UNMEASURED' "$err")"
KB_STUB_BYREF="hit hit html" run_a1
eq "a measured STILL-PRESENT beside an unmeasured acceptance → rc 1" "1" "$rc"
eq "…the verdict states the measured failure" "true" \
   "$(has 'verification failed (found=1 still_present=1)' "$err")"
KB_STUB_BYREF="html miss hit" run_a1
eq "a measured RESIDUE beside an unmeasured verify → rc 1" "1" "$rc"
eq "…and names the residue, which is the stronger true statement" "true" \
   "$(has 'residue — by-ref still resolves 777 after delete' "$err")"

# ---------------------------------------------------------------------------
echo "== a by-ref hit on a DIFFERENT card is residue, never 'empty' (card#10426) =="
# The after-clear and acceptance reads ask whether the SENTINEL still resolves, not whether it
# resolves to THIS run's throwaway. A card an earlier run's failed teardown leaked still carries
# the sentinel and poisons the minter's max(dl_number) seed exactly as this run's own would — so
# reading "not my card" as "empty" printed both pass lines and exited 0 over the very state this
# tool exists to rule out.
# The foreign card is NOT this run's to write: it may be a real card whose DL collides with the
# sentinel. Zero requests of ANY method to its task path, beside the throwaway's own teardown.
FOREIGN_TASK="/tasks/$KB_STUB_FOREIGN_ID.json"
LEAK_LINE="card $KB_STUB_FOREIGN_ID is NOT this run's throwaway (777)"
KB_STUB_BYREF="hit foreign miss" run_a1
eq "a foreign card AFTER THE CLEAR → rc 1"        "1" "$rc"
eq "…the foreign card receives ZERO writes"     "0" "$(kb_stub_count_any "$FOREIGN_TASK")"
eq "…the after-clear line does NOT say empty"     "false" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT empty" "$out")"
eq "…it names the foreign card"                   "true" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT STILL PRESENT — resolves card(s) 5" "$err")"
eq "…the verdict reports still_present=1"         "true" \
   "$(has 'verification failed (found=1 still_present=1)' "$err")"
eq "…and the run never prints OK"                 "false" "$(has 'OK (field registered' "$out")"
eq "…the throwaway is still cleared and deleted"  "2" "$(kb_stub_count "${TEARDOWN[@]}")"

KB_STUB_BYREF="hit miss foreign" run_a1
eq "a foreign card at the ACCEPTANCE read → rc 1" "1" "$rc"
eq "…the foreign card receives ZERO writes"     "0" "$(kb_stub_count_any "$FOREIGN_TASK")"
eq "…NO zero-residue claim is printed"            "false" "$(has 'zero residue' "$out")"
eq "…the residue line names the foreign card"     "true" \
   "$(has 'residue — by-ref still resolves 5 after delete' "$err")"
eq "…and the run never prints OK"                 "false" "$(has 'OK (field registered' "$out")"

# The card's reproduction, verbatim: the foreign id at BOTH residue reads.
KB_STUB_BYREF="hit foreign foreign" run_a1
eq "a foreign card at both residue reads → rc 1"  "1" "$rc"
eq "…the foreign card receives ZERO writes"     "0" "$(kb_stub_count_any "$FOREIGN_TASK")"
eq "…no after-clear 'empty' line"                 "false" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT empty" "$out")"
eq "…no zero-residue claim"                       "false" "$(has 'zero residue' "$out")"
eq "…the foreign card is named, with the command to inspect it" "true" \
   "$(has 'kbcard show --task 5' "$err")"
eq "…named ONCE though both residue reads saw it" "1" \
   "$(grep -cF "$LEAK_LINE" <<<"$err")"
eq "…the advice does not prescribe deleting a possibly-real card" "true" \
   "$(has 're-run with a different --sentinel' "$err")"

# Own AND foreign in one answer: both are named, so the operator does not delete the throwaway
# and walk away from the leaked card.
KB_STUB_BYREF="hit both miss" run_a1
eq "own + foreign AFTER THE CLEAR → rc 1"         "1" "$rc"
eq "…the foreign card receives ZERO writes"     "0" "$(kb_stub_count_any "$FOREIGN_TASK")"
eq "…both cards are named"                        "true" \
   "$(has "after clear: by-ref ref=$SENTINEL_DEFAULT STILL PRESENT — resolves card(s) 777 5" "$err")"
eq "…the after-clear read reports the foreign card as a leak" "true" "$(has "$LEAK_LINE" "$err")"
eq "…and never reports this run's OWN throwaway as a leak" "false" \
   "$(has "card 777 is NOT" "$err")"
KB_STUB_BYREF="hit miss both" run_a1
eq "own + foreign at ACCEPTANCE → rc 1"           "1" "$rc"
eq "…the foreign card receives ZERO writes"     "0" "$(kb_stub_count_any "$FOREIGN_TASK")"
eq "…both cards are named"                        "true" \
   "$(has 'residue — by-ref still resolves 777 5 after delete' "$err")"

# THE CONTROL: the same positions answered with an EMPTY result still pass, so the rows above
# are not passing because the tool now refuses every run.
KB_STUB_BYREF="hit miss miss" run_a1
eq "control: empty residue reads → rc 0"          "0" "$rc"
eq "control: …and the OK verdict"                 "true" "$(has 'OK (field registered' "$out")"

# ---------------------------------------------------------------------------
echo "== the EXIT trap fires when a teardown step itself fails =="
# The clear PATCH fails, so the script exits 1 at its own FATAL — BEFORE the explicit delete.
# `cleanup_done` is still 0, so the trap must re-issue the pair; the delete is what stops the
# sentinel leaking. Without the trap this run would leave a live sentinel card behind.
KB_STUB_CLEAR_HTTP=500 run_a1
eq "a failing clear → rc 1"               "1" "$rc"
eq "the fatal names the CLEAR step and its status" "true" "$(has 'FATAL clearing dl_number: HTTP 500' "$err")"
eq "the trap re-issued the pair (1 failed clear + 2 trap writes)" "3" "$(kb_stub_count "${TEARDOWN[@]}")"
eq "the trap DID issue the delete"        "1" \
   "$(kb_stub_bodies "${TEARDOWN[@]}" | grep -c '"_action":"delete"' || true)"
# The trap's own two writes, in order. Clearing before deleting is not cosmetic: `_action:delete`
# is a recoverable soft delete, so a card removed while still carrying dl_number keeps the value
# the minter seeds from. The pair must land clear-then-delete on the trap path too.
eq "the trap clears dl_number BEFORE deleting" \
   '{"payload":{"dl_number":null}}
{"_action":"delete"}' "$(kb_stub_bodies "${TEARDOWN[@]}" | tail -2)"
eq "the run died before the second by-ref read" "1" "$(kb_stub_count "${BYREF[@]}")"
# KB_API_QUIET=1 is set so the callers own the wording. The lib's generic line would otherwise
# sit beside the FATAL above saying the same thing in weaker terms.
eq "KB_API_QUIET keeps the lib's own HTTP line off stderr" "false" \
   "$(has 'dl-a1-register-field: HTTP 500 on PATCH' "$err")"

echo "== a failing delete is reported, and retried by the trap =="
KB_STUB_DELETE_HTTP=500 run_a1
eq "a failing delete → rc 1"              "1" "$rc"
eq "the fatal names the DELETE step and its status" "true" "$(has 'FATAL deleting throwaway: HTTP 500' "$err")"
eq "the delete was attempted twice (explicit, then the trap)" "2" \
   "$(kb_stub_bodies "${TEARDOWN[@]}" | grep -c '"_action":"delete"' || true)"
eq "the run never claimed the throwaway was deleted" "false" "$(has 'throwaway 777 deleted' "$out")"

# ---------------------------------------------------------------------------
echo "== a throwaway that cannot be created is fatal, and leaves nothing behind =="
KB_STUB_CREATE_HTTP=422 run_a1
eq "a failing create → rc 1"              "1" "$rc"
eq "the fatal declines to claim a status it cannot see" "true" \
   "$(has 'FATAL create throwaway (non-2xx or curl error)' "$err")"
# Counted against ANY /tasks/ write, not just card 777's: with both create-side guards gone the
# trap is armed over an EMPTY task id and tears down `/tasks/.json`, which a card-specific count
# would miss entirely.
eq "no teardown was attempted (the trap is armed AFTER the create)" "0" "$(kb_stub_count PATCH /tasks/)"
eq "witness: the create WAS attempted"    "1" "$(kb_stub_count "${CREATE[@]}")"

KB_STUB_CREATE_BODY='{"data":{"noid":1}}' run_a1
eq "a create response with no task id → rc 1" "1" "$rc"
eq "the fatal names the missing id"       "true" "$(has 'FATAL create throwaway: no task id in response' "$err")"
eq "no teardown was attempted against an unknown card" "0" "$(kb_stub_count PATCH /tasks/)"
eq "witness: the no-id create WAS attempted" "1" "$(kb_stub_count "${CREATE[@]}")"

# ---------------------------------------------------------------------------
echo "== the flags are read, not decorative =="
run_a1 --stage 88 --swimlane 5 --sentinel 424242
eq "explicit flags → rc 0"                "0" "$rc"
CREATE_BODY="$(kb_stub_bodies "${CREATE[@]}")"
eq "--stage reaches the throwaway"        "88"     "$(jq -r '.workflow_stage_id' <<<"$CREATE_BODY")"
eq "--swimlane reaches the throwaway"     "5"      "$(jq -r '.swimlane_id' <<<"$CREATE_BODY")"
# The witness for the absence assertion above: the key DOES ride when a lane is named, so
# "no key" cannot pass because the tool stopped emitting one entirely.
eq "--swimlane puts the key ON the body"  "true"   "$(jq -c 'has("swimlane_id")' <<<"$CREATE_BODY")"
eq "--swimlane rides as a JSON number, not a string" "number" \
   "$(jq -r '.swimlane_id | type' <<<"$CREATE_BODY")"
eq "--sentinel reaches the payload"       "DL-424242" "$(jq -r '.payload.dl_number' <<<"$CREATE_BODY")"
eq "--sentinel reaches the by-ref query"  "3"      "$(kb_stub_count GET 'ref=424242')"

KB_A1_STAGE=61 KB_A1_SWIMLANE=7 KB_A1_SENTINEL=555001 run_a1
eq "the KB_A1_* env defaults → rc 0"      "0" "$rc"
CREATE_BODY="$(kb_stub_bodies "${CREATE[@]}")"
eq "KB_A1_STAGE is honoured over KB_STAGE_BACKLOG" "61" "$(jq -r '.workflow_stage_id' <<<"$CREATE_BODY")"
eq "KB_A1_SWIMLANE is honoured"           "7"         "$(jq -r '.swimlane_id' <<<"$CREATE_BODY")"
eq "KB_A1_SWIMLANE puts the key ON the body" "true"   "$(jq -c 'has("swimlane_id")' <<<"$CREATE_BODY")"
eq "KB_A1_SENTINEL is honoured"           "DL-555001" "$(jq -r '.payload.dl_number' <<<"$CREATE_BODY")"
KB_A1_STAGE=61 run_a1 --stage 88
eq "an explicit --stage beats KB_A1_STAGE" "88" "$(jq -r '.workflow_stage_id' <<<"$(kb_stub_bodies "${CREATE[@]}")")"
KB_A1_SWIMLANE=7 run_a1 --swimlane 5
eq "an explicit --swimlane beats KB_A1_SWIMLANE" "5" "$(jq -r '.swimlane_id' <<<"$(kb_stub_bodies "${CREATE[@]}")")"

run_a1 --board alt
eq "--board alt → rc 0"                   "0" "$rc"
eq "--board alt talks to board 77"        "4" "$(kb_stub_count_any /boards/77/)"
eq "--board alt never touches the default board" "0" "$(kb_stub_count_any /boards/42/)"

# ---------------------------------------------------------------------------
echo "== the argument surface refuses before it touches the board =="
run_a1 --help
eq "--help → rc 0"                        "0" "$rc"
eq "--help prints the usage line"         "$USAGE" "$out"
eq "--help issues no request"             "0" "$(kb_stub_total)"
run_a1 -h
eq "-h → rc 0"                            "0" "$rc"
eq "-h prints the same usage"             "$USAGE" "$out"

# Every value-taking flag, in BOTH short forms — explicitly empty and missing-because-trailing.
# The two are separate inputs (a guard dispatching on the flag being SEEN would keep one green),
# and each refusal must name ITS OWN flag: this tool takes four, so the usage line alone told the
# operator only that one of them was short. The expected string is built per flag, so a guard
# that named a hardcoded flag for all four reds on three of them.
# The population is DERIVED from the bin, not typed here (card#6645). A hand list cannot go red
# when the bin grows a flag, so a totality claim made over one narrows silently with every
# release — measured on this repo: `promote-stage-guard-selftest` named five of
# `promote-released-cards`' six guarded flags for two minor versions under the same claim.
# `expect_value_flags` compares the list below against the bin's own guard call sites and reds
# in both directions, so this block's claim cannot outlive the population it is about.
VALUE_FLAGS=(--board --stage --swimlane --sentinel)
expect_value_flags "$A1" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
    NO_VALUE="dl-a1-register-field: $f requires a non-empty value"
    run_a1 "$f" ""
    eq "$f with an empty value → rc 2"    "2" "$rc"
    eq "$f empty-value refusal names $f itself" "$NO_VALUE" "$err"
    eq "$f empty value issues no request" "0" "$(kb_stub_total)"
    run_a1 "$f"
    eq "a trailing $f with no argument → rc 2" "2" "$rc"
    eq "a trailing $f is refused identically to an empty one" "$NO_VALUE" "$err"
    eq "a trailing $f does not leak an unbound-variable error" "false" "$(has 'unbound variable' "$err")"
done
# Only the EMPTY form carries an "issues no request" zero. Measured on the sibling tool with its
# guard deleted outright: a TRAILING flag still reaches no request, because the arg loop's closing
# `shift` fails on an exhausted stack and `set -e` ends the run first. That zero cannot be made to
# fail by any regression in this guard, and a check that cannot fail is decoration (canon #9).

run_a1 --bogus
eq "an unknown option → rc 2"             "2" "$rc"
eq "the unknown-option refusal prints usage" "true" "$(has "$USAGE" "$err")"
run_a1 stray
eq "a stray positional → rc 2"            "2" "$rc"

run_a1 --sentinel abc
eq "a non-numeric --sentinel → rc 2"      "2" "$rc"
eq "the refusal states the required shape" "true" \
   "$(has '--sentinel must be a DL number this toolkit can render' "$err")"
eq "a rejected sentinel never reaches the board" "0" "$(kb_stub_total)"
run_a1 --sentinel -1
eq "a negative --sentinel → rc 2"         "2" "$rc"
# The sentinel is validated by kb_dl_num — the same strict parser `kbcard --dl` uses — so the
# bound it enforces is that parser's, not a second one this file invented: a value this toolkit
# cannot RENDER is refused before any request rather than at the create the board would reject.
run_a1 --sentinel 9999999
eq "a 7-digit --sentinel is out of DL range → rc 2" "2" "$rc"
eq "…refused before any request"          "0" "$(kb_stub_total)"
run_a1 --sentinel 0
eq "a zero --sentinel → rc 2"             "2" "$rc"

run_a1 --board nostage
eq "no stage anywhere → rc 2"             "2" "$rc"
eq "the refusal names both ways to supply one" "true" \
   "$(has 'pass --stage or set KB_A1_STAGE/KB_STAGE_BACKLOG in' "$err")"
eq "the refusal names the board env file it read" "true" "$(has '.kanban-nostage-board.env' "$err")"
eq "a stage-less board is refused before any request" "0" "$(kb_stub_total)"

run_a1 --board nosuchboard
eq "an unknown --board → rc 2"            "2" "$rc"
eq "the refusal names the missing env file" "true" "$(has '.kanban-nosuchboard-board.env' "$err")"

# The witness for every "issues no request" zero above: the identical harness, with valid
# arguments, does reach the API. Without it those zeros could all be passing for the wrong reason.
run_a1
eq "witness: the same harness DOES issue requests when the arguments are valid" "7" \
   "$(kb_stub_total)"

echo "== a 2xx whose body is not JSON at all (card#6426) =="
# kb_api decides success on the HTTP STATUS CLASS alone, so a 2xx carrying a proxy's HTML error
# page or a truncated read reaches both body reads in this bin as a success. The registration
# read already suppressed jq's MESSAGE with 2>/dev/null — but not its STATUS, so it still exited
# 5 through `set -e`: quietly, which is worse than loudly, and skipping the cleanup trap whose
# whole reason for existing is that a leaked sentinel card poisons the DL minter. Both reads now
# go through the shared kb_parse_resp and land in the arm each already had.
KB_STUB_REGISTER_BODY='<html><body>502 Bad Gateway</body></html>' run_a1
eq "an unreadable REGISTER body → the run still completes (rc 0)" "0" "$rc"
eq "…and reports the field id as unknown, not as a crash" "true" \
   "$(has 'registered dl_number as a STRING field (field id ?)' "$out")"
eq "…leaking no raw jq parse error"        "false" "$(has 'parse error' "$err")"
eq "…and the throwaway is still created AND torn down" "2" "$(kb_stub_count "${TEARDOWN[@]}")"
KB_STUB_CREATE_BODY='<html><body>502 Bad Gateway</body></html>' run_a1
eq "an unreadable CREATE body → FATAL rc 1, not jq's rc 5" "1" "$rc"
eq "…in this tool's own words"             "true" "$(has 'FATAL create throwaway: no task id in response' "$err")"
eq "…leaking no raw jq parse error"        "false" "$(has 'parse error' "$err")"
# The control that makes both legs a measurement: the same route with a well-formed body still
# reports the real id.
run_a1
eq "control: a well-formed body still reports the field id" "true" \
   "$(has 'registered dl_number as a STRING field (field id 9)' "$out")"

echo "== a lib-less copy is refused before the argument surface, --help included =="
# The arg loop parses with the lib's kb_require_value, so the lib is sourced AHEAD of it. That
# ordering is caller-visible on a BROKEN install only, and this is where it shows: a copy vendored
# without _kb-board-lib.sh beside it now answers every invocation with the missing-lib refusal at
# rc 1. With the check BELOW the loop it reported the missing lib only for an invocation the loop
# let through: measured lib-less on the pre-change binary, --help answered rc 0 and each arg-loop
# refusal (--bogus, a trailing value-taking flag, a stray positional) answered rc 2 with usage.
# next-dl, kbcard and adopt-to-dl have always behaved this way; this pins the alignment.
mkdir -p "$TMP/nolib"
cp "$A1" "$TMP/nolib/"
nolib_rc=0
nolib_err="$("$TMP/nolib/dl-a1-register-field" --help 2>&1 >/dev/null)" || nolib_rc=$?
eq "a lib-less copy refuses --help → rc 1" "1" "$nolib_rc"
eq "the refusal names the lib and how to fix it" "true" \
   "$(has 'shared lib _kb-board-lib.sh not found next to this script' "$nolib_err")"

_summary "dl-a1-register-field-selftest"
