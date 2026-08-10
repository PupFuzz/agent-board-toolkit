#!/usr/bin/env bash
# ci-matrix-parity-selftest.sh — assert that every tests/*-selftest.sh is actually RUN by a
# pull-request-triggered workflow in .github/workflows/, and that those workflows name no
# selftest that isn't on disk.
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
# be run on every pull request — either as a `selftest` matrix entry, or named as a literal
# `tests/<name>.sh` in some unconditional job's `run:` block, in any workflow that subscribes
# `pull_request`. Both channels count because the repo genuinely uses both, and an allow-list of
# "tests that are deliberately not in the matrix" would be a second hand-maintained registry,
# i.e. this defect again. THIS test is wired via the second channel on purpose: it gets its own
# top-level CI job rather than a matrix entry, because a matrix entry would be self-referential
# — deleting the guard's own matrix line would disable the guard silently, the exact hole it
# exists to close. Being run by a `run:` block, it still satisfies the one rule it enforces.
#
# THE POPULATION IS THE WORKFLOW DIRECTORY, NOT ci.yml — and the qualifier is the TRIGGER, not
# the filename. It read only ci.yml until card#6062 moved the `changelog-card-entry` job into
# its own workflow (that gate must subscribe `edited`, which ci.yml does not), at which point a
# single-file scan called a test that CI genuinely runs "unrun". A scan of every workflow
# regardless of trigger would have been the wrong repair in the other direction: this repo has
# push-to-main-only workflows (`auto-tag-version`, `release-promote-cards`), and a test named
# only in one of those does NOT run on pull requests — counting it would loosen the rule to
# "named somewhere", which is not the property anyone relies on. So the scan admits a workflow
# only if its `on:` subscribes `pull_request`, and that predicate is exposed as its own
# projection (`_pr_workflows`) so it is asserted in both directions rather than buried.
#
# THE TWO DIRECTIONS ARE NOT EQUALLY LOAD-BEARING, and saying so is the point:
#   * `unrun`    — a file on disk that no PR-triggered workflow executes. This is the SILENT
#                  direction and the only reason this guard exists. Nothing else reports it.
#   * `dangling` — a name in a workflow with no file on disk. CI already fails LOUDLY on these
#                  (`bash tests/x.sh` exits 127), so this leg adds a clearer message at a
#                  cheaper stage, not new coverage. It is asserted because it is the other half
#                  of the same set comparison and costs nothing — do not read it as the leg
#                  that makes this file worth having.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that
# every selftest file is REFERENCED by an unconditional job in some workflow that subscribes
# `pull_request`. It does not prove the job succeeded, or that the reference is spelled in a
# form the runner can execute. Those imprecisions err RED, never green: a job gated by `if:`
# is skipped by the extractor, and an invocation not spelled as a literal `tests/<name>.sh`
# (`cd tests && bash foo.sh`) simply isn't seen — each reads as "unrun" and fails the build
# rather than passing it.
#
# ONE ACCEPTED GAP ERRS GREEN: a `paths:`/`branches:` filter on a workflow's `pull_request`
# does not demote it — its tests count as run even on PRs the filter excludes. No workflow
# here carries such a filter today; the day one does, tighten `_pr_workflows` to reject it
# (forcing an explicit decision) rather than letting this paragraph go stale.
#
# The workflows are PARSED, never grepped: the matrix is structured data, and a grep for
# `- foo` would match a `- foo` under any other key.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

WORKFLOWS="$HERE/../.github/workflows"
_need -r "$WORKFLOWS"
_mktmp_scratch

