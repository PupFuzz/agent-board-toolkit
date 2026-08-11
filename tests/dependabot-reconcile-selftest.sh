#!/usr/bin/env bash
# dependabot-reconcile-selftest.sh — network-free checks for bin/dependabot-deploy-reconcile
# and its `_dependabot-reconcile.py` implementation (card#6277).
#
# WHAT IS DRIVEN, AND HOW. The tool is exercised as a real PROCESS against a scratch HOME
# carrying a synthetic `.mcp.json`, a synthetic deployed `node_modules`, a `gh` stub and a `ps`
# stub (both copied from tests/_dependabot-*-stub.sh, so the code deciding what every assertion
# sees is itself shellchecked). Nothing here touches GitHub, and nothing here reads this host's
# real processes — a real `ps` reports whatever the host happens to be running, which is not a
# test input.
#
# EACH CHECK IS POINTED AT A FIXTURE THAT DRIVES ITS FAILING BRANCH, and almost every one is
# paired with a control that differs in exactly one input. That pairing is the point: this
# instrument's whole job is to answer UNVERIFIABLE where it cannot see, so a suite that only
# fed it healthy inputs would prove nothing about the answers that matter. Where the failing
# branch is a whole-run gate, the control is the same fixture with the one defect removed.
#
# "EACH", not "every" — that is a correction, not a hedge. This header once claimed *every*
# check drove its failing branch, and a review pass falsified it by mutating the shipped code
# and watching the suite stay green in two places: the excluded-state COUNTS were emitted over
# fixtures where all three states held 0, so hardcoding them to 0 survived; and `gh_alerts`
# calling `_validate_state` was untested, because for the only literals a real run passes the
# validated and unvalidated URLs are identical. Both are pinned below. The honest claim is the
# weaker one: no check here is known to be unable to fail, and the way to keep that true is to
# mutate the code, not to re-assert the sentence.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property these assertions support: that
# the disposition engine and the five query gates answer as specified on the inputs below. It
# proves nothing about GitHub's real response shapes (the stub's routing is an assumption
# re-derived from a live probe, not a contract), nothing about whether the alerted packages are
# the right ones to read, and nothing about node's real module resolution — only that a nested
# copy is REPORTED as ambiguous rather than silently resolved.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

BIN="$HERE/../bin/dependabot-deploy-reconcile"
HELPER="$HERE/../bin/_dependabot-reconcile.py"
_need -x "$BIN"
_need -r "$HELPER"

_mktmp_scratch
H="$TMP/home"; mkdir -p "$H"
UB="/usr/bin:/bin"
STUB="$TMP/bin"; mkdir -p "$STUB"
cp "$HERE/_dependabot-gh-stub.sh" "$STUB/gh"
cp "$HERE/_dependabot-ps-stub.sh" "$STUB/ps"
chmod +x "$STUB/gh" "$STUB/ps"

DEP="$H/deploy/examples/channel-servers"
NM="$DEP/node_modules"
MJS="$DEP/agent-webhook-bridge-channel.mjs"
IN_SCOPE="examples/channel-servers/package-lock.json"
FIX="$TMP/fixture"
PSF="$TMP/ps.txt"
OUTF="$TMP/out"; ERRF="$TMP/err"
REAL_ART="$H/.cache/coord/dependabot-reconcile"
TEST_ART="$H/.cache/coord/dependabot-reconcile-test"

# ---------------------------------------------------------------------------
# Fixture builders.
# ---------------------------------------------------------------------------

# mk_pkg <name> <version> — a top-level installed package in the synthetic deployment.
mk_pkg() {
    mkdir -p "$NM/$1"
    printf '{"name":"%s","version":"%s"}\n' "$1" "$2" > "$NM/$1/package.json"
}

# mk_deploy — the deployed tree + the MCP config that launches it. Every package.json is aged
# to -10 minutes so the staleness leg has a NEWER-than-process-start state to be driven into
# deliberately, rather than every file being "now" and the answer depending on clock luck.
mk_deploy() {
    rm -rf "$H/deploy"
    mkdir -p "$NM"
    : > "$MJS"
    printf '{"mcpServers":{"kanbanboard-agent":{"command":"node","args":["%s"]}}}\n' \
        "$MJS" > "$H/.mcp.json"
    mk_pkg hono 4.13.0
    mk_pkg fast-uri 3.1.5
    mk_pkg body-parser 2.3.0
    mk_pkg weird-pkg nightly
    find "$NM" -name package.json -exec touch -d '-10 minutes' {} +
}

# mk_ps [extra-line...] — the process table. The channel server's start time is -5 minutes:
# NEWER than every package.json above (so the healthy state is "the files predate the process")
# and OLDER than `now` (so `touch`ing one file drives the stale branch).
mk_ps() {
    local when; when="$(date -d '-5 minutes' +'%a %b %e %H:%M:%S %Y')"
    printf '%s %s node %s\n' 4242 "$when" "$MJS" > "$PSF"
    local extra
    for extra in "$@"; do printf '%s\n' "$extra" >> "$PSF"; done
}

