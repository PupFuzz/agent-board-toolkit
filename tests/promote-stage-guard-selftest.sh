#!/usr/bin/env bash
# promote-stage-guard-selftest.sh — deterministic, network-free end-to-end checks for the
# source-stage guard (--shipped-stages) in bin/promote-released-cards.
#
# WHY THIS FILE EXISTS. Promotion means Shipped→Released. A DL/PR-matched card that is NOT
# in a Shipped-class source stage must never be moved — otherwise a stale or RECYCLED DL/PR
# stamp left on a declined (wont_do) card resurrects it into Released (the incident this
# guard was added for: a wont_do card carrying a stale dl_number was promoted when a later
# release recycled the DL token). The guard is OPT-IN: with no --shipped-stages the run is
# byte-identical to the prior unconditional behavior (fleet consumers adopt on their own
# windows). The guard lives in the top-level move loop (not a liftable function), so this
# exercises the REAL script end-to-end with `curl` stubbed on PATH; --dls drives ref
# derivation so no git-range / merge-tip stubbing is needed.
#
# SCOPE, WIDER THAN THE FILENAME (card#5877). This file also owns the `--cards` id-correlation
# path and the every-value-taking-flag guard, both of which need exactly this harness — the
# real script as a process, over a canned board, with its PATCH set observable. Adding a third
# selftest would have meant a third bespoke `curl` stub in tests/ (this one and the shared
# `_kb-api-stub-curl.sh` are already two, for genuinely different callers), so the cases live
# with the harness they need. The filename is NOT renamed on purpose: it names a `selftest` matrix
# entry, so a rename moves the reported check name `selftest (promote-stage-guard-selftest)`.
#
# ⚠ THIS PARAGRAPH USED TO SAY that check name "is a required status check", and that a rename
# would leave the context permanently unreported. Read live for card#8261,
# `branches/{main,dev}/protection` answer `required_status_checks: null` — nothing is required, so
# no matrix entry's name has been load-bearing on a merge. It is not going to become load-bearing
# either: the required context is the single `ci-gate` job, which `needs:` the whole matrix and
# survives any entry being renamed. That is what the aggregator is FOR. The rename is still
# avoided, for the reading reason above; the settings reason is retired.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# --- fake curl on PATH: serves the canned board on a GET, records PATCH targets+bodies ----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Minimal curl stand-in for promote-released-cards' api(): a PATCH (via `-X PATCH`) is a card
# move — log "<url>\t<body>" and return success; anything else is the paged board GET.
method=GET; url=""; data=""; want_data=0
for a in "$@"; do
  if [ "$want_data" = 1 ]; then data="$a"; want_data=0; continue; fi
  case "$a" in
    -X) method=_next ;;
    PATCH|GET|POST) [ "$method" = _next ] && method="$a" ;;
    -d) want_data=1 ;;
    http://*|https://*) url="$a" ;;
  esac
done
if [ "$method" = PATCH ]; then
  printf '%s\t%s\n' "$url" "$data" >> "$PATCH_LOG"
  printf '{"data":{"id":0}}'
else
  # STUB_GET_FAIL makes the board READ fail the way `curl -fsS` fails on a non-2xx (rc 22),
  # which is the only way to reach fetch_whole_board's read-failure die (card#7500). Scoped to
  # the GET so a test can still observe whether any PATCH was attempted after it.
  [ -n "${STUB_GET_FAIL:-}" ] && exit 22
  cat "$BOARD_FILE"
fi
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

# --- config + board fixture -------------------------------------------------------------
cat > "$TMP/release-pr.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": {
    "board_id": "12",
    "released_stage_id": "85",
    "api_base": "https://kanban.test/api/v3"
  }
}
JSON

# Two matched cards: #1 sits in a Shipped-class stage (51); #2 sits in wont_do (99). Neither
# is at the released stage (85), so neither is an idempotent "already released" skip.
export BOARD_FILE="$TMP/board.json"
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":99,"payload":{"dl_number":"DL-101"}}
],"meta":{"last_page":1,"total":2}}
JSON

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"

# run_promote <extra-args...> — invoke the real script (both DLs shipped), capturing
# rc / stdout(out) / stderr(err) / the PATCH log(patched).
run_promote() {
  : > "$PATCH_LOG"
  rc=0
  out="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100,DL-101" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"
  patched="$(cat "$PATCH_LOG")"
}

echo "== guard ON: matched card in an allowed stage promoted; disallowed-stage card skipped =="
run_promote --shipped-stages 51
eq "guard on → rc 0"                                "0"     "$rc"
eq "allowed-stage card #1 PATCHed (promoted)"       "true"  "$(has '/tasks/1.json' "$patched")"
eq "disallowed-stage card #2 NOT PATCHed (skipped)" "false" "$(has '/tasks/2.json' "$patched")"
eq "skip log names the card id"                     "true"  "$(has '(#2)' "$err")"
eq "skip log names its current stage"               "true"  "$(has 'stage 99' "$err")"
eq "skip log explains the reason"                   "true"  "$(has 'never resurrects declined/backlog cards' "$err")"
eq "summary surfaces the stage-guarded count"       "true"  "$(has '1 stage-guarded' "$out")"
eq "guard-on states stage-guard ON on stderr"      "true"  "$(has 'stage-guard ON' "$err")"
eq "guard-on ON line names the guarded stage ids"  "true"  "$(has 'Shipped-class source stages: 51' "$err")"

