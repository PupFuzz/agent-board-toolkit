#!/usr/bin/env bash
# board-stats-selftest.sh — network-free tests for board-stats' argument surface, for WHERE
# ITS BACKWARD PAGING STOPS, for the per-transition human/service split it computes off a
# fixture changelog page, and for the two classifications every count downstream depends on:
# which stages are terminal/pullable, and which `task.moved` rows are transitions at all.
#
# WHY THESE. board-stats reads two different surfaces to answer two different questions, and
# each has a way of being quietly wrong that a live run cannot show you:
#
#   * THE WINDOW. The changelog endpoint has no date filter — a window is read by paging
#     backwards until the rows precede the cutoff. Stop one page too early and the report is a
#     short read presented as a whole one; stop too late and every window walks 90 days of
#     retention. Both look like a normal report. The pagination cases below therefore assert
#     not just the rows returned but WHICH PAGES WERE REQUESTED, against a fixture whose third
#     page holds rows that a correct run must never reach.
#
#   * THE SPLIT. Live boards can go weeks with no human `task.moved` row at all (measured: on
#     all three of this box's boards the only human-actored rows in the 90-day retention are
#     `board_member.role_changed`), so a human counter hardcoded to 0 would pass every live
#     run. It is fixture-proven here, in both directions, and a `null` actor_type — the third
#     value the API emits — is asserted to land in its own bucket rather than silently in one
#     of the two named ones.
#
#   * THE WINDOW ARITHMETIC. `--since 24h` must resolve to the PAST. GNU date reads "24h" as
#     now + 24 hours, so a tool that handed the relative form to date(1) would report an empty
#     window as a quiet day, at rc 0, forever. That trap is asserted directly — including a
#     control that measures date(1) doing exactly it, and the same control for every OTHER spec
#     date parses at rc 0 (`7` = 07:00 today, `tomorrow` = a future window) which is why the
#     spec's SHAPE is checked before date is consulted at all.
#
#   * THE CLASSIFICATIONS. Both are silent when wrong, and both produce zeros that read like a
#     measurement. Terminal/pullable is derived from the board's `lane_type` with the env's
#     KB_STAGE_* ids as a per-key override: the env alone lost every Won't-Do resolution on a
#     board whose env omits KB_STAGE_WONT_DO, so the derivation is asserted with its own control
#     (lane types stripped ⇒ the loss reappears), and an unclassifiable board is asserted to
#     produce a failure LINE rather than zeros. And a `task.moved` row whose from-stage equals
#     its to-stage is a SWIMLANE move, not a transition — ungrouped, one inside a terminal stage
#     mints a phantom resolution on every lane change.
#
# WHAT A GREEN RUN HERE DOES NOT PROVE: nothing about the live API's shape. Every response is
# a fixture, so a server that renamed `actor_type`, moved the cursor parameter, or started
# capping `limit` lower would leave this file green. The API facts it is built on were probed
# live and are recorded in the tool's own header.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/board-stats"
_need -x "$BIN"
# Scratch HOME: no real ~/.kanban-*-board.env or roster on this box may reach a case here.
_mktmp_scratch --home
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines the pure functions, issues no request

# ---------------------------------------------------------------------------
echo "== the argument surface refuses before it reads anything =="
# Each of these must be answered by the parser, so none of them touches an API or a config.
expect_rc "an unknown argument is rc 2"              2 "$BIN" --nope
expect_rc "--format xml is rc 2"                     2 "$BIN" --format xml
expect_rc "--board with an empty value is rc 2"      2 "$BIN" --board ""
expect_rc "--since with an empty value is rc 2"      2 "$BIN" --since ""
expect_rc "--format with an empty value is rc 2"     2 "$BIN" --format ""
# Sibling of the card#6645 class, closed by the same shared gate: the three empty-value lines
# above are a HAND LIST of this bin's value-taking flags, so a fourth flag would join with
# nothing here able to notice. `expect_value_flags` derives the population from the bin's own
# guard call sites and reds in BOTH directions — a flag the bin grew that this block does not
# name, and a flag named here that the bin no longer guards.
expect_value_flags "$BIN" --board --since --format
expect_rc "--all and --board together are rc 2"      2 "$BIN" --all --board dev
expect_rc "--board given twice is rc 2"              2 "$BIN" --board a --board b
expect_rc "--since with an unreadable window is rc 2" 2 "$BIN" --since 24x
# The two shapes date(1) answers at rc 0 with a window nobody asked for: a bare number is
# TODAY at that hour (not N days), and any future instant is a window that can only ever be
# empty. Both are refused by the spec check, before date is consulted.
expect_rc "--since 7 (a bare number) is rc 2"        2 "$BIN" --since 7
expect_rc "--since a FUTURE instant is rc 2"         2 "$BIN" --since 2999-01-01
expect_rc "--help is rc 0"                           0 "$BIN" --help

# The rc alone cannot separate these: every refusal above answers 2, so each message is what
# says WHICH guard fired. (help-output-selftest.sh owns --help's content and channel.)
msg="$("$BIN" --board "" 2>&1 >/dev/null)"
eq "an empty --board names the flag"        "true"  "$(has '--board requires a non-empty value' "$msg")"
msg="$("$BIN" --all --board dev 2>&1 >/dev/null)"
eq "--all + --board names the exclusion"    "true"  "$(has 'mutually exclusive' "$msg")"
msg="$("$BIN" --board a --board b 2>&1 >/dev/null)"
eq "--board twice names the repetition"     "true"  "$(has '--board given twice' "$msg")"
msg="$("$BIN" --format xml 2>&1 >/dev/null)"
eq "a bad --format names the accepted set"  "true"  "$(has "not one of: text, json" "$msg")"
msg="$("$BIN" --since 24x 2>&1 >/dev/null)"
eq "a bad --since names the accepted forms" "true"  "$(has '<N>h / <N>d' "$msg")"
msg="$("$BIN" --since 2999-01-01 2>&1 >/dev/null)"
eq "a future --since is refused AS future, not as unparseable" "true" \
   "$(has 'is not in the past' "$msg")"
out="$("$BIN" --nope 2>/dev/null)"
eq "a refusal keeps stdout empty"           ""      "$out"

