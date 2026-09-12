#!/usr/bin/env bash
# promote-refusal-detail-selftest.sh — card#9301. A card move that the board REFUSES must
# report the HTTP status and the server's own explanation; and it must do so without ever
# putting a credential on stderr, without an unbounded excerpt, and WITHOUT having changed
# which answers this tool treats as success.
#
# ─────────────────────────── WHAT WENT WRONG, AND WHERE ───────────────────────────
#
# `api()` was `curl -fsS …`, and **`-f` DISCARDS the HTTP error body**. By the time the move
# loop composed `✗ <ref> (#<id>): move failed (left in place)` there was nothing left to
# report, so a 401 (token expired), a 403 (the role lacks `task.update`), a 409 (the card moved
# under us) and a 422 (wrong stage id for this board) all reached the operator as ONE sentence
# — with the released cards left sitting in the wrong column and the next action a guess.
#
# ─────────────────────── WHY THIS FILE IS BIGGER THAN THAT FIX ───────────────────────
#
# Removing `-f` is three characters and it flips curl's rc on an HTTP error from 22 to **0**.
# Both callers gate on that rc (`resp="$(api …)" || die` and `if api -X PATCH …`), so the naive
# fix makes a 401 read as a SUCCESS: the board read would return a proxy's error page as the
# board, and a refused move would print `✓ moved`. The classification therefore has to be
# re-derived inside `api()` and reproduced EXACTLY — and "exactly" is not 2xx: `curl -f` fails
# at 400 and above and passes every 3xx through, body and all (measured; the table is in the
# bin, beside the `[123]??` arm that reproduces it). §5 below drives that whole table through
# the shipped tool.
#
# Three further things could go wrong silently, and each owns a section: the excerpt could
# carry the bearer token (§3 — a debug-rendering server echoes request headers into its own
# error page, measured); it could be unbounded (§3); and dropping `-f` could have disarmed
# `--retry`, which is what rides through the deploy window this tool races (§4 — COUNTED at
# the stub, never read off the flags).
#
# ⛔ THE STATUS RIDES A FILE, NOT A VARIABLE, and §2 is what proves it: the board-read caller's
# shape is `resp="$(api …)"`, a command substitution, i.e. a SUBSHELL — a global assigned
# inside it never reaches the `die` that renders the message. A green §1 with a red §2 is
# exactly what a variable-carried status looks like.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

cat > "$TMP/release-pr.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": {
    "board_id": "12",
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3",
    "source": "*"
  }
}
JSON

export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}}
],"meta":{"last_page":1,"total":1}}
JSON

# A token with a shape a mask can be seen to act on, and long enough that a PREFIX of it is a
# recognisable leak on its own (§3's straddle case asserts no prefix survives).
TOKEN_VALUE='kbwb_AAAABBBBCCCCDDDDEEEEFFFF0123456789'
export KANBAN_WRITEBACK_TOKEN="$TOKEN_VALUE"
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"

# run_promote <extra-args…> — the real bin as a process, over the canned board.
run_promote() {
    : > "$PATCH_LOG"
    rc=0
    out="$(cd "$TMP" && KANBAN_API_BASE="${API_BASE_OVERRIDE:-}" \
        bash "$PRC" --config "$TMP/release-pr.json" --dls "DL-100" "$@" \
        2>"$TMP/err")" || rc=$?
    err="$(cat "$TMP/err")"
    patched="$(cat "$PATCH_LOG")"
}

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 1 — A REFUSED CARD MOVE NAMES THE STATUS AND THE SERVER'S OWN WORDS =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# The four statuses the card names, each driven for real through the move loop. The point is
# not that a message appeared — it is that the four are now TOLD APART, which is the operator
# action the old single sentence could not decide.
STUB_PATCH_BODY='{"message":"The given data was invalid.","errors":{"workflow_stage_id":["The selected workflow stage id is invalid."]}}'
export STUB_PATCH_BODY

for st in 401 403 409 422; do
    STUB_PATCH_STATUS="$st" run_promote
    eq "$st: the move is still reported as FAILED"        "true"  "$(has '✗ DL-100 (#1): move failed (left in place)' "$err")"
    eq "$st: …and the line now carries HTTP $st"          "true"  "$(has "HTTP $st" "$err")"
    eq "$st: …and the server's own explanation"           "true"  "$(has 'The selected workflow stage id is invalid.' "$err")"
    eq "$st: …and the summary counts one failure"         "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 failed' "$out")"
    eq "$st: …and the PATCH was really attempted"         "true"  "$(has '/tasks/1.json' "$patched")"
