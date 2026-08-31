#!/usr/bin/env bash
# ci-gate-selftest.sh — the `ci-gate` job is the repository's ONE required status context, so
# the two things that make it a gate rather than a decoration are asserted here: it depends on
# EVERY job in its workflow, and its verdict step really reds on every non-success result.
#
# WHY THIS FILE EXISTS (card#8261). `main` and `dev` carry the whole fleet branch-protection
# model — `enforce_admins`, blocked force-pushes and deletions, the merge-method rulesets — with
# `required_status_checks` at **`null`**. The repo therefore reads as protected on every surface
# an operator inspects while **no CI result is required to merge at all**. The obvious repair —
# fill in the `contexts` list — is a hand-maintained registry of check names standing in front of
# a `selftest` matrix that ORDINARY PULL REQUESTS EDIT (`run-coverage-check-selftest` was added
# three PRs before this one), and such a list rots in both directions: a name dropped from the
# matrix never reports again and deadlocks every PR (loud), while a name ADDED to it is required
# by nothing (silent, and the direction that matters). `ci-gate` is the one context that does not
# move when the matrix does — and everything that gate is worth then rests on the two properties
# below.
#
# ⛔ AN AGGREGATOR OBSERVED ONLY GREEN IS A DECORATION, and this one stands in front of the whole
# merge gate. Two failure shapes are specifically what leg 4 drives, because both are silent:
#   * a MISSING `if: always()` — the job is SKIPPED the moment a needed job fails, and a skipped
#     required check does NOT block a merge. The gate passes precisely when the suite is red.
#   * a verdict step that reads only `failure` — `cancelled` and `skipped` are then read as
#     "not a failure", which is the same fail-open one value along.
# Leg 4 runs the SHIPPED step, extracted from `ci.yml` by step name, over planted `needs`
# payloads: a copy of the command in this file would be a second thing that can disagree with the
# one CI runs (card#5389, card#5740, card#5355 are this repo's own instances of that), and it
# would go green against its own copy while the shipped step rotted.
#
# ⚑ WHAT LEG 4 EXERCISES vs WHAT IT ARGUES. It drives the VERDICT LOGIC — given these results,
# does the step exit non-zero — for `failure`, `cancelled`, `skipped`, mixtures, and the empty
# `needs:` control. It does NOT prove GitHub populates `needs.<job>.result` with those strings,
# nor that `if: always()` makes the runner schedule the job at all: both are runner behaviour and
# only a real workflow run can answer them. Leg 2 asserts the `if:` is present and is `always()`;
# what that expression MEANS is GitHub's, not this file's.
#
# ⚑ THE `skipped` RULING IS A DECISION, NOT A DETAIL, and it is `ci.yml`'s to state — that job's
# comment owns the reasoning (no job in that file can be skipped today, so the arm is a ruling
# about the next edit; reading it as a pass would let a future `if:` drop a leg out of the merge
# gate with no signal anywhere). This file only holds the shipped step to it. The ruling is
# deliberately NOT restated here: a second copy is a second thing to correct.
#
# ⛔ WHAT `needs:` STRUCTURALLY CANNOT REACH — and why leg 3 exists. `needs:` names jobs in the
# SAME workflow file. `changelog-card-entry.yml` and `release-artifacts-gate.yml` each own a
# PR-triggered job for a trigger `ci.yml` cannot give it (`edited`, load-bearing on both), and
# `ci-gate` covers NEITHER. An operator who requires `ci-gate` alone has gated this workflow and
# left those two gates advisory — the same "looks protected, is not" shape this whole card is
# about, one file over. So the full REQUIRED-CONTEXT SET is declared once, HERE, in
# `REQUIRE_BESIDE_CI_GATE`, and leg 3 partitions every job in the workflow directory against it
# so a ninth job anywhere reds until someone places it. This file is the single owner of that
# declaration; `ci.yml` points at it rather than carrying a second copy.
#
# ⛔ BOUNDS, stated so this is not over-cited:
#   * Leg 3 partitions by JOB ID over the whole workflow directory. It does not evaluate
#     triggers — `ci-matrix-parity-selftest.sh` owns the `pull_request` trigger predicate and is
#     the one place it is written. What leg 3 asserts is that every job is DISPOSED of (gated by
#     `ci-gate`, required by name beside it, or explicitly declared not-PR-gating), never that
#     the disposition is the right one; a job moved from a PR trigger to a push trigger would
#     stay green here. That is a partition, not a trigger check, and it is the cheap half.
#   * Nothing here reads live branch protection. Whether the operator ACTUALLY set these contexts
#     is a fact about the repository settings, not about this tree, and a test that cannot see it
#     must not imply it. It is what the card's own closing step verifies, live.
#   * `strict` (require branches up to date before merging) is not this file's business either.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_gha-surface-lib.sh"

