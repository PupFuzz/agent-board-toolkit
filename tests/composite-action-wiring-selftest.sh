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
# `action.yml` OR `action.yaml` in the tree, both spellings because GitHub honours both — so a
# fourth action is covered by existing, unedited code, and an assertion cannot be silently
# absent for one member.
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
# CODES: UNPARSEABLE, NOT-COMPOSITE, NO-STEPS, BAD-SHELL, NO-SCRIPT, MISSING-SCRIPT, DEAD-INPUT,
# INTERPOLATED — the full set this function can emit, kept in sync with the mutant block below,
# which drives one fixture per code. The first cut of this list omitted UNPARSEABLE and the
# mutant block was two codes short of it, so a reader had two disagreeing enumerations and both
# were wrong: a code with no mutant is a predicate nothing has watched fail.
_caw_scan() {
  python3 - "$1" "$TMP/run" <<'PY'
import os, re, sys, yaml

root, rundir = sys.argv[1], sys.argv[2]
os.makedirs(rundir, exist_ok=True)

# BOTH SPELLINGS. GitHub resolves an action directory by `action.yml` OR `action.yaml`, so a
# walk keyed on one of them answers about that FILENAME rather than about the actions this repo
# ships — and the "a fourth action is covered by unedited code" intent above fails silently for
# whichever spelling its author happens to use.
ACTION_FILES = ('action.yml', 'action.yaml')

acts = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != '.git']
    for name in ACTION_FILES:
        if name in filenames:
            acts.append(os.path.join(dirpath, name))

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
    # Every DECLARED input must reach SOME step's env. The wrapper carries no logic, so an input
    # it accepts and drops is an input that silently does nothing. The join below covers EVERY
    # step's env at once, so this is deliberately the weaker property: it cannot say an input
    # reached the step it BELONGS to, only that it reached one of them. Every action here is single-step today,
    # which is why the weaker property still holds the contract — stated so the comment does not
    # over-claim what the code checks.
    #
    # THE REFERENCED NAMES ARE PARSED, NOT SUBSTRING-TESTED. `f'inputs.{name}' in reached` reads
    # `inputs.before-sha` as a reference to an input named `before`, so an input whose name is a
    # PREFIX of a used one is silently never reported — the false negative a dead-input check
    # exists to prevent.
    referenced = set(re.findall(r'inputs\.([A-Za-z0-9_-]+)',
                                '\n'.join(str(v) for e in envs for v in e.values())))
    for name in (d.get('inputs') or {}):
        if name not in referenced:
            finding('DEAD-INPUT', name)
    # An Actions expression inside a run: body is textual substitution into the shell source —
    # the script-injection class. Inputs travel by env or not at all. The needle is BUILT so
    # this file never contains a literal one.
    if '$' + '{{' in joined:
        finding('INTERPOLATED')
    slug = re.sub(r'\.ya?ml$', '', rel).replace('/', '_')
    with open(os.path.join(rundir, slug + '.sh'), 'w') as f:
        f.write('#!/usr/bin/env bash\nset -e -o pipefail\n' + joined + '\n')
PY
}