# mk_alerts <outfile> <state> — alert specs on stdin, one per line:
#   <number>|<ecosystem>|<name>|<manifest_path>|<scope>|<first_patched|null>
mk_alerts() {
    python3 -c '
import json, sys
state = sys.argv[1]
out = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    num, eco, name, manifest, scope, patched = line.split("|")
    out.append({
        "number": int(num),
        "state": state,
        "dependency": {
            "package": {"ecosystem": eco, "name": name},
            "manifest_path": manifest,
            "scope": None if scope == "null" else scope,
        },
        "security_vulnerability": {
            "first_patched_version": None if patched == "null" else {"identifier": patched}
        },
    })
print(json.dumps(out))
' "$2" > "$1"
}

# mk_states — the three EXCLUDED state queries answer empty, and the unfiltered query answers
# the population. That is the healthy shape; cases that need the integrity gate to fire
# overwrite one of these afterwards.
mk_states() {
    printf '[]\n' > "$FIX/alerts-open.json"
    printf '[]\n' > "$FIX/alerts-dismissed.json"
    printf '[]\n' > "$FIX/alerts-auto_dismissed.json"
    cp "$FIX/alerts-fixed.json" "$FIX/alerts-nofilter.json"
}

# mk_union <outfile> <infile…> — the unfiltered query's answer built as the real UNION of the
# per-state fixtures, so the integrity gate's denominator is the sum of the populations the
# state queries actually return rather than a hand-kept count that can drift away from them.
mk_union() {
    python3 -c '
import json, sys
merged = []
for path in sys.argv[2:]:
    merged.extend(json.load(open(path)))
json.dump(merged, open(sys.argv[1], "w"))
' "$@"
}

# run_dr <args...> — run the tool under the scratch environment; sets RC, fills $OUTF/$ERRF.
# Artifacts are cleared first so "the newest artifact" is unambiguously THIS run's (run_ts has
# one-second resolution, and two runs in one second would otherwise collide).
run_dr() {
    rm -rf "$H/.cache/coord"
    RC=0
    HOME="$H" PATH="$STUB:$UB" DR_FIXTURE="$FIX" DR_PS_FIXTURE="$PSF" \
        "$BIN" "$@" >"$OUTF" 2>"$ERRF" || RC=$?
}

# art <dir> — the newest JSON artifact in <dir>, or empty when the directory does not exist.
# The `|| true` is load-bearing under `set -o pipefail`: a missing directory makes `find` exit
# non-zero, which would abort the whole suite at the assignment rather than letting the
# assertion below report an absent artifact. A harness that dies on the state a mutation
# creates reds for the wrong reason.
art() {
    { find "$1" -maxdepth 1 -name '*.json' 2>/dev/null || true; } | LC_ALL=C sort | tail -1
}

# get <file> <dotted.path> — one value out of a JSON document (numeric segments index lists).
# A string prints bare; everything else prints as JSON, so a boolean reads `true`/`false`
# rather than python's `True`/`False` and a null reads `null` rather than `None`.
get() {
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d[int(k)] if k.lstrip("-").isdigit() else d[k]
print(d if isinstance(d, str) else json.dumps(d))
' "$1" "$2"
}

# disp <file> <alert-number> — that alert's disposition, or NO-ROW.
disp() {
    python3 -c '
import json, sys
rows = json.load(open(sys.argv[1]))["rows"]
for r in rows:
    if r["alert_number"] == int(sys.argv[2]):
        print(r["disposition"]); break
else:
    print("NO-ROW")
' "$1" "$2"
}

mkdir -p "$FIX"
mk_deploy
mk_ps

# ---------------------------------------------------------------------------
# 1. The disposition engine over one population carrying every branch it can take.
# ---------------------------------------------------------------------------
echo "== the disposition engine — one population, every branch =="
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.9
3|composer|guzzlehttp/guzzle|composer.lock|runtime|7.15.2
4|npm|ghost-pkg|$IN_SCOPE|development|1.0.0
5|npm|body-parser|other/package-lock.json|runtime|2.0.0
6|npm|hono|$IN_SCOPE|runtime|null
7|npm|weird-pkg|$IN_SCOPE|runtime|1.0.0
SPECS
mk_states
run_dr
A="$(art "$REAL_ART")"
eq "a complete run exits 0 (findings are reported, never signalled by the exit code)" "0" "$RC"
eq "the artifact was written" "false" "$([ -z "$A" ] && echo true || echo false)"

# Positive control FIRST: the row set is real, so every disposition assertion below is a claim
# about a row that exists rather than about an empty document.
eq "positive control: the artifact carries one row per alert" "7" \
   "$(get "$A" scope.denominator.rows_emitted)"
