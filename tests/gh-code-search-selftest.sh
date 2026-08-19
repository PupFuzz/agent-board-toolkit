#!/usr/bin/env bash
# gh-code-search-selftest.sh — deterministic, network-free checks that `bin/gh-code-search`
# reports error / partial / complete and NEVER a bare count, driven as a real process over a
# faked `gh`.
#
# WHY THIS FILE EXISTS. `GET /search/code` answers HTTP 200 with `total_count: 0` and
# `incomplete_results: true` on a private repository — for a term that certainly exists and a
# term that cannot exist alike. The zero reads as an answer to anything that does
# `--jq '.total_count'`, which is how a cross-repository claim gets made from a search that
# never ran. The tool exists to make that state impossible to consume by accident; this file
# is what asserts it stays impossible.
#
# WHY FIXTURES AND NOT THE LIVE API — the deliberate choice, stated because the obvious
# reading is that live is free here (a private repo is a standing live positive, a public repo
# a standing negative, and both were in fact run against the real endpoint while this was
# written):
#   1. ONE OF THE FOUR STATES IS UNREACHABLE LIVE. `incomplete_results: true` with a NON-ZERO
#      count has never been observed by either seat that measured this — one of them went
#      looking with five deliberately broad queries (up to 27.5M hits) and got `false` five
#      times. That is a failure to observe, not a proof of impossibility, and the tool has to
#      handle it; a live-only suite could never exercise the arm at all.
#   2. THE LIVE POSITIVE IS NOT STABLE. `incomplete_results` varies BETWEEN CALLS on one seat,
#      same token, same query — both values were measured on one query in one window. A test
#      whose expected verdict flips between runs teaches people to re-run until green, which
#      is the same error in miniature as re-running a probe until the number looks right.
#   3. THE SEARCH API IS RATE-LIMITED to a handful of requests a minute, and roughly 2 of 9
#      probe attempts on the reference seat came back a secondary-rate-limit object. In CI
#      that is a flake with a scary message, and a suite that flakes gets ignored.
#   4. CI HAS NO TOKEN THAT CAN READ AN ARBITRARY PRIVATE REPO, so the failure branch would
#      simply not be reachable there under any spelling.
# So the fixtures are the population, and they cover shapes the live endpoint cannot be asked
# to produce on demand — an unreadable envelope, a mistyped field, a secondary-rate-limit
# body, a non-zero `gh` exit carrying a body that WOULD have parsed.
#
# A LIVE LEG EXISTS ANYWAY, opt-in, at the bottom of this file (canon #9 — a synthetic test is
# not the first real exercise of a boundary). It is OFF unless `GH_CODE_SEARCH_LIVE=1`, it
# bakes in NO repository (the toolkit is vendored onto other people's hosts and may assume
# none — the caller names both repos), and when it is off it SAYS so on stderr rather than
# passing silently, because a skipped leg that reports nothing is indistinguishable from one
# that ran.
#
# THE SEEN-TO-FAIL RECORD (canon #9 — a pass is evidence only if failure was possible). Eighteen
# mutations were applied to `bin/gh-code-search`, run, and reverted byte-identically (verified by
# `cmp` against a pre-mutation copy, not by `git checkout` — the file was untracked when this was
# done, and a checkout restore would have silently deleted it). Red counts as measured:
#   17  the ERROR verdict claims `total_count=0 incomplete_results=false` instead of UNKNOWN
#   15  UNANSWERED loses its `-eq 0` test, so a flagged zero falls through to PARTIAL — the whole
#       defect restored
#   13  the ERROR wording stops branching on the `gh` rc
#    8  the readability gate loses its item-shape clause
#    6  …its `total_count` type clause · 6  …its `incomplete_results` type clause
#    6  the UNANSWERED refusal stops naming the fallback
#    3  …its `items`-is-an-array clause · 3  the withheld emitter gains an `items` key
#    3  the withheld emitter prints `items_returned=0` · 3  UNANSWERED emits the item lines
#    2  PARTIAL exits 0 · 2  `items_truncated` pinned false · 2  the whitespace-query guard removed
#    2  `--per-page` loses its range test · 2  the query stops reaching the wire
#    1  `kb_is_uint` dropped from the `--per-page` guard
#    1  a single-dash typo becomes the query again
#
# THREE OF THOSE EIGHTEEN STARTED AT **ZERO** RED. Two were defects in the TOOL and one a gap in
# THIS FILE — recorded because the useful output of the exercise was not the green run:
#   * `if [[ "$gh_rc" -ne 0 || -z "$envelope" ]]` — mutating the rc clause away changed nothing,
#     because the parse that fills `envelope` runs only when `gh` exited 0. The clause was an
#     unfalsifiable defence against a state that cannot happen; it was REMOVED from the tool
#     rather than tested (canon #6). The rc still selects the wording, where it is observable —
#     that is the 13 above.
#   * "UNANSWERED emits the item lines anyway" — the real `unanswered` body carries no item, so
#     the assertion that no item line leaks out could not fail against it. The
#     `unanswered-with-item` fixture below exists for exactly that, and it is a FIXTURE, not a
#     handled case (see its own note).
#   * the unknown-flag arm matched `--*`, so `gh-code-search -v '<query>'` took `-v` as the QUERY
#     and sent it to GitHub as a search term. The arm is now `-*` and the case below is what
#     holds it there.
#
# THE LIVE LEG WAS ALSO SEEN TO FAIL, on the real endpoint against a real private repository:
# with the first mutation above in place the tool answered
# `PARTIAL total_count=0 … incomplete_results=true items_returned=0` at rc 3 and the leg went
# red. That run is what motivated the leg's current predicate — an earlier spelling tested rc 0
# alone and would have PASSED on that output, certifying the defect at a different exit code.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that
# the tool maps a given `gh` (rc, stdout, stderr) triple to the documented (rc, stdout, stderr)
# triple, and that its one request carries the query and per_page it was given. It proves
# nothing about what the real `search/code` returns for any query, and nothing about the
# accuracy of the prose in either file's header.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

