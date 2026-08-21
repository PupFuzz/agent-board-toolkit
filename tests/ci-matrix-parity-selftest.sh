#!/usr/bin/env bash
# ci-matrix-parity-selftest.sh — assert that every tests/*-selftest.sh is actually RUN by a
# pull-request-triggered workflow in .github/workflows/, that those workflows name no selftest
# that isn't on disk, and that the `pull_request` triggers themselves hold two contracts: no
# workflow narrows itself with a paths/branches filter, and every workflow whose verdict can
# read a PR field subscribes `edited` (card#6099).
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
# THE TRIGGER CONTRACT — two rules about the `pull_request` key itself, closed as a class
# rather than instance-by-instance (card#6099). NEITHER HAS AN INSTANCE ON THIS TREE, which is
# precisely why each is pointed at a planted fixture below: on the live directory both answer
# "" for structural reasons indistinguishable from a clean repo, and a check that cannot fail
# is a decoration.
#
#   (a) A `pull_request` mapping carrying `paths:`, `paths-ignore:`, `branches:` or
#       `branches-ignore:` is REJECTED — the workflow qualifies for nothing, so the tests it
#       names read as unrun. This was an ACCEPTED, DOCUMENTED gap in this very paragraph until
#       card#6099: a filtered workflow's tests counted as "run on pull requests" for the PRs
#       its own filter excludes, which errs GREEN — the one direction this file exists to
#       refuse. Rejecting forces an explicit decision (drop the filter, or move the test) in
#       place of a silent under-run. The four keys are ONE tuple in the parser, exported as the
#       `filter-keys` projection so the fixture loop drives whatever that tuple holds instead
#       of a hand-typed echo of it (card#6645's shape). `types:` is NOT a narrowing key — it
#       selects which PR EVENTS re-run a workflow, not which PRs it observes — and that
#       boundary is pinned by a fixture rather than by this sentence.
#
#   (b) A workflow whose TEXT reads `github.event.pull_request` must list `edited` in its
#       `pull_request` `types:`. A verdict that is a function of a PR field goes STALE the
#       moment the field is edited after opening, because the default event set (opened,
#       synchronize, reopened) never re-runs it: card#6054 shipped that defect on the BASE
#       field (`release-artifacts-gate.yml`) and card#6062 on the TITLE
#       (`changelog-card-entry.yml` — the reason that gate owns a workflow at all). Two
#       instances of one class were fixed in place and nothing stopped a third from being
#       minted; this leg is the class fix.
#
#       THE POPULATION IS RE-DERIVED FROM THE FILE TEXT ON EVERY RUN, never enumerated: the
#       workflows containing the literal `github.event.pull_request`. Text rather than parsed
#       structure, because the reference can sit in an `env:`, a `with:`, an `if:` or a `run:`
#       block, and a structural walk would have to enumerate those places to find it. The
#       population is exposed as its own projection and asserted non-empty with a named member,
#       so an absence verdict measured over an empty set cannot read as clean.
#
#       COMMENT LINES ARE OUTSIDE THE POPULATION, and that is a precision fix, not a
#       loosening: a comment cannot make a verdict stale, and this rule gets DESCRIBED in
#       workflow comments. Counting them named ci.yml — whose own verdict reads no PR field —
#       as a stale reader on the very change that added this guard. A fixture whose only
#       mention is a comment pins it, and asserts that the file really does carry the literal,
#       so the clean answer is the predicate's and not a broken fixture's.
#
#       IT ERRS RED where a workflow reads a PR field while subscribing NO `pull_request`
#       event — push-only, or `pull_request_target`, which this predicate does not read. It has
#       no `types` that could satisfy the rule and is REPORTED; on a push that field is empty,
#       so it is a defect of a different shape rather than a false alarm. That costs an
#       explicit decision, the same trade the `if:` rule below already makes.
#
# ⛔ WHAT (b) STRUCTURALLY CANNOT SEE: the `pull_request` recipe published in docs/INSTALL.md
# §6c, which consumers paste into THEIR repos. The population here is .github/workflows/, so
# this holds THIS repository's workflows level and says nothing about a copy living in a fenced
# block in a markdown file.
#
# THE STRUCTURE IS PARSED, NEVER GREPPED: the matrix and the trigger are structured data, and
# a grep for `- foo` would match a `- foo` under any other key. Rule (b)'s population is the
# one deliberate exception and is a different question — "does this file REFER to a PR field",
# which has no single structural home (an `env:`, a `with:`, an `if:`, a `run:` block) — so it
# is read from the file's non-comment text, and every VERDICT about a matched file is then
# taken from the parse.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

