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
# has <needle> <haystack> → true/false on a LITERAL substring match (no globbing,
# no regex — robust against the JSON quotes/braces in the dry-run output).
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

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

# THE safety guard: --hard without --yes in a non-interactive shell refuses UP
# FRONT (rc 2, before any soft-delete) — never leaves the card half-trashed.
# </dev/null forces a non-TTY fd 0 so the check is deterministic in any CI shell.
rc=0; err="$(cmd_delete --task 42 --hard </dev/null 2>&1)" || rc=$?
eq "non-TTY --hard without --yes → rc 2"      "2"    "$rc"
eq "non-TTY --hard refusal names --yes"       "true" "$(has '--yes' "$err")"

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

# has_tag <body-json> <tag> → membership of the created card's .task.tags array.
has_tag() { jq -e --arg t "$2" '((.task.tags // []) | index($t)) != null' <<<"$1" >/dev/null && echo true || echo false; }

# Native-type board: --triaged adds `triaged`; the native id is used, no type: tag.
export KB_TYPE_TASK=21; unset KB_TYPING_MODE 2>/dev/null || true
b="$(cmd_create_card --type task --name x --triaged 2>/dev/null)"
eq "native + --triaged → triaged tag present" "true"  "$(has_tag "$b" triaged)"
eq "native + --triaged → native card_type_id" "21"    "$(jq -c '.task.card_type_id' <<<"$b")"
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
unset KB_SWIMLANE_1 KB_SWIMLANE_2

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
# byte-identical task.payload — the whole point of sharing one assembler. Stub the
# API to echo the request body; assert the .task.payload objects match.
kb_api() { printf '%s' "$3"; }
_kbc_write_echo() { cat; }
export KB_BOARD_ID=12 KB_STAGE_BACKLOG=48 KB_TYPE_TASK=21 KB_CF_VERSION_TARGET=99
unset KB_TYPING_MODE 2>/dev/null || true
cpay="$(cmd_create_card --type task --name x --dl DL-7 --pr 42 --pr-url https://github.com/o/r/pull/0 --version v1.0.0 2>/dev/null | jq -Sc '.task.payload')"
ppay="$(cmd_patch --task 99 --dl DL-7 --pr 42 --pr-url https://github.com/o/r/pull/0 --version v1.0.0 2>/dev/null | jq -Sc '.task.payload')"
eq "create + patch send identical payload" "$cpay" "$ppay"
eq "and it is the expected object" \
   '{"dl_number":"DL-0007","pr_number":42,"pr_url":"https://github.com/o/r/pull/0","version_target":"v1.0.0"}' "$cpay"

# --issue / --issue-url wired through create-card AND patch: issue_number number-typed, and a
# card co-stamped with --issue + --pr carries BOTH lifecycle pairs, independently.
ci="$(cmd_create_card --type task --name x --issue 300 --issue-url https://github.com/o/r/issues/300 2>/dev/null | jq -Sc '.task.payload')"
eq "create-card --issue → number-typed issue_number + issue_url" \
   '{"issue_number":300,"issue_url":"https://github.com/o/r/issues/300"}' "$ci"
pi="$(cmd_patch --task 99 --issue 300 --issue-url https://github.com/o/r/issues/300 2>/dev/null | jq -Sc '.task.payload')"
eq "patch --issue sends the identical issue payload" "$ci" "$pi"
co="$(cmd_create_card --type task --name x --issue 300 --pr 305 2>/dev/null | jq -Sc '.task.payload')"
eq "create-card --issue + --pr co-stamp both keys, independent" \
   '{"issue_number":300,"pr_number":305}' "$co"

# card-4714: patch --swimlane writes the card's TOP-LEVEL swimlane_id (not a payload
# key), resolving a name through the SAME swimlane_id() helper `list` uses. A numeric
# --task short-circuits resolve_task (no search call) and kb_api is stubbed to echo the
# request body, so this is network-free. Assert on .task.swimlane_id.
export KB_SWIMLANE_1=device KB_SWIMLANE_2=backend
sp() { cmd_patch --task 99 "$@" 2>/dev/null | jq -c '.task'; }
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
unset KB_SWIMLANE_1 KB_SWIMLANE_2
unset -f sp _kbc_write_echo_orig

unset KB_BOARD_ID KB_STAGE_BACKLOG KB_TYPE_TASK KB_CF_VERSION_TARGET

# ---------------------------------------------------------------------------
_summary "kbcard-selftest"