BIN="$HERE/../bin/gh-code-search"
_need -x "$BIN"
_need -r "$HERE/../bin/_kb-board-lib.sh"

_mktmp_scratch
UB="/usr/bin:/bin"
STUB="$TMP/bin"; mkdir -p "$STUB"
cp "$HERE/_gh-code-search-stub.sh" "$STUB/gh"
chmod +x "$STUB/gh"
BODIES="$TMP/bodies"; mkdir -p "$BODIES"
OUTF="$TMP/out"; ERRF="$TMP/err"; ARGV="$TMP/argv"

# ---------------------------------------------------------------------------
# Fixture bodies. Each is a WHOLE response body, written once and named for the state it is
# meant to drive, so a case selects a shape by naming a file.
# ---------------------------------------------------------------------------

# _item <repo> <path> — one code-search item, trimmed to the three fields the tool reads.
_item() { printf '{"repository":{"full_name":"%s"},"path":"%s","html_url":"https://example.invalid/%s"}' "$1" "$2" "$2"; }

# _body <name> <total> <flag> <item…> — an envelope with N items.
_body() {
    local name="$1" total="$2" flag="$3"; shift 3
    { printf '{"total_count":%s,"incomplete_results":%s,"items":[' "$total" "$flag"
      local first=1 it
      for it in "$@"; do [[ $first -eq 1 ]] || printf ','; printf '%s' "$it"; first=0; done
      printf ']}'
    } > "$BODIES/$name.json"
}

_body complete-2   2460 false "$(_item acme/app src/A.php)" "$(_item acme/app src/B.php)"
_body complete-0   0    false
_body complete-big 80740352 false "$(_item acme/app src/A.php)"
# THE DEFECT, verbatim off the wire: this is the exact body `repo:<private> class` returned on
# the reference seat, and the byte-identical body a term that CANNOT exist returned too.
_body unanswered   0    true
_body partial-2    17   true  "$(_item acme/app src/A.php)" "$(_item acme/app src/B.php)"
# A flagged ZERO that nonetheless carries an item. GitHub has NOT been seen to produce this, and
# it exists here for a measured reason: the dispatch is on (`total_count`, `incomplete_results`)
# while `items` is an independent axis, so against the real `unanswered` body — which carries no
# item — the "no item line leaks out" assertion could not fail, and a mutation that emitted the
# items on that branch reddened NOTHING. It is a fixture, not a handled case: the tool grows no
# code for it, the branch already withholds everything, and this is what makes that observable.
_body unanswered-with-item 0 true "$(_item acme/app src/A.php)"

