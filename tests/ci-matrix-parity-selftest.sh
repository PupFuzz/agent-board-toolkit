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
#   (a) A `pull_request` trigger that observes FEWER THAN ALL PULL REQUESTS is REJECTED — the
#       workflow qualifies for nothing, so the tests it names read as unrun. This was an
#       ACCEPTED, DOCUMENTED gap in this very paragraph until card#6099: a narrowed workflow's
#       tests counted as "run on pull requests" for the PRs it does not observe, which errs
#       GREEN — the one direction this file exists to refuse. Rejecting forces an explicit
#       decision (drop the narrowing, or move the test) in place of a silent under-run.
#
#       TWO SHAPES NARROW A TRIGGER, and the rule reads both from the parse:
#         * any of `paths:`, `paths-ignore:`, `branches:`, `branches-ignore:` — the FILTER_KEYS
#           tuple, which selects which pull requests fire the workflow at all;
#         * a `types:` list omitting `opened` or `synchronize` — the REQUIRED_TYPES tuple.
#           `types:` selects which PR EVENTS re-run a workflow, and that is NOT a separate
#           question from coverage, which is what an earlier cut of this rule got wrong: a
#           workflow on `types: [closed]` never runs on an OPEN pull request at all, and one
#           omitting `synchronize` never re-runs on a push to the branch, so the head commit
#           that actually merges was never tested. Both are the same silent under-run.
#       A SUPERSET is admitted (both live gates carry `[opened, edited, reopened,
#       synchronize]`), and an ABSENT `types:` is GitHub's default — opened, synchronize,
#       reopened — which satisfies the rule. Each tuple is ONE declaration in the parser,
#       exported as the `filter-keys` and `required-types` projections so the fixture loops
#       drive whatever the tuples hold rather than a hand-typed echo of them (card#6645's
#       shape): a member added to either gets fixtures with no other edit.
#
#   (b) A workflow that reads `github.event.pull_request` must subscribe `edited` on EVERY
#       PR trigger it has. A verdict that is a function of a PR field goes STALE the
#       moment the field is edited after opening, because the default event set (opened,
#       synchronize, reopened) never re-runs it: card#6054 shipped that defect on the BASE
#       field (`release-artifacts-gate.yml`) and card#6062 on the TITLE
#       (`changelog-card-entry.yml` — the reason that gate owns a workflow at all). Two
#       instances of one class were fixed in place and nothing stopped a third from being
#       minted; this leg is the class fix.
#
#       THE POPULATION IS RE-DERIVED ON EVERY RUN, never enumerated: the workflows one of
#       whose PARSED SCALARS contains the literal `github.event.pull_request`. It is every
#       scalar in the document, walked recursively, because the reference has no single
#       structural home — an `env:` value, a `with:` input, an `if:`, a `run:` script — and
#       enumerating those places is what would go stale. The population is exposed as its own
#       projection and asserted non-empty with named members, so an absence verdict measured
#       over an empty set cannot read as clean.
#
#       WALKING SCALARS, NOT RAW TEXT, is what makes the two boundaries right at once, and
#       both were measured. A YAML COMMENT naming the field is not a read — pyyaml has already
#       discarded it — which matters because this rule gets DESCRIBED in workflow comments:
#       matching raw text named ci.yml, whose own verdict reads no PR field, as a stale reader
#       on the very change that added this guard. And a `#` line INSIDE A BLOCK SCALAR *is* a
#       read: Actions expands `${{ }}` textually into a `run:` script before any shell sees
#       it, so `# ${{ github.event.pull_request.title }}` in a heredoc is a live reference
#       whose verdict goes stale on a title edit. A `#`-prefix line filter over raw text got
#       the comment right and that one WRONG — err-green, in the leg's own defect class.
#       Fixtures pin both directions, each asserting the file really carries the literal, so a
#       clean answer is the predicate's verdict and not a fixture that planted nothing.
#
#       BOTH PR TRIGGERS ARE READ — `pull_request` AND `pull_request_target`. The latter fires
#       on the same activity types, has the same default set, and populates the same
#       `github.event.pull_request` object, so a stale verdict is available through it on
#       exactly the same terms. Reading only the former reported such a workflow as stale
#       under a message no edit to it could ever clear — unsatisfiable, and untrue of a
#       workflow that already carries `edited`. Every subscribed PR trigger must carry it: the
#       one that fires the run is the one that decides whether the verdict is fresh.
#
#       IT ERRS RED where a PR field is read by a workflow subscribing NEITHER PR trigger
#       (push-only, `workflow_dispatch`-only). Nothing there could satisfy the rule, and on
#       those events the field is empty, so it is REPORTED under its own message — a defect of
#       a different shape, not a false alarm. That costs an explicit decision, the same trade
#       the `if:` rule below already makes.
#
# ⛔ THE BOUNDS OF BOTH RULES, stated rather than left to be inferred — this file's own
# standard is to name every one:
#   * The population of BOTH rules is `.github/workflows/`. The `pull_request` recipe published
#     in docs/INSTALL.md §6c, which consumers paste into THEIR repos, is a fenced block in a
#     markdown file and is not parsed here.
#   * Neither rule follows a local composite action a workflow `uses:` (`./release-artifacts`,
#     `./promote`). An `action.yml`'s own steps can read `github.event.pull_request` and would
#     be invisible to rule (b). Verified clean at this change — both local actions name that
#     field only in `description:` prose — so this is a bound, not a live gap.
#   * A STEP-level `if:` is not read by either rule — only a JOB-level one demotes a
#     reference. A conditional step inside an unconditional job still counts as running the
#     test it names, which errs GREEN in the job-level rule's own direction. The weakest
#     property below is worded for exactly that ("referenced by an unconditional JOB"), and no
#     step in these workflows carries an `if:` today; closing it is a decision, not a typo.
#   * A reusable workflow (`on: workflow_call`) reading a PR field would land in rule (b)'s
#     no-PR-trigger arm, where the honest answer depends on the CALLER's trigger rather than on
#     the file. None exists here; the day one does, the right answer is an explicit decision,
#     not a silent pass — the same trade the `if:` rule makes.
#   * Rule (a) admits `pull_request` only. A workflow triggered SOLELY by
#     `pull_request_target` qualifies for nothing here, so the tests it names read as unrun —
#     err-RED, and left that way deliberately: no workflow in this repo uses that trigger, and
#     admitting it would mean deciding what "runs on every pull request" means for an event
#     that runs in the BASE ref's context. Rule (b) reads it, because a stale verdict is
#     available through it today.
#
# THE STRUCTURE IS PARSED, NEVER GREPPED — all of it, both rules. The matrix and the trigger
# are structured data, and a grep for `- foo` would match a `- foo` under any other key; rule
# (b)'s "does this file refer to a PR field" is answered over the document's parsed scalars for
# the same reason, not over the file's bytes.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_gha-surface-lib.sh"

