#!/usr/bin/env bash
# composite-action-wiring-selftest.sh — hold the wiring contract over EVERY composite action
# this repo ships, as one derived population rather than one hand-written job per action.
#
# WHY THIS FILE EXISTS (card#7203). The toolkit shipped two composite actions and gave each its
# own `*-action-selftest` job in `ci.yml`, with the shared assertions — is it still composite, is
# the step still bash, does it still exec the bin it wraps, does an input reach the script, is
# the run: body free of `${{ }}` interpolation, does that body shellcheck — written out inline in
# each. A THIRD action (`release-tag-check/`, this card) would have been the third copy of that
# block, and the copies had already drifted: only one of them asserted the no-interpolation rule,
# and the property "every declared input reaches the step's env" was enumerated by hand in one
# and absent from the other. This file makes the population the FILE SYSTEM's answer — every
# `action.yml` in the tree — so a fourth action is covered by existing, unedited code, and an
# assertion cannot be silently absent for one member.
#
# WHAT THIS DOES NOT REPLACE. The per-action jobs in `ci.yml` keep the parts that are genuinely
# about ONE action: `promote`'s flag-parity derivation (every `--flag` on an `args+=` line has a
# case arm in its script) and `release-artifacts`' input→flag map, plus each action's end-to-end
# smoke invocation on a real runner, which no local test can stand in for. Those jobs still carry
# their own copies of the SHARED assertions this file now derives — a residual duplication,
# stated rather than left to be discovered, and left in place here because editing two green CI
# jobs is a wider change than this card carries. This file is a superset guard, not their
# replacement.
#
# THE POPULATION IS PRINTED ON EVERY RUN, clean or not. A clean result over an unnamed set
# reports where the searcher stopped, not the state of the tree.
#
# THE SHELLCHECK LEG IS THE ONE WITH NO OTHER OWNER: `ci.yml`'s shellcheck job scans `bin/`,
# `hooks/` and `tests/` — never an action's embedded `run:` block, which is shell that a runner
# will execute.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$HERE/.."
SHELLCHECK="$ROOT/bin/_shellcheck-pinned"
_need -x "$SHELLCHECK"
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "python3 PyYAML is required" >&2; exit 2; }
_mktmp_scratch
# The pinned analyser caches a downloaded binary under $HOME by default, and this file runs the
# wrapper — so under `suite-home-containment-selftest.sh`'s sacrificial HOME it wrote `.cache`
# into it and that gate correctly reported the escape. Contained in the scratch instead. On a
# host or runner that already carries the pinned version on PATH the wrapper resolves it there
# and this directory is never created; where it is not, the download lands here and dies with
# the scratch rather than persisting into someone's HOME.
export SHELLCHECK_PIN_CACHE="$TMP/shellcheck-cache"

# _caw_scan <dir> — emit one TAB-separated record per finding:
#     <action.yml path relative to dir>\t<CODE>\t<detail>
# and nothing at all for a clean action. It also writes each action's run: bodies to
# $TMP/run/<slug>.sh so the shellcheck leg below can run the pinned analyser over them — a
# python-side shellcheck call would be a second way to invoke the pin.
#
# CODES: NOT-COMPOSITE, NO-STEPS, BAD-SHELL, NO-SCRIPT, MISSING-SCRIPT, DEAD-INPUT, INTERPOLATED.
_caw_scan() {
  python3 - "$1" "$TMP/run" <<'PY'
import os, re, sys, yaml

root, rundir = sys.argv[1], sys.argv[2]
os.makedirs(rundir, exist_ok=True)

acts = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != '.git']
    if 'action.yml' in filenames:
        acts.append(os.path.join(dirpath, 'action.yml'))

SCRIPT = re.compile(r'"\$GITHUB_ACTION_PATH/\.\./bin/([A-Za-z0-9._-]+)"')

