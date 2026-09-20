#!/usr/bin/env bash
# _promote-curl-stub.sh — the `curl` stand-in that lets a selftest drive
# `bin/promote-released-cards` END TO END, as a process, network-free: it serves a canned board
# on a GET and records every card move on a PATCH.
#
# WHY IT IS SHARED (card#8421). The stub is not a helper anybody wanted twice — it is the ONLY
# way to exercise this tool, whose whole subject (the correlation, the guards, the reports, the
# exit policy) lives at top level in a standalone that must not be sourced. Two selftests had
# already hand-rolled it, and a third was about to: that is the second-real-caller line, and a
# fourth divergent copy of the fixture that decides what "the board said" means is a defect in
# waiting, not a style choice. This file is the copy; a caller sources it and calls
# `promote_install_curl_stub`.
#
# ⚠ NOT YET THE ONLY COPY. `tests/promote-ref-canon-selftest.sh` keeps its own url-ONLY stub,
# because its `moved()` asserts whole-LINE equality against the logged url — this stub logs
# `<url>\t<body>`, so adopting it there would mean rewriting a deliberately strict assertion
# into a substring one. That is a change to a test's strength, which belongs in its own PR;
# it is recorded in docs/CONSOLIDATION-PLAN.md rather than folded in here.
#
# ⚠ IT MODELS `api()`'s WIRE SHAPE, WHICH CHANGED AT card#9301, AND THAT IS WHY IT HAS
# STATUSES AT ALL. `api()` used to be `curl -fsS …`, where a non-2xx meant "curl exits 22 and
# there is no body" — so a stub could model a refusal with a bare `exit 22`. It is now
# `curl -sS -o <file> -w '%{http_code}' …`: the BODY goes to the `-o` target, the STATUS goes
# to stdout through `-w`, and a refusal is rc 0 with a >=400 status. A stub that ignores `-o`
# therefore hands the tool an EMPTY body and a status made of JSON, which fails loudly rather
# than quietly — but it fails, so both are honoured below.
#
# CONTRACT — the environment the stub reads, all of it optional except the first two:
#   $BOARD_FILE     (required) the file whose contents every GET returns verbatim.
#   $PATCH_LOG      (required) appended `<url>\t<body>` on every `-X PATCH`.
#   $GET_LOG        when set, appended `<url>` on every non-PATCH request. Lets a caller
#                   assert that a refusal happened BEFORE ANY READ — an absence that is
#                   otherwise unobservable, and that `.promote.source` exists to guarantee.
#   $ATTEMPT_LOG    when set, appended `<method> <url>` on EVERY request, retries included.
#                   This is the only surface on which `--retry` is observable: a caller counts
#                   the lines rather than reading the flags (card#9301).
#   $STUB_GET_FAIL  when set, the board GET is REFUSED BY THE SERVER — the stub answers
#                   $STUB_GET_STATUS (default 500) carrying $STUB_GET_BODY. It is the only
#                   route to fetch_whole_board's read-failure die. Scoped to the GET so a
#                   caller can still see whether any PATCH was attempted after it.
#                   ⚠ IT USED TO BE SPELLED `exit 22`, which was how `curl -fsS` failed on a
#                   non-2xx. Post-card#9301 that rc means a TRANSPORT failure instead, which
#                   is a different state with a different message — see $STUB_GET_TRANSPORT.
#                   Every existing caller is unaffected: both spellings reach the same die.
#   $STUB_GET_STATUS / $STUB_GET_BODY   what $STUB_GET_FAIL answers with. Defaults 500 and a
#                   one-line JSON envelope.
#   $STUB_GET_TRANSPORT  when set, a GET exits with THIS curl rc (7 = could not connect)
#                   having written no body at all — "the request did not complete", the state
#                   whose outcome is UNKNOWN rather than refused. ⚠ IT REACHES THE BOARD GET
#                   ONLY: a single-card read is answered by its own arm first, and is killed by
#                   $STUB_CARD_TRANSPORT below.
#   $STUB_CARD_TRANSPORT  the same, for a single-card GET (`/tasks/<id>.json`) — the read a move
#                   is confirmed by. Separate from the knob above because they cannot be one:
#                   with every GET dead the board read dies first and the tool refuses before any
#                   PATCH, so the branch this drives (a stage PATCH whose read-back never
#                   completed) would be unreachable.
#   $STUB_CARD_TRANSPORT_IDS  its PER-CARD twin: a space-separated list of card ids whose
#                   single-card GET exits 7 having written nothing, while every other card reads
#                   back normally. The mixed run — one card moved, one UNVERIFIED — is a run
#                   shape the exit policy rules on and a whole-run knob cannot construct.
#   $STUB_PATCH_STATUS / $STUB_PATCH_BODY  what a PATCH answers with. Defaults 200 and
#                   `{"data":{"id":0}}`, so a caller that sets neither sees the pre-card#9301
#                   behaviour. A >=400 status here is how a REFUSED CARD MOVE is driven.
#   $STUB_PATCH_REFUSE_IDS  the PER-CARD twin of $STUB_PATCH_STATUS: a space-separated list of
#                   card ids whose PATCH is REFUSED — answered $STUB_PATCH_STATUS (default 403)
#                   carrying $STUB_PATCH_BODY — while every other card's succeeds. A whole-run
#                   status refuses every card and so can only build a run that promoted nothing;
#                   the exit policy's `moved == 0 && skipped == 0` terms are invisible to that
#                   run shape, which is why they went unmeasured for as long as they did.
#   $STUB_PATCH_TRANSPORT  the WRITE-side twin of $STUB_GET_TRANSPORT: the PATCH exits with THIS
#                   curl rc having written no body and no status. ⚠ IT IS A DIFFERENT CLAIM FROM
#                   A REFUSAL, not a variant of one — a reset AFTER the server applied the PATCH
#                   is indistinguishable here from one before it, so the card may well have
#                   MOVED. The url is still appended to $PATCH_LOG (the request was issued);
#                   what is unknown is what the far end did with it. Without this knob the whole
#                   transport branch of the MOVE loop is undriven, which is how a message
#                   asserting the card was "left in place" survived on it.
#   $STUB_CARD_BODY  the card a single-card GET (`/tasks/<id>.json`) answers with, at
#                   $STUB_CARD_STATUS (default 200), as it stood BEFORE this run's writes —
#                   see THE STUB APPLIES ITS OWN WRITES below. Default: the card of that id out
#                   of $BOARD_FILE (so its stage is the board's), given an empty `tags` list when
#                   it carries none, which is what a caller that sets neither sees.
#   $STUB_TAGS_PATCH_STATUS / $STUB_TAGS_PATCH_BODY  when the status is set, a PATCH whose body
#                   carries `"tags"` answers with it, while a stage-only PATCH keeps
#                   $STUB_PATCH_STATUS — the server's move-vs-update authorization split.
#   $STUB_STAGE_UNAPPLIED_IDS  ⛔ THE PER-CARD TWIN of $STUB_STAGE_UNAPPLIED below: a
#                   space-separated list of card ids (`"2"`, `"2 5"`) whose STAGE PATCH answers
#                   its success status, is logged, and applies nothing — while every other
#                   card's applies. It cannot be one knob with the whole-run one, and that is
#                   the point: the run shape card#9938's exit policy turns on is a MIXED one
#                   (one card moves, another is measured un-applied), and a whole-run knob can
#                   only make every card behave the same way. With a single-card board the two
#                   are indistinguishable, which is exactly how a rc-1 assertion came to be
#                   pinned in the one configuration where it happened to hold.
#   $STUB_STAGE_UNAPPLIED / $STUB_TAGS_UNAPPLIED  ⛔ THE 2xx THAT CHANGES NOTHING. When set, the
#                   matching PATCH still answers its success status and is still logged — and the
#                   stub's own card does NOT change. That is the state card#9938 exists for and
#                   the one this fleet actually met (2026-05-22: 28/28 PATCHed, every call 2xx,
#                   `updated_at` bumped, `workflow_stage_id` unchanged, the run green). Without a
#                   knob for it, a control can only drive writes that WORK, and a tool that
#                   reports from the status class passes every one of those.
#
# ⛔ THE STUB APPLIES ITS OWN WRITES, and that is what makes a read-back testable at all. A
# single-card GET does not answer a canned body: it answers the card as this stub's server now
# HOLDS it — the base above, with every PATCH it has ANSWERED SUCCESSFULLY merged over it, key by
# key (the board replaces a tag list wholesale, so a shallow merge is the right model). The merge
# is replayed from $PATCH_LOG rather than from a side file, so it carries no state a caller has
# to reset: the callers already truncate that log per run, and the stub decides each logged
# PATCH's status with the SAME rules it answered it by — a refused PATCH (>=400), one cut off by
# $STUB_PATCH_TRANSPORT, and one under an *_UNAPPLIED knob apply nothing. A base body that is not
# JSON with an object `.data` (an HTML error page, a bare `{"message":…}`) is answered VERBATIM,
# so a fixture testing an unreadable read stays unreadable.
#
# ⛔ THERE IS DELIBERATELY NO "FLAKY 503 THEN SUCCEED" KNOB, and the reason belongs here rather
# than in the caller that wanted one. `--retry` is curl's OWN internal loop, and this stub IS
# curl — so a knob answering 503 for the first N requests models N separate invocations of the
# tool, never one retried request. It would look like a retry assertion and measure nothing.
# The retry claim is a fact about curl: measured against a real 503-then-200 server, with the
# reproduction recorded in tests/promote-refusal-detail-selftest.sh § 4.