# Unreadable-at-200 shapes. Every one of these must be ERROR, never a zero.
printf '{"message":"You have exceeded a secondary rate limit","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#secondary-rate-limits"}' > "$BODIES/ratelimit.json"
printf '<html><body>502</body></html>'                                    > "$BODIES/html.json"
printf '{"incomplete_results":false,"items":[]}'                          > "$BODIES/no-total.json"
printf '{"total_count":3,"items":[]}'                                     > "$BODIES/no-flag.json"
printf '{"total_count":"3","incomplete_results":false,"items":[]}'        > "$BODIES/total-string.json"
printf '{"total_count":3,"incomplete_results":"false","items":[]}'        > "$BODIES/flag-string.json"
printf '{"total_count":3,"incomplete_results":false}'                     > "$BODIES/no-items.json"
printf '{"total_count":3,"incomplete_results":false,"items":{}}'          > "$BODIES/items-object.json"
printf '{"total_count":1,"incomplete_results":false,"items":[{"repository":{"full_name":"acme/app"}}]}' > "$BODIES/item-no-path.json"
printf '{"total_count":1,"incomplete_results":false,"items":[{"path":"src/A.php"}]}'                    > "$BODIES/item-no-repo.json"
printf '{"total_count":1,"incomplete_results":false,'                     > "$BODIES/truncated.json"
printf '[]'                                                               > "$BODIES/array.json"
: > "$BODIES/empty.json"

# ---------------------------------------------------------------------------
# Harness. Every case names the (rc, stdout, stderr) the fake `gh` presents; the tool's own
# (RC, OUT, ERR) come back in globals.
# ---------------------------------------------------------------------------
GRC=0; GERR=""; BODY=""

# run <tool-args…> — drive the bin as a process with the current fixture selection.
run() {
    RC=0
    : > "$ARGV"
    env PATH="$STUB:$UB" GCS_BODY="$BODY" GCS_RC="$GRC" GCS_STDERR="$GERR" GCS_ARGV="$ARGV" \
        "$BIN" "$@" >"$OUTF" 2>"$ERRF" || RC=$?
    OUT="$(cat "$OUTF")"; ERR="$(cat "$ERRF")"
}

# case_body <name> — select a 200-with-this-body fixture.
case_body() { BODY="$BODIES/$1.json"; GRC=0; GERR=""; }

# _lines <text> — line count that reports 0 for the empty string (`wc -l` on "" is 0 too, but
# a here-string appends a newline and would report 1).
_lines() { [[ -z "$1" ]] && { echo 0; return; }; printf '%s\n' "$1" | wc -l | tr -d ' '; }

# _verdict <text> — the first stdout line, which is the verdict line in every state.
_verdict() { printf '%s\n' "$1" | head -n 1; }

Q='repo:acme/app class'

# ---------------------------------------------------------------------------
# CONTROL FIRST — the harness can produce a PASS and a FAIL, and the stub is really being
# reached. Every "must refuse" assertion below is an assertion about a non-zero rc, and a stub
# that was never invoked (a stale PATH, a tool that dies before the call) would make many of
# them pass for the wrong reason.
# ---------------------------------------------------------------------------
echo "== control — the stub is on PATH and is actually the thing being called =="
case_body complete-2
run "$Q"
eq "a well-formed COMPLETE body exits 0"            "0"    "$RC"
eq "…and the stub recorded an invocation"           "true" "$([ -s "$ARGV" ] && echo true || echo false)"
eq "…and the tool did NOT reach a real gh"          "true" "$(has 'search/code' "$(cat "$ARGV")")"
# The negative half: an invocation the stub does not recognize must be fatal, so a future
# rewrite that calls `gh` some other way cannot pass by being silently answered.
eq "the stub refuses an invocation it does not recognize" "2" \
   "$(env PATH="$STUB:$UB" gh repo list >/dev/null 2>&1; echo $?)"