# _wf_scan <workflows-dir> <runs|workflows> — ONE parser, two projections:
#   `workflows` — the basenames of the workflow files that subscribe `pull_request`.
#   `runs`      — every selftest basename those workflows run.
# The trigger predicate is written once and both projections read it, so asserting the
# `workflows` projection asserts the same code path the `runs` projection filters on.
#
# `runs` collects through two channels. Channel 1: any job's strategy.matrix.test entries.
# Channel 2: any `tests/<name>.sh` named in a step's `run:` text. The matrix job's own `run:`
# is `bash "tests/${{ matrix.test }}.sh"`, whose `${{` cannot match the name pattern — so
# channel 2 does not manufacture a fake entry from it, and the matrix job is covered by
# channel 1 alone.
#
# A job carrying a job-level `if:` is SKIPPED by both channels, so a test referenced only from
# a conditional job reads as unrun. That is deliberate and errs red: `if:` is a GitHub
# expression this cannot evaluate, so a job gated on (say) `github.event_name == 'push'`
# contributes nothing on a pull_request while still *naming* the test — precisely the
# "green build, test never ran" state this guard exists to report. Today no job in these
# workflows carries one; the day one does, the right answer is an explicit decision, not a
# silent pass.
_wf_scan() {
    python3 - "$1" "$2" <<'PY'
import glob, os, re, sys, yaml

def pr_triggered(doc):
    # YAML 1.1 — which is what pyyaml implements — resolves a bare `on` key to the BOOLEAN
    # True, not the string 'on'. A `doc.get('on')` alone reads None for every workflow in this
    # repo and would silently admit nothing (or, read the other way round, everything); both
    # keys are consulted so the answer does not depend on how the author quoted the key.
    spec = doc.get('on', doc.get(True))
    if isinstance(spec, dict):
        return 'pull_request' in spec
    if isinstance(spec, list):
        return 'pull_request' in spec
    return spec == 'pull_request'

names, files = set(), []
for path in sorted(glob.glob(os.path.join(sys.argv[1], '*.yml'))
                   + glob.glob(os.path.join(sys.argv[1], '*.yaml'))):
    doc = yaml.safe_load(open(path)) or {}
    if not isinstance(doc, dict) or not pr_triggered(doc):
        continue
    files.append(os.path.basename(path))
    for job in (doc.get('jobs') or {}).values():
        if not isinstance(job, dict) or 'if' in job:
            continue
        names.update(str(t) for t in ((job.get('strategy') or {}).get('matrix') or {}).get('test') or [])
        for step in job.get('steps') or []:
            if isinstance(step, dict) and isinstance(step.get('run'), str):
                names.update(re.findall(r'tests/([A-Za-z0-9._-]+)\.sh', step['run']))
# Codepoint order == LC_ALL=C order, so `comm` below sees two identically-collated streams.
# A locale sort would reorder punctuated names against python's and silently corrupt the diff.
print('\n'.join(sorted(names) if sys.argv[2] == 'runs' else files))
PY
}

_wf_runs()      { _wf_scan "$1" runs; }
_pr_workflows() { _wf_scan "$1" workflows; }

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
unrun()    { LC_ALL=C comm -23 <(_disk_tests "$2") <(_wf_runs "$1"); }
dangling() { LC_ALL=C comm -13 <(_disk_tests "$2") <(_wf_runs "$1"); }

# ---------------------------------------------------------------------------
# Positive control FIRST. Every assertion below is an assertion of ABSENCE ("no unrun
# tests"), and an empty answer is indistinguishable from an extraction that returned nothing
# at all — a yaml parse that quietly yielded {} would make every absence check pass. So prove
# both streams carry real data before trusting any emptiness.
# ---------------------------------------------------------------------------
echo "== positive control — both streams are non-empty and carry a known member =="
runs="$(_wf_runs "$WORKFLOWS")"
disk="$(_disk_tests "$HERE")"
wfs="$(_pr_workflows "$WORKFLOWS")"
eq "workflow extraction is non-empty"      "false" "$([ -z "$runs" ] && echo true || echo false)"
eq "tests/ enumeration is non-empty"       "false" "$([ -z "$disk" ] && echo true || echo false)"
# Named members, not just counts: a count pins the check to a past value and goes stale as the
# suite grows, whereas a member that must be present re-derives nothing and cannot rot silently.
eq "workflow extraction contains a known matrix entry" "true" \
   "$(printf '%s\n' "$runs" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"
eq "workflow extraction contains THIS test (run: channel, not matrix)" "true" \
   "$(printf '%s\n' "$runs" | grep -qx 'ci-matrix-parity-selftest' && echo true || echo false)"
eq "tests/ enumeration contains a known file" "true" \
   "$(printf '%s\n' "$disk" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"

# The trigger predicate, asserted in BOTH directions against the real directory. Only the
# "admits" half is implied by the extraction above; without the "rejects" half, a predicate
# that returned True unconditionally would satisfy every other assertion in this file.
eq "the PR-trigger filter admits ci.yml" "true" \
   "$(printf '%s\n' "$wfs" | grep -qx 'ci.yml' && echo true || echo false)"