done

# THE DISCRIMINATOR, stated as a value rather than implied by four passing rows above: the
# four refusals must produce four DIFFERENT lines. Before this card they produced one.
distinct=0
for st in 401 403 409 422; do
    STUB_PATCH_STATUS="$st" run_promote
    printf '%s\n' "$(printf '%s' "$err" | grep -F '✗ DL-100' || true)" >> "$TMP/refusal-lines"
done
distinct="$(sort -u "$TMP/refusal-lines" | grep -c . || true)"
eq "four different refusals render four DIFFERENT lines" "4" "$distinct"

# ⛔ NEGATIVE CONTROL — the detector must NOT fire on a success. Without this every assertion
# above is satisfiable by a tool that appends `HTTP …` to every line it prints.
unset STUB_PATCH_STATUS
run_promote
eq "control: an ACCEPTED move still reports success"     "0"     "$rc"
eq "control: …as the ✓ line"                             "true"  "$(has '✓ DL-100 (#1): moved 51 → 85' "$out")"
eq "control: …with no refusal line at all"               "false" "$(has 'move failed' "$err")"
eq "control: …and no HTTP status anywhere"                "false" "$(has 'HTTP ' "$err$out")"
eq "control: …and no body excerpt anywhere"               "false" "$(has 'server said' "$err$out")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 2 — THE OTHER CALL SITE: THE BOARD READ, ACROSS A COMMAND-SUBSTITUTION SUBSHELL =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# `resp="$(api …)" || die` runs api() in a SUBSHELL. This section is the one that reds if the
# status is ever carried on a variable instead of the file — and it is driven on a
# credential-bearing api_base, because that is the base a real operator has and this die
# renders the base (card#7500).
export STUB_GET_FAIL=1
export STUB_GET_STATUS=403
export STUB_GET_BODY='{"message":"This action is unauthorized."}'
API_BASE_OVERRIDE="https://svc:not-a-real-password@kanban.test/api/v3" run_promote
eq "read refusal → dies rc 2"                            "2"     "$rc"
eq "read refusal → it IS the read-failure die"           "true"  "$(has 'check the token and api_base' "$err")"
eq "read refusal → the status CROSSED the subshell"      "true"  "$(has 'HTTP 403' "$err")"
eq "read refusal → so did the server's own words"        "true"  "$(has 'This action is unauthorized.' "$err")"
eq "read refusal → the credential is NOT echoed"         "false" "$(has 'not-a-real-password' "$err")"
eq "read refusal → nor is the username"                  "false" "$(has 'svc@' "$err")"
eq "read refusal → the base is still rendered MASKED"    "true"  "$(has 'api_base (https://***@kanban.test/api/v3)' "$err")"
eq "read refusal → nothing was PATCHed"                  ""      "$patched"

# THE TRANSPORT ARM IS A DIFFERENT STATE and must not be dressed up as a refusal: no status
# came back at all, so whether the server acted is UNKNOWN. `000` is the sentinel the lib's
# kb_api uses for the same state.
unset STUB_GET_FAIL STUB_GET_STATUS STUB_GET_BODY
export STUB_GET_TRANSPORT=7
run_promote
eq "transport failure → still dies rc 2"                 "2"     "$rc"
eq "transport failure → says the request DID NOT COMPLETE" "true" "$(has 'the request DID NOT COMPLETE' "$err")"
eq "transport failure → and says the outcome is UNKNOWN"  "true" "$(has 'UNKNOWN' "$err")"
eq "transport failure → does NOT invent an HTTP status"   "false" "$(has 'HTTP 0' "$err")"
eq "transport failure → nor claims the server said anything" "false" "$(has 'server said' "$err")"
unset STUB_GET_TRANSPORT
# WITNESS that the switch is off again — without it every later row could pass on a dead read.
run_promote
eq "the transport switch is OFF again (witness)"          "true" "$(has '/tasks/1.json' "$patched")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 3 — THE EXCERPT: MASKED FIRST, THEN BOUNDED BY A NAMED CONSTANT =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# The bound is READ OUT OF THE SHIPPED FILE by name. Writing the number here would make this
# file a second authority for it that drifts the day the bin changes (canon #16); reading it
# means these rows pin the RULE and not a figure.
MAX="$(sed -n 's/^API_ERR_EXCERPT_MAX=\([0-9][0-9]*\)$/\1/p' "$PRC")"
[ -n "$MAX" ] || { echo "selftest: no API_ERR_EXCERPT_MAX= constant in $PRC — was it inlined?" >&2; exit 1; }
ok "the bound is a NAMED constant in the bin (read back as $MAX)"
eq "…and resp_detail cuts by that NAME, not by a literal" "true" \
   "$(has 'body:0:$API_ERR_EXCERPT_MAX' "$(_fn_src "$PRC" resp_detail)")"