# ---------------------------------------------------------------------------
echo "== COMPLETE (rc 0) — an answer GitHub did not flag =="
case_body complete-2
run "$Q"
eq "rc 0"                                        "0"    "$RC"
eq "verdict line says COMPLETE"                  "true" "$(has 'COMPLETE' "$(_verdict "$OUT")")"
eq "…carries the count"                          "true" "$(has 'total_count=2460' "$(_verdict "$OUT")")"
eq "…carries the flag ON THE SAME LINE"          "true" "$(has 'incomplete_results=false' "$(_verdict "$OUT")")"
eq "…tags the count an ESTIMATE"                 "true" "$(has '(ESTIMATE)' "$(_verdict "$OUT")")"
eq "…names the exact half of the answer"         "true" "$(has 'items_returned=2' "$(_verdict "$OUT")")"
eq "…echoes the query"                           "true" "$(has "query=$Q" "$(_verdict "$OUT")")"
eq "one verdict line + one line per item"        "3"    "$(_lines "$OUT")"
eq "an item line carries repo and path"          "true" "$(has "acme/app$(printf '\t')src/A.php" "$OUT")"
eq "a short page is not reported truncated"      "true" "$(has 'items_truncated=false' "$OUT")"
eq "nothing is written to stderr on a clean run" "0"    "$(_lines "$ERR")"

# ⛔ THE REFUTED MODULUS, asserted as behaviour rather than as a comment. 2460 is not divisible
# by 8 and IS a real stable code-search answer (measured, in a window that also returned 4472).
# A tool that had encoded "every total_count is divisible by 8" would have to reject, round or
# flag this; it passes through byte-identically.
eq "a count that is NOT divisible by 8 passes through verbatim" "true" "$(has 'total_count=2460 ' "$OUT")"
case_body complete-big
run "$Q"
eq "a coarse 8-figure count also passes through verbatim" "true" "$(has 'total_count=80740352 ' "$OUT")"
eq "…still tagged an ESTIMATE"                            "true" "$(has '(ESTIMATE)' "$OUT")"

# A GENUINE no-match. This is the one zero the tool is allowed to report, and it must stay
# reportable — a guard that refused every zero would be unusable and would get routed around.
case_body complete-0
run "$Q"
eq "an UNFLAGGED zero is a real answer: rc 0"     "0"    "$RC"
eq "…reported as COMPLETE"                        "true" "$(has 'COMPLETE' "$OUT")"
eq "…with the count and the flag together"        "true" "$(has 'total_count=0 (ESTIMATE) incomplete_results=false' "$OUT")"
eq "…and no item lines"                           "1"    "$(_lines "$OUT")"

# ---------------------------------------------------------------------------
echo "== UNANSWERED (rc 4) — the defect: a flagged ZERO is not \"no matches\" =="
case_body unanswered
run "$Q"
eq "rc 4"                                          "4"     "$RC"
eq "verdict says UNANSWERED"                       "true"  "$(has 'UNANSWERED' "$OUT")"
eq "…the count and the flag are on that one line"  "true"  "$(has 'total_count=0 (ESTIMATE) incomplete_results=true' "$OUT")"
eq "…and it says the results are WITHHELD"         "true"  "$(has 'results=WITHHELD' "$OUT")"
# THE CENTRAL INVARIANT: no empty result set, in any spelling. Not an empty stdout, not an
# `items_returned=0`, not an item line.
eq "stdout carries the verdict and NOTHING else"   "1"     "$(_lines "$OUT")"
eq "stdout never says items_returned=0"            "false" "$(has 'items_returned' "$OUT")"
eq "stderr refuses the zero in words"              "true"  "$(has 'That zero is NOT "no matches"' "$ERR")"
eq "stderr names the git/trees fallback"           "true"  "$(has 'git/trees/<ref>?recursive=1' "$ERR")"
eq "stderr names the contents fallback"            "true"  "$(has '/contents/<path>' "$ERR")"
eq "…with the repo resolved out of the query"      "true"  "$(has 'repos/acme/app/git/trees' "$ERR")"
# ⛔ NO STABILITY HEURISTIC — measured, not grepped. The confounded "a `false` flag comes with a
# stable count" hypothesis would be implemented as a re-run; exactly one request is issued, so
# there is no retry loop to have encoded it in.
eq "exactly ONE gh invocation — no retry loop"     "true"  "$(has 'search/code' "$(cat "$ARGV")")"
eq "…and that invocation carried one q="           "1"     "$(grep -c "^q=$Q\$" "$ARGV")"