eq "…over a population denominator that was measured, not assumed" "7" \
   "$(get "$A" scope.denominator.alerts_in_population)"

eq "installed above patched ⇒ FIXED_CONFIRMED" "FIXED_CONFIRMED" "$(disp "$A" 1)"
eq "installed below patched ⇒ STILL_EXPOSED" "STILL_EXPOSED" "$(disp "$A" 2)"
eq "an ecosystem with no leg in this run ⇒ named UNVERIFIABLE, never a silent skip" \
   "UNVERIFIABLE: ecosystem composer not in this run's declared leg set (npm)" "$(disp "$A" 3)"
eq "a package absent from the deployment ⇒ UNDECIDABLE" \
   "UNDECIDABLE: package not in deployment" "$(disp "$A" 4)"
eq "a manifest_path outside the leg's declared set ⇒ UNVERIFIABLE naming the path" \
   "UNVERIFIABLE: manifest_path other/package-lock.json not in leg's declared scope" "$(disp "$A" 5)"
eq "a null first_patched_version ⇒ UNDECIDABLE" \
   "UNDECIDABLE: no first_patched_version" "$(disp "$A" 6)"
eq "a non-semver installed version ⇒ UNDECIDABLE, never an ordering guess" \
   "UNDECIDABLE: non-semver version, cannot order" "$(disp "$A" 7)"

echo "== every row is annotated with the alert's OWN dependency.scope =="
eq "a runtime-scope alert carries it" "runtime" \
   "$(python3 -c 'import json,sys;print([r["scope"] for r in json.load(open(sys.argv[1]))["rows"] if r["alert_number"]==1][0])' "$A")"
# The discriminator: the annotation is READ from the alert, not assumed. A development-scope
# alert in the same run must come back different, or the field is a constant.
eq "…and a development-scope alert carries THAT, not a constant" "development" \
   "$(python3 -c 'import json,sys;print([r["scope"] for r in json.load(open(sys.argv[1]))["rows"] if r["alert_number"]==4][0])' "$A")"

echo "== the scope object is emitted into BOTH the artifact and human stdout =="
eq "the artifact carries the scope object's leg id" "bridge-npm" \
   "$(get "$A" scope.legs.0.leg_id)"
eq "stdout carries the scope object too (not artifact-only)" "true" \
   "$(has '"leg_id": "bridge-npm"' "$(cat "$OUTF")")"
eq "stdout names the artifact it wrote" "true" "$(has "$A" "$(cat "$OUTF")")"

echo "== state=fixed is a named inclusion with MEASURED exclusions (not a silent filter) =="
eq "the included state is named" "$(printf '["fixed"]')" \
   "$(get "$A" scope.alert_states_queried.included | tr -d ' \n')"
eq "the excluded states are counted, not assumed" "0" \
   "$(get "$A" scope.alert_states_queried.counts.open)"
eq "…all three of them" "0" "$(get "$A" scope.alert_states_queried.counts.dismissed)"
eq "…and the third" "0" "$(get "$A" scope.alert_states_queried.counts.auto_dismissed)"
eq "the per-state total is checked against an unfiltered query" "ok" \
   "$(get "$A" scope.alert_states_queried.sum_integrity)"

echo "== the coverage statement is a measurement, not an assumption =="
eq "this agent's own install is covered" "true" "$(get "$A" scope.legs.0.coverage_scope.0.covered)"
eq "…and the leg names the deployed path it read" "$DEP" "$(get "$A" scope.legs.0.deployed_path)"

# ---------------------------------------------------------------------------
# 2. The equality boundary, through the SHIPPED argument path (F12).
# ---------------------------------------------------------------------------
echo "== equality boundary: installed == patched is FIXED (the predicate is >=, not >) =="
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
6|npm|body-parser|$IN_SCOPE|runtime|2.3.0
SPECS
mk_states
run_dr --test-mode --inject-identity bridge-npm=body-parser@2.3.0
A="$(art "$TEST_ART")"
eq "injected == patched ⇒ rc 0" "0" "$RC"
eq "injected == patched ⇒ FIXED_CONFIRMED" "FIXED_CONFIRMED" "$(disp "$A" 6)"
eq "the injection is stamped into the scope object, never absent from the record" "2.3.0" \
   "$(get "$A" scope.injected_identity.body-parser)"

# The discriminating control: ONE patch level below the same boundary must flip. Without this
# pair, a comparator accidentally spelled `>` would pass the case above on any healthy tree.
run_dr --test-mode --inject-identity bridge-npm=body-parser@2.2.9
A="$(art "$TEST_ART")"
eq "one below the boundary ⇒ STILL_EXPOSED" "STILL_EXPOSED" "$(disp "$A" 6)"