# Drive the SHIPPED resp_detail directly: the bound and the mask are properties of that
# function, and a unit drive is the only way to feed it a body megabytes long and a token
# placed at a chosen offset.
_adopt_fn "$PRC" resp_detail
API_ERR_FILE="$TMP/detail"; API_ERR_EXCERPT_MAX="$MAX"; TOKEN="$TOKEN_VALUE"
detail() { printf '%s\n%s' "$1" "$2" > "$API_ERR_FILE"; resp_detail; }

short='{"message":"nope"}'
got="$(detail 422 "$short")"
eq "a body under the bound is rendered WHOLE"            "true"  "$(has "$short" "$got")"
eq "…and is not marked truncated"                        "false" "$(has '[truncated' "$got")"
eq "…under its own status"                               "true"  "$(has 'HTTP 422, server said: ' "$got")"

long="$(head -c 4000 /dev/zero | tr '\0' 'x')"
got="$(detail 500 "$long")"
eq "a body over the bound IS marked truncated"           "true"  "$(has "[truncated at $MAX bytes]" "$got")"
excerpt="${got#*server said: }"; excerpt="${excerpt%…*}"
eq "…and the excerpt is exactly the bound, in bytes"     "$MAX"  "$(printf '%s' "$excerpt" | LC_ALL=C wc -c | tr -d ' ')"

# ⛔ THE BOUND IS IN BYTES, AND THE `local LC_ALL=C` PIN IS WHAT MAKES IT SO. `${#s}` and
# `${s:0:n}` are CHARACTER operations, so on a UTF-8 runner an unpinned cut takes up to four
# times the bytes it says — and "the bound" stops being one number per runner locale. A
# MULTI-BYTE body is the discriminating input: an ASCII one measures the same either way, which
# is why the row above cannot see the pin at all.
mb="$(head -c 2000 /dev/zero | tr '\0' 'x' | sed 's/x/€/g')"
got="$(detail 500 "$mb")"
excerpt="${got#*server said: }"; excerpt="${excerpt%…*}"
eq "a multi-byte body is cut at the bound in BYTES"      "$MAX"  "$(printf '%s' "$excerpt" | LC_ALL=C wc -c | tr -d ' ')"
# CONTROL — the same function with the pin REMOVED must cut MORE bytes, or the row above is
# green for a reason that has nothing to do with the pin. Run over the real artifact's text.
unpinned="$(_fn_src "$PRC" resp_detail)"
unpinned="${unpinned/resp_detail() \{/resp_detail_unpinned() \{}"
unpinned="${unpinned/  local LC_ALL=C all status body/  local all status body}"
eval "$unpinned"
got_u="$(printf '%s\n%s' 500 "$mb" > "$API_ERR_FILE"; resp_detail_unpinned)"
exc_u="${got_u#*server said: }"; exc_u="${exc_u%…*}"
bytes_u="$(printf '%s' "$exc_u" | LC_ALL=C wc -c | tr -d ' ')"
[ "$bytes_u" -gt "$MAX" ] \
  && ok "CONTROL: with the pin removed the same body cuts $bytes_u bytes, not $MAX" \
  || bad "CONTROL: the unpinned copy cut $bytes_u bytes too — this runner's locale cannot see the pin, so the row above proves nothing"

# A BODY WITH NO CONTENT AT ALL is its own answer: a 401 with an empty body must not render as
# `server said: ` with nothing after it, which reads as a truncation bug rather than a fact.
got="$(detail 401 "")"
eq "an empty body is NAMED as empty"                     "true"  "$(has 'HTTP 401, and the server sent no body' "$got")"

