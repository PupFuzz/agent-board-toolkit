#!/usr/bin/env bash
# suite-home-containment-selftest.sh — the suite writes NOTHING outside its own scratch.
#
# ⛔ WHY THIS FILE EXISTS (card#7245). At 00:42 on 2026-08-22 a selftest run wrote the
# operator's LIVE host config and overwrote a prod-capable bearer token. The check written in
# response — tests/e2e-harness-containment-selftest.sh — declares its population as "every path
# kb_stub_board_config opens", and that is a SUB-POPULATION of the property it is trusted for.
# The property is the one in the first line above; the harness's write set is one member of it.
#
# THE SUB-POPULATION LET TWO LIVE MEMBERS THROUGH, both measured on this tree:
#   * tests/kbcard-field-selftest.sh called _mktmp_scratch WITHOUT --home, and bin/kbcard
#     resolves KB_LOG_FILE="${KBCARD_LOG_FILE:-$HOME/.kbcard-failures.log}" at SOURCE time — so
#     every run appended 20 fabricated HTTP-422/413/500 records (8746 bytes) to the operator's
#     live ~/.kbcard-failures.log, a triage surface. The suite was manufacturing evidence in it.
#   * tests/locale-range-guard-selftest.sh drives its probes by sourcing bin/kbcard in child
#     shells, and most of this suite's guard probes REJECT by design, so each one logged.
#
# ⛔ AND THE OBVIOUS DERIVATION — `grep -n '$HOME/' bin/ tests/` — SCORES ZERO ON BOTH.
# Neither file mentions $HOME anywhere; the path is built inside the BIN they source. A grep for
# a name answers a question about that name, not about the property. So the derivation here is
# EMPIRICAL and re-computed every run: hand each selftest a sacrificial HOME, run it, and look
# at what is sitting in that HOME afterwards. The population is re-globbed each run rather than
# listed, so a new selftest is covered the day it lands instead of the day someone remembers.
#
# A CLEAN RESULT IS ONLY EVIDENCE IF THE RUN HAPPENED. A selftest that aborts early under a
# sacrificial HOME writes nothing and looks perfectly contained, so its rc is recorded and a
# nonzero one is reported as UNMEASURED — a finding, not a pass.
#
# COST: this runs the whole suite once more (~4 min here). That is the price of measuring the
# property instead of asserting it, and the incident it exists to prevent cost a hand-restored
# production credential.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

SELF="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"
_mktmp_scratch   # NOT --home: this file hands each subject a HOME of its own.

# probe <script> — run <script> under a sacrificial HOME and a TMPDIR inside it. Sets
# PROBE_RC and PROBE_ESC (comma-joined names of everything left in that HOME, or empty).
# The handed TMPDIR is excluded: a selftest putting its scratch under $TMPDIR is doing the
# right thing, and counting it would make correct behaviour look like an escape.
PROBE_RC=0; PROBE_ESC=""
probe() {
    local script="$1" h
    h="$(mktemp -d "$TMP/home.XXXXXX")"
    mkdir -p "$h/.tmpdir"
    PROBE_RC=0
    env HOME="$h" TMPDIR="$h/.tmpdir" bash "$script" >/dev/null 2>&1 || PROBE_RC=$?
    PROBE_ESC="$(find "$h" -mindepth 1 -maxdepth 1 ! -name '.tmpdir' -printf '%f,' 2>/dev/null)"
    PROBE_ESC="${PROBE_ESC%,}"
    rm -rf "$h"
}

# ---------------------------------------------------------------------------
echo "== CONTROLS: the instrument must be able to say both words =="
# ⛔ WITHOUT THESE, A GREEN RUN BELOW IS INDISTINGUISHABLE FROM AN INSTRUMENT THAT NEVER
# LOOKED. The negative control is a script that writes exactly what the incident wrote; the
# positive one is a script that writes only inside the scratch it was given. If the first is
# not FLAGGED and the second not CLEAN, every verdict in this file is decoration.
cat > "$TMP/ctl-leaks.sh" <<'LEAK'
printf 'fabricated\n' >> "$HOME/.kbcard-failures.log"
printf 'export KBCARD_API="https://kanban.test/api/v3"\n' > "$HOME/.kanban-host.env"
LEAK
cat > "$TMP/ctl-clean.sh" <<'CLEAN'
d="$(mktemp -d)"; printf 'fabricated\n' >> "$d/.kbcard-failures.log"; rm -rf "$d"
CLEAN
cat > "$TMP/ctl-aborts.sh" <<'ABORT'
exit 3
ABORT

probe "$TMP/ctl-leaks.sh"
eq "CONTROL: a script writing \$HOME is FLAGGED"        "true" \
   "$([[ -n "$PROBE_ESC" ]] && echo true || echo false)"
eq "CONTROL: …and the escape is NAMED, not just counted" "true" \
   "$(has '.kbcard-failures.log' "$PROBE_ESC")"
eq "CONTROL: …including the host config the incident wrote" "true" \
   "$(has '.kanban-host.env' "$PROBE_ESC")"

probe "$TMP/ctl-clean.sh"
eq "CONTROL: a script writing only its own scratch is CLEAN" "" "$PROBE_ESC"

probe "$TMP/ctl-aborts.sh"
eq "CONTROL: an aborting script is caught by its rc, not read as clean" "3" "$PROBE_RC"
eq "  …and it did leave an empty HOME (which is why the rc is load-bearing)" "" "$PROBE_ESC"

# ---------------------------------------------------------------------------
echo "== the population, re-derived from the tree on every run =="
# The glob IS the derivation — no list to fall out of date, and no written number for a later
# pass to quote back instead of re-computing. This file excludes ITSELF: it runs the suite, so
# including itself is unbounded recursion, and that exclusion is asserted rather than assumed.
subjects=()
for f in "$HERE"/*selftest*.sh; do
    [[ "$(basename "$f")" == "$SELF" ]] && continue
    subjects+=("$f")
done
eq "the derivation found selftests to run" "false" \
   "$([[ "${#subjects[@]}" -eq 0 ]] && echo true || echo false)"
eq "  …and excluded itself (no recursion)" "false" \
   "$(has "$SELF" "$(printf '%s\n' "${subjects[@]##*/}")")"
printf '  ..  population re-derived from %s/*selftest*.sh: %d subject(s)\n' \
    "${HERE##*/}" "${#subjects[@]}"

echo "== every subject, under a HOME of its own =="
leaked=""; unmeasured=""
for f in "${subjects[@]}"; do
    probe "$f"
    if [[ -n "$PROBE_ESC" ]]; then
        leaked+="    ${f##*/} → ${PROBE_ESC}"$'\n'
    elif [[ "$PROBE_RC" -ne 0 ]]; then
        # Clean, but the run did not complete — so "clean" here reports where the subject
        # stopped, not what it writes. Reported separately rather than folded into the pass.
        unmeasured+="    ${f##*/} (rc ${PROBE_RC})"$'\n'
    fi
done

eq "no selftest writes outside its scratch" "" "$leaked"
[[ -n "$leaked" ]] && printf '  escapes into the sacrificial HOME:\n%s' "$leaked" >&2
eq "…and every subject actually RAN (a clean abort is UNMEASURED, not contained)" "" "$unmeasured"
[[ -n "$unmeasured" ]] && printf '  subjects whose containment was NOT measured:\n%s' "$unmeasured" >&2

_summary "suite-home-containment-selftest"