# ---------------------------------------------------------------------------
echo "== _bs_since_epoch — a relative window resolves into the PAST =="
NOW=1000000000
eq "24h is now minus 86400"  "$((NOW - 86400))"    "$(_bs_since_epoch 24h "$NOW")"
eq "7d is now minus 604800"  "$((NOW - 604800))"   "$(_bs_since_epoch 7d "$NOW")"
eq "1h is now minus 3600"    "$((NOW - 3600))"     "$(_bs_since_epoch 1h "$NOW")"
expect_rc "a zero-length window is refused"       2 _bs_since_epoch 0h "$NOW"
expect_rc "an unknown suffix is refused"          2 _bs_since_epoch 24x "$NOW"
expect_rc "a bare number is refused"              2 _bs_since_epoch 24 "$NOW"
expect_rc "an empty spec is refused"              2 _bs_since_epoch "" "$NOW"
expect_rc "a whitespace-only spec is refused"     2 _bs_since_epoch " " "$NOW"
# The SHAPE gate, asserted where date(1) would otherwise answer. Each of these parses on a GNU
# box — `7` as 07:00 today, `tomorrow`/`next monday` as a future instant, `2026-08-01 UTC` as a
# real instant in a spelling the contract does not accept — and each answered at rc 0 with a
# window that reads as a measurement.
# The MESSAGE leg below is the discriminating one: with the synthetic $NOW in 2001, `date -d 7`
# lands in the future and the future-window refusal answers rc 2 as well, so an rc-only
# assertion here cannot tell the two guards apart (the shared-rc trap this repo has been bitten
# by — see docs/CONSOLIDATION-PLAN.md § Verification). The CLI leg above runs against the real
# clock, where only the shape gate can answer.
expect_rc "a bare 7 is refused (date reads it as 07:00 TODAY)" 2 _bs_since_epoch 7 "$NOW"
expect_rc "an English relative spec is refused"   2 _bs_since_epoch tomorrow "$NOW"
expect_rc "a non-ISO instant spelling is refused" 2 _bs_since_epoch "2026-08-01 UTC" "$NOW"
msg="$(_bs_since_epoch 7 "$NOW" 2>&1 >/dev/null)"
eq "…naming the accepted forms rather than blaming date(1)" "true" "$(has '<N>h / <N>d' "$msg")"
# THE CONTROL for the three above: date(1) is measured reading each of them at rc 0, so the
# refusals are pinned to a defect that was live in the alternative, not to a parse failure.
for spec in 7 tomorrow "2026-08-01 UTC"; do
    if dparsed="$(date -u -d "$spec" +%s 2>/dev/null)" && [[ "$dparsed" =~ ^[0-9]+$ ]]; then
        eq "control: date(1) DOES answer '$spec' at rc 0 (which is why it is not asked)" \
           "true" "$([[ "$dparsed" -gt 0 ]] && echo true || echo false)"
    fi
done
# Not hypothetical: date(1) answers `date -d ""` with today's MIDNIGHT at rc 0, so an
# unexpanded variable would silently become a since-midnight window rather than a refusal —
# which is why the empty case is answered before date(1) is ever reached.
if datemid="$(date -u -d "" +%s 2>/dev/null)" && [[ "$datemid" =~ ^[0-9]+$ ]]; then
    eq "control: date(1) answers an EMPTY spec with a plausible number, at rc 0" \
       "true" "$([[ "$datemid" -gt 0 ]] && echo true || echo false)"
fi

# THE CONTROL for the case above, and the reason the arithmetic is not delegated: date(1) is
# measured here reading the very same spec as a FUTURE instant. Without this the assertion
# above is just a number; with it, it is a defect that was live in the alternative.
if datefut="$(date -u -d 24h +%s 2>/dev/null)" && [[ "$datefut" =~ ^[0-9]+$ ]]; then
    nowreal="$(date -u +%s)"
    eq "control: date(1) reads '24h' as the FUTURE (which is why it is not used here)" \
       "true" "$([[ "$datefut" -gt "$nowreal" ]] && echo true || echo false)"
    eq "…while _bs_since_epoch reads it as the PAST" \
       "true" "$([[ "$(_bs_since_epoch 24h "$nowreal")" -lt "$nowreal" ]] && echo true || echo false)"
    # Resolved against the REAL now, because an ISO instant in the future is now refused as a
    # window that can only report zeros — and this fixture date is in the past only relative to
    # a real clock, never to the synthetic $NOW.
    isoep="$(date -u -d '2026-08-01T00:00:00Z' +%s)"
    eq "an ISO-8601 spec resolves through date(1)" "$isoep" \
       "$(_bs_since_epoch '2026-08-01T00:00:00Z' "$nowreal")"
    expect_rc "…while a FUTURE ISO instant is refused, not silently accepted" \
       2 _bs_since_epoch '2999-01-01T00:00:00Z' "$nowreal"
    expect_rc "…and an instant AT now is refused too (a zero-length window)" \
       2 _bs_since_epoch "$(date -u -d "@$nowreal" +%Y-%m-%dT%H:%M:%SZ)" "$nowreal"
else
    echo "  note: date(1) cannot parse a relative/ISO spec here — the ISO leg is not exercised"
fi

# ---------------------------------------------------------------------------
echo "== _bs_window_rows — the backward paging stops at the cutoff, and not later =="
# Fixture pages, newest-first, keyed by the cursor the tool would send. mkpage writes a page of
# <count> task.moved rows descending from <first-id>, one every <step> seconds back from <t0>.
mkpage() { # <file> <first-id> <t0-epoch> <step-seconds> <count> <subject-base>
    jq -n --argjson n "$5" --argjson id0 "$2" --argjson t0 "$3" --argjson st "$4" --argjson sb "$6" '
      { data: [ range(0; $n)
                | { id: ($id0 - .), board_id: 1, subject_id: ($sb + .), user_id: 3,
                    action: "task.moved",
                    payload: { from_stage_id: 1, to_stage_id: 2,
                               from_stage_name: "A", to_stage_name: "B",
                               from_swimlane_id: null, to_swimlane_id: null, index: null },
                    created_at: (($t0 - (. * $st)) | todate),
                    actor_type: "service" } ] }' > "$1"
}

T0=1786000000
mkpage "$TMP/page.first.json" 5000 "$T0"        60  200 10000   # newest 200, one per minute
mkpage "$TMP/page.4801.json"  4800 "$((T0 - 12060))" 600 200 20000   # older 200, one per 10min
mkpage "$TMP/page.4601.json"  4600 "$((T0 - 200000))" 60  10  30000  # a SHORT third page

# The stub records every URL it is asked for, so "which pages were requested" is assertable —
# the rows alone cannot tell a loop that stopped from one that fetched and filtered.
CALLS="$TMP/calls"
kb_api() {
    local url="$2" key
    printf '%s\n' "$url" >> "$CALLS"
    key="${url##*before=}"
    [[ "$key" == "$url" ]] && key=first
    cat "$TMP/page.$key.json" 2>/dev/null || return 1
}

# Cutoff inside page 2: page 1 is wholly in-window, page 2 crosses it, page 3 must never be
# requested at all.
CUT=$((T0 - 20000))
: > "$CALLS"; rowsf="$TMP/rows1.jsonl"; : > "$rowsf"
meta="$(_bs_window_rows 1 "$CUT" "$rowsf")"
rows="$(jq -s 'add // []' "$rowsf")"
eq "it reports 2 pages"                        "2" "$(printf '%s' "$meta" | jq -r '.pages')"
eq "…and it made exactly 2 requests"           "2" "$(wc -l < "$CALLS" | tr -d ' ')"
eq "…the second one carrying the page-1 cursor" "true" \
   "$(has 'before=4801' "$(cat "$CALLS")")"