echo "== a test-mode artifact NEVER lands in the real evidence trail (F21) =="
eq "the test-mode artifact exists" "false" "$([ -z "$(art "$TEST_ART")" ] && echo true || echo false)"
eq "…and the real artifact directory was not written at all" "true" \
   "$([ -z "$(art "$REAL_ART")" ] && echo true || echo false)"
# Witness that the real directory IS reachable from this harness — otherwise the absence above
# would also pass for a path nothing can ever write.
run_dr
eq "witness: a non-test run DOES write the real directory" "false" \
   "$([ -z "$(art "$REAL_ART")" ] && echo true || echo false)"

echo "== --inject-identity without --test-mode is a HARD ERROR, not a silent override =="
run_dr --inject-identity bridge-npm=body-parser@1.0.0
eq "rc 2 (usage error)" "2" "$RC"
eq "…naming the constraint" "true" \
   "$(has 'accepted only alongside --test-mode' "$(cat "$ERRF")")"
eq "…and nothing was written to the real artifact directory" "true" \
   "$([ -z "$(art "$REAL_ART")" ] && echo true || echo false)"
run_dr --test-mode --inject-identity bridge-npm=body-parser@1.0.0
eq "control: the SAME injection with --test-mode is accepted" "0" "$RC"

echo "== a scoped package name survives the injection parse (rpartition, not partition) =="
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
7|npm|@hono/node-server|$IN_SCOPE|runtime|2.0.5
SPECS
mk_states
run_dr --test-mode --inject-identity bridge-npm=@hono/node-server@2.0.5
A="$(art "$TEST_ART")"
eq "an @scope/name@version injection reaches the engine" "FIXED_CONFIRMED" "$(disp "$A" 7)"
run_dr --test-mode --inject-identity bridge-npm=@hono/node-server@1.19.14
A="$(art "$TEST_ART")"
eq "…and its control flips (a major below the patch is not fixed)" "STILL_EXPOSED" "$(disp "$A" 7)"

echo "== an unknown argument is refused =="
run_dr --nope
eq "unknown flag ⇒ rc 2" "2" "$RC"

# ---------------------------------------------------------------------------
# 3. The per-query gates (MF7). Each is driven into its failing branch by a fixture.
# ---------------------------------------------------------------------------
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
SPECS
mk_states

echo "== gate: the state literal comes from a validated enum =="
# A unit-level check, because the literals are internal constants: no invocation can ask this
# tool for state=Fixed, and the assertion is that the guard REFUSES one if a future edit tries.
# Both directions, so a validator that refused everything would fail the control.
#
# WHAT THE ENUM IS FOR, measured rather than assumed: this API answers 200 with `[]` for an
# UNKNOWN state value, so an unvalidated literal reads as a real empty population at a success
# status. A mis-cased KNOWN value is a different (and benign) case — the filter is applied
# case-insensitively — so `Fixed` is asserted refused because the enum is spelled in the API's
# own lower case, not because a mis-cased query would return the wrong population.
enum_probe() {
    python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    m._validate_state(sys.argv[2]); print("accepted")
except m.InstrumentError:
    print("refused")
' "$HELPER" "$1"
}
eq "the enum accepts the real literal" "accepted" "$(enum_probe fixed)"
eq "…refuses a MIS-CASED one (not the API's own spelling of the state)" "refused" "$(enum_probe Fixed)"
eq "…refuses 'all' (which this API answers 200 with [] for)" "refused" "$(enum_probe all)"
eq "…refuses an unknown one (200 with [] again — an empty population at a success status)" \
   "refused" "$(enum_probe bogus)"

# THE CALL SITE, not just the validator. `_validate_state` being correct says nothing about
# `gh_alerts` calling it: dropping the call leaves every case in this file green, because the
# only literals a real run passes are already valid, so the validated and unvalidated URLs are
# byte-identical. So this probe drives `gh_alerts` itself with `subprocess` replaced by a
# recorder — no network, no `gh` — and asserts on what the function DID: refuse before running
# anything, or run a command whose URL carries the literal.
gh_call_probe() {
    python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

ran = []
class _Completed:
    returncode = 0
    stdout = "[]"
    stderr = ""
class _Sub:
    @staticmethod
    def run(argv, **kwargs):
        ran.append(argv)
        return _Completed()
m.subprocess = _Sub          # only this module object is rebound, never the real subprocess
state = None if sys.argv[2] == "none" else sys.argv[2]
try:
    m.gh_alerts(state)
except m.InstrumentError as e:
    print("REFUSED-BEFORE-RUNNING" if not ran else "ran-then-failed: %s" % e)
else:
    print(" ".join(ran[-1]) if ran else "no-command")
' "$HELPER" "$1"
}
# Positive control first: the probe can observe a real command, so a "refused" answer below is
# the guard firing and not the probe failing to see anything.
eq "positive control: a valid state reaches gh with the literal in the query string" \
   "gh api --paginate repos/PupFuzz/agent-webhook-bridge/dependabot/alerts?state=fixed" \
   "$(gh_call_probe fixed)"