echo "== guard ON, whitespace in the input is tolerated (normalized) =="
run_promote --shipped-stages " 51 , 51 "
eq "whitespace-padded set still promotes #1"        "true"  "$(has '/tasks/1.json' "$patched")"
eq "whitespace-padded set still skips #2"           "false" "$(has '/tasks/2.json' "$patched")"

echo "== malformed --shipped-stages → fail loud (config error, not silent no-guard) =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" --shipped-stages "51,foo" 2>&1)" || rc=$?
eq "non-numeric token → dies rc 2"                  "2"     "$rc"
eq "die names the bad --shipped-stages value"       "true"  "$(has 'comma-separated list of numeric stage ids' "$err")"

echo "== whitespace-ONLY --shipped-stages → normalizes to empty and dies (the '' case arm) =="
# Pins that the '' arm in the validation case is REACHABLE and doing work: this input passes
# require_value (non-empty as typed) and only becomes empty after the whitespace strip. It is
# the reason that arm must not be deleted as dead code once require_value covers "".
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" --shipped-stages " " 2>&1)" || rc=$?
eq "whitespace-only → dies rc 2"                    "2"     "$rc"
eq "die reports the normalized-empty value"         "true"  "$(has "(got '')" "$err")"

echo "== EXPLICITLY EMPTY --shipped-stages → dies; never a silent unguarded promote (#5144) =="
# RED-when-reverted: drop require_value from the --shipped-stages arm and this block fails on
# every assertion — rc becomes 0, the wont_do card #2 is PATCHed (resurrected off its stale
# stamp), and the summary is byte-identical to a run with no guard at all. That silence is the
# defect: an unexpanded shell variable or an empty CI input selected the unguarded default.
run_promote --shipped-stages ""
eq "explicit empty → dies rc 2"                     "2"     "$rc"
eq "die names the flag, not an unbound variable"    "true"  "$(has '--shipped-stages requires a non-empty value' "$err")"
eq "no card was PATCHed (died before any move)"     ""      "$patched"
eq "no summary line was printed"                    "false" "$(has 'moved,' "$out")"

echo "== every value-taking flag rejects an empty value (the whole class, not one instance) =="
# "The whole class" is now an assertion rather than a claim. The list below was hand-typed and
# said five while the bin guarded six: `--cards` arrived in v0.26.0 and nothing here could go
# red about it, so this block asserted totality over 5/6 for two minor versions (card#6645).
# expect_value_flags derives the population from the bin's own guard call sites and reds in both
# directions, so the seventh flag cannot join in silence.
VALUE_FLAGS=(--dls --cards --base --head --shipped-stages --config)
expect_value_flags "$PRC" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
  rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls "DL-100" "$f" "" 2>&1)" || rc=$?
  eq "$f \"\" → dies rc 2"                          "2"     "$rc"
  eq "$f \"\" die names the flag"                   "true"  "$(has "$f requires a non-empty value" "$err")"
done

echo "== a trailing flag with no argument dies by flag name, not 'unbound variable' =="
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --dls 2>&1)" || rc=$?
eq "trailing --dls → dies rc 2"                     "2"     "$rc"
eq "die names the flag"                             "true"  "$(has '--dls requires a non-empty value' "$err")"
eq "no raw set -u unbound-variable leak"            "false" "$(has 'unbound variable' "$err")"

echo "== guard OFF (input absent): SAME fixture → prior behavior, both cards promoted =="
# RED-when-reverted anchor: if the guard is removed, the guard-ON block above would ALSO
# promote #2 (its 'NOT PATCHed' assertion flips to true→fail, and the skip-log asserts fail).
run_promote
eq "guard off → rc 0"                               "0"     "$rc"
eq "card #1 promoted"                               "true"  "$(has '/tasks/1.json' "$patched")"
eq "card #2 ALSO promoted (unconditional prior)"    "true"  "$(has '/tasks/2.json' "$patched")"
eq "guard-off summary omits stage-guarded (byte-identical line)" "false" "$(has 'stage-guarded' "$out")"
# card#5152: the summary stays byte-identical (above) AND the guard's state is stated on
# its own stderr line, every run. Before this, an ABSENT guard produced a summary
# indistinguishable from a guarded one — an unguarded promote that reads as clean.
eq "guard-off states stage-guard OFF on stderr"     "true"  "$(has 'stage-guard OFF' "$err")"
eq "guard-off OFF line names the remedy"            "true"  "$(has 'Pass --shipped-stages' "$err")"
eq "guard-off OFF line is not on stdout"            "false" "$(has 'stage-guard OFF' "$out")"
eq "guard-off run logs no skip line"                "false" "$(has 'never resurrects' "$err")"