# promote_install_curl_stub <dir> — write the stub to <dir>/curl and prepend <dir> to $PATH.
promote_install_curl_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/curl" <<'STUB'
#!/usr/bin/env bash
# Minimal curl stand-in for promote-released-cards' api(): a PATCH (via `-X PATCH`) is a card
# move — log "<url>\t<body>" — and anything else is the paged board GET. The body goes to the
# `-o` target when one is given and to stdout otherwise; the status is written wherever `-w`
# asks for it, which is how api() reads it (card#9301).
method=GET; url=""; data=""; ofile=""; wfmt=""; want=""
for a in "$@"; do
  case "$want" in
    data) data="$a"; want=""; continue ;;
    ofile) ofile="$a"; want=""; continue ;;
    wfmt) wfmt="$a"; want=""; continue ;;
  esac
  case "$a" in
    -X) method=_next ;;
    PATCH|GET|POST) [ "$method" = _next ] && method="$a" ;;
    -d|--data) want=data ;;
    -o|--output) want=ofile ;;
    -w|--write-out) want=wfmt ;;
    http://*|https://*) url="$a" ;;
  esac
done

# emit <status> <body> — the ONE exit path, so no arm can forget the -o/-w routing.
emit() {
  local status="$1" body="$2"
  if [ -n "$ofile" ]; then printf '%s' "$body" > "$ofile"; else printf '%s' "$body"; fi
  if [ -n "$wfmt" ]; then printf '%s' "${wfmt//'%{http_code}'/$status}"; fi
  exit 0
}

