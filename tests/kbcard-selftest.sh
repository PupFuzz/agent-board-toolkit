#!/usr/bin/env bash
# kbcard-selftest.sh — deterministic, network-free unit checks for kbcard's pure
# mapping logic: stage_name (the KB_STAGE_* reverse lookup) and _kbc_annotate_card
# (show's stage/column population). The rule under test is omit-don't-null (card
# #4387): a `"stage": null` emitted for a card that IS in a stage reads as "no
# stage" and caused a false "auto-move is broken" escalation. Sources the bin
# (main-guarded) and asserts on its pure functions. Matches the toolkit's
# selftest-CI convention (no bats/shunit2; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# The comment/comments block at the end drives the bin as a PROCESS against a faked kanban
# (a `curl` stand-in on PATH), so the real kb_api decides success on the HTTP status class.
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
BIN="$HERE/../bin/kbcard"
_need -r "$BIN"
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines stage_name / _kbc_annotate_card without running

# annot <task-json> <jq-expr>: run the annotator and project one value out.
annot() { _kbc_annotate_card "$1" | jq -c "$2"; }

# kbc <args…> — run the REAL bin as a process on a fresh request log; sets rc/out/err.
# One definition serves every process-driving section below — the runner is identical for
# all of them, so only the per-section `kb_stub_route` is torn down between them.
kbc() { kb_stub_reset; rc=0; out="$("$BIN" "$@" 2>"$TMP/e")" || rc=$?; err="$(cat "$TMP/e")"; }

# The operator's shell may have a real board env sourced (they `export` their
# keys) — scrub every KB_STAGE_* so no live board id can fake a pass or a fail.
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}

# ---------------------------------------------------------------------------
echo "== stage_name — KB_STAGE_* reverse lookup =="
export KB_STAGE_BACKLOG=48
export KB_STAGE_SHIPPED_TO_DEV=51

eq "known id resolves to its column name"      "backlog"        "$(stage_name 48)"
eq "multi-word suffix keeps its underscores"   "shipped_to_dev" "$(stage_name 51)"

rc=0; out="$(stage_name 999)" || rc=$?
eq "unknown id → rc 1"        "1" "$rc"
eq "unknown id → no output"   ""  "$out"

export KB_STAGE_EMPTY=""
rc=0; stage_name "" >/dev/null || rc=$?
eq "empty id never matches (even an empty-valued var)" "1" "$rc"
unset KB_STAGE_EMPTY

# A board's OWN taxonomy resolves too — the lookup is any KB_STAGE_*, not the
# eight stage_id aliases.
export KB_STAGE_TESTING=77
eq "non-alias KB_STAGE_ var resolves" "testing" "$(stage_name 77)"
unset KB_STAGE_TESTING

# ---------------------------------------------------------------------------
echo "== _kbc_annotate_card — show's stage/column population (omit, don't null) =="

# THE defect (card #4387): show must map the real stage id into `stage` — parity
# with list — and resolve `column` from the board env.
eq "stage populated from workflow_stage_id"  "48"          "$(annot '{"id":1,"workflow_stage_id":48}' '.stage')"
eq "column resolved from KB_STAGE_* env"     '"backlog"'   "$(annot '{"id":1,"workflow_stage_id":48}' '.column')"

# Unknown stage id ⇒ NO column key — not null (null reads as "no stage").
eq "unknown stage id still populates stage"  "999"   "$(annot '{"id":1,"workflow_stage_id":999}' '.stage')"
eq "unknown stage id ⇒ column key OMITTED"   "false" "$(annot '{"id":1,"workflow_stage_id":999}' 'has("column")')"

# A serializer that itself emits null stage/column (the shape the peer hit) is
# corrected: stage overwritten with the real id, an unresolvable column DELETED.
eq "serializer null stage overwritten with the real id" "48" \
   "$(annot '{"id":1,"workflow_stage_id":48,"stage":null,"column":null}' '.stage')"
eq "serializer null column resolved when the env maps it" '"backlog"' \
   "$(annot '{"id":1,"workflow_stage_id":48,"stage":null,"column":null}' '.column')"
eq "serializer null column DELETED when unresolvable" "false" \
   "$(annot '{"id":1,"workflow_stage_id":999,"stage":null,"column":null}' 'has("column")')"

# No workflow_stage_id at all ⇒ neither key is fabricated.
eq "no workflow_stage_id ⇒ no stage key"  "false" "$(annot '{"id":1}' 'has("stage")')"
eq "no workflow_stage_id ⇒ no column key" "false" "$(annot '{"id":1}' 'has("column")')"

# Everything else in the task passes through untouched.
eq "other fields pass through" '"card"' "$(annot '{"id":1,"workflow_stage_id":48,"name":"card"}' '.name')"

unset KB_STAGE_BACKLOG KB_STAGE_SHIPPED_TO_DEV

echo "== _kbc_write_echo: payload rides only when the serializer sent the key (card #4390) =="
# It takes the RESPONSE as an argument (card#6426) rather than reading stdin, because it now
# owns the refusal for a 2xx body no card can be read out of — and a refusal needs the verb and
# the subject the caller typed, which stdin cannot carry.
we() { _kbc_write_echo patch "on task 1" "$@"; }
r="$(we '{"data":{"id":1,"name":"x","workflow_stage_id":5}}')"
eq "absent payload key → omitted"  "false" "$(jq 'has("payload")' <<<"$r")"
r="$(we '{"data":{"id":1,"name":"x","workflow_stage_id":5,"payload":{"dl_number":"DL-0001"}}}')"
eq "real payload → included"       '{"dl_number":"DL-0001"}' "$(jq -c '.payload' <<<"$r")"
r="$(we '{"data":{"id":1,"name":"x","workflow_stage_id":5,"payload":null}}')"
eq "server-sent null → passed through (the server SAID null)" "true" "$(jq 'has("payload")' <<<"$r")"
r="$(we '{"data":{"id":1,"name":"x","workflow_stage_id":5,"description":"abcdef"}}' 'description: (.description // "" | .[0:3])')"
eq "extra-fields arg composes (patch echo)" '"abc"' "$(jq -c '.description' <<<"$r")"
# The refusal it now owns, at the unit level: a body no card can be read out of prints nothing
# and returns 1 — never a plausible-looking projection of nothing.
rc=0; r="$(we '<html>502</html>' 2>/dev/null)" || rc=$?
e="$(we '<html>502</html>' 2>&1 >/dev/null || true)"
eq "a body that is not JSON → rc 1"          "1" "$rc"
eq "…and nothing on stdout"                  ""  "$r"
eq "…refuses in kbcard's words, naming the verb" "true" "$(has 'kbcard: patch on task 1' "$e")"
eq "…and does NOT claim the body could not be parsed" "false" "$(has 'could not be parsed' "$e")"
unset -f we; unset e


# ---------------------------------------------------------------------------
echo "== cmd_archive / cmd_delete — arg guards + dry-run + non-TTY --hard refusal =="
# These paths are network-free: a NUMERIC --task short-circuits resolve_task (no
# search call), --dry-run returns before any API call, and the non-TTY --hard
# guard refuses before the soft-delete — so no kb_api call is ever reached here.

rc=0; cmd_archive >/dev/null 2>&1 || rc=$?
eq "archive without --task → rc 2" "2" "$rc"
rc=0; cmd_delete  >/dev/null 2>&1 || rc=$?
eq "delete without --task → rc 2"  "2" "$rc"
rc=0; cmd_delete --task 42 --bogus >/dev/null 2>&1 || rc=$?
eq "delete unknown arg → rc 2"     "2" "$rc"

out="$(cmd_archive --task 42 --dry-run 2>/dev/null)"
eq "archive --dry-run prints the archive PATCH" "true" "$(has '"_action":"archive"' "$out")"

out="$(cmd_delete --task 42 --dry-run 2>/dev/null)"
eq "delete --dry-run prints the soft PATCH"           "true"  "$(has '"_action":"delete"' "$out")"
eq "delete --dry-run (no --hard) omits force-delete"  "false" "$(has 'force-delete' "$out")"

out="$(cmd_delete --task 42 --hard --dry-run 2>/dev/null)"
eq "delete --hard --dry-run includes force-delete"    "true"  "$(has 'force-delete.json' "$out")"

# ---------------------------------------------------------------------------
echo "== _kbc_archive_decision — null/absent .data fails closed before the board fetch =="
# A 2xx whose .data is JSON null (trashed / permission-limited / edge card) yields
# the literal "null" at rc 0 — the fetch `||` guard never fires. The bash guard must
# short-circuit to a noprimitive token BEFORE fetch_board_cards / the shim run, so a
# null card can never reach the shim as a source-less `{}` that would false-`ok`.
# RED-when-reverted: without the guard the literal "null" card falls through to the
# board fetch (sentinel set) → the unsafe path this guard closes.
_saved_fbc="$(declare -f fetch_board_cards || true)"
_FBC_SENTINEL="$(mktemp)"; : > "$_FBC_SENTINEL"
kb_api() { printf '{"data":null}'; }
fetch_board_cards() { echo REACHED > "$_FBC_SENTINEL"; printf '[]'; }
_dec="$(_kbc_archive_decision 42)"
eq "null .data → noprimitive token"        "noprimitive" "${_dec%%$'\t'*}"
eq "null .data → board fetch NOT reached"   ""            "$(cat "$_FBC_SENTINEL")"
unset -f kb_api fetch_board_cards
[[ -n "$_saved_fbc" ]] && eval "$_saved_fbc"
rm -f "$_FBC_SENTINEL"; unset _saved_fbc _FBC_SENTINEL _dec