eq "the PR-trigger filter REJECTS a push-only workflow (release-promote-cards.yml)" "false" \
   "$(printf '%s\n' "$wfs" | grep -qx 'release-promote-cards.yml' && echo true || echo false)"

# ---------------------------------------------------------------------------
# The live assertion.
# ---------------------------------------------------------------------------
echo "== every tests/*-selftest.sh is run by a PR-triggered workflow =="
eq "no selftest on disk is left unrun" "" "$(unrun "$WORKFLOWS" "$HERE")"
eq "the workflows name no selftest that is absent from tests/" "" "$(dangling "$WORKFLOWS" "$HERE")"

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL. Both legs are pointed at fixtures carrying the exact defect they claim to
# catch. Without this, a guard that answers "" for structural reasons reads identically to one
# that answered "" because the repo is clean.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: an unregistered selftest is REPORTED =="
mkdir -p "$TMP/t-unrun"
# One registered name + one that no workflow has ever heard of. The registered file is the
# presence witness: it must NOT appear in the output, which is what shows the comparison ran
# against real workflow data rather than against an empty set.
touch "$TMP/t-unrun/kb-board-lib-selftest.sh" "$TMP/t-unrun/orphan-selftest.sh"
eq "an unrun selftest is named" "orphan-selftest" "$(unrun "$WORKFLOWS" "$TMP/t-unrun")"
eq "the REGISTERED sibling is not named (witness: the comparison saw the workflows)" "" \
   "$(printf '%s\n' "$(unrun "$WORKFLOWS" "$TMP/t-unrun")" | grep -x 'kb-board-lib-selftest' || true)"

echo "== prove-it-can-fail: a matrix entry with no file is REPORTED =="
# Injected as a literal matrix line into a copy of the real workflow dir — a re-dumped YAML
# would assert this check against pyyaml's serializer rather than against the files CI reads.
cp -r "$WORKFLOWS" "$TMP/wf-ghost"
sed 's/^\( *\)- adopt-to-dl-selftest$/&\n\1- ghost-selftest/' "$WORKFLOWS/ci.yml" > "$TMP/wf-ghost/ci.yml"
eq "the fixture actually injected the ghost entry" "true" \
   "$(grep -qx ' *- ghost-selftest' "$TMP/wf-ghost/ci.yml" && echo true || echo false)"
eq "a dangling matrix entry is named" "ghost-selftest" "$(dangling "$TMP/wf-ghost" "$HERE")"
eq "the unrun leg stays clean on that fixture (the two legs are independent)" "" \
   "$(unrun "$TMP/wf-ghost" "$HERE")"

echo "== prove-it-DISCRIMINATES: the same job counts on pull_request and not on push =="
# The two fixture dirs differ in ONE key — the trigger — and each holds a single workflow that
# names a real on-disk selftest. If the filter were dropped, the push-only leg would go green
# on a test that no pull request ever runs, which is the loosening this predicate exists to
# refuse; if the filter admitted nothing, the pull_request leg would fail. Neither miswiring
# survives both legs. The fixtures also carry a BARE `on:` key, which is how the pyyaml
# `on` → True resolution gets exercised rather than argued about.
_wf_fixture() {  # <dir> <trigger-block>
    mkdir -p "$1"
    cat > "$1/probe.yml" <<EOF
name: Probe
on:
$2
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/kb-board-lib-selftest.sh
EOF
}
_wf_fixture "$TMP/wf-push" "  push:
    branches: [main]"
_wf_fixture "$TMP/wf-pr" "  pull_request:
    types: [opened, edited]"
eq "a push-only workflow qualifies for nothing" "" "$(_pr_workflows "$TMP/wf-push")"
eq "the pull_request twin qualifies" "probe.yml" "$(_pr_workflows "$TMP/wf-pr")"
eq "a test named ONLY by a push-only workflow reads as unrun" "true" \
   "$(unrun "$TMP/wf-push" "$HERE" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"
eq "the same naming under pull_request does NOT read as unrun (witness: it was extracted)" \
   "false" \
   "$(unrun "$TMP/wf-pr" "$HERE" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"

_summary "ci-matrix-parity-selftest"
