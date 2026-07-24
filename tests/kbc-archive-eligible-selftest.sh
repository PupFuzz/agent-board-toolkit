#!/usr/bin/env bash
# kbc-archive-eligible-selftest.sh — network-free checks for the read-only
# _kbc-archive-eligible.py session-close leg: its done-lane candidate FILTER, the
# archived-card skip, and that it lists exactly the terminal cards the shipped
# `may_archive` gate reports eligible. It exercises the helper's main() over the
# REAL framework `may_archive` primitive (canon #9 — validate on the real surface)
# by path-loading it through a FAKE `kanban_common` that re-exports the real pure
# primitives (may_archive / _card_backing_sources / _derive_card_source / gh_json)
# but STUBS the I/O surface (load_config / load_token / KanbanClient.fetch_board /
# kanban_base_url / kanban_tls_verify) so the run is deterministic + offline. GitHub
# state is driven by a fake `gh` keyed PER PR NUMBER (so one board fetch can carry a
# terminal AND a live source at once). When the plugin's kanban_common cannot be
# located (a bare CI runner with no plugin cache) the whole suite SKIPs — every case
# here is primitive-backed.
#
# PROVE-IT-CAN-FAIL: the done-lane filter is load-bearing. Case (c) (an in-progress
# card with a terminal source) is asserted ABSENT from the output; the final block
# runs a MUTANT copy of the helper whose done-lane filter is widened to also accept
# in_progress, and asserts case (c) then APPEARS — so the pristine "absent" assertion
# is one that can go red, not a decoration.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
HELPER="$HERE/../bin/_kbc-archive-eligible.py"
LIB="$HERE/../bin/_kbc-archive-lib.py"
_need -r "$HELPER"
_need -r "$LIB"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }

_mktmp_scratch --home   # TMP + EXIT-cleanup trap + scratch HOME (no real ~/.kanban-* taint)

# ── Locate the real kanban_common the same way the helper's lib does ─────────────
REAL_KC="$(python3 - "$LIB" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lib", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.resolve_kanban_common() or "")
PY
)"
if [[ -z "$REAL_KC" || ! -f "$REAL_KC" ]]; then
    echo "  SKIP — plugin kanban_common not found on this host (nothing to validate offline)"
    _summary "kbc-archive-eligible-selftest"
    return 0 2>/dev/null || exit 0
fi
export REAL_KANBAN_COMMON="$REAL_KC"

# ── Fake gh on PATH: per-PR-number canned state (arg 3 is the number) ────────────
#    FAKE_GH_STATE_<num>=OPEN|CLOSED|MERGED ; "ERR" makes gh exit non-zero.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
num="$3"                       # gh pr view <num> --repo <r> --json state
var="FAKE_GH_STATE_${num}"
st="${!var:-OPEN}"
[[ "$st" == "ERR" ]] && { echo "gh: read failed" >&2; exit 1; }
printf '{"state":"%s"}' "$st"
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# ── Fake kanban_common: real pure primitives + stubbed I/O surface ──────────────
cat > "$TMP/fake_kc.py" <<'PY'
import importlib.util, json, os
_spec = importlib.util.spec_from_file_location("real_kc_st", os.environ["REAL_KANBAN_COMMON"])
_r = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_r)

# real, pure — the gate + its source machinery
may_archive = _r.may_archive
_card_backing_sources = _r._card_backing_sources
_derive_card_source = _r._derive_card_source
_source_key = _r._source_key
gh_json = _r.gh_json                       # shells to the fake gh on PATH

# stubbed I/O surface (env-driven), so main() runs offline + deterministic
def load_config():
    return json.loads(os.environ["FAKE_CONFIG"])
def load_token():
    return "faketoken"
def kanban_base_url():
    return "http://fake.invalid"
def kanban_tls_verify():
    return False
class KanbanClient:
    def __init__(self, *a, **k):
        pass
    def fetch_board(self, board_id):
        with open(os.environ["FAKE_BOARD"]) as f:
            return json.load(f)