echo "== --cards correlates on the card's own id, never on dl_number (card#5877) =="
# WHY THIS EXISTS. `ref_token_regex` and the card-id spelling are two id spaces with one
# comparison. Re-spelling that key as `card#[0-9]+` was the tempting one-line fix and is a
# live defect, shown here rather than argued: card #1's dl_number is DL-100, so asking about
# CARD id 100 under the old single-key scheme moved card #1. The `--cards` path compares the
# id instead, so card 100 (which does not exist on this board) is reported as no-card and
# card #1 is left alone.
CARDS_BOARD="$TMP/board-cards.json"
cat > "$CARDS_BOARD" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"dl_number":"DL-100"}},
  {"id":2,"workflow_stage_id":99,"payload":{"dl_number":"DL-101"}}
],"meta":{"last_page":1,"total":2}}
JSON
run_cards() { # <extra-args...> — same shape as run_promote, but driven by --cards
  : > "$PATCH_LOG"; rc=0
  BOARD_FILE="$CARDS_BOARD" out="$("$PRC" --config "$TMP/release-pr.json" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}

run_cards --cards "100"
eq "an id matching only a DL NUMBER moves nothing"   ""      "$patched"
eq "…and is reported as no-card, by id spelling"     "true"  "$(has 'card#100' "$err")"
eq "…the DL-100 card was not silently promoted"      "false" "$(has '/tasks/1.json' "$patched")"
# CONTROL — same flag, same board, an id that DOES exist. Without it every assertion above is
# satisfied by a --cards path that matches nothing at all.
run_cards --cards "1"
eq "control: an existing id IS promoted"             "true"  "$(has '/tasks/1.json' "$patched")"
eq "control: it is labelled by its id, not a DL"     "true"  "$(has 'card#1 (#1)' "$out")"
eq "control: nothing is reported no-card"            "false" "$(has 'matched NO card' "$err")"

echo "== --cards composes with --dls, and the source-stage guard still applies =="
run_cards --dls "DL-100" --cards "2"
eq "the DL leg promotes card #1"                     "true"  "$(has '/tasks/1.json' "$patched")"
eq "the id leg promotes card #2"                     "true"  "$(has '/tasks/2.json' "$patched")"
run_cards --dls "DL-100" --cards "2" --shipped-stages 51
eq "guard still skips the wont_do card matched by id" "false" "$(has '/tasks/2.json' "$patched")"
eq "…and says so"                                     "true"  "$(has 'never resurrects declined/backlog cards' "$err")"

echo "== --cards is STRICTLY numeric — a token spelling is a config error, not a parse =="
# `--dls` is a token stream that gets grepped, so junk degrades to "matched nothing". An id
# list is different: junk that greps down to a number would move a card nobody named.
for bad_in in "card#1" "#1" "1,foo" "1;2"; do
  rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --cards "$bad_in" 2>&1)" || rc=$?
  eq "--cards '$bad_in' → dies rc 2"                 "2"     "$rc"
  eq "--cards '$bad_in' names the expected shape"    "true"  "$(has 'comma-separated list of numeric card ids' "$err")"
done
rc=0; err="$("$PRC" --config "$TMP/release-pr.json" --cards "" 2>&1)" || rc=$?
eq "--cards \"\" → dies rc 2"                        "2"     "$rc"
eq "--cards \"\" names the flag"                     "true"  "$(has '--cards requires a non-empty value' "$err")"

echo "== --cards ABSENT is byte-identical to the pre-flag behavior =="
# The whole opt-in claim. The flag touched the correlation jq, the no-card report and the exit
# policy — all three on the SHARED path — so "absent = unchanged" is a property to assert, not
# to assume. The literal below is the summary this fixture produced BEFORE the flag existed,
# read off the pre-change script over this same board rather than written from expectation; it
# was additionally diffed (stdout, stderr and PATCH set) against the pre-change script across
# five invocation shapes: multi-DL with a cardless ref, the stage guard, an already-released
# card, a no-match set, and --dry-run. Pinning the literal here rather than re-deriving it in
# CI is deliberate — re-deriving would mean reading an old blob out of git history, which
# returns 128 in a depth-1 checkout and would turn this into a check that cannot run.
run_promote; base_out="$out"; base_err="$err"; base_patched="$patched"
run_promote --shipped-stages 51; guard_out="$out"; guard_err="$err"; guard_patched="$patched"
eq "unguarded stdout unchanged"  "2 moved, 0 already-released, 0 no-card, 0 failed." \
   "$(printf '%s' "$base_out" | sed -n 's/^promote-released-cards: //p')"
eq "unguarded no-card report is DL-only spelling"  "false" "$(has 'card#' "$base_err")"
eq "unguarded PATCH set is both cards"             "true"  \
   "$( [ "$(has '/tasks/1.json' "$base_patched")" = true ] && [ "$(has '/tasks/2.json' "$base_patched")" = true ] && echo true || echo false )"