WORKFLOWS="$HERE/../.github/workflows"
_need -r "$WORKFLOWS"
_mktmp_scratch

# _wf_scan <workflows-dir> <projection> — ONE parser, five projections plus a constant:
#   `workflows`              — basenames of the workflow files that subscribe `pull_request`
#                              and are not narrowed by a filter key.
#   `runs`                   — every selftest basename those workflows run.
#   `filtered`               — `<file>: <key>[,<key>...]` for each workflow REJECTED by rule
#                              (a); it names the key that rejected it, because "your selftest
#                              is unrun" alone would not tell an author what they just did.
#   `pr-field-readers`       — rule (b)'s population: the workflows whose text reads
#                              `github.event.pull_request`. Printed so the absence assertion
#                              over it can be shown to have measured something.
#   `stale-pr-field-readers` — those of them that do not list `edited`.
#   `filter-keys`            — the FILTER_KEYS tuple itself (the directory argument is ignored),
#                              so the fixtures below are driven by the parser's own set.
# The trigger predicate is written once and every projection reads it, so asserting one
# projection asserts the same code path the others filter on.
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

# The `pull_request` sub-keys that NARROW which pull requests a workflow observes — one
# declaration, exported as the `filter-keys` projection so nothing re-types the set.
FILTER_KEYS = ('branches', 'branches-ignore', 'paths', 'paths-ignore')

# `pull_request:` with an empty value is a real, common spelling (ci.yml uses it) and means
# "every event type, unnarrowed". A sentinel keeps it distinguishable from a workflow that
# subscribes no pull_request at all — `None` would conflate the two.
ABSENT = object()

def pr_trigger(doc):
    # YAML 1.1 — which is what pyyaml implements — resolves a bare `on` key to the BOOLEAN
    # True, not the string 'on'. A `doc.get('on')` alone reads None for every workflow in this
    # repo and would silently admit nothing (or, read the other way round, everything); both
    # keys are consulted so the answer does not depend on how the author quoted the key.
    spec = doc.get('on', doc.get(True))
    if isinstance(spec, dict):
        return spec['pull_request'] if 'pull_request' in spec else ABSENT
    if isinstance(spec, list):
        return None if 'pull_request' in spec else ABSENT
    return None if spec == 'pull_request' else ABSENT

def pr_filters(trig):
    return [k for k in FILTER_KEYS if isinstance(trig, dict) and k in trig]

def pr_types(trig):
    t = trig.get('types') if isinstance(trig, dict) else None
    return [str(x) for x in t] if isinstance(t, list) else []

mode = sys.argv[2]
if mode == 'filter-keys':
    print('\n'.join(FILTER_KEYS))
    sys.exit(0)

names, files, filtered, readers, stale = set(), [], [], [], []
for path in sorted(glob.glob(os.path.join(sys.argv[1], '*.yml'))
                   + glob.glob(os.path.join(sys.argv[1], '*.yaml'))):
    with open(path) as fh:
        text = fh.read()
    doc = yaml.safe_load(text) or {}
    if not isinstance(doc, dict):
        continue
    base = os.path.basename(path)
    trig = pr_trigger(doc)
    # Rule (b). The population is the TEXT — re-derived here, on every run, from every file in
    # the directory; there is no list of PR-field-reading workflows anywhere in this file.
    # COMMENT LINES ARE EXCLUDED. A comment cannot make a verdict stale, and the rule gets
    # DESCRIBED in workflow comments — ci.yml's `ci-matrix-parity` job describes exactly this
    # rule, and counting its text named ci.yml a stale reader on the very change that added the
    # guard (measured, not hypothetical). A whole-text match would answer about the prose.
    active = '\n'.join(ln for ln in text.splitlines() if not ln.lstrip().startswith('#'))
    if 'github.event.pull_request' in active:
        readers.append(base)
        if 'edited' not in pr_types(trig):
            stale.append(base)
    # Rule (a). A narrowed pull_request qualifies for NOTHING — the tests it names read as
    # unrun rather than as covered on pull requests its own filter excludes.
    narrowed = pr_filters(trig)
    if narrowed:
        filtered.append('%s: %s' % (base, ','.join(narrowed)))
        continue
    if trig is ABSENT:
        continue
    files.append(base)
    for job in (doc.get('jobs') or {}).values():
        if not isinstance(job, dict) or 'if' in job:
            continue
        names.update(str(t) for t in ((job.get('strategy') or {}).get('matrix') or {}).get('test') or [])
        for step in job.get('steps') or []:
            if isinstance(step, dict) and isinstance(step.get('run'), str):
                names.update(re.findall(r'tests/([A-Za-z0-9._-]+)\.sh', step['run']))