eq "…and it never requested a third"           "false" "$(has 'before=4601' "$(cat "$CALLS")")"
eq "no error is reported"                      "null" "$(printf '%s' "$meta" | jq -r '.error | tostring')"
eq "the window is not flagged truncated"       "false" "$(printf '%s' "$meta" | jq -r '.truncated')"
# 200 from page 1, plus page 2's rows down to the cutoff: (12060 - 20000)/600 → 14 of them.
eq "it keeps page 1 whole and page 2 only to the cutoff" "214" "$(printf '%s' "$rows" | jq 'length')"
eq "every kept row is at or after the cutoff"  "true" \
   "$(printf '%s' "$rows" | jq --argjson c "$CUT" 'all(.[]; (.at | sub("\\+00:00$";"Z") | fromdate) >= $c)')"
# The third page's rows are IN-window by construction — impossible in a real descending log,
# and exactly what makes their absence proof that the loop STOPPED rather than filtered.
eq "no row from the unreached third page is present" "0" \
   "$(printf '%s' "$rows" | jq '[ .[] | select(.card >= 30000) ] | length')"

# THE CONTROL: same fixtures, a cutoff old enough that page 2 does not cross it. If the stop
# above were structural (a bad cursor, a two-page ceiling) this would stop at 2 as well.
: > "$CALLS"; rowsf2="$TMP/rows2.jsonl"; : > "$rowsf2"
meta2="$(_bs_window_rows 1 $((T0 - 999999)) "$rowsf2")"
eq "control: an older cutoff reaches the third page" "3" "$(printf '%s' "$meta2" | jq -r '.pages')"
eq "control: …and its rows ARE collected"            "10" \
   "$(jq -s 'add // [] | [ .[] | select(.card >= 30000) ] | length' "$rowsf2")"

echo "== _bs_window_rows — a log SHORTER than the window is a truncation, not a quiet board =="
# The run above is exactly that case: the fixture log ends at page 3's last row, which is still
# INSIDE a T0-999999 window. Before this was recorded the loop stopped on the short page and
# reported the window complete — a `--since 90d` over a 44-day-old log rendered as a full
# 90-day report at rc 0, with nothing in the output saying the data ran out rather than the
# events.
avail3="$(printf '%s' "$meta2" | jq -r '.data_available_from // "none"')"
eq "the log running out inside the window flags truncated" "true" \
   "$(printf '%s' "$meta2" | jq -r '.truncated')"
eq "…and records how far back the log actually reaches" "true" \
   "$([[ "$avail3" != none ]] && echo true || echo false)"
eq "…which is the OLDEST row the log holds" "$(date -u -d "@$((T0 - 200000 - 9*60))" +%Y-%m-%dT%H:%M:%SZ)" \
   "$avail3"
eq "…and it says the log, not the page cap, is what ended the read" "true" \
   "$(has 'the changelog itself ends at' "$(printf '%s' "$meta2" | jq -r '.error')")"

# THE CONTROL: the SAME short page, the only change being a cutoff the log DOES reach past. A
# flag that fired on every short page would be a decoration, and the third page would look
# truncated in every run above.
: > "$CALLS"; rowsf2b="$TMP/rows2b.jsonl"; : > "$rowsf2b"
meta2b="$(_bs_window_rows 1 $((T0 - 200300)) "$rowsf2b")"
eq "control: the same short page ends the log at 3 pages" "3" \
   "$(printf '%s' "$meta2b" | jq -r '.pages')"
eq "control: …and a log that REACHES the cutoff is not truncated" "false" \
   "$(printf '%s' "$meta2b" | jq -r '.truncated')"
eq "control: …carries no data_available_from"       "null" \
   "$(printf '%s' "$meta2b" | jq -r '.data_available_from | tostring')"
eq "control: …and no error"                          "null" \
   "$(printf '%s' "$meta2b" | jq -r '.error | tostring')"

echo "== _bs_window_rows — the page cap truncates LOUDLY, never silently =="
: > "$CALLS"; rowsf3="$TMP/rows3.jsonl"; : > "$rowsf3"
_BS_PAGE_CAP_SAVED="$_BS_PAGE_CAP"; _BS_PAGE_CAP=1
meta3="$(_bs_window_rows 1 $((T0 - 999999)) "$rowsf3")"
_BS_PAGE_CAP="$_BS_PAGE_CAP_SAVED"
eq "the cap stops the loop at one page"     "1"    "$(printf '%s' "$meta3" | jq -r '.pages')"
eq "…and flags the window truncated"        "true" "$(printf '%s' "$meta3" | jq -r '.truncated')"
eq "…naming the cap in the error"           "true" \
   "$(has 'page cap' "$(printf '%s' "$meta3" | jq -r '.error')")"
eq "…while still keeping the rows it read"  "200"  "$(jq -s 'add | length' "$rowsf3")"

echo "== _bs_window_rows — an unreadable first page is an error, not an empty window =="
: > "$CALLS"; rowsf4="$TMP/rows4.jsonl"; : > "$rowsf4"
# The stub sets KB_HTTP exactly as the real kb_api does when the server ANSWERED a non-2xx.
# A stub that left the global alone would measure this arm against a state the lib cannot
# produce, and the arm reads that global.
kb_api() { printf '%s\n' "$2" >> "$CALLS"; KB_HTTP="503"; return 1; }
meta4="$(_bs_window_rows 1 "$CUT" "$rowsf4")"
eq "no page is reported read"            "0"     "$(printf '%s' "$meta4" | jq -r '.pages')"
eq "an error is reported"                "false" "$(printf '%s' "$meta4" | jq -r '.error == null')"
eq "…and no rows are claimed"            "0"     "$(jq -s 'add // [] | length' "$rowsf4")"

echo "== _bs_window_rows — a request that NEVER COMPLETED is not a status the server sent (card#6680) =="
# THE DEFECT. The read was `resp="$(kb_api …)" || err="… (HTTP ${KB_HTTP:-000}) …"`, and a
# command substitution is a SUBSHELL: the KB_HTTP kb_api set inside it never reached that line,
# so the status came from the lib's own empty initialiser and EVERY failure rendered `HTTP 000`
# — the sentinel for a request that never completed — including the 403/500 the server actually
# answered. `KB_API_QUIET=1` also suppresses kb_api's own `HTTP 500 on GET …` line, so nothing
# anywhere in the run contradicted it: an answered non-2xx was reported, silently, as a
# transport failure. Measured before the fix: both stubs below produced the byte-identical
# `changelog read failed (HTTP 000) after 0 page(s)`.
#
# ⛔ ASSERTED AS A DISTINCTION, NOT AS A STRING. "an error is reported" above was already true
# of BOTH states, so it could not have failed on this defect. The two messages are compared
# against each other, in the same run.
: > "$CALLS"; rowsf4b="$TMP/rows4b.jsonl"; : > "$rowsf4b"
kb_api() { printf '%s\n' "$2" >> "$CALLS"; KB_HTTP="000"; return "$KB_API_RC_TRANSPORT"; }
meta4b="$(_bs_window_rows 1 "$CUT" "$rowsf4b")"
err4="$(printf '%s' "$meta4" | jq -r '.error')"
err4b="$(printf '%s' "$meta4b" | jq -r '.error')"
eq "⭐ the two failures do NOT share one message" "differ" \
   "$(if [[ "$err4" == "$err4b" ]]; then echo same; else echo differ; fi)"
