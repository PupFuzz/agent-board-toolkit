#!/usr/bin/env bash
# python-syntax-gate-selftest.sh — CI's python syntax gate must not WRITE bytecode, and must not
# be weaker than the `py_compile` it replaced.
#
# WHAT IT GUARDS (card#7207). `.github/workflows/ci.yml`'s "python shims compile clean" step ran
# `python3 -m py_compile bin/*.py`. `py_compile` writes the bytecode it produces beside each
# source — i.e. into `bin/__pycache__` — and `docs/INSTALL.md` §2 installs this toolkit by
# globbing `bin/*` and symlinking each entry onto PATH, so a non-tool directory there is a defect
# the moment it exists (card#6871, and downstream card#7234's `RESULT=NOT_INSTALLED` refusal).
# card#6871 stopped the `bin/*.py` ENTRY POINTS minting it and did not touch this step, so the
# fix was being defeated on every hand-run of these gates. Measured on the reference host the day
# this was filed: `bin/__pycache__` was already present, and re-minted at rc 0.
#
# ⛔ WHY CI WAS BLIND TO IT, which is the reason this file exists rather than a code comment. A
# GitHub runner's checkout is disposable, so the directory costs nothing there, and `.gitignore`
# keeps it out of `git status`. Every instrument the repo had read green. The damage is LOCAL —
# on the seat that runs these gates by hand before opening a PR, which is the documented
# workflow here — and surfaces later as an unrelated-looking install failure.
#
# ⛔ THE FIRST PROPOSED FIX WAS A LOOSENING, and leg 3 is what keeps it from being re-adopted.
# `ast.parse` writes nothing, but it answers a WEAKER question than `py_compile`. Measured on
# python 3.12.3, `ast.parse` ACCEPTS `return` / `break` / `continue` / `yield` / `await` outside
# their construct, `def f(a, a)`, an unbound `nonlocal`, and `*a = [1]` — eight of the ten error
# classes `py_compile` rejects. `compile(src, f, 'exec')` is `py_compile`'s own check MINUS the
# write: it rejects all ten and caches nothing. Leg 3 plants a COMPILE-STAGE error specifically —
# a file `ast.parse` would wave through — so a future "simplification" to `ast.parse` reds here
# instead of silently shrinking what the gate proves.
#
# THE GATE IS EXTRACTED, NEVER RESTATED. Legs 2–6 run the `run:` block out of `ci.yml` itself,
# located by STEP NAME, verbatim, in a scratch directory carrying its own `bin/*.py`. A copy of
# the command in this file would be a second thing that can disagree with the one CI runs — this
# repository's recurring defect (card#5389, card#5740, card#5355) — and it would go green against
# its own copy while the shipped step rotted.
#
# THE POPULATION OF LEG 1 IS THE WHOLE EXECUTABLE SURFACE, re-derived every run and NOT DERIVED
# HERE: `tests/_gha-surface-lib.sh` owns "which YAML documents does GitHub Actions execute in this
# repository" for the three gates that ask it — every `*.yml` AND `*.yaml` in `.github/workflows/`,
# plus every `action.yml`/`action.yaml` at any depth under the root — and this file collects EVERY
# value under a `run:` key wherever it sits in each of those documents. There is no list of files
# here, so a sixth workflow or a third composite action is covered on the next run with no edit.
# Fixing the one site without that rule leaves the next hand to re-mint the artifact (card#7207 IS
# the instance of card#6871 being re-minted by an unguarded second site).
#
# ⛔ THE FIRST CUT OF THIS FILE GLOBBED `*.yml` ONLY, and that is why the derivation is shared now
# rather than spelled here. GitHub loads `.yaml` on exactly the same terms; measured, a planted
# `.github/workflows/sneak.yaml` running `python3 -m py_compile bin/*.py` passed this file at
# `all checks passed` while the identical file renamed `.yml` reds it — an absence verdict over a
# population smaller than the one the file claimed. Two sibling gates
# (`ci-matrix-parity-selftest.sh`, `shellcheck-pin-selftest.sh`) already read both spellings, so the
# repair was not a third correction but ONE owner all three call (canon #5). The planted pair below
# is now a planted TRIPLE — both extensions and a NESTED action — through that same owner.
#
# ⛔ BOUNDS, stated so this is not over-cited:
#   * Leg 1 keys on the TOKENS `py_compile` and `compileall`. It cannot see a bytecode write
#     reached some other way — a `run:` block that execs a script which imports a repo module, or
#     an `uses:` third-party action. What closes THAT direction is the empirical census in legs
#     4–5 over the gate this repo actually runs, plus `bin-artifact-hygiene-selftest.sh` over the
#     entry points. Neither subsumes the other.
#   * YAML COMMENTS ARE INVISIBLE HERE, deliberately — pyyaml drops them before this sees the
#     document. `ci.yml`'s own step comment explains at length why `py_compile` is not used, and
#     a scanner reading raw text would red on that prose. The rule is about what RUNS.
#   * It says nothing about whether the syntax check is the RIGHT check, only that it is not a
#     weaker one than the compile it replaced and that it writes nothing.
#   * Leg 4's ValueError arm is UNEXERCISED BY A REAL INTERPRETER HERE, and is driven by a stub
#     instead — see the leg. It is the arm, not the outcome, that is version-specific.
#
# LEG 4 IS ABOUT THE EXCEPTION CLASSES, not the verdict, and it exists because the failing path
# had two defects that a green `rc 1` hid completely. A source containing a NUL byte is rejected by
# a class that MOVED: CPython gh-96670 — "the parser now raises SyntaxError when parsing source
# code containing null bytes", quoted from the NEWS file shipped with the 3.12.3 interpreter this
# was measured on. MEASURED here: `SyntaxError`, `lineno` None, so a one-class `except SyntaxError`
# printed `line=None`, a location that does not exist. On an interpreter raising the other class
# (documented as `ValueError`; UNVERIFIED here — this box has only 3.12) it escapes as an uncaught
# traceback, which ABORTS THE LOOP and leaves every later file UNCHECKED at an exit status that
# still reads 1. So the leg asserts the three OBSERVABLE properties — reported, later files still
# checked, no phantom location — rather than the interpreter's classification, which is the part
# that moves under it.
#
# HOW EACH LEG IS SEEN TO FAIL. Legs 1 and 6 are assertions of ABSENCE, which pass for free when
# the thing that would create the artifact never ran:
#   * leg 1 carries planted fixtures — workflows that DO call `py_compile`/`compileall` in BOTH
#     extensions and in a nested composite action (each must be flagged) beside a clean twin (must
#     not) — and a named witness that the live derivation read real data at all, rather than
#     answering the empty set from a moved directory.
#   * leg 6's absence of `__pycache__` is paired with a CONTROL that runs `py_compile` over the
#     same fixture tree and asserts the directory DOES appear. Without it the leg passes equally
#     when the gate command never executed.
#   * `PYTHONDONTWRITEBYTECODE=1` — which `_selftest-prelude.sh` exports for the whole suite — is
#     CLEARED for every probe here. Left set, it would suppress the control's write too, and this
#     file would certify a property of the environment instead of a property of the gate.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_gha-surface-lib.sh"