eq "guarded summary still names the guarded count" "true"  "$(has '1 stage-guarded' "$guard_out")"
eq "guarded PATCH set is card #1 only"             "true"  \
   "$( [ "$(has '/tasks/1.json' "$guard_patched")" = true ] && [ "$(has '/tasks/2.json' "$guard_patched")" = false ] && echo true || echo false )"
eq "guard-state line still emitted"                "true"  "$(has 'stage-guard ON' "$guard_err")"

echo "== derive path: non-merge tip + all matches stage-guarded → the die STILL fires =="
# The 0-promoted/non-merge-tip die guards PR-MARKER completeness; a guarded skip proves
# only that a DL survived the squash and canNOT disprove a dropped sibling (#NNN) ref —
# so the die must fire even when every match was a deliberate decline-skip. RED-when-
# reverted: re-adding `[ "$guarded" = 0 ]` to the die's conjuncts turns this rc into 0.
GITDIR="$TMP/gitfx"; mkdir -p "$GITDIR"
git -C "$GITDIR" init -q -b main
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "baseline"
git -C "$GITDIR" tag v0.0.1
git -C "$GITDIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "release: v0.0.2 DL-101 squashed"
# Board: the only derivable match (DL-101 → card #2) sits in a DISALLOWED stage.
rc=0; err2="$(cd "$GITDIR" && "$PRC" --config "$TMP/release-pr.json" --shipped-stages 51 2>&1)" || rc=$?
eq "derive path, guarded-only matches, squash tip → still dies rc 2" "2" "$rc"
eq "die names the squash cause"                     "true"  "$(has 'not a merge commit' "$err2")"
eq "the guarded skip itself was logged first"       "true"  "$(has 'never resurrects declined/backlog cards' "$err2")"