eq "…and the no-filter query sends no state literal at all" \
   "gh api --paginate repos/PupFuzz/agent-webhook-bridge/dependabot/alerts" \
   "$(gh_call_probe none)"
eq "the CALL SITE validates: an invalid literal is refused before any command runs" \
   "REFUSED-BEFORE-RUNNING" "$(gh_call_probe bogus)"

echo "== gate: every returned alert's own .state is re-asserted against the query =="
# A BOUNDARY CHECK on a remote answer, not a patch for a known bug — no live shape is known that
# produces it (a mis-cased filter is honoured case-insensitively; an unknown one answers `[]`).
# The fixture below is therefore synthetic on purpose: HTTP 200, a well-formed array, alerts
# that are not in the queried state. Only the re-assert catches that, and the reason to keep it
# is that finding out by disposing a population nobody asked for is the expensive way.
mk_alerts "$TMP/mixed.json" open <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
SPECS
cp "$TMP/mixed.json" "$FIX/alerts-fixed.json"
cp "$FIX/alerts-fixed.json" "$FIX/alerts-nofilter.json"
run_dr
eq "an unhonoured filter ⇒ rc 1 (instrument failure, not a disposition)" "1" "$RC"
eq "…and says the filter was not honoured" "true" \
   "$(has 'did not honour the filter' "$(cat "$ERRF")")"
# Control: the identical population, differing only in the state field, must run clean.
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
SPECS
mk_states
run_dr
eq "control: the same population in the QUERIED state runs clean" "0" "$RC"

echo "== gate: the command's rc is checked =="
DR_GH_RC=1 DR_GH_STDERR="gh: HTTP 401" run_dr
eq "a failing gh ⇒ rc 1" "1" "$RC"
eq "…naming the exit status and gh's own words" "true" \
   "$(has 'gh api (state=fixed) exited 1' "$(cat "$ERRF")")"
eq "…carrying gh's stderr" "true" "$(has 'HTTP 401' "$(cat "$ERRF")")"

echo "== gate: the response must PARSE, and must be an ARRAY =="
printf 'not json at all\n' > "$TMP/raw-bad.json"
DR_GH_RAW="$TMP/raw-bad.json" run_dr
eq "an unparseable body ⇒ rc 1" "1" "$RC"
eq "…saying so" "true" "$(has 'did not return parseable JSON' "$(cat "$ERRF")")"
# EMPTY stdout at rc 0 is the dangerous one and gets its own case: it is the only failure here
# that a lenient parse would turn into a well-formed EMPTY POPULATION, i.e. a confident "this
# repository has no fixed alerts" produced by a read that returned nothing at all.
: > "$TMP/raw-empty.json"
DR_GH_RAW="$TMP/raw-empty.json" run_dr
eq "an EMPTY body at rc 0 ⇒ rc 1, never an empty population" "1" "$RC"
eq "…named as unparseable rather than counted as zero alerts" "true" \
   "$(has 'did not return parseable JSON' "$(cat "$ERRF")")"
eq "…and no run reports a clean zero-alert measurement" "false" \
   "$(has 'genuinely has zero alerts' "$(cat "$OUTF")")"
printf '{"message":"Not Found"}\n' > "$TMP/raw-obj.json"
DR_GH_RAW="$TMP/raw-obj.json" run_dr
eq "an error DOCUMENT at 200 ⇒ rc 1" "1" "$RC"
eq "…named as not-an-array" "true" "$(has 'not a JSON array' "$(cat "$ERRF")")"

echo "== gate: a zero-length population is UNVERIFIABLE unless the repo is genuinely empty =="
# The five reads AGREE (0+2+1+3 == 6) so the integrity gate below is satisfied and this gate is
# the one under test — the repository holds alerts, and the queried population is empty.
#
# THE EXCLUDED STATES CARRY DISTINCT NON-ZERO COUNTS HERE, and that is this fixture's second job
# (F20). Everywhere else in this suite all three are 0, so the emitted `counts` block could have
# been hardcoded to zero — or had two of its states swapped — with nothing able to say so: the
# emitted numbers were only ever compared against a population that was empty anyway. Distinct
# non-zero values make each emitted number a claim about the state it is keyed to, and the
# genuinely-empty control below re-reads the SAME three keys as 0, so neither a constant nor a
# swap can satisfy both runs.
printf '[]\n' > "$FIX/alerts-fixed.json"
mk_alerts "$FIX/alerts-open.json" open <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
SPECS
mk_alerts "$FIX/alerts-dismissed.json" dismissed <<SPECS
3|npm|hono|$IN_SCOPE|runtime|4.12.25
SPECS
mk_alerts "$FIX/alerts-auto_dismissed.json" auto_dismissed <<SPECS
4|npm|hono|$IN_SCOPE|runtime|4.12.25
5|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
6|npm|body-parser|$IN_SCOPE|runtime|2.0.0
SPECS
mk_union "$FIX/alerts-nofilter.json" "$FIX/alerts-fixed.json" "$FIX/alerts-open.json" \
         "$FIX/alerts-dismissed.json" "$FIX/alerts-auto_dismissed.json"