# ---------------------------------------------------------------------------
echo "== cmd_archive — may_archive gate wiring (roundtable #39) =="
# The gate DECISION (fetch card + board, run the shim over the framework primitive)
# is a separate seam _kbc_archive_decision; here we stub THAT to canned tokens and
# assert cmd_archive's wiring: block → refuse + NO PATCH, --force → PATCH + audited
# override line, ok → PATCH, noprimitive → fail-loud refuse. Network-free: a numeric
# --task short-circuits resolve_task, and kb_api is stubbed to record the PATCH.
# RED-when-reverted: delete the gate call and the block/noprimitive refusals archive.
# kb_api records the PATCH body to a FILE (a $()-subshell side effect on a global
# would not survive the command-substitution boundary the stderr capture needs).
KB_LOG_FILE="$(mktemp)"; export KB_LOG_FILE
_PATCH_FILE="$(mktemp)"; _ERR_FILE="$(mktemp)"
trap 'rm -f "$KB_LOG_FILE" "$_PATCH_FILE" "$_ERR_FILE"' EXIT
kb_api() { case "$2" in */tasks/*) printf '%s' "$3" > "$_PATCH_FILE" ;; esac; printf '{"data":{"id":42}}'; }
_reset() { : > "$_PATCH_FILE"; : > "$KB_LOG_FILE"; }
# run <args...> — cmd_archive at TOP LEVEL (no $() around it) so rc + the file side
# effects are the parent's; sets rc/err/patched/logtxt for the assertions.
run() { rc=0; cmd_archive "$@" >/dev/null 2>"$_ERR_FILE" || rc=$?;
        err="$(cat "$_ERR_FILE")"; patched="$(cat "$_PATCH_FILE")"; logtxt="$(cat "$KB_LOG_FILE")"; }

# blocked, no --force → refuse (rc 1), NO archive PATCH sent, drift-vocab line.
_kbc_archive_decision() { printf 'blocked\tsource live (pr o/r#5) and no surviving twin — archive blocked'; }
_reset; run --task 42
eq "blocked → rc 1"                         "1"    "$rc"
eq "blocked → no archive PATCH sent"        ""     "$patched"
eq "blocked → '⚠ archive withheld' line"    "true" "$(has '⚠ archive withheld: card #42' "$err")"
eq "blocked → names --force override"        "true" "$(has 'pass --force to override' "$err")"

# blocked + --force → archive PATCH IS sent + audited FORCED line on stderr + log.
_reset; run --task 42 --force
eq "force → archive PATCH sent"             "true" "$(has '"_action":"archive"' "$patched")"
eq "force → audited FORCED line on stderr"  "true" "$(has '⚠ archive FORCED past live-source gate: card #42' "$err")"
eq "force → override written to durable log" "true" "$(has 'ARCHIVE-FORCE task=42' "$logtxt")"

# ok (gate cleared) → archive PATCH sent, no withheld/forced noise.
_kbc_archive_decision() { printf 'ok\tall backing sources terminal or twin-covered'; }
_reset; run --task 42
eq "ok → archive PATCH sent"                "true"  "$(has '"_action":"archive"' "$patched")"
eq "ok → no FORCED audit line"              "false" "$(has 'FORCED past live-source gate' "$err")"
eq "ok → clean run, no override in log"     "false" "$(has 'ARCHIVE-FORCE' "$logtxt")"

# noprimitive (gate unverifiable) → fail LOUD refuse, NO PATCH; --force still archives.
_kbc_archive_decision() { printf 'noprimitive\tmay_archive primitive not found'; }
_reset; run --task 42
eq "noprimitive → rc 1 (fail-loud refuse)" "1"     "$rc"
eq "noprimitive → no archive PATCH sent"   ""      "$patched"
eq "noprimitive → says cannot verify"      "true"  "$(has 'cannot verify archive safety' "$err")"
_reset; run --task 42 --force
eq "noprimitive + --force → archive PATCH sent"  "true" "$(has '"_action":"archive"' "$patched")"
eq "noprimitive + --force → audited override"    "true" "$(has 'ARCHIVE-FORCE task=42' "$logtxt")"

# gate-infra failure (e.g. python3 absent → the decision fetch exits non-zero). Under
# --force the escape hatch must NOT be blocked by the very gate infra it bypasses: the
# archive PATCH still goes AND the audited override line is STILL written (never a
# silent forced archive). RED-when-reverted: without `|| decision=""` the set -e
# assignment aborts cmd_archive so --force fails to archive at all.
_kbc_archive_decision() { return 127; }
_reset; run --task 42 --force
eq "force + gate-infra failure → archive PATCH sent" "true" "$(has '"_action":"archive"' "$patched")"
eq "force + gate-infra failure → audited override"   "true" "$(has 'ARCHIVE-FORCE task=42' "$logtxt")"
eq "force + gate-infra failure → FORCED line names it" "true" "$(has 'infra could not run' "$err")"
# Non-force stays FAIL-CLOSED: a gate-infra failure aborts before any PATCH (the
# non-force assignment intentionally has no `|| …`, so set -e refuses).
_reset; run --task 42
eq "non-force + gate-infra failure → no archive PATCH" "" "$patched"

# --dry-run stays offline: prints the PATCH, never calls the gate (a stub that would
# fatal proves the gate is not reached under --dry-run).
_kbc_archive_decision() { echo "GATE MUST NOT RUN UNDER DRY-RUN" >&2; return 99; }
out="$(cmd_archive --task 42 --dry-run 2>/dev/null)"
eq "dry-run still prints the archive PATCH" "true" "$(has '"_action":"archive"' "$out")"
unset -f _kbc_archive_decision kb_api _reset run
rm -f "$KB_LOG_FILE" "$_PATCH_FILE" "$_ERR_FILE" 2>/dev/null || true
unset KB_LOG_FILE _PATCH_FILE _ERR_FILE; trap - EXIT

# THE safety guard: --hard without --yes in a non-interactive shell refuses UP
# FRONT (rc 2, before any soft-delete) — never leaves the card half-trashed.
# </dev/null forces a non-TTY fd 0 so the check is deterministic in any CI shell.
rc=0; err="$(cmd_delete --task 42 --hard </dev/null 2>&1)" || rc=$?
eq "non-TTY --hard without --yes → rc 2"      "2"    "$rc"
eq "non-TTY --hard refusal names --yes"       "true" "$(has '--yes' "$err")"

# ---------------------------------------------------------------------------
echo "== cmd_move — decline (→ wont_do) clears correlation stamps in the same PATCH =="
# Moving a card to wont_do CLEARS payload.dl_number/pr_number/pr_url (explicit JSON nulls,
# which the kanban v3 per-key payload merge deletes) so a stale/recycled stamp can't later
# resurrect the declined card in a release-promote scan. --keep-refs opts out; every other
# target column leaves the payload untouched. Network-free: a numeric --task short-circuits
# resolve_task, and kb_api records the request body ($3) to a file (a command-substitution
# subshell side effect on a global would not survive back to the parent).
_MOVE_BODY="$(mktemp)"; _MOVE_ERR="$(mktemp)"
trap 'rm -f "$_MOVE_BODY" "$_MOVE_ERR"' EXIT
kb_api() { printf '%s' "$3" > "$_MOVE_BODY"; printf '{"data":{"id":99,"name":"x","workflow_stage_id":60}}'; }
export KB_BOARD_ID=12 KB_STAGE_WONT_DO=60 KB_STAGE_IN_REVIEW=50
# mv_body <args...> — run cmd_move, return the request body it sent; err in $_MOVE_ERR.
mv_body() { : > "$_MOVE_BODY"; cmd_move "$@" >/dev/null 2>"$_MOVE_ERR"; cat "$_MOVE_BODY"; }

# Decline: the three correlation keys are PRESENT and null ([has,value]=[true,null]) — an
# explicit null (the API delete form), NOT an omitted key. RED-when-reverted: drop the clear
# and the payload key is absent, so [false,null] reds instead of reading like a real null.
b="$(mv_body --task 99 --column wont_do)"
eq "wont_do move → stage set to wont_do"            "60" "$(jq -c '.workflow_stage_id' <<<"$b")"
eq "wont_do move → dl_number present + null"        '[true,null]' "$(jq -c '[(.payload|has("dl_number")), .payload.dl_number]' <<<"$b")"
eq "wont_do move → pr_number present + null"        '[true,null]' "$(jq -c '[(.payload|has("pr_number")), .payload.pr_number]' <<<"$b")"
eq "wont_do move → pr_url present + null"           '[true,null]' "$(jq -c '[(.payload|has("pr_url")), .payload.pr_url]' <<<"$b")"
eq "wont_do move → prints what it cleared"          "true" "$(has 'cleared correlation stamps' "$(cat "$_MOVE_ERR")")"

# --keep-refs opts out: the payload key is entirely ABSENT (no clear), and the notice says so.
b="$(mv_body --task 99 --column wont_do --keep-refs)"
eq "wont_do --keep-refs → no payload clear"         "false" "$(jq 'has("payload")' <<<"$b")"
eq "wont_do --keep-refs → still sets the stage"     "60"    "$(jq -c '.workflow_stage_id' <<<"$b")"
eq "wont_do --keep-refs → prints the retained note" "true"  "$(has 'retained' "$(cat "$_MOVE_ERR")")"

# A NON-wont_do move is byte-unchanged: no payload key, no clear/keep notice on stderr.
b="$(mv_body --task 99 --column in_review)"
eq "non-wont_do move → no payload key (unchanged)"  "false" "$(jq 'has("payload")' <<<"$b")"
eq "non-wont_do move → stage set"                   "50"    "$(jq -c '.workflow_stage_id' <<<"$b")"
eq "non-wont_do move → no clear/keep notice"        "false" "$(has 'correlation stamps' "$(cat "$_MOVE_ERR")")"

echo "== cmd_patch — the SECOND decline call-site clears the same stamps (canon #7 sibling) =="
# patch --column wont_do declines too; the clear is shared via _kbc_decline_nulls so the
# hygiene invariant has ONE owner. An explicit ref flag passed IN THIS CALL wins over the
# null (merge order: right-hand precedence). RED-when-reverted: dropping the cmd_patch
# decline block leaves the payload key absent → [false,null] reds.
pt_body() { : > "$_MOVE_BODY"; cmd_patch "$@" >/dev/null 2>"$_MOVE_ERR"; cat "$_MOVE_BODY"; }
b="$(pt_body --task 99 --column wont_do)"
eq "wont_do patch → stage set to wont_do"           "60" "$(jq -c '.workflow_stage_id' <<<"$b")"
eq "wont_do patch → dl_number present + null"       '[true,null]' "$(jq -c '[(.payload|has("dl_number")), .payload.dl_number]' <<<"$b")"
eq "wont_do patch → pr_url present + null"          '[true,null]' "$(jq -c '[(.payload|has("pr_url")), .payload.pr_url]' <<<"$b")"
eq "wont_do patch → prints what it cleared"         "true" "$(has 'cleared correlation stamps' "$(cat "$_MOVE_ERR")")"

# Explicit flag beats hygiene: --dl in the SAME declining call keeps its value; the other
# two keys still clear.
b="$(pt_body --task 99 --column wont_do --dl DL-7)"
eq "wont_do patch + --dl → explicit dl wins"        '"DL-0007"' "$(jq -c '.payload.dl_number' <<<"$b")"
eq "wont_do patch + --dl → pr_number still null"    '[true,null]' "$(jq -c '[(.payload|has("pr_number")), .payload.pr_number]' <<<"$b")"

b="$(pt_body --task 99 --column wont_do --keep-refs)"
eq "wont_do patch --keep-refs → no payload key"     "false" "$(jq 'has("payload")' <<<"$b")"
eq "wont_do patch --keep-refs → retained notice"    "true"  "$(has 'retained' "$(cat "$_MOVE_ERR")")"

b="$(pt_body --task 99 --column in_review)"
eq "non-wont_do patch → no payload key"             "false" "$(jq 'has("payload")' <<<"$b")"

unset -f kb_api mv_body pt_body
unset KB_BOARD_ID KB_STAGE_WONT_DO KB_STAGE_IN_REVIEW
rm -f "$_MOVE_BODY" "$_MOVE_ERR"; unset _MOVE_BODY _MOVE_ERR; trap - EXIT

# ---------------------------------------------------------------------------
echo "== cmd_create_card --triaged — born-triaged tag (card #4617) =="
# Network-free: stub the POST to echo the request body ($3) and the write-echo to
# pass it through, so we assert on the tags the create body WOULD send. Defined
# AFTER the real-_kbc_write_echo block above so those checks use the real fn.
# Capture the real projection first — the echo-parity pair near the end restores it.
eval "_kbc_write_echo_orig() $(declare -f _kbc_write_echo | tail -n +2)"
kb_api() { printf '%s' "$3"; }
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48

# has_tag <body-json> <tag> → membership of the created card's flat .tags array.
has_tag() { jq -e --arg t "$2" '((.tags // []) | index($t)) != null' <<<"$1" >/dev/null && echo true || echo false; }

# Native-type board: --triaged adds `triaged`; the native id is used, no type: tag.
export KB_TYPE_TASK=21; unset KB_TYPING_MODE 2>/dev/null || true
b="$(cmd_create_card --type task --name x --triaged 2>/dev/null)"
eq "native + --triaged → triaged tag present" "true"  "$(has_tag "$b" triaged)"
eq "native + --triaged → native card_type_id" "21"    "$(jq -c '.card_type_id' <<<"$b")"
eq "native + --triaged → no type: tag"        "false" "$(has_tag "$b" 'type:task')"

# Negative control: WITHOUT --triaged, no triaged tag (proves the flag is load-bearing).
b="$(cmd_create_card --type task --name x 2>/dev/null)"
eq "native, no flag → triaged tag ABSENT"     "false" "$(has_tag "$b" triaged)"

# Tag-typing board: --triaged rides alongside the type:<alias> fallback tag.
unset KB_TYPE_TASK; export KB_TYPING_MODE=tags
b="$(cmd_create_card --type task --name x --triaged 2>/dev/null)"
eq "tag-mode + --triaged → triaged tag present"   "true" "$(has_tag "$b" triaged)"
eq "tag-mode + --triaged → type:task tag present" "true" "$(has_tag "$b" 'type:task')"

# The roundtable use-case: caller passes its PM policy tag, the toolkit adds triaged.
b="$(cmd_create_card --type task --name x --tags backlog:pm --triaged 2>/dev/null)"
eq "--tags + --triaged → caller tag kept"    "true" "$(has_tag "$b" 'backlog:pm')"
eq "--tags + --triaged → triaged appended"   "true" "$(has_tag "$b" triaged)"
unset KB_TYPING_MODE KB_TYPE_TASK KB_BOARD_ID KB_STAGE_BACKLOG

# ---------------------------------------------------------------------------
echo "== swimlane resolution + list projection (card-4637) =="
# Swimlanes are keyed by id in the env (KB_SWIMLANE_<id>=<name>) — the INVERSE of
# KB_STAGE_<name>=<id> — because swimlane names are freeform (hyphens/spaces) and
# can't be env-var suffixes. Scrub any the operator's shell exported first.
# shellcheck disable=SC2086
unset ${!KB_SWIMLANE_@} 2>/dev/null || true
export KB_SWIMLANE_1=device
export KB_SWIMLANE_2=backend

# _kbc_swimlane_map — {id:name} object from the env; keys are strings, empty-valued vars skipped.
eq "swimlane map resolves both lanes"   '{"1":"device","2":"backend"}' "$(_kbc_swimlane_map)"
export KB_SWIMLANE_3=""
eq "empty-valued swimlane var skipped"  '{"1":"device","2":"backend"}' "$(_kbc_swimlane_map)"
unset KB_SWIMLANE_3

# _kbc_swimlane_is_laneless_ref — the ONE owner of which refs mean "no lane", shared by
# the two write paths and the list filter. `0` counts because lane ids are positive, so
# it never named a real lane; a lane NAME never does, which is why a lane literally named
# `none` must be addressed by id.
lanelessq() { if _kbc_swimlane_is_laneless_ref "$1"; then echo yes; else echo no; fi; }
eq "'none' is a laneless ref"        "yes" "$(lanelessq none)"
eq "'0' is a laneless ref"           "yes" "$(lanelessq 0)"
eq "a lane name is NOT laneless"     "no"  "$(lanelessq device)"
eq "a real lane id is NOT laneless"  "no"  "$(lanelessq 2)"

# swimlane_id — name→id, numeric passthrough, unmapped name errors LOUD (rc 2) —
# so a typo'd --swimlane never silently lists nothing (parity with stage_id).
eq "name resolves to its id"     "2"    "$(swimlane_id backend)"
eq "numeric id passes through"   "9"    "$(swimlane_id 9)"
rc=0; err="$(swimlane_id nope 2>&1)" || rc=$?
eq "unmapped name → rc 2"        "2"    "$rc"
eq "unmapped name names itself"  "true" "$(has 'nope' "$err")"

# card-4713: the unresolved-name error must ENUMERATE the board's defined swimlanes
# (id→name, sorted) so it can't be misread as "the board has no such swimlane" — the
# false board-fact this fix prevents. RED-when-reverted: drop the enumeration and this
# fails. Mirrors the board-not-found error's "boards found on this box: …" style.
eq "unresolved name enumerates the defined swimlanes" "true" \
   "$(has 'defined swimlanes: 1=device, 2=backend' "$err")"

# The empty case (a board with NO swimlanes declared) gets a DISTINCT honest line, not
# an empty "defined swimlanes:" list that would read the same as the enumerated case.
# shellcheck disable=SC2086
unset ${!KB_SWIMLANE_@}
err="$(swimlane_id whatever 2>&1)" || true
eq "no-swimlane board → distinct honest empty-case line" "true"  "$(has 'defines no swimlanes' "$err")"
eq "no-swimlane board → NOT an empty enumerated list"    "false" "$(has 'defined swimlanes:' "$err")"
export KB_SWIMLANE_1=device
export KB_SWIMLANE_2=backend

# _kbc_list_project — synthetic cards (board 12 has NO swimlanes, so it must be
# unit-tested). Projection surfaces swimlane_id + the resolved name (null when the
# card has no lane or the env doesn't map it); the filter is a client-side select.
CARDS='[{"id":1,"name":"a","workflow_stage_id":48,"card_type_id":7,"swimlane_id":1,"payload":{}},
        {"id":2,"name":"b","workflow_stage_id":48,"card_type_id":7,"swimlane_id":2,"payload":{}},
        {"id":3,"name":"c","workflow_stage_id":49,"card_type_id":7,"payload":{}}]'
proj() { printf '%s' "$CARDS" | _kbc_list_project "$1" "$2" "$3" "$4"; }

eq "projection surfaces swimlane_id"     "1"        "$(proj '' '' '' '' | jq -c '.[0].swimlane_id')"
eq "projection resolves swimlane name"   '"device"' "$(proj '' '' '' '' | jq -c '.[0].swimlane')"
eq "no-lane card → swimlane_id null"     "null"     "$(proj '' '' '' '' | jq -c '.[2].swimlane_id')"
eq "no-lane card → swimlane name null"   "null"     "$(proj '' '' '' '' | jq -c '.[2].swimlane')"

eq "--swimlane 2 → only card 2"          "[2]"      "$(proj '' '' '' 2  | jq -c 'map(.id)')"
eq "--swimlane 1 + stage 48 → card 1"    "[1]"      "$(proj 48 '' '' 1  | jq -c 'map(.id)')"
eq "no swimlane filter → all 3 rows"     "3"        "$(proj '' '' '' '' | jq 'length')"

# card-5766: the LANELESS filter. Its value is the projection's own key for a card with
# no lane, `(null | tostring)` == "null" — deliberately distinct from the filter-absent
# value "". The pair below is the whole point: collapsing "laneless" into "absent" (the
# naive reuse of the WRITE-side none→JSON-null rule) returns the WHOLE BOARD while
# looking correct, so the length assertion is what reds on it — the id list alone would
# not, since the laneless card is a member of the whole board either way.
eq "--swimlane none → only the laneless card" "[3]" "$(proj '' '' '' null | jq -c 'map(.id)')"
eq "--swimlane none is NOT the whole board"   "1"   "$(proj '' '' '' null | jq 'length')"
eq "--swimlane none + stage 49 → card 3"      "[3]" "$(proj 49 '' '' null | jq -c 'map(.id)')"
# A laned card must never fall into the laneless bucket, and an EXPLICIT swimlane_id:null
# must land in it exactly like an absent key (the API may spell "no lane" either way).
eq "a laned card never matches laneless" "[]" \
   "$(printf '%s' '[{"id":9,"swimlane_id":2,"payload":{}}]' | _kbc_list_project '' '' '' null | jq -c 'map(.id)')"
eq "explicit swimlane_id:null is laneless" "[8]" \
   "$(printf '%s' '[{"id":8,"swimlane_id":null,"payload":{}}]' | _kbc_list_project '' '' '' null | jq -c 'map(.id)')"

# Robustness: the API's swimlane_id JSON type can't be verified on a board without
# lanes, so the filter keys on the STRINGIFIED id — a STRING-typed swimlane_id must
# still match (a numeric == would silently drop it). Positive control for the type
# assumption we can't otherwise check.
eq "string-typed swimlane_id still filters" "[7]" \
   "$(printf '%s' '[{"id":7,"swimlane_id":"2","payload":{}}]' | _kbc_list_project '' '' '' 2 | jq -c 'map(.id)')"

# Integration (faithful): cmd_list must FAIL LOUD on a typo'd --swimlane, never
# silently list every card with the filter dropped. The guarantee rides on set -e +
# swimlane_id's rc 2 (parity with --column/stage_id) — but any IN-PROCESS capture
# ($()/||) suspends errexit for the code under test and masks it, so cmd_list must
# run at the TOP LEVEL of a fresh subprocess (as the real binary does); the capture
# then crosses a process boundary the outer ||/$() cannot reach into. Fetch is mocked
# so the subprocess is network-free.
_lane_child='set -euo pipefail; source "'"$BIN"'";
  fetch_board_cards() { printf "%s" "[{\"id\":1,\"swimlane_id\":1,\"payload\":{}},{\"id\":2,\"payload\":{}}]"; }
  export KB_API=x KB_TOKEN=y KB_BOARD_ID=12 KB_SWIMLANE_1=device;
  cmd_list --swimlane "$1"'
out="$(bash -c "$_lane_child" _ device 2>/dev/null)" || true
eq "valid --swimlane lists that lane"           "[1]" "$(jq -c 'map(.id)' <<<"$out")"
rc=0; out="$(bash -c "$_lane_child" _ bogus 2>/dev/null)" || rc=$?
eq "typo'd --swimlane → rc 2 (loud, no drop)"   "2"   "$rc"
eq "typo'd --swimlane prints NO cards"          ""    "$out"

# card-5766 end-to-end through the real arg parse: the mock board is one laned card (1)
# + one laneless card (2), so the whole-board regression is [1,2] and the correct answer
# is [2] — this is the assertion that separates them. `none` must also never reach
# swimlane_id(), which would reject it rc 2 as an undefined lane name (the pre-fix
# behaviour), so a nonzero rc here is itself a failure.
rc=0; out="$(bash -c "$_lane_child" _ none 2>/dev/null)" || rc=$?
eq "--swimlane none → rc 0 (not an unknown lane)" "0"   "$rc"
eq "--swimlane none lists ONLY the laneless card" "[2]" "$(jq -c 'map(.id)' <<<"$out")"
rc=0; out="$(bash -c "$_lane_child" _ 0 2>/dev/null)" || rc=$?
eq "--swimlane 0 → rc 0"                          "0"   "$rc"
eq "--swimlane 0 is the same laneless filter"     "[2]" "$(jq -c 'map(.id)' <<<"$out")"
unset KB_SWIMLANE_1 KB_SWIMLANE_2

# ---------------------------------------------------------------------------
echo "== _kbc_list_project — the PROJECTED FIELD SET is the filterable surface =="
# A consumer can only filter list OUTPUT on a key the projection emits, and a grep over
# a field it drops returns 0 indistinguishably from an empty board — a live consumer
# concluded "745 cards, 0 dependabot cards" while the `id:<sid>` provenance tag was on
# the card the whole time (`show` returned it). The key set is asserted as an EQUALITY,
# not a contains: a key silently dropped IS the defect, and a contains-check cannot see
# it. RED-when-reverted — reverting the projection to its old key set reds five of the
# assertions below, the prefix-grep one among them (measured, not assumed).
PCARDS='[{"id":1,"name":"a","workflow_stage_id":48,"card_type_id":7,"external_id":990,
          "tags":["id:dep:acme#200","triaged"],"payload":{"dl_number":"DL-0007","pr_number":12}},
         {"id":2,"name":"b","workflow_stage_id":48,"payload":{}}]'
pproj() { printf '%s' "$PCARDS" | _kbc_list_project '' '' '' ''; }

eq "row key set is EXACTLY the documented projection" \
   '["id","name","stage","type","swimlane_id","swimlane","external_id","tags","dl","pr"]' \
   "$(pproj | jq -c '.[0] | keys_unsorted')"
eq "tags ride every row verbatim"   '["id:dep:acme#200","triaged"]' "$(pproj | jq -c '.[0].tags')"
eq "external_id rides every row"    "990"  "$(pproj | jq -c '.[0].external_id')"
# The measured consumer query itself: a PREFIX grep over the output for a provenance
# namespace. Exactly what answered 0 before, so it is asserted end-to-end and not as
# "the key exists" — the tag namespace is queried by prefix, not by exact value.
eq "a downstream prefix grep for the provenance tag finds the card" "1" \
   "$(pproj | grep -c 'id:dep:')"
# Absent-key normalization: [] for tags (the same normalization the type FILTER above
# applies, so the filter and the emitted value can never disagree about a card's tags),
# null for external_id (matching dl/pr, whose absence has always projected null).
eq "a card with no tags projects []"          "[]"   "$(pproj | jq -c '.[1].tags')"
eq "a card with no external_id projects null" "null" "$(pproj | jq -c '.[1].external_id')"
# description stays OUT by design — unbounded free text on every row of a whole-board
# read. This assertion is the bound; `show` is where a description is read.
eq "description is NOT projected, even when the card carries one" "false" \
   "$(printf '%s' '[{"id":3,"description":"x","payload":{}}]' \
      | _kbc_list_project '' '' '' '' | jq -c '.[0] | has("description")')"

# ---------------------------------------------------------------------------
echo "== cmd_list — a FILTERED read reports its denominator on stderr =="
# A filtered [] is indistinguishable from an empty board at the call site: the caller
# sees the numerator and never the population. The line goes to STDERR so stdout stays
# exactly the array every existing consumer parses. Run through the REAL arg parse in a
# fresh subprocess (mocked fetch, network-free) — the stream split is a property of the
# whole verb, not of the projection.
_mktmp_scratch
_diag_board='[{"id":1,"workflow_stage_id":48,"payload":{}},
              {"id":2,"workflow_stage_id":49,"payload":{}},
              {"id":3,"workflow_stage_id":49,"payload":{}}]'
_diag_child='set -euo pipefail; source "'"$BIN"'";
  fetch_board_cards() { printf "%s" "$DIAG_BOARD"; }
  export KB_API=x KB_TOKEN=y KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_STAGE_HELD=49 KB_STAGE_WONT_DO=99;
  cmd_list "$@"'
export DIAG_BOARD="$_diag_board"
diag() { bash -c "$_diag_child" _ "$@" >"$TMP/diag.out" 2>"$TMP/diag.err"; }

diag --column backlog
eq "filtered stdout is still just the array"  "[1]" "$(jq -c 'map(.id)' <"$TMP/diag.out")"
# …and byte-identically so. The assertion above cannot carry this alone: jq EMITS its
# value before erroring on trailing garbage, so a diagnostic line leaking onto stdout
# after the array leaves it green. The FILTERED run is the one that can leak (it is the
# only one that prints a diagnostic at all), so it needs its own byte comparison — the
# unfiltered `cmp` below can never observe this class.
printf '%s' "$_diag_board" | _kbc_list_project 48 '' '' '' >"$TMP/diagf.want"
eq "filtered stdout is byte-identical to the projection output (no leak onto stdout)" "true" \
   "$(cmp -s "$TMP/diag.out" "$TMP/diagf.want" && echo true || echo false)"
eq "filtered run names matched-of-total"      "true" \
   "$(has 'kbcard: list --column backlog: 1 of 3 board cards matched' "$(cat "$TMP/diag.err")")"

# The 0-of-N case is the whole point: an empty answer that names its population is a
# different statement from an empty answer that does not.
diag --column wont_do
eq "an empty filtered result is still []"     "[]" "$(jq -c '.' <"$TMP/diag.out")"
eq "…and still reports the population it came out of" "true" \
   "$(has 'kbcard: list --column wont_do: 0 of 3 board cards matched' "$(cat "$TMP/diag.err")")"

# Every active flag is echoed AS TYPED, so a caller running several list reads can tell
# the lines apart.
diag --column held --type bug
eq "both active filters are named in the line" "true" \
   "$(has 'kbcard: list --column held --type bug: 0 of 3 board cards matched' "$(cat "$TMP/diag.err")")"

# UNFILTERED: nothing on stderr — the array's own length IS the denominator, and a line
# printed here would be noise on the most common invocation.
diag
eq "an unfiltered read prints NOTHING on stderr" "" "$(cat "$TMP/diag.err")"
eq "…and still lists the whole board"            "3" "$(jq 'length' <"$TMP/diag.out")"
# Byte-identity of stdout with the projection's own output, trailing newline included:
# the diagnostic capture reprints what used to stream straight through, and a doubled or
# missing final newline is invisible to every command-substitution assertion above.
printf '%s' "$_diag_board" | _kbc_list_project '' '' '' '' >"$TMP/diag.want"
eq "stdout is byte-identical to the projection output" "true" \
   "$(cmp -s "$TMP/diag.out" "$TMP/diag.want" && echo true || echo false)"
unset DIAG_BOARD

# ---------------------------------------------------------------------------
echo "== _kbc_build_payload — shared create/patch payload assembly (card-4511, dedup D2) =="
# Single home for the payload-merge jq + version_target guard + DL-canon + pr
# appends that create-card and patch both need. RED-when-reverted: these pin the
# exact merged object, so a helper that diverged from either original (dropped a
# field, lost the numeric coercion, skipped the DL canon) FAILS here.
unset KB_CF_VERSION_TARGET 2>/dev/null || true
export KB_CF_VERSION_TARGET=99   # board HAS the version_target custom field

# Full flag set: DL canonicalized (DL-93→DL-0093), pr_number coerced to a JSON
# NUMBER, pr_url a string, version_target written (board has the CF).
eq "full flag set → exact merged payload" \
   '{"dl_number":"DL-0093","pr_number":178,"pr_url":"https://github.com/o/r/pull/0","version_target":"v0.9.2"}' \
   "$(_kbc_build_payload DL-93 178 https://github.com/o/r/pull/0 v0.9.2 | jq -Sc .)"

# origin (trailing 7th arg, create-only) rides the same coercion path and is appended.
eq "origin arg included, coerced like the rest" \
   '{"dl_number":"DL-0001","origin":"preemptive"}' \
   "$(_kbc_build_payload 1 '' '' '' '' '' preemptive | jq -Sc .)"

# issue_number / issue_url mirror pr_number / pr_url — issue_number NUMERIC-coerced (a JSON
# number, not "300"), issue_url a string, both INDEPENDENT of the pr_* pair. RED-when-reverted:
# drop the coercion (the `tonumber? // .` in the merge jq) and issue_number becomes a string.
eq "issue_number coerced to a JSON number + issue_url string" \
   '{"issue_number":300,"issue_url":"https://github.com/o/r/issues/300"}' \
   "$(_kbc_build_payload '' '' '' '' 300 https://github.com/o/r/issues/300 | jq -Sc .)"
# Co-stamping: --issue + --pr in one call yield BOTH pairs, independently (like dl/pr coexist).
eq "issue + pr co-stamp — both number-typed keys present, independent" \
   '{"issue_number":300,"pr_number":305}' \
   "$(_kbc_build_payload '' 305 '' '' 300 '' | jq -Sc .)"
# An omitted --issue leaves issue_number ABSENT (not null) — the untriaged/serializer omit rule.
eq "no --issue → issue_number key ABSENT (not null)" "false" \
   "$(_kbc_build_payload '' '' '' '' '' '' | jq 'has("issue_number")')"

# No flags → empty object (create's length-gate / patch's !={} both key on this).
eq "no flags → {}" "{}" "$(_kbc_build_payload '' '' '' '')"

# Version guard: a board WITHOUT the CF drops version_target + warns (never 422s).
unset KB_CF_VERSION_TARGET
rc=0; out="$(_kbc_build_payload '' '' '' v1.2.3 2>/dev/null)" || rc=$?
eq "version w/o CF → rc 0"            "0"    "$rc"
eq "version w/o CF → empty payload"   "{}"   "$out"
err="$(_kbc_build_payload '' '' '' v1.2.3 2>&1 >/dev/null)"
eq "version w/o CF → warns on stderr" "true" "$(has 'version_target field' "$err")"
# The '000' sentinel is treated as absent too.
export KB_CF_VERSION_TARGET=000
eq "version_target=000 sentinel → dropped" "{}" "$(_kbc_build_payload '' '' '' v1.2.3 2>/dev/null)"
unset KB_CF_VERSION_TARGET

# Malformed --dl fails LOUD (rc 2) before any output — never a plausible-wrong DL.
rc=0; out="$(_kbc_build_payload not-a-dl '' '' '' 2>/dev/null)" || rc=$?
eq "malformed --dl → rc 2"       "2" "$rc"
eq "malformed --dl → no payload" ""  "$out"

# Integration: create-card and patch, given the SAME dl/pr/pr_url/version, must send
# byte-identical payload — the whole point of sharing one assembler. Stub the
# API to echo the request body; assert the flat .payload objects match.
kb_api() { printf '%s' "$3"; }
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_TYPE_TASK=21 KB_CF_VERSION_TARGET=99
unset KB_TYPING_MODE 2>/dev/null || true
cpay="$(cmd_create_card --type task --name x --dl DL-7 --pr 42 --pr-url https://github.com/o/r/pull/0 --version v1.0.0 2>/dev/null | jq -Sc '.payload')"
ppay="$(cmd_patch --task 99 --dl DL-7 --pr 42 --pr-url https://github.com/o/r/pull/0 --version v1.0.0 2>/dev/null | jq -Sc '.payload')"
eq "create + patch send identical payload" "$cpay" "$ppay"
eq "and it is the expected object" \
   '{"dl_number":"DL-0007","pr_number":42,"pr_url":"https://github.com/o/r/pull/0","version_target":"v1.0.0"}' "$cpay"

# --issue / --issue-url wired through create-card AND patch: issue_number number-typed, and a
# card co-stamped with --issue + --pr carries BOTH lifecycle pairs, independently.
ci="$(cmd_create_card --type task --name x --issue 300 --issue-url https://github.com/o/r/issues/300 2>/dev/null | jq -Sc '.payload')"
eq "create-card --issue → number-typed issue_number + issue_url" \
   '{"issue_number":300,"issue_url":"https://github.com/o/r/issues/300"}' "$ci"
pi="$(cmd_patch --task 99 --issue 300 --issue-url https://github.com/o/r/issues/300 2>/dev/null | jq -Sc '.payload')"
eq "patch --issue sends the identical issue payload" "$ci" "$pi"
co="$(cmd_create_card --type task --name x --issue 300 --pr 305 2>/dev/null | jq -Sc '.payload')"
eq "create-card --issue + --pr co-stamp both keys, independent" \
   '{"issue_number":300,"pr_number":305}' "$co"

# card-4714: patch --swimlane writes the card's TOP-LEVEL swimlane_id (not a payload
# key), resolving a name through the SAME swimlane_id() helper `list` uses. A numeric
# --task short-circuits resolve_task (no search call) and kb_api is stubbed to echo the
# request body, so this is network-free. Assert on the flat .swimlane_id.
export KB_SWIMLANE_1=device KB_SWIMLANE_2=backend
sp() { cmd_patch --task 99 "$@" 2>/dev/null | jq -c '.'; }
eq "patch --swimlane by name → resolved id"        "2"    "$(sp --swimlane backend | jq -c '.swimlane_id')"
eq "patch --swimlane by numeric id → passthrough"  "5"    "$(sp --swimlane 5 | jq -c '.swimlane_id')"
# none/0 unassign: the key must be PRESENT and null (an EXPLICIT null clears the column
# per the API's per-key merge) — assert `[has, value]` so an absent key (setter reverted)
# reds instead of reading the same as a genuine null.
eq "patch --swimlane none → key present + null (unassign)" '[true,null]' \
   "$(sp --swimlane none | jq -c '[has("swimlane_id"), .swimlane_id]')"
eq "patch --swimlane 0 → key present + null (unassign)"    '[true,null]' \
   "$(sp --swimlane 0 | jq -c '[has("swimlane_id"), .swimlane_id]')"
# swimlane_id is a top-level column, NOT a payload key — must not leak into task.payload.
eq "patch --swimlane sets a top-level column, not payload" "false" \
   "$(sp --swimlane backend | jq '(.payload // {}) | has("swimlane_id")')"
# Negative control: no --swimlane leaves the key ABSENT (proves the flag is load-bearing).
eq "patch without --swimlane → swimlane_id key ABSENT" "false" "$(sp --dl DL-1 | jq 'has("swimlane_id")')"
# A typo'd name fails LOUD (rc 2, explicit `|| return 2`) — never a silent wrong write.
# Call cmd_patch directly (not the `sp` pipe wrapper, which would mask it with jq's rc).
rc=0; cmd_patch --task 99 --swimlane bogus >/dev/null 2>&1 || rc=$?
eq "patch --swimlane typo → rc 2 (loud, no write)" "2" "$rc"

# The write echo SURFACES swimlane_id ONLY when --swimlane was set (parity with it
# always showing workflow_stage_id) — so a --swimlane patch confirms the resulting lane
# and other patches keep their echo shape. The REAL _kbc_write_echo (captured above,
# restored here — not a copy) + a kb_api returning the server's {data:…} envelope.
kb_api() { printf '%s' '{"data":{"id":99,"name":"x","workflow_stage_id":5,"swimlane_id":2}}'; }
eval "_kbc_write_echo() $(declare -f _kbc_write_echo_orig | tail -n +2)"
eq "patch --swimlane echo surfaces swimlane_id"      "true"  "$(cmd_patch --task 99 --swimlane backend 2>/dev/null | jq 'has("swimlane_id")')"
eq "patch WITHOUT --swimlane echo omits swimlane_id" "false" "$(cmd_patch --task 99 --dl DL-1 2>/dev/null | jq 'has("swimlane_id")')"
unset -f sp

# ---------------------------------------------------------------------------
echo "== cmd_create_card --swimlane — birth a card ON a lane (card#5671, roundtable #205) =="
# The gap: create-card rejected --swimlane (rc 2, `unknown arg`) while patch and list both
# advertised it two lines away in the same usage block, so minting onto a lane took
# create-then-patch — leaving a laneless window any lane-keyed reader can observe.
# The create POST honours swimlane_id at birth (measured on a swimlaned board, roundtable
# #205), so the flag rides the create body directly; no create+patch composition.
# Network-free: kb_api echoes the request body ($3); the write-echo passes it through.
# _CC_POSTED records whether kb_api was reached AT ALL — the fail-before-write assertion
# below is about a POST that must never happen, which a body assertion alone cannot show.
_CC_POSTED="$(mktemp)"; trap 'rm -f "$_CC_POSTED"' EXIT
kb_api() { printf 'yes' > "$_CC_POSTED"; printf '%s' "$3"; }
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_TYPE_TASK=21
cc() { : > "$_CC_POSTED"; cmd_create_card --type task --name x "$@" 2>/dev/null | jq -c '.'; }

eq "create --swimlane by name → resolved id"       "2" "$(cc --swimlane backend | jq -c '.swimlane_id')"
eq "create --swimlane by numeric id → passthrough" "5" "$(cc --swimlane 5       | jq -c '.swimlane_id')"
# none/0 birth the card explicitly laneless: the key must be PRESENT and null, so an
# absent key (flag silently dropped) reds instead of reading the same as a genuine null.
eq "create --swimlane none → key present + null" '[true,null]' \
   "$(cc --swimlane none | jq -c '[has("swimlane_id"), .swimlane_id]')"
eq "create --swimlane 0 → key present + null"    '[true,null]' \
   "$(cc --swimlane 0    | jq -c '[has("swimlane_id"), .swimlane_id]')"
# swimlane_id is a top-level column, NOT a payload key — must not leak into task.payload.
eq "create --swimlane sets a top-level column, not payload" "false" \
   "$(cc --swimlane backend | jq '(.payload // {}) | has("swimlane_id")')"
# Negative control: without the flag the key is ABSENT (proves the flag is load-bearing,
# and that an ordinary create's body is byte-unchanged by this feature).
eq "create without --swimlane → key ABSENT" "false" "$(cc | jq 'has("swimlane_id")')"

# A typo'd lane must fail rc 2 with NO POST AT ALL. Accepting the flag and then birthing
# the card laneless (or in a wrong lane) is strictly worse than the old rc-2 rejection —
# a wrong card exists and something has to notice it. Assert the write never happened.
: > "$_CC_POSTED"
rc=0; cmd_create_card --type task --name x --swimlane bogus >/dev/null 2>&1 || rc=$?
eq "create --swimlane typo → rc 2"              "2"  "$rc"
eq "create --swimlane typo → NO card POSTed"    ""   "$(cat "$_CC_POSTED")"
# Positive control for that assertion: the same probe records a POST on the happy path,
# so the empty result above is a measurement, not a stub that never writes.
: > "$_CC_POSTED"; cmd_create_card --type task --name x --swimlane backend >/dev/null 2>&1
eq "control: a valid create DOES reach the POST" "yes" "$(cat "$_CC_POSTED")"
# An explicitly-empty value is a caller bug (an unexpanded var), not "use the default".
rc=0; cmd_create_card --type task --name x --swimlane "" >/dev/null 2>&1 || rc=$?
eq "create --swimlane \"\" → rc 2" "2" "$rc"

# ONE owner for the none/0→null rule (canon #5): create-card and patch must map the SAME
# ref to the SAME swimlane_id. RED-when-reverted: re-inline a second none/0 branch in
# either command and any divergence — notably `0` writing 0 instead of null — reds here.
for ref in backend 5 none 0; do
    eq "create/patch agree on --swimlane $ref" \
       "$(cmd_patch --task 99 --swimlane "$ref" 2>/dev/null | jq -c '.swimlane_id')" \
       "$(cc --swimlane "$ref" | jq -c '.swimlane_id')"
done

# The write echo surfaces swimlane_id ONLY when the flag was passed — same rule as patch,
# so the caller sees the lane the server recorded. Uses the REAL projection over a server
# {data:…} envelope (captured before the patch block; restored here, not re-implemented).
kb_api() { printf '%s' '{"data":{"id":77,"name":"x","workflow_stage_id":48,"swimlane_id":2}}'; }
eval "_kbc_write_echo() $(declare -f _kbc_write_echo_orig | tail -n +2)"
eq "create --swimlane echo surfaces swimlane_id"      "true" \
   "$(cmd_create_card --type task --name x --swimlane backend 2>/dev/null | jq 'has("swimlane_id")')"
eq "create WITHOUT --swimlane echo omits swimlane_id" "false" \
   "$(cmd_create_card --type task --name x 2>/dev/null | jq 'has("swimlane_id")')"

rm -f "$_CC_POSTED"; unset _CC_POSTED; trap - EXIT
unset KB_BOARD_ID KB_STAGE_BACKLOG KB_TYPE_TASK
unset KB_SWIMLANE_1 KB_SWIMLANE_2
unset -f cc _kbc_write_echo_orig

# ---------------------------------------------------------------------------
echo "== patch's corrective setters — the five write-once-at-birth fields (card#5776) =="
# THE CLASS: --name/--tags/--type/--external-id/--origin were settable only by create-card,
# so a card minted wrong stayed wrong. The shipped consequence was a card name stamped once
# from a PR title that Dependabot then RETARGETED — the card asserted a version the merged
# diff never landed, with no supported way to retitle it.
#
# Network-free: a numeric --task short-circuits resolve_task; kb_api dispatches on the METHOD
# so the tag read-merge-write has a GET to read (patch must re-send the whole list — the API
# replaces `tags` wholesale) while the PATCH echoes its request body back to be asserted on.
# The request log is what makes "no write happened" a measurement rather than an assumption.
_REQ_LOG="$(mktemp)"
trap 'rm -f "$_REQ_LOG"' EXIT
_CUR_TAGS='[]'
kb_api() {
    printf '%s\n' "$1" >> "$_REQ_LOG"
    case "$1" in
        GET) printf '{"data":{"id":99,"tags":%s}}' "$_CUR_TAGS" ;;
        *)   printf '%s' "$3" ;;
    esac
}
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_STAGE_IN_REVIEW=50
# pb <args…> — run cmd_patch on a fresh request log, return the PATCH request body.
pb() { : > "$_REQ_LOG"; cmd_patch --task 99 "$@" 2>/dev/null; }
# reqs — the methods this call issued, in order (e.g. "GET PATCH").
reqs() { tr '\n' ' ' < "$_REQ_LOG" | sed 's/ $//'; }

echo "-- --name: the member with the shipped consequence (card#5385) --"
eq "--name writes the new title"      '"retitled"' "$(pb --name retitled | jq -c '.name')"
eq "--name needs no tag read"         "PATCH"      "$(reqs)"
# Negative control: the key is ABSENT without the flag, so the assertion above is the flag's
# doing and not a field this body always carries.
eq "no --name → name key ABSENT"      "false"      "$(pb --dl DL-7 | jq 'has("name")')"

echo "-- --external-id: numeric, fail-loud, and no half-write --"
eq "--external-id writes a JSON number" "4242"     "$(pb --external-id 4242 | jq -c '.external_id')"
eq "no --external-id → key ABSENT"      "false"    "$(pb --dl DL-7 | jq 'has("external_id")')"
: > "$_REQ_LOG"
rc=0; err="$(cmd_patch --task 99 --external-id abc 2>&1 >/dev/null)" || rc=$?
eq "--external-id non-numeric → rc 2"          "2"    "$rc"
eq "--external-id non-numeric names the flag"  "true" "$(has '--external-id must be numeric' "$err")"
eq "--external-id non-numeric → NO request"    ""     "$(reqs)"
# Positive control for that empty result: the same probe DOES record a PATCH when the value
# is valid, so "no request" is a measurement and not a stub that never writes.
eq "control: a valid --external-id reaches the PATCH" "PATCH" "$(pb --external-id 4242 >/dev/null; reqs)"

echo "-- --type: re-type the card, and never leave it reading as two types --"
export KB_TYPE_TASK=21; unset KB_TYPING_MODE 2>/dev/null || true
_CUR_TAGS='["type:bug","keep"]'
b="$(pb --type task)"
eq "native board → card_type_id written"        "21"          "$(jq -c '.card_type_id' <<<"$b")"
eq "native board → stale type: tag dropped"     '["keep"]'    "$(jq -c '.tags' <<<"$b")"
eq "--type reads the current tags first"        "GET PATCH"   "$(reqs)"
# The mixed-board hazard this strip exists for: `list --type bug` resolves an alias with no
# native id through the `type:` TAG clause, so a card retyped to a native type while keeping
# `type:bug` would still answer as a bug. RED-when-reverted: drop the strip and the tags
# assertion above becomes ["type:bug","keep"].
unset KB_TYPE_TASK; export KB_TYPING_MODE=tags
b="$(pb --type task)"
eq "tag board → no card_type_id"                "false"                 "$(jq 'has("card_type_id")' <<<"$b")"
eq "tag board → type: tag swapped, not added"   '["keep","type:task"]'  "$(jq -c '.tags' <<<"$b")"
unset KB_TYPING_MODE; export KB_TYPE_TASK=21
rc=0; err="$(cmd_patch --task 99 --type 'not an alias' 2>&1 >/dev/null)" || rc=$?
eq "--type with a space → rc 2"                 "2"    "$rc"
eq "--type with a space names the flag"         "true" "$(has "--type 'not an alias'" "$err")"
eq "no --type → card_type_id key ABSENT"        "false" "$(pb --dl DL-7 | jq 'has("card_type_id")')"

echo "-- --tags: replaces the list wholesale, and composes with --triaged --"
_CUR_TAGS='["dropped"]'
eq "--tags replaces the whole list"     '["a","b"]'          "$(pb --tags a,b | jq -c '.tags')"
eq "--tags spares the read"             "PATCH"              "$(reqs)"
eq "--tags + --triaged appends triaged" '["a","b","triaged"]' "$(pb --tags a,b --triaged | jq -c '.tags')"
eq "no tag flag → tags key ABSENT"      "false"              "$(pb --dl DL-7 | jq 'has("tags")')"

echo "-- --triaged keeps the card's existing tag ORDER (it no longer sorts) --"
# `unique` re-sorted every tag a card carried on an unrelated --triaged patch. First-seen
# order is what create-card writes, so both writers now agree.
_CUR_TAGS='["zeta","alpha"]'
eq "--triaged appends without re-sorting" '["zeta","alpha","triaged"]' "$(pb --triaged | jq -c '.tags')"
_CUR_TAGS='["alpha","triaged"]'
eq "--triaged is idempotent (no dupe)"    '["alpha","triaged"]'        "$(pb --triaged | jq -c '.tags')"
_CUR_TAGS='[]'

echo "-- --origin: provenance is correctable, through the same payload assembler --"
eq "--origin stamps payload.origin"  '"consumer-driven"' "$(pb --origin consumer-driven | jq -c '.payload.origin')"
eq "no --origin → payload key ABSENT" "false"            "$(pb --name x | jq 'has("payload")')"

echo "-- everything resolvable offline is resolved BEFORE any request --"
# A typo'd column must not leave a card tag-read (or worse, half-written): rc 2, no traffic.
: > "$_REQ_LOG"
rc=0; cmd_patch --task 99 --column bogus --triaged >/dev/null 2>&1 || rc=$?
eq "--column typo → rc 2"          "2" "$rc"
eq "--column typo → NO request"    ""  "$(reqs)"
eq "control: a valid --column reaches the PATCH" "50" "$(pb --column in_review | jq -c '.workflow_stage_id')"

echo "-- ONE owner assembles the task fields for BOTH writers (canon #5) --"
# The consolidation IS the fix: five fields drifted onto create-card alone because each
# command carried its own top-level field assembly, so a sixth would drift the same way.
# Stub the shared owner with a sentinel and assert both bodies carry it — re-inline the jq
# in either command and this reds, which no per-field value assertion would.
eval "_kbc_task_fields_orig() $(declare -f _kbc_task_fields | tail -n +2)"
_kbc_task_fields() { printf '{"_shared_owner":true}'; }
eq "create-card assembles via _kbc_task_fields" "true" \
   "$(cmd_create_card --type task --name x 2>/dev/null | jq '._shared_owner')"
eq "patch assembles via _kbc_task_fields"       "true" \
   "$(cmd_patch --task 99 --name y 2>/dev/null | jq '._shared_owner')"
eval "_kbc_task_fields() $(declare -f _kbc_task_fields_orig | tail -n +2)"
unset -f _kbc_task_fields_orig
# And they agree on the RESOLVED value, not just the code path: the same --type alias must
# produce the same card_type_id from both, on a native board and a tag-typed one alike.
eq "create/patch agree on --type (native)" \
   "$(cmd_create_card --type task --name x 2>/dev/null | jq -c '[.card_type_id, (.tags//[]|index("type:task"))]')" \
   "$(pb --type task | jq -c '[.card_type_id, (.tags//[]|index("type:task"))]')"
unset KB_TYPE_TASK; export KB_TYPING_MODE=tags
eq "create/patch agree on --type (tag mode)" \
   "$(cmd_create_card --type task --name x 2>/dev/null | jq -c '[.card_type_id, (.tags//[]|index("type:task"))]')" \
   "$(pb --type task | jq -c '[.card_type_id, (.tags//[]|index("type:task"))]')"

unset KB_TYPING_MODE KB_BOARD_ID KB_STAGE_BACKLOG KB_STAGE_IN_REVIEW
unset -f kb_api pb reqs
unset _CUR_TAGS
rm -f "$_REQ_LOG"; unset _REQ_LOG; trap - EXIT

# ---------------------------------------------------------------------------
echo "== --pr / --issue must name ONE POSITIVE integer — the correlation MINT site (card#7536) =="
# THE DEFECT, and why it is refused HERE rather than handled by each reader: kbcard is the
# reachable operator path that WRITES payload.pr_number / issue_number, and it accepted any
# string. A stored value carrying SEVERAL digit runs is then read two incompatible ways and
# neither reader errors — a board applying kanban's DL-251 rule (`^\D*(\d+)\D*$`) derives NO
# reference, so the card correlates to nothing while its stamp looks set, while a reader that
# strips every non-digit derives the CONCATENATION of the runs ("1.5" -> 15, "2026-08-23" ->
# 20260823): a real but DIFFERENT pull request or issue. One value, two authorities, two
# answers. The refusal is at the mint site because that is upstream of both, and because the
# value is only unambiguous at the moment it is typed.
#
# Unit legs on the shared assembler first, then both verbs as its callers, then the leg that
# makes "before any request" a measurement rather than a claim.
unset KB_CF_VERSION_TARGET 2>/dev/null || true

echo "-- the rule, on the shared assembler --"
# arg 2 is --pr, arg 5 is --issue (see _kbc_build_payload's positional contract).
for bad in 1.5 2026-08-23 "PR 12 of 34" TBD 1.0e20; do
    rc=0; out="$(_kbc_build_payload '' "$bad" '' '' '' '' 2>/dev/null)" || rc=$?
    eq "--pr '$bad' -> rc 2"       "2" "$rc"
    eq "--pr '$bad' -> no payload" ""  "$out"
    rc=0; out="$(_kbc_build_payload '' '' '' '' "$bad" '' 2>/dev/null)" || rc=$?
    eq "--issue '$bad' -> rc 2"       "2" "$rc"
    eq "--issue '$bad' -> no payload" ""  "$out"
done
# The diagnostic names the FLAG and the VALUE — a refusal that names neither leaves the caller
# guessing which of two co-stamped correlation flags it was about.
err="$(_kbc_build_payload '' 1.5 '' '' '' '' 2>&1 >/dev/null || true)"
eq "the refusal names the flag"  "true" "$(has "kbcard: --pr '1.5'" "$err")"
err="$(_kbc_build_payload '' '' '' '' 2026-08-23 '' 2>&1 >/dev/null || true)"
eq "…and names --issue when it is --issue" "true" "$(has "kbcard: --issue '2026-08-23'" "$err")"

# THE POSITIVE CONTROLS, and the reason they are not optional: every assertion above is a
# refusal, and a predicate that refused EVERYTHING would satisfy all of them. The accept set is
# the board's own accept-set NARROWED TO THE POSITIVES — one integer, optionally decorated — so
# a decorated spelling the board canonicalizes must still pass here. (`0` was a control on this
# list until the sign/zero ruling below refused it; the reasoning it carried is preserved and
# answered there.)
eq "control: a bare integer still stamps"     '{"pr_number":178}'   "$(_kbc_build_payload '' 178 '' '' '' '' | jq -Sc .)"
eq "control: a DECORATED integer still stamps" '{"pr_number":"#178"}' "$(_kbc_build_payload '' '#178' '' '' '' '' | jq -Sc .)"
eq "control: PR-085 is one decorated integer"  '{"issue_number":"PR-085"}' "$(_kbc_build_payload '' '' '' '' 'PR-085' '' | jq -Sc .)"
eq "control: a decorated value with an INTERIOR hyphen is not a sign" '{"pr_number":"PR-085"}' \
   "$(_kbc_build_payload '' 'PR-085' '' '' '' '' | jq -Sc .)"
# ⚠ SHAPE, not declared TYPE: a decorated value is not numeric, so it rides as a JSON STRING
# (above) and a `number`-typed pr_number refuses it server-side. That is a different question
# and deliberately not this predicate's — narrowing to a bare integer would refuse a spelling
# the board itself canonicalizes, on a board that declares the field `string`.
#
# ⭐ THE SIGN PIN, FLIPPED — DELIBERATELY, AND THIS IS WHERE THE RULING IS RECORDED.
#
# WHAT THIS LEG USED TO ASSERT, AND WHY IT DID. The first half of card#7536 landed the SHAPE
# rule only, and `-5` satisfies it by construction: `-` is a non-digit, so `-5` is ONE decorated
# integer under the board's own rule. That was left standing rather than narrowed on the spot
# because narrowing it REFUSES a value the approved rule accepts, which was a ruling nobody had
# made — and this leg existed precisely so the narrowing could not land silently. It has now
# been made, and this is its record.
#
# WHY REFUSING IS RIGHT. `-5` was accepted and STORED, and the three readers of that one stamp
# then answered three different ways with none of them erring: this tool stored `-5`; the board
# drops the sign with the rest of the decoration and indexes the card under github_pr ref "5",
# a real but DIFFERENT pull request (MEASURED on the vendored 1:1 mirror of the server's rule,
# `canonicalize('github_pr', '-5') === '5'`, not inferred); and the reconciler's own ADMISSION
# test, `is_numeric && (float) > 0` — which DL-309 deliberately did NOT widen — declines the
# value outright, so the card is invisible to it. Stored, mis-correlated and invisible at once.
# GitHub numbers pull requests and issues from 1, so refusing costs no legitimate caller, and it
# collapses the three answers into one at the MINT site, which is the cheapest place to fix it
# and the only point at which the value is still unambiguous.
#
# ZERO GOES WITH IT, as its own explicit ruling and not a side effect of the sign. `0` was
# accepted and stamped too (this block's own former positive control asserted it, on the
# reasoning that kbcard's pre-PR placeholder is `.../pull/0`) — but that placeholder is a URL
# and rides on `--pr-url`, which this predicate does not cover and which is untouched; nothing
# in the toolkit passes `--pr 0`. There is no pull request or issue 0 to correlate to, the board
# indexes ref "0" and the same `> 0` admission test declines it, and `--dl` — the third
# correlation key — has refused a token resolving to 0 in its own words since it was written.
# The three keys now agree.
#
# The accept set is still NON-EMPTY and still DECORATED (the four controls above), so the
# refusals below are not satisfiable by a predicate that refuses everything.
for neg in -5 ' -5' -0 '-178'; do
    rc=0; out="$(_kbc_build_payload '' "$neg" '' '' '' '' 2>/dev/null)" || rc=$?
    eq "ruling: --pr '$neg' is NEGATIVE -> rc 2" "2" "$rc"
    eq "ruling: --pr '$neg' -> no payload"       ""  "$out"
    rc=0; out="$(_kbc_build_payload '' '' '' '' "$neg" '' 2>/dev/null)" || rc=$?
    eq "ruling: --issue '$neg' is NEGATIVE -> rc 2" "2" "$rc"
done
err="$(_kbc_build_payload '' -5 '' '' '' '' 2>&1 >/dev/null || true)"
eq "the sign refusal names the flag and the value" "true" "$(has "kbcard: --pr '-5'" "$err")"
eq "…and says NEGATIVE, not \"not one integer\""   "true" "$(has "is NEGATIVE" "$err")"
# ZERO, in every spelling that names it — bare, padded, and decorated. `#0` and `PR-000` are the
# legs a bare `-eq 0` arithmetic test would miss: they ride as JSON strings, never as numbers.
for z in 0 00 '#0' 'PR-000' 'issue-0'; do
    rc=0; out="$(_kbc_build_payload '' "$z" '' '' '' '' 2>/dev/null)" || rc=$?
    eq "ruling: --pr '$z' names ZERO -> rc 2" "2" "$rc"
    eq "ruling: --pr '$z' -> no payload"      ""  "$out"
    rc=0; out="$(_kbc_build_payload '' '' '' '' "$z" '' 2>/dev/null)" || rc=$?
    eq "ruling: --issue '$z' names ZERO -> rc 2" "2" "$rc"
done
err="$(_kbc_build_payload '' 'PR-000' '' '' '' '' 2>&1 >/dev/null || true)"
eq "the zero refusal names the flag and the value" "true" "$(has "kbcard: --pr 'PR-000'" "$err")"
eq "…and points at --pr-url for the placeholder"   "true" "$(has "--pr-url" "$err")"
# ⭐ THE SCOPE LEG. The narrowing is the SIGN and ZERO — nothing else moved, and #304's
# deliberate non-decisions stay non-decided: a decorated value is still accepted (no bare-integer
# requirement), and `--pr-url` / `--issue-url` still take any string, including the `.../pull/0`
# placeholder the zero rule above would otherwise read as a refusal.
eq "scope: --pr-url is untouched, placeholder and all" \
   '{"pr_url":"https://github.com/o/r/pull/0"}' \
   "$(_kbc_build_payload '' '' 'https://github.com/o/r/pull/0' '' '' '' | jq -Sc .)"
eq "scope: --issue-url is untouched too" \
   '{"issue_url":"https://github.com/o/r/issues/0"}' \
   "$(_kbc_build_payload '' '' '' '' '' 'https://github.com/o/r/issues/0' | jq -Sc .)"
# ⭐ THE SIBLING AXIS, ASSERTED RATHER THAN ARGUED. The other two flags that carry an integer
# correlation key were audited for this same hole and have none — their predicates are ANCHORED
# canonical-decimal (`kb_is_uint`) and anchored DL (`kb_dl_num`), so neither ever admitted a
# sign, and `kb_dl_num` already refused 0. These legs pin that, so a future widening of either
# predicate to a decoration-tolerant one cannot re-open the hole unnoticed.
rc=0; _kbc_require_ext_id -5 >/dev/null 2>&1 || rc=$?
eq "sibling: --external-id -5 was ALREADY refused" "2" "$rc"
rc=0; kb_dl_canon -5 >/dev/null 2>&1 || rc=$?
eq "sibling: --dl -5 was ALREADY refused"          "2" "$rc"
rc=0; kb_dl_canon 0 >/dev/null 2>&1 || rc=$?
eq "sibling: --dl 0 was ALREADY refused"           "2" "$rc"

echo "-- both verbs refuse it, and the refusal costs NO request --"
_REF_LOG="$(mktemp)"
trap 'rm -f "$_REF_LOG"' EXIT
# GET answers the external-id search with a resolvable row; every other method echoes its
# request body. The log is what turns "no request" into a measurement.
kb_api() {
    printf '%s\n' "$1" >> "$_REF_LOG"
    case "$1" in GET) printf '{"data":[{"id":99}]}' ;; *) printf '%s' "$3" ;; esac
}
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_TYPE_TASK=21
unset KB_TYPING_MODE 2>/dev/null || true
rreqs() { tr '\n' ' ' < "$_REF_LOG" | sed 's/ $//'; }

: > "$_REF_LOG"
rc=0; cmd_patch --task 99 --pr 1.5 >/dev/null 2>&1 || rc=$?
eq "patch --pr 1.5 -> rc 2"       "2" "$rc"
eq "patch --pr 1.5 -> NO request" ""  "$(rreqs)"
: > "$_REF_LOG"
rc=0; cmd_create_card --type task --name x --issue 2026-08-23 >/dev/null 2>&1 || rc=$?
eq "create-card --issue 2026-08-23 -> rc 2"        "2" "$rc"
eq "create-card --issue 2026-08-23 -> NO card POSTed" "" "$(rreqs)"
# Positive controls for those two empty results: the same probes DO reach the wire on a valid
# value, so the empties measure the refusal and not a stub that never writes.
: > "$_REF_LOG"; cmd_patch --task 99 --pr 178 >/dev/null 2>&1
eq "control: a valid --pr reaches the PATCH"      "PATCH" "$(rreqs)"
: > "$_REF_LOG"; cmd_create_card --type task --name x --issue 300 >/dev/null 2>&1
eq "control: a valid --issue reaches the POST"    "POST"  "$(rreqs)"

# ⭐ THE ORDERING LEG. `--task 99` short-circuits resolve_task, so the two "NO request" legs
# above would hold even if the payload were assembled AFTER the ref lookup. An EXTERNAL task
# ref is what distinguishes them: the refusal must land before the external-id search, i.e.
# the assembler must sit with the no-network preflight, not below resolve_task.
: > "$_REF_LOG"
rc=0; cmd_patch --task EXT-9 --pr 1.5 >/dev/null 2>&1 || rc=$?
eq "patch --task EXT-9 --pr 1.5 -> rc 2"                    "2" "$rc"
eq "…and NOT EVEN the external-id lookup was issued"        ""  "$(rreqs)"
: > "$_REF_LOG"; cmd_patch --task EXT-9 --pr 178 >/dev/null 2>&1
eq "control: the same ref DOES search, then PATCH, on a valid --pr" "GET PATCH" "$(rreqs)"
# The SIGN and ZERO arms ride the same assembler at the same point, and "rc 2 before any
# request" is measured for them too rather than inherited by argument: they are new arms of an
# existing guard, and a guard's ORDER is the property a later edit is most likely to move.
: > "$_REF_LOG"
rc=0; cmd_patch --task EXT-9 --pr -5 >/dev/null 2>&1 || rc=$?
eq "patch --task EXT-9 --pr -5 -> rc 2"                     "2" "$rc"
eq "…and the sign refusal issued no lookup either"          ""  "$(rreqs)"
: > "$_REF_LOG"
rc=0; cmd_create_card --type task --name x --issue 0 >/dev/null 2>&1 || rc=$?
eq "create-card --issue 0 -> rc 2"                          "2" "$rc"
eq "create-card --issue 0 -> NO card POSTed"                ""  "$(rreqs)"
# --dl rides the same assembler and inherits the same ordering — it was refused only AFTER the
# lookup before this moved.
: > "$_REF_LOG"
rc=0; cmd_patch --task EXT-9 --dl not-a-dl >/dev/null 2>&1 || rc=$?
eq "patch --task EXT-9 --dl not-a-dl -> rc 2"        "2" "$rc"
eq "…and issues no request either"                   ""  "$(rreqs)"

unset -f kb_api rreqs
unset KB_BOARD_ID KB_STAGE_BACKLOG KB_TYPE_TASK
rm -f "$_REF_LOG"; unset _REF_LOG; trap - EXIT

# ---------------------------------------------------------------------------
echo "== value-taking flags reject an EMPTY value (card#5146) =="
# An option that consumes "$2" and is then dispatched with `[[ -n "$var" ]]` reads an
# explicitly-empty value as an ABSENT flag. `kbcard patch --dl "$DL"` with DL unset
# therefore stamped NOTHING and still exited 0 — a card silently left without the
# correlation ref it was told to carry, which never promotes at release. The guard makes
# the flag's PRESENCE the dispatch signal. RED-when-reverted: drop kb_require_value from
# the --dl arm and the first two assertions flip (rc 0, body `{}`).
# Echo the request body back and pass the write echo through (the block above restored the
# REAL _kbc_write_echo, which expects a server {data:…} envelope this stub does not send).
kb_api() { printf '%s' "$3"; }   # $3 is the request body
_kbc_write_echo() { printf '%s' "$3"; }   # $3 is the response (see its new signature)

rc=0; err="$(cmd_patch --task 99 --dl "" 2>&1 >/dev/null)" || rc=$?
eq "patch --dl \"\" → rc 2"                        "2"    "$rc"
eq "patch --dl \"\" names the flag"                "true" "$(case "$err" in *'--dl requires a non-empty value'*) echo true ;; *) echo false ;; esac)"
# The negative control that makes the above attributable: a REAL value still stamps.
eq "patch --dl DL-7 still stamps (control)"        "DL-0007" \
   "$(cmd_patch --task 99 --dl DL-7 2>/dev/null | jq -r '.payload.dl_number')"

# The whole class, not the one reported instance — and "the whole class" is now DERIVED from
# the bin rather than typed here (card#6645). A hand list cannot red when kbcard grows a flag,
# so this block's totality claim narrowed silently with every release; `expect_value_flags`
# compares the guard call sites in `bin/kbcard` against the two lists below and reds in both
# directions. The split is the claim, stated honestly: DRIVEN_HERE is what this block actually
# exercises with an empty value, GUARDED_NOT_DRIVEN is the rest of the guarded population —
# they share ONE owner (`kb_require_value`), so driving all 27 through their several verbs
# would re-assert one primitive 27 times. What the gate buys is that a 28th flag cannot join
# either list without an explicit edit here, which is the review moment a hand list never got.
DRIVEN_HERE=(--dl --pr --pr-url --issue --issue-url --version --column --swimlane --description
             --name --tags --type --external-id --origin --task)
GUARDED_NOT_DRIVEN=(--board            # the global pre-verb flag; driven empty as a PROCESS in
                                       # kb-positional-guard-selftest.sh, the only file with a
                                       # resolvable kbcard config
                    --content          # driven with an empty value at the comment verb, below
                    --options          # driven empty in kbcard-field-selftest.sh
                    --content-file --description-file --name-file
                    --field --from --to --relation --key --label)
expect_value_flags "$BIN" "${DRIVEN_HERE[@]}" "${GUARDED_NOT_DRIVEN[@]}"
for f in --dl --pr --pr-url --issue --issue-url --version --column --swimlane --description \
         --name --tags --type --external-id --origin; do
    rc=0; err="$(cmd_patch --task 99 "$f" "" 2>&1 >/dev/null)" || rc=$?
    eq "patch $f \"\" → rc 2"                      "2"    "$rc"
    eq "patch $f \"\" names the flag"              "true" "$(case "$err" in *"$f requires a non-empty value"*) echo true ;; *) echo false ;; esac)"
done

# A trailing flag with no argument at all names the flag rather than leaking `set -u`.
rc=0; err="$(cmd_patch --task 99 --dl 2>&1 >/dev/null)" || rc=$?
eq "patch trailing --dl → rc 2"                    "2"    "$rc"
eq "patch trailing --dl does not leak set -u"      "false" "$(case "$err" in *'unbound variable'*) echo true ;; *) echo false ;; esac)"

# --task itself is a REQUIRED flag and was already guarded by its own -z check; assert the
# empty case still fails loud so the new guard didn't displace it into a different verdict.
rc=0; cmd_patch --task "" --dl DL-7 >/dev/null 2>&1 || rc=$?
eq "patch --task \"\" → rc 2"                      "2"    "$rc"

unset KB_BOARD_ID KB_STAGE_BACKLOG KB_TYPE_TASK KB_CF_VERSION_TARGET

# ---------------------------------------------------------------------------
echo "== comment / comments — the card audit-trail verbs (card#6051) =="
# THE GAP: posting a card comment — the routine audit trail — had no verb, so every caller
# hand-rolled the API call. The API semantics below were MEASURED against the sandbox instance
# (board 1162) before any of this was written, and each measurement is what one assertion here
# pins: the body is FLAT `{"content": …}` (the wrapped `{"comment":{…}}` form is 422), the POST
# 201s echoing the created row, adding a comment does NOT bump the card's updated_at (so the
# echoed id is the only cheap write verification), and there is NO comment read route at all —
# GET on the comments path is 405, POST-only, which is why `comments` projects the array the
# task detail GET already carries.
#
# WHY THIS BLOCK DRIVES THE BIN AS A PROCESS while everything above stubs `kb_api` as a shell
# function: the property under test is that success is decided on the HTTP STATUS CLASS and
# never on the response body's shape, and a stubbed `kb_api` IS the code that decides that — a
# test that replaces it cannot observe the thing it claims to check. The seam therefore sits
# BELOW the lib (a `curl` stand-in on PATH, tests/_kb-api-stub.sh), so kb_load_config, kb_api,
# the arg parse, main's dispatch and the process exit status all run for real.
#
# EVERY grep in this block is spelled `/usr/bin/grep`, for one reason that applies to all of
# them: the ambient `grep` on some hosts is a shim (an alias, a function, a wrapper on PATH) and
# a shim that colourizes, or that answers a `-c` differently, turns an assertion about kbcard's
# output into an assertion about the host's grep. The absolute path is the same grep everywhere.

# _kbc_comments_render is pure, so it is asserted on synthetic comments first — the shapes a
# faked board can produce cheaply, before the process-level checks.
eq "render: one comment is a header line + its indented content" \
   "$(printf 'comment 13 · user 2238 · 2026-08-12T23:40:36+00:00\n  hello')" \
   "$(printf '%s' '[{"id":13,"user_id":2238,"content":"hello","created_at":"2026-08-12T23:40:36+00:00"}]' | _kbc_comments_render)"
# EVERY line of a multi-line comment is indented: an unindented second line reads as the start
# of the next comment, which is the whole reason the content is not printed verbatim.
eq "render: every line of a multi-line comment is indented" \
   "$(printf 'comment 14 · user 7 · 2026-08-12T23:41:12+00:00\n  line1\n  line2')" \
   "$(printf '%s' '[{"id":14,"user_id":7,"content":"line1\nline2","created_at":"2026-08-12T23:41:12+00:00"}]' | _kbc_comments_render)"
eq "render: two comments are two blocks" "2" \
   "$(printf '%s' '[{"id":1,"user_id":7,"content":"a","created_at":"t"},{"id":2,"user_id":7,"content":"b","created_at":"t"}]' \
      | _kbc_comments_render | /usr/bin/grep -c '^comment ')"
# The author is a bare user id because that is the ONLY author field a comment row carries
# (measured) — a name would be a fabrication. A missing header field degrades to `?`, not to
# "null" — id, user_id and created_at alike.
eq "render: a row with no header fields says ? rather than null" "comment ? · user ? · ?" \
   "$(printf '%s' '[{"content":"","created_at":null}]' | _kbc_comments_render)"
# The TAB is exempt alongside the newline. It IS a C0 control, but it cannot move the cursor
# backward — it only advances to the next tab stop — so replacing it buys nothing against the
# thing this filter exists for (an ESC sequence erasing the attribution line above) while
# damaging every pasted diff, log line or indented block a comment carries.
eq "render: a TAB survives — it cannot move the cursor backward" \
   "$(printf 'comment 4 · user 7 · t\n  col1\tcol2')" \
   "$(printf '%s' '[{"id":4,"user_id":7,"content":"col1\tcol2","created_at":"t"}]' | _kbc_comments_render)"
# THE HEADER FIELDS ARE THE SAME UNTRUSTED BODY. id / user_id / created_at are interpolated into
# the very line the content filter exists to protect, so a control character there reaches the
# terminal by the shorter route — sanitizing the content and not the header would leave the hole
# open one line up. Their filter is STRICTER than the content's, and the newline case below is
# why: content can never forge a header (every content line is indented), while an unindented
# newline in a header field mints a whole extra `comment N · user M · t` block — a forged
# attribution, which is exactly what this filter exists to prevent. So no C0 control is exempt
# there, tab and newline included. Both fixtures build the control from its CODEPOINT — no raw
# control byte is typed into this file.
eq "render: an ESC in a header FIELD is neutralized, not just in the content" \
   "$(printf 'comment 5 · user 7 · t?[2K?[1Aimpostor\n  body')" \
   "$(jq -nc --arg e "$(printf '\033')" \
        '[{id:5,user_id:7,content:"body",created_at:("t" + $e + "[2K" + $e + "[1Aimpostor")}]' \
      | _kbc_comments_render)"
eq "render: a NEWLINE in a header field cannot forge a second block" \
   "$(printf 'comment 6 · user 7 · t?comment 99 · user 1 · t\n  body')" \
   "$(jq -nc '[{id:6,user_id:7,content:"body",created_at:"t\ncomment 99 · user 1 · t"}]' \
      | _kbc_comments_render)"
# …and the count assertion that says the forgery did not happen, independently of the exact
# rendering above: one comment in, ONE header line out.
eq "render: …so that fixture still renders exactly one block" "1" \
   "$(jq -nc '[{id:6,user_id:7,content:"body",created_at:"t\ncomment 99 · user 1 · t"}]' \
      | _kbc_comments_render | /usr/bin/grep -c '^comment ')"
# A TAB is exempt in the CONTENT and not in the header: the header carries an id, a user id and a
# timestamp, none of which has a legitimate tab, so the reason for the content exemption (it
# damages pasted diffs and indented blocks) simply does not apply there.
eq "render: a TAB in a header field is replaced, unlike one in the content" \
   "$(printf 'comment 7 · user 7 · a?b\n  col1\tcol2')" \
   "$(jq -nc '[{id:7,user_id:7,content:"col1\tcol2",created_at:"a\tb"}]' | _kbc_comments_render)"

# --- process-level: the real kb_api, over a faked kanban --------------------
rm -rf "$TMP"          # the earlier _mktmp_scratch's dir; its EXIT trap is replaced below
_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42
kb_stub_install

# The route table. Every knob is per-scenario so exactly one leg can be failed at a time.
# KB_STUB_POST_HTTP / KB_STUB_POST_BODY  — the comment POST's answer.
# KB_STUB_GET_HTTP  / KB_STUB_GET_COMMENTS — the task detail GET's answer.
# KB_STUB_GET_BODY — the detail GET's body VERBATIM, bypassing the envelope KB_STUB_GET_COMMENTS
#   fills in. Without it the GET arm can only emit well-formed JSON, so the one 2xx body that
#   breaks a reader — a proxy's HTML, a truncated read — would be unreachable on the READ side
#   while the write side already has a leg for it (KB_STUB_POST_BODY is free-form).
# NOT_FOUND_BODY is the REAL 404 body the un-suffixed comments path returns (captured from the
# sandbox, trace elided): well-formed JSON that any "did the body parse?" success test reads as
# a success, and carrying no `.data` — so a body-shape reader degrades to a SILENT empty
# success rather than to a crash. It is the fixture for the discrimination assertions below.
NOT_FOUND_BODY='{"message":"The route api/v3/tasks/505/comments could not be found.","exception":"Symfony\\Component\\HttpKernel\\Exception\\NotFoundHttpException","file":"/app/vendor/laravel/framework/src/Illuminate/Routing/AbstractRouteCollection.php","line":44,"trace":[{"function":"handleMatchedRoute"}]}'
# The 201 body the real API echoes for a created comment, verbatim in shape (measured).
KB_STUB_CREATED='{"data":{"id":13,"task_id":505,"user_id":2238,"content":"x","deleted_at":null,"created_at":"2026-08-12T23:40:36+00:00","updated_at":"2026-08-12T23:40:36+00:00"}}'
export NOT_FOUND_BODY KB_STUB_CREATED
kb_stub_route() {
    local method="$1" url="$2"
    case "$method $url" in
        "POST "*/tasks/*/comments.json)
            printf '%s\n%s' "${KB_STUB_POST_HTTP:-201}" \
                "${KB_STUB_POST_BODY:-$KB_STUB_CREATED}" ;;
        "GET "*/tasks/search.json*)
            printf '200\n{"data":[{"id":505}]}' ;;
        "GET "*/tasks/*.json)
            if [[ -n "${KB_STUB_GET_BODY:-}" ]]; then
                printf '%s\n%s' "${KB_STUB_GET_HTTP:-200}" "$KB_STUB_GET_BODY"
            else
                printf '%s\n{"data":{"id":505,"name":"probe","comments":%s}}' \
                    "${KB_STUB_GET_HTTP:-200}" "${KB_STUB_GET_COMMENTS:-[]}"
            fi ;;
    esac
}
export -f kb_stub_route

CPATH="/tasks/505/comments.json"

echo "-- comment: path, method, and the MEASURED flat body key --"
kbc comment --task 505 --content 'hello there'
eq "comment → rc 0"                              "0" "$rc"
eq "comment → exactly one POST to the .json comments path" "1" "$(kb_stub_count POST "$CPATH")"
eq "comment → and no other request at all"       "1" "$(kb_stub_total)"
# The body's key set is asserted as an EQUALITY, not a contains: the wrapped
# {"comment":{"content":…}} form the API refuses (422, measured) would still "contain" the
# text, and only a key-set equality can see that regression.
eq "comment → body is FLAT, exactly {content}"   '["content"]' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c 'keys')"
eq "comment → body carries the text verbatim"    '"hello there"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"
# The write verification (the card's updated_at does not move on a comment-add, so this id is
# the only confirmation the write landed).
eq "comment → prints the CREATED comment id on stdout" "13" "$out"

echo "-- comment: --content-file reaches the body, multi-line included --"
printf 'file line 1\nfile line 2\n' > "$TMP/c.txt"
kbc comment --task 505 --content-file "$TMP/c.txt"
eq "--content-file → rc 0"                       "0" "$rc"
# INTERIOR newlines ride verbatim; the file's TRAILING newline does not — the text is carried out
# of its resolver through a command substitution, which strips every trailing newline. That is
# the documented behaviour (the bin's usage block / README say so), not an accident, so it is
# pinned here rather than left as an unremarked property of the expected string.
eq "--content-file → the file's text is the body, trailing newline TRIMMED" \
   '"file line 1\nfile line 2"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"
printf 'file line 1\nfile line 2\n\n\n' > "$TMP/trail.txt"
kbc comment --task 505 --content-file "$TMP/trail.txt"
eq "--content-file → ALL trailing newlines are trimmed, not just one" \
   '"file line 1\nfile line 2"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"

echo "-- comment: a CRLF file does not put \\r on the wire --"
# Windows/Git-Bash is a documented install target (docs/INSTALL.md), so a --content-file written
# there arrives CRLF-terminated. An unnormalized \r is sent verbatim and then renders as `?` on
# EVERY line of the comment (the reader sanitizes C0 controls) — including a stray trailing one,
# because the command substitution above strips the \n and leaves the \r behind it. CR-before-LF
# is therefore normalized at the WRITE site, which owns both sources.
printf 'crlf line 1\r\ncrlf line 2\r\n' > "$TMP/crlf.txt"
kbc comment --task 505 --content-file "$TMP/crlf.txt"
eq "CRLF --content-file → rc 0"                  "0" "$rc"
eq "CRLF → the wire body has LF line breaks and no \\r at all" \
   '"crlf line 1\ncrlf line 2"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"
# The same normalization from the OTHER source, because one helper owns both.
kbc comment --task 505 --content "$(printf 'inline 1\r\ninline 2')"
eq "CRLF --content → the same LF body"           '"inline 1\ninline 2"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"
# A LONE \r is deliberately NOT normalized — it is not a line ending here, it is a cursor-return
# control character, and the reader's sanitizer is what owns it. Asserting it survives the write
# is what keeps the normalization narrow (a blanket \r→\n would silently rewrite content).
kbc comment --task 505 --content "$(printf 'lone\rcarriage')"
eq "a LONE \\r is left for the renderer's sanitizer, not rewritten here" \
   '"lone\rcarriage"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"

echo "-- comment: ID-OR-EXT resolves exactly as move/patch does --"
kbc comment --task EXT-9 --content x
eq "external-id ref → search first, then the POST" "1" "$(kb_stub_count_any '/tasks/search.json')"
eq "external-id ref → POSTs to the RESOLVED task id" "1" "$(kb_stub_count POST "$CPATH")"

echo "-- comment: the refusals, each with NO request at all --"
kbc comment --task 505 --content x --content-file "$TMP/c.txt"
eq "--content + --content-file → rc 2"           "2" "$rc"
eq "…names both flags"                           "true" "$(has 'mutually exclusive' "$err")"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
kbc comment --task 505
eq "neither --content nor --content-file → rc 2" "2" "$rc"
# `--content` is a SUBSTRING of `--content-file`, so a plain contains-test for it is satisfied by
# a diagnostic that names only the file flag — i.e. the half that says "you may pass text inline"
# could be dropped with this leg still green (watched, by rewording the refusal to name only
# --content-file). The match is therefore delimited: `--content` must appear NOT followed by a
# flag-name character, which `--content-file` cannot satisfy.
eq "…names both flags — and --content on its OWN, not just inside --content-file" "true" \
   "$(/usr/bin/grep -Eq -- '(^|[^[:alnum:]_-])--content([^[:alnum:]_-]|$)' <<<"$err" \
      && /usr/bin/grep -qF -- '--content-file' <<<"$err" && echo true || echo false)"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
kbc comment --task 505 --content ""
eq "--content \"\" → rc 2 (the empty-value class)" "2" "$rc"
eq "…names the flag"                             "true" "$(has '--content requires a non-empty value' "$err")"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
# THE ORDERING LEG, and the reason this one arm uses an EXTERNAL ref: `--task 505` is numeric,
# and resolve_task's numeric branch issues no request at all, so a "0 requests" assertion under
# a numeric ref holds no matter WHICH of the two resolutions runs first — it cannot see content
# resolution being moved after task resolution. An external ref makes task resolution cost a
# search, so 0 total requests here is the assertion that the offline refusal really did happen
# BEFORE any resolution (RED when the `text=` line is moved below the `task=` line: 1 request).
kbc comment --task EXT-9 --content-file "$TMP/nope.txt"
eq "--content-file missing → rc 2"               "2" "$rc"
eq "…names the path"                             "true" "$(has "$TMP/nope.txt" "$err")"
# The readability guard is asserted by its OWN wording, not merely by the rc: without it the
# `cat` failure arm below still refuses at rc 2 naming the same path (while leaking cat's raw
# stderr), so an rc-only assertion cannot tell the two apart and the guard could be deleted
# with the suite green. The two arms are both reachable — a directory is `-r` yet uncattable.
eq "…via the readability guard, not the cat fallback" "true" "$(has 'is not readable' "$err")"
eq "…and issues no request — NOT EVEN the external-ref lookup" "0" "$(kb_stub_total)"
: > "$TMP/empty.txt"
kbc comment --task 505 --content-file "$TMP/empty.txt"
eq "--content-file with no text → rc 2"          "2" "$rc"
eq "…says the file holds no comment text"        "true" "$(has 'holds no comment text' "$err")"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
# BLANK, not merely empty: the server trims before it validates, so a whitespace-only body is a
# 422 there — i.e. a POST that was always going to be refused, arriving as rc 1 (the wire's
# verdict) instead of the rc 2 every other bad-invocation takes. The local check therefore has
# to test the TRIMMED value; testing the raw one puts this on the wire. Both sources, because
# both resolve through the one helper.
printf ' \t\n \n' > "$TMP/blank.txt"
kbc comment --task 505 --content-file "$TMP/blank.txt"
eq "--content-file of only whitespace → rc 2"    "2" "$rc"
eq "…says the file holds no comment text"        "true" "$(has 'holds no comment text' "$err")"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
kbc comment --task 505 --content '   '
eq "--content of only whitespace → rc 2"         "2" "$rc"
eq "…says it holds no comment text"              "true" "$(has 'holds no comment text' "$err")"
eq "…and issues no request"                      "0" "$(kb_stub_total)"
# The other side of the trim: only the CHECK is trimmed. Content that merely BEGINS with
# whitespace is real content and must reach the wire with its indentation intact.
kbc comment --task 505 --content '  indented body'
eq "leading whitespace is content, not emptiness → rc 0" "0" "$rc"
eq "…and the body keeps it verbatim"             '"  indented body"' \
   "$(kb_stub_bodies POST "$CPATH" | jq -c '.content')"
kbc comment --content x
eq "comment without --task → rc 2"               "2" "$rc"
# The positive control that makes every "0 requests" above a MEASUREMENT rather than a harness
# that never writes: the same probe records a POST on the happy path.
kbc comment --task 505 --content x
eq "control: a valid comment DOES reach the POST" "1" "$(kb_stub_count POST "$CPATH")"

echo "-- comment: an HTTP failure carries the status AND the error body --"
KB_STUB_POST_HTTP=422 \
KB_STUB_POST_BODY='{"message":"The content field is required.","errors":{"content":["The content field is required."]}}' \
    kbc comment --task 505 --content x
eq "422 → rc 1"                                  "1" "$rc"
eq "422 → the status is named"                   "true" "$(has "HTTP 422 on POST $CPATH" "$err")"
eq "422 → the server's error body is echoed"     "true" "$(has 'The content field is required.' "$err")"
eq "422 → nothing on stdout (no id was created)" "" "$out"

echo "-- comment: success is decided on STATUS, never on a parseable body --"
# The 404 the un-suffixed path returns is well-formed JSON with no `.data` — a body-shape
# reader answers "parsed fine, no id" and exits 0. RED-when-reverted: swap the status check
# for a body test and both assertions below flip (rc 0, and stdout empty-but-successful).
KB_STUB_POST_HTTP=404 KB_STUB_POST_BODY="$NOT_FOUND_BODY" kbc comment --task 505 --content x
eq "404 with parseable JSON → rc 1 (status, not shape)" "1" "$rc"
eq "404 → the status is named"                   "true" "$(has 'HTTP 404' "$err")"
eq "404 → nothing on stdout"                     "" "$out"
# The other half of the same class, one layer in: a 2xx that carries no comment id leaves the
# write UNVERIFIED (the card's updated_at does not move), so it must fail loudly rather than
# print a plausible-looking `null`.
KB_STUB_POST_HTTP=201 KB_STUB_POST_BODY='{"data":{}}' kbc comment --task 505 --content x
eq "2xx with no comment id → rc 1"               "1" "$rc"
eq "…says the write is UNVERIFIED"               "true" "$(has 'UNVERIFIED' "$err")"
eq "…and never prints a bare null as an id"      "" "$out"
# Same state, one step earlier: a 2xx whose body is not JSON AT ALL (a proxy's HTML error page,
# a truncated read). kb_api has already said success on the status class, so this is still "the
# write is unconfirmed" — but the id extraction is where it lands, and an unguarded `jq` there
# dies on the parse under `set -e`, exiting the SCRIPT's rc 5 with jq's raw parse error as the
# only diagnostic. The refusal must be this verb's own, at its own documented rc.
KB_STUB_POST_HTTP=200 KB_STUB_POST_BODY='<html><body>502 Bad Gateway</body></html>' \
    kbc comment --task 505 --content x
eq "2xx with a NON-JSON body → rc 1, not jq's rc 5" "1" "$rc"
eq "…says the write is UNVERIFIED"               "true" "$(has 'UNVERIFIED' "$err")"
eq "…and leaks no raw jq parse error"            "false" "$(has 'parse error' "$err")"
eq "…and never prints anything as an id"         "" "$out"

echo "-- comments: the read side projects the task detail's own array --"
KB_STUB_GET_COMMENTS='[{"id":13,"task_id":505,"user_id":2238,"content":"first","deleted_at":null,"created_at":"2026-08-12T23:40:36+00:00","updated_at":"2026-08-12T23:40:36+00:00"},{"id":14,"task_id":505,"user_id":2238,"content":"second\nline","deleted_at":null,"created_at":"2026-08-12T23:41:12+00:00","updated_at":"2026-08-12T23:41:12+00:00"}]' \
    kbc comments --task 505
eq "comments → rc 0"                             "0" "$rc"
eq "comments → one block per comment"            "2" "$(/usr/bin/grep -c '^comment ' <<<"$out")"
eq "comments → the exact rendered output"        \
   "$(printf 'comment 13 · user 2238 · 2026-08-12T23:40:36+00:00\n  first\ncomment 14 · user 2238 · 2026-08-12T23:41:12+00:00\n  second\n  line')" \
   "$out"
# No new route: the read is the task detail GET, and nothing is sent to the comments path
# (which is POST-only — a GET there is 405, measured).
eq "comments → reads the task detail, not a comments route" "1" "$(kb_stub_count_any '/tasks/505.json')"
eq "comments → never GETs the comments path"     "0" "$(kb_stub_count_any "$CPATH")"

echo "-- comments: untrusted content cannot drive the terminal --"
# Comment content is written by anyone who can comment on the card and is printed RAW to a
# terminal. An embedded ESC is a terminal COMMAND, not a character: `ESC[2K ESC[1A` erases the
# `comment <id> · user <n>` header line above it, so the content can delete its own
# attribution. Every C0 control but the newline and the tab is therefore replaced before
# printing (the tab cannot move the cursor backward, so it cannot reach that header line).
# The ESC is built from its CODEPOINT — no raw control byte is typed into this file.
ESC="$(printf '\033')"
CTRL_COMMENTS="$(jq -nc --arg e "$ESC" \
    '[{id:21,task_id:505,user_id:7,content:("before" + $e + "[2K" + $e + "[1Aimpostor"),deleted_at:null,created_at:"t","updated_at":"t"}]')"
KB_STUB_GET_COMMENTS="$CTRL_COMMENTS" kbc comments --task 505
eq "control chars → rc 0 (rendered, not refused)" "0" "$rc"
eq "control chars → each replaced, text preserved" \
   "$(printf 'comment 21 · user 7 · t\n  before?[2K?[1Aimpostor')" "$out"
# The byte-level assertion. Its positive control is the line below it: the SAME grep over the
# same fixture's raw content finds the byte, so a 0 here is an absence rather than a grep that
# never matches.
eq "control chars → the raw ESC byte is ABSENT from stdout" "0" \
   "$(printf '%s' "$out" | /usr/bin/grep -c -e "$ESC" || true)"
eq "control: that grep DOES find the ESC in the unsanitized fixture" "1" \
   "$(printf '%s' "$CTRL_COMMENTS" | jq -r '.[0].content' | /usr/bin/grep -c -e "$ESC" || true)"
# The SAME byte-level assertion for a control character arriving in a HEADER field, end to end:
# id, user_id and created_at come from the same untrusted response body and land on the very
# line the content filter protects, so an unsanitized header is the same defect by the shorter
# route. The fixture puts the ESC in created_at and a forging newline in the id.
HDR_COMMENTS="$(jq -nc --arg e "$ESC" \
    '[{id:("22" + $e + "[2K"),task_id:505,user_id:7,content:"body",deleted_at:null,created_at:"t\ncomment 99 · user 1 · t","updated_at":"t"}]')"
KB_STUB_GET_COMMENTS="$HDR_COMMENTS" kbc comments --task 505
eq "header control chars → rc 0 (rendered, not refused)" "0" "$rc"
eq "header control chars → the raw ESC byte is ABSENT from stdout" "0" \
   "$(printf '%s' "$out" | /usr/bin/grep -c -e "$ESC" || true)"
eq "control: that grep DOES find the ESC in the unsanitized header fixture" "1" \
   "$(printf '%s' "$HDR_COMMENTS" | jq -r '.[0].id' | /usr/bin/grep -c -e "$ESC" || true)"
# One comment in, ONE header line out: the newline in created_at must not mint a second block.
eq "header newline → still exactly one comment block" "1" \
   "$(printf '%s' "$out" | /usr/bin/grep -c '^comment ')"
unset ESC CTRL_COMMENTS HDR_COMMENTS

echo "-- comments: an empty array SAYS so, at rc 0 --"
KB_STUB_GET_COMMENTS='[]' kbc comments --task 505
eq "no comments → rc 0"                          "0" "$rc"
eq "no comments → an explicit line, not silence" "kbcard: card 505 has no comments" "$out"

echo "-- comments: a 404 must NOT read as 'no comments' --"
# The sharpest form of the body-shape trap: `.data.comments // []` over the 404's parseable
# body yields [] — i.e. a body-shape reader reports "this card has no comments" at rc 0 for a
# request that never reached a card. RED-when-reverted: tolerate kb_api's non-zero rc and the
# rc assertion AND the no-comments assertion below both flip.
KB_STUB_GET_HTTP=404 KB_STUB_GET_COMMENTS='[]' kbc comments --task 505
eq "404 on the detail read → rc 1"               "1" "$rc"
eq "404 → the status is named"                   "true" "$(has 'HTTP 404' "$err")"
eq "404 → does NOT claim the card has no comments" "false" "$(has 'no comments' "$out")"
kbc comments
eq "comments without --task → rc 2"              "2" "$rc"
kbc comments --task 505 --bogus
eq "comments unknown arg → rc 2"                 "2" "$rc"

echo "-- comments / show: a 2xx whose body is not JSON at all --"
# The same state the comment POST already has a leg for, on the READ side: kb_api has said
# success on the status class, and the projection then meets a body that does not parse (a
# proxy's HTML error page, a truncated read). An unguarded jq there dies under `set -e` at the
# SCRIPT's rc 5 with jq's raw parse error as the only diagnostic. Both readers must refuse in
# kbcard's own words, at kbcard's own rc — and `comments` must NOT degrade to "no comments",
# which is the same silent-empty trap the 404 leg above pins.
NONJSON_BODY='<html><body>502 Bad Gateway</body></html>'
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY="$NONJSON_BODY" kbc comments --task 505
eq "comments: 2xx NON-JSON body → rc 1, not jq's rc 5" "1" "$rc"
eq "…refuses in kbcard's own words, naming the verb" "true" "$(has 'kbcard: comments' "$err")"
eq "…and leaks no raw jq parse error"            "false" "$(has 'parse error' "$err")"
eq "…and never claims the card has no comments"  "false" "$(has 'no comments' "$out")"
eq "…and prints nothing on stdout"               "" "$out"
# THE WORDING IS PART OF THE CONTRACT, because this arm has more than one way in. The empty
# value it fires on also arrives from a body that parsed PERFECTLY WELL and simply is not a card
# (a 200 `[]`: `[] | .data` is a jq error, suppressed to empty), and from a jq that is missing or
# unrunnable. A diagnostic saying "its body could not be parsed" is specific AND WRONG in those
# arms — it names a fault of the server for something that may be a fault of this box. So both
# readers state only the observation that is true in every arm: nothing could be read OUT of the
# body. RED when the message reverts to the parse-specific wording.
eq "…states what is true in EVERY arm: nothing could be read out of the body" "true" \
   "$(has 'no comment list could be read out of its body' "$err")"
eq "…and does NOT claim the body could not be parsed" "false" "$(has 'could not be parsed' "$err")"
# The other way into the same arm, exercised for real: valid JSON that is not a card.
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY='[]' kbc comments --task 505
eq "comments: 2xx of VALID JSON that is not a card → rc 1" "1" "$rc"
eq "…same true-in-every-arm wording"             "true" \
   "$(has 'no comment list could be read out of its body' "$err")"
eq "…and does NOT claim the body could not be parsed" "false" "$(has 'could not be parsed' "$err")"
eq "…and never claims the card has no comments"  "false" "$(has 'no comments' "$out")"
# `show` reads the SAME detail body through the same projection and had the same hole. Its
# positive control is the line below: on a well-formed body it still prints the card at rc 0,
# so the refusal above is the non-JSON case and not `show` being broken outright.
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY="$NONJSON_BODY" kbc show --task 505
eq "show: 2xx NON-JSON body → rc 1, not jq's rc 5" "1" "$rc"
eq "…refuses in kbcard's own words, naming the verb" "true" "$(has 'kbcard: show' "$err")"
eq "…and leaks no raw jq parse error"            "false" "$(has 'parse error' "$err")"
eq "…and prints nothing on stdout"               "" "$out"
eq "…states what is true in EVERY arm: no card could be read out of the body" "true" \
   "$(has 'no card could be read out of its body' "$err")"
eq "…and does NOT claim the body could not be parsed" "false" "$(has 'could not be parsed' "$err")"
# `show`'s own parseable-but-not-a-card way in, and its EMPTY-body one — which was a SILENT rc 0
# (no output, no diagnostic) before this verb family landed, i.e. the second exit-code change a
# vendoring consumer has to know about, not just the jq-rc-5 one.
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY='[]' kbc show --task 505
eq "show: 2xx of VALID JSON that is not a card → rc 1" "1" "$rc"
eq "…same true-in-every-arm wording"             "true" \
   "$(has 'no card could be read out of its body' "$err")"
eq "…and prints nothing on stdout"               "" "$out"
# A single space, not the empty string: KB_STUB_GET_BODY is dispatched on `-n`, so an empty
# value selects the envelope branch instead — and a body of whitespace is the same input to
# every reader downstream (jq yields no value from it either way).
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY=' ' kbc show --task 505
eq "show: an EMPTY 2xx body → rc 1, never a silent success" "1" "$rc"
eq "…and says so rather than exiting 0 with no output" "true" \
   "$(has 'no card could be read out of its body' "$err")"
kbc show --task 505
eq "control: show on a well-formed body → rc 0"  "0" "$rc"
eq "control: …and returns the card"              "505" "$(jq -r '.id' <<<"$out")"
unset NONJSON_BODY

unset -f kb_stub_route
unset NOT_FOUND_BODY KB_STUB_CREATED

# ---------------------------------------------------------------------------
echo "== every projection refuses a 2xx it cannot read, in kbcard's words =="
# THE CLASS (card#6426). kb_api decides success on the HTTP STATUS CLASS alone, so a 2xx
# carrying a proxy's HTML error page or a truncated read arrives at EVERY projection in this
# file as a success. An unguarded jq there exits 5 under `set -e`, with jq's raw parse error as
# the caller's whole diagnostic — a status this tool documents nowhere, from a program the
# caller never ran. card#6051 closed three of those sites; this block is the rest of the
# population, one leg per verb, each asserting the same four things: the verb's OWN documented
# rc (never jq's 5), a refusal in kbcard's words naming the verb, no raw jq parse error on
# stderr, and nothing on stdout that could be mistaken for a value. Every leg is paired with a
# control on the SAME route with a well-formed body, so a green here is a refusal that
# discriminates and not a verb that is broken outright.
rm -rf "$TMP"
_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48' 'export KB_STAGE_IN_PROGRESS=49'
kb_stub_install

NONJSON='<html><body>502 Bad Gateway</body></html>'
SEARCH_BODY='{"data":[{"id":505}]}'
CARD_BODY='{"data":{"id":505,"name":"probe","workflow_stage_id":48,"board_id":42,"tags":["keep-me"]}}'
LINK_BODY='{"data":{"id":9,"relation_type":"blocks"}}'
FIELDS_BODY='{"data":[{"id":7,"key":"stage","label":"Stage","type":"enum","options":[{"value":"a","label":"a"}]}]}'
# The custom-field WRITE echoes ONE field object, not the board's array — two distinct shapes
# behind two distinct routes, so the read arm's fixture cannot stand in for the write arm's.
FIELD_ROW_BODY='{"data":{"id":7,"key":"stage","label":"Stage","type":"enum","options":[{"value":"a","label":"a"},{"value":"b","label":"b"}]}}'
export NONJSON SEARCH_BODY CARD_BODY LINK_BODY FIELDS_BODY FIELD_ROW_BODY
# One knob per ROUTE, so exactly one leg is failed at a time and every other request in the
# same run still answers normally — a run that fails every route cannot tell which projection
# refused.
kb_stub_route() {
    local method="$1" url="$2"
    case "$method $url" in
        "GET "*/tasks/search.json*)  printf '%s\n%s' "${KB_STUB_SEARCH_HTTP:-200}" \
                                        "${KB_STUB_SEARCH_BODY:-$SEARCH_BODY}" ;;
        "POST "*/tasks.json)         printf '%s\n%s' "${KB_STUB_POST_HTTP:-201}" "${KB_STUB_POST_BODY:-$CARD_BODY}" ;;
        "POST "*/task_links.json)    printf '%s\n%s' "${KB_STUB_LINK_HTTP:-201}" "${KB_STUB_LINK_BODY:-$LINK_BODY}" ;;
        "PATCH "*/tasks/*.json)      printf '%s\n%s' "${KB_STUB_PATCH_HTTP:-200}" "${KB_STUB_PATCH_BODY:-$CARD_BODY}" ;;
        "GET "*/tasks/*.json)        printf '%s\n%s' "${KB_STUB_GET_HTTP:-200}" "${KB_STUB_GET_BODY:-$CARD_BODY}" ;;
        "GET "*/custom_fields.json)  printf '%s\n%s' "${KB_STUB_CF_HTTP:-200}" "${KB_STUB_CF_BODY:-$FIELDS_BODY}" ;;
        "PATCH "*/custom_fields/*)   printf '%s\n%s' "${KB_STUB_CFW_HTTP:-200}" "${KB_STUB_CFW_BODY:-$FIELD_ROW_BODY}" ;;
    esac
}
export -f kb_stub_route

# nonjson_leg <label> <expected-rc> <verb-word> <args…> — the four assertions this class needs,
# stated once. `parse error` is jq's own wording; `jq:` catches its prefix if the text changes.
nonjson_leg() {
    local label="$1" want_rc="$2" verb="$3"; shift 3
    kbc "$@"
    eq "$label → rc $want_rc, not jq's rc 5"        "$want_rc" "$rc"
    eq "$label → refuses in kbcard's words"         "true"     "$(has "kbcard: $verb" "$err")"
    eq "$label → leaks no raw jq parse error"       "false"    "$(has 'parse error' "$err")"
    eq "$label → prints nothing on stdout"          ""         "$out"
}

echo "-- the usage block renders as prose, not as comment markup --"
# A bare `#` is how this header separates paragraphs (a trailing space would not survive an
# editor or a linter), and a strip that requires the space left every separator in the rendered
# help as a literal `#` line. Asserted on the ABSENCE of such a line, with the control below:
# the same run must actually produce the block, or an absence proves nothing.
kbc
eq "no arguments → the usage block at rc 0" "0" "$rc"
eq "control: …and it IS the usage block"    "true" "$(has 'Usage:' "$out")"
eq "no line of the rendered help is a bare comment marker" "0" \
   "$(/usr/bin/grep -c '^#' <<<"$out" || true)"

echo "-- create-card / move / patch: a write whose echo is unreadable --"
KB_STUB_POST_BODY="$NONJSON" nonjson_leg "create-card" 1 "create-card" \
    create-card --type fr --name probe
kbc create-card --type fr --name probe
eq "control: create-card on a well-formed echo → rc 0" "0" "$rc"
eq "control: …and prints the created card"       "505" "$(jq -r '.id' <<<"$out")"

KB_STUB_PATCH_BODY="$NONJSON" nonjson_leg "move" 1 "move" move --task 505 --column in_progress
kbc move --task 505 --column in_progress
eq "control: move on a well-formed echo → rc 0"  "0" "$rc"
eq "control: …and prints the moved card"         "505" "$(jq -r '.id' <<<"$out")"

KB_STUB_PATCH_BODY="$NONJSON" nonjson_leg "patch" 1 "patch" patch --task 505 --pr 12
kbc patch --task 505 --pr 12
eq "control: patch on a well-formed echo → rc 0" "0" "$rc"
eq "control: …and prints the patched card"       "505" "$(jq -r '.id' <<<"$out")"

echo "-- patch --triaged: an unreadable TAG READ must never write a tag list --"
# The sharpest instance in the file. `tags` is replaced WHOLESALE by the API, so this verb
# read-merge-writes it: a read that yields nothing and is then treated as "no tags" writes
# ["triaged"] and DESTROYS every tag the card carried. The refusal is therefore about the
# WRITE, and the load-bearing assertion is the absence of the PATCH — asserted against the
# request log, which nothing under test can truncate.
KB_STUB_GET_BODY="$NONJSON" nonjson_leg "patch --triaged (tag read)" 2 "patch" patch --task 505 --triaged
KB_STUB_GET_BODY="$NONJSON" kbc patch --task 505 --triaged
eq "…and issues NO PATCH at all (a tag wipe is worse than a refusal)" "0" "$(kb_stub_count PATCH '/tasks/505.json')"
kbc patch --task 505 --triaged
eq "control: the same patch on a readable card DOES write" "1" "$(kb_stub_count PATCH '/tasks/505.json')"
eq "control: …and the write keeps the card's existing tags" '["keep-me","triaged"]' \
   "$(kb_stub_bodies PATCH '/tasks/505.json' | jq -c '.tags')"

echo "-- patch --triaged: a 2xx that PARSES but carries no card is the same refusal --"
# The half of the tag-wipe class a tolerant parse alone does NOT close. `.data.tags // []`
# only yields empty when jq FAULTS; on a body that parses perfectly well and simply has no
# `.data` object, `//` supplies the string `[]` — non-empty, so the `[[ -n … ]]` arm passes and
# the PATCH goes out carrying only what THIS call adds. `tags` is replaced WHOLESALE, so that
# is the tag wipe the refusal exists to prevent, reached through the guard rather than around
# it. Measured on the pre-fix bin: `{"ok":true}` → rc 0, 2 requests, PATCH body `{"tags":
# ["triaged"]}`. Closed by a shape test on the READ that feeds this destructive write — the
# write path only; a read verb's acceptance is not changed by it.
#
# Each leg carries its OWN well-formed control on the same route, so a green is a refusal that
# discriminates rather than a verb that stopped writing.
shape_leg() {
    local label="$1" body="$2"
    KB_STUB_GET_BODY="$body" nonjson_leg "$label" 2 "patch" patch --task 505 --triaged
    eq "$label → the tag-read refusal, in kbcard's words" "true" \
       "$(has 'refusing to replace this card' "$err")"
    eq "$label → issues NO PATCH at all"  "0" "$(kb_stub_count PATCH '/tasks/505.json')"
    kbc patch --task 505 --triaged
    eq "$label control: a well-formed card on the same route DOES write" "1" \
       "$(kb_stub_count PATCH '/tasks/505.json')"
    eq "$label control: …keeping the tags it already had" '["keep-me","triaged"]' \
       "$(kb_stub_bodies PATCH '/tasks/505.json' | jq -c '.tags')"
}
# No `.data` key at all — a 2xx from something that is not this API, or a truncated envelope.
shape_leg "patch --triaged (2xx with no .data key)" '{"ok":true,"note":"a 2xx with no data key"}'
# `.data` present and JSON null — the trashed / permission-limited card shape.
shape_leg "patch --triaged (.data is null)"         '{"data":null}'
# `.data` a scalar. Already refused pre-fix (jq faults indexing a string, and the fault lands in
# the same empty arm), so this leg is a REGRESSION GUARD, not evidence of the defect: it pins
# that the shape test does not move a case the tolerant parse already covered.
shape_leg "patch --triaged (.data is a string)"     '{"data":"str"}'
unset -f shape_leg

echo "-- patch --triaged: a .data object whose tags is not a LIST is the same refusal --"
# The `.data`-object test above is a test on the WRAPPER, and the value that actually gets
# re-sent is `.data.tags`. A `.data` object carrying a non-array `tags` passes the wrapper test
# and then faults one line later inside the merge (`jq: error … string ("abc") and array
# (["triaged"]) cannot be added`) — already rc 2 with no PATCH, so no tag is destroyed, but the
# caller's whole diagnostic is jq's, with no `kbcard:` line at all. Same harm class, same
# refusal, same rc: CONTAINER type only. What `tags` CONTAINS is deliberately not tested here —
# `{"data":{"tags":[1,2]}}` still patches `[1,2,"triaged"]`, which is a change to what this verb
# ACCEPTS and is filed as its own ask-gated question.
tags_leg() {
    local label="$1" body="$2"
    kb_stub_reset
    KB_STUB_GET_BODY="$body" kbc patch --task 505 --triaged
    eq "$label → rc 2, this verb's own refusal rc"  "2"    "$rc"
    eq "$label → the tag-read refusal, in kbcard's words" "true" \
       "$(has 'refusing to replace this card' "$err")"
    eq "$label → leaks no raw jq diagnostic"        "false" "$(has 'jq: ' "$err")"
    eq "$label → prints nothing on stdout"          ""     "$out"
    eq "$label → issues NO PATCH at all"            "0"    "$(kb_stub_count PATCH '/tasks/505.json')"
}
tags_leg "patch --triaged (.data.tags is a string)" '{"data":{"id":505,"tags":"abc"}}'
tags_leg "patch --triaged (.data.tags is an object)" '{"data":{"id":505,"tags":{"a":1}}}'
tags_leg "patch --triaged (.data.tags is a number)" '{"data":{"id":505,"tags":5}}'
unset -f tags_leg

echo "-- patch --type: a tags OBJECT was a silent TAG WIPE, not just a bad diagnostic --"
# The sharpest leg in this block, and the reason the container test is not cosmetic. `--type`'s
# merge opens with `map(…)`, and jq's `map` over an OBJECT iterates its VALUES — so a `tags`
# object whose values are all strings does not fault at all: it degrades into a plausible list,
# the merge succeeds, and the PATCH replaces the card's real tags with that object's values.
# MEASURED on the bin before the container test: `{"tags":{"0":"keep-me"}}` + `--type fr` wrote
# `{"tags":["keep-me","type:fr"]}` at rc 0 — a card carrying other tags loses every one of them.
# `--triaged` alone never reached this (object + array faults); it takes a `map`-first flag.
wipe_leg() {
    local label="$1" body="$2"; shift 2
    kb_stub_reset
    KB_STUB_GET_BODY="$body" kbc patch --task 505 "$@"
    eq "$label → rc 2, this verb's own refusal rc" "2"    "$rc"
    eq "$label → issues NO PATCH (no tag wipe)"    "0"    "$(kb_stub_count PATCH '/tasks/505.json')"
    eq "$label → the tag-read refusal, in kbcard's words" "true" \
       "$(has 'refusing to replace this card' "$err")"
}
wipe_leg "patch --type (tags object of strings)"  '{"data":{"id":505,"tags":{"0":"keep-me"}}}' --type fr
wipe_leg "patch --type (tags empty object)"       '{"data":{"id":505,"tags":{}}}'              --type fr
wipe_leg "patch --type --triaged (tags object)"   '{"data":{"id":505,"tags":{"a":"x"}}}'       --type fr --triaged
# `tags:false` — the shape the container test could not see, because `//` was ABOVE it. jq's
# `//` treats `false` exactly as it treats `null`, so `.data.tags // []` substituted `[]` and
# `select(type == "array")` was then handed the DEFAULT rather than the value it was written to
# police. MEASURED on the bin before this leg landed: `{"data":{"id":505,"tags":false}}` +
# `--triaged` → rc 0, PATCH body `{"tags":["triaged"]}` — every real tag on the card gone, with
# no diagnostic anywhere. `--type` reaches it identically. The fix moves the shape test to the
# near side of the default; these legs red on any bin that reinstates the old ordering.
wipe_leg "patch --triaged (tags is false)"        '{"data":{"id":505,"tags":false}}'           --triaged
wipe_leg "patch --type (tags is false)"           '{"data":{"id":505,"tags":false}}'           --type fr
unset -f wipe_leg

# THE ACCEPTED SET IS UNCHANGED — asserted, not assumed. These three bodies wrote before the
# container test and must still write: a card whose `tags` key is absent, one whose `tags` is a
# server-sent JSON null (both reach `// []`), and one whose list is genuinely empty. Without
# these the container test could tighten acceptance and every leg above would still be green.
tags_accept_leg() {
    local label="$1" body="$2" want="$3"
    kb_stub_reset
    KB_STUB_GET_BODY="$body" kbc patch --task 505 --triaged
    eq "$label → still writes at rc 0"     "0"     "$rc"
    eq "$label → issues exactly one PATCH" "1"     "$(kb_stub_count PATCH '/tasks/505.json')"
    eq "$label → with the merged tag list" "$want" "$(kb_stub_bodies PATCH '/tasks/505.json' | jq -c '.tags')"
}
tags_accept_leg "patch --triaged (no tags key)"      '{"data":{"id":505}}'              '["triaged"]'
tags_accept_leg "patch --triaged (tags is null)"     '{"data":{"id":505,"tags":null}}'  '["triaged"]'
tags_accept_leg "patch --triaged (tags is [])"       '{"data":{"id":505,"tags":[]}}'    '["triaged"]'
tags_accept_leg "patch --triaged (tags is a list)"   '{"data":{"id":505,"tags":["a"]}}' '["a","triaged"]'
unset -f tags_accept_leg

# `--tags` BYPASSES the read entirely, so the narrowing above must not reach it — asserted
# against the sharpest input there is: the same `tags:false` body that now refuses on the read
# path. A caller supplying the list explicitly never consults the card, so this writes.
kb_stub_reset
KB_STUB_GET_BODY='{"data":{"id":505,"tags":false}}' kbc patch --task 505 --tags a,b
eq "patch --tags over a tags:false card → still writes at rc 0" "0" "$rc"
eq "…issues exactly one PATCH"        "1"           "$(kb_stub_count PATCH '/tasks/505.json')"
eq "…with the caller's own list"      '["a","b"]'   "$(kb_stub_bodies PATCH '/tasks/505.json' | jq -c '.tags')"
eq "…and never GETs the card at all"  "0"           "$(kb_stub_count GET '/tasks/505.json')"

echo "-- link: the relation echo --"
KB_STUB_LINK_BODY="$NONJSON" nonjson_leg "link" 1 "link" link --from 505 --to 506 --relation blocks
kbc link --from 505 --to 506 --relation blocks
eq "control: link on a well-formed echo → rc 0"  "0" "$rc"
eq "control: …and prints the created link"       "9" "$(jq -r '.id' <<<"$out")"

echo "-- the external-id resolver: 'no task found' is a claim about the BOARD --"
# An unreadable body is not an absent card. Routing it into the not-found arm would answer a
# question this read never reached — the same silent-empty trap `comments`' no-comments line
# sets. RED-when-reverted: fold the unreadable case into the not-found arm and the wording
# assertion below flips while the rc stays 1.
KB_STUB_SEARCH_BODY="$NONJSON" nonjson_leg "external-id lookup" 1 "external-id lookup" show --task EXT-9
KB_STUB_SEARCH_BODY="$NONJSON" kbc show --task EXT-9
eq "…and does NOT claim there is no such card"   "false" "$(has 'no task found' "$err")"
eq "…states only what is true: nothing could be read out of the body" "true" \
   "$(has 'could be read out of its body' "$err")"
# The genuine not-found answer still reads as not-found: a well-formed search result with no
# rows is the control that keeps the refusal above narrow.
KB_STUB_SEARCH_BODY='{"data":[]}' kbc show --task EXT-9
eq "control: a well-formed EMPTY result → the not-found arm" "1" "$rc"
eq "control: …and says so"                       "true" "$(has 'no task found' "$err")"
# A `.data` that is present and non-empty but NOT a list. The guard above is `[[ -n "$rows" ]]`,
# which a JSON object satisfies, so the row projection right after it used to run unguarded and
# print jq's own "Cannot index object with number" before the verb's message. THIS LEG ASSERTS
# ONLY THE PART THAT IS FIXED — no raw jq text on stderr. The verb's rc and its wording are
# DELIBERATELY unchanged and asserted as such: refusing here would change what a READ verb
# accepts, which is a separate, filed decision and not this change's to make.
KB_STUB_SEARCH_BODY='{"data":{"id":9}}' kbc show --task EXT-9
eq "a non-list .data → leaks no raw jq error"    "false" "$(has 'jq:' "$err")"
eq "…rc is UNCHANGED at 1"                       "1"     "$rc"
eq "…and so is the (residual, filed) wording"    "true"  "$(has 'no task found' "$err")"

echo "-- field list / field set-options --"
KB_STUB_CF_BODY="$NONJSON" nonjson_leg "field list" 1 "field" field list
kbc field list
eq "control: field list on a well-formed body → rc 0" "0" "$rc"
eq "control: …and projects the field"            "stage" "$(jq -r '.[0].key' <<<"$out")"
KB_STUB_CF_BODY="$NONJSON" nonjson_leg "field set-options (read)" 1 "field" \
    field set-options --field stage --options a,b
# _kbc_fetch_fields owns this refusal for BOTH sub-verbs, so set-options adding one of its own
# on top prints a second line that names no cause the first did not. `field list` above is the
# shape to match: one message, rc 1. Counted, not substring-matched — a second line is exactly
# what a `has` assertion cannot see.
KB_STUB_CF_BODY="$NONJSON" kbc field set-options --field stage --options a,b
eq "field set-options (read) → ONE kbcard line, as field list emits" "1" \
   "$(/usr/bin/grep -c '^kbcard: ' <<<"$err" || true)"
KB_STUB_CF_BODY="$NONJSON" kbc field list
eq "control: field list emits that same single line"                 "1" \
   "$(/usr/bin/grep -c '^kbcard: ' <<<"$err" || true)"
# The WRITE echo: the reconcile PATCH already landed (2xx), so this refusal is about the echo,
# not the write — and it must still not print jq's rc 5.
KB_STUB_CFW_BODY="$NONJSON" nonjson_leg "field set-options (write echo)" 1 "field" \
    field set-options --field stage --options a,b
kbc field set-options --field stage --options a,b
eq "control: set-options on a well-formed echo → rc 0" "0" "$rc"
eq "control: …and projects the reconciled option set" '["a","b"]' \
   "$(jq -c '[.options[].value]' <<<"$out")"

echo "-- archive: the safety gate must fail CLOSED, and quietly --"
# The gate already refuses on an unreadable card (its `||` arm catches jq's death), so the rc
# and the absent PATCH are green either way — what is NOT green is the raw jq parse error the
# unguarded jq prints to stderr on its way there. That is the assertion this leg adds.
KB_STUB_GET_BODY="$NONJSON" kbc archive --task 505
eq "archive on an unreadable card → rc 1"        "1" "$rc"
eq "…refuses in kbcard's words"                  "true" "$(has 'archive withheld' "$err")"
eq "…leaks no raw jq parse error"                "false" "$(has 'parse error' "$err")"
eq "…and issues NO archive PATCH"                "0" "$(kb_stub_count PATCH '/tasks/505.json')"

echo "-- comments: a .data.comments that is not an ARRAY --"
# card#6426 (c), instance 1. `.data.comments // []` passes a non-array straight through to the
# renderer, whose `.[]` then dies with jq's "Cannot iterate over …" at rc 5 — mid-render, after
# the header work is done. It is not an empty comment list either, so it belongs in the verb's
# existing "nothing was read" arm, not in the no-comments line.
KB_STUB_GET_BODY='{"data":{"id":505,"comments":{"1":{"content":"x"}}}}' \
    nonjson_leg "comments with an object where the array goes" 1 "comments" comments --task 505
KB_STUB_GET_BODY='{"data":{"id":505,"comments":"nope"}}' \
    nonjson_leg "comments with a string where the array goes" 1 "comments" comments --task 505
KB_STUB_GET_BODY='{"data":{"id":505,"comments":{"1":{"content":"x"}}}}' kbc comments --task 505
eq "…and never claims the card has no comments"  "false" "$(has 'no comments' "$out")"

echo "-- comments: a row whose content is not a STRING --"
# card#6426 (c), instance 2. `explode` on a number is a jq error, so a single bad row exits 5
# PART WAY THROUGH the output — the caller gets some comments, no diagnostic it can attribute,
# and an rc from a program it never ran. Refuse the read instead: a partial audit trail that
# looks complete is the worst of the three outcomes.
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[{"id":1,"user_id":2,"created_at":"t","content":7}]}}' \
    nonjson_leg "comments with a numeric content" 1 "comments" comments --task 505
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[{"id":1,"user_id":2,"created_at":"t","content":{"a":1}}]}}' \
    nonjson_leg "comments with an object content" 1 "comments" comments --task 505
# A row that is not an object at all dies the same way one line earlier, on the header.
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[7]}}' \
    nonjson_leg "comments with a row that is not an object" 1 "comments" comments --task 505
# The controls that keep all of the above narrow: content ABSENT and content NULL are ordinary
# rows the renderer has always printed as empty, and must keep printing.
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[{"id":1,"user_id":2,"created_at":"t"}]}}' \
    kbc comments --task 505
eq "control: a row with NO content still renders" "0" "$rc"
# Header only: jq's `split` over the empty string yields NO elements, so an absent content
# emits no indented line at all. Pinned as the measured shape rather than assumed.
eq "control: …as a header with no content line"  "comment 1 · user 2 · t" "$out"
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[{"id":1,"user_id":2,"created_at":"t","content":null}]}}' \
    kbc comments --task 505
eq "control: a row with NULL content still renders" "0" "$rc"
KB_STUB_GET_BODY='{"data":{"id":505,"comments":[{"id":1,"user_id":2,"created_at":"t","content":"hi"}]}}' \
    kbc comments --task 505
eq "control: an ordinary row is unaffected"      "0" "$rc"
eq "control: …and renders verbatim"              "$(printf 'comment 1 · user 2 · t\n  hi')" "$out"

unset -f kb_stub_route nonjson_leg
unset NONJSON SEARCH_BODY CARD_BODY LINK_BODY FIELDS_BODY FIELD_ROW_BODY

# ---------------------------------------------------------------------------
echo "== --name-file / --description-file — text that never meets a shell (card#6648) =="
# THE DEFECT THESE CLOSE. `--description "$TEXT"` forces externally-authored text through the
# CALLER's shell, which expands it before kbcard is started: a `$(…)` or a backtick sitting in a
# report someone else wrote RUNS as a command on this box, and argv already holds its output by
# the time any code here could look at it. No in-tool validator can see the unsafe case — the
# expansion happened in another process — so the fix is a source that never passes through a
# shell at all. That is why the load-bearing assertion below is on the REQUEST BODY and not on an
# exit code: what is being proven is that the bytes in the file are the bytes on the wire.
#
# BOTH NEW PAIRS RESOLVE THROUGH THE SAME `_kbc_text_arg` the shipped `comment` verb now uses, so
# the comment block above is ALSO this consolidation's regression suite: it runs unchanged against
# the hoisted resolver, and any drift in the mutual-exclusion, readability, CRLF, trailing-newline
# or blank-text semantics reds there before it reds here.
#
# WHAT IS DELIBERATELY NOT ASSERTED, because it is deliberately not built: the new flags do NOT
# require an absolute path, and neither does `--content-file`. What makes the file form safe is
# that the text never passes through a shell, which a relative path delivers exactly as well;
# absolute-required is ergonomics, and retrofitting it onto the shipped flag would change what an
# existing caller may pass. Nor is there a `$(`-sniffing check on the inline flags — see above.
rm -rf "$TMP"
_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48'
kb_stub_install

TA_CARD='{"data":{"id":505,"name":"probe","workflow_stage_id":48,"board_id":42,"tags":[]}}'
export TA_CARD
kb_stub_route() {
    local method="$1" url="$2"
    case "$method $url" in
        "POST "*/tasks.json)        printf '201\n%s' "$TA_CARD" ;;
        "GET "*/tasks/search.json*) printf '200\n{"data":[{"id":505}]}' ;;
        "PATCH "*/tasks/*.json)     printf '200\n%s' "$TA_CARD" ;;
        "GET "*/tasks/*.json)       printf '200\n%s' "$TA_CARD" ;;
    esac
}
export -f kb_stub_route

# The injection fixture. SINGLE-quoted, so the only shell that could ever expand it is the one
# under test — and the assertion is that none does. `$(id -u)` is the shape that made this a
# security question rather than an ergonomics one; the backtick and `${…}` forms ride along
# because they are the same hole with different syntax.
TA_INJ='pre-$(id -u)-post `date` ${HOME} $((6*7))'
TA_INJ_JSON="$(jq -cn --arg s "$TA_INJ" '$s')"
printf '%s\n' "$TA_INJ" > "$TMP/inj.txt"
printf 'plain text\n'   > "$TMP/plain.txt"
printf 'trail\n\n\n'    > "$TMP/trail.txt"
printf 'c1\r\nc2\r\n'   > "$TMP/crlf.txt"
printf ' \t\n \n'       > "$TMP/blank.txt"
: >                       "$TMP/empty.txt"
mkdir -p "$TMP/adir"

# ta <verb> <field> <args…> — drive create-card or patch with the arguments that verb REQUIRES
# plus the text flags under test, on a fresh request log, recording where that verb's write lands.
# The (method, path) pair is the only thing that differs between the two verbs' assertions; the
# `name` column must not supply `--name` itself, since that flag is what is under test there.
ta() {
    local verb="$1" field="$2"; shift 2
    case "$verb" in
        create-card)
            TA_METHOD=POST; TA_PATH='/tasks.json'
            if [[ "$field" == name ]]; then kbc create-card --type fr "$@"
            else kbc create-card --type fr --name probe "$@"; fi ;;
        patch)
            TA_METHOD=PATCH; TA_PATH='/tasks/505.json'
            kbc patch --task 505 "$@" ;;
    esac
}
# ta_wire <field> — the value the last `ta` run's write put on the wire, as JSON.
ta_wire() { kb_stub_bodies "$TA_METHOD" "$TA_PATH" | jq -c ".$1"; }

for _verb in create-card patch; do
  for _field in name description; do
    _f="--$_field"; _ff="--$_field-file"
    _L="$_verb $_ff"

    # THE CARD'S WHOLE POINT, asserted on the wire and not on an rc.
    ta "$_verb" "$_field" "$_ff" "$TMP/inj.txt"
    eq "$_L: rc 0"                                    "0" "$rc"
    eq "$_L: the file's text is BYTE-EXACT on the wire" "$TA_INJ_JSON" "$(ta_wire "$_field")"
    # The independent witness that the equality above is measuring what it claims: the command
    # substitution is present AS TEXT. An expansion anywhere on the path would have consumed it,
    # so this cannot pass on a body that was expanded — and it needs no knowledge of what the
    # expansion would have produced on this particular box.
    eq "$_L: …the command substitution rides as TEXT, unexpanded" "true" \
       "$(has '$(id -u)' "$(ta_wire "$_field")")"
    eq "$_L: …in exactly one write"                   "1" "$(kb_stub_count "$TA_METHOD" "$TA_PATH")"
    eq "$_L: …and no other request at all"            "1" "$(kb_stub_total)"

    # The refusals. Every one is decided offline, so each carries its own "no traffic" assertion;
    # the write above is the positive control that makes those zeros a measurement.
    ta "$_verb" "$_field" "$_f" inline "$_ff" "$TMP/plain.txt"
    eq "$_L + $_f → rc 2"                             "2" "$rc"
    eq "$_L + $_f → names them mutually exclusive"    "true" "$(has 'mutually exclusive' "$err")"
    eq "$_L + $_f → issues no request"                "0" "$(kb_stub_total)"

    ta "$_verb" "$_field" "$_ff" "$TMP/nope.txt"
    eq "$_L missing → rc 2"                           "2" "$rc"
    eq "$_L missing → via the readability guard"      "true" "$(has 'is not readable' "$err")"
    eq "$_L missing → names the path"                 "true" "$(has "$TMP/nope.txt" "$err")"
    eq "$_L missing → issues no request"              "0" "$(kb_stub_total)"

    # UNREADABLE-BUT-PRESENT, exercising the `cat` fallback the readability guard cannot catch: a
    # directory is `-r` yet uncattable. Deliberately NOT a chmod-000 file — CI may run as root,
    # where `-r` is true regardless, and a check that cannot fail on the runner is a decoration.
    ta "$_verb" "$_field" "$_ff" "$TMP/adir"
    eq "$_L unreadable → rc 2"                        "2" "$rc"
    eq "$_L unreadable → via the cat fallback"        "true" "$(has 'could not be read' "$err")"
    eq "$_L unreadable → issues no request"           "0" "$(kb_stub_total)"

    # `-` is refused BY NAME rather than falling into "not readable": `-` is not a stdin token
    # here. The assertion is on the TOKEN claim, deliberately not on "never reads stdin" — that
    # would be a false absolute, since `--…-file /dev/stdin` is a readable path and does work.
    # here, and the old message named the wrong problem. Acceptance is unchanged — `-` never
    # worked — so this is the diagnostic, asserted by its own wording.
    ta "$_verb" "$_field" "$_ff" -
    eq "$_L - → rc 2"                                 "2" "$rc"
    eq "$_L - → names the token, not a stdin ban"     "true" "$(has "'-' is not a stdin token" "$err")"
    eq "$_L - → issues no request"                    "0" "$(kb_stub_total)"

    ta "$_verb" "$_field" "$_ff" "$TMP/blank.txt"
    eq "$_L whitespace-only → rc 2"                   "2" "$rc"
    eq "$_L whitespace-only → names the field's text" "true" "$(has "holds no $_field text" "$err")"
    eq "$_L whitespace-only → issues no request"      "0" "$(kb_stub_total)"

    ta "$_verb" "$_field" "$_ff" "$TMP/empty.txt"
    eq "$_L empty file → rc 2"                        "2" "$rc"
    eq "$_L empty file → names the field's text"      "true" "$(has "holds no $_field text" "$err")"
    eq "$_L empty file → issues no request"           "0" "$(kb_stub_total)"

    ta "$_verb" "$_field" "$_ff" ""
    eq "$_L \"\" → rc 2 (the empty-value class)"      "2" "$rc"
    eq "$_L \"\" → names the flag"                    "true" \
       "$(has "$_ff requires a non-empty value" "$err")"

    # The two normalizations, inherited verbatim from the comment resolver.
    ta "$_verb" "$_field" "$_ff" "$TMP/trail.txt"
    eq "$_L → ALL trailing newlines are trimmed"      '"trail"' "$(ta_wire "$_field")"
    ta "$_verb" "$_field" "$_ff" "$TMP/crlf.txt"
    eq "$_L → CRLF is normalized to LF, no \\r on the wire" '"c1\nc2"' "$(ta_wire "$_field")"

    # THE INLINE FLAG'S SHIPPED BEHAVIOUR IS UNCHANGED — the control that keeps this an ADDITION.
    # `--description`/`--name` predate their file twins, so their value still rides verbatim: not
    # blank-checked (a whitespace value has always been accepted and written) and not rewritten
    # (a CRLF one still reaches the wire as typed). Narrowing either is an acceptance change, and
    # these two legs red on a later "harmonization" that makes one silently.
    ta "$_verb" "$_field" "$_f" '   '
    eq "$_verb $_f whitespace → still rc 0, as it always has" "0" "$rc"
    eq "$_verb $_f whitespace → …and reaches the wire verbatim" '"   "' "$(ta_wire "$_field")"
    ta "$_verb" "$_field" "$_f" "$(printf 'i1\r\ni2')"
    eq "$_verb $_f CRLF → reaches the wire verbatim, unnormalized" '"i1\r\ni2"' \
       "$(ta_wire "$_field")"
  done
done
unset _verb _field _f _ff _L

# NEITHER SOURCE GIVEN is the ordinary case for an optional setter and must stay silent — the
# half of the requiredness parameter that `comment` (where neither is rc 2) cannot exercise.
ta create-card description
eq "create-card with no description flag → rc 0"     "0" "$rc"
eq "…and no description key on the wire at all"      "false" \
   "$(kb_stub_bodies POST '/tasks.json' | jq -c 'has("description")')"
kbc patch --task 505 --pr 12
eq "patch with neither text flag → rc 0"             "0" "$rc"
eq "…and neither key on the wire"                    "false,false" \
   "$(kb_stub_bodies PATCH '/tasks/505.json' | jq -r '[has("name"),has("description")] | join(",")')"
# …while create-card's NAME requirement is now a question about the resolved name, not about
# which of the two flags carried it, and says so.
kbc create-card --type fr
eq "create-card with neither --name nor --name-file → rc 2" "2" "$rc"
eq "…and names both spellings"                       "true" "$(has '--name or --name-file required' "$err")"
eq "…and issues no request"                          "0" "$(kb_stub_total)"

# The third member of the pair set gets the `-` refusal too — it is one resolver, so a flag left
# out of it would be a divergence, and this is the leg that would see it.
kbc comment --task 505 --content-file -
eq "comment --content-file - → rc 2"                 "2" "$rc"
eq "…names the token, not a stdin ban"               "true" "$(has "'-' is not a stdin token" "$err")"
eq "…and issues no request"                          "0" "$(kb_stub_total)"

unset -f kb_stub_route ta ta_wire
unset TA_CARD TA_INJ TA_INJ_JSON TA_METHOD TA_PATH

# ---------------------------------------------------------------------------
echo "== search — the free-text verb, and the DESCRIPTION it exists to print (card#6771) =="
# THE GAP: the board's search endpoint has always matched name + description and returned the
# whole card, but no verb surfaced it — so the only board-wide read was `list`, whose nine-field
# projection drops `description`. A grep for a phrase in a card BODY through `list` therefore
# answered 0 no matter what the board held. The load-bearing property of this verb is that the
# field it MATCHED ON is the field it PRINTS; a result that hid it would move the same miss one
# layer over rather than close it.
#
# The server-side semantics asserted here are only the ones the CLIENT owes: that the query
# reaches the wire as one encoded term inside this board's `q=`. WHICH cards match is the
# server's rule (MATCH-in-boolean-mode vs a substring LIKE, decided there by driver and token
# length) and a stub cannot witness it — a test that faked it would be asserting on its own
# fixture. Read the parser, not this file, for that half.

# The renderer is pure, so it is asserted on synthetic cards first.
SR_MULTI='[{"id":7,"workflow_stage_id":48,"name":"probe card","description":"line one\nline two"}]'
eq "render: a hit is a header line + its description, EVERY line indented" \
   "$(printf 'card 7 · stage 48 · probe card\n  line one\n  line two')" \
   "$(printf '%s' "$SR_MULTI" | _kbc_search_render)"
# The whole point, asserted as an equality on the description text rather than on a line count:
# a renderer that printed only the first line, or a truncation of it, still prints A block.
eq "render: the description arrives WHOLE, not a first line or a summary" "true" \
   "$(has 'line two' "$(printf '%s' "$SR_MULTI" | _kbc_search_render)")"
eq "render: two hits are two blocks" "2" \
   "$(printf '%s' '[{"id":1,"name":"a","description":"x"},{"id":2,"name":"b","description":"y"}]' \
      | _kbc_search_render | /usr/bin/grep -c '^card ')"
# A card that matched on its NAME and has no body says so in words: an empty indented block
# reads as a rendering fault, i.e. exactly like the dropped field this verb exists to restore.
eq "render: a card with no description SAYS so rather than printing an empty block" \
   "$(printf 'card 3 · stage 48 · titled only\n  (no description)')" \
   "$(printf '%s' '[{"id":3,"workflow_stage_id":48,"name":"titled only"}]' | _kbc_search_render)"
eq "render: an explicitly null description is the same answer" \
   "$(printf 'card 4 · stage ? · n\n  (no description)')" \
   "$(printf '%s' '[{"id":4,"name":"n","description":null}]' | _kbc_search_render)"
# A description is UNTRUSTED text printed to a terminal, and it reaches the same shared C0
# sanitizer the comment renderer uses: `ESC[2K ESC[1A` in a card body would otherwise erase the
# `card <id>` line above it — the line that says which card the text came from.
eq "render: an ESC in the DESCRIPTION is neutralized" \
   "$(printf 'card 5 · stage ? · n\n  ?[2K?[1Abody')" \
   "$(jq -nc --arg e "$(printf '\033')" '[{id:5,name:"n",description:($e + "[2K" + $e + "[1Abody")}]' \
      | _kbc_search_render)"
# …and the header line's own fields come from the same untrusted body, under the STRICTER
# filter: a newline in a card NAME would forge a second `card N · …` block, which indented
# content can never do.
eq "render: a NEWLINE in the card NAME cannot forge a second block" "1" \
   "$(jq -nc '[{id:6,name:"n\ncard 99 · stage 1 · impostor",description:"b"}]' \
      | _kbc_search_render | /usr/bin/grep -c '^card ')"
eq "render: a TAB in the description survives (it cannot move the cursor backward)" \
   "$(printf 'card 8 · stage ? · n\n  col1\tcol2')" \
   "$(jq -nc '[{id:8,name:"n",description:"col1\tcol2"}]' | _kbc_search_render)"
# TOTAL, not gated: a description that is not a string renders as its JSON text instead of
# dying at jq's rc 5 PART WAY THROUGH the blocks and handing back a truncated result.
rc=0; out="$(printf '%s' '[{"id":9,"name":"n","description":{"oops":1}},{"id":10,"name":"m","description":"after"}]' \
             | _kbc_search_render 2>/dev/null)" || rc=$?
eq "render: a non-string description does not kill the render"        "0" "$rc"
eq "render: …and the block AFTER it is still printed"                 "true" "$(has 'card 10' "$out")"

# --- process-level: the real paginator + kb_api, over a faked kanban ---------
rm -rf "$TMP"
_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48' 'export KB_STAGE_IN_PROGRESS=49' 'export KB_TYPE_FR=7'
# Resolved BEFORE the stub PATH exists, so it names the real jq and not a stand-in.
KB_JQ_REAL="$(command -v jq)"; export KB_JQ_REAL
kb_stub_install

# One page of 200 rows is what makes the paginator ask for a second page — the only way to
# reach the mid-pagination rc from outside.
KBS_FULL_PAGE="$(jq -nc '{data:[range(200)|{id:(.+1000),workflow_stage_id:48,name:"bulk",description:"bulk body"}],meta:{last_page:2,total:400}}')"
KBS_HITS_BODY='{"data":[{"id":501,"workflow_stage_id":48,"card_type_id":7,"name":"deploy hook card","description":"first line\nsecond line"},{"id":502,"workflow_stage_id":49,"card_type_id":null,"name":"other","description":"other body"}],"links":{},"meta":{"last_page":1,"total":2}}'
export KBS_FULL_PAGE KBS_HITS_BODY
kb_stub_route() {
    local method="$1" url="$2" page
    page="${url##*page=}"; page="${page%%&*}"
    case "$method $url" in
        "GET "*/tasks/search.json*)
            case "${KBS_SCENARIO:-hits}" in
                hits)      printf '200\n%s' "$KBS_HITS_BODY" ;;
                empty)     printf '200\n{"data":[],"links":{},"meta":{"last_page":1,"total":0}}' ;;
                page1fail) printf '403\n{"message":"token lacks board scope"}' ;;
                page2fail) if [[ "$page" == "1" ]]; then printf '200\n%s' "$KBS_FULL_PAGE"
                           else printf '500\n{"message":"upstream exploded"}'; fi ;;
                pagecap)   printf '200\n%s' "$KBS_FULL_PAGE" ;;
                shortread) printf '200\n{"data":[{"id":1,"name":"a","description":"x"}],"meta":{"last_page":1,"total":3}}' ;;
            esac ;;
    esac
}
export -f kb_stub_route
# The URL field of the one search request, for the wire assertions.
sq_url() { kb_stub_lines GET '/tasks/search.json' | cut -f2; }