eq "the ANSWERED non-2xx names the status the server sent" "true"  "$(has 'HTTP 503' "$err4")"
eq "…and never says the request failed to complete"        "false" "$(has 'DID NOT COMPLETE' "$err4")"
eq "the never-completed request says exactly that"         "true"  "$(has 'DID NOT COMPLETE' "$err4b")"
# `000` is this state's own sentinel, not something the server sent, so the line names no
# status at all rather than dressing the sentinel up as one.
eq "…and names NO status — none was read"                  "false" "$(has 'HTTP' "$err4b")"
eq "…reports no page read"                                 "0"     "$(printf '%s' "$meta4b" | jq -r '.pages')"
eq "…and claims no rows"                                   "0"     "$(jq -s 'add // [] | length' "$rowsf4b")"

echo "== _bs_window_rows — a body of the wrong shape is refused, not half-read =="
: > "$CALLS"; rowsf5="$TMP/rows5.jsonl"; : > "$rowsf5"
kb_api() { printf '%s\n' "$2" >> "$CALLS"; printf '%s' '<html>a proxy said hello</html>'; }
meta5="$(_bs_window_rows 1 "$CUT" "$rowsf5")"
eq "a non-JSON body is an error"         "true"  \
   "$(has 'not the shape this tool reads' "$(printf '%s' "$meta5" | jq -r '.error')")"
eq "…and no rows are claimed"            "0"     "$(jq -s 'add // [] | length' "$rowsf5")"

echo "== _bs_window_rows — a page carrying no ROW ARRAY is UNREADABLE, never an exhausted log =="
# The defect this closes (card#6630 — the third instance of the envelope shape the two card
# paginators already fixed, and the last one in the pager population docs/CONSOLIDATION-PLAN.md
# derives): the page parse opened with `(.data // []) as $d`, and jq's
# `//` substitutes for `false` and `null` as well as for absent — so a 2xx carrying a proxy's
# error object arrived as `n: 0`, which IS the loop's log-is-exhausted stop. The window ended
# there with truncated=false and no error, and the flow counts rendered off a truncated window
# with no ⚠ and no (WINDOW TRUNCATED) marker, at rc 0 — a plausible wrong answer.
#
# The fixtures are the MEASURED silent set, not a guessed one: every other unreadable shape
# already faulted the page parse at `$d[-1]` and was caught by the same `[[ -n "$page" ]]`
# guard the non-JSON leg above exercises, so a `.data`-shape test would over-claim what moved. `{"data":false}` is the discriminating member — it
# is silent under `//` and caught under a type test — and its control is `{"data":{}}` below.
_bs_page2_body=""
kb_api() {
    local url="$2"
    printf '%s\n' "$url" >> "$CALLS"
    if [[ "$url" == *before=* ]]; then printf '%s' "$_bs_page2_body"
    else cat "$TMP/page.first.json"; fi
}
# A cutoff far older than the whole fixture log, so nothing but the page-2 body can stop the
# loop — if it were the cutoff, this would pass with the predicate reverted.
CUT6=$((T0 - 999999))
for _bs_page2_body in '{"error":"upstream connect error"}' '{"data":null}' '{"data":false}'; do
    : > "$CALLS"; rowsf6="$TMP/rows6.jsonl"; : > "$rowsf6"
    meta6="$(_bs_window_rows 1 "$CUT6" "$rowsf6")"
    eq "page 2 = $_bs_page2_body is reported unreadable, not exhausted" "true" \
       "$(has 'changelog page 2 is not the shape this tool reads' \
              "$(printf '%s' "$meta6" | jq -r '.error // ""')")"
    eq "…and the rows page 1 DID deliver are kept (a floor, not a loss)" "200" \
       "$(jq -s 'add // [] | length' "$rowsf6")"
    eq "…and the loop stops there rather than paging on" "2" \
       "$(wc -l < "$CALLS" | tr -d ' ')"
done

# CONTROL 1 — the other half of the discriminating pair. `{"data":{}}` was ALREADY caught (it
# reaches `$d[-1]` as an object and faults the parse), so a fix that simply reported every
# page-2 body as unreadable would look identical on the three cases above. This one must keep
# answering exactly as it did before the predicate existed.
: > "$CALLS"; rowsf6c="$TMP/rows6c.jsonl"; : > "$rowsf6c"
_bs_page2_body='{"data":{}}'
meta6c="$(_bs_window_rows 1 "$CUT6" "$rowsf6c")"
eq "control: {\"data\":{}} is still caught, by the same message" "true" \
   "$(has 'changelog page 2 is not the shape this tool reads' \
          "$(printf '%s' "$meta6c" | jq -r '.error // ""')")"

# CONTROL 2 — the case the predicate must NOT touch, and the reason it is a TYPE test rather
# than a truthiness one: a genuinely exhausted log answers `{"data":[]}`, which is an array. It
# is a short page, it stops the loop, and it is SILENT — a board younger than its first event
# is not a failure. Without this leg, refusing every falsy `.data` would pass every assertion
# above while breaking every empty board in the roster.
: > "$CALLS"; rowsf6d="$TMP/rows6d.jsonl"; : > "$rowsf6d"
_bs_page2_body='{"data":[]}'
meta6d="$(_bs_window_rows 1 "$CUT6" "$rowsf6d")"
eq "control: an EMPTY page-2 array ends the log with no error" "null" \
   "$(printf '%s' "$meta6d" | jq -r '.error | tostring')"
eq "control: …and is not flagged truncated"        "false" \
   "$(printf '%s' "$meta6d" | jq -r '.truncated')"
eq "control: …while still keeping page 1's rows"   "200" \
   "$(jq -s 'add // [] | length' "$rowsf6d")"

# PAGE 1 IS THE SAME PREDICATE AND THE SAME MESSAGE — there is no page-dependent arm here, and
# this leg is what says so. (The two card paginators DO split by page, because each has two
# documented rcs to split between; this function has one channel, `error`, and `_bs_one_board`
# already renders pages>0 identically either way.) Pre-fix, a page-1 gateway error body
# produced a flow section of zeros that read as a quiet board.
: > "$CALLS"; rowsf6e="$TMP/rows6e.jsonl"; : > "$rowsf6e"
kb_api() { printf '%s\n' "$2" >> "$CALLS"; printf '%s' '{"data":null}'; }
meta6e="$(_bs_window_rows 1 "$CUT6" "$rowsf6e")"
eq "an unreadable PAGE 1 is unreadable too, naming page 1" "true" \
   "$(has 'changelog page 1 is not the shape this tool reads' \
          "$(printf '%s' "$meta6e" | jq -r '.error // ""')")"
# `pages` must still count the request: it is what _bs_one_board branches on to decide between
# a flagged flow section and a dropped one, so an unreadable page 1 that reported 0 pages would
# turn this ⚠ into "flow: UNAVAILABLE" and lose the zeros it qualifies.
eq "…and the request is still counted as one page"  "1" \
   "$(printf '%s' "$meta6e" | jq -r '.pages')"