run_dr
A="$(art "$REAL_ART")"
eq "empty population + a non-empty unfiltered query ⇒ rc 1" "1" "$RC"
eq "…blaming the filter rather than the repository" "true" \
   "$(has 'the filter, not the repository, produced the empty population' "$(cat "$ERRF")")"
eq "the emitted count for open is the one MEASURED for open" "2" \
   "$(get "$A" scope.alert_states_queried.counts.open)"
eq "…dismissed carries its own, different, count" "1" \
   "$(get "$A" scope.alert_states_queried.counts.dismissed)"
eq "…and auto_dismissed a third" "3" \
   "$(get "$A" scope.alert_states_queried.counts.auto_dismissed)"
eq "…while the INCLUDED state reads 0, which is what makes this run rc 1" "0" \
   "$(get "$A" scope.alert_states_queried.counts.fixed)"
eq "…and the failure is recorded with the counts, not instead of them" "6" \
   "$(get "$A" scope.alert_states_queried.unfiltered_total)"
# Control: genuinely zero alerts everywhere is a real (and clean) measurement, said out loud.
printf '[]\n' > "$FIX/alerts-open.json"
printf '[]\n' > "$FIX/alerts-dismissed.json"
printf '[]\n' > "$FIX/alerts-auto_dismissed.json"
printf '[]\n' > "$FIX/alerts-nofilter.json"
run_dr
A="$(art "$REAL_ART")"
eq "control: a genuinely empty repository ⇒ rc 0" "0" "$RC"
eq "…with the emptiness CONFIRMED rather than assumed" "true" \
   "$(has 'genuinely has zero alerts' "$(cat "$OUTF")")"
eq "…and a denominator of 0, not a missing one" "0" \
   "$(get "$A" scope.denominator.alerts_in_population)"
eq "control: the same three keys now read 0 (open)" "0" \
   "$(get "$A" scope.alert_states_queried.counts.open)"
eq "…(dismissed)" "0" "$(get "$A" scope.alert_states_queried.counts.dismissed)"
eq "…(auto_dismissed)" "0" "$(get "$A" scope.alert_states_queried.counts.auto_dismissed)"

echo "== gate: the per-state total must equal the unfiltered total (F15) =="
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
SPECS
printf '[]\n' > "$FIX/alerts-open.json"
printf '[]\n' > "$FIX/alerts-dismissed.json"
printf '[]\n' > "$FIX/alerts-auto_dismissed.json"
# A truncated read: the unfiltered query sees a third alert the four state queries do not.
mk_alerts "$FIX/alerts-nofilter.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
3|npm|body-parser|$IN_SCOPE|runtime|2.0.0
SPECS
run_dr
eq "a truncated read ⇒ rc 1" "1" "$RC"
eq "…naming both totals" "true" "$(has 'total 2 alerts while the unfiltered query returns 3' "$(cat "$ERRF")")"
A="$(art "$REAL_ART")"
eq "…and the artifact records the failure rather than a clean-looking empty run" "true" \
   "$(has 'FAILED' "$(get "$A" scope.alert_states_queried.sum_integrity)")"
# Control: the same five reads in agreement.
cp "$FIX/alerts-fixed.json" "$FIX/alerts-nofilter.json"
run_dr
eq "control: five agreeing reads ⇒ rc 0" "0" "$RC"

# ---------------------------------------------------------------------------
# 4. The installed-tree reads: nesting, staleness, process presence.
# ---------------------------------------------------------------------------
echo "== a NESTED node_modules copy makes the loaded copy ambiguous (MF2) =="
mk_alerts "$FIX/alerts-fixed.json" fixed <<SPECS
1|npm|hono|$IN_SCOPE|runtime|4.12.25
2|npm|fast-uri|$IN_SCOPE|runtime|3.1.0
SPECS
mk_states
mkdir -p "$NM/type-is/node_modules/hono"
printf '{"name":"hono","version":"1.0.0"}\n' > "$NM/type-is/node_modules/hono/package.json"
run_dr
A="$(art "$REAL_ART")"
eq "the nested-copy alert ⇒ UNVERIFIABLE naming the package" \
   "UNVERIFIABLE: nested node_modules copy of hono present — loaded copy ambiguous" "$(disp "$A" 1)"
eq "control: a sibling with NO nested copy is still disposed on its top-level read" \
   "FIXED_CONFIRMED" "$(disp "$A" 2)"