case_body unanswered-with-item
run "$Q"
eq "a flagged zero carrying an item is STILL fatal"  "4"     "$RC"
eq "…and the item does NOT leak out"                 "1"     "$(_lines "$OUT")"
eq "…nor its path"                                   "false" "$(has 'src/A.php' "$OUT")"
run --format json "$Q"
eq "…nor through --format json"                      "false" "$(printf '%s' "$OUT" | jq -r 'has("items")')"

# A query with no `repo:` qualifier still gets a recipe, with placeholders and a note saying so
# — never a silent omission of the way through.
run 'org:acme HTTP 409'
eq "an org-wide query still refuses at rc 4"       "4"     "$RC"
eq "…and still names the fallback"                 "true"  "$(has 'git/trees/<ref>?recursive=1' "$ERR")"
eq "…with placeholders, since no repo is named"    "true"  "$(has 'repos/<owner>/<repo>/git/trees' "$ERR")"
eq "…and says why they are placeholders"           "true"  "$(has 'names no single `repo:`' "$ERR")"

# ---------------------------------------------------------------------------
echo "== PARTIAL (rc 3) — flagged but NON-ZERO: loud, and still usable =="
# Never observed live by either seat that measured this endpoint; reachable only here. A
# blanket fatal was rejected because it collapses "could not answer" into "answered partially",
# so this arm's whole point is that the items survive while the COUNT does not.
case_body partial-2
run "$Q"
eq "rc 3 — not 0, and not the fatal 4"        "3"    "$RC"
eq "verdict says PARTIAL"                     "true" "$(has 'PARTIAL' "$OUT")"
eq "…count and flag together"                 "true" "$(has 'total_count=17 (ESTIMATE) incomplete_results=true' "$OUT")"
eq "the items ARE emitted — this is usable"   "3"    "$(_lines "$OUT")"
eq "…and they are the real matches"           "true" "$(has "acme/app$(printf '\t')src/B.php" "$OUT")"
eq "stderr says the count is not authoritative" "true" "$(has 'COUNT is not authoritative' "$ERR")"
eq "stderr names the fallback here too"       "true" "$(has 'git/trees/<ref>?recursive=1' "$ERR")"

# ---------------------------------------------------------------------------
echo "== ERROR (rc 1) — the third state: an unreadable response is not an empty one =="
# THE CRISP CONTROL for "gate on the command's rc, never on the output's shape": the body here
# is the SAME one that produces COMPLETE above. Only `gh`'s exit status differs.
BODY="$BODIES/complete-2.json"; GRC=1; GERR='gh: ERROR_TYPE_QUERY_PARSING_FATAL unable to parse query! (HTTP 422)'
run "$Q"
eq "a non-zero gh exit is ERROR even with a parseable body" "1" "$RC"
eq "…the verdict does NOT claim a count"      "true"  "$(has 'total_count=UNKNOWN' "$OUT")"
eq "…nor a flag"                              "true"  "$(has 'incomplete_results=UNKNOWN' "$OUT")"
eq "…results WITHHELD"                        "true"  "$(has 'results=WITHHELD' "$OUT")"
eq "…and NO item line leaks through"          "1"     "$(_lines "$OUT")"
eq "…the count from the body never appears"   "false" "$(has '2460' "$OUT")"
eq "stderr quotes what gh said"               "true"  "$(has 'ERROR_TYPE_QUERY_PARSING_FATAL' "$ERR")"
eq "stderr forbids the no-matches reading"    "true"  "$(has 'Do NOT read this as "no matches"' "$ERR")"
eq "stderr names the fallback"                "true"  "$(has 'git/trees/<ref>?recursive=1' "$ERR")"

# Every 200-with-an-unreadable-body shape. The list is the tool's readability gate read as a
# population — one case per clause of it, plus the two live shapes (a secondary-rate-limit
# object and an HTML error page) that motivated the gate in the first place.
echo "-- 200 bodies that must be ERROR, never a zero --"
for shape in ratelimit html no-total no-flag total-string flag-string no-items items-object \
             item-no-path item-no-repo truncated array empty; do
    case_body "$shape"
    run "$Q"
    eq "200 + $shape → rc 1"                   "1"     "$RC"
    eq "200 + $shape → no count claimed"       "true"  "$(has 'total_count=UNKNOWN' "$OUT")"
    eq "200 + $shape → no item line"           "1"     "$(_lines "$OUT")"
    eq "200 + $shape → not read as zero"       "true"  "$(has 'unreadable response is not an empty one' "$ERR")"
