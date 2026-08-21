#!/usr/bin/env bash
# kbc-stale-blocker-selftest.sh — network-free checks for the read-only
# _kbc-stale-blocker.py session-close leg: the citation form, the blocking-context
# adjacency, the three structural exclusions, the referent-state test (including the
# `waiting` bound it deliberately does NOT treat as terminal), the cross-board index,
# the bounded referent read, and the fail-loud board-read contract.
#
# NO PLUGIN DEPENDENCY, AND THAT IS A REAL DIFFERENCE FROM ITS SIBLING.
# `kbc-archive-eligible-selftest.sh` SKIPs when the plugin's `kanban_common` cannot be
# located, because every case there is backed by the framework's real `may_archive`
# primitive. This leg rides no framework primitive at all — it uses `kanban_common` only
# for config/token/HTTP — so the fake module here is wholly synthetic and every case runs
# on every host, including a bare CI runner. Nothing is skipped and nothing is faked that
# the leg's OWN logic owns: the predicate, the exclusions and the classification are the
# real ones, over fixture boards.
#
# ⛔ THE MUTATION BATTERY IS THE POINT (canon #9). Nearly every assertion below is an
# assertion of ABSENCE — "this card must NOT be flagged" — and an absence assertion passes
# just as well against a tool that flags nothing at all. So each one is paired with a
# MUTANT run: a copy of the helper with exactly the guard that suppresses that case
# removed, asserted to flag it. A case with no mutant is a decoration, and the positive
# control (#6581, the historical true positive this class was filed from) is what proves
# the pipeline can fire at all.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
HELPER="$HERE/../bin/_kbc-stale-blocker.py"
LIB="$HERE/../bin/_kbc-archive-lib.py"
_need -r "$HELPER"
_need -r "$LIB"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }

_mktmp_scratch --home   # TMP + EXIT-cleanup trap + scratch HOME (no real ~/.kanban-* taint)

# ── Fake kanban_common: the I/O surface only, env-driven ────────────────────────
# fetch_board's SystemExit(2) is not an invention here — it is the framework's own
# LOUD-FATAL board-read contract (card#4889), and the leg's warn-and-continue arm is
# written against it, so the fake has to keep it or that arm would never be exercised.
cat > "$TMP/fake_kc.py" <<'PY'
import json, os

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
        with open(os.environ["FAKE_BOARDS"]) as f:
            boards = json.load(f)
        b = boards.get(str(board_id))
        if b is None:
            raise SystemExit(2)      # the framework's loud-fatal read contract
        return b
    def fetch_card_status(self, tid):
        with open(os.environ["FAKE_DETAIL"]) as f:
            rows = json.load(f)
        row = rows.get(str(tid))
        if row is None:
            return "absent", None
        if row == "ERROR":
            return "error", None
        return "ok", row
PY
export KBCARD_KANBAN_COMMON="$TMP/fake_kc.py"

# ── Fixture boards. Two of them, because ids are global on a real install and the
#    cross-board case is the one a per-board scan gets wrong. ────────────────────
python3 - "$TMP" <<'PY'
import json, os, sys
tmp = sys.argv[1]

def stage(i, name, lane):
    return {"id": i, "name": name, "lane_type": lane}

def card(cid, board, stage_id, name, desc=""):
    return {"id": cid, "board_id": board, "workflow_stage_id": stage_id,
            "name": name, "description": desc}

SPECIMEN = "**Blocked behind DL-238 (card #6570)**"

