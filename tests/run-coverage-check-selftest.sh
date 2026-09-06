#!/usr/bin/env bash
# run-coverage-check-selftest.sh — deterministic, network-free checks that
# `bin/run-coverage-check` keeps its three verdict states APART, and that no unreadable or
# truncated input can be reported as coverage.
#
# WHY THIS FILE EXISTS. The tool's entire value is a distinction — ran / correctly-skipped /
# MISSING — and every way of getting that wrong looks like a clean report. A tool that answered
# SKIPPED for every workflow would print a plausible page and exit 0 on every repository in the
# fleet; so would one whose `on:` reader silently derived nothing. Neither would fail. So each
# state below is driven from a fixture that carries exactly that state, and every ABSENCE
# assertion is paired with a presence witness measured on the same run.
#
# ─────────────────────────── THE POPULATION, AND WHY IT TERMINATES ───────────────────────────
#
# The population is FINITE, ENUMERATED, and MONOTONICALLY CONSUMED — it is the cross of the
# tool's own two contracts, both of which are closed sets read off its `--help`:
#
#   the five report states   RAN · SKIPPED · MISSING · UNMEASURED · OUT-OF-SCOPE
#   the five read surfaces   the PR object · the changed-file list · the run list ·
#                            the workflow directory · each workflow file
#
# Every state is driven at least once, and every read surface is driven in BOTH directions
# (whole, and unreadable-or-truncated) — because "unreadable" is the input class the tool
# exists to refuse, and an unexercised refusal is a decoration. A sixth axis, the `on:`
# reader's own accept/refuse boundary, is driven by fixtures at each shape it claims to read
# and at three it claims to refuse.
#
# CLEAN, defined before the first pass: every member of that cross has a driven case whose
# assertion pair (the state IS reported, and the state it must NOT be reported as is absent)
# both hold. It is not "the findings stopped".
#
# NON-CONVERGENCE OBSERVABLE, pre-committed: a fix that makes an assertion pass by widening a
# state — most plausibly by letting UNMEASURED absorb a case that should be SKIPPED, or the
# reverse — would show as an UNMEASURED count that only ever grows across rounds. Every
# truncation case therefore asserts the UNMEASURED set MEMBER BY NAME and asserts the
# unfiltered sibling is NOT in it, so a widening reds instead of quietly passing.
#
# ⛔ WHAT A GREEN RUN HERE DOES NOT PROVE — the weakest property the assertions support:
#   * Nothing about the LIVE GitHub API. Every byte comes from `_run-coverage-gh-stub.sh`, so
#     this file certifies the tool's LOGIC against a fixture's idea of the API's shape. The
#     wire shape is asserted from the recorded argv (the full-40-hex `head_sha` in particular),
#     which is the one thing a stub can hold honest; whether GitHub still answers that way is
#     not knowable here and was measured by hand against `agent-webhook-bridge` PR #574 and
#     `kanban-board` PR #651 when the tool was written.
#   * Nothing about `on:` shapes absent from these fixtures. The reader's REFUSAL is what is
#     asserted for the shapes it does not read, so an unlisted shape lands in UNMEASURED — a
#     finding, never a pass — which is the direction that does not need enumerating.
#   * Nothing about whether a RAN workflow actually asserted anything. The tool prints a run's
#     conclusion and judges it not at all, deliberately, and neither does this file.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
BIN="$ROOT/bin/run-coverage-check"
_need -x "$BIN"
_need -x "$HERE/_run-coverage-gh-stub.sh"
command -v jq >/dev/null 2>&1 || { echo "selftest: jq not found" >&2; exit 1; }
_mktmp_scratch --home

mkdir -p "$TMP/bin"
cp "$HERE/_run-coverage-gh-stub.sh" "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
FIX="$TMP/fix"

SHA40="8623d5fa892a34072487eb1a87b291dee7daf12c"
KB_PROG_NAME="run-coverage-check"

# ── the fixture builder ─────────────────────────────────────────────────────────────────────
#
# A case writes a DIRECTORY, never a rule inside the stub. `_fix_build` is called by every
# mutator, so a case reads as a sequence of facts about one pull request.
HEADSHA=""; BASEREF=""; CHANGED=0; RUNS_TOTAL=""