for path in sorted(acts):
    rel = os.path.relpath(path, root)
    def finding(code, detail=''):
        print(f'{rel}\t{code}\t{detail}')
    try:
        d = yaml.safe_load(open(path)) or {}
    except Exception as e:                      # noqa: BLE001 - the finding IS the diagnosis
        finding('UNPARSEABLE', str(e).replace('\n', ' ')[:120])
        continue
    runs = d.get('runs') or {}
    if runs.get('using') != 'composite':
        finding('NOT-COMPOSITE', str(runs.get('using')))
        continue
    steps = runs.get('steps') or []
    if not steps:
        finding('NO-STEPS')
        continue
    bodies, envs = [], []
    for i, step in enumerate(steps):
        if 'run' not in step:
            continue
        if step.get('shell') != 'bash':
            finding('BAD-SHELL', f'step {i}: {step.get("shell")!r}')
        bodies.append(step['run'])
        envs.append(step.get('env') or {})
    if not bodies:
        finding('NO-STEPS', 'no run: step')
        continue
    joined = '\n'.join(bodies)
    # The wrapper must exec the bin it wraps, from the action's OWN checkout — not a PATH
    # lookup, which on a vendoring consumer can resolve to a different toolkit version.
    tools = SCRIPT.findall(joined)
    if not tools:
        finding('NO-SCRIPT')
    for tool in sorted(set(tools)):
        target = os.path.join(root, 'bin', tool)
        if not (os.path.isfile(target) and os.access(target, os.X_OK)):
            finding('MISSING-SCRIPT', f'bin/{tool}')
    # Every DECLARED input must reach the step it belongs to. The wrapper carries no logic, so
    # an input it accepts and drops is an input that silently does nothing.
    reached = '\n'.join(str(v) for e in envs for v in e.values())
    for name in (d.get('inputs') or {}):
        if f'inputs.{name}' not in reached:
            finding('DEAD-INPUT', name)
    # An Actions expression inside a run: body is textual substitution into the shell source —
    # the script-injection class. Inputs travel by env or not at all. The needle is BUILT so
    # this file never contains a literal one.
    if '$' + '{{' in joined:
        finding('INTERPOLATED')
    slug = rel.replace('/', '_').replace('.yml', '')
    with open(os.path.join(rundir, slug + '.sh'), 'w') as f:
        f.write('#!/usr/bin/env bash\nset -e -o pipefail\n' + joined + '\n')
PY
}

# _caw_population <dir> — the action.yml set the scan walks, same walk, printed not recalled.
_caw_population() {
  find "$1" -name action.yml -not -path '*/.git/*' -printf '%P\n' | sort
}

# ── THE POPULATION, RE-DERIVED EVERY RUN ──────────────────────────────────────────────────────
echo "== the population this run is clean over =="
POP="$(_caw_population "$ROOT")"
printf '%s\n' "$POP" | sed 's/^/  action: /'
eq "the walk finds at least one action" "false" "$([ -z "$POP" ] && echo true || echo false)"
# A NAMED WITNESS, not a count — a count pins this to today's tree and rots on the next action.
eq "…including a known member"          "true" "$(has_line 'promote/action.yml' "$POP")"

# ── THE SHIPPED TREE IS CLEAN ─────────────────────────────────────────────────────────────────
echo "== every shipped composite action holds the wiring contract =="
rm -rf "$TMP/run"
FINDINGS="$(_caw_scan "$ROOT")"
[ -z "$FINDINGS" ] && ok "no wiring findings across $(printf '%s\n' "$POP" | wc -l) action(s)" \
                   || bad "wiring findings: $(printf '%s' "$FINDINGS" | tr '\n' '|')"

echo "== each action's embedded run: body shellchecks clean under the PINNED analyser =="
# ci.yml's shellcheck job scans bin/, hooks/ and tests/ — an action's run: block is shell it
# never sees. The bodies were written out by the scan above, from the same YAML it judged.
SC_RC=0
SC_OUT="$("$SHELLCHECK" -S error "$TMP"/run/*.sh 2>&1)" || SC_RC=$?
[ "$SC_RC" = 0 ] && ok "shellcheck -S error over $(find "$TMP/run" -name '*.sh' | wc -l) extracted run: body/bodies" \
                 || bad "shellcheck reported: $SC_OUT"