b5 = {
    "id": 5,
    "workflows": [{"stages": [
        stage(1, "In Progress", "in_progress"),
        stage(2, "Backlog", "backlog_inventory"),
        stage(3, "Released to main", "done"),
        stage(4, "Shipped to dev", "waiting"),
    ]}],
    "tasks": [
        card(6570, 5, 3, "the blocker, released"),
        card(6873, 5, 2, "a genuinely OPEN blocker"),
        card(6910, 5, 4, "a blocker that only reached Shipped to dev"),
        # POSITIVE CONTROL — kanban#6581's pre-fix text, the known-true historical positive
        card(6581, 5, 2, "refuse-with-remedy", SPECIMEN + " — original reason"),
        # NEGATIVE CONTROL — cites a blocker that is genuinely open
        card(6900, 5, 2, "negative control", "Blocked behind card#6873, which is open."),
        # SUPPRESSION (a) inline-code / (b) strikethrough / (c) discharge line
        card(6901, 5, 2, "suppression a", "| 3 | `" + SPECIMEN + "` | quoted specimen |"),
        card(6902, 5, 2, "suppression b", "~~" + SPECIMEN + "~~ — kept for provenance"),
        card(6903, 5, 2, "suppression c", "✅ **UNBLOCKED 2026-08-20.** " + SPECIMEN),
        # BARE #N is not a citation
        card(6904, 5, 2, "bare-hash control", "Blocked behind #6570 (no card token)."),
        # PROVENANCE — bare `behind` is not a marker
        card(6905, 5, 2, "provenance control",
             "Filed by the canon #7 sibling audit behind card#6570."),
        # UNRESOLVED — an id no board carries and no detail GET finds
        card(6906, 5, 2, "unresolved control", "Blocked behind card#999999."),
        # The `waiting` bound, stated in the docblock, pinned here
        card(6907, 5, 2, "waiting-bound control", "Blocked behind card#6910."),
        # WORD BOUNDARY — "docblocks" is not "blocks"
        card(6908, 5, 2, "word-boundary control",
             "The cmd_comment/cmd_comments docblocks restate card#6570 verbatim."),
        # SENTENCE BOUNDARY between the marker and the citation
        card(6909, 5, 2, "sentence-boundary control",
             "It is blocked. See card#6570 for the remedy analysis."),
        # WINDOW — a marker further back than _MARKER_WINDOW does not govern
        card(6913, 5, 2, "window control",
             "Blocked, and after a long stretch of unrelated narration that runs past "
             "the window this leg allows, we mention card#6570."),
        # ARCHIVED referent — absent from every board GET, resolved by the detail read
        card(6911, 5, 2, "archived-referent control", "Blocked behind card#5000."),
        # OUT-OF-TENANT — ids are global on this shared instance, so this one resolves to a
        # REAL card on a board no roster entry names (roundtable #327, measured live).
        card(6915, 5, 2, "out-of-tenant control", "Blocked behind card#1120."),
    ],
}

b12 = {
    "id": 12,
    "workflows": [{"stages": [
        stage(11, "Backlog", "backlog_inventory"),
        stage(12, "Released to main", "done"),
    ]}],
    "tasks": [
        # CROSS-BOARD — a board-12 card citing a terminal board-5 card
        card(7000, 12, 11, "cross-board control", "Blocked behind card#6570."),
        card(7001, 12, 12, "a done card citing the same thing", "Blocked behind card#6570."),
    ],
}

with open(os.path.join(tmp, "boards.json"), "w") as f:
    json.dump({"5": b5, "12": b12}, f)

# The detail-GET surface: ids NOT on any board. 5000 is archived (terminal), 5001 is a
# read that FAILED (undetermined, not absent), everything else 404s.
# 1120 is the cross-tenant specimen: a real card on board 4, at a stage id that COLLIDES
# with board 5's "Released to main" — which is what makes an unqualified stage key answer
# "done" about a foreign card, and is exactly the wrong flag the mutants below produce.
detail = {
    "5000": {"id": 5000, "board_id": 5, "workflow_stage_id": 2,
             "name": "archived blocker", "archived_at": "2026-07-01T00:00:00Z"},
    "5001": "ERROR",
    "1120": {"id": 1120, "board_id": 4, "workflow_stage_id": 3,
             "name": "another tenant's card"},
}
with open(os.path.join(tmp, "detail.json"), "w") as f:
    json.dump(detail, f)