echo "-- § 3b THE CREDENTIAL. A debug-rendering server echoes request headers into its own"
echo "--       error page; MEASURED against a header-echoing server, the 422 body came back"
echo "--       carrying the bearer token verbatim. That is the reachable leak this masks."
echoed="{\"headers\":{\"Authorization\":\"Bearer $TOKEN_VALUE\"},\"message\":\"Server Error\"}"
got="$(detail 500 "$echoed")"
eq "an echoed bearer token is NOT rendered"              "false" "$(has "$TOKEN_VALUE" "$got")"
eq "…it is replaced by a mask"                           "true"  "$(has 'Bearer ***' "$got")"
eq "…and the rest of the body survives"                  "true"  "$(has 'Server Error' "$got")"

echo "-- § 3c THE ORDER. Mask BEFORE bound. A token STRADDLING the cut is the case that tells"
echo "--       the two orders apart: cut first and the mask no longer matches, so the token's"
echo "--       surviving PREFIX is printed."
pad_len=$(( MAX - 8 ))
straddle="$(head -c "$pad_len" /dev/zero | tr '\0' 'y')$TOKEN_VALUE tail"
got="$(detail 500 "$straddle")"
eq "a token straddling the bound leaks no whole token"    "false" "$(has "$TOKEN_VALUE" "$got")"
eq "…and no PREFIX of it either"                         "false" "$(has "${TOKEN_VALUE:0:8}" "$got")"

# ⛔ THE CONTROL THAT MAKES THE TWO ROWS ABOVE MEAN SOMETHING. An absence passes trivially for a
# function that prints nothing, or for a bound that happened to cut the token off entirely.
# This runs the INVERTED order — bound first, then mask — and requires it to LEAK, so the
# assertion is watched failing on the very mutant the ordering rule exists to exclude.
mutant_src="$(_fn_src "$PRC" resp_detail)"
mutant_src="${mutant_src/resp_detail() \{/resp_detail_mutant() \{}"
# swap the two statements: bound the body first, then try to mask it.
mutant_src="$(printf '%s\n' "$mutant_src" | sed \
  -e 's|^  body="${body//"\$TOKEN"/\*\*\*}"$|  __MASK__|' \
  -e 's|^      "\$status" "${body:0:\$API_ERR_EXCERPT_MAX}" "\$API_ERR_EXCERPT_MAX"$|      "$status" "$(printf %s "${body:0:$API_ERR_EXCERPT_MAX}" \| sed "s/\$TOKEN/***/g")" "$API_ERR_EXCERPT_MAX"|')"