# CONTROL for the leg above: the SAME page 1, the only change being an array `.data`. An empty
# first page is a board with no events, which must stay silent at every page number.
: > "$CALLS"; rowsf6f="$TMP/rows6f.jsonl"; : > "$rowsf6f"
kb_api() { printf '%s\n' "$2" >> "$CALLS"; printf '%s' '{"data":[]}'; }
meta6f="$(_bs_window_rows 1 "$CUT6" "$rowsf6f")"
eq "control: an empty PAGE 1 is a quiet board, not a failure" "null" \
   "$(printf '%s' "$meta6f" | jq -r '.error | tostring')"

# ---------------------------------------------------------------------------
echo "== _bs_board_json — the human/service split, per transition =="
# One fixture page carrying every shape the aggregation must keep apart: a multi-actor
# transition, two DIFFERENT terminal destinations (which must not collapse into one
# "resolutions" number), a terminal→terminal move (a resolution, NOT a wash), a
# terminal→non-terminal move (a WASH, which must survive in the transition list rather than
# being netted against the resolutions), and a null actor_type (the API's third value).
# Timestamps here are the API's "+00:00" spelling, which fromdateiso8601 rejects unaided.
NOW2=1786000000
cat > "$TMP/fx-rows.jsonl" <<'ROWS'
[
 {"action":"task.moved","at":"2026-08-11T10:00:00+00:00","card":1,"actor":"service","from_id":83,"to_id":84,"from_name":"Backlog","to_name":"In Progress"},
 {"action":"task.moved","at":"2026-08-11T10:01:00+00:00","card":2,"actor":"service","from_id":83,"to_id":84,"from_name":"Backlog","to_name":"In Progress"},
 {"action":"task.moved","at":"2026-08-11T10:02:00+00:00","card":3,"actor":"human","from_id":83,"to_id":84,"from_name":"Backlog","to_name":"In Progress"},
 {"action":"task.moved","at":"2026-08-11T10:03:00+00:00","card":4,"actor":"service","from_id":87,"to_id":89,"from_name":"In Review","to_name":"Shipped to dev"},
 {"action":"task.moved","at":"2026-08-11T10:04:00+00:00","card":5,"actor":"service","from_id":87,"to_id":89,"from_name":"In Review","to_name":"Shipped to dev"},
 {"action":"task.moved","at":"2026-08-11T10:05:00+00:00","card":6,"actor":"service","from_id":89,"to_id":85,"from_name":"Shipped to dev","to_name":"Released to main"},
 {"action":"task.moved","at":"2026-08-11T10:06:00+00:00","card":7,"actor":"unknown","from_id":90,"to_id":83,"from_name":"Won't Do","to_name":"Backlog"},
 {"action":"task.created","at":"2026-08-11T10:07:00+00:00","card":8,"actor":"service","from_id":null,"to_id":null,"from_name":null,"to_name":null},
 {"action":"task.created","at":"2026-08-11T10:08:00+00:00","card":9,"actor":"human","from_id":null,"to_id":null,"from_name":null,"to_name":null}
]
ROWS
cat > "$TMP/fx-cards.json" <<'CARDS'
[{"id":11,"workflow_stage_id":83,"created_at":"2026-08-01T00:00:00+00:00","deleted_at":null},
 {"id":12,"workflow_stage_id":83,"created_at":"2026-07-01T00:00:00+00:00","deleted_at":null},
 {"id":13,"workflow_stage_id":84,"created_at":"2026-07-15T00:00:00+00:00","deleted_at":null},
 {"id":14,"workflow_stage_id":85,"created_at":"2026-07-15T00:00:00+00:00","deleted_at":null},
 {"id":15,"workflow_stage_id":77,"created_at":"2026-07-15T00:00:00+00:00","deleted_at":null},
 {"id":16,"workflow_stage_id":83,"created_at":"2026-07-02T00:00:00+00:00","deleted_at":"2026-08-01T00:00:00+00:00"}]
CARDS
fxmeta="$(jq -n --argjson now "$NOW2" '
  { name: "fx", label: "Fixture board", board_id: 1,
    names: {"83":"Backlog","84":"In Progress","85":"Released to main","86":"Prioritized",
            "87":"In Review","89":"Shipped to dev","90":"Won'"'"'t Do"},
    order: ["83","86","84","87","89","85","90"],
    term: ["89","85","90"], pull: ["83","86"],
    now: $now, flow: {pages:1, truncated:false, error:null}, failures: [],
    stock_ok: true, flow_ok: true }')"
obj="$(_bs_board_json "$TMP/fx-cards.json" "$TMP/fx-rows.jsonl" "$fxmeta")"

eq "created counts only task.created"        "2" "$(printf '%s' "$obj" | jq '.flow.created')"
eq "moved counts only task.moved"            "7" "$(printf '%s' "$obj" | jq '.flow.moved')"
eq "the board-wide split is 1 human"         "1" "$(printf '%s' "$obj" | jq '.flow.actors.human')"
eq "…5 service"                              "5" "$(printf '%s' "$obj" | jq '.flow.actors.service')"
eq "…and 1 unattributed (a null actor_type)" "1" "$(printf '%s' "$obj" | jq '.flow.actors.other')"

t="$(printf '%s' "$obj" | jq -c '.flow.transitions[] | select(.from_stage_id == 83 and .to_stage_id == 84)')"
eq "the multi-actor transition counts 3"     "3" "$(printf '%s' "$t" | jq '.count')"
eq "…split 1 human"                          "1" "$(printf '%s' "$t" | jq '.actors.human')"
eq "…and 2 service"                          "2" "$(printf '%s' "$t" | jq '.actors.service')"
eq "…labelled from the board's own names"    "Backlog -> In Progress" \
   "$(printf '%s' "$t" | jq -r '"\(.from_stage) -> \(.to_stage)"')"
eq "…and not marked a resolution"            "false" "$(printf '%s' "$t" | jq '.resolution')"

echo "== _bs_board_json — resolutions stay PER DESTINATION, and a wash is a row =="
eq "two distinct terminal destinations stay two rows" "2" \
   "$(printf '%s' "$obj" | jq '.flow.resolutions | length')"
eq "…Shipped to dev counted on its own"      "2" \
   "$(printf '%s' "$obj" | jq '[.flow.resolutions[] | select(.stage_id == 89)] | .[0].count')"
eq "…Released to main counted on its own"    "1" \
   "$(printf '%s' "$obj" | jq '[.flow.resolutions[] | select(.stage_id == 85)] | .[0].count')"
eq "a terminal→terminal move is a resolution, not a wash" "true" \
   "$(printf '%s' "$obj" | jq '[.flow.transitions[] | select(.from_stage_id == 89 and .to_stage_id == 85)] | .[0] | (.resolution and (.wash | not))')"
eq "the terminal→non-terminal move is one wash" "1" \
   "$(printf '%s' "$obj" | jq '.flow.washes | length')"
eq "…identified by its endpoints"            "90->83" \
   "$(printf '%s' "$obj" | jq -r '.flow.washes[0] | "\(.from_stage_id)->\(.to_stage_id)"')"
eq "…carrying its own unattributed actor"    "1" \
   "$(printf '%s' "$obj" | jq '.flow.washes[0].actors.other')"
# The netting failure this guards is silent by construction: netted away, the wash simply
# would not be in the transition list, and every count would still add up.
eq "…and STILL present among the transitions (not netted away)" "1" \
   "$(printf '%s' "$obj" | jq '[.flow.transitions[] | select(.wash)] | length')"

echo "== _bs_board_json — the split is measured, not constant (control) =="
# Same fixture with the human row's actor changed to service. Without this, a human counter
# hardcoded to 1 — or one reading the board-wide count into every transition — passes above.
jq -c 'map(if .actor == "human" then .actor = "service" else . end)' "$TMP/fx-rows.jsonl" > "$TMP/fx-rows-nohuman.jsonl"
obj2="$(_bs_board_json "$TMP/fx-cards.json" "$TMP/fx-rows-nohuman.jsonl" "$fxmeta")"
eq "control: with no human row the human count is 0" "0" \
   "$(printf '%s' "$obj2" | jq '.flow.actors.human')"
eq "control: …and the transition's own human count is 0 too" "0" \
   "$(printf '%s' "$obj2" | jq '[.flow.transitions[] | select(.from_stage_id == 83)] | .[0].actors.human')"
eq "control: the service count absorbs it" "6" \
   "$(printf '%s' "$obj2" | jq '.flow.actors.service')"

echo "== _bs_board_json — stock counts columns, and ages only the PULLABLE ones =="
eq "a deleted card is not stock"             "5" "$(printf '%s' "$obj" | jq '.stock.total')"
eq "Backlog holds 2 live cards"              "2" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 83)] | .[0].cards')"
eq "…and reports its OLDEST live card"       "12" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 83)] | .[0].oldest_card.id')"
eq "…as an age in days off the +00:00 timestamp" "true" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 83)] | .[0].oldest_card.age_days > 0')"
eq "a NON-pullable column carrying cards has no age" "null" \
   "$(printf '%s' "$obj" | jq -r '[.stock.columns[] | select(.stage_id == 84)] | .[0].oldest_card | tostring')"