echo "== api_base resolution: \$KANBAN_API_BASE overrides the config, and BOTH sources meet the SAME host guard (card#7494) =="
# WHAT THIS PINS. The committed .promote.api_base is normally a host-scrubbed placeholder — the
# real kanban host must not live in a vendored repo — and only the GUARD's side
# ($KANBAN_EXPECTED_HOST) had an env channel, so the target and the constraint could never agree
# and the tool refused unconditionally, for everyone, on its own committed config. Giving the
# TARGET the same channel is only correct if the env-supplied value is still host-validated, so
# all three arms are asserted: override absent, override valid, override INVALID-and-refused.
#
# THE OBSERVABLE IS THE URL THE PATCH ACTUALLY WENT TO, which the curl stub logs — the question
# is where the bearer token was sent, and a log line claiming a source is not that. The stderr
# source line is asserted separately, as the operator-facing half.
run_promote_env() { # <KANBAN_API_BASE value> <extra-args...> — as run_promote, with the override set
  local base="$1"; shift
  : > "$PATCH_LOG"; rc=0
  out="$(KANBAN_API_BASE="$base" "$PRC" --config "$TMP/release-pr.json" --dls "DL-100,DL-101" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}

# ARM 1 — override ABSENT: the committed value is used, byte-identically to before the override
# existed (the "unguarded stdout unchanged" block above is the stdout half of that claim).
run_promote
eq "no override → rc 0"                                "0"     "$rc"
eq "no override → the PATCH went to the CONFIG base"   "true"  "$(has 'https://kanban.test/api/v3/tasks/1.json' "$patched")"
eq "no override → the source line names the config"    "true"  "$(has "resolved from $TMP/release-pr.json .promote.api_base" "$err")"
eq "no override → it does not claim the env channel"   "false" "$(has 'resolved from $KANBAN_API_BASE' "$err")"

# ARM 1b — set-but-EMPTY reads as absent. An unset repo/org variable renders as the empty string
# through the composite action, and "no override" is the correct reading of it: the fallback is
# the config value, which meets the same guard, so the worst case is a refusal — never an
# unvalidated send. (Contrast --shipped-stages "", which MUST die: its default path is weaker
# than the flag. This one's is not.)
run_promote_env ""
eq "empty override → rc 0"                             "0"     "$rc"
eq "empty override → falls back to the CONFIG base"    "true"  "$(has 'https://kanban.test/api/v3/tasks/1.json' "$patched")"

# ARM 2 — override SET and host-valid (a subdomain of $KANBAN_EXPECTED_HOST): accepted, and the
# request goes THERE, not to the committed value. This is also the CONTROL for arm 3: without it,
# every refusal below would be satisfied by an override channel that never works at all.
run_promote_env "https://board.kanban.test/api/v3"
eq "valid override → rc 0"                             "0"     "$rc"
eq "valid override → the PATCH went to the OVERRIDE"   "true"  "$(has 'https://board.kanban.test/api/v3/tasks/1.json' "$patched")"
eq "valid override → nothing went to the config base"  "false" "$(has 'https://kanban.test/api/v3/tasks/' "$patched")"
eq "valid override → the source line names the env"    "true"  "$(has 'resolved from $KANBAN_API_BASE' "$err")"

# The success line names the CHANNEL, never the resolved base — host_ok ACCEPTS a base carrying
# userinfo (kb-host-guard-selftest asserts `https://u:pw@<expected host>/…` is accepted), so
# echoing it on the happy path would print a credential into every CI run log. Asserted on the
# value, not on the mechanism: the needle is the password.
run_promote_env "https://svc:not-a-real-password@kanban.test/api/v3"
eq "userinfo base → still promotes (host_ok accepts it)" "0"     "$rc"
eq "userinfo base → the credential is NOT echoed"        "false" "$(has 'not-a-real-password' "$err")"
eq "…nor on stdout"                                      "false" "$(has 'not-a-real-password' "$out")"

# The OTHER site in this tool that renders the resolved base: fetch_whole_board's read-failure
# die (card#7500). It fires only AFTER host_ok has accepted the base — i.e. on a real operator's
# real, legitimate, credential-bearing api_base — and it goes to stderr, so into the CI log of
# the run that just failed. Driven by failing the board GET the way `curl -fsS` does.
# EXPORTED and later UNSET explicitly, rather than as a `VAR=1 run_promote_env` prefix. The
# prefix works here — measured on this box's bash 5.2.21, default (non-POSIX) mode: it reaches
# the child and does NOT persist past the function — but `bin/board-stats` carries an in-file
# note asserting that such a prefix DOES persist past a shell function, and a security test is
# the wrong place to depend on which of those a runner's bash mode selects. This spelling has
# one meaning under every mode.
export STUB_GET_FAIL=1
run_promote_env "https://svc:not-a-real-password@kanban.test/api/v3"
eq "read failure on a userinfo base → dies rc 2"          "2"     "$rc"
# POSITIVE CONTROL: the legs below are absences, and an empty stderr satisfies them all.
eq "read failure → it IS the read-failure die (positive control)" "true" \
   "$(has 'check the token and api_base' "$err")"
eq "read failure → the credential is NOT echoed"          "false" "$(has 'not-a-real-password' "$err")"
eq "read failure → nor is the username"                   "false" "$(has 'svc@' "$err")"
# The host leg names the WHOLE rendered spelling, not just the hostname: every run of this tool
# also prints `host-guarded against 'kanban.test'` on the success/source line, so a bare
# `has 'kanban.test'` would pass even if the die itself had been redacted to nothing — measured
# under the over-redaction mutant, where it was the one leg that did not red.
eq "read failure → the die itself still names the host" "true" \
   "$(has 'api_base (https://***@kanban.test/api/v3)' "$err")"
eq "read failure → nothing was PATCHed"                   ""      "$patched"
# CONTROL — a userinfo-free base is still printed verbatim, so the mask is not a rewrite of the
# message. Without this, redacting the whole base would satisfy every absence leg above.
run_promote_env "https://kanban.test/api/v3"
eq "CONTROL: a userinfo-free base is printed verbatim"    "true"  \
   "$(has 'api_base (https://kanban.test/api/v3)' "$err")"
eq "CONTROL: …and no mask is inserted into it"            "false" "$(has '***' "$err")"
unset STUB_GET_FAIL
# WITNESS that the unset took: the very next run must read the board again, not die at the GET.
# Without it a leaked STUB_GET_FAIL would make every remaining refusal row pass for the wrong
# reason — they assert rc 2, and a failed board read is also rc 2.
run_promote_env "https://board.kanban.test/api/v3"
eq "the GET-failure switch is OFF again (witness)" "true" "$(has '/tasks/1.json' "$patched")"

# ARM 3 — override SET and host-INVALID: STILL REFUSED. This is the arm that matters. An override
# that bypassed the guard would be the regression the whole card exists to avoid — an env var is
# not trustworthy for being an env var, and the fix routes both sources through the one host_ok
# call rather than forking a second, unguarded path. RED-WHEN-REVERTED: move the host_ok call
# onto the config-only value (or skip it when the env supplied the base) and every line here
# fails — rc 0, a PATCH logged against the named host, no refusal.
#
# Each row is `<base sent>|<base the refusal must PRINT>`, and the two halves are spelled out
# rather than derived (card#7500): the printed half comes from `redact_userinfo`, so computing
# it here by calling that same function would assert only that the function equals itself. The
# last row is the one where they DIFFER — `kanban.test@evil.example` is a userinfo decoy, not a
# host, and the mask is what makes the refusal say so.
for row in \
    "https://evil.example/api/v3|https://evil.example/api/v3" \
    "http://kanban.test/api/v3|http://kanban.test/api/v3" \
    "https://kanban.test.evil.example/api/v3|https://kanban.test.evil.example/api/v3" \
    "https://kanban.test@evil.example/api/v3|https://***@evil.example/api/v3"; do
  bad_base="${row%%|*}"; shown_base="${row#*|}"
  run_promote_env "$bad_base"
  eq "override '$bad_base' → dies rc 2"                "2"     "$rc"
  eq "override '$bad_base' → NOTHING was PATCHed"      ""      "$patched"
  eq "override '$bad_base' → it is the host guard"     "true"  "$(has 'refusing to send token' "$err")"
  # Value AND channel AND refusal context in ONE needle. Split into "quotes the value" and
  # "names the env", each half is also satisfied by the SUCCESS path's source line, which says
  # the same words about an ACCEPTED base — measured: under a mutant that skipped the guard for
  # an env-supplied base, the split "names the env" assertion still passed.
  eq "override '$bad_base' → refusal names value+channel" "true" \
     "$(has "api_base '$shown_base' (from \$KANBAN_API_BASE)" "$err")"
done

# The userinfo decoy, asserted on the VALUE rather than on the presence of a mask (card#7500):
# a tool printing BOTH `***` and the userinfo would satisfy a `has '***'` check. The host leg is
# the other half — without it, a later "simplification" that redacted the whole base would pass
# the absence leg while destroying the one fact this message exists to carry.
run_promote_env "https://kanban.test@evil.example/api/v3"
eq "userinfo decoy → the refusal does NOT carry the userinfo"   "false" "$(has 'kanban.test@' "$err")"
eq "userinfo decoy → it DOES still name the host it refused"    "true"  "$(has 'evil.example' "$err")"

# …and the CONFIG side keeps refusing the same values, which is what "one guard, two sources"
# means: the guard did not move onto the env path, it stayed under both.
cat > "$TMP/release-pr-offhost.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": { "board_id": "12", "released_stage_id": "85", "api_base": "https://evil.example/api/v3" }
}
JSON
: > "$PATCH_LOG"; rc=0
err="$("$PRC" --config "$TMP/release-pr-offhost.json" --dls "DL-100" 2>&1)" || rc=$?
eq "off-host CONFIG base (no override) → dies rc 2"    "2"     "$rc"
eq "off-host CONFIG base → nothing PATCHed"            ""      "$(cat "$PATCH_LOG")"
eq "off-host CONFIG base → refusal names the config"   "true"  "$(has "(from $TMP/release-pr-offhost.json .promote.api_base)" "$err")"