echo "-- search: the query reaches the wire as ONE encoded term inside this board's q= --"
kbc search 'deploy hook'
eq "search → rc 0"                                   "0" "$rc"
eq "search → exactly one request"                    "1" "$(kb_stub_total)"
# board_id FIRST and the term after it: the board scope is this tool's, not the caller's, and a
# caller's own board_id token is ANDed with it rather than replacing it.
eq "search → q carries board_id then the term, space-encoded" "true" \
   "$(has 'q=board_id=42%20deploy%20hook&' "$(sq_url)")"
eq "search → still the whole-board page size and page 1"      "true" \
   "$(has 'limit=200&page=1' "$(sq_url)")"
# A term carrying an `&` must not become a second query parameter — the encode is what stops a
# search string from retargeting the read.
kbc search 'a&b c'
eq "search → an & in the term is encoded, not a new parameter" "true" \
   "$(has 'q=board_id=42%20a%26b%20c&' "$(sq_url)")"
eq "search → …so the request still carries exactly one q"      "1" \
   "$(sq_url | /usr/bin/grep -o 'q=' | /usr/bin/grep -c 'q=')"

echo "-- search: THE LOAD-BEARING LEG — the hit prints the FULL description --"
kbc search 'deploy hook'
eq "a hit prints its card header"                    "true" "$(has 'card 501 · stage 48 · deploy hook card' "$out")"
eq "a hit prints the description's FIRST line"       "true" "$(has '  first line' "$out")"
# The second line is the assertion a first-line-only or truncating render cannot pass, and the
# one that reds when `list`'s projection (which drops description entirely) is substituted.
eq "a hit prints the description's SECOND line too"  "true" "$(has '  second line' "$out")"
eq "…one block per matched card"                     "2" "$(/usr/bin/grep -c '^card ' <<<"$out")"
eq "…and nothing about it goes to stderr"            ""  "$err"