eq "an empty pullable column is still a row"  "0" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 86)] | .[0].cards')"
eq "…with no age to report"                   "null" \
   "$(printf '%s' "$obj" | jq -r '[.stock.columns[] | select(.stage_id == 86)] | .[0].oldest_card | tostring')"
eq "the terminal columns are marked terminal" "true" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 85)] | .[0].terminal')"
# A card sitting in a stage the board's own preload never named must still be counted, under
# an honest label — dropping it would make `total` disagree with the column sum silently.
eq "a card in an unnamed stage is still counted" "1" \
   "$(printf '%s' "$obj" | jq '[.stock.columns[] | select(.stage_id == 77)] | .[0].cards')"
eq "…and labelled by its id"                  "stage 77" \
   "$(printf '%s' "$obj" | jq -r '[.stock.columns[] | select(.stage_id == 77)] | .[0].stage')"
eq "the column counts sum to the total"       "true" \
   "$(printf '%s' "$obj" | jq '([.stock.columns[].cards] | add) == .stock.total')"

# ---------------------------------------------------------------------------
echo "== _bs_board_json — a SWIMLANE-only move is not a transition, and not a resolution =="
# The board emits `task.moved` for a swimlane change as well as a stage change, so a swimlaned
# board's log carries rows whose from_stage_id EQUALS their to_stage_id. Ungrouped, one of
# those inside a terminal stage mints a resolution out of a card that never moved column — and
# on a board where the release lane is swimlaned, it does so every time.
cat > "$TMP/fx-same.jsonl" <<'ROWS'
[
 {"action":"task.moved","at":"2026-08-11T10:00:00+00:00","card":1,"actor":"service","from_id":83,"to_id":84,"from_name":"Backlog","to_name":"In Progress"},
 {"action":"task.moved","at":"2026-08-11T10:01:00+00:00","card":2,"actor":"human","from_id":89,"to_id":89,"from_name":"Shipped to dev","to_name":"Shipped to dev"},
 {"action":"task.moved","at":"2026-08-11T10:02:00+00:00","card":3,"actor":"service","from_id":83,"to_id":83,"from_name":"Backlog","to_name":"Backlog"}
]
ROWS
objs="$(_bs_board_json "$TMP/fx-cards.json" "$TMP/fx-same.jsonl" "$fxmeta")"
eq "the two same-stage rows are counted on their own line" "2" \
   "$(printf '%s' "$objs" | jq '.flow.same_stage_moves')"
eq "…and are NOT transitions"                 "1" \
   "$(printf '%s' "$objs" | jq '.flow.transitions | length')"
eq "…the one transition being the real move"  "83->84" \
   "$(printf '%s' "$objs" | jq -r '.flow.transitions[0] | "\(.from_stage_id)->\(.to_stage_id)"')"
# The phantom this guards: stage 89 is terminal, so an ungrouped same-stage row there is a
# resolution of a card that never moved column.
eq "…so a same-stage row in a TERMINAL stage mints no resolution" "0" \
   "$(printf '%s' "$objs" | jq '.flow.resolutions | length')"
eq "…and no wash"                             "0" \
   "$(printf '%s' "$objs" | jq '.flow.washes | length')"
eq "moved still counts every task.moved event read" "3" \
   "$(printf '%s' "$objs" | jq '.flow.moved')"
eq "…so moved = the transitions plus the same-stage moves" "true" \
   "$(printf '%s' "$objs" | jq '.flow.moved == (([.flow.transitions[].count] | add // 0) + .flow.same_stage_moves)')"
# THE CONTROL: the same fixture with the two rows given a real destination. If the counter were
# a constant, or the grouping still swallowed them, this would not move.
jq -c 'map(if .from_id == .to_id then .to_id = 84 else . end)' "$TMP/fx-same.jsonl" > "$TMP/fx-same-ctl.jsonl"
objsc="$(_bs_board_json "$TMP/fx-cards.json" "$TMP/fx-same-ctl.jsonl" "$fxmeta")"
eq "control: with no same-stage row the counter is 0" "0" \
   "$(printf '%s' "$objsc" | jq '.flow.same_stage_moves')"
eq "control: …and all three rows are transitions"     "3" \
   "$(printf '%s' "$objsc" | jq '[.flow.transitions[].count] | add')"
printf '%s' "$objs" | jq -s --argjson now "$NOW2" '
    { generated_at: ($now|todate), since: {spec:"24h", cutoff:(($now-86400)|todate), epoch:($now-86400)},
      partial: false, failed_boards: 0, readable_boards: 1, boards: . }' > "$TMP/doc-same.json"
txtsame="$(_bs_render_text "$TMP/doc-same.json")"
eq "the same-stage count reaches the text on its own line" "true" \
   "$(has 'same-stage moves' "$txtsame")"
eq "…labelled as swimlane-only rather than left to read as a transition" "true" \
   "$(has 'swimlane-only; not transitions' "$txtsame")"