PY
export KBCARD_KANBAN_COMMON="$TMP/fake_kc.py"

# ── Fake board: two stages (done / in_progress) + the four case cards ───────────
cat > "$TMP/board.json" <<'EOF'
{
  "workflows": [{"stages": [
    {"id": 1, "name": "In Progress", "lane_type": "in_progress"},
    {"id": 2, "name": "Done", "lane_type": "done"}
  ]}],
  "tasks": [
    {"id": 10, "name": "done-with-terminal-source",       "workflow_stage_id": 2, "payload": {"pr_number": 5, "repo": "o/r"}},
    {"id": 11, "name": "done-with-live-source",            "workflow_stage_id": 2, "payload": {"pr_number": 6, "repo": "o/r"}},
    {"id": 12, "name": "inprogress-with-terminal-source",  "workflow_stage_id": 1, "payload": {"pr_number": 7, "repo": "o/r"}},
    {"id": 13, "name": "archived-done-card", "archived_at": "2026-07-01T00:00:00Z", "workflow_stage_id": 2, "payload": {"pr_number": 8, "repo": "o/r"}}
  ]
}
EOF
export FAKE_BOARD="$TMP/board.json"
export FAKE_CONFIG='{"kanban":{"boards":[{"key":"test","board_id":"100","repo":"o/r"}]}}'

# case (a) terminal source → CLOSED (eligible); (b) live → OPEN (blocked, no twin);
# (c) in_progress card's source terminal (would be eligible IF it were a candidate);
# (d) archived card's source terminal (irrelevant — the card is skipped).
export FAKE_GH_STATE_5=CLOSED
export FAKE_GH_STATE_6=OPEN
export FAKE_GH_STATE_7=CLOSED
export FAKE_GH_STATE_8=CLOSED

has() { case "$1" in *"$2"*) echo true ;; *) echo false ;; esac; }

echo "== _kbc-archive-eligible.py over the REAL may_archive (kanban_common: $REAL_KC) =="
out="$(python3 "$HELPER" 2>&1)"; rc=$?
eq "helper exits 0 (no infra error)"                       "0"    "$rc"
eq "(a) done card, all sources terminal → LISTED eligible" "true"  "$(has "$out" "done-with-terminal-source")"
eq "(b) done card, live source no twin → NOT listed"       "false" "$(has "$out" "done-with-live-source")"
eq "(c) in-progress card (terminal src) → NOT a candidate" "false" "$(has "$out" "inprogress-with-terminal-source")"
eq "(d) archived done card → skipped"                      "false" "$(has "$out" "archived-done-card")"
eq "summary reports 2 done cards not yet archived (total)"  "true"  "$(has "$out" "2 done card(s) not yet archived")"
eq "sample reports exactly 1 safe to archive now"          "true"  "$(has "$out" "1 safe to archive now")"
eq "eligible line carries the [Done] column"               "true"  "$(has "$out" "[Done]")"

# ── PROVE-IT-CAN-FAIL: widen the done-lane filter → case (c) must appear ─────────
# A mutant copy (lib copied alongside so its sibling path-load still resolves) whose
# `== "done"` candidate filter also accepts in_progress. If case (c) STILL didn't
# appear, the pristine "(c) NOT a candidate" assertion above would be untestable.
echo "== prove-it-can-fail: inverting the done-lane filter surfaces the in_progress card =="
mkdir -p "$TMP/mut"
cp "$LIB" "$TMP/mut/_kbc-archive-lib.py"
sed 's/== "done"/in ("done", "in_progress")/' "$HELPER" > "$TMP/mut/_kbc-archive-eligible.py"
mut="$(python3 "$TMP/mut/_kbc-archive-eligible.py" 2>&1)"
eq "mutant (widened filter) NOW lists the in-progress card" "true" "$(has "$mut" "inprogress-with-terminal-source")"
eq "pristine filter change was the only difference (mutant differs)" "true" "$([[ "$mut" != "$out" ]] && echo true || echo false)"

_summary "kbc-archive-eligible-selftest"