echo "-- search: a multi-word query is ONE term, both words on the wire --"
kbc search 'deploy hook'
eq "both words ride in the same q term"              "true" "$(has 'deploy%20hook' "$(sq_url)")"
eq "…and neither becomes its own parameter"          "1" "$(kb_stub_total)"

echo "-- search: zero hits exits cleanly and SAYS so --"
KBS_SCENARIO=empty kbc search 'nothing matches this'
eq "no hits → rc 0"                                  "0" "$rc"
eq "no hits → an explicit line, not a silent empty stdout" "true" \
   "$(has 'no card on board 42 matched this search' "$out")"
eq "no hits → no card block is printed"              "0" "$(/usr/bin/grep -c '^card ' <<<"$out" || true)"

echo "-- search: the refusals decided offline, each costing no traffic --"
kbc search
eq "no query → rc 2"                                 "2" "$rc"
eq "…names what the verb takes"                      "true" "$(has 'search requires a query' "$err")"
eq "…and issues no request"                          "0" "$(kb_stub_total)"
kbc search ""
eq "an EMPTY query → rc 2 (the unexpanded-variable class)" "2" "$rc"
eq "…and issues no request"                          "0" "$(kb_stub_total)"
# A whitespace-only term is not a narrow search: the server trims the q value, finds no token,
# and answers the WHOLE BOARD — which this verb would print as matches, every description
# included. That is the widest wrong answer available here, so it is refused before the wire.
kbc search '   '
eq "a whitespace-only query → rc 2"                  "2" "$rc"
eq "…says why (it would match every card)"           "true" "$(has 'matches every card' "$err")"
eq "…and issues no request"                          "0" "$(kb_stub_total)"
kbc search one two
eq "a second positional → rc 2"                      "2" "$rc"
eq "…and issues no request"                          "0" "$(kb_stub_total)"
kbc search x --column no-such-column
eq "an unknown --column → rc 2 through the shared resolver" "2" "$rc"
eq "…and issues no request"                          "0" "$(kb_stub_total)"