rm -rf "$NM/type-is"
run_dr
A="$(art "$REAL_ART")"
eq "control: removing the nested copy restores the top-level disposition" \
   "FIXED_CONFIRMED" "$(disp "$A" 1)"

echo "== ABSENT and UNREADABLE are different findings, not one generic answer =="
# Collapsing an unparseable package.json into "package not in deployment" would be a
# wrong-but-specific cause: the package IS installed, and what failed is the read.
printf 'not json\n' > "$NM/fast-uri/package.json"
touch -d '-10 minutes' "$NM/fast-uri/package.json"
run_dr
A="$(art "$REAL_ART")"
eq "an unparseable package.json ⇒ UNVERIFIABLE, naming the read as the fault" "true" \
   "$(has 'UNVERIFIABLE: package.json unreadable' "$(disp "$A" 2)")"
eq "control: its readable sibling is unaffected" "FIXED_CONFIRMED" "$(disp "$A" 1)"
mk_pkg fast-uri 3.1.5
touch -d '-10 minutes' "$NM/fast-uri/package.json"
run_dr
A="$(art "$REAL_ART")"
eq "control: restoring the file restores the disposition" "FIXED_CONFIRMED" "$(disp "$A" 2)"

echo "== a package.json NEWER than the running process is UNVERIFIABLE (F9) =="
# The staleness input is the mtime of each READ package.json, not the node_modules directory:
# a reinstall that rewrites one package leaves the directory mtime saying nothing about which
# file the running process actually loaded.
touch "$NM/hono/package.json"
run_dr
A="$(art "$REAL_ART")"
eq "the freshly-written package ⇒ UNVERIFIABLE" \
   "UNVERIFIABLE: package.json modified after the running process started" "$(disp "$A" 1)"
eq "control: its untouched sibling keeps its disposition (the check is per-file)" \
   "FIXED_CONFIRMED" "$(disp "$A" 2)"
touch -d '-10 minutes' "$NM/hono/package.json"
run_dr
A="$(art "$REAL_ART")"
eq "control: ageing the file back below the process start restores the disposition" \
   "FIXED_CONFIRMED" "$(disp "$A" 1)"

echo "== NO running process for this install is its own explicit disposition (F9) =="
: > "$PSF"
run_dr
A="$(art "$REAL_ART")"
eq "rc stays 0 — this is a finding about the host, not a broken instrument" "0" "$RC"
eq "every in-leg row says so" "UNVERIFIABLE: no running process for this install" "$(disp "$A" 1)"
eq "…including the second" "UNVERIFIABLE: no running process for this install" "$(disp "$A" 2)"
eq "…and the coverage statement stops claiming this install is covered" "false" \
   "$(get "$A" scope.legs.0.coverage_scope.0.covered)"
eq "…naming why" "no running process for this install" \
   "$(get "$A" scope.legs.0.coverage_scope.0.reason)"
mk_ps
run_dr
A="$(art "$REAL_ART")"
eq "control: restoring the process restores both the disposition and the coverage claim" \
   "FIXED_CONFIRMED" "$(disp "$A" 1)"
eq "…and coverage" "true" "$(get "$A" scope.legs.0.coverage_scope.0.covered)"

echo "== other installs on the host are REPORTED as uncovered, never ignored (F16) =="
# TWO foreign installs, and the second one is the assertion: it lives under a directory that
# does NOT carry the repository's name, and its launcher is not named for it either. A detector
# keyed on the repo name matches the first and silently loses the second — which is worse than
# not looking, because a coverage statement that omits an install reads as a complete one. The
# install is named by its own `install_path`, so the path pattern needs nothing but the
# channel-servers/<file>.mjs shape.
WHEN5="$(date -d '-5 minutes' +'%a %b %e %H:%M:%S %Y')"
mk_ps \
  "9999 $WHEN5 node /home/other/agent-webhook-bridge/examples/channel-servers/agent-webhook-bridge-channel.mjs" \
  "9998 $WHEN5 node /home/other/bridge-fork/examples/channel-servers/channel.mjs"
run_dr
A="$(art "$REAL_ART")"
eq "the foreign install gets its own coverage entry" \
   "/home/other/agent-webhook-bridge/examples/channel-servers" \
   "$(get "$A" scope.legs.0.coverage_scope.1.install_path)"
eq "…marked NOT covered" "false" "$(get "$A" scope.legs.0.coverage_scope.1.covered)"
eq "…with the reason stated" "true" \
   "$(has 'detected via ps' "$(get "$A" scope.legs.0.coverage_scope.1.reason)")"
eq "a foreign install under a RENAMED directory is reported too, not silently dropped" \
   "/home/other/bridge-fork/examples/channel-servers" \
   "$(get "$A" scope.legs.0.coverage_scope.2.install_path)"