ROOT="$(cd "$HERE/.." && pwd)"
CI_YML="$ROOT/.github/workflows/ci.yml"
STEP_NAME="python shims compile clean"
_need -r "$CI_YML"
_mktmp_scratch

# _run_blocks <path>... — every value under a `run:` key, anywhere in each document, one block
# per `\0`-terminated record. One recursive walk for workflows and composite actions alike: a
# structure-specific extractor would answer the empty set for whichever shape it did not know.
_run_blocks() {
    python3 - "$@" <<'PY'
import sys, yaml

def walk(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == 'run' and isinstance(v, str):
                out.append(v)
            walk(v, out)
    elif isinstance(node, list):
        for v in node:
            walk(v, out)

out = []
for path in sys.argv[1:]:
    with open(path) as fh:
        walk(yaml.safe_load(fh) or {}, out)
# TERMINATED, not joined. `'\0'.join(…)` leaves the LAST record without a delimiter, and
# `read -r -d ''` returns non-zero at EOF — so a `while read` loop drops it. For a file with a
# single run: block that is the whole file, silently. The planted control in leg 1 is what
# caught this; it was written as a join first.
sys.stdout.write(''.join(b + '\0' for b in out))
PY
}

# _writers <path>... — the bytecode-WRITING invocations among those run blocks, one `path: line`
# per line. The PATH as handed in, never a basename: the population now reaches composite actions
# at any depth, and every one of them is called `action.yml`.
# `py_compile` and `compileall` are the two stdlib entry points whose whole purpose is to emit a
# `.pyc`; nothing else in the stdlib writes one without being imported.
# A HERESTRING, not `printf … | while read` — the prelude's standing rule against a pipeline
# whose reader can leave early, and it also keeps the loop out of a subshell.
_writers() {
    local f block line
    for f in "$@"; do
        while IFS= read -r -d '' block; do
            while IFS= read -r line; do
                case "$line" in
                    *py_compile*|*compileall*)
                        printf '%s: %s\n' "$f" "${line#"${line%%[![:space:]]*}"}" ;;
                esac
            done <<< "$block"
        done < <(_run_blocks "$f")
    done
}