done

# ---------------------------------------------------------------------------
echo "== --format json — the same four states, and the same withholding =="
case_body complete-2
run --format json "$Q"
eq "COMPLETE json rc 0"                       "0"          "$RC"
eq "…state"                                   "COMPLETE"   "$(printf '%s' "$OUT" | jq -r .state)"
eq "…count"                                   "2460"       "$(printf '%s' "$OUT" | jq -r .total_count)"
eq "…flag is in the SAME object"              "false"      "$(printf '%s' "$OUT" | jq -r .incomplete_results)"
eq "…and the count is labelled an estimate"   "true"       "$(printf '%s' "$OUT" | jq -r .total_count_is_estimate)"
eq "…items carry repository and path"         "src/A.php"  "$(printf '%s' "$OUT" | jq -r '.items[0].path')"
eq "…one object, one line"                    "1"          "$(_lines "$OUT")"

case_body unanswered
run --format json "$Q"
eq "UNANSWERED json rc 4"                     "4"           "$RC"
eq "…state"                                   "UNANSWERED"  "$(printf '%s' "$OUT" | jq -r .state)"
# `has_key`, not `.items == null`: a JSON consumer doing `.items | length` gets 0 from a null
# just as it does from `[]`, so the key has to be ABSENT for the withholding to be legible.
eq "…the object carries NO items key at all"  "false"       "$(printf '%s' "$OUT" | jq -r 'has("items")')"
eq "…nor an items_returned"                   "false"       "$(printf '%s' "$OUT" | jq -r 'has("items_returned")')"
eq "…it says results are WITHHELD"            "WITHHELD"    "$(printf '%s' "$OUT" | jq -r .results)"
eq "…the zero is still shown"                 "0"           "$(printf '%s' "$OUT" | jq -r .total_count)"
eq "…beside its flag, in the same object"     "true"        "$(printf '%s' "$OUT" | jq -r .incomplete_results)"

case_body partial-2
run --format json "$Q"
eq "PARTIAL json rc 3"                        "3"           "$RC"
eq "…state"                                   "PARTIAL"     "$(printf '%s' "$OUT" | jq -r .state)"
eq "…items survive"                           "2"           "$(printf '%s' "$OUT" | jq -r '.items | length')"
eq "…flag rides with them"                    "true"        "$(printf '%s' "$OUT" | jq -r .incomplete_results)"

BODY="$BODIES/ratelimit.json"; GRC=0; GERR=""
run --format json "$Q"
eq "ERROR json rc 1"                          "1"           "$RC"
eq "…state"                                   "ERROR"       "$(printf '%s' "$OUT" | jq -r .state)"
eq "…count is null, never 0"                  "null"        "$(printf '%s' "$OUT" | jq -r .total_count)"
eq "…flag is null, never false"               "null"        "$(printf '%s' "$OUT" | jq -r .incomplete_results)"
eq "…no items key"                            "false"       "$(printf '%s' "$OUT" | jq -r 'has("items")')"

# ---------------------------------------------------------------------------
echo "== the wire — what was actually sent =="
case_body complete-2
run --per-page 7 "$Q"
argv="$(cat "$ARGV")"
eq "GET is explicit"                          "true" "$(has '--method' "$argv")"
eq "…the path is search/code"                 "1"    "$(grep -c '^search/code$' "$ARGV")"
eq "…the query rides verbatim in q="          "1"    "$(grep -c "^q=$Q\$" "$ARGV")"
eq "…per_page is what was asked for"          "1"    "$(grep -c '^per_page=7$' "$ARGV")"
eq "…and the default is the endpoint maximum" "1"    "$(run "$Q"; grep -c '^per_page=100$' "$ARGV")"

# items_truncated errs toward "there is more": a page that comes back FULL cannot be known to
# be the whole set, so it is flagged even though total_count would suggest otherwise.
run --per-page 2 "$Q"
eq "a FULL page is reported truncated"        "true" "$(has 'items_truncated=true' "$OUT")"
eq "…and says so on stderr as well"           "true" "$(has 'came back FULL' "$ERR")"
run --per-page 3 "$Q"
eq "a page short of --per-page is not"        "true" "$(has 'items_truncated=false' "$OUT")"
eq "…and stays quiet on stderr"               "0"    "$(_lines "$ERR")"

