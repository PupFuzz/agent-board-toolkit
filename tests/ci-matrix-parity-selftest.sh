#!/usr/bin/env bash
# ci-matrix-parity-selftest.sh — assert that every tests/*-selftest.sh is actually RUN by
# .github/workflows/ci.yml, and that ci.yml names no selftest that isn't on disk.
#
# WHY THIS FILE EXISTS. The `selftest` job's `strategy.matrix.test` list and the contents of
# tests/ were kept aligned BY HAND, behind a `# KEEP THIS LIST IN SYNC` comment. A comment is
# not a gate. Add a selftest, forget the matrix line, and the test never runs in CI —
# permanently, silently, and every PR stays green. The author sees it pass locally and has no
# signal at all that CI skipped it. This was card#5339's defect shape (a hand-maintained
# registry that silently under-covers) one layer up: the registry that decides which tests run
# AT ALL (card#5355). Both registries are now gated — help-output-selftest.sh's CLIS by its own
# completeness assertion — so the shape survives in neither.
#
# THE RULE IS ONE RULE, WITH NO HAND-MAINTAINED EXCEPTION LIST: every tests/*-selftest.sh must
# be run by ci.yml — either as a `selftest` matrix entry, or named as a literal `tests/<name>.sh`
# in some unconditional job's `run:` block. Both channels count because the repo genuinely uses
# both, and an allow-list of
# "tests that are deliberately not in the matrix" would be a second hand-maintained registry,
# i.e. this defect again. THIS test is wired via the second channel on purpose: it gets its own
# top-level CI job rather than a matrix entry, because a matrix entry would be self-referential
# — deleting the guard's own matrix line would disable the guard silently, the exact hole it
# exists to close. Being run by a `run:` block, it still satisfies the one rule it enforces.
#
# THE TWO DIRECTIONS ARE NOT EQUALLY LOAD-BEARING, and saying so is the point:
#   * `unrun`    — a file on disk that ci.yml never executes. This is the SILENT direction and
#                  the only reason this guard exists. Nothing else in the repo reports it.
#   * `dangling` — a name in ci.yml with no file on disk. CI already fails LOUDLY on these
#                  (`bash tests/x.sh` exits 127), so this leg adds a clearer message at a
#                  cheaper stage, not new coverage. It is asserted because it is the other half
#                  of the same set comparison and costs nothing — do not read it as the leg
#                  that makes this file worth having.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that
# every selftest file is REFERENCED by an unconditional job in this one workflow file. It does
# not prove the job succeeded, that the reference is spelled in a form the runner can execute,
# or that a sibling workflow doesn't gate things elsewhere. Both directions of imprecision err
# RED, never green: a job gated by `if:` is skipped by the extractor, and an invocation not
# spelled as a literal `tests/<name>.sh` (`cd tests && bash foo.sh`) simply isn't seen — each
# reads as "unrun" and fails the build rather than passing it.
#
# ci.yml is PARSED, never grepped: the matrix is structured data, and a grep for `- foo` would
# match a `- foo` under any other key.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

CI="$HERE/../.github/workflows/ci.yml"
_need -r "$CI"
_mktmp_scratch

# _ci_runs <ci.yml> — every selftest basename that ci.yml runs, one per line, C-collated.
# Channel 1: any job's strategy.matrix.test entries. Channel 2: any `tests/<name>.sh` named in
# a step's `run:` text. The matrix job's own `run:` is `bash "tests/${{ matrix.test }}.sh"`,
# whose `${{` cannot match the name pattern — so channel 2 does not manufacture a fake entry
# from it, and the matrix job is covered by channel 1 alone.
#
# A job carrying a job-level `if:` is SKIPPED by both channels, so a test referenced only from
# a conditional job reads as unrun. That is deliberate and errs red: `if:` is a GitHub
# expression this cannot evaluate, so a job gated on (say) `github.event_name == 'push'`
# contributes nothing on a pull_request while still *naming* the test — precisely the
# "green build, test never ran" state this guard exists to report. Today no job in ci.yml
# carries one; the day one does, the right answer is an explicit decision, not a silent pass.
_ci_runs() {
    python3 - "$1" <<'PY'
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1])) or {}
names = set()
for job in (doc.get('jobs') or {}).values():
    if not isinstance(job, dict) or 'if' in job:
        continue
    names.update(str(t) for t in ((job.get('strategy') or {}).get('matrix') or {}).get('test') or [])
    for step in job.get('steps') or []:
        if isinstance(step, dict) and isinstance(step.get('run'), str):
            names.update(re.findall(r'tests/([A-Za-z0-9._-]+)\.sh', step['run']))
# Codepoint order == LC_ALL=C order, so `comm` below sees two identically-collated streams.
# A locale sort would reorder punctuated names against python's and silently corrupt the diff.
print('\n'.join(sorted(names)))
PY
}