# A config with NO api_base is now runnable — but only through the override, and only through
# the guard. Before card#7494 this was a hard "required in <config>" die, and the placeholder it
# was there to satisfy is what made the tool unrunnable.
cat > "$TMP/release-pr-nobase.json" <<'JSON'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": { "board_id": "12", "released_stage_id": "85" }
}
JSON
: > "$PATCH_LOG"; rc=0
err="$("$PRC" --config "$TMP/release-pr-nobase.json" --dls "DL-100" 2>&1)" || rc=$?
eq "no api_base anywhere → dies rc 2"                  "2"     "$rc"
eq "…and names BOTH ways to supply one"                "true"  \
   "$( [ "$(has 'KANBAN_API_BASE' "$err")" = true ] && [ "$(has '.promote.api_base' "$err")" = true ] && echo true || echo false )"
: > "$PATCH_LOG"; rc=0
out="$(KANBAN_API_BASE="https://kanban.test/api/v3" "$PRC" --config "$TMP/release-pr-nobase.json" --dls "DL-100" 2>"$TMP/err")" || rc=$?
eq "override alone makes a base-less config runnable"  "0"     "$rc"
eq "…and the PATCH went to the override base"          "true"  "$(has 'https://kanban.test/api/v3/tasks/1.json' "$(cat "$PATCH_LOG")")"

echo "== an explicit --base/--head that does not RESOLVE is refused by name (card#7535) =="
# WHAT WAS BROKEN. The derive path built `RANGE="$BASE..$HEAD_REF"` from the two explicit flags
# and read it with `git log "$RANGE" … 2>/dev/null || true`: `2>/dev/null` swallowed git's
# "bad object" and `|| true` converted its rc 128 into success, so an unresolvable ref produced
# an EMPTY subject list — which is what a genuinely empty range produces. The run then printed
# "no shipped refs in range — nothing to do" and exited **0**. That is a PROMOTION that promoted
# nothing and reported success: the release's cards stay un-promoted and the log looks clean.
#
# MEASURED PRE-FIX, not inferred — six of the SEVEN unresolvable-ref invocations below were
# rc 0 with that line and an empty PATCH log, on both legs, for both a nonsense NAME and a hex
# sha naming no object. The seventh (`--head <bad>` with the base DEFAULTED) was already rc 2,
# but by the wrong route: the
# `git describe "${HEAD_REF}^"` above swallows its own failure, leaving BASE empty, so it
# surfaced as "no base tag found before <head>" — a refusal that blamed the baseline for a bad
# head, after printing a NOTE about a baseline of ''.
#
# SCOPE — THE EXPLICIT LEGS ONLY, which is why the controls at the bottom of this block are not
# optional. A defaulted HEAD_REF (`HEAD`) and a defaulted BASE keep their existing refusals; the
# explicit-refs path (--dls/--cards) builds no range at all and must be untouched.
GR="$TMP/gitrange"; mkdir -p "$GR"
git -C "$GR" init -q -b main
# Identity in the fixture's own config rather than per-command `-c`: the merge tip and the
# ANNOTATED tag below both need a committer/tagger, and $HOME is the scratch dir (--home), so
# there is no global identity to fall back on.
git -C "$GR" config user.email t@t
git -C "$GR" config user.name t
git -C "$GR" commit -q --allow-empty -m "baseline"
git -C "$GR" tag v0.0.1
git -C "$GR" checkout -q -b feat
git -C "$GR" commit -q --allow-empty -m "feat: the thing DL-100"
git -C "$GR" checkout -q main
git -C "$GR" merge -q --no-ff -m "Merge the thing" feat
GR_TIP="$(git -C "$GR" rev-parse main)"