mutant_src="${mutant_src/__MASK__/:}"
eval "$mutant_src"
got_m="$(printf '%s\n%s' 500 "$straddle" > "$API_ERR_FILE"; resp_detail_mutant)"
eq "CONTROL: the bound-then-mask order DOES leak a prefix" "true" "$(has "${TOKEN_VALUE:0:8}" "$got_m")"

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 4 — --retry MUST SURVIVE THE LOSS OF -f =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# WHY IT MATTERS: the merge-to-main promote job races the operator's deploy, which drops prod
# into maintenance (HTTP 503) for seconds. Card moves are idempotent and a 503 applies nothing,
# so retrying a PATCH is safe — and that whole argument is worth nothing if the retry stopped
# firing when `-f` was removed.
#
# ⛔ WHAT THIS SECTION CANNOT DO, STATED RATHER THAN FAKED. `--retry` is curl's OWN internal
# loop, and every case in this file replaces curl with a stub — so the stub IS the thing that
# would have to retry, and a stub answering 503 once is one invocation, not a retried one. A
# knob pretending otherwise would be a decoration. The BEHAVIOURAL claim was therefore measured
# against a REAL curl and a real 503-then-200 server, by hand, and is reproducible:
#
#   python3 -c 'import http.server,json,collections,sys
#   H=collections.Counter()
#   class S(http.server.BaseHTTPRequestHandler):
#    protocol_version="HTTP/1.1"
#    def log_message(s,*a): pass
#    def do_PATCH(s):
#     n=int(s.headers.get("Content-Length") or 0)
#     if n: s.rfile.read(n)
#     H[s.path]+=1; c=503 if H[s.path]<=2 else 200; b=json.dumps({"hits":H[s.path]}).encode()
#     s.send_response(c); s.send_header("Content-Length",str(len(b))); s.end_headers(); s.wfile.write(b)
#   http.server.ThreadingHTTPServer(("127.0.0.1",18931),S).serve_forever()' &
#   curl -sS --retry 5 --retry-connrefused --retry-max-time 60 -o /tmp/b -w "%{http_code}\n" \
#        -X PATCH -d "{}" http://127.0.0.1:18931/tasks/1.json
#
# MEASURED on curl 8.5.0: `200`, the server counted THREE hits, and /tmp/b holds ONE body —
# the 200's. Two facts come out of that, both load-bearing:
#   * `--retry` keys off the RESPONSE STATUS, not off `-f`, so dropping `-f` did not disarm it;
#   * with the body left on STDOUT instead of an `-o` file, the same run captures all THREE
#     bodies CONCATENATED — which is not JSON, and which fetch_whole_board would have handed to
#     jq as a board. That is why the fix uses `-o` and not a `-w` marker on stdout, and it is
#     the hazard a naive de-`-f` would have shipped.
# A loopback server is deliberately NOT started here: this suite is network-free and
# single-process by construction, and buying this one row with a bound port plus three seconds
# of backoff would trade a deterministic suite for a fact that cannot regress from inside this
# repo anyway. What CAN regress from inside this repo is the FLAG LINE, and that is pinned:
API_SRC="$(_fn_src "$PRC" api)"
for flag in '--retry 5' '--retry-connrefused' '--retry-max-time 60'; do
    eq "api() still carries $flag"                        "true"  "$(has "$flag" "$API_SRC")"
done
# ⛔ AND IT MUST NOT CARRY `-f` AGAIN. `-f` is what discarded the body this card exists to
# surface, and re-adding it would make every row of § 1 pass vacuously (a body of "" still
# renders a status). `--fail-with-body` is refused for a different reason: it needs curl >= 7.76
# and this repo declares no minimum curl anywhere, so it would move a floor by stealth.
eq "api() does not re-introduce -f"                       "false" "$(has ' -f' "$API_SRC")"
eq "…nor the long spelling"                               "false" "$(has '--fail' "$API_SRC")"
eq "api() captures the body to a FILE, not to stdout"     "true"  "$(has '-o "$API_BODY_FILE"' "$API_SRC")"
# CONTROLS — each predicate above is an ABSENCE or a presence over one string, so each is
# satisfiable by an api() that has been renamed out from under it. Watched against planted text.
eq "CONTROL: the -f predicate SEES a planted -f"          "true"  "$(has ' -f' 'curl -sS -f --retry 5')"
eq "CONTROL: the --fail predicate SEES a planted --fail"  "true"  "$(has '--fail' 'curl -sS --fail-with-body')"

# WHAT IS OBSERVABLE IN-SUITE: that the TOOL issues exactly ONE request per card and never
# wraps api() in a retry loop of its own — which is the half that would double-apply a move.
export ATTEMPT_LOG="$TMP/attempts.log"
: > "$ATTEMPT_LOG"
STUB_PATCH_STATUS=401 run_promote
eq "a refused move is attempted exactly ONCE by the tool"  "1" \
   "$(grep -cF '/tasks/1.json' "$ATTEMPT_LOG" || true)"
eq "…and is reported as a refusal"                        "true"  "$(has 'HTTP 401' "$err")"
: > "$ATTEMPT_LOG"
run_promote
eq "control: an accepted move is also attempted once"      "1" \
   "$(grep -cF '/tasks/1.json' "$ATTEMPT_LOG" || true)"
eq "control: the attempt log is not simply empty"          "true" \
   "$(has '/tasks/1.json' "$(cat "$ATTEMPT_LOG")")"