# ---------------------------------------------------------------------------
echo "== usage refusals (rc 2) — and the ONE that is rc 1 =="
case_body complete-2
_usage_rc() { run "$@"; printf '%s' "$RC"; }
eq "no query at all"                    "2" "$(_usage_rc)"
eq "an empty query"                     "2" "$(_usage_rc '')"
eq "a whitespace-only query"            "2" "$(_usage_rc '   ')"
eq "…refused BEFORE any request"        "0" "$(run '   '; wc -c < "$ARGV" | tr -d ' ')"
eq "a second positional"                "2" "$(_usage_rc "$Q" 'extra')"
eq "an unknown flag"                    "2" "$(_usage_rc --bogus "$Q")"
# SINGLE dash too. `-v` is passed ALONE, and that is the whole point of the case: with a real
# query beside it the second positional refuses at rc 2 anyway, so the first spelling of this
# assertion passed under BOTH arms and reddened nothing when the arm was mutated back to `--*`.
# Alone, `-v` under a `--*` arm becomes the QUERY and is sent to GitHub as a search term at rc 0.
eq "a single-dash typo alone is a flag, not a query" "2" "$(_usage_rc -v)"
eq "--per-page with no value"           "2" "$(_usage_rc "$Q" --per-page)"
eq "--per-page empty"                   "2" "$(_usage_rc --per-page '' "$Q")"
eq "--per-page non-numeric"             "2" "$(_usage_rc --per-page abc "$Q")"
eq "--per-page 0"                       "2" "$(_usage_rc --per-page 0 "$Q")"
eq "--per-page 101"                     "2" "$(_usage_rc --per-page 101 "$Q")"
eq "--per-page 100 is accepted"         "0" "$(_usage_rc --per-page 100 "$Q")"
eq "--format with no value"             "2" "$(_usage_rc "$Q" --format)"
eq "--format bogus"                     "2" "$(_usage_rc --format yaml "$Q")"
# A non-ASCII digit must not satisfy the numeric guard — `kb_is_uint` matches under LC_ALL=C,
# and this is the assertion that keeps it doing so from here.
eq "--per-page with an Arabic-Indic digit" "2" "$(LC_ALL=en_US.UTF-8 _usage_rc --per-page '٣' "$Q")"

run --bogus "$Q"
eq "an unknown flag prints usage on stderr"  "true" "$(has 'usage: gh-code-search' "$ERR")"
eq "…and nothing on stdout"                  "0"    "$(_lines "$OUT")"

# `gh` missing is rc 2 (the run cannot be SET UP), matching release-artifacts-check's
# `jq is required` refusal — deliberately NOT rc 1, which means "the search ran and could not
# be trusted".
#
# A HAND-BUILT PATH, not `PATH=/usr/bin:/bin` minus a stub: the reference host has a REAL `gh`
# in /usr/bin, so the obvious spelling found it, issued a live search for a fixture repo and
# came back rc 4 — a network call from a "network-free" suite, passing for the wrong reason
# twice over. NOGH holds only what the tool legitimately needs, so the absence being asserted
# is the one named.
NOGH="$TMP/nogh"; mkdir -p "$NOGH"
# `bash` and `env` are in the list because the tool's `#!/usr/bin/env bash` shebang resolves
# `bash` through PATH: without them the run dies rc 127 and the rc-2 assertion below would be
# measuring a missing interpreter, not a missing dependency.
for c in bash env jq mktemp awk sed readlink basename dirname cat; do ln -sf "$(command -v "$c")" "$NOGH/$c"; done
_on_nogh() { env PATH="$NOGH" "$NOGH/bash" -c "command -v $1 >/dev/null 2>&1" && echo true || echo false; }
eq "the no-gh PATH really has no gh"      "false" "$(_on_nogh gh)"
eq "…and still has the jq the tool needs" "true"  "$(_on_nogh jq)"
eq "…and still resolves its own shared lib"  "true"  "$(_on_nogh dirname)"
RC=0; env PATH="$NOGH" "$BIN" "$Q" >"$OUTF" 2>"$ERRF" || RC=$?
eq "a PATH with no gh refuses at rc 2"       "2"    "$RC"
eq "…and says which dependency"              "true" "$(has 'gh is required' "$(cat "$ERRF")")"