[ -n "${ATTEMPT_LOG:-}" ] && printf '%s %s\n' "$method" "$url" >> "$ATTEMPT_LOG"

# stage_unapplied <url> — true when this card's STAGE PATCHes apply nothing: either the
# whole-run knob is set, or the card's own id is named in the per-card list.
stage_unapplied() {
  local id="${1##*/tasks/}"; id="${id%%.json*}"
  [ -z "${STUB_STAGE_UNAPPLIED:-}" ] || return 0
  case " ${STUB_STAGE_UNAPPLIED_IDS:-} " in *" $id "*) return 0 ;; esac
  return 1
}

# patch_status <url> — the status a PATCH to <url> is ANSWERED with. ONE owner, consulted by the
# PATCH arm and by applied()'s replay, so what the server holds cannot disagree with what it said.
patch_status() {
  local id="${1##*/tasks/}"; id="${id%%.json*}"
  case " ${STUB_PATCH_REFUSE_IDS:-} " in *" $id "*) printf '%s' "${STUB_PATCH_STATUS:-403}"; return 0 ;; esac
  printf '%s' "${STUB_PATCH_STATUS:-200}"
}

# applied <url> — the merged effect of every PATCH to <url> this stub ANSWERED SUCCESSFULLY, as
# one JSON object ({} when none). Replayed from $PATCH_LOG under the same status rules the PATCH
# arm below answers by, so "what the server holds" cannot disagree with "what the server said".
applied() {
  local u="$1" lurl lbody st acc='{}' merged
  [ -r "${PATCH_LOG:-}" ] || { printf '%s' "$acc"; return 0; }
  while IFS="$(printf '\t')" read -r lurl lbody; do
    [ "$lurl" = "$u" ] || continue
    if [ -n "${STUB_PATCH_TRANSPORT:-}" ]; then continue; fi
    case "$lbody" in
      *'"tags"'*) st="${STUB_TAGS_PATCH_STATUS:-$(patch_status "$u")}"
                  if [ -n "${STUB_TAGS_UNAPPLIED:-}" ]; then continue; fi ;;
      *)          st="$(patch_status "$u")"
                  if stage_unapplied "$u"; then continue; fi ;;
    esac
    case "$st" in [123]??) ;; *) continue ;; esac
    merged="$(jq -cn --argjson a "$acc" --argjson b "$lbody" '$a + $b' 2>/dev/null)" || continue
    [ -n "$merged" ] && acc="$merged"
  done < "$PATCH_LOG"
  printf '%s' "$acc"
}