# Codepoint order == LC_ALL=C order, so `comm` below sees two identically-collated streams.
# A locale sort would reorder punctuated names against python's and silently corrupt the diff.
# An unknown projection is a KeyError, not an empty line: a typo'd argument must not read as a
# clean absence in a file whose every live assertion is an assertion of absence.
print('\n'.join({'runs': sorted(names), 'workflows': files, 'filtered': filtered,
                  'pr-field-readers': readers, 'stale-pr-field-readers': stale}[mode]))
PY
}

_wf_runs()          { _wf_scan "$1" runs; }
_pr_workflows()     { _wf_scan "$1" workflows; }
_filtered_pr()      { _wf_scan "$1" filtered; }
_pr_field_readers() { _wf_scan "$1" pr-field-readers; }
_stale_pr_fields()  { _wf_scan "$1" stale-pr-field-readers; }
_filter_keys()      { _wf_scan "$1" filter-keys; }

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

# Rule (b)'s DENOMINATOR, printed and asserted before the absence check that reads it. The
# population is derived from the file text every run; if it ever measures the empty set — a
# moved directory, a renamed event field — the "no stale reader" assertion below would pass
# while checking nothing at all. Named members, never a count, for the reason stated above.
readers="$(_pr_field_readers "$WORKFLOWS")"
eq "the PR-field-reader population is non-empty" "false" \
   "$([ -z "$readers" ] && echo true || echo false)"
eq "the PR-field-reader population contains a known member (release-artifacts-gate.yml)" "true" \
   "$(printf '%s\n' "$readers" | grep -qx 'release-artifacts-gate.yml' && echo true || echo false)"
eq "the PR-field-reader population contains a second known member (changelog-card-entry.yml)" "true" \
   "$(printf '%s\n' "$readers" | grep -qx 'changelog-card-entry.yml' && echo true || echo false)"
# The discriminating half: a workflow that reads no PR field must be OUTSIDE the population.
# Without it, a predicate matching every file would satisfy both assertions above.
eq "a workflow that reads no PR field is outside it (ci.yml)" "false" \
   "$(printf '%s\n' "$readers" | grep -qx 'ci.yml' && echo true || echo false)"

# ---------------------------------------------------------------------------
# The live assertion.
# ---------------------------------------------------------------------------
echo "== every tests/*-selftest.sh is run by a PR-triggered workflow =="
eq "no selftest on disk is left unrun" "" "$(unrun "$WORKFLOWS" "$HERE")"
eq "the workflows name no selftest that is absent from tests/" "" "$(dangling "$WORKFLOWS" "$HERE")"

echo "== the trigger contract: no narrowed pull_request, no PR-field read without 'edited' =="
eq "no workflow narrows its pull_request with a paths/branches filter" "" \
   "$(_filtered_pr "$WORKFLOWS")"
