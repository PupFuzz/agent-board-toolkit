#!/usr/bin/env bash
# _composite-step-run.sh — run a composite action's `run:` step the way the runner would, so a
# CI step can capture its exit status and output. Exits with the step's own status.
#
#   tests/_composite-step-run.sh <action-dir> [--input <name>=<value>]... [--env <KEY>=<value>]...
#
# WHY IT EXISTS (card#9022). The repo's `continue-on-error` guard has no exemption, and a step
# that `uses:` a composite action fails its job when the action fails. So the composite
# smoke tests in `ci.yml` cannot run their EXPECTED-FAILURE direction through `uses:`. This
# script stands in for the runner in that direction. It reads `<action-dir>/action.yml`, takes
# the action's one `run:` step, builds that step's `env:` from the inputs as the runner does, and
# runs the body the way the runner runs `shell: bash` (`bash --noprofile --norc -eo pipefail`)
# with $GITHUB_ACTION_PATH set to the action directory. The body under test is the shipped text,
# read from the file and not copied: a wrapper edit that swallows the script's status, drops a
# flag, or stops calling the script changes what this runs.
#
# HOW AN ENV VALUE IS RESOLVED:
#   * `${{ inputs.<name> }}`, and nothing else in the value → the `--input` given for <name>,
#     otherwise the input's declared `default`, otherwise "". That is the runner's rule for a
#     composite input. A `--input` that names an undeclared input is refused, so a typo cannot
#     silently fall back to the default.
#   * ANY other value containing an expression (e.g. promote's `GITHUB_TOKEN`, which is
#     `inputs.require-complete == 'true' && github.token || ''`) must be supplied with
#     `--env KEY=value`, or this refuses. It does not evaluate Actions expressions, and it
#     says so rather than guessing one.
#   * A literal value with no expression passes through as written.
#
# WHAT IT REFUSES, at exit 64, rather than run a step it would model wrongly:
#   * a step key other than `name`, `id`, `shell`, `env` and `run` — `if:`, `working-directory:`,
#     `continue-on-error:` and the rest each change what the runner does with the step;
#   * a shell other than bash, or more or fewer than one step;
#   * `${{` anywhere in the `run:` body (the runner substitutes it before bash runs);
#   * an input whose declared `default` is not a string;
#   * an env value holding any expression other than a bare `${{ inputs.<name> }}`, unless the
#     caller supplies it with `--env`; and a `--input` naming an undeclared input.
# `tests/composite-step-run-selftest.sh` plants a fixture for each of these.
#
# WHAT THIS DOES NOT STAND IN FOR. It does not show that the runner evaluates
# `${{ inputs.X }}` into the step env, or that the runner fails a calling step when the composite
# exits non-zero. Both are runner behaviour. The first is covered where the same action also runs
# through `uses:` on a path expected to succeed, for the inputs that path discriminates (`ci.yml`
# states which, per job). The second is GitHub's, and nothing in this repository exercises it.
#
# Refusals of its own exit 64 with a `_composite-step-run:` prefix, so they cannot be read as the
# action's status.
set -euo pipefail

die() { echo "_composite-step-run: $*" >&2; exit 64; }

[ $# -ge 1 ] || die "usage: $0 <action-dir> [--input name=value]... [--env KEY=value]..."
ACTION_DIR="$(cd "$1" 2>/dev/null && pwd)" || die "no such action directory: $1"
shift

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

python3 - "$ACTION_DIR" "$SCRATCH" "$@" <<'PY' || exit $?
import os, re, sys, yaml

def die(msg):
    print(f'_composite-step-run: {msg}', file=sys.stderr)
    sys.exit(64)

action_dir, scratch, args = sys.argv[1], sys.argv[2], sys.argv[3:]
meta = None
for name in ('action.yml', 'action.yaml'):
    p = os.path.join(action_dir, name)
    if os.path.isfile(p):
        meta = p
        break
if meta is None:
    die(f'no action.yml / action.yaml in {action_dir}')
d = yaml.safe_load(open(meta)) or {}
runs = d.get('runs') or {}
if runs.get('using') != 'composite':
    die(f'{meta}: runs.using is {runs.get("using")!r}, not composite')
steps = runs.get('steps') or []
if len(steps) != 1 or 'run' not in steps[0]:
    die(f'{meta}: this runner stand-in handles exactly one run: step; the action has '
        f'{len(steps)} step(s). Extend it before relying on it here.')
step = steps[0]
# Every step key this runs is read below; any other key changes what the runner does with the step
# (`if:` can skip it, `working-directory:` moves it, `continue-on-error:` hides its failure), and
# ignoring it would let a failure test pass for a step the runner would not run this way.
STEP_KEYS = {'name', 'id', 'shell', 'env', 'run'}
extra = sorted(set(step) - STEP_KEYS)
if extra:
    die(f'{meta}: the step carries {extra}, which this does not model; it reads only '
        f'{sorted(STEP_KEYS)}')
if step.get('shell') != 'bash':
    die(f'{meta}: shell is {step.get("shell")!r}; only bash is run here')
if not isinstance(step.get('run'), str):
    die(f'{meta}: run: is not a string')
if '${{' in step['run']:
    die(f'{meta}: the run: body contains an Actions expression, which the runner substitutes '
        f'into the script before bash sees it; this does not evaluate expressions')

declared = d.get('inputs') or {}
for n, spec in declared.items():
    if isinstance(spec, dict) and 'default' in spec and not isinstance(spec['default'], str):
        die(f'{meta}: input {n!r} has a non-string default {spec["default"]!r}; how the runner '
            f'renders it into the env is not modelled here — quote it')
given, overrides = {}, {}
it = iter(args)
for a in it:
    if a not in ('--input', '--env'):
        die(f'unknown argument {a!r}')
    kv = next(it, None)
    if kv is None or '=' not in kv:
        die(f'{a} needs <name>=<value>')
    k, v = kv.split('=', 1)
    if a == '--input':
        if k not in declared:
            die(f'--input {k!r} is not an input of {meta}')
        given[k] = v
    else:
        overrides[k] = v

PLAIN = re.compile(r'^\$\{\{\s*inputs\.([A-Za-z0-9_-]+)\s*\}\}$')
env = {}
for k, v in (step.get('env') or {}).items():
    if k in overrides:
        env[k] = overrides.pop(k)
        continue
    v = str(v)
    m = PLAIN.match(v.strip())
    if m:
        n = m.group(1)
        if n not in declared:
            die(f'env {k} references undeclared input {n!r}')
        env[k] = given.get(n, (declared[n] or {}).get('default', ''))
    elif '${{' in v:
        die(f'env {k} is the expression {v!r}, which this does not evaluate; pass --env {k}=<value>')
    else:
        env[k] = v
if overrides:
    die(f'--env names keys the step does not declare: {sorted(overrides)}')

with open(os.path.join(scratch, 'body.sh'), 'w') as f:
    f.write(step['run'])
with open(os.path.join(scratch, 'env'), 'wb') as f:
    for k, v in env.items():
        f.write(k.encode() + b'=' + v.encode() + b'\0')
PY

declare -a ENV_ARGS=()
while IFS= read -r -d '' kv; do ENV_ARGS+=("$kv"); done < "$SCRATCH/env"

rc=0
env ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} GITHUB_ACTION_PATH="$ACTION_DIR" \
  bash --noprofile --norc -eo pipefail "$SCRATCH/body.sh" || rc=$?
exit "$rc"