ROOT="$(cd "$HERE/.." && pwd)"
WORKFLOWS="$ROOT/.github/workflows"
CI_YML="$WORKFLOWS/ci.yml"
GATE_JOB="ci-gate"
STEP_NAME="every needed job succeeded"
_need -r "$CI_YML"
_mktmp_scratch

# THE ONE DECLARATION of which check contexts must be required BESIDE `ci-gate`, and of which
# jobs are not PR gates at all. Leg 3 holds both level with the workflow directory, in both
# directions, so neither can quietly shrink.
#
# ⚑ These are CHECK-RUN NAMES. A job reports under its `name:` when it has one and under its job
# id otherwise — leg 2 asserts no job in this repo carries a `name:`, which is what makes reading
# the two lists as context strings legitimate rather than an assumption.
REQUIRE_BESIDE_CI_GATE=(
    changelog-card-entry     # changelog-card-entry.yml — needs `edited` for the PR TITLE
    release-artifacts        # release-artifacts-gate.yml — needs `edited` for the PR BASE
)
NOT_A_PR_GATE=(
    auto-tag                 # auto-tag-version.yml    — push: main only, post-merge
    promote                  # release-promote-cards.yml — push: main only, post-merge
)

# _wf <projection> <workflow-path> [job] — one parser, five projections. Each is a fact about the
# PARSED document, never a grep: `needs:`, `if:` and `name:` are structured keys and a text match
# for any of them would find the word in a comment or in an unrelated job.
#   `jobs`      — every top-level job id, in file order.
#   `needs`     — the named job's `needs:` list, one per line (a bare string is one entry).
#   `if`        — the named job's job-level `if:`, or "" when it carries none.
#   `job-names` — `<job>=<name:>` for every job that declares a `name:`; empty when none does.
#   `step-run`  — the `run:` body of the step named by the fourth argument, in the named job.
#   `step-env`  — that same step's WHOLE `env:` map as `<key>=<value>` lines.
#
# A step that is not found is reported as "" rather than as a hard exit, so the premise
# assertions in leg 4 can SAY that the step is missing. An exit there would kill the script
# before its own diagnostic ran, which is how a premise check becomes a decoration.
_wf() {
    python3 - "$@" <<'PY'
import sys, yaml

mode, path = sys.argv[1], sys.argv[2]
arg = sys.argv[3] if len(sys.argv) > 3 else None
jobs = (yaml.safe_load(open(path)) or {}).get('jobs') or {}

if mode == 'jobs':
    print('\n'.join(jobs))
    sys.exit(0)
if mode == 'job-names':
    print('\n'.join(f'{j}={s["name"]}' for j, s in jobs.items() if isinstance(s, dict) and 'name' in s))
    sys.exit(0)

spec = jobs.get(arg)
if not isinstance(spec, dict):
    sys.exit(f'{path}: no job {arg!r} (the job was renamed, which orphans the required context)')

if mode == 'needs':
    n = spec.get('needs') or []
    print('\n'.join([n] if isinstance(n, str) else list(n)))
elif mode == 'if':
    # `if: always()` parses as the STRING; a bare `if: true` would parse as a bool. Rendering
    # whatever it is keeps a shape change visible instead of crashing on it.
    print('' if 'if' not in spec else str(spec['if']))
elif mode in ('step-run', 'step-env'):
    hits = [s for s in spec.get('steps', []) if s.get('name') == sys.argv[4]]
    if len(hits) != 1:
        sys.exit(0)
    if mode == 'step-run':
        sys.stdout.write(hits[0].get('run') or '')
    else:
        print('\n'.join(f'{k}={v}' for k, v in (hits[0].get('env') or {}).items()))
PY
}

echo "== leg 1: ci-gate needs EVERY job in its own workflow =="

# `awk NF` is not decoration: `'\n'.join([])` writes one EMPTY line, so an empty `jobs:` map
# arrives here as a one-element array and the emptiness control below would never fire on the
# one input it exists for.
mapfile -t CI_JOBS < <(_wf jobs "$CI_YML" | awk 'NF')