# ⛔ EVERY INVOCATION IN THIS BLOCK GOES THROUGH run_range, AND run_range PINS $GITHUB_ACTIONS.
# That is not tidiness. The derived-baseline NOTE below is emitted only when that variable is
# UNSET (`[ -n "${GITHUB_ACTIONS:-}" ] ||`, a pre-existing branch this card does not touch), so
# two arms here — the NOTE-present control and the "no NOTE about a baseline of ''" absence arm
# — mean the OPPOSITE things on a workstation and on a runner. MEASURED, not inferred: run
# UNPINNED against the pre-fix binary this block reds 17 arms in EACH environment, but not the
# SAME 17 — with the variable set the absence arm passes VACUOUSLY, satisfied by an output the
# environment had suppressed, and the NOTE-present control reds in its place. That control is
# the arm this block first shipped CI-red on, green on the same commit locally.
#
# Pinning is what makes an arm mean ONE thing in both places, and the pin is measured too: with
# it, each mutant's red set is IDENTICAL in both directions — pre-fix binary 17, `^{commit}`
# peel dropped 4, guard hoisted out of the derive branch 2, NOTE suppression deleted 1.
#
# The suppressed direction is NOT skipped: RANGE_ENV is the one knob, and the last control below
# flips it to assert the runner's branch head-on. Keep it the ONLY way this block invokes the
# tool — a hand-rolled second invocation would drift from run_range's rc/out/err/PATCH capture,
# and would silently reintroduce the ambient-environment dependence this comment exists to close.
RANGE_ENV=(-u GITHUB_ACTIONS)
run_range() { # <args...> — the real script in the range fixture, under RANGE_ENV
  : > "$PATCH_LOG"; rc=0
  out="$( (cd "$GR" && env "${RANGE_ENV[@]}" "$PRC" --config "$TMP/release-pr.json" "$@") 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"
}

badref="no-such-ref"
run_range --base v0.0.1 --head "$badref"
eq "unresolvable --head → rc 2"                     "2"     "$rc"
eq "…the refusal names the FLAG and its value"      "true"  "$(has "--head '$badref'" "$err")"
eq "…and says it resolves to no commit here"        "true"  "$(has 'does not resolve to a commit in this repo' "$err")"
eq "…it does NOT report success and stop"           "false" "$(has 'no shipped refs in range' "$out")"
eq "…and nothing was PATCHed"                       ""      "$patched"

run_range --base no-such-tag --head main
eq "unresolvable --base → rc 2"                     "2"     "$rc"
eq "…the refusal names --base and its value"        "true"  "$(has "--base 'no-such-tag'" "$err")"
eq "…rather than nothing-to-do at rc 0"             "false" "$(has 'no shipped refs in range' "$out")"

# The base leg with the head leg DEFAULTED: pre-fix this was the plain rc-0 nothing-to-do too.
run_range --base no-such-tag
eq "bad --base + defaulted head → rc 2"             "2"     "$rc"
eq "…refuses on the BASE it was handed"             "true"  "$(has "--base 'no-such-tag'" "$err")"

# ORDERING: with BOTH legs bad the BASE is named, matching bin/release-pr-body's ordering so the
# two release tools answer the same way about the same pair of flags.
run_range --base no-such-tag --head "$badref"
eq "both legs bad → the BASE is the one named"      "true"  "$(has "--base 'no-such-tag'" "$err")"
eq "…and the head is not reported instead"          "false" "$(has "--head '$badref'" "$err")"

# The head leg must nonetheless be checked BEFORE `git describe "${HEAD_REF}^"`, which swallows
# its own failure. Pre-fix this arm was rc 2 already — by blaming the baseline for a bad head.
run_range --head "$badref"
eq "bad --head + defaulted base → rc 2"             "2"     "$rc"
eq "…names the --head it was handed"                "true"  "$(has "--head '$badref'" "$err")"
eq "…not 'no base tag found', which blamed the base" "false" "$(has 'no base tag found' "$err")"
eq "…nor the NOTE about a baseline of ''"           "false" "$(has "baseline '' derived from LOCAL tags" "$err")"