echo "== leg 1: no run: block in the executable surface writes bytecode =="

# The population, re-derived every run through the shared owner — BOTH workflow extensions, and
# composite actions at any depth. `-print0` is not needed: these names are repo-controlled and
# carry no whitespace. The derivation IS the coverage, and it is asserted non-empty below.
mapfile -t SURFACE < <(
    _gha_workflow_files "$ROOT/.github/workflows"
    _gha_action_files "$ROOT"
)

eq "the surface derivation found files (positive control on the population)" "false" \
   "$([[ "${#SURFACE[@]}" -eq 0 ]] && echo true || echo false)"

# NAMED WITNESS, not a count: a count pins this to a past value and rots the moment a workflow is
# added. `_shellcheck-pinned` is a token that lives in a `run:` block of the live tree — if the
# walk cannot see it, the walk is broken and every absence below is vacuous.
live_blocks="$(_run_blocks "${SURFACE[@]}" | tr '\0' '\n')"
eq "the run:-block walk reads real data (named witness)" "true" \
   "$(has '_shellcheck-pinned' "$live_blocks")"

eq "no run: block invokes py_compile or compileall" "" "$(_writers "${SURFACE[@]}")"

# PROVE-IT-CAN-FAIL — planted fixtures through the SAME derivation the live population goes
# through (a fixture ROOT, not a hand-written file list), so what is certified is the check that
# actually runs, ON THE POPULATION IT ACTUALLY DERIVES. The `.yaml` twin is not decoration: this
# file globbed `*.yml` alone until card#7207's review, and the identical dirty workflow spelled
# `.yaml` was invisible to it while GitHub ran it exactly the same way.
mkdir -p "$TMP/surf/.github/workflows" "$TMP/surf/deep/nested"
_plant_dirty() {   # <path> <token-invocation>
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<YML
name: dirty
on: [pull_request]
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - name: mints bytecode
        run: $2
YML
}
_plant_dirty "$TMP/surf/.github/workflows/dirty.yml"  'python3 -m py_compile bin/*.py'
_plant_dirty "$TMP/surf/.github/workflows/dirty.yaml" 'python3 -m py_compile bin/*.py'
_plant_dirty "$TMP/surf/deep/nested/action.yaml"      'python3 -m compileall bin'
cat > "$TMP/surf/.github/workflows/clean.yml" <<'YML'
name: clean
on: [pull_request]
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - name: writes nothing
        run: python3 -c 'compile(open("x.py","rb").read(), "x.py", "exec")'
YML

mapfile -t FIXTURE < <(
    _gha_workflow_files "$TMP/surf/.github/workflows"
    _gha_action_files "$TMP/surf"
)
# The derived population FIRST, named: `_writers` answering "" would otherwise be as consistent
# with a derivation that found nothing as with a clean tree — the same trap leg 1 itself is built
# around. C-collated, so `.yaml` sorts ahead of `.yml`.
eq "control: the derivation reaches both extensions and a nested action" \
   "$TMP/surf/.github/workflows/clean.yml
$TMP/surf/.github/workflows/dirty.yaml
$TMP/surf/.github/workflows/dirty.yml
$TMP/surf/deep/nested/action.yaml" \
   "$(printf '%s\n' "${FIXTURE[@]}")"
eq "control: every dirty spelling IS flagged, and the clean twin is NOT" \
   "$TMP/surf/.github/workflows/dirty.yaml: python3 -m py_compile bin/*.py
$TMP/surf/.github/workflows/dirty.yml: python3 -m py_compile bin/*.py
$TMP/surf/deep/nested/action.yaml: python3 -m compileall bin" \
   "$(_writers "${FIXTURE[@]}")"

echo "== legs 2-6: the SHIPPED gate command, extracted from ci.yml by step name =="

GATE="$(python3 - "$CI_YML" "$STEP_NAME" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
hits = [s for j in d['jobs'].values() for s in j.get('steps', [])
        if s.get('name') == sys.argv[2]]
if len(hits) != 1:
    sys.exit(f"expected exactly 1 step named {sys.argv[2]!r}, found {len(hits)}")
sys.stdout.write(hits[0]['run'])
PY
)"

# The extraction is the premise of every leg below; an empty or renamed step must red HERE and
# not as four mysterious rc failures.
eq "the '$STEP_NAME' step was extracted from ci.yml" "true" \
   "$([[ -n "$GATE" ]] && echo true || echo false)"
eq "the extracted block invokes python3" "true" "$(has 'python3' "$GATE")"

# _gate_rc — run the SHIPPED block verbatim, in a scratch tree whose `bin/` holds the fixtures.
# No string surgery on the command: retargeting it by editing `bin/*.py` would be a second
# spelling of the thing under test.
#
# ⛔ PYTHONDONTWRITEBYTECODE is cleared: see the header. `env -u` is per-probe, so the suite-wide
# export the prelude makes is untouched for everything else.
_gate_rc() { ( cd "$TMP/probe" && env -u PYTHONDONTWRITEBYTECODE bash -c "$GATE" >/dev/null 2>&1 ); }

# _gate_run [VAR=value...] — the same invocation, keeping what it SAID: rc in GRC, the annotation
# stream in `$TMP/gate.err`. Leg 4 asserts on the annotations, which `_gate_rc` discards; any extra
# arguments are handed to the same `env`, which is how the stub in 4b is put in front of it without
# any string surgery on `$GATE`.
GRC=0
_gate_run() {
    GRC=0
    ( cd "$TMP/probe" && env -u PYTHONDONTWRITEBYTECODE "$@" bash -c "$GATE" ) \
        >"$TMP/gate.out" 2>"$TMP/gate.err" || GRC=$?
}
_has_nul() { python3 -c 'import sys; print("true" if b"\0" in open(sys.argv[1],"rb").read() else "false")' "$1"; }
_pycache() { find "$TMP/probe" -type d -name __pycache__ | LC_ALL=C sort; }

mkdir -p "$TMP/probe/bin"
# A PEP 263 coding cookie is in the clean fixture on purpose: `py_compile` decodes the source
# before compiling, and a replacement that hands `compile()` an already-decoded `str` would trip
# over `SyntaxError: encoding declaration in Unicode string`. That would be a false RED on a
# valid file — a different way of not answering the same question.
printf '# -*- coding: latin-1 -*-\nCAFE = "caf\xe9"\n\n\nif __name__ == "__main__":\n    print(CAFE)\n' \
    > "$TMP/probe/bin/_clean.py"

echo "== leg 2: a valid tree passes (and a coding cookie is not a false red) =="
expect_rc "the gate accepts a syntactically valid bin/" 0 _gate_rc

echo "== leg 3: NO WEAKENING — both error classes still red =="
# 3a: a plain parse error. `ast.parse` catches this one too; it is the floor, not the discriminator.
printf 'def f(:\n    pass\n' > "$TMP/probe/bin/_bad.py"
expect_rc "the gate REJECTS a bare syntax error" 1 _gate_rc
rm -f "$TMP/probe/bin/_bad.py"

# 3b: THE DISCRIMINATOR. `return` at module level parses fine and fails at the COMPILE stage, so
# `ast.parse` accepts it and `py_compile` does not. This is the leg that reds if the gate is ever
# swapped for a parse-only check — the loosening card#7207 declined to make.
printf 'return 1\n' > "$TMP/probe/bin/_bad.py"
expect_rc "the gate REJECTS a compile-stage error (ast.parse would ACCEPT this)" 1 _gate_rc
rm -f "$TMP/probe/bin/_bad.py"

echo "== leg 4: a file the compiler rejects with NO LINE still reports, and does not end the run =="
# 4a: THE REAL CASE ON THIS INTERPRETER — a NUL byte in the source. `_z_bad.py` sorts after it in
# the `bin/*.py` glob and is the witness that the loop reached the END of its population: the
# defect this closes is a first file that kills the loop while the exit status still says 1, i.e.
# every later file UNCHECKED and nothing on any channel saying so.
printf 'A = 1\x00\n' > "$TMP/probe/bin/_a_nul.py"
printf 'return 1\n'   > "$TMP/probe/bin/_z_bad.py"
eq "witness: the fixture really holds a NUL byte" "true" "$(_has_nul "$TMP/probe/bin/_a_nul.py")"
_gate_run
err="$(cat "$TMP/gate.err")"
eq "the gate REJECTS it" "1" "$GRC"
eq "the NUL-byte file is named in an annotation" "true" "$(has 'file=bin/_a_nul.py' "$err")"
eq "the LATER file was still checked (the loop did not abort)" "true" "$(has 'file=bin/_z_bad.py' "$err")"
eq "no annotation points at a location that does not exist" "false" "$(has 'line=None' "$err")"
eq "…and nothing escaped as a traceback" "false" "$(has 'Traceback' "$err")"
rm -f "$TMP/probe/bin/_a_nul.py" "$TMP/probe/bin/_z_bad.py"

# 4b: THE `ValueError` ARM, DRIVEN — and it is driven by a stub because on THIS interpreter no
# input can reach it. CPython gh-96670 made the parser answer the NUL byte with `SyntaxError` from
# 3.12 on, so 4a takes the OTHER arm here, and the one that keeps the gate whole on an interpreter
# answering with `ValueError` (a runner image, or a maintainer's box — which is where these gates
# are run by hand) would be entered by nothing. A
# `sitecustomize` on PYTHONPATH — the repo's own stub idiom, and the ONLY channel that reaches the
# heredoc without editing it — raises a real `ValueError` out of a real `compile()` call for one
# marked fixture. Without this the arm is a decoration: an `except` clause nothing has entered.
mkdir -p "$TMP/vestub"
cat > "$TMP/vestub/sitecustomize.py" <<'PY'
import builtins
_real = builtins.compile
MARK = b"VALUEERROR-ARM-FIXTURE"

def compile(source, filename, mode, *a, **kw):
    raw = source if isinstance(source, bytes) else source.encode()
    if MARK in raw:
        raise ValueError("stubbed ValueError out of compile()")
    return _real(source, filename, mode, *a, **kw)

builtins.compile = compile
PY
printf 'MARKER = "VALUEERROR-ARM-FIXTURE"\n' > "$TMP/probe/bin/_a_ve.py"
printf 'return 1\n'                          > "$TMP/probe/bin/_z_bad.py"
_gate_run PYTHONPATH="$TMP/vestub"
err="$(cat "$TMP/gate.err")"
eq "the gate REJECTS the ValueError file" "1" "$GRC"
# The stub's own message is the positive control: it can only appear if a real ValueError really
# came out of the gate's `compile()` and was really caught by the arm under test. It also pins the
# two things the arm has to get right — NO `line=` field, and a message read off an exception that
# has no `.msg`.
eq "the ValueError arm reported it, with no line field and the exception's own text" "true" \
   "$(has '::error file=bin/_a_ve.py::stubbed ValueError out of compile()' "$err")"
eq "the LATER file was still checked (the loop did not abort)" "true" "$(has 'file=bin/_z_bad.py' "$err")"
eq "…and nothing escaped as a traceback" "false" "$(has 'Traceback' "$err")"
# The stub is scoped to that one invocation: with the syntax error cleared and ONLY the marked
# fixture left, the next probe must compile it for real. A stub leaking into the rest of the file
# would make every later probe a measurement of the stub.
rm -f "$TMP/probe/bin/_z_bad.py"
_gate_run
eq "control: without PYTHONPATH the marked fixture compiles clean (the stub is not global)" "0" "$GRC"
rm -f "$TMP/probe/bin/_a_ve.py"

echo "== leg 5: a clean tree still passes after the failures (the gate is not stuck red) =="
expect_rc "the gate accepts the valid tree again" 0 _gate_rc

echo "== leg 6: the gate minted NO bytecode across any of the runs above =="
eq "no __pycache__ anywhere under the probe tree" "" "$(_pycache)"

# CONTROL — without this, leg 6 passes just as well when the gate never ran at all, or when the
# environment is suppressing bytecode. `py_compile` over the SAME tree must plant the directory.
( cd "$TMP/probe" && env -u PYTHONDONTWRITEBYTECODE python3 -m py_compile bin/*.py >/dev/null 2>&1 )
eq "control: py_compile over the same tree DOES mint bin/__pycache__" "$TMP/probe/bin/__pycache__" \
   "$(_pycache)"

_summary "python-syntax-gate-selftest"