# A second board fixture whose one card cites 30 corpus-absent ids, to drive the
# per-run referent-read budget past its bound.
budget = {
    "5": {"id": 5, "workflows": b5["workflows"],
          "tasks": [card(6999, 5, 2, "budget control",
                         " ".join("Blocked behind card#%d." % (900000 + i)
                                  for i in range(30)))]},
}
with open(os.path.join(tmp, "boards-budget.json"), "w") as f:
    json.dump(budget, f)

# One card citing the id whose detail read FAILS, so the degraded-read arm is driven by a
# test rather than only by a docstring.
degraded = {
    "5": {"id": 5, "workflows": b5["workflows"],
          "tasks": [card(6998, 5, 2, "degraded-read control", "Blocked behind card#5001.")]},
}
with open(os.path.join(tmp, "boards-degraded.json"), "w") as f:
    json.dump(degraded, f)

# A board body carrying no `id` — the one shape whose fallback (key the lane map by the
# CONFIG's spelling of the board id) would produce a wrong-but-plausible clean scan.
noid = {"5": {"workflows": b5["workflows"], "tasks": b5["tasks"]}}
with open(os.path.join(tmp, "boards-noid.json"), "w") as f:
    json.dump(noid, f)
PY

export FAKE_BOARDS="$TMP/boards.json"
export FAKE_DETAIL="$TMP/detail.json"
export FAKE_CONFIG='{"kanban":{"boards":[{"key":"kanban","board_id":5},{"key":"toolkit","board_id":12}]}}'

# run_helper <dir> — run the helper (pristine or mutant) and echo its combined output.
run_helper() { python3 "$1/_kbc-stale-blocker.py" 2>&1; }

# mutant <name> <sed-expr> — a copy of the helper with ONE guard removed, with the lib
# copied beside it so its sibling path-load still resolves.
mutant() {
    local name="$1" expr="$2" dir="$TMP/mut-$1"
    mkdir -p "$dir"
    cp "$LIB" "$dir/_kbc-archive-lib.py"
    sed "$expr" "$HELPER" > "$dir/_kbc-stale-blocker.py"
    if cmp -s "$HELPER" "$dir/_kbc-stale-blocker.py"; then
        bad "mutant '$name' changed NOTHING — its sed matched no line, so the case it is
             supposed to prove is untested"
        return 1
    fi
    run_helper "$dir"
}

echo "== _kbc-stale-blocker.py over the fixture boards =="
out="$(run_helper "$(dirname "$HELPER")")"; rc=$?
eq "helper exits 0 (findings ride the report, not the exit code)" "0" "$rc"

# ── The positive control: without this the whole file is measuring nothing ───────
eq "POSITIVE CONTROL — #6581's pre-fix text flags"                   "true" \
   "$(has "card#6581 (kanban, Backlog) cites card#6570 as a blocker" "$out")"
eq "the flag names the referent's terminal column"                   "true" \
   "$(has "referent is TERMINAL: Released to main (kanban)" "$out")"
eq "CROSS-BOARD — a board-12 card citing a terminal board-5 card flags" "true" \
   "$(has "card#7000 (toolkit, Backlog) cites card#6570" "$out")"
eq "ARCHIVED referent (corpus-absent, resolved by detail GET) flags"  "true" \
   "$(has "card#6911 (kanban, Backlog) cites card#5000" "$out")"
eq "  … and says WHY it is terminal"                                 "true" \
   "$(has "referent is TERMINAL: archived" "$out")"