eq "…also marked NOT covered" "false" "$(get "$A" scope.legs.0.coverage_scope.2.covered)"
eq "…so the host-wide statement covers three installs, not two" "3" \
   "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["scope"]["legs"][0]["coverage_scope"]))' "$A")"
mk_ps
run_dr
A="$(art "$REAL_ART")"
eq "control: with no foreign process there is exactly one coverage entry" "1" \
   "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["scope"]["legs"][0]["coverage_scope"]))' "$A")"
# …and THAT one is this agent's own install, reached through the `== launch` skip rather than by
# failing to match the pattern at all: the own install matches it too, and must not be listed twice.
eq "…which is this agent's own install, not a second copy of it" "$DEP" \
   "$(get "$A" scope.legs.0.coverage_scope.0.install_path)"

echo "== an unresolvable deployment is an instrument failure, never a guessed path =="
mv "$H/.mcp.json" "$TMP/mcp.bak"
run_dr
eq "a missing MCP config ⇒ rc 1" "1" "$RC"
eq "…naming the file" "true" "$(has '.mcp.json' "$(cat "$ERRF")")"
printf '{"mcpServers":{"kanbanboard-agent":{"command":"node","args":[]}}}\n' > "$H/.mcp.json"
run_dr
eq "an entry launching no .mjs ⇒ rc 1" "1" "$RC"
eq "…saying the directory is not derivable" "true" \
   "$(has 'not derivable' "$(cat "$ERRF")")"
cp "$TMP/mcp.bak" "$H/.mcp.json"
run_dr
eq "control: restoring the config restores a clean run" "0" "$RC"

# ---------------------------------------------------------------------------
# 5. The comparator, and the two static properties.
# ---------------------------------------------------------------------------
echo "== the comparator orders by SemVer precedence, not lexically =="
cmp_probe() {
    python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dr", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
a, b = m.semver_key(sys.argv[2]), m.semver_key(sys.argv[3])
print("undecidable" if a is None or b is None else str(a >= b).lower())
' "$HELPER" "$1" "$2"
}
# 10.9.0 vs 10.10.0 is the discriminator: a string compare answers "10.9.0" > "10.10.0".
eq "10.10.0 >= 10.9.0" "true" "$(cmp_probe 10.10.0 10.9.0)"
eq "10.9.0 >= 10.10.0 is FALSE (a lexical compare would say true)" "false" "$(cmp_probe 10.9.0 10.10.0)"
eq "equality satisfies >=" "true" "$(cmp_probe 2.3.0 2.3.0)"
eq "a major below the patch is exposed" "false" "$(cmp_probe 1.19.14 2.0.5)"
eq "a release outranks its own pre-release" "true" "$(cmp_probe 3.0.0 3.0.0-rc.1)"
eq "…and the pre-release does not outrank the release" "false" "$(cmp_probe 3.0.0-rc.1 3.0.0)"
eq "a leading v is tolerated on either side" "true" "$(cmp_probe v3.1.5 3.1.4)"
eq "a non-semver version is not ordered at all" "undecidable" "$(cmp_probe nightly 1.0.0)"

echo "== the tool runs NO git command, network or otherwise (F19) =="
# A static assertion, because the property is "this never happens" and no fixture can witness
# an absence. Each direction carries its own witness — an absence measured by a probe that has
# not been shown able to fire is not a measurement.
#
# The python side asserts the EXECUTED BINARY SET rather than the absence of a word: the helper
# runs everything through literal `subprocess.run([...])` argument lists, so the first element
# of each is the complete set of programs it can start. A word-absence grep would instead be
# satisfied or defeated by prose (this file's own header discusses git tags).
py_execs() {
    grep -oE 'subprocess\.run\(\["[a-z0-9_.-]+"' "$HELPER" | sed 's/.*\["//; s/"$//' \
        | LC_ALL=C sort -u
}
# Captured into a variable rather than piped straight into `grep -q`: under `set -o pipefail`
# an early-exiting consumer can leave the producer's SIGPIPE as the pipeline's status, and the
# `&& echo true || echo false` would then report a MATCH as false.
execs="$(py_execs)"
eq "positive control: the executed-binary set is non-empty and carries a known member" "true" \
   "$(printf '%s\n' "$execs" | grep -qx 'gh' && echo true || echo false)"
eq "the implementation executes exactly gh and ps — no git, and no shell to hide one in" \
   "$(printf 'gh\nps')" "$execs"
# The wrapper is bash, so the probe is a command-word match over comment-stripped source.
bash_git() { sed 's/#.*//' "$1" | grep -cE '(^|[[:space:]]|;|\||&|\()git[[:space:]]' || true; }
eq "the wrapper runs no git either" "0" "$(bash_git "$BIN")"
eq "witness: the same probe DOES fire on a bin that runs git" "false" \
   "$([ "$(bash_git "$HERE/../bin/board-card-start")" = 0 ] && echo true || echo false)"

_summary "dependabot-reconcile-selftest"