if [ "$method" = PATCH ]; then
  printf '%s\t%s\n' "$url" "$data" >> "$PATCH_LOG"
  # Logged BEFORE the transport exit on purpose: the request went out either way, and a caller
  # asserting "the move really was attempted" must still be able to see it.
  [ -n "${STUB_PATCH_TRANSPORT:-}" ] && exit "$STUB_PATCH_TRANSPORT"
  case "$data" in
    *'"tags"'*) tbody='{"message":"This action is unauthorized."}'
                [ -n "${STUB_TAGS_PATCH_STATUS:-}" ] && emit "$STUB_TAGS_PATCH_STATUS" "${STUB_TAGS_PATCH_BODY:-$tbody}" ;;
  esac
  pbody='{"data":{"id":0}}'
  emit "$(patch_status "$url")" "${STUB_PATCH_BODY:-$pbody}"
fi

[ -n "${GET_LOG:-}" ] && printf '%s\n' "$url" >> "$GET_LOG"
case "$url" in
  */tasks/[0-9]*.json)
    # The single-card read that NEVER COMPLETED — no status, no body, curl's own rc. It is the
    # CARD-scoped twin of $STUB_GET_TRANSPORT, which reaches only the board GET below (this arm
    # emits before it), and without it the "the move's read-back did not complete" branch is
    # undrivable: killing every GET kills the board read first and the tool dies before any PATCH.
    [ -n "${STUB_CARD_TRANSPORT:-}" ] && exit "$STUB_CARD_TRANSPORT"
    cid="${url##*/tasks/}"; cid="${cid%%.json*}"
    # …and its PER-CARD twin: only the cards named in the list read back unreadably, so one card
    # of a run can be UNVERIFIED while another is measured. rc 7 (could not connect), the same
    # answer the whole-run knob's callers give it.
    case " ${STUB_CARD_TRANSPORT_IDS:-} " in *" $cid "*) exit 7 ;; esac
    cstatus="${STUB_CARD_STATUS:-200}"
    cempty='{"data":{"tags":[]}}'
    # A refused read answers its body verbatim: nothing was read, so there is nothing to overlay.
    case "$cstatus" in [123]??) ;; *) emit "$cstatus" "${STUB_CARD_BODY:-$cempty}" ;; esac
    cbase="${STUB_CARD_BODY:-}"
    if [ -z "$cbase" ]; then
      cbase="$(jq -c --arg id "$cid" '{data: ((.data[]? | select((.id|tostring) == $id)) // {})}
                 | .data |= (if has("tags") then . else .tags = [] end)' "$BOARD_FILE" 2>/dev/null)"
      [ -n "$cbase" ] || cbase="$cempty"
    fi
    cout="$(jq -c --argjson p "$(applied "$url")" '.data = ((.data // {}) + $p)' <<<"$cbase" 2>/dev/null)"
    # Not JSON with an object `.data` ⇒ verbatim, so an unreadable-body fixture stays unreadable.
    [ -n "$cout" ] || cout="$cbase"
    emit "$cstatus" "$cout"
    ;;
esac
# A GET that never reached a server at all: no status, no body, curl's own rc.
[ -n "${STUB_GET_TRANSPORT:-}" ] && exit "$STUB_GET_TRANSPORT"
# A GET the server ANSWERED and refused (card#7500's render path, card#9301's status path).
gbody='{"message":"Server Error"}'
[ -n "${STUB_GET_FAIL:-}" ] && emit "${STUB_GET_STATUS:-500}" "${STUB_GET_BODY:-$gbody}"
emit 200 "$(cat "$BOARD_FILE")"
STUB
    chmod +x "$dir/curl"
    export PATH="$dir:$PATH"
}