# ── The absence assertions. Each is paired with a mutant below. ──────────────────
eq "NEGATIVE CONTROL — blocker genuinely open → not flagged"    "false" "$(has "card#6900 " "$out")"
eq "(a) citation inside an inline-code span → not flagged"      "false" "$(has "card#6901 " "$out")"
eq "(b) citation inside a strikethrough span → not flagged"     "false" "$(has "card#6902 " "$out")"
eq "(c) line announcing the discharge → not flagged"            "false" "$(has "card#6903 " "$out")"
eq "bare #N is not a citation → not flagged"                    "false" "$(has "card#6904 " "$out")"
eq "provenance (bare 'behind' is not a marker) → not flagged"   "false" "$(has "card#6905 " "$out")"
eq "the \`waiting\` bound holds — shipped-to-dev is not terminal" "false" "$(has "card#6907 " "$out")"
eq "'docblocks' is not the marker 'blocks' → not flagged"       "false" "$(has "card#6908 " "$out")"
eq "a sentence boundary breaks the context → not flagged"       "false" "$(has "card#6909 " "$out")"
eq "a marker beyond the window does not govern → not flagged"   "false" "$(has "card#6913 " "$out")"
eq "a DONE card is not a citer (population is open cards)"      "false" "$(has "card#7001 " "$out")"

# ── Out-of-tenant: reported as its own finding, never a flag and never clean ─────
eq "OUT-OF-TENANT — an id on a non-roster board is REPORTED" "true" \
   "$(has "card#6915 (kanban, Backlog) cites card#1120 — OUT-OF-TENANT" "$out")"
eq "  … naming the referent's board AND the roster it is not in" "true" \
   "$(has "on board 4, which is NOT one of this roster's boards ([5, 12])" "$out")"
eq "  … called a MIS-CITATION, with the fix that is NOT widening a token" "true" \
   "$(has "fix the citation rather than widening any token" "$out")"
eq "  … and NOT reported as a blocker flag"                    "false" \
   "$(has "card#6915 (kanban, Backlog) cites card#1120 as a blocker" "$out")"
eq "the run footer states the tenant scoping out loud"         "true" \
   "$(has "resolution is deliberately confined to the roster boards" "$out")"

# ── Unresolved is reported, never dropped or counted clean ───────────────────────
eq "UNRESOLVED — an id no board and no GET can find is REPORTED" "true" \
   "$(has "card#6906 (kanban, Backlog) cites card#999999 — UNRESOLVED" "$out")"
eq "  … and says the id does not exist (404), not that it is clean" "true" \
   "$(has "no such card (404)" "$out")"

# ── The denominator: an empty result must be a measurement ───────────────────────
eq "reports boards read + cards indexed + open cards scanned" "true" \
   "$(has "2 board(s) read, 19 live card(s) indexed as referents, 17 open card(s) scanned" "$out")"
eq "reports the per-board open count"          "true" "$(has "board 5 (kanban): 17 live card(s), 16 open (scanned)" "$out")"
eq "reports the citations with no marker"      "true" "$(has "no blocking marker before it: 4" "$out")"
eq "reports the inline-code exclusion count"   "true" "$(has "excluded, inline-code: 1" "$out")"
eq "reports the strikethrough exclusion count" "true" "$(has "excluded, strikethrough: 1" "$out")"
eq "reports the discharge-line exclusion count" "true" "$(has "excluded, discharge-line: 1" "$out")"
eq "reports the candidate → flag/unresolved funnel" "true" \
   "$(has "asserted as a blocker: 7 → 3 flagged, 1 out-of-tenant, 1 unresolved referent(s); 3 referent GET(s) of 25" "$out")"
eq "every citation lands in exactly one bucket (4+1+1+1+7 = 14 examined)" "true" \
   "$(has "14 citation(s) examined" "$out")"