_fix_reset() {
    rm -rf "$FIX"; mkdir -p "$FIX/wf"
    HEADSHA="$SHA40"; BASEREF="dev"; CHANGED=0; RUNS_TOTAL=""
    : > "$FIX/filelist"; : > "$FIX/runlist"; : > "$FIX/statelist"
    _fix_build
}
# _fix_build — re-render every JSON body from the plain-text lists. jq builds them, so a
# filename carrying a quote or a backslash cannot corrupt a fixture into a shape that would
# make the tool refuse for the wrong reason.
_fix_build() {
    printf '{"number":7,"state":"open","head":{"sha":"%s"},"base":{"ref":"%s"},"changed_files":%s}\n' \
        "$HEADSHA" "$BASEREF" "$CHANGED" > "$FIX/pr.json"
    jq -R -s 'split("\n")|map(select(length>0))|map({filename:.})' < "$FIX/filelist" > "$FIX/files.json"
    local total
    total="$RUNS_TOTAL"
    if [[ -z "$total" ]]; then total="$(awk 'NF{c++}END{print c+0}' "$FIX/runlist")"; fi
    jq -R -s --argjson total "$total" \
        'split("\n")|map(select(length>0))|map(split("\t"))
         |{total_count:$total, workflow_runs:map({path:.[0],event:.[1],conclusion:.[2]})}' \
        < "$FIX/runlist" > "$FIX/runs.json"
    jq -R -s 'split("\n")|map(select(length>0))|map(split("\t"))
              |{workflows:map({path:.[0],state:.[1]})}' < "$FIX/statelist" > "$FIX/states.json"
    ( cd "$FIX/wf" && ls -1 ) | jq -R -s 'split("\n")|map(select(length>0))|map({name:.,type:"file"})' \
        > "$FIX/workflows.json"
}
_fix_changed() { printf '%s\n' "$@" >> "$FIX/filelist"; CHANGED=$(( CHANGED + $# )); _fix_build; }
_fix_run()     { printf '%s\t%s\t%s\n' ".github/workflows/$1" "${2:-pull_request}" "${3:-success}" >> "$FIX/runlist"; _fix_build; }
_fix_state()   { printf '%s\t%s\n' ".github/workflows/$1" "$2" >> "$FIX/statelist"; _fix_build; }
# _fix_wf <name> — the workflow YAML arrives on stdin, so a case shows the `on:` block verbatim.
_fix_wf()      { cat > "$FIX/wf/$1"; _fix_build; }

# ── the driver ──────────────────────────────────────────────────────────────────────────────
RCC_OUT=""; RCC_ERR=""; RCC_RC=0
run_rcc() {
    RCC_RC=0
    : > "$TMP/argv"
    RCC_OUT="$(PATH="$TMP/bin:$PATH" RCC_FIX="$FIX" RCC_FAIL="${FAIL:-}" RCC_ARGV="$TMP/argv" \
               "$BIN" --repo o/n --pr 7 2>"$TMP/err")" || RCC_RC=$?
    RCC_ERR="$(cat "$TMP/err")"
}
# _line <STATE> <workflow-name> — the report line for one workflow in one state, or "".
# Matching on BOTH the state word and the path is what makes an absence assertion mean
# something: `grep MISSING` alone also matches the section heading.
_line() { printf '%s\n' "$RCC_OUT" | awk -v s="$1" -v p=".github/workflows/$2" '$1==s && $2==p {print; exit}'; }
_state_of() { printf '%s\n' "$RCC_OUT" | awk -v p=".github/workflows/$1" '$2==p {print $1; exit}'; }

# a workflow with a `pull_request` trigger and no filter at all — the shape that must ALWAYS
# produce a run, and therefore the one whose absence is unambiguously a finding.
_wf_plain() { _fix_wf "$1" <<'YML'
name: plain
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
YML
}
# the shape this whole card is about: zero runs is the NORMAL state for it on most PRs.
_wf_paths() { _fix_wf "$1" <<'YML'
name: pathy
on:
  pull_request:
    paths:
      - 'bin/**'
      - '.github/workflows/pathy.yml'
jobs:
  a:
    runs-on: ubuntu-latest
    steps: [{ run: "true" }]
YML
}

# ---------------------------------------------------------------------------
# POSITIVE CONTROL FIRST. Most assertions below are assertions of ABSENCE, and an absence is
# indistinguishable from a harness that never reached the tool at all — a bad PATH, a stub that
# refused every call, a fixture directory that was never written. Prove the driver reaches the
# bin and that the bin reached the stub before trusting any emptiness.
# ---------------------------------------------------------------------------
echo "== positive control — the harness drives the real bin through the stub =="
_fix_reset
_wf_plain plain.yml
_fix_run plain.yml
_fix_state plain.yml active
run_rcc
eq "the run reached a verdict (rc 0)" "0" "$RCC_RC"
eq "the report names the repo and PR" "true" "$(has 'o/n PR #7' "$RCC_OUT")"
eq "the stub was actually called (argv log is non-empty)" "false" \
   "$([[ -s "$TMP/argv" ]] && echo false || echo true)"
eq "stderr is silent on a clean run" "" "$RCC_ERR"

echo "== the FULL 40-hex head SHA is what goes on the wire =="
# ⛔ A SHORT SHA RETURNS ZERO ROWS AT HTTP 200 and reads exactly like 'no runs exist' — this
# card's own defect arriving through the query string. Asserted from the RECORDED ARGV, not
# from the tool's echo of it: the wire is the only place this claim is checkable.
eq "actions/runs was queried with the 40-hex sha" "true" \
   "$(has "head_sha=$SHA40" "$(cat "$TMP/argv")")"
eq "…and never with a truncated one" "" \
   "$(command grep -oE 'head_sha=[0-9a-f]{1,39}(&|$)' "$TMP/argv" || true)"

# ---------------------------------------------------------------------------
# THE THREE STATES, EACH DRIVEN, EACH PAIRED WITH THE STATE IT MUST NOT BE.
# ---------------------------------------------------------------------------
echo "== RAN: a run exists for this head =="
eq "the workflow is RAN" "RAN" "$(_state_of plain.yml)"
eq "…and its conclusion is printed, not judged" "true" "$(has 'pull_request/success' "$RCC_OUT")"

echo "== SKIPPED: path-filtered, and no changed file matches — CORRECT silence =="
_fix_reset
_wf_paths pathy.yml
_fix_state pathy.yml active
_fix_changed "docs/README.md" "src/app.php"
run_rcc
eq "a correctly-skipped workflow is SKIPPED" "SKIPPED" "$(_state_of pathy.yml)"
eq "…and is NOT reported MISSING" "" "$(_line MISSING pathy.yml)"
eq "…and the reason it is correct is printed" "true" \
   "$(has 'paths: no changed file matches' "$RCC_OUT")"
eq "a report with nothing missing exits 0" "0" "$RCC_RC"

echo "== MISSING: the PR matches, and no run exists — THE FINDING =="
_fix_reset
_wf_plain plain.yml
_fix_state plain.yml active
_fix_changed "docs/README.md"
run_rcc
eq "an unfiltered workflow with no run is MISSING" "MISSING" "$(_state_of plain.yml)"
eq "…and is NOT reported SKIPPED" "" "$(_line SKIPPED plain.yml)"
eq "a MISSING finding exits 1" "1" "$RCC_RC"

echo "== the three states are told apart IN ONE REPORT =="
# The discriminating case: one fixture carrying all three at once. A tool that collapsed any
# pair would still pass each single-state case above by answering that state for everything.
_fix_reset
_wf_plain plain.yml
_wf_paths pathy.yml
_fix_wf ranner.yml <<'YML'
name: ranner
on:
  pull_request:
jobs:
  a: { runs-on: ubuntu-latest, steps: [{ run: "true" }] }
YML
_fix_state plain.yml active; _fix_state pathy.yml active; _fix_state ranner.yml active
_fix_changed "docs/README.md"
_fix_run ranner.yml
run_rcc
eq "RAN"     "RAN"     "$(_state_of ranner.yml)"
eq "SKIPPED" "SKIPPED" "$(_state_of pathy.yml)"
eq "MISSING" "MISSING" "$(_state_of plain.yml)"
eq "the population line carries the denominator" "true" \
   "$(has '3 workflow file(s) — 1 ran, 1 skipped, 1 MISSING, 0 unmeasured, 0 out-of-scope' "$RCC_OUT")"

# ---------------------------------------------------------------------------
# A READ THAT RETURNED NOTHING IS NEVER COVERAGE. Each surface is broken in turn.
# ---------------------------------------------------------------------------
echo "== a TRUNCATED changed-file list makes the paths verdict UNMEASURED, not SKIPPED =="
# ⛔ The core of the card: with the file list short, 'no changed file matches' is a statement
# about the read, not about the PR. Reporting it as SKIPPED is the collapse.
_fix_reset
_wf_paths pathy.yml
_wf_plain plain.yml
_fix_state pathy.yml active; _fix_state plain.yml active
_fix_changed "docs/README.md"
CHANGED=4000; _fix_build          # the PR object says 4000; the endpoint returned 1
run_rcc
eq "the path-filtered workflow is UNMEASURED" "UNMEASURED" "$(_state_of pathy.yml)"
eq "…and is NOT reported SKIPPED" "" "$(_line SKIPPED pathy.yml)"
eq "the truncation is named with both counts" "true" \
   "$(has 'TRUNCATED — read 1 of 4000' "$RCC_OUT")"
# THE PAIRED PRESENCE WITNESS, and the pre-committed non-convergence guard: a fix that let
# UNMEASURED widen would swallow this sibling too, and this line is what reds when it does.
eq "the UNFILTERED sibling still gets a sound verdict" "MISSING" "$(_state_of plain.yml)"
eq "a run carrying both MISSING and UNMEASURED exits 1, not 2" "1" "$RCC_RC"
eq "…and the UNMEASURED block is still printed under it" "true" \
   "$(has 'is NOT '"'"'covered'"'"'' "$RCC_OUT")"

echo "== truncation with NOTHING missing exits 2, never 0 =="
_fix_reset
_wf_paths pathy.yml
_fix_state pathy.yml active
_fix_changed "docs/README.md"
CHANGED=4000; _fix_build
run_rcc
eq "unmeasured alone exits 2" "2" "$RCC_RC"
eq "the verdict line says it stands behind nothing" "true" \
   "$(has 'rc 2 — this run stands behind nothing' "$RCC_OUT")"

echo "== a run list that is NOT WHOLE refuses the whole report =="
# Every MISSING is an assertion about an ABSENCE from this list. A short read would mint
# findings out of pagination, so no per-workflow verdict is emitted at all.
_fix_reset
_wf_plain plain.yml
_fix_state plain.yml active
RUNS_TOTAL=5; _fix_build          # total_count 5, zero rows returned
run_rcc
eq "a partial run list exits 2" "2" "$RCC_RC"
eq "…and emits no per-workflow verdict at all" "" "$(_state_of plain.yml)"
eq "…and says which counts disagreed" "true" "$(has 'read 0 of 5' "$RCC_ERR")"

echo "== an unreadable read surface is a refusal, one surface at a time =="
_fix_reset; _wf_plain plain.yml; _fix_state plain.yml active
for surface in "pulls/7" "actions/runs" "contents/.github/workflows" "actions/workflows"; do
    FAIL="$surface" run_rcc
    eq "unreadable '$surface' exits 2" "2" "$RCC_RC"
    eq "…nothing is reported as covered" "false" "$(has 'rc 0' "$RCC_OUT")"
    # ⛔ THE REFUSAL ITSELF, not merely the rc. Without this leg the case is satisfied by the
    # DOWNSTREAM empty-population rule — measured: a mutation replacing the workflow-directory
    # refusal with a warning left every other assertion green, because an empty listing lands on
    # rc 2 anyway. The rc is right by two mechanisms and the test could see only one of them.
    eq "…and the tool NAMES the refusal on stderr" "true" "$(has "$KB_PROG_NAME: " "$RCC_ERR")"
    eq "…as a measurement refusal, not a usage error" "false" "$(has 'usage: run-coverage-check' "$RCC_ERR")"
done
unset FAIL

echo "== an unreadable CHANGED-FILE list degrades only the path-filtered workflows =="
# The one read surface whose failure is deliberately NOT a whole-run refusal: an unfiltered
# workflow's verdict does not depend on it. Driven separately because the sweep above cannot
# reach it — `pulls/7` is a substring of `pulls/7/files`, so that case refuses at the PR read.
_fix_reset
_wf_paths pathy.yml
_wf_plain plain.yml
_fix_state pathy.yml active; _fix_state plain.yml active
FAIL="pulls/7/files" run_rcc
unset FAIL
eq "the path-filtered workflow is UNMEASURED" "UNMEASURED" "$(_state_of pathy.yml)"
eq "…and is NOT reported SKIPPED" "" "$(_line SKIPPED pathy.yml)"
eq "the unfiltered sibling keeps a sound verdict" "MISSING" "$(_state_of plain.yml)"
eq "the unreadable list is named as unreadable, not as zero files" "true" \
   "$(has 'changed files UNREADABLE' "$RCC_OUT")"

echo "== a workflow body that reads back EMPTY at rc 0 is UNMEASURED, not out-of-scope =="
# ⛔ The tool's own thesis, one level down: the `on:` reader would say "no top-level on: key"
# and file it as a shrug, when what happened is that the read returned nothing.
_fix_reset
_wf_plain plain.yml
: > "$FIX/wf/hollow.yml"; _fix_build
_fix_state plain.yml active; _fix_state hollow.yml active
run_rcc
eq "an empty body is UNMEASURED" "UNMEASURED" "$(_state_of hollow.yml)"
eq "…and says the read returned nothing" "true" "$(has 'read back EMPTY at rc 0' "$RCC_OUT")"
eq "…and it is counted in the population, not dropped" "true" \
   "$(has '2 workflow file(s)' "$RCC_OUT")"

echo "== a listing entry that cannot go in a request path is UNMEASURED, not dropped =="
_fix_reset
_wf_plain plain.yml
printf 'name: x\non:\n  pull_request:\n' > "$FIX/wf/we?ird.yml"; _fix_build
_fix_state plain.yml active
run_rcc
eq "the refused name is reported" "true" "$(has 'will not put in a request path' "$RCC_OUT")"
eq "…and the denominator still counts it" "true" "$(has '2 workflow file(s)' "$RCC_OUT")"

echo "== an unreadable WORKFLOW FILE is UNMEASURED for that file only =="
_fix_reset
_wf_plain plain.yml
_fix_wf unreadable.yml <<'YML'
name: x
on:
  pull_request:
YML
_fix_state plain.yml active; _fix_state unreadable.yml active
_fix_run plain.yml
FAIL="workflows/unreadable.yml" run_rcc
unset FAIL
eq "the unreadable file is UNMEASURED" "UNMEASURED" "$(_state_of unreadable.yml)"
eq "the readable sibling still gets its verdict" "RAN" "$(_state_of plain.yml)"
eq "the run exits 2" "2" "$RCC_RC"

echo "== an EMPTY workflow population is rc 2, never rc 0 =="
_fix_reset
run_rcc
eq "no workflow files at all exits 2" "2" "$RCC_RC"

echo "== a population that is ENTIRELY out-of-scope is rc 2, never rc 0 =="
# Nothing was decided, so nothing is covered — the emptiness is in the derivation this time.
_fix_reset
_fix_wf pushonly.yml <<'YML'
name: pushy
on:
  push:
    branches: [main]
YML
_fix_state pushonly.yml active
run_rcc
eq "the push-only workflow is OUT-OF-SCOPE" "true" "$(has 'no pull_request trigger (on: push)' "$RCC_OUT")"
eq "…and a report that decided nothing exits 2" "2" "$RCC_RC"

# ---------------------------------------------------------------------------
# THE `on:` READER — the shapes it reads, and the shapes it REFUSES.
# ---------------------------------------------------------------------------
echo "== branches: filters on the BASE ref =="
_fix_reset
_fix_wf mainonly.yml <<'YML'
name: mainonly
on:
  pull_request:
    branches: [main]
YML
_fix_state mainonly.yml active
run_rcc     # base is dev
eq "a base ref outside branches: is SKIPPED" "SKIPPED" "$(_state_of mainonly.yml)"
eq "…with the base ref named" "true" "$(has 'branches: does not match base ref dev' "$RCC_OUT")"
BASEREF=main; _fix_build
run_rcc
eq "…and the SAME workflow on a matching base is MISSING" "MISSING" "$(_state_of mainonly.yml)"

echo "== paths-ignore: expects a run iff some changed file is NOT ignored =="
_fix_reset
_fix_wf ign.yml <<'YML'
name: ign
on:
  pull_request:
    paths-ignore:
      - 'docs/**'
YML
_fix_state ign.yml active
_fix_changed "docs/a.md" "docs/b/c.md"
run_rcc
eq "every changed file ignored ⇒ SKIPPED" "SKIPPED" "$(_state_of ign.yml)"
_fix_changed "bin/x"
run_rcc
eq "one file outside the ignore set ⇒ MISSING" "MISSING" "$(_state_of ign.yml)"

echo "== '!' negation is applied IN ORDER, later pattern wins =="
_fix_reset
_fix_wf neg.yml <<'YML'
name: neg
on:
  pull_request:
    paths:
      - 'bin/**'
      - '!bin/vendor/**'
YML
_fix_state neg.yml active
_fix_changed "bin/vendor/lib.sh"
run_rcc
eq "a negated subpath does not match" "SKIPPED" "$(_state_of neg.yml)"
_fix_changed "bin/tool"
run_rcc
eq "a sibling outside the negation does" "MISSING" "$(_state_of neg.yml)"

echo "== '*' does not cross a slash; '**' does =="
_fix_reset
_fix_wf star.yml <<'YML'
name: star
on:
  pull_request:
    paths:
      - 'bin/*'
YML
_fix_state star.yml active
_fix_changed "bin/sub/deep.sh"
run_rcc
eq "'bin/*' does not match bin/sub/deep.sh" "SKIPPED" "$(_state_of star.yml)"
_fix_changed "bin/flat.sh"
run_rcc
eq "'bin/*' matches bin/flat.sh" "MISSING" "$(_state_of star.yml)"

echo "== a types: list without 'synchronize' is annotated, not excused =="
# This IS the card#7594 / card#7597 shape: a gate that stops reporting on every push after the
# first. It must still be EXPECTED (so its absence is a finding), and the weakness must be said.
_fix_reset
_fix_wf title.yml <<'YML'
name: title
on:
  pull_request:
    types: [opened, edited, reopened]
YML
_fix_state title.yml active
run_rcc
eq "it is still MISSING, not excused" "MISSING" "$(_state_of title.yml)"
eq "…and the weakness is named" "true" "$(has 'no-synchronize' "$RCC_OUT")"

echo "== a types: list naming no confirmable activity is OUT-OF-SCOPE, not SKIPPED =="
_fix_reset
_fix_wf closed.yml <<'YML'
name: closed
on:
  pull_request:
    types: [closed]
YML
_fix_state closed.yml active
run_rcc
eq "it is not called correctly-skipped" "" "$(_line SKIPPED closed.yml)"
eq "…nor missing" "" "$(_line MISSING closed.yml)"
eq "…it is out of scope, with the reason" "true" \
   "$(has 'types names no activity this PR object can confirm' "$RCC_OUT")"

echo "== a glob feature the parser does NOT implement is UNMEASURED, never SKIPPED =="
# ⛔ `[abc]` would be escaped to four literal characters by the pattern translator, which
# matches nothing — i.e. it would read as 'correctly skipped' for every PR forever.
_fix_reset
_fix_wf klass.yml <<'YML'
name: klass
on:
  pull_request:
    paths:
      - 'bin/[abc]*.sh'
YML
_fix_state klass.yml active
_fix_changed "bin/a.sh"
run_rcc
eq "a character class is refused out loud" "UNMEASURED" "$(_state_of klass.yml)"
eq "…and is NOT silently skipped" "" "$(_line SKIPPED klass.yml)"
eq "…naming the pattern it could not read" "true" "$(has 'bin/[abc]*.sh' "$RCC_OUT")"

echo "== an on: shape the parser cannot read is UNMEASURED, naming the construct =="
_fix_reset
_fix_wf weird.yml <<'YML'
name: weird
on:
  pull_request:
    types: [opened,
            synchronize]
YML
_fix_state weird.yml active
run_rcc
eq "a multi-line flow sequence is refused" "UNMEASURED" "$(_state_of weird.yml)"
_fix_reset
_fix_wf weird2.yml <<'YML'
name: weird2
on:
  pull_request:
    unknown-filter: [x]
YML
_fix_state weird2.yml active
run_rcc
eq "an unknown pull_request filter key is refused" "UNMEASURED" "$(_state_of weird2.yml)"
eq "…naming the key" "true" "$(has 'filter key this parser does not read: unknown-filter' "$RCC_OUT")"

echo "== the flow form 'on: [push, pull_request]' is read =="
_fix_reset
_fix_wf flow.yml <<'YML'
name: flow
on: [push, pull_request]
YML
_fix_state flow.yml active
run_rcc
eq "a flow trigger list with pull_request is expected" "MISSING" "$(_state_of flow.yml)"

echo "== a comment inside the on: block is not read as YAML =="
_fix_reset
_fix_wf commented.yml <<'YML'
name: commented
on:
  pull_request:
    # paths:  <- this is prose, not a filter
    #   - 'nothing/**'
    types: [opened, synchronize]   # trailing comment
YML
_fix_state commented.yml active
run_rcc
eq "the commented-out paths filter is ignored" "MISSING" "$(_state_of commented.yml)"
eq "…and no glob refusal was raised" "" "$(_line UNMEASURED commented.yml)"

echo "== a DISABLED workflow is SKIPPED, not MISSING =="
_fix_reset
_wf_plain plain.yml
_fix_state plain.yml disabled_manually
run_rcc
eq "a disabled workflow is not a finding" "SKIPPED" "$(_state_of plain.yml)"
eq "…and the state is named" "true" "$(has "state is 'disabled_manually'" "$RCC_OUT")"

echo "== a workflow absent from actions/workflows is NEW AT HEAD, not disabled =="
_fix_reset
_wf_plain plain.yml     # no _fix_state at all
run_rcc
eq "it is still MISSING" "MISSING" "$(_state_of plain.yml)"
eq "…and is annotated new-at-head" "true" "$(has 'new-at-head' "$RCC_OUT")"

echo "== a run existing where none was derived reds the DERIVATION, not the repo =="
# The one direction that says this tool's model is wrong rather than the repo's CI. Calling it
# SKIPPED would hide exactly that.
_fix_reset
_wf_paths pathy.yml
_fix_state pathy.yml active
_fix_changed "docs/README.md"
_fix_run pathy.yml
run_rcc
eq "it is UNMEASURED" "UNMEASURED" "$(_state_of pathy.yml)"
eq "…and says the derivation is what is wrong" "true" \
   "$(has 'the derivation is wrong, not the repo' "$RCC_OUT")"

# ---------------------------------------------------------------------------
# THE REFUSAL SURFACE. rc 2 is the single 'stands behind nothing' code, and a usage error is a
# member of it on purpose — see the tool's own header.
# ---------------------------------------------------------------------------
echo "== the invocation guards refuse at rc 2 with stdout empty =="
_bad() {
    local rc=0 out
    out="$(PATH="$TMP/bin:$PATH" RCC_FIX="$FIX" "$BIN" "$@" 2>/dev/null)" || rc=$?
    printf '%s/%s' "$rc" "$([[ -z "$out" ]] && echo empty || echo DATA)"
}
eq "no --repo"            "2/empty" "$(_bad --pr 7)"
eq "no --pr"              "2/empty" "$(_bad --repo o/n)"
eq "--repo not owner/name" "2/empty" "$(_bad --repo notaslug --pr 7)"
eq "--repo carrying a query" "2/empty" "$(_bad --repo 'o/n?x=1' --pr 7)"
# ⚠ A NARROWING, recorded as one (card#8421): `o/n.git` was ACCEPTED here until this flag was
# moved onto the shared `kb_is_repo_slug`, which refuses a `.git` suffix. The narrowing is the
# correct direction — the value goes into a `repos/<slug>/…` request path, and `repos/o/n.git`
# names no repository GitHub will answer for, so what used to happen was a 404 reported as an
# unreadable endpoint instead of a refusal naming the operator's own spelling.
eq "--repo with a .git suffix (narrowed)" "2/empty" "$(_bad --repo 'o/n.git' --pr 7)"
eq "--pr not an integer"  "2/empty" "$(_bad --repo o/n --pr twelve)"
eq "--pr zero"            "2/empty" "$(_bad --repo o/n --pr 0)"
eq "--ref with a space"   "2/empty" "$(_bad --repo o/n --pr 7 --ref 'a b')"
eq "an unknown flag"      "2/empty" "$(_bad --repo o/n --pr 7 --gate-on-this)"
expect_value_flags "$ROOT/bin/run-coverage-check" --repo --pr --ref

echo "== the shape guards mean the same thing under a UTF-8 locale (card#5409) =="
# ⛔ A BRACKET RANGE IN A BASH PATTERN IS A COLLATION RANGE. Under en_US.UTF-8 a bare
# `^[0-9]+$` matches U+0663 ARABIC-INDIC DIGIT THREE and `^[A-Za-z0-9._-]+$` matches U+00E9 —
# and these guards decide what may be interpolated into a REQUEST PATH. Fixtures are explicit
# UTF-8 BYTE escapes: the bytes are what reach the guard, and a byte escape cannot be
# re-encoded by the shell's own locale.
AI3=$'\xd9\xa3'        # U+0663 ARABIC-INDIC DIGIT THREE
EACUTE=$'\xc3\xa9'     # U+00E9 LATIN SMALL LETTER E WITH ACUTE
eq "--pr as a non-ASCII digit is refused under C"   "2/empty" "$(LC_ALL=C _bad --repo o/n --pr "$AI3")"
eq "--repo carrying U+00E9 is refused under C"      "2/empty" "$(LC_ALL=C _bad --repo "o/n$EACUTE" --pr 7)"
# THE UTF-8 HALF IS ONLY EVIDENCE IF THIS BOX HAS A LOCALE THAT ACTUALLY WIDENS. Probed with a
# bare range in a subprocess — deliberately NOT through the guard under test — so an
# uninstalled locale says so loudly instead of passing vacuously.
WIDE=""
for _l in en_US.UTF-8 C.UTF-8 en_GB.UTF-8; do
    if LC_ALL="$_l" bash -c '[[ "$1" =~ ^[0-9]+$ ]]' _ "$AI3" 2>/dev/null; then WIDE="$_l"; break; fi
done
if [[ -n "$WIDE" ]]; then
    eq "control: $WIDE really does widen [0-9] (else the two below prove nothing)" "true" "true"
    eq "--pr as a non-ASCII digit is refused under $WIDE"  "2/empty" "$(LC_ALL="$WIDE" _bad --repo o/n --pr "$AI3")"
    eq "--repo carrying U+00E9 is refused under $WIDE"     "2/empty" "$(LC_ALL="$WIDE" _bad --repo "o/n$EACUTE" --pr 7)"
else
    printf '  SKIP  no collation-wide UTF-8 locale on this box — the two cases above certify the C locale ONLY\n' >&2
fi

echo "== a head SHA that is not 40 hex is refused BEFORE any run is queried =="
_fix_reset
_wf_plain plain.yml
HEADSHA="8623d5f"; _fix_build
run_rcc
eq "a short head sha exits 2" "2" "$RCC_RC"
eq "…naming what it refused" "true" "$(has "got '8623d5f'" "$RCC_ERR")"
eq "…and no runs endpoint was ever queried" "" \
   "$(command grep -c 'actions/runs' "$TMP/argv" | command grep -v '^0$' || true)"

echo "== --help prints the whole header on stdout, silently, at rc 0 =="
rc=0
hout="$(PATH="$TMP/bin:$PATH" "$BIN" --help 2>"$TMP/err")" || rc=$?
eq "rc 0" "0" "$rc"
eq "stderr silent" "" "$(cat "$TMP/err")"
eq "it states outright that it gates nothing" "true" "$(has 'IT GATES NOTHING, BLOCKS NOTHING' "$hout")"
eq "it states the three states" "true" "$(has 'RAN' "$hout")"

echo "== the tool WRITES nothing: every request it makes is a GET =="
# ⛔ REPORT-ONLY is a claim about the wire, so it is asserted from the recorded argv rather than
# from the header that makes it. `gh api` defaults to GET; a write would carry -X/--method or
# -f/-F/--input, and none may ever appear.
_fix_reset; _wf_plain plain.yml; _fix_state plain.yml active; _fix_run plain.yml
run_rcc
eq "argv carries no method override or request body" "" \
   "$(command grep -xE -- '-X|--method|-f|-F|--input|--raw-field' "$TMP/argv" || true)"
eq "witness: argv carries the endpoints it DID request" "true" \
   "$(has 'repos/o/n/pulls/7' "$(cat "$TMP/argv")")"

_summary "run-coverage-check-selftest"