unset ATTEMPT_LOG

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 5 — THE CLASSIFICATION IS BYTE-IDENTICAL: THE SUCCESS BOUNDARY IS 400, NOT 200 =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# `curl -f` fails at 400 and above; every 3xx passes through as a SUCCESS with its body. Both
# callers gate on that rc, so reproducing it is the whole safety argument for dropping `-f`.
# Measured on curl 8.5.0 and recorded in the bin beside the `[123]??` arm; these rows pin that
# the shipped tool still ACTS on it, at the move call site (a ✓ versus a ✗).
#
# ⚠ THE 3xx ROWS ARE A PRESERVATION, NOT AN ENDORSEMENT. A 302 body is not a card, and reading
# one as an applied move is a real (reported) defect — but narrowing to 2xx changes what this
# tool accepts, which is a decision this card does not get to make silently. If that narrowing
# is ever ruled on, THESE are the rows that must be flipped deliberately.
for st in 200 201 204 301 302 307 399; do
    STUB_PATCH_STATUS="$st" run_promote
    eq "HTTP $st is a SUCCESS (as it was under curl -f)"  "true"  "$(has '✓ DL-100 (#1): moved' "$out")"
    eq "…and is not reported as a failure"                "false" "$(has 'move failed' "$err")"
done
for st in 400 401 403 404 409 422 500 503; do
    STUB_PATCH_STATUS="$st" run_promote
    eq "HTTP $st is a FAILURE (as it was under curl -f)"  "true"  "$(has '✗ DL-100 (#1): move failed' "$err")"
    eq "…and is not reported as moved"                    "false" "$(has '✓ DL-100' "$out")"
done
unset STUB_PATCH_STATUS

# The SAME boundary at the read call site: a 3xx must not reach the read-failure die. It dies
# later, on `.data` not being an array — which is the leg that catches a redirect body.
export STUB_GET_FAIL=1 STUB_GET_STATUS=302 STUB_GET_BODY='<html>moved</html>'
run_promote
eq "a 3xx board read does NOT hit the read-failure die"  "false" "$(has 'read failed' "$err")"
eq "…it is caught by the no-readable-card-array leg"     "true" \
   "$(has 'returned 0 visible cards' "$err$(cat "$TMP/err")")"
STUB_GET_STATUS=500 run_promote
eq "control: a 5xx board read DOES hit the read-failure die" "true" "$(has 'read failed' "$err")"
unset STUB_GET_FAIL STUB_GET_STATUS STUB_GET_BODY

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 6 — NOTHING BUT api() AND resp_detail() TOUCHES THE DETAIL FILES =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# The card#7500 shape, one card over: fixing two messages does not close the class. The third
# error path somebody adds next year reaches for $API_ERR_FILE because it is right there, and
# re-mints the unmasked, unbounded render — which is why resp_detail is the ONE renderable
# spelling and this row is DERIVED from the tree rather than asserted in prose.
#
# THE RULE: outside api() (which writes the detail) and resp_detail() (which reads it), the two
# names may appear only in their own declarations and the trap that removes them.
_strays() {
    awk '
      /^(api|resp_detail)\(\) \{/                     { inf = 1; next }
      inf && /^\}/                                     { inf = 0; next }
      inf                                              { next }
      /^[[:space:]]*#/                                 { next }
      /^(API_ERR_FILE|API_BODY_FILE)=/                 { next }
      /^[[:space:]]*\|\| die "cannot create a temporary file/ { next }
      /^trap /                                         { next }
      /API_ERR_FILE|API_BODY_FILE/                     { printf "%d: %s\n", FNR, $0 }
    ' "$1"
}
eq "no other site in the tool touches the detail files"  ""  "$(_strays "$PRC")"
# ⛔ THE CONTROL RUNS THE SAME awk OVER THE REAL ARTIFACT WITH ONE LINE PLANTED, not over a
# sample it minted itself: an empty result is otherwise equally consistent with an awk whose
# regex matches nothing at all.
cp "$PRC" "$TMP/prc-leak"
printf 'echo "an eleventh error path $API_ERR_FILE" >&2\n' >> "$TMP/prc-leak"
eq "CONTROL: the same predicate SEES a planted eleventh render" "true" \
   "$(has 'an eleventh error path' "$(_strays "$TMP/prc-leak")")"
# …and the inverse control: a planted line INSIDE resp_detail must be admitted, or the rule
# above is not "outside those two functions", it is "nowhere", and the fix itself would red.
eq "…and does NOT flag the legitimate readers"           "true" \
   "$(has 'API_ERR_FILE' "$(_fn_src "$PRC" resp_detail)")"

_summary "promote-refusal-detail-selftest"
