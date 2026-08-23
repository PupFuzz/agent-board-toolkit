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
# THE GATE IS EXTRACTED, NEVER RESTATED. Leg 2–5 run the `run:` block out of `ci.yml` itself,
# located by STEP NAME, verbatim, in a scratch directory carrying its own `bin/*.py`. A copy of
# the command in this file would be a second thing that can disagree with the one CI runs — this
# repository's recurring defect (card#5389, card#5740, card#5355) — and it would go green against
# its own copy while the shipped step rotted.
#
# THE POPULATION OF LEG 1 IS THE WHOLE EXECUTABLE SURFACE, re-derived by glob every run:
# `.github/workflows/*.yml` plus the composite actions' `*/action.yml`, with EVERY value under a
# `run:` key collected wherever it sits in the document. There is no list of files here, so a
# sixth workflow or a third composite action is covered on the next run with no edit. Fixing the
# one site without that rule leaves the next hand to re-mint the artifact (card#7207 IS the
# instance of card#6871 being re-minted by an unguarded second site).
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
#
# HOW EACH LEG IS SEEN TO FAIL. Legs 1 and 5 are assertions of ABSENCE, which pass for free when
# the thing that would create the artifact never ran:
#   * leg 1 carries a planted fixture pair — a workflow that DOES call `py_compile` (must be
#     flagged) beside its clean twin (must not) — and a named witness that the live derivation
#     read real data at all, rather than answering the empty set from a moved directory.
#   * leg 5's absence of `__pycache__` is paired with a CONTROL that runs `py_compile` over the
#     same fixture tree and asserts the directory DOES appear. Without it the leg passes equally
#     when the gate command never executed.
#   * `PYTHONDONTWRITEBYTECODE=1` — which `_selftest-prelude.sh` exports for the whole suite — is
#     CLEARED for every probe here. Left set, it would suppress the control's write too, and this
#     file would certify a property of the environment instead of a property of the gate.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$HERE/.."
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

# _writers <path>... — the bytecode-WRITING invocations among those run blocks, one `file: line`
# per line. `py_compile` and `compileall` are the two stdlib entry points whose whole purpose is
# to emit a `.pyc`; nothing else in the stdlib writes one without being imported.
# A HERESTRING, not `printf … | while read` — the prelude's standing rule against a pipeline
# whose reader can leave early, and it also keeps the loop out of a subshell.
_writers() {
    local f block line
    for f in "$@"; do
        while IFS= read -r -d '' block; do
            while IFS= read -r line; do
                case "$line" in
                    *py_compile*|*compileall*)
                        printf '%s: %s\n' "$(basename "$f")" "${line#"${line%%[![:space:]]*}"}" ;;
                esac
            done <<< "$block"
        done < <(_run_blocks "$f")
    done
}

echo "== leg 1: no run: block in the executable surface writes bytecode =="

# The population, re-derived by glob. `-print0` is not needed — these names are repo-controlled
# and carry no whitespace — but the glob IS the derivation, and it is asserted non-empty below.
mapfile -t SURFACE < <(
    { ls -1 "$ROOT"/.github/workflows/*.yml
      ls -1 "$ROOT"/*/action.yml
    } 2>/dev/null | LC_ALL=C sort
)

eq "the surface glob found files (positive control on the population)" "false" \
   "$([[ "${#SURFACE[@]}" -eq 0 ]] && echo true || echo false)"

# NAMED WITNESS, not a count: a count pins this to a past value and rots the moment a workflow is
# added. `_shellcheck-pinned` is a token that lives in a `run:` block of the live tree — if the
# walk cannot see it, the walk is broken and every absence below is vacuous.
live_blocks="$(_run_blocks "${SURFACE[@]}" | tr '\0' '\n')"
eq "the run:-block walk reads real data (named witness)" "true" \
   "$(has '_shellcheck-pinned' "$live_blocks")"

eq "no run: block invokes py_compile or compileall" "" "$(_writers "${SURFACE[@]}")"

# PROVE-IT-CAN-FAIL — a planted pair through the SAME derivation the live population goes
# through, so what is certified is the check that actually runs.
mkdir -p "$TMP/wf"
cat > "$TMP/wf/dirty.yml" <<'YML'
name: dirty
on: [pull_request]
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - name: mints bytecode
        run: python3 -m py_compile bin/*.py
YML
cat > "$TMP/wf/clean.yml" <<'YML'
name: clean
on: [pull_request]
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - name: writes nothing
        run: python3 -c 'compile(open("x.py","rb").read(), "x.py", "exec")'
YML
eq "control: a run: block calling py_compile IS flagged" \
   "dirty.yml: python3 -m py_compile bin/*.py" "$(_writers "$TMP/wf/dirty.yml")"
eq "control: its clean twin is NOT flagged" "" "$(_writers "$TMP/wf/clean.yml")"

echo "== legs 2-5: the SHIPPED gate command, extracted from ci.yml by step name =="

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

echo "== leg 4: a clean tree still passes after the failures (the gate is not stuck red) =="
expect_rc "the gate accepts the valid tree again" 0 _gate_rc

echo "== leg 5: the gate minted NO bytecode across any of the runs above =="
eq "no __pycache__ anywhere under the probe tree" "" "$(_pycache)"

# CONTROL — without this, leg 5 passes just as well when the gate never ran at all, or when the
# environment is suppressing bytecode. `py_compile` over the SAME tree must plant the directory.
( cd "$TMP/probe" && env -u PYTHONDONTWRITEBYTECODE python3 -m py_compile bin/*.py >/dev/null 2>&1 )
eq "control: py_compile over the same tree DOES mint bin/__pycache__" "$TMP/probe/bin/__pycache__" \
   "$(_pycache)"

_summary "python-syntax-gate-selftest"