# _disk_tests <tests-dir> — every *-selftest.sh basename in the dir, C-collated.
_disk_tests() {
    local d="$1" f
    for f in "$d"/*-selftest.sh; do
        [[ -e "$f" ]] || continue
        basename "$f" .sh
    done | LC_ALL=C sort
}

# `comm` validates its inputs' order in the AMBIENT locale, so it must be pinned to C as well
# as the two producers — not merely for tidiness. en_US.UTF-8 collation ignores punctuation in
# its primary pass, which orders this very suite differently from codepoint order
# (`kbc-archive-eligible` vs `kbcard-field` invert on the `-` vs `a` at position 4). Feed comm
# two C-collated streams while it judges them as en_US and it reports "not in sorted order" and
# emits an unreliable diff — observed, not hypothetical.
unrun()    { LC_ALL=C comm -23 <(_disk_tests "$2") <(_ci_runs "$1"); }
dangling() { LC_ALL=C comm -13 <(_disk_tests "$2") <(_ci_runs "$1"); }

# ---------------------------------------------------------------------------
# Positive control FIRST. Every assertion below is an assertion of ABSENCE ("no unrun
# tests"), and an empty answer is indistinguishable from an extraction that returned nothing
# at all — a yaml parse that quietly yielded {} would make every absence check pass. So prove
# both streams carry real data before trusting any emptiness.
# ---------------------------------------------------------------------------
echo "== positive control — both streams are non-empty and carry a known member =="
runs="$(_ci_runs "$CI")"
disk="$(_disk_tests "$HERE")"
eq "ci.yml extraction is non-empty"        "false" "$([ -z "$runs" ] && echo true || echo false)"
eq "tests/ enumeration is non-empty"       "false" "$([ -z "$disk" ] && echo true || echo false)"
# Named members, not just counts: a count pins the check to a past value and goes stale as the
# suite grows, whereas a member that must be present re-derives nothing and cannot rot silently.
eq "ci.yml extraction contains a known matrix entry" "true" \
   "$(printf '%s\n' "$runs" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"
eq "ci.yml extraction contains THIS test (run: channel, not matrix)" "true" \
   "$(printf '%s\n' "$runs" | grep -qx 'ci-matrix-parity-selftest' && echo true || echo false)"
eq "tests/ enumeration contains a known file" "true" \
   "$(printf '%s\n' "$disk" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"

# ---------------------------------------------------------------------------
# The live assertion.
# ---------------------------------------------------------------------------
echo "== every tests/*-selftest.sh is run by ci.yml =="
eq "no selftest on disk is left unrun by ci.yml" "" "$(unrun "$CI" "$HERE")"
eq "ci.yml names no selftest that is absent from tests/" "" "$(dangling "$CI" "$HERE")"

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL. Both legs are pointed at fixtures carrying the exact defect they claim to
# catch. Without this, a guard that answers "" for structural reasons reads identically to one
# that answered "" because the repo is clean.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: an unregistered selftest is REPORTED =="
mkdir -p "$TMP/t-unrun"
# One registered name + one that ci.yml has never heard of. The registered file is the
# presence witness: it must NOT appear in the output, which is what shows the comparison ran
# against real ci.yml data rather than against an empty set.
touch "$TMP/t-unrun/kb-board-lib-selftest.sh" "$TMP/t-unrun/orphan-selftest.sh"
eq "an unrun selftest is named" "orphan-selftest" "$(unrun "$CI" "$TMP/t-unrun")"
eq "the REGISTERED sibling is not named (witness: the comparison saw ci.yml)" "" \
   "$(printf '%s\n' "$(unrun "$CI" "$TMP/t-unrun")" | grep -x 'kb-board-lib-selftest' || true)"

echo "== prove-it-can-fail: a matrix entry with no file is REPORTED =="
# Injected as a literal matrix line into a copy of the real ci.yml — a re-dumped YAML would
# assert this check against pyyaml's serializer rather than against the file CI actually reads.
sed 's/^\( *\)- adopt-to-dl-selftest$/&\n\1- ghost-selftest/' "$CI" > "$TMP/ci-ghost.yml"
eq "the fixture actually injected the ghost entry" "true" \
   "$(grep -qx ' *- ghost-selftest' "$TMP/ci-ghost.yml" && echo true || echo false)"
eq "a dangling matrix entry is named" "ghost-selftest" "$(dangling "$TMP/ci-ghost.yml" "$HERE")"
eq "the unrun leg stays clean on that fixture (the two legs are independent)" "" \
   "$(unrun "$TMP/ci-ghost.yml" "$HERE")"

_summary "ci-matrix-parity-selftest"
