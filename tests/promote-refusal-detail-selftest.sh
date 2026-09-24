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

# ⛔ THE WRITE THAT NEVER GOT AN ANSWER — A THIRD OUTCOME, AND A DIFFERENT CLAIM. Every row above
# drives a COMPLETED non-2xx, where `(left in place)` is a fact: the server read the PATCH and
# applied nothing. When the request does not complete, that parenthetical is a FALSE STATEMENT
# the tool is in no position to make — curl's connection can die AFTER the server applied the
# write, so the card may already have moved — and the old single line asserted `(left in place)`
# and `whether the server received it is UNKNOWN` in the same breath. An operator reading the
# first half re-runs or hand-moves a card that is possibly already moved.
# ⚑ THE STATE WAS UNDRIVEN UNTIL NOW: the stub had $STUB_GET_TRANSPORT and no PATCH twin, so the
# only transport case in this file was on the READ, which never reaches the move loop at all.
export STUB_PATCH_TRANSPORT=7
run_promote
eq "PATCH transport → the move is still reported with ✗"  "true"  "$(has '✗ DL-100 (#1):' "$err")"
eq "PATCH transport → it does NOT claim the card was left in place" "false" "$(has 'left in place' "$err")"
eq "PATCH transport → it says the move is NOT CONFIRMED"  "true"  "$(has 'move NOT CONFIRMED' "$err")"
eq "PATCH transport → and keeps the ambiguity sentence"   "true"  "$(has 'whether the server received it is UNKNOWN' "$err")"
# ⚠ NOT `has 'HTTP '` — THAT PREDICATE IS SATISFIED BY THE TRANSPORT SENTENCE ITSELF ("no HTTP
# status came back at all"), so it reds on the correct output. Written that way first and watched
# doing exactly that. resp_detail renders a status in exactly two shapes, and both are asserted
# absent by their OWN trailing text rather than by the bare protocol name: `HTTP %s, server said:`
# and `HTTP %s, and the server sent no body`.
eq "PATCH transport → renders no body excerpt"            "false" "$(has 'server said' "$err")"
eq "PATCH transport → nor the empty-body form of a status" "false" "$(has 'the server sent no body' "$err")"
eq "PATCH transport → the PATCH really was issued"        "true"  "$(has '/tasks/1.json' "$patched")"
eq "PATCH transport → and it counts as one failure"       "true"  "$(has '0 moved, 0 already-released, 0 no-card, 1 failed' "$out")"
unset STUB_PATCH_TRANSPORT
# ⛔ THE DISCRIMINATOR, AS A PAIR RATHER THAN AS FOUR ABSENCES. Each row above is satisfiable by a
# tool that simply stopped printing `left in place` — or stopped rendering a status at all —
# anywhere. These require the SAME run shape to say DIFFERENT things depending only on whether an
# answer came back, which is also the positive control for the two absence predicates above.
STUB_PATCH_STATUS=422 run_promote
eq "…while a COMPLETED refusal still says left in place"  "true"  "$(has 'move failed (left in place)' "$err")"
eq "…and does NOT borrow the not-confirmed wording"       "false" "$(has 'NOT CONFIRMED' "$err")"
eq "CONTROL: …and the excerpt predicate SEES that render" "true"  "$(has 'server said' "$err")"
# WITNESS that the transport switch is off again — without it the ✓ rows later could pass dead.
run_promote
eq "the PATCH transport switch is OFF again (witness)"    "true"  "$(has '✓ DL-100 (#1): moved' "$out")"

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
#
# ⛔ THE CONTROL HAS TO CHOOSE ITS OWN LOCALE RATHER THAN INHERIT THE RUNNER'S, and that is not a
# convenience. What the pin defends against is the AMBIENT locale, so with the pin removed the
# copy cuts more bytes only where the ambient locale is multi-byte-aware. Under `LC_ALL=C` it cuts
# exactly $MAX too — correctly — and this control then RED, reporting an ENVIRONMENT as a defect
# (measured on this tree before the fix: rc 0 under `LANG=en_US.UTF-8`, rc 1 under `LC_ALL=C`, the
# only failure being this row; `ci-gate` would have gone red on a runner, with the code innocent).
# Deleting the control was not available — it is the only thing that makes the row above mean
# anything — and neither was loosening the assertion, which is the same green-by-weakening the
# whole file exists to refuse. So the discriminating case runs under a PROBED locale in a CHILD
# process, the shape tests/locale-range-guard-selftest.sh already owns, and the box that has none
# gets a stated SKIP instead of a false accusation.
#
# THE PROBE IS THE AVAILABILITY TEST, and it asks for exactly the property the case needs —
# `${#s}` counting a 3-byte character as ONE — with a bare parameter expansion in a subprocess,
# deliberately NOT through the function under test. An uninstalled locale falls back to C
# behaviour and so fails the probe; no separate `locale -a` existence check is written, because
# its failure mode was not measured.
UTF8_LOCALE=""
for cand in en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
    if [ "$(LC_ALL="$cand" IN=$'\xe2\x82\xac' bash -c 'printf %s "${#IN}"' 2>/dev/null)" = 1 ]; then
        UTF8_LOCALE="$cand"; break
    fi
done
unpinned="$(_fn_src "$PRC" resp_detail)"
unpinned="${unpinned/resp_detail() \{/resp_detail_unpinned() \{}"
unpinned="${unpinned/  local LC_ALL=C all status body/  local all status body}"
eq "the pin really is the ONE line the control removes"  "true"  "$(has 'local all status body' "$unpinned")"
if [ -n "$UTF8_LOCALE" ]; then
    ok "a multi-byte-aware locale is available for the control ($UTF8_LOCALE reads a 3-byte character as 1)"
    printf '%s\n' "$unpinned" > "$TMP/unpinned-resp-detail.sh"
    printf '%s\n%s' 500 "$mb" > "$API_ERR_FILE"
    # The pinned and the unpinned copy are run in the SAME child under the SAME locale, so the
    # comparison is one variable — the `local LC_ALL=C` line — and not two ambient environments.
    _cut_bytes() { # <function-name> — bytes of the rendered excerpt, measured in the child
        LC_ALL="$UTF8_LOCALE" API_ERR_FILE="$API_ERR_FILE" API_ERR_EXCERPT_MAX="$MAX" \
        TOKEN="$TOKEN_VALUE" bash -c '
            . "$1"; . "$2"
            got="$('"$1"')"; exc="${got#*server said: }"; exc="${exc%…*}"; printf %s "$exc"
        ' _ "$TMP/unpinned-resp-detail.sh" "$TMP/pinned-resp-detail.sh" \
          | LC_ALL=C wc -c | tr -d ' '
    }
    _fn_src "$PRC" resp_detail > "$TMP/pinned-resp-detail.sh"
    bytes_p="$(_cut_bytes resp_detail)"
    bytes_u="$(_cut_bytes resp_detail_unpinned)"
    eq "under $UTF8_LOCALE the SHIPPED copy still cuts the bound in bytes" "$MAX" "$bytes_p"
    [ "$bytes_u" -gt "$MAX" ] \
      && ok "CONTROL: under $UTF8_LOCALE the copy with the pin removed cuts $bytes_u bytes, not $MAX" \
      || bad "CONTROL: the unpinned copy cut $bytes_u bytes under $UTF8_LOCALE — a locale this file PROVED is multi-byte-aware, so the pin is not what the row above is measuring"
else
    printf '  SKIP  no multi-byte-aware locale on this box, so the LC_ALL=C pin CANNOT be\n' >&2
    printf '        discriminated here: with the ambient locale already byte-oriented, the\n' >&2
    printf '        pinned and unpinned copies cut the same %s bytes and the row above is\n' "$MAX" >&2
    printf '        green for a reason that is not the pin. `locale -a` offers: %s\n' \
        "$(locale -a 2>/dev/null | tr '\n' ' ' | head -c 200)" >&2
    printf '        Install en_US.UTF-8 (or run under one) to exercise it.\n' >&2
fi

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

# WHAT IS OBSERVABLE IN-SUITE: that the TOOL issues exactly ONE move request per card and never
# wraps api() in a retry loop of its own — which is the half that would double-apply a move. The
# count is of PATCHes: an accepted move is followed by the owner-tag clear's card GET (§ 7), which
# is a different request, not a second attempt at the move.
export ATTEMPT_LOG="$TMP/attempts.log"
: > "$ATTEMPT_LOG"
STUB_PATCH_STATUS=401 run_promote
eq "a refused move is attempted exactly ONCE by the tool"  "1" \
   "$(grep -c '^PATCH .*/tasks/1\.json$' "$ATTEMPT_LOG" || true)"
eq "…and is reported as a refusal"                        "true"  "$(has 'HTTP 401' "$err")"
: > "$ATTEMPT_LOG"
run_promote
eq "control: an accepted move is also attempted once"      "1" \
   "$(grep -c '^PATCH .*/tasks/1\.json$' "$ATTEMPT_LOG" || true)"
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
# ⚑ `101` IS IN THIS LOOP BECAUSE THE TABLE IT MIRRORS HAS A 1xx ROW, and the `1` in `[123]??`
# has to be driven by something or it is an arm nobody measured. It is the ONLY reachable 1xx:
# an interim `100 Continue` is never what `%{http_code}` reports (measured — curl reports the
# FINAL status, 200), so the bin's table records `101` and this row is it.
for st in 101 200 201 204 301 302 307 399; do
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

# ═════════════════════════════════════════════════════════════════════════════════════════
echo "== § 7 — A RELEASED CARD LOSES ITS SEAT OWNER TAGS, BY A SEPARATE WRITE THAT NEVER BLOCKS THE MOVE =="
# ═════════════════════════════════════════════════════════════════════════════════════════
# A released card is finished, so it holds nobody's claim (README.md § The seat owner tag). The
# move stays the stage-only PATCH it always was; the clear is a fresh card read and its own
# `{tags}` PATCH. Asserted on the whole PATCH log, because a `tags` key riding the move — or a
# list built from an unreadable read — only shows in the bodies.
unset STUB_PATCH_BODY STUB_PATCH_STATUS
_move_line=$'https://kanban.test/api/v3/tasks/1.json\t{"workflow_stage_id":85}'
_tags_line=$'https://kanban.test/api/v3/tasks/1.json\t{"tags":["fr","triaged"]}'
_owned='{"data":{"id":1,"tags":["fr","owner:acme/builder","triaged","owner:other/reviewer"]}}'

STUB_CARD_BODY="$_owned" run_promote
eq "owned card: rc 0"                                     "0" "$rc"
eq "⭐ owned card: the stage-only move, THEN a PATCH carrying only the kept tags" \
   "$_move_line"$'\n'"$_tags_line" "$patched"
eq "owned card: …naming what was removed"                 "true" "$(has '✓ DL-100 (#1): removed owner tag(s) owner:acme/builder, owner:other/reviewer' "$out")"
eq "owned card: the summary is unchanged by the clear"    "true" "$(has '1 moved, 0 already-released, 0 no-card, 0 failed.' "$out")"

for _tp in 403 422; do
    STUB_CARD_BODY="$_owned" STUB_TAGS_PATCH_STATUS=$_tp STUB_TAGS_PATCH_BODY='{"message":"tag write refused by the stub"}' run_promote
    eq "tag write $_tp: rc 0"                             "0" "$rc"
    eq "tag write $_tp: the move is exactly the stage and landed; the clear followed it" \
       "$_move_line"$'\n'"$_tags_line" "$patched"
    eq "tag write $_tp: the card is still counted moved, and nothing failed" "true" "$(has '1 moved, 0 already-released, 0 no-card, 0 failed.' "$out")"
    eq "tag write $_tp: …and the clear says NOT cleared, with the server's words" "true" \
       "$(has "⚠ DL-100 (#1): owner tags NOT cleared — HTTP $_tp, server said: {\"message\":\"tag write refused by the stub\"}" "$err")"
done

# ⛔ THIS FIXTURE CHANGED MEANING AT card#9938, and the rows are rewritten rather than relaxed.
# The read it refuses is no longer only the clear's: it is the MOVE's own read-back, the one that
# decides whether this run may say the card moved. So a 403 here is not "the move landed and the
# tags were not cleared" — it is "the PATCH went out and nobody here can say what it did", which
# is the UNVERIFIED outcome (`rc 3`, `bin/kbcard`'s ladder, adopted). The old rows asserted rc 0
# and a `0 failed.` summary; both were true of the tool that reported a move from its 2xx.
STUB_CARD_STATUS=403 STUB_CARD_BODY='{"message":"This action is unauthorized."}' run_promote
eq "card read refused: no tag write, only the move"       "$_move_line" "$patched"
eq "card read refused: the MOVE is reported UNVERIFIED, with the status" "true" \
   "$(has '⚠ DL-100 (#1): move UNVERIFIED — the stage PATCH was SENT and answered success, but its outcome could NOT be read back (HTTP 403, server said: {"message":"This action is unauthorized."})' "$err")"
eq "card read refused: …and NOTHING claims the card moved" "false" "$(has '✓ DL-100 (#1): moved' "$out")"
eq "card read refused: …nor that its tags were cleared"   "false" "$(has 'owner tag' "$out$err")"
eq "card read refused: …and the run exits 3, not 0"       "3|true" "$rc|$(has '0 no-card, 1 UNVERIFIED, 0 failed.' "$out")"
eq "card read refused: …saying what an operator does next" "true" \
   "$(has 'promote-released-cards: 1 stage PATCH(es) were SENT and answered success, and their outcome could NOT be read back — UNVERIFIED WRITE (rc 3).' "$err")"
STUB_CARD_BODY='{"data":{"id":1,"tags":{"0":"owner:acme/builder"}}}' run_promote
eq "unreadable tag list: no tag write (never a list built from nothing)" "$_move_line" "$patched"
eq "unreadable tag list: …said"                           "true" "$(has 'no tag list could be read out of it' "$err")"
STUB_CARD_BODY='{"data":{"id":1,"tags":["fr"]}}' run_promote
eq "a card with no owner tag: the move alone, silently"   "$_move_line|false" "$patched|$(has 'owner tag' "$out$err")"
# THE NEGATIVE CONTROLS: a move that did not land, and a dry run, clear nothing and read nothing.
: > "$TMP/gets.log"
STUB_CARD_BODY="$_owned" STUB_PATCH_STATUS=403 GET_LOG="$TMP/gets.log" run_promote
eq "a refused move: no owner clear follows it"            "https://kanban.test/api/v3/tasks/1.json" "$(cut -f1 <<<"$patched")"
eq "…and no card read for one"                            "false" "$(has '/tasks/1.json' "$(cat "$TMP/gets.log")")"
: > "$TMP/gets.log"
STUB_CARD_BODY="$_owned" GET_LOG="$TMP/gets.log" run_promote --dry-run
eq "--dry-run: no write, and no card read"                "|false" "$patched|$(has '/tasks/1.json' "$(cat "$TMP/gets.log")")"
unset _move_line _tags_line _owned _tp

_summary "promote-refusal-detail-selftest"