# ---------------------------------------------------------------------------
echo "== the terminal/pullable classification is DERIVED from the board's lane_type =="
# The board env is not the only source, and must not be the only source: it names stage ids by
# ROLE, so a role it omits (the shipped examples/kanban-board.env.example has no
# KB_STAGE_WONT_DO) silently emptied a whole class — every Won't-Do resolution and every wash
# out of it vanished at rc 0, with no failure line. The board's own `lane_type` answers the
# same question for stages the env never mentions.
cat > "$TMP/fx-preload.json" <<'PRE'
{"data":{"workflows":[{"id":1,"stages":[
  {"id":88,"name":"Blocked/Gated","lane_type":"in_progress","position":1024},
  {"id":83,"name":"Backlog","lane_type":"backlog_inventory","position":2048},
  {"id":86,"name":"Prioritized","lane_type":"backlog_inventory","position":3072},
  {"id":84,"name":"In Progress","lane_type":"in_progress","position":4096},
  {"id":87,"name":"In Review","lane_type":"in_progress","position":5120},
  {"id":89,"name":"Shipped to dev","lane_type":"waiting","position":6144},
  {"id":85,"name":"Released to main","lane_type":"done","position":7168},
  {"id":90,"name":"Won't Do","lane_type":"done","position":8192}]}]}}
PRE
fxmap="$(_bs_stage_map "$(cat "$TMP/fx-preload.json")")"
eq "the stage map carries the done-typed stages"     '["85","90"]' \
   "$(printf '%s' "$fxmap" | jq -c '.derived_term')"
eq "…and the backlog_inventory-typed ones"           '["83","86"]' \
   "$(printf '%s' "$fxmap" | jq -c '.derived_pull')"
eq "…while still carrying the column names"          "Won't Do" \
   "$(printf '%s' "$fxmap" | jq -r '.names["90"]')"

# A board env with NO KB_STAGE_WONT_DO — the shipped example's shape.
cls="$(_bs_classify "$fxmap" 89 85 "" 83 86)"
eq "Won't Do is terminal with no env key naming it"  "true" \
   "$(printf '%s' "$cls" | jq '.term | index("90") != null')"
eq "…and the env-only Shipped to dev stays terminal too (lane_type waiting)" "true" \
   "$(printf '%s' "$cls" | jq '.term | index("89") != null')"
eq "…so the class is the UNION, not either source alone" '["85","89","90"]' \
   "$(printf '%s' "$cls" | jq -c '.term')"
eq "pullable derives the same way"                   '["83","86"]' \
   "$(printf '%s' "$cls" | jq -c '.pull')"
# THE CONTROL for the derivation: with the lane types stripped, only the env keys remain — the
# pre-fix behaviour, and the defect itself, measured rather than asserted.
fxmap_nolane="$(_bs_stage_map "$(jq -c '.data.workflows[0].stages |= map(del(.lane_type))' "$TMP/fx-preload.json")")"
eq "control: with no lane_type the derivation is empty" "[]" \
   "$(printf '%s' "$fxmap_nolane" | jq -c '.derived_term')"
eq "control: …and Won't Do is then LOST to a wont-do-less env" "false" \
   "$(_bs_classify "$fxmap_nolane" 89 85 "" 83 86 | jq '.term | index("90") != null')"
eq "control: …while an env that DOES name it keeps it" "true" \
   "$(_bs_classify "$fxmap_nolane" 89 85 90 83 86 | jq '.term | index("90") != null')"
eq "an unusable preload plus an empty env classifies NOTHING" '{"term":[],"pull":[]}' \
   "$(_bs_classify "$(_bs_stage_map '<html>a proxy said hello</html>')" "" "" "" "" "" | jq -c '.')"

# ---------------------------------------------------------------------------
echo "== _bs_one_board — the derivation reaches the report, and an empty class SAYS SO =="
# End-to-end over stubs: a real board env (minus KB_STAGE_WONT_DO), the fixture preload, and a
# changelog page whose last row precedes the cutoff so the window is complete.
NOW4=1786000000
CUT4=$((NOW4 - 86400))
printf 'a-token\n' > "$TMP/fx-token"
API="https://stub.invalid/api/v3"
cat > "$HOME/.kanban-fx-board.env" <<ENVF
export KB_BOARD_ID=1
export KBCARD_TOKEN_FILE="$TMP/fx-token"
export KB_STAGE_BACKLOG=83
export KB_STAGE_PRIORITIZED=86
export KB_STAGE_SHIPPED_TO_DEV=89
export KB_STAGE_RELEASED_TO_MAIN=85
ENVF
jq -n --argjson t "$NOW4" '
  { data: [ { id: 9, board_id: 1, subject_id: 1, action: "task.moved", actor_type: "service",
              payload: {from_stage_id: 87, to_stage_id: 90, from_stage_name: "In Review", to_stage_name: "Wont Do"},
              created_at: (($t - 3600) | todate) },
            { id: 8, board_id: 1, subject_id: 2, action: "task.moved", actor_type: "human",
              payload: {from_stage_id: 90, to_stage_id: 90, from_stage_name: "Wont Do", to_stage_name: "Wont Do"},
              created_at: (($t - 3700) | todate) },
            { id: 7, board_id: 1, subject_id: 3, action: "task.created", actor_type: "service",
              payload: {}, created_at: (($t - 90000) | todate) } ] }' > "$TMP/fx-changelog.json"
printf '%s' '[{"id":11,"workflow_stage_id":83,"created_at":"2026-08-01T00:00:00+00:00","deleted_at":null}]' \
    > "$TMP/fx-onecards.json"
kb_api() {
    case "$2" in
        */preload.json) cat "$TMP/fx-preload.json" ;;
        */changelog.json*) cat "$TMP/fx-changelog.json" ;;
        *) return 1 ;;
    esac
}
fetch_board_cards() { cat "$TMP/fx-onecards.json"; }
mkdir -p "$TMP/b1"
onb="$(_bs_one_board fx "Fixture board" "$CUT4" "$NOW4" "$TMP/b1")"
eq "the board reports no failure"                    "0" \
   "$(printf '%s' "$onb" | jq '.failures | length')"
eq "the Won't-Do move IS a resolution, with no env key for it" "1" \
   "$(printf '%s' "$onb" | jq '[.flow.resolutions[] | select(.stage_id == 90)] | .[0].count')"
eq "…and the swimlane-only move in that same stage is not" "1" \
   "$(printf '%s' "$onb" | jq '.flow.same_stage_moves')"
eq "the pullable column is classified from lane_type too" "true" \
   "$(printf '%s' "$onb" | jq '[.stock.columns[] | select(.stage_id == 83)] | .[0].pullable')"

echo "== _bs_one_board — an EMPTY class is a failure line, never a silent zero =="
# Nothing to derive from (a preload with no lane_type) and nothing to override with (an env
# with no KB_STAGE_* key at all). The counts that follow are all zero, and without this line
# they read exactly like a board where nothing happened.
cat > "$HOME/.kanban-fx2-board.env" <<ENVF
export KB_BOARD_ID=1
export KBCARD_TOKEN_FILE="$TMP/fx-token"
ENVF
jq -c '.data.workflows[0].stages |= map(del(.lane_type))' "$TMP/fx-preload.json" > "$TMP/fx-preload-nolane.json"
kb_api() {
    case "$2" in
        */preload.json) cat "$TMP/fx-preload-nolane.json" ;;
        */changelog.json*) cat "$TMP/fx-changelog.json" ;;
        *) return 1 ;;
    esac
}
mkdir -p "$TMP/b2"
onb2="$(_bs_one_board fx2 "Unclassifiable board" "$CUT4" "$NOW4" "$TMP/b2")"
eq "an unclassifiable terminal set is named"         "true" \
   "$(has 'no TERMINAL stage could be classified' "$(printf '%s' "$onb2" | jq -r '.failures[]')")"
