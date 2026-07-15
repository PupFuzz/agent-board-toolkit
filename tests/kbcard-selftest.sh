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
BIN="$HERE/../bin/kbcard"
[[ -r "$BIN" ]] || { echo "selftest: $BIN not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines stage_name / _kbc_annotate_card without running

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
eq()  { # <label> <expected> <got>
    [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"
}
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

# ---------------------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
    echo "kbcard-selftest: $fails check(s) FAILED" >&2
    exit 1
fi
echo "kbcard-selftest: all checks passed"