echo "-- search: --column / --type filter the match set and name their denominator --"
kbc search 'deploy hook' --column backlog
eq "--column → rc 0"                                 "0" "$rc"
eq "--column keeps the matching card"                "true" "$(has 'card 501' "$out")"
eq "--column drops the other one"                    "false" "$(has 'card 502' "$out")"
eq "--column names the denominator on stderr"        "true" "$(has 'search --column backlog: 1 of 2 cards matched by the query' "$err")"
kbc search 'deploy hook' --type fr
eq "--type resolves through the board's native id"   "true" "$(has 'card 501' "$out")"
eq "--type drops the untyped card"                   "false" "$(has 'card 502' "$out")"
# A filter that removes every match is a DIFFERENT answer from a query that matched nothing,
# and saying the first for the second sends a caller hunting the wrong thing.
kbc search 'deploy hook' --column in_progress --type fr
eq "filtered to nothing → rc 0"                      "0" "$rc"
eq "…says the query DID match, and the flags removed them" "true" \
   "$(has 'the query matched 2 card(s) on board 42, none of which passed the filter flags' "$out")"
eq "…and does not claim the board holds no match"    "false" "$(has 'no card on board 42 matched' "$out")"

echo "-- search: an INCOMPLETE read is a refusal, never a partial answer presented as whole --"
# THE mid-pagination case (card#6630): page 1 delivers a full 200 rows, page 2 fails. The
# paginator returns rc 2 and emits nothing; the verb must not print the 200 cards it does have.
KBS_SCENARIO=page2fail kbc search 'bulk'
eq "page 2 unreadable → rc 1"                        "1" "$rc"
eq "…NOT ONE card block reaches stdout"              "0" "$(/usr/bin/grep -c '^card ' <<<"$out" || true)"
eq "…stdout is empty entirely"                       ""  "$out"
eq "…the refusal names the paginator's rc"           "true" "$(has 'did not return a complete card list for this search (fetch rc=2)' "$err")"
eq "…and says it is refusing a partial answer"       "true" "$(has 'refusing to present a partial match set as a whole one' "$err")"
eq "…both pages really were attempted"               "2" "$(kb_stub_count_any '/tasks/search.json')"
# The other four paginator outcomes reach the same arm — this is the measurement behind the
# `rc 1,2,3,4,5` arity registered in tests/fetch-board-cards-caller-claims-selftest.sh.
KBS_SCENARIO=page1fail kbc search 'bulk'
eq "page 1 unreadable → rc 1"                        "1" "$rc"
eq "…naming fetch rc=1"                              "true" "$(has '(fetch rc=1)' "$err")"
eq "…with empty stdout"                              ""  "$out"
KBS_SCENARIO=pagecap BOARD_PAGE_CAP=1 kbc search 'bulk'
eq "the page cap → rc 1"                             "1" "$rc"
eq "…naming fetch rc=3"                              "true" "$(has '(fetch rc=3)' "$err")"
eq "…with empty stdout, though the paginator emitted its partial array" "" "$out"
KBS_SCENARIO=shortread kbc search 'bulk'
eq "a short read → rc 1"                             "1" "$rc"
eq "…naming fetch rc=4"                              "true" "$(has '(fetch rc=4)' "$err")"
eq "…with empty stdout"                              ""  "$out"