eq "…and so is an unclassifiable pullable set"       "true" \
   "$(has 'no PULLABLE stage could be classified' "$(printf '%s' "$onb2" | jq -r '.failures[]')")"
eq "…each naming the board env that could override it" "true" \
   "$(has '.kanban-fx2-board.env' "$(printf '%s' "$onb2" | jq -r '.failures[]')")"
eq "the zeros it warns about are really there"       "0" \
   "$(printf '%s' "$onb2" | jq '.flow.resolutions | length')"
# THE CONTROL: the board above differs from the healthy one ONLY in what it can classify — so
# the failure lines cannot be an artifact of the stub, the env file, or the fixture log.
eq "control: the healthy board carries neither line"  "false" \
   "$(has 'could be classified' "$(printf '%s' "$onb" | jq -r '.failures[]')")"

echo "== _bs_one_board — an unreadable changelog page reaches the report as a FLOOR line =="
# This is the surface bin/board-stats' header promise is kept on: "a number that is a floor
# rather than a total (a capped card read, a truncated changelog window) says so where it is
# printed." The silent-envelope path falsified it — the counts rendered with nothing beside
# them — so the leg asserts the ⚠ line, not just the `error` field _bs_window_rows returns.
# Same env, same preload, same cards as the healthy board above; ONLY the changelog body moves.
kb_api() {
    case "$2" in
        */preload.json) cat "$TMP/fx-preload.json" ;;
        */changelog.json*) printf '%s' '{"data":null}' ;;
        *) return 1 ;;
    esac
}
mkdir -p "$TMP/b3"
onb3="$(_bs_one_board fx "Fixture board" "$CUT4" "$NOW4" "$TMP/b3")"
eq "the unreadable window is named on the board's own failure list" "true" \
   "$(has 'changelog window INCOMPLETE' "$(printf '%s' "$onb3" | jq -r '.failures[]')")"
eq "…saying the flow counts are a floor rather than a total" "true" \
   "$(has 'a floor, not a total' "$(printf '%s' "$onb3" | jq -r '.failures[]')")"
eq "…and the flow section is still rendered, not dropped" "false" \
   "$(printf '%s' "$onb3" | jq '.flow == null')"
eq "…carrying the page count that kept it renderable" "1" \
   "$(printf '%s' "$onb3" | jq '.flow.pages')"
# The ⚠ must reach the TEXT a human reads, above the counts it qualifies — the JSON field
# alone is not where this report is consumed.
printf '%s' "$onb3" | jq -s --argjson now "$NOW4" '
    { generated_at: ($now | todate),
      since: {spec: "24h", cutoff: (($now - 86400) | todate), epoch: ($now - 86400)},
      partial: true, failed_boards: 1, readable_boards: 1, boards: . }' > "$TMP/doc-flowfail.json"
txtff="$(_bs_render_text "$TMP/doc-flowfail.json")"
eq "the floor line is printed above the flow counts" "true" \
   "$(has '⚠ changelog window INCOMPLETE' "$txtff")"
# THE CONTROL: the healthy board, same fixtures apart from a readable changelog, carries no
# such line — otherwise the ⚠ would be a decoration that fires on every run.
eq "control: a readable window carries no INCOMPLETE line" "false" \
   "$(has 'changelog window INCOMPLETE' "$(printf '%s' "$onb" | jq -r '.failures[]')")"

# ---------------------------------------------------------------------------
echo "== _bs_render_text — the text renders what the JSON carries =="
printf '%s' "$obj" | jq -s --argjson now "$NOW2" '
    { generated_at: ($now | todate),
      since: {spec: "24h", cutoff: (($now - 86400) | todate), epoch: ($now - 86400)},
      partial: false, failed_boards: 0, readable_boards: 1, boards: . }' > "$TMP/doc.json"
txt="$(_bs_render_text "$TMP/doc.json")"
eq "the wash is rendered as a WASH row"       "true" "$(has '[WASH]' "$txt")"
eq "the resolutions are labelled per destination" "true" \
   "$(has 'resolutions, per destination stage' "$txt")"
eq "…and both destinations appear"            "true" \
   "$(has 'Shipped to dev' "$txt")"
eq "the human/service split reaches the text" "true" "$(has 'human 1 · service 2' "$txt")"
eq "the stock section names the oldest pullable card" "true" "$(has '(#12)' "$txt")"
# A window the LOG could not fill must say so where the counts are read, not only in the JSON:
# the counts themselves are indistinguishable from a quiet board.
jq '.boards[0].flow.data_available_from = "2026-07-01T00:00:00Z" | .boards[0].flow.truncated = true' \
    "$TMP/doc.json" > "$TMP/doc-short.json"
txtshort="$(_bs_render_text "$TMP/doc-short.json")"
eq "a log that ran out inside the window says so in the text" "true" \
   "$(has 'the changelog reaches back only to 2026-07-01T00:00:00Z' "$txtshort")"
eq "…and the flow heading is marked truncated"     "true" \
   "$(has 'WINDOW TRUNCATED' "$txtshort")"
eq "control: the untruncated report carries neither" "false" \
   "$(has 'reaches back only to' "$txt")"

echo "== _bs_render_text — a failed board is NAMED, never omitted =="
jq -n '{ generated_at: "2026-08-12T00:00:00Z",
         since: {spec:"24h", cutoff:"2026-08-11T00:00:00Z", epoch: 0},
         partial: true, failed_boards: 1, readable_boards: 0,
         boards: [ {board:"gone", label:"Gone board", board_id:null, stock:null, flow:null,
                    failures:["board env not readable: /nope — this board contributes nothing to the report"]} ] }' \
    > "$TMP/doc-fail.json"
txt2="$(_bs_render_text "$TMP/doc-fail.json")"
eq "the failed board still has a heading"   "true" "$(has 'Gone board' "$txt2")"
eq "its failure is printed"                 "true" "$(has 'board env not readable' "$txt2")"
eq "its stock section says UNAVAILABLE"     "true" "$(has 'stock: UNAVAILABLE' "$txt2")"
eq "its flow section says UNAVAILABLE"      "true" "$(has 'flow: UNAVAILABLE' "$txt2")"
eq "the report ends with a PARTIAL line"    "true" "$(has 'PARTIAL REPORT' "$txt2")"
# The control for the leg above: a healthy document must NOT carry that trailer, or "partial"
# would be a decoration that fires on every run.
eq "control: a healthy report carries no PARTIAL line" "false" "$(has 'PARTIAL REPORT' "$txt")"

# ---------------------------------------------------------------------------
_summary "board-stats-selftest"