eq "the footer states the \`waiting\` under-report out loud" "true" \
   "$(has "\`waiting\`-lane (Shipped to dev) referents are NOT counted terminal" "$out")"

echo "== the referent-read budget is bounded, and a hit run SAYS it was bounded =="
bout="$(FAKE_BOARDS="$TMP/boards-budget.json" \
        FAKE_CONFIG='{"kanban":{"boards":[{"key":"kanban","board_id":5}]}}' \
        run_helper "$(dirname "$HELPER")")"
eq "exactly _MAX_REFERENT_GETS reads are issued"     "true" "$(has "25 referent GET(s) of 25" "$bout")"
eq "the run says the bound was HIT"                  "true" "$(has "referent-read budget (25) was HIT" "$bout")"
eq "the unread citations are UNRESOLVED, not clean"  "true" "$(has "this id was NOT read" "$bout")"

echo "== a referent read that FAILED is not a referent that is ABSENT =="
drc=0
dout="$(FAKE_BOARDS="$TMP/boards-degraded.json" \
        FAKE_CONFIG='{"kanban":{"boards":[{"key":"kanban","board_id":5}]}}' \
        run_helper "$(dirname "$HELPER")")" || drc=$?
eq "a degraded referent read is UNRESOLVED, distinctly worded" "true" \
   "$(has "the referent read FAILED" "$dout")"
eq "  … and is NOT reported as a 404 / absent card"            "false" "$(has "no such card (404)" "$dout")"
eq "  … and drives rc 2, because the instrument could not answer" "2" "$drc"

echo "== a board body with no id is REFUSED, not scanned against an index nothing matches =="
nrc=0
nout="$(FAKE_BOARDS="$TMP/boards-noid.json" \
        FAKE_CONFIG='{"kanban":{"boards":[{"key":"kanban","board_id":5}]}}' \
        run_helper "$(dirname "$HELPER")")" || nrc=$?
eq "an id-less board body drives rc 2"                    "2" "$nrc"
eq "…named, with the reason its cards cannot be keyed"    "true" \
   "$(has "board body carries no id" "$nout")"
eq "…and nothing is reported as scanned-and-clean"        "false" \
   "$(has "citation(s) examined" "$nout")"

echo "== fail LOUD: a board that cannot be read is named, and drives the exit code =="
lrc=0
lout="$(FAKE_CONFIG='{"kanban":{"boards":[{"key":"kanban","board_id":5},{"key":"gone","board_id":77},{"key":"unset","board_id":"REPLACE_ME"}]}}' \
        run_helper "$(dirname "$HELPER")")" || lrc=$?
eq "an unreadable board drives rc 2 (the instrument, not a finding)" "2" "$lrc"
eq "the unreadable board is named on stderr"        "true" "$(has "board 77 (gone): board read FATAL" "$lout")"
eq "  … and says its cards are missing as REFERENTS too" "true" \
   "$(has "neither scanned NOR available as referents" "$lout")"
eq "an unconfigured board_id is reported skipped, not silently dropped" "true" \
   "$(has "board (unset): board_id not configured — skipped" "$lout")"
eq "the readable board is still scanned"            "true" "$(has "card#6581 (kanban, Backlog)" "$lout")"

# ─────────────────────── PROVE-IT-CAN-FAIL: one mutant per guard ────────────────
# Each removes exactly the guard that suppresses one absence assertion above and asserts
# the suppressed card NOW appears. If a mutant did not flag it, the pristine assertion it
# is paired with was passing for some other reason and proves nothing.
echo "== prove-it-can-fail: each guard removed in turn re-surfaces the case it suppresses =="

m="$(mutant excl-code '/("inline-code", _excl_inline_code)/d')"
eq "drop the inline-code exclusion → the quoted specimen flags" "true" "$(has "card#6901 " "$m")"
eq "  … and the other exclusions still hold"                    "false" "$(has "card#6902 " "$m")"

m="$(mutant excl-strike '/("strikethrough", _excl_strikethrough)/d')"
eq "drop the strikethrough exclusion → the retracted line flags" "true" "$(has "card#6902 " "$m")"
eq "  … and the other exclusions still hold"                     "false" "$(has "card#6901 " "$m")"

m="$(mutant excl-discharge '/("discharge-line", _excl_discharge_line)/d')"
eq "drop the discharge-line exclusion → the ✅ UNBLOCKED line flags" "true" "$(has "card#6903 " "$m")"
eq "  … and the other exclusions still hold"                          "false" "$(has "card#6901 " "$m")"

m="$(mutant bare-hash 's/^_CITATION_RE = .*/_CITATION_RE = re.compile(r"(?:\\bcards?[ \\t]{0,2})?#[ \\t]{0,2}(\\d+)", re.IGNORECASE)/')"
eq "let a bare #N be a citation → the bare-hash control flags" "true" "$(has "card#6904 " "$m")"

m="$(mutant bare-behind 's/|blocks|/|blocks|behind|/')"
eq "add bare 'behind' to the marker set → the provenance line flags" "true" "$(has "card#6905 " "$m")"

m="$(mutant no-word-boundary 's/r"\\b(?:blocked/r"(?:blocked/')"
eq "drop the marker's leading word boundary → 'docblocks' flags as 'blocks'" "true" \
   "$(has "card#6908 " "$m")"

m="$(mutant no-sentence-boundary 's/or _SENTENCE_RE.*):$/or False:/')"
eq "stop honouring the sentence boundary → the '. See card#N' line flags" "true" \
   "$(has "card#6909 " "$m")"

m="$(mutant wide-window 's/^_MARKER_WINDOW = 60$/_MARKER_WINDOW = 600/')"
eq "widen the marker window → the far-marker control flags" "true" "$(has "card#6913 " "$m")"

m="$(mutant waiting-terminal 's/if lt == "done":/if lt in ("done", "waiting"):/')"
eq "treat \`waiting\` as terminal → the shipped-to-dev citer flags" "true" "$(has "card#6907 " "$m")"
eq "  … which is exactly the card the stated bound excludes"        "true" "$(has "cites card#6910" "$m")"

m="$(mutant open-is-terminal 's/if lt == "done":/if lt != "zzz":/')"
eq "treat every lane as terminal → the NEGATIVE control flags" "true" "$(has "card#6900 " "$m")"

m="$(mutant done-cards-too 's/!= "done"\]/!= "zzz"]/')"
eq "scan done cards too → the done citer flags (the population filter is live)" "true" \
   "$(has "card#7001 " "$m")"

m="$(mutant no-tenancy-gate 's/if row.get("board_id") not in self.roster_boards:/if False:/')"
# The needle is the FINDING LINE, not the bare vocabulary: the report's own scope footer
# says the word "OUT-OF-TENANT" on every run, so a bare needle would be satisfied by the
# footer and this absence assertion would pass against a tool that lost the finding.
eq "drop the tenancy gate → the out-of-tenant finding is LOST"          "false" \
   "$(has "cites card#1120 — OUT-OF-TENANT" "$m")"
eq "  … the citation degrades to an undecidable stage, not a clean line" "true" \
   "$(has "card#6915 (kanban, Backlog) cites card#1120 — UNRESOLVED" "$m")"

# ⛔ THE MEASURED CROSS-TENANT FAILURE, reproduced: with the tenancy gate gone AND the
# stage key un-qualified by board — the naive spelling — another tenant's card at stage 3
# borrows OUR board's lane type and is reported as a terminal blocker. Confident, wrong,
# and about someone else's board. Both halves are needed to produce it, which is the
# argument for keeping both.
m="$(mutant tenant-bleed 's/if row.get("board_id") not in self.roster_boards:/if False:/; s/lt = self.lane.get((bid, sid))/lt = next((v for (b, s2), v in self.lane.items() if s2 == sid), None)/')"
eq "un-qualified stage key + no tenancy gate → a WRONG flag on a foreign card" "true" \
   "$(has "cites card#1120 as a blocker" "$m")"
eq "  … and it even claims the foreign card is TERMINAL"                       "true" \
   "$(has "card#6915 (kanban, Backlog) cites card#1120 as a blocker — referent is TERMINAL" "$m")"

m="$(mutant no-cross-board 's/in scanned:/in scanned[:1]:/')"
eq "scan only the first board → the cross-board citer is NOT reported" "false" "$(has "card#7000 " "$m")"
eq "  … while the first board's positive control still is"            "true"  "$(has "card#6581 " "$m")"

_summary "kbc-stale-blocker-selftest"
