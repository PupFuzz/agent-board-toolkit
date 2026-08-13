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
r="$(echo '{"data":{"id":1,"name":"x","workflow_stage_id":5}}' | _kbc_write_echo)"
eq "absent payload key → omitted"  "false" "$(jq 'has("payload")' <<<"$r")"
r="$(echo '{"data":{"id":1,"name":"x","workflow_stage_id":5,"payload":{"dl_number":"DL-0001"}}}' | _kbc_write_echo)"
eq "real payload → included"       '{"dl_number":"DL-0001"}' "$(jq -c '.payload' <<<"$r")"
r="$(echo '{"data":{"id":1,"name":"x","workflow_stage_id":5,"payload":null}}' | _kbc_write_echo)"
eq "server-sent null → passed through (the server SAID null)" "true" "$(jq 'has("payload")' <<<"$r")"
r="$(echo '{"data":{"id":1,"name":"x","workflow_stage_id":5,"description":"abcdef"}}' | _kbc_write_echo 'description: (.description // "" | .[0:3])')"
eq "extra-fields arg composes (patch echo)" '"abc"' "$(jq -c '.description' <<<"$r")"


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
_kbc_write_echo() { cat; }
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
_kbc_write_echo() { cat; }
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
_kbc_write_echo() { cat; }
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
_kbc_write_echo() { cat; }
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
_kbc_write_echo() { cat; }

rc=0; err="$(cmd_patch --task 99 --dl "" 2>&1 >/dev/null)" || rc=$?
eq "patch --dl \"\" → rc 2"                        "2"    "$rc"
eq "patch --dl \"\" names the flag"                "true" "$(case "$err" in *'--dl requires a non-empty value'*) echo true ;; *) echo false ;; esac)"
# The negative control that makes the above attributable: a REAL value still stamps.
eq "patch --dl DL-7 still stamps (control)"        "DL-0007" \
   "$(cmd_patch --task 99 --dl DL-7 2>/dev/null | jq -r '.payload.dl_number')"

# The whole class, not the one reported instance.
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
      | _kbc_comments_render | grep -c '^comment ')"
# The author is a bare user id because that is the ONLY author field a comment row carries
# (measured) — a name would be a fabrication. A missing one degrades to `?`, not to "null".
eq "render: a row with no user_id says ? rather than null" "comment 3 · user ? · ?" \
   "$(printf '%s' '[{"id":3,"content":"","created_at":null}]' | _kbc_comments_render)"
# The TAB is exempt alongside the newline. It IS a C0 control, but it cannot move the cursor
# backward — it only advances to the next tab stop — so replacing it buys nothing against the
# thing this filter exists for (an ESC sequence erasing the attribution line above) while
# damaging every pasted diff, log line or indented block a comment carries.
eq "render: a TAB survives — it cannot move the cursor backward" \
   "$(printf 'comment 4 · user 7 · t\n  col1\tcol2')" \
   "$(printf '%s' '[{"id":4,"user_id":7,"content":"col1\tcol2","created_at":"t"}]' | _kbc_comments_render)"

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

# kbc <args…> — run the REAL bin as a process on a fresh request log; sets rc/out/err.
kbc() { kb_stub_reset; rc=0; out="$("$BIN" "$@" 2>"$TMP/e")" || rc=$?; err="$(cat "$TMP/e")"; }
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
   "$(grep -Eq -- '(^|[^[:alnum:]_-])--content([^[:alnum:]_-]|$)' <<<"$err" \
      && grep -qF -- '--content-file' <<<"$err" && echo true || echo false)"
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
eq "comments → one block per comment"            "2" "$(grep -c '^comment ' <<<"$out")"
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
# The byte-level assertion, with /usr/bin/grep because the ambient `grep` on some hosts is a
# shim. Its positive control is the line below it: the SAME grep over the same fixture's raw
# content finds the byte, so a 0 here is an absence rather than a grep that never matches.
eq "control chars → the raw ESC byte is ABSENT from stdout" "0" \
   "$(printf '%s' "$out" | /usr/bin/grep -c -e "$ESC" || true)"
eq "control: that grep DOES find the ESC in the unsanitized fixture" "1" \
   "$(printf '%s' "$CTRL_COMMENTS" | jq -r '.[0].content' | /usr/bin/grep -c -e "$ESC" || true)"
unset ESC CTRL_COMMENTS

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
# `show` reads the SAME detail body through the same projection and had the same hole. Its
# positive control is the line below: on a well-formed body it still prints the card at rc 0,
# so the refusal above is the non-JSON case and not `show` being broken outright.
KB_STUB_GET_HTTP=200 KB_STUB_GET_BODY="$NONJSON_BODY" kbc show --task 505
eq "show: 2xx NON-JSON body → rc 1, not jq's rc 5" "1" "$rc"
eq "…refuses in kbcard's own words, naming the verb" "true" "$(has 'kbcard: show' "$err")"
eq "…and leaks no raw jq parse error"            "false" "$(has 'parse error' "$err")"
eq "…and prints nothing on stdout"               "" "$out"
kbc show --task 505
eq "control: show on a well-formed body → rc 0"  "0" "$rc"
eq "control: …and returns the card"              "505" "$(jq -r '.id' <<<"$out")"
unset NONJSON_BODY

unset -f kbc kb_stub_route
unset NOT_FOUND_BODY KB_STUB_CREATED

# ---------------------------------------------------------------------------
_summary "kbcard-selftest"