echo "-- search: an unencodable term is refused BEFORE any request (fetch rc 5) --"
# The one paginator rc only a search can reach. It is unreachable from any query string (a
# non-empty term always has a non-empty @uri), so the seam is a jq that fails exactly the
# `@uri` call and passes everything else through — see tests/_kb-jq-uri-fail-stub.sh.
cp "$HERE/_kb-jq-uri-fail-stub.sh" "$TMP/bin/jq"
chmod +x "$TMP/bin/jq"
kbc search 'deploy hook'
eq "an unencodable term → rc 1"                      "1" "$rc"
eq "…naming fetch rc=5"                              "true" "$(has '(fetch rc=5)' "$err")"
# The property that makes rc 5 worth its own rc: NOTHING was asked of the server. A dropped
# encode would instead have sent the bare board_id read — the whole board, answered as the
# match set.
eq "…and NO request was issued at all"               "0" "$(kb_stub_total)"
eq "…the paginator says why on stderr"               "true" "$(has 'could not be encoded' "$err")"
rm -f "$TMP/bin/jq"
# The control that says the stub, not the code, is what those three assertions measured.
kbc search 'deploy hook'
eq "control: with the real jq back, the same call is rc 0 again" "0" "$rc"
eq "control: …and issues its request"                "1" "$(kb_stub_total)"

unset -f kb_stub_route sq_url
unset KBS_SCENARIO KBS_FULL_PAGE KBS_HITS_BODY SR_MULTI KB_JQ_REAL

# ---------------------------------------------------------------------------
_summary "kbcard-selftest"