WORKFLOWS="$HERE/../.github/workflows"
_need -r "$WORKFLOWS"
_mktmp_scratch

# _wf_scan <workflows-dir> <projection> — ONE parser, five projections plus a constant:
#   `workflows`              — basenames of the workflow files that subscribe `pull_request`
#                              and are not narrowed by a filter key.
#   `runs`                   — every selftest basename those workflows run.
#   `filtered`               — `<file>: <reason>[,<reason>...]` for each workflow REJECTED by
#                              rule (a); it names the key, or the missing types, that rejected
#                              it, because "your selftest is unrun" alone would not tell an
#                              author what they just did.
#   `pr-field-readers`       — rule (b)'s population: the workflows one of whose parsed scalars
#                              reads `github.event.pull_request`. Printed so the absence
#                              assertion over it can be shown to have measured something.
#   `stale-pr-field-readers` — `<file>: <reason>` for each of them that does not subscribe
#                              `edited` — per PR trigger, since a file can carry both.
#   `filter-keys`            — the FILTER_KEYS tuple itself (the directory argument is ignored),
#   `required-types`         — and the REQUIRED_TYPES tuple, so the fixture loops below are
#                              driven by the parser's own sets rather than by a copy of them.
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
#
# THE FILE POPULATION IS NOT DERIVED HERE — `_gha_workflow_files` in `tests/_gha-surface-lib.sh`
# owns "which YAML documents does GitHub Actions execute", both extensions included, and the
# paths arrive in argv already C-collated. This file globbed `*.yml`+`*.yaml` inline until
# card#7207's review found a THIRD copy of that derivation with a NARROWER predicate; the copies
# are gone rather than corrected one by one. The directory stays a parameter, so the fixture
# trees below go through the same derivation the live directory does.
_wf_scan() {
    local -a files=()
    mapfile -t files < <(_gha_workflow_files "$1")
    python3 - "$2" "${files[@]}" <<'PY'
import os, re, sys, yaml

# The `pull_request` sub-keys that NARROW which pull requests a workflow observes, and the
# activity types it must keep to observe all of them — one declaration each, exported as the
# `filter-keys` / `required-types` projections so nothing re-types either set.
FILTER_KEYS = ('branches', 'branches-ignore', 'paths', 'paths-ignore')
REQUIRED_TYPES = ('opened', 'synchronize')

# Both events populate `github.event.pull_request` and both take the same activity types.
PR_EVENTS = ('pull_request', 'pull_request_target')

# `pull_request:` with an empty value is a real, common spelling (ci.yml uses it) and means
# "the default event types, unnarrowed". A sentinel keeps it distinguishable from a workflow
# that subscribes the event not at all — `None` would conflate the two.
ABSENT = object()

def trigger(doc, event):
    # YAML 1.1 — which is what pyyaml implements — resolves a bare `on` key to the BOOLEAN
    # True, not the string 'on'. A `doc.get('on')` alone reads None for every workflow in this
    # repo and would silently admit nothing (or, read the other way round, everything); both
    # keys are consulted so the answer does not depend on how the author quoted the key.
    spec = doc.get('on', doc.get(True))
    if isinstance(spec, dict):
        return spec[event] if event in spec else ABSENT
    if isinstance(spec, list):
        return None if event in spec else ABSENT
    return None if spec == event else ABSENT

def types_of(trig):
    # None means NO `types:` key — GitHub's default set, which is a real and different answer
    # from an empty or unusable list. A bare string is read as the one-element list it means;
    # anything else present but unusable reads as the empty list, which errs RED under both
    # rules rather than being silently skipped.
    if not isinstance(trig, dict) or 'types' not in trig:
        return None
    t = trig['types']
    if isinstance(t, str):
        return [t]
    return [str(x) for x in t] if isinstance(t, list) else []

def narrowing(trig):
    # Why this workflow observes fewer than ALL pull requests — empty means it observes them
    # all. The two shapes are one answer because they are one question.
    out = [k for k in FILTER_KEYS if isinstance(trig, dict) and k in trig]
    types = types_of(trig)
    if types is not None:
        missing = [t for t in REQUIRED_TYPES if t not in types]
        if missing:
            out.append('types(%s)' % ','.join('-' + m for m in missing))
    return out

def scalars(node):
    # Every string in the parsed document, wherever it sits. pyyaml has already dropped the
    # comments, and a block scalar arrives as one string INCLUDING its `#` lines — which is
    # exactly the distinction a line filter over raw text cannot make.
    if isinstance(node, dict):
        for k, v in node.items():
            yield from scalars(k)
            yield from scalars(v)
    elif isinstance(node, list):
        for v in node:
            yield from scalars(v)
    elif isinstance(node, str):
        yield node

mode = sys.argv[1]
if mode == 'filter-keys':
    print('\n'.join(FILTER_KEYS))
    sys.exit(0)
if mode == 'required-types':
    print('\n'.join(REQUIRED_TYPES))
    sys.exit(0)

names, files, filtered, readers, stale = set(), [], [], [], []
for path in sys.argv[2:]:
    with open(path) as fh:
        doc = yaml.safe_load(fh) or {}
    if not isinstance(doc, dict):
        continue
    base = os.path.basename(path)
    # Rule (b). The population is re-derived on every run, from every file the caller's
    # directory holds; there is no list of PR-field-reading workflows anywhere in this file.
    if any('github.event.pull_request' in sc for sc in scalars(doc)):
        readers.append(base)
        subscribed = [e for e in PR_EVENTS if trigger(doc, e) is not ABSENT]
        if not subscribed:
            stale.append('%s: reads a PR field but subscribes no %s event'
                         % (base, '/'.join(PR_EVENTS)))
        for event in subscribed:
            types = types_of(trigger(doc, event))
            if types is None or 'edited' not in types:
                stale.append('%s: %s does not subscribe edited' % (base, event))
    # Rule (a). A narrowed pull_request qualifies for NOTHING — the tests it names read as
    # unrun rather than as covered on pull requests it does not observe.
    trig = trigger(doc, 'pull_request')
    if trig is ABSENT:
        continue
    narrowed = narrowing(trig)
    if narrowed:
        filtered.append('%s: %s' % (base, ','.join(narrowed)))
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
_required_types()   { _wf_scan "$1" required-types; }

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
   "$(has_line 'kb-board-lib-selftest' "$runs")"
eq "workflow extraction contains THIS test (run: channel, not matrix)" "true" \
   "$(has_line 'ci-matrix-parity-selftest' "$runs")"
eq "tests/ enumeration contains a known file" "true" \
   "$(has_line 'kb-board-lib-selftest' "$disk")"

# The trigger predicate, asserted in BOTH directions against the real directory. Only the
# "admits" half is implied by the extraction above; without the "rejects" half, a predicate
# that returned True unconditionally would satisfy every other assertion in this file.
eq "the PR-trigger filter admits ci.yml" "true" \
   "$(has_line 'ci.yml' "$wfs")"
eq "the PR-trigger filter REJECTS a push-only workflow (release-promote-cards.yml)" "false" \
   "$(has_line 'release-promote-cards.yml' "$wfs")"

# Rule (b)'s DENOMINATOR, printed and asserted before the absence check that reads it. The
# population is derived from the file text every run; if it ever measures the empty set — a
# moved directory, a renamed event field — the "no stale reader" assertion below would pass
# while checking nothing at all. Named members, never a count, for the reason stated above.
readers="$(_pr_field_readers "$WORKFLOWS")"
eq "the PR-field-reader population is non-empty" "false" \
   "$([ -z "$readers" ] && echo true || echo false)"
eq "the PR-field-reader population contains a known member (release-artifacts-gate.yml)" "true" \
   "$(has_line 'release-artifacts-gate.yml' "$readers")"
eq "the PR-field-reader population contains a second known member (changelog-card-entry.yml)" "true" \
   "$(has_line 'changelog-card-entry.yml' "$readers")"
# The discriminating half: a workflow that reads no PR field must be OUTSIDE the population.
# Without it, a predicate matching every file would satisfy both assertions above.
eq "a workflow that reads no PR field is outside it (ci.yml)" "false" \
   "$(has_line 'ci.yml' "$readers")"

# ---------------------------------------------------------------------------
# The live assertion.
# ---------------------------------------------------------------------------
echo "== every tests/*-selftest.sh is run by a PR-triggered workflow =="
eq "no selftest on disk is left unrun" "" "$(unrun "$WORKFLOWS" "$HERE")"
eq "the workflows name no selftest that is absent from tests/" "" "$(dangling "$WORKFLOWS" "$HERE")"

echo "== the trigger contract: no narrowed pull_request, no PR-field read without 'edited' =="
eq "no workflow observes fewer than all pull requests (filter key, or a deficient types list)" \
   "" "$(_filtered_pr "$WORKFLOWS")"
eq "every workflow reading github.event.pull_request subscribes edited on every PR trigger" \
   "" "$(_stale_pr_fields "$WORKFLOWS")"

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
# The PR twin carries the SUPERSET both live gates carry. An earlier cut used
# `[opened, edited]`, which is narrowed under rule (a) — it never re-runs on a push to the
# branch, so the head commit that merges is never tested — and asserting that it qualifies
# would have pinned the err-GREEN case as correct.
_wf_fixture "$TMP/wf-pr" "  pull_request:
    types: [opened, edited, reopened, synchronize]"
eq "a push-only workflow qualifies for nothing" "" "$(_pr_workflows "$TMP/wf-push")"
eq "the pull_request twin qualifies" "probe.yml" "$(_pr_workflows "$TMP/wf-pr")"
eq "a test named ONLY by a push-only workflow reads as unrun" "true" \
   "$(has_line 'kb-board-lib-selftest' "$(unrun "$TMP/wf-push" "$HERE")")"
eq "the same naming under pull_request does NOT read as unrun (witness: it was extracted)" \
   "false" \
   "$(has_line 'kb-board-lib-selftest' "$(unrun "$TMP/wf-pr" "$HERE")")"

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
       "$(has_line 'kb-board-lib-selftest' "$(unrun "$TMP/wf-filter-$key" "$HERE")")"
done <<< "$keys"

# The pinned NEGATIVES for rule (a) — the half that keeps it from being a rule that rejects
# everything. A types SUPERSET of the required set is admitted (the twin above, and what both
# live gates carry), and so is a bare 'pull_request:' with no sub-keys at all — ci.yml's own
# spelling, whose absent types: means GitHub's default set.
eq "a types superset is not reported as narrowed" "" "$(_filtered_pr "$TMP/wf-pr")"
_wf_fixture "$TMP/wf-pr-bare" "  pull_request:"
eq "a bare pull_request: carries no filter" "" "$(_filtered_pr "$TMP/wf-pr-bare")"
eq "a bare pull_request: still qualifies" "probe.yml" "$(_pr_workflows "$TMP/wf-pr-bare")"

# The types half of rule (a), driven the same derived way: one fixture per REQUIRED_TYPES
# member, each omitting exactly that member so the loop cannot pass by covering some other
# gap. `[closed]` is the shape that made this rule necessary — a workflow running only when a
# PR closes runs on no OPEN pull request at all, while an earlier cut of the parser counted it
# as running on every one of them.
req="$(_required_types "$WORKFLOWS")"
eq "the required-types population is non-empty (the loop below has members)" "false" \
   "$([ -z "$req" ] && echo true || echo false)"
while read -r t; do
    [[ -n "$t" ]] || continue
    keep="$(printf '%s\n' "$req" | grep -vx "$t" | paste -sd, -)"
    _wf_fixture "$TMP/wf-types-no-$t" "  pull_request:
    types: [$keep, closed]"
    eq "a types list omitting $t is reported, naming what is missing" "probe.yml: types(-$t)" \
       "$(_filtered_pr "$TMP/wf-types-no-$t")"
    eq "a types list omitting $t qualifies as PR-triggered for nothing" "" \
       "$(_pr_workflows "$TMP/wf-types-no-$t")"
    eq "a types list omitting $t leaves the test it names unrun" "true" \
       "$(has_line 'kb-board-lib-selftest' "$(unrun "$TMP/wf-types-no-$t" "$HERE")")"
done <<< "$req"

_wf_fixture "$TMP/wf-types-closed" "  pull_request:
    types: [closed]"
eq "types: [closed] is reported, naming BOTH missing members" \
   "probe.yml: types(-opened,-synchronize)" "$(_filtered_pr "$TMP/wf-types-closed")"
eq "types: [closed] qualifies for nothing" "" "$(_pr_workflows "$TMP/wf-types-closed")"

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
   "$(has_line 'kb-board-lib-selftest' "$(unrun "$TMP/wf-narrowed" "$HERE")")"

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
eq "a PR-field reader whose types omit edited is reported, naming the trigger" \
   "probe.yml: pull_request does not subscribe edited" \
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

# NEGATIVE: a mention in a real YAML COMMENT is not a read — pyyaml drops it before the walk
# ever sees the document. The third assertion is the load-bearing one: it shows the fixture
# really does carry the literal on disk, so the two clean answers above it are the predicate's
# verdict and not a fixture that failed to plant anything. Read with the heredoc fixture above,
# this pair is what distinguishes "comment" from "`#` character".
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
eq "a PR-field reader subscribing neither PR trigger is reported under its OWN message" \
   "probe.yml: reads a PR field but subscribes no pull_request/pull_request_target event" \
   "$(_stale_pr_fields "$TMP/wf-field-push")"

# pull_request_target fires on the same activity types and populates the same object, so it
# carries the same obligation and the same discharge. An earlier cut read only `pull_request`
# and reported the compliant twin below under a message no edit to it could ever clear.
_wf_fixture "$TMP/wf-target-stale" "  pull_request_target:
    types: [opened, synchronize]" "$PR_FIELD_STEP"
_wf_fixture "$TMP/wf-target-edited" "  pull_request_target:
    types: [opened, synchronize, edited]" "$PR_FIELD_STEP"
eq "a pull_request_target reader omitting edited is reported, naming THAT trigger" \
   "probe.yml: pull_request_target does not subscribe edited" \
   "$(_stale_pr_fields "$TMP/wf-target-stale")"
eq "the same workflow WITH edited is clean (the rule is satisfiable there)" "" \
   "$(_stale_pr_fields "$TMP/wf-target-edited")"
eq "and it was in the measured population (witness: that clean answer means something)" \
   "probe.yml" "$(_pr_field_readers "$TMP/wf-target-edited")"

# A `#` line inside a BLOCK SCALAR is a real read: Actions expands ${{ }} textually into the
# run: script before any shell sees it. Walking the parsed scalars sees it; a `#`-prefix line
# filter over raw text dropped it — err-green, in this leg's own defect class.
_wf_fixture "$TMP/wf-field-heredoc" "  pull_request:
    types: [opened, synchronize]" '      - run: |
          cat > body.md <<'"'"'MD'"'"'
          # ${{ github.event.pull_request.title }}
          MD'
eq "a PR field read from a heredoc COMMENT line inside run: is a read" \
   "probe.yml: pull_request does not subscribe edited" \
   "$(_stale_pr_fields "$TMP/wf-field-heredoc")"
eq "and that workflow is in the population" "probe.yml" \
   "$(_pr_field_readers "$TMP/wf-field-heredoc")"
eq "the heredoc fixture really does put the literal on a #-prefixed line" "true" \
   "$(grep -qE '^[[:space:]]*# \$\{\{ github\.event\.pull_request\.title' \
      "$TMP/wf-field-heredoc/probe.yml" && echo true || echo false)"

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
eq "the real gate stripped of edited is reported" \
   "release-artifacts-gate.yml: pull_request does not subscribe edited" \
   "$(_stale_pr_fields "$TMP/wf-unedited")"
eq "its sibling PR-field reader, untouched, is not (the report names ONE file)" "true" \
   "$(has_line 'changelog-card-entry.yml' "$(_pr_field_readers "$TMP/wf-unedited")")"

_summary "ci-matrix-parity-selftest"