# POSITIVE CONTROL FIRST. Both comparisons below are set DIFFERENCES, and a derivation that read
# nothing satisfies them exactly as a correct `needs:` list does — the same trap this file's
# subject is built around. A named witness rather than a count: a count pins this to a past value
# and rots the day a job is added, which is the whole failure mode under discussion.
eq "the job derivation read real data (positive control)" "false" \
   "$([[ "${#CI_JOBS[@]}" -eq 0 ]] && echo true || echo false)"
eq "the job derivation names the matrix job (named witness)" "true" \
   "$(has_line 'selftest' "$(printf '%s\n' "${CI_JOBS[@]}")")"
eq "the aggregator job itself is present in ci.yml" "true" \
   "$(has_line "$GATE_JOB" "$(printf '%s\n' "${CI_JOBS[@]}")")"

expected_needs="$(printf '%s\n' "${CI_JOBS[@]}" | awk -v self="$GATE_JOB" 'NF && $0 != self' | LC_ALL=C sort)"
actual_needs="$(_wf needs "$CI_YML" "$GATE_JOB" | awk 'NF' | LC_ALL=C sort)"

# BOTH DIRECTIONS, and they fail for different reasons. A job in ci.yml that `needs:` omits is a
# leg of the suite the merge gate does not cover — silent, and the reason this leg exists. A
# `needs:` entry with no such job is a workflow GitHub refuses to load at all, which is loud, but
# it is the other half of the same set comparison and costs nothing.
eq "job in ci.yml that ci-gate does not need (it is outside the merge gate)" "" \
   "$(LC_ALL=C comm -23 <(printf '%s\n' "$expected_needs") <(printf '%s\n' "$actual_needs"))"
eq "ci-gate needs a job that does not exist in ci.yml" "" \
   "$(LC_ALL=C comm -13 <(printf '%s\n' "$expected_needs") <(printf '%s\n' "$actual_needs"))"

echo "== leg 2: the shape that makes it report at all =="

# ⛔ THE LOAD-BEARING HALF. Without `always()` the job is skipped when a needed job fails, and a
# skipped required check does not block a merge — the gate would be satisfied exactly when the
# suite was red. `success()` is the implicit default, so DELETING this line is the regression,
# not just editing it.
eq "ci-gate carries if: always()" "always()" "$(_wf if "$CI_YML" "$GATE_JOB")"

# A `name:` REPLACES the job id in the reported check-run name. On the required job that silently
# renames the required context and every pull request becomes permanently unmergeable; on any
# other job it invalidates leg 3's reading of job ids as context strings. Asserted over the whole
# directory, so it is a property of the repo rather than of one job.
#
# ⚑ NO EMPTINESS CONTROL ON THIS DERIVATION, deliberately, and the reason is the same standard
# that would otherwise demand one: `_need -r "$CI_YML"` above has already refused a run in which
# `.github/workflows/` holds nothing, so an `is it empty` assertion here could never fail — and a
# check that cannot fail is a decoration, which is exactly what this file is written against. The
# population SHRINKING is a different question and is genuinely caught: delete a workflow and its
# declared context in `REQUIRE_BESIDE_CI_GATE` becomes a phantom, which reds leg 3's second
# comparison. That is the reachable control, and it was watched to fail.
mapfile -t WF_FILES < <(_gha_workflow_files "$WORKFLOWS")
declared_names=""
for f in "${WF_FILES[@]}"; do
    declared_names+="$(_wf job-names "$f" | awk -v f="${f##*/}" 'NF {print f ": " $0}')"$'\n'
done
eq "no job declares a name: (so every check context IS its job id)" "" "$(printf '%s' "$declared_names" | awk 'NF')"

echo "== leg 3: every job in the directory is DISPOSED of, not just ci.yml's =="

all_jobs=""
for f in "${WF_FILES[@]}"; do
    all_jobs+="$(_wf jobs "$f")"$'\n'
done
all_jobs="$(printf '%s' "$all_jobs" | awk 'NF' | LC_ALL=C sort -u)"
disposed="$(printf '%s\n' "${CI_JOBS[@]}" "${REQUIRE_BESIDE_CI_GATE[@]}" "${NOT_A_PR_GATE[@]}" \
            | awk 'NF' | LC_ALL=C sort -u)"

# The silent direction: a NEW job somewhere that nothing gates and nobody decided about.
eq "job in .github/workflows/ that no bucket disposes of (gate it, require it, or declare it)" "" \
   "$(LC_ALL=C comm -23 <(printf '%s\n' "$all_jobs") <(printf '%s\n' "$disposed"))"
# The other direction: a declaration naming a job that no longer exists — i.e. a context an
# operator may still be requiring, which never reports again and deadlocks every pull request.
eq "declared context naming a job that no longer exists (drop it from branch protection too)" "" \
   "$(LC_ALL=C comm -13 <(printf '%s\n' "$all_jobs") <(printf '%s\n' "$disposed"))"

echo "== leg 4: the SHIPPED verdict step, extracted from ci.yml by step name =="

GATE="$(_wf step-run "$CI_YML" "$GATE_JOB" "$STEP_NAME")"

# The extraction is the premise of every case below; a renamed or emptied step must red HERE and
# not as six mysterious rc failures.
eq "the '$STEP_NAME' step was extracted from ci.yml" "true" \
   "$([[ -n "$GATE" ]] && echo true || echo false)"
eq "the extracted block reads the results from the environment" "true" "$(has 'os.environ["NEEDS"]' "$GATE")"

# ⛔ THE WIRING, and the one thing leg 4's probes structurally cannot notice. They PLANT `NEEDS`
# themselves, so a workflow that stopped handing the step `toJSON(needs)` — a typo'd key, a
# dropped `env:` — would leave every probe below passing while the shipped gate read an empty
# environment and crashed, or worse, read something else. Measured: mutating this line to a
# different key produced NO red anywhere in this file until this assertion existed. The WHOLE map
# is compared rather than one key, because this step needs exactly one variable and an added
# second one is a decision someone should have to make out loud.
eq "the verdict step is handed toJSON(needs) as NEEDS" 'NEEDS=${{ toJSON(needs) }}' \
   "$(_wf step-env "$CI_YML" "$GATE_JOB" "$STEP_NAME")"

# _verdict <needs-json> — run the SHIPPED block verbatim with a planted `toJSON(needs)` payload.
# `-e -o pipefail` mirrors the runner's own default shell flags for a `run:` block, so the status
# this observes is produced under the same options CI produces it under. No string surgery on
# `$GATE`: rewriting the command to retarget it would be a second spelling of the thing under
# test.
VRC=0
_verdict() {
    VRC=0
    NEEDS="$1" bash -e -o pipefail -c "$GATE" >"$TMP/verdict.out" 2>&1 || VRC=$?
}
_j() { python3 -c 'import json,sys; print(json.dumps({j: {"result": r} for j, r in (a.split("=",1) for a in sys.argv[1:])}))' "$@"; }

# The GREEN arm first — without it every red below is equally consistent with a step that fails
# on everything, which would be a gate that cannot be satisfied rather than one that works.
_verdict "$(_j a=success b=success c=success)"
eq "all needed jobs succeeded ⇒ rc 0" "0" "$VRC"
eq "  … and it says what it measured" "true" "$(has 'all 3 needed job(s) succeeded' "$(cat "$TMP/verdict.out")")"

_verdict "$(_j a=success b=failure c=success)"
eq "a FAILED job ⇒ non-zero" "true" "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … and the offending job is NAMED, not just counted" "true" \
   "$(has "::error::b reported 'failure'" "$(cat "$TMP/verdict.out")")"

# ⛔ CANCELLED. A cancelled run MEASURED NOTHING, so there is no verdict to inherit — and this is
# the arm `if: !cancelled()` would have thrown away by never running the job at all.
_verdict "$(_j a=success b=cancelled c=success)"
eq "a CANCELLED job ⇒ non-zero" "true" "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … and it is named" "true" "$(has "::error::b reported 'cancelled'" "$(cat "$TMP/verdict.out")")"

# ⛔ SKIPPED — the ruling `ci.yml`'s own comment states and defends. Unreachable on today's tree
# (no job there carries a job-level `if:` or its own `needs:`), which is exactly why it is driven
# from a planted payload here: an arm nothing can reach is an arm nothing has ever seen fail.
_verdict "$(_j a=success b=skipped c=success)"
eq "a SKIPPED job ⇒ non-zero" "true" "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … and it is named" "true" "$(has "::error::b reported 'skipped'" "$(cat "$TMP/verdict.out")")"

# EVERY leg skipped — the shape a workflow-level `if:` or a cancelled generation stage produces.
# It must not read as "nothing failed".
_verdict "$(_j a=skipped b=skipped c=skipped)"
eq "EVERY job skipped ⇒ non-zero" "true" "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … reported as 3 of 3, not as one" "true" \
   "$(has '3 of 3 needed job(s) did not succeed' "$(cat "$TMP/verdict.out")")"

# EVERY failing job is reported, not just the first: an author who fixes the one name in the
# annotation and pushes has to be told about the other on the same run, not on the next one.
_verdict "$(_j a=failure b=success c=cancelled)"
eq "MIXED failures ⇒ non-zero" "true" "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … and BOTH are reported" "true" \
   "$(has '2 of 3 needed job(s) did not succeed' "$(cat "$TMP/verdict.out")")"

# ⛔ THE CONTROL, and not a hypothetical: this job IS the required context, so an aggregator that
# needs nothing is a green tick standing in front of an unmeasured suite. `{}` is what
# `toJSON(needs)` renders for a job whose `needs:` was emptied — the cheapest possible way to
# disable the entire merge gate while every surface still shows a passing required check.
_verdict '{}'
eq "an EMPTY needs: ⇒ non-zero (the aggregator refuses to stand in front of nothing)" "true" \
   "$([[ "$VRC" -ne 0 ]] && echo true || echo false)"
eq "  … and it says so" "true" "$(has 'standing in front of nothing' "$(cat "$TMP/verdict.out")")"

_summary ci-gate-selftest