# _caw_population <dir> — the action.yml/action.yaml set the scan walks, same walk, printed not
# recalled. Its spelling coverage is asserted, not assumed: a `.yaml` fixture below reds here.
_caw_population() {
  find "$1" \( -name action.yml -o -name action.yaml \) -not -path '*/.git/*' -printf '%P\n' | sort
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

# ── PROVE IT CAN FAIL — EVERY code has a mutant, each one edit away from a clean action ───────
# A predicate that cannot fail is a decoration, and the first cut of this block shipped two that
# could not: it claimed "one mutant per code" over 6 fixtures for 8 codes, with `NO-STEPS` and
# `UNPARSEABLE` unproven and the latter missing from the CODES list as well. The claim is now the
# thing the block below satisfies — a fixture for each of the eight, plus `NO-STEPS`'s SECOND
# emission site (a steps list with no `run:` step in it), the prefix-name case that the
# substring form of the DEAD-INPUT test could not see, and the `action.yaml` spelling.
# Each fixture is a COMPLETE action, clean except for the named defect, so a finding names that
# defect and nothing else.
echo "== prove-it-can-fail: each rule reports its own mutant =="
FIX="$TMP/fix"; mkdir -p "$FIX/bin"
cp "$ROOT/bin/release-tag-check" "$FIX/bin/release-tag-check"   # a real, executable target

_mutant() {  # _mutant <name> <yaml> [filename, default action.yml]
  mkdir -p "$FIX/$1"
  printf '%s\n' "$2" > "$FIX/$1/${3:-action.yml}"
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

_mutant no-steps "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps: []"

_mutant no-run-step "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - name: 'a step that runs no shell at all'
      uses: 'actions/checkout@v4'"

# TRUNCATED, not merely odd: the flow mapping is left open, so the parse fails at EOF — the
# shape a half-written or half-transferred file actually takes. A file the scanner cannot parse
# must be a FINDING, never a silently skipped member: an action.yml that does not load is an
# action whose whole contract went unasserted.
_mutant unparseable "name: 'm'
description: 'd'
runs:
  using: 'composite'
  steps:
    - shell: bash
      env: { A: 1,"

# THE PREFIX CASE. `before` is declared and never referenced; `before-sha` is referenced. A
# substring test reads `inputs.before-sha` as a use of `before` and reports nothing.
_mutant prefix-input "name: 'm'
description: 'd'
inputs:
  before: {description: 'declared, referenced by nobody', required: false, default: ''}
  before-sha: {description: 'b', required: true}
runs:
  using: 'composite'
  steps:
    - shell: bash
      env:
        B: \${{ inputs.before-sha }}
      run: |
$CLEAN_RUN"

# THE OTHER SPELLING. Same defect, same one edit, `action.yaml` — a walk keyed on `action.yml`
# alone finds nothing here and reports clean.
_mutant yaml-spelled "name: 'm'
description: 'd'
runs:
  using: 'node20'
  main: 'index.js'" action.yaml

rm -rf "$TMP/run"
MUT="$(_caw_scan "$FIX")"
printf '%s\n' "$MUT" | sed 's/^/  finding: /'
_code() { printf '%s\n' "$MUT" | awk -F'\t' -v d="$1/${2:-action.yml}" '$1 == d { print $2 }' | sort -u | tr '\n' ',' ; }
# _detail — the finding's THIRD column. A code alone cannot discriminate two emission sites of
# ONE code, and this file has such a pair: `NO-STEPS` is emitted for a `steps: []` list and
# again for a steps list with no `run:` step in it. With only `_code` asserted, deleting either
# predicate left the other one catching both fixtures and the whole block still passed — the
# decoration this block exists to forbid, in the block itself.
_detail() { printf '%s\n' "$MUT" | awk -F'\t' -v d="$1/${2:-action.yml}" '$1 == d { print $3 }' ; }
eq "a clean fixture yields NO finding (control)" ""                "$(_code clean)"
eq "a non-composite action is named"             "NOT-COMPOSITE,"  "$(_code not-composite)"
eq "a non-bash run step is named"                "BAD-SHELL,"      "$(_code bad-shell)"
eq "a wrapper that does not exec its bin"        "NO-SCRIPT,"      "$(_code no-script)"
eq "a wrapper pointing at an absent bin"         "MISSING-SCRIPT," "$(_code missing-script)"
eq "an input that reaches nothing"               "DEAD-INPUT,"     "$(_code dead-input)"
eq "an Actions expression in the run: body"      "INTERPOLATED,"   "$(_code interpolated)"
eq "an action declaring no steps at all"         "NO-STEPS,"       "$(_code no-steps)"
eq "…from the EMPTY-STEPS site (blank detail)"   ""                "$(_detail no-steps)"
eq "…and one whose steps run no shell"           "NO-STEPS,"       "$(_code no-run-step)"
eq "…from the NO-RUN-STEP site, not that one"    "no run: step"    "$(_detail no-run-step)"
eq "a file that does not parse is a FINDING"     "UNPARSEABLE,"    "$(_code unparseable)"
eq "an input whose NAME PREFIXES a used one"     "DEAD-INPUT,"     "$(_code prefix-input)"
# …and it names the input that is dead, not the one that is used — the detail is what an
# operator acts on, and a check reporting the wrong name is worse than one reporting none.
eq "…naming the DEAD one"                        "before" "$(_detail prefix-input)"
# The population and the scan must agree on which files ARE actions; asserting only the scan
# would leave the derivation that PRINTS the population free to disagree with it.
eq "an action.yaml is scanned like an action.yml" "NOT-COMPOSITE," "$(_code yaml-spelled action.yaml)"
eq "…and the population derivation lists it"      "true" \
   "$(has_line 'yaml-spelled/action.yaml' "$(_caw_population "$FIX")")"

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

# ── THE BATTERY ITSELF, COUNTED ───────────────────────────────────────────────────────────────
# `_summary` reports FAILURES, and a file that never ran half its assertions has none. Measured
# on this file: deleting one `eq` line dropped its check silently and it still printed `all
# checks passed` — so the harness could not tell a whole battery from a truncated one, which is
# how a `NO-STEPS` mutant that discriminated nothing survived a review round here. The count is
# the cheapest predicate that reds on a silently-dropped leg. It is a NUMBER on purpose: the
# legs are hand-written, so there is nothing to derive it from, and a derivation that read the
# file's own `eq` lines would agree with any file it was given.
#
# ⚠ EXPECTED is the count of the assertions ABOVE this line — this one is not in it. When you
# add or remove an assertion here, move this number by the same amount; a mismatch means the
# battery changed, and the only question is whether you meant it.
eq "the whole battery ran (leg count)" "22" "$checks"

_summary "composite-action-wiring-selftest"