# The lib-less install: rc 1 on EVERY invocation, including --help, matching every other
# lib-sourcing bin. A copy is used rather than the real bin so the tree is untouched.
mkdir -p "$TMP/lonely/bin"; cp "$BIN" "$TMP/lonely/bin/gh-code-search"
RC=0; env PATH="$STUB:$UB" "$TMP/lonely/bin/gh-code-search" --help >"$OUTF" 2>"$ERRF" || RC=$?
eq "vendored without _kb-board-lib.sh: rc 1"  "1"    "$RC"
eq "…naming the lib and the fix"              "true" "$(has '_kb-board-lib.sh not found' "$(cat "$ERRF")")"

# ---------------------------------------------------------------------------
echo "== --help =="
# help-output-selftest.sh owns the whole-header equality and the channel; this pair only pins
# that --help never reaches the network, which is this file's concern and not that one's.
run --help
eq "--help exits 0"                          "0"     "$RC"
eq "…prints the Usage block"                 "true"  "$(has 'Usage: gh-code-search' "$OUT")"
eq "…and issues no request"                  "0"     "$(wc -c < "$ARGV" | tr -d ' ')"

# ---------------------------------------------------------------------------
# OPT-IN LIVE LEG. Off by default; see the header for why the fixtures above are the
# population and this is the real-surface exercise rather than the other way round.
# ---------------------------------------------------------------------------
if [[ "${GH_CODE_SEARCH_LIVE:-}" == "1" ]]; then
    echo "== LIVE (GH_CODE_SEARCH_LIVE=1) — the real endpoint, real token =="
    priv="${GH_CODE_SEARCH_LIVE_PRIVATE_REPO:-}"
    pub="${GH_CODE_SEARCH_LIVE_PUBLIC_REPO:-}"
    if [[ -z "$priv" || -z "$pub" ]]; then
        bad "LIVE requested but GH_CODE_SEARCH_LIVE_PRIVATE_REPO / GH_CODE_SEARCH_LIVE_PUBLIC_REPO are not both set — nothing was measured (no repository is baked in: this toolkit is vendored onto other people's hosts)"
    else
        # The private leg is the known live POSITIVE for the failure branch. It asserts the
        # weakest thing that is still the defect: a zero was not presented as CONSUMABLE.
        # Consumable is rc 0 and rc 3 — the two states that emit a result set — so both are in
        # the predicate; an earlier spelling tested rc 0 alone and would have passed a mutated
        # tool that routed the flagged zero into PARTIAL at rc 3, which is the same defect
        # wearing a different code. Asserting rc 4 EXACTLY is deliberately not done: the flag is
        # measured to vary between calls, so that spelling would make the suite flake on a
        # property of GitHub rather than of this tool.
        RC=0; "$BIN" --per-page 1 "repo:$priv class" >"$OUTF" 2>"$ERRF" || RC=$?
        eq "LIVE private repo: a zero is never presented as consumable" "false" \
           "$([[ ( "$RC" -eq 0 || "$RC" -eq 3 ) && "$(has 'total_count=0 ' "$(cat "$OUTF")")" == true ]] && echo true || echo false)"
        echo "     (live private verdict: rc=$RC · $(head -n 1 "$OUTF"))"
        # The public leg is the known live NEGATIVE: the tool must not refuse a search that
        # really did run. rc 3 is tolerated for the same varies-between-calls reason.
        RC=0; "$BIN" --per-page 1 "repo:$pub class" >"$OUTF" 2>"$ERRF" || RC=$?
        eq "LIVE public repo: answers, does not refuse" "true" \
           "$([[ "$RC" -eq 0 || "$RC" -eq 3 ]] && echo true || echo false)"
        echo "     (live public verdict: rc=$RC · $(head -n 1 "$OUTF"))"
    fi
else
    echo "== LIVE leg SKIPPED — set GH_CODE_SEARCH_LIVE=1 plus GH_CODE_SEARCH_LIVE_PRIVATE_REPO"
    echo "   and GH_CODE_SEARCH_LIVE_PUBLIC_REPO to exercise the real endpoint. Nothing above"
    echo "   touched the network, so nothing above is a claim about what GitHub returns." >&2
fi

_summary gh-code-search-selftest