# A FULL-LENGTH HEX NAMING NO OBJECT — the arm that reds if the `^{commit}` peel is dropped.
# `git rev-parse --verify -q <40-hex>` exits 0 on it (it verifies the SPELLING can become a raw
# object name, not that the object is present — measured, git 2.43.0), while `git log` dies
# `bad object`. A sha copied off a rebased-away branch or an old PR IS the deleted-ref case, and
# a raw sha is the natural hand spelling of --head. The two preconditions below are what make
# this arm mean something: without them a peel-less predicate looks equally good here.
deadsha="0000000000000000000000000000000000000001"
rc=0; ( cd "$GR" && git rev-parse --verify -q "$deadsha" ) >/dev/null 2>&1 || rc=$?
eq "precondition: the BARE predicate passes this sha" "0"   "$rc"
eq "precondition: …and git log dies on it"          "true" \
   "$(has 'bad object' "$( (cd "$GR" && git log "$deadsha" --oneline) 2>&1 || true )")"
run_range --base v0.0.1 --head "$deadsha"
eq "a hex sha naming no object as --head → rc 2"    "2"     "$rc"
eq "…named in the refusal"                          "true"  "$(has "--head '$deadsha'" "$err")"
run_range --base "$deadsha" --head main
eq "a hex sha naming no object as --base → rc 2"    "2"     "$rc"
eq "…named in the refusal"                          "true"  "$(has "--base '$deadsha'" "$err")"

# POSITIVE CONTROLS — without them a guard that refused EVERYTHING satisfies every arm above.
# Each is a resolvable spelling that must still promote, over the same fixture: a branch name,
# `HEAD`, a live raw sha (the spelling the peel must not break) and an ANNOTATED tag (a peel
# that refused non-commit objects would break the baseline every release tag actually uses).
for spelling in main HEAD "$GR_TIP"; do
  run_range --base v0.0.1 --head "$spelling"
  eq "control: --head '$spelling' still promotes (rc 0)" "0"    "$rc"
  eq "control: …and the card was PATCHed"                "true" "$(has '/tasks/1.json' "$patched")"
done
# Created for this arm and removed straight after: an annotated tag at the baseline commit WINS
# `git describe --tags --abbrev=0` (measured), so leaving it in place would silently change which
# baseline the defaulted-leg control below reports.
git -C "$GR" tag -a -m "annotated" v0.0.1-annot v0.0.1
run_range --base v0.0.1-annot --head main
eq "control: an ANNOTATED tag as --base (rc 0)"     "0"     "$rc"
eq "control: …and the card was PATCHed"             "true"  "$(has '/tasks/1.json' "$patched")"
git -C "$GR" tag -d v0.0.1-annot >/dev/null

# THE DEFAULTED PATH IS OUT OF SCOPE AND MUST BE UNCHANGED. Both legs defaulted still derives
# the baseline from local tags, still prints that NOTE, and still promotes.
run_range
eq "control: both legs defaulted still promotes"    "0"     "$rc"
eq "control: …and the card was PATCHed"             "true"  "$(has '/tasks/1.json' "$patched")"
eq "control: …and the LOCAL-tags NOTE is unchanged" "true"  "$(has "baseline 'v0.0.1' derived from LOCAL tags" "$err")"
# THE OTHER SIDE OF THAT ENVIRONMENT BRANCH, asserted rather than merely avoided by the pin:
# with $GITHUB_ACTIONS SET the NOTE is suppressed and the run still promotes. Both directions
# are pre-existing behaviour and unchanged by this card — measured on the defaulted-leg run, rc,
# stdout, the PATCH set and stderr are identical under the pre- and post-fix binaries in EACH
# environment (stderr compared with the scratch path its api_base line names normalised away,
# because the two binaries necessarily run under different mktemp dirs). Deleting the tool's
# suppression branch reds the first arm here and nothing else in this FILE — measured — so this
# is the only thing holding the runner's side of that branch.
RANGE_ENV=(GITHUB_ACTIONS=true); run_range; RANGE_ENV=(-u GITHUB_ACTIONS)
eq "control: under GITHUB_ACTIONS the NOTE is suppressed" "false" "$(has 'derived from LOCAL tags' "$err")"
eq "control: …and that run still promotes"          "0"     "$rc"
eq "control: …and the card was PATCHed"             "true"  "$(has '/tasks/1.json' "$patched")"

# …AND SO IS THE EXPLICIT-REFS PATH, which builds no range: a --base nobody can resolve is
# simply unused there, exactly as before. This pins that the guard sits inside the derive
# branch and did not move up into the parse.
run_range --dls "DL-100" --base no-such-tag
eq "control: --dls with an unresolvable --base → rc 0" "0"    "$rc"
eq "control: …and it still promotes"                   "true" "$(has '/tasks/1.json' "$patched")"

_summary "promote-stage-guard-selftest"