# ── PROVE IT CAN FAIL — one mutant per code, each differing from a clean action by one edit ────
# A predicate that cannot fail is a decoration. Each fixture below is a COMPLETE action that is
# clean except for the named defect, so a finding names that defect and nothing else.
echo "== prove-it-can-fail: each rule reports its own mutant =="
FIX="$TMP/fix"; mkdir -p "$FIX/bin"
cp "$ROOT/bin/release-tag-check" "$FIX/bin/release-tag-check"   # a real, executable target

_mutant() {  # _mutant <name> <yaml>
  mkdir -p "$FIX/$1"
  printf '%s\n' "$2" > "$FIX/$1/action.yml"
}
CLEAN_RUN='        "$GITHUB_ACTION_PATH/../bin/release-tag-check" --before "$B" --after "$A"'

_mutant clean "name: 'clean'
description: 'a wrapper with nothing wrong with it'
inputs:
  before-sha: {description: 'b', required: true}
runs:
  using: 'composite'
  steps:
    - shell: bash
      env:
        B: \${{ inputs.before-sha }}
      run: |
$CLEAN_RUN"

_mutant not-composite "name: 'm'
description: 'd'
runs:
  using: 'node20'
  main: 'index.js'"

_mutant bad-shell "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - shell: sh
      run: |
$CLEAN_RUN"

_mutant no-script "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - shell: bash
      run: |
        release-tag-check --before x --after y"

_mutant missing-script "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - shell: bash
      run: |
        \"\$GITHUB_ACTION_PATH/../bin/no-such-tool\" --before x"

_mutant dead-input "name: 'm'
description: 'd'
inputs:
  before-sha: {description: 'b', required: true}
  orphan: {description: 'accepted and dropped', required: false, default: ''}
runs:
  using: 'composite'
  steps:
    - shell: bash
      env:
        B: \${{ inputs.before-sha }}
      run: |
$CLEAN_RUN"

_mutant interpolated "name: 'm'
description: 'd'
inputs:
  before-sha: {description: 'b', required: true}
runs:
  using: 'composite'
  steps:
    - shell: bash
      env:
        B: \${{ inputs.before-sha }}
      run: |
        \"\$GITHUB_ACTION_PATH/../bin/release-tag-check\" --before \"\${{ inputs.before-sha }}\" --after \"\$B\""

rm -rf "$TMP/run"
MUT="$(_caw_scan "$FIX")"
printf '%s\n' "$MUT" | sed 's/^/  finding: /'
_code() { printf '%s\n' "$MUT" | awk -F'\t' -v d="$1/action.yml" '$1 == d { print $2 }' | sort -u | tr '\n' ',' ; }
eq "a clean fixture yields NO finding (control)" ""                "$(_code clean)"
eq "a non-composite action is named"             "NOT-COMPOSITE,"  "$(_code not-composite)"
eq "a non-bash run step is named"                "BAD-SHELL,"      "$(_code bad-shell)"
eq "a wrapper that does not exec its bin"        "NO-SCRIPT,"      "$(_code no-script)"
eq "a wrapper pointing at an absent bin"         "MISSING-SCRIPT," "$(_code missing-script)"
eq "an input that reaches nothing"               "DEAD-INPUT,"     "$(_code dead-input)"
eq "an Actions expression in the run: body"      "INTERPOLATED,"   "$(_code interpolated)"

echo "== prove-it-can-fail: the shellcheck leg reds on a broken run: body =="
# The extracted-body path, driven end to end: a body with a real parse error must red under the
# same pinned analyser the clean legs above ran.
_mutant broken-shell "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - shell: bash
      run: |
        if [ -n \"\$X\" ]; then
        echo unterminated"
rm -rf "$TMP/run"
_caw_scan "$FIX" >/dev/null
rc=0; out="$("$SHELLCHECK" -S error "$TMP"/run/broken-shell_action.sh 2>&1)" || rc=$?
eq "a broken embedded body is rejected"          "false" "$([ "$rc" = 0 ] && echo true || echo false)"
eq "…and the analyser says why"                  "true"  "$(has 'SC1' "$out")"

_summary "composite-action-wiring-selftest"