eq "no workflow reading github.event.pull_request omits 'edited' from its types" "" \
   "$(_stale_pr_fields "$WORKFLOWS")"

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
# <extra-step-lines> is appended INSIDE the single step, so a fixture can make the workflow
# read a PR field without a second fixture generator. Emitted through an `if` rather than a
# trailing `[[ -n … ]] && printf`, whose exit status would leak past `set -e` on the empty
# case and kill the run after writing a correct file (card#5874's shape).
_wf_fixture() {  # <dir> <trigger-block> [extra-step-lines]
    mkdir -p "$1"
    {
        cat <<EOF
name: Probe
on:
$2
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: bash tests/kb-board-lib-selftest.sh
EOF
        if [[ -n "${3:-}" ]]; then printf '%s\n' "$3"; fi
    } > "$1/probe.yml"
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

echo "== prove-it-can-fail: a NARROWED pull_request is REJECTED, naming the key =="
# The keys come from the parser's own FILTER_KEYS via the `filter-keys` projection — they are
# not re-typed here. A fifth narrowing key added to that tuple gets a fixture without anyone
# remembering to write one, and a key dropped from it stops being asserted. A hand-typed echo
# of a population is the defect class this repo has already filed twice (card#6645).
keys="$(_filter_keys "$WORKFLOWS")"
eq "the filter-key population is non-empty (the loop below has members)" "false" \
   "$([ -z "$keys" ] && echo true || echo false)"
while read -r key; do
    [[ -n "$key" ]] || continue
    _wf_fixture "$TMP/wf-filter-$key" "  pull_request:
    $key: [x]"
    eq "a pull_request narrowed by $key is reported, naming the key" "probe.yml: $key" \
       "$(_filtered_pr "$TMP/wf-filter-$key")"
    eq "a pull_request narrowed by $key qualifies as PR-triggered for nothing" "" \
       "$(_pr_workflows "$TMP/wf-filter-$key")"
    eq "a pull_request narrowed by $key leaves the test it names unrun (what the author sees)" \
       "true" \
       "$(unrun "$TMP/wf-filter-$key" "$HERE" | grep -qx 'kb-board-lib-selftest' \
          && echo true || echo false)"
done <<< "$keys"

# The pinned NEGATIVES for rule (a). 'types:' selects which EVENTS re-run a workflow, not which
# pull requests it observes, so the twin above must stay admitted; and a bare 'pull_request:'
# with no sub-keys — ci.yml's own spelling — must not become collateral.
eq "the types-carrying twin is not reported as narrowed" "" "$(_filtered_pr "$TMP/wf-pr")"
_wf_fixture "$TMP/wf-pr-bare" "  pull_request:"
eq "a bare pull_request: carries no filter" "" "$(_filtered_pr "$TMP/wf-pr-bare")"
eq "a bare pull_request: still qualifies" "probe.yml" "$(_pr_workflows "$TMP/wf-pr-bare")"

# The same defect PLANTED IN THE REAL DIRECTORY, because the live assertion above runs against
# THAT and a synthetic one-file dir does not prove it can fail there. Injected as literal text
# into a copy, never a re-dumped YAML — that would assert against pyyaml's serializer instead
# of the files CI reads (the same reason the ghost-matrix fixture is a sed).
cp -r "$WORKFLOWS" "$TMP/wf-narrowed"
sed "s|^  pull_request:$|  pull_request:\n    paths: ['bin/**']|" "$WORKFLOWS/ci.yml" \
    > "$TMP/wf-narrowed/ci.yml"
eq "the fixture actually injected the paths filter into ci.yml" "true" \
   "$(grep -qx "    paths: \['bin/\*\*'\]" "$TMP/wf-narrowed/ci.yml" && echo true || echo false)"
eq "a paths filter on the REAL ci.yml is reported" "ci.yml: paths" \
   "$(_filtered_pr "$TMP/wf-narrowed")"
eq "and the tests only ci.yml runs go unrun (the whole matrix, not one name)" "true" \
   "$(unrun "$TMP/wf-narrowed" "$HERE" | grep -qx 'kb-board-lib-selftest' && echo true || echo false)"

echo "== prove-it-can-fail: a PR-field reader without 'edited' is REPORTED =="
# The twin pair differs in ONE token — 'edited' in types — and both halves read the same PR
# field. SINGLE-quoted: the value carries a literal \${{ … }}, which bash would read as a
# parameter expansion (and abort on) if this were written in double quotes.
PR_FIELD_STEP='        env:
          PR_TITLE: ${{ github.event.pull_request.title }}'
_wf_fixture "$TMP/wf-field-stale" "  pull_request:
    types: [opened, synchronize]" "$PR_FIELD_STEP"
_wf_fixture "$TMP/wf-field-edited" "  pull_request:
    types: [opened, synchronize, edited]" "$PR_FIELD_STEP"
eq "the fixture really does read a PR field (without which both legs are vacuous)" "true" \
   "$(grep -q 'github.event.pull_request.title' "$TMP/wf-field-stale/probe.yml" \
      && echo true || echo false)"
eq "a PR-field reader whose types omit edited is reported" "probe.yml" \
   "$(_stale_pr_fields "$TMP/wf-field-stale")"
eq "the same workflow with edited added is not reported" "" \
   "$(_stale_pr_fields "$TMP/wf-field-edited")"
eq "the edited twin was IN the measured population (witness: its clean answer means something)" \
   "probe.yml" "$(_pr_field_readers "$TMP/wf-field-edited")"

# NEGATIVE: omitting 'edited' is not a finding by itself. Without this, a predicate that simply
# reported every workflow lacking 'edited' would satisfy every assertion above.
_wf_fixture "$TMP/wf-no-field" "  pull_request:
    types: [opened, synchronize]"
eq "types without edited is NOT reported where no PR field is read" "" \
   "$(_stale_pr_fields "$TMP/wf-no-field")"
eq "that workflow is outside the population entirely" "" "$(_pr_field_readers "$TMP/wf-no-field")"

# NEGATIVE: a mention in a COMMENT is not a read. The third assertion is the load-bearing one —
# it shows the fixture really does carry the literal, so the two clean answers above it are the
# predicate's verdict and not a fixture that failed to plant anything.
_wf_fixture "$TMP/wf-field-comment" "  pull_request:
    types: [opened, synchronize]" '        # this step no longer reads ${{ github.event.pull_request.title }}'
eq "a mention in a comment is not reported" "" "$(_stale_pr_fields "$TMP/wf-field-comment")"
eq "a mention in a comment is outside the population" "" \
   "$(_pr_field_readers "$TMP/wf-field-comment")"
eq "the comment fixture does carry the literal (witness: those two answers mean something)" \
   "true" \
   "$(grep -q 'github.event.pull_request.title' "$TMP/wf-field-comment/probe.yml" \
      && echo true || echo false)"

# The err-RED arm the header names: a PR field read by a workflow subscribing no pull_request
# event has no types that could satisfy the rule, and is reported rather than skipped.
_wf_fixture "$TMP/wf-field-push" "  push:
    branches: [main]" "$PR_FIELD_STEP"
eq "a PR-field reader subscribing no pull_request event at all is reported" "probe.yml" \
   "$(_stale_pr_fields "$TMP/wf-field-push")"

# And rule (b)'s defect planted in the REAL directory — card#6054's exact regression, put back:
# release-artifacts-gate.yml reads github.event.pull_request.base.sha, and its verdict is a
# function of that base, so dropping 'edited' is the state this leg exists to report.
cp -r "$WORKFLOWS" "$TMP/wf-unedited"
sed 's/\[opened, edited, reopened/[opened, reopened/' "$WORKFLOWS/release-artifacts-gate.yml" \
    > "$TMP/wf-unedited/release-artifacts-gate.yml"
# Asserted on the rewritten LINE, not on `grep -q edited` over the file: that word also
# appears in the workflow's own comments, so a file-wide search answers about the prose and
# reads as "the injection failed" on a fixture that is in fact correct (observed, once).
eq "the fixture actually rewrote the real gate's types line" \
   "    types: [opened, reopened, synchronize]" \
   "$(grep -E '^[[:space:]]*types:' "$TMP/wf-unedited/release-artifacts-gate.yml")"
eq "the real gate stripped of edited is reported" "release-artifacts-gate.yml" \
   "$(_stale_pr_fields "$TMP/wf-unedited")"
eq "its sibling PR-field reader, untouched, is not (the report names ONE file)" "true" \
   "$(printf '%s\n' "$(_pr_field_readers "$TMP/wf-unedited")" | grep -qx 'changelog-card-entry.yml' \
      && echo true || echo false)"

_summary "ci-matrix-parity-selftest"
