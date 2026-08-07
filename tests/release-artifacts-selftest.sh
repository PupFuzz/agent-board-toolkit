#!/usr/bin/env bash
# release-artifacts-selftest.sh — deterministic, network-free checks for
# `bin/release-artifacts-check`, against a THROWAWAY fixture git repo under mktemp.
#
# WHY THIS FILE EXISTS. `.release-pr.json`'s `artifacts` array names the must-move-together
# release set, and its only consumer was a PRINTER (`release-pr-body` renders it as a `- [ ]`
# checklist). Nothing asserted a member actually moved, so the class defect — a guard that
# reads a proper SUBSET of a must-move-together file set cannot fail on the member it never
# reads — had a subset of size zero here (card#5910).
#
# EVERY DEFECT CLASS THE TOOL CLAIMS TO CATCH IS WATCHED TO FAIL BELOW — the git-state ones
# on their own fixture branch, the config ones on their own config file:
#   * a declared member that did not move;
#   * a `docs/CHANGELOG.md` that moved without gaining its `## [V]` section;
#   * a member DELETED — which APPEARS in the diff, so the moved-leg alone passes it;
#   * two failing members reported as two, not as the first one;
#   * an unreadable version file at either end — which must refuse, rc 2, and never classify
#     as "not a release PR", since that is a silent non-run of the whole gate;
#   * a config entry that expands to NO path (an empty brace set, or a leading-whitespace
#     entry) — which would drop a declared member from both the assertions and the count.
# That last pair is the tool's own defect class one layer up, and its rc assertion is not
# decoration: `_expand_braces` is consumed through a process substitution, so a `die` placed
# INSIDE it printed the right message and then let the run finish rc 0 with the member
# silently dropped. Only the exit-status leg saw that.
#
# The happy paths are equally load-bearing, as the controls for all of the above: a
# version-unchanged PR and a fully-correct release PR must both exit 0, else "fails on defect
# X" would also be true of a tool that fails on everything.
#
# NEVER OPERATES ON THE REAL CHECKOUT. The fixture is built by `git init` under mktemp and
# removed by the prelude's EXIT trap. No `git checkout --` anywhere: that command destroys
# uncommitted work in whatever tree it is pointed at, and a selftest is not a place to find
# out which tree that was.
#
# WHAT A GREEN RUN HERE PROVES — the weakest property the assertions support: that the tool
# reports the four defect shapes above on fixtures carrying them, and exits 0 on the two
# clean shapes. It says nothing about whether any REAL repo's `artifacts` array enumerates
# the right set — an under-declared set is invisible to this tool by construction.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/release-artifacts-check"
_need -x "$BIN"

# Deterministic git identity/config, independent of the runner's.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_mktmp_scratch; T="$TMP"     # the prelude owns cleanup
R="$T/repo"

# run <base> <head> [extra args...] — invoke the tool in the fixture repo, capturing both
# streams together (the failure lines go to stdout as `::error::`, the summary to stderr) and
# the exit status. Sets RC and OUT.
run() {
  local base="$1" head="$2"; shift 2
  RC=0
  OUT="$( (cd "$R" && "$BIN" --base "$base" --head "$head" "$@") 2>&1 )" || RC=$?
}

# --- fixture ----------------------------------------------------------------
# Four declared members across three shapes: a plain version-bearing file, the
# `[{{version}}] section` shape, a prose-suffixed row shape, and a brace-set whose FILENAME
# carries the version (so the "path contains V ⇒ agrees" arm is exercised).
mkdir -p "$R"
g init -q "$R"
mkdir -p "$R/docs" "$R/sboms"
# A root commit that predates the version file, kept as its own branch. It is an ANCESTOR of
# everything below, so `merge-base pre-version <head>` resolves to it — which is what makes
# the unreadable-version-file case reachable through a real fork point rather than only
# through two refs with no common history (that case has its own fixture further down).
echo "seed" > "$R/src.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: root, before the version file exists"
g -C "$R" branch pre-version

cat > "$R/.release-pr.json" <<'JSON'
{
  "main_branch": "main",
  "dev_branch": "dev",
  "version_file": "VERSION",
  "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": [
    "VERSION → {{version}}",
    "docs/CHANGELOG.md → [{{version}}] section",
    "NOTES.md § Recent releases row",
    "sboms/v{{version}}.{a,b}.json"
  ]
}
JSON
echo "0.1.0" > "$R/VERSION"
printf '# Changelog\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md"
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
echo '{"v":"0.1.0"}' > "$R/sboms/v0.1.0.a.json"
echo '{"v":"0.1.0"}' > "$R/sboms/v0.1.0.b.json"
echo "unrelated" > "$R/src.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: baseline at 0.1.0"
g -C "$R" branch base-0.1.0

# bump_to_0_2_0 <mode> — materialize a head state on a fresh branch off base-0.1.0.
# One builder, one branch per mode, so each case differs from the correct one by exactly the
# defect it is named for (a per-case hand-built tree would let two things drift at once).
mk_head() {
  local branch="$1" mode="$2"
  g -C "$R" checkout -q -B "$branch" base-0.1.0
  case "$mode" in
    nonrelease)
      echo "changed, but no version bump" > "$R/src.txt"
      ;;
    good|deleted|two-bad|no-section|not-moved)
      echo "0.2.0" > "$R/VERSION"
      case "$mode" in
        no-section)
          # moved, but the new section header is missing — the exact shape a hand-edited
          # changelog takes when the entry lands under the previous version's heading.
          printf '# Changelog\n\n## [0.1.0] - 2026-01-01\n\n- first\n- second, filed under the OLD heading\n' > "$R/docs/CHANGELOG.md"
          ;;
        *)
          printf '# Changelog\n\n## [0.2.0] - 2026-02-02\n\n- second\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md"
          ;;
      esac
      case "$mode" in
        not-moved|two-bad) : ;;   # NOTES.md deliberately left at its 0.1.0 content
        *) printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md" ;;
      esac
      echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
      case "$mode" in
        two-bad) : ;;             # the `b` member of the brace set is never created
        *) echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.b.json" ;;
      esac
      ;;
  esac
  # Removed from the WORKING TREE, then staged by `add -A` — `git rm` would refuse a path
  # whose modification is already staged, and `-f` to force it is not worth the reach.
  if [ "$mode" = deleted ]; then rm -f "$R/NOTES.md"; fi
  g -C "$R" add -A
  g -C "$R" commit -qm "release: $mode"
}

for m in nonrelease good not-moved no-section deleted two-bad; do mk_head "head-$m" "$m"; done

# A head that deletes the version file — the HEAD-side unreadable read, with a readable fork
# point, so the two ends fail closed independently rather than one masking the other.
g -C "$R" checkout -q -B head-noversion base-0.1.0
rm -f "$R/VERSION"
g -C "$R" add -A; g -C "$R" commit -qm "chore: head with no VERSION file"

# --- the BASE-DRIFT scenario (the two-dot defect) ----------------------------
# `drift-fork` is the fork point, and it ALREADY carries NOTES.md's v0.2.0 row — the realistic
# case where a member was updated on the integration branch before the release branch was cut.
# `drift-base` is the base branch moving ON after the fork (a hotfix touching that same
# member). `drift-head` is the release PR: it bumps the version and moves everything EXCEPT
# NOTES.md, which it never touches.
#
# Under a base-TIP (two-dot) diff, NOTES.md differs between drift-base and drift-head, so it
# appears in the diff and satisfies the MOVED leg; it exists at head and its content carries
# 0.2.0, so AGREES passes too — a full, silent, spurious PASS for a member this PR never
# touched. Against the merge base it is correctly absent. This is the fixture that tells the
# two implementations apart, so both verdicts are asserted explicitly below.
g -C "$R" checkout -q -B drift-fork base-0.1.0
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
g -C "$R" add -A; g -C "$R" commit -qm "docs: NOTES.md row added before the release branch was cut"

g -C "$R" checkout -q -B drift-base drift-fork
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 (hotfix touched this line) |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
g -C "$R" add -A; g -C "$R" commit -qm "fix: a hotfix lands on the base branch after the fork"

g -C "$R" checkout -q -B drift-head drift-fork
echo "0.2.0" > "$R/VERSION"
printf '# Changelog\n\n## [0.2.0] - 2026-02-02\n\n- second\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md"
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.b.json"
g -C "$R" add -A; g -C "$R" commit -qm "release: 0.2.0 without touching NOTES.md"

# --- the BASE-BUMP scenario (the two-dot MISCLASSIFICATION) ------------------
# The base branch acquires the SAME version as the PR after the fork. Reading base's tip then
# says "version unchanged ⇒ not a release PR" and the entire gate silently does not run, on a
# PR that IS a release and IS missing a member.
g -C "$R" checkout -q -B bump-base base-0.1.0
echo "0.2.0" > "$R/VERSION"
g -C "$R" add -A; g -C "$R" commit -qm "chore: a version bump lands on the base branch after the fork"

# Two refs with NO common ancestor — the merge base itself is unresolvable.
g -C "$R" checkout -q --orphan unrelated
g -C "$R" rm -rq --cached . >/dev/null 2>&1 || true
g -C "$R" clean -qfd
echo "an unrelated history" > "$R/other.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: an unrelated root"

g -C "$R" checkout -q base-0.1.0

# two_dot_moved / merge_base_moved <base> <head> <path> — what each range says about the MOVED
# leg, computed from raw git rather than from the tool, so the fixture's discriminating power
# is established independently of the implementation being tested.
two_dot_moved() {
  local d; d="$(g -C "$R" diff --name-only "$1" "$2")"
  case $'\n'"$d"$'\n' in *$'\n'"$3"$'\n'*) echo true ;; *) echo false ;; esac
}
merge_base_moved() {
  local mb d; mb="$(g -C "$R" merge-base "$1" "$2")"; d="$(g -C "$R" diff --name-only "$mb" "$2")"
  case $'\n'"$d"$'\n' in *$'\n'"$3"$'\n'*) echo true ;; *) echo false ;; esac
}
ver_at() { g -C "$R" show "$1:VERSION" 2>/dev/null | tr -d '[:space:]'; }

echo "== precondition: the fixture is a throwaway repo, not this checkout =="
eq "fixture root is under the temp dir" "true" \
   "$(case "$(g -C "$R" rev-parse --show-toplevel)" in "$T"/*) echo true ;; *) echo false ;; esac)"

# ---------------------------------------------------------------------------
# The two clean shapes. They are also the CONTROLS for every defect case below: without
# them, "reports defect X" would be equally true of a tool that reports everything.
# ---------------------------------------------------------------------------
echo "== (i) a non-release PR (version unchanged) asserts nothing and exits 0 =="
run base-0.1.0 head-nonrelease
eq "rc 0"                              "0"    "$RC"
eq "…and says why it asserted nothing" "true" "$(has 'version unchanged (0.1.0)' "$OUT")"
eq "…and names no artifact"            "false" "$(has '::error::' "$OUT")"

echo "== (ii) a correct release PR passes every declared member and exits 0 =="
run base-0.1.0 head-good
eq "rc 0"                                   "0"    "$RC"
eq "VERSION passes"                         "true" "$(has 'OK — VERSION moved' "$OUT")"
eq "the [V] section member passes"          "true" "$(has 'OK — docs/CHANGELOG.md moved' "$OUT")"
eq "the prose-suffixed row member passes"   "true" "$(has 'OK — NOTES.md moved' "$OUT")"
eq "brace-set member a passes"              "true" "$(has 'OK — sboms/v0.2.0.a.json moved' "$OUT")"
eq "brace-set member b passes"              "true" "$(has 'OK — sboms/v0.2.0.b.json moved' "$OUT")"
# The count is what proves the brace set EXPANDED rather than being asserted as one literal
# path: four declared entries, five members.
eq "the summary counts 5 members from 4 entries" "true" \
   "$(has 'all 5 declared artifact member(s) moved and agree with 0.2.0' "$OUT")"
eq "no failure lines"                       "false" "$(has '::error::' "$OUT")"

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL — one fixture per defect class, each seen to red.
# ---------------------------------------------------------------------------
echo "== (iii-a) POSITIVE CONTROL: a declared member that did not move is REPORTED =="
run base-0.1.0 head-not-moved
eq "rc 1"                                    "1"    "$RC"
eq "the failure is an ::error:: annotation"  "true" "$(has '::error::release artifact not moved' "$OUT")"
eq "…and names the member path"              "true" "$(has "'NOTES.md' is absent from this PR's own changes" "$OUT")"
eq "…and names the original declared entry"  "true" "$(has 'declared as: NOTES.md § Recent releases row' "$OUT")"
eq "…while the moved siblings still pass (witness: the run got past member 1)" "true" \
   "$(has 'OK — VERSION moved' "$OUT")"
eq "the summary counts exactly one failure"  "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-b) POSITIVE CONTROL: a CHANGELOG that moved without its ## [V] section =="
run base-0.1.0 head-no-section
eq "rc 1"                                   "1"    "$RC"
eq "the failure is the AGREES leg, not the moved leg" "true" \
   "$(has "::error::release artifact does not agree: 'docs/CHANGELOG.md'" "$OUT")"
eq "…and names the section line it wanted"  "true" "$(has "no '## [0.2.0]' section line" "$OUT")"
eq "…and the moved leg did NOT fire for it" "false" \
   "$(has "not moved: 'docs/CHANGELOG.md'" "$OUT")"
eq "exactly one member failed"              "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-c) POSITIVE CONTROL: a DELETED member fails, though it IS in the diff =="
# The whole point of the exists-at-head leg: a deletion satisfies "moved". A moved-only guard
# passes this fixture, so the witness below (the moved leg staying silent) is load-bearing.
run base-0.1.0 head-deleted
eq "rc 1"                                    "1"    "$RC"
eq "witness: the deletion DOES satisfy the moved leg" "false" \
   "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and the exists-at-head leg is what fails" "true" \
   "$(has "::error::release artifact missing at head: 'NOTES.md'" "$OUT")"
eq "exactly one member failed"               "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-d) POSITIVE CONTROL: an unreadable version_file at the FORK POINT refuses (rc 2) =="
# It must NOT read as "version unchanged ⇒ not a release PR": that misclassification is a
# silent non-run of the entire gate, which is strictly worse than a loud refusal.
run pre-version head-good
eq "rc 2"                                        "2"    "$RC"
eq "the error names the file"                    "true" "$(has "cannot read 'VERSION' at" "$OUT")"
# The resolved merge base appears in none of the caller's inputs, so the message must say
# which END of the range it is, not just print a bare SHA.
eq "…and names WHICH end of the range it is"     "true" "$(has "the fork point of 'pre-version' and 'head-good'" "$OUT")"
eq "…and names the fetch-depth precondition"     "true" "$(has 'fetch-depth: 0' "$OUT")"
eq "…and did NOT classify it as a non-release PR" "false" "$(has 'version unchanged' "$OUT")"
eq "…and asserted no member"                     "false" "$(has 'artifact member(s) failed' "$OUT")"

echo "== an unreadable version_file at HEAD refuses the same way (both ends fail closed) =="
# A readable fork point, so this end fails on its own rather than being masked by the other.
run base-0.1.0 head-noversion
eq "rc 2"                                 "2"    "$RC"
eq "the error names the head end"         "true" "$(has "cannot read 'VERSION' at head 'head-noversion'" "$OUT")"

echo "== two refs with no common ancestor refuse — never a 'not a release PR' pass =="
run unrelated head-good
eq "rc 2"                                    "2"    "$RC"
eq "the error names both refs"               "true" "$(has "merge base of 'unrelated' and 'head-good'" "$OUT")"
eq "…and the fetch-depth precondition"       "true" "$(has 'fetch-depth: 0' "$OUT")"
eq "…and did NOT classify it as non-release" "false" "$(has 'version unchanged' "$OUT")"

echo "== (iii-e) EVERY failing member is reported, not just the first =="
# NOTES.md never moves AND the brace set's `b` member is never created: two independent
# failures, in two different legs, from two different declared entries.
run base-0.1.0 head-two-bad
eq "rc 1"                                     "1"    "$RC"
eq "failure 1 named (a whole entry that did not move)" "true" \
   "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "failure 2 named (one member of a brace set)"       "true" \
   "$(has "not moved: 'sboms/v0.2.0.b.json'" "$OUT")"
eq "the sibling brace member still passes"    "true" "$(has 'OK — sboms/v0.2.0.a.json moved' "$OUT")"
eq "the summary counts BOTH"                  "true" "$(has '2 of 5 artifact member(s) failed' "$OUT")"

# ---------------------------------------------------------------------------
# THE RANGE IS THE PR'S OWN CHANGES — merge-base(base, head)..head, never base's tip.
# Both legs below are RED under a base-tip (two-dot) range and GREEN against the merge base,
# and the raw-git facts that make them differ are asserted FIRST — otherwise "the tool says
# rc 1" would be equally true of a tool that had never been fixed.
# ---------------------------------------------------------------------------
echo "== base drift after the fork must not satisfy the MOVED leg (two-dot defect) =="
# The fixture's discriminating power, established from raw git, independent of the tool:
eq "witness: a base-tip range WOULD have called NOTES.md moved" "true" \
   "$(two_dot_moved drift-base drift-head NOTES.md)"
eq "…while the PR's own changes do NOT contain it"              "false" \
   "$(merge_base_moved drift-base drift-head NOTES.md)"
# …and the member is otherwise fully satisfiable, which is what makes the two-dot pass SILENT
# rather than merely wrong on one leg: it exists at head and its content carries the version.
eq "witness: NOTES.md at head carries 0.2.0 (so AGREES would have passed too)" "true" \
   "$(has 'v0.2.0' "$(g -C "$R" show drift-head:NOTES.md)")"

run drift-base drift-head
eq "the tool FAILS on the unmoved member"        "1"    "$RC"
eq "…naming it"                                  "true" "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and describing the range as the PR's own changes" "true" \
   "$(has "this PR's own changes (drift-base...drift-head)" "$OUT")"
eq "…while the members the PR DID move still pass" "true" \
   "$(has 'OK — docs/CHANGELOG.md moved' "$OUT")"
# CONTROL — the same head against the fork point itself. Identical verdict, which is the
# point: the merge-base resolution NORMALIZES base drift away rather than reacting to it.
run drift-fork drift-head
eq "control: against the fork point directly, the same verdict" "1"    "$RC"
eq "control: …and the same member"                              "true" "$(has "not moved: 'NOTES.md'" "$OUT")"

echo "== a version bump landing on BASE after the fork must not misclassify the PR =="
# The worst of the two shapes: a base-tip read makes a real release PR look like a non-release
# one, so the gate exits 0 and asserts NOTHING while a member is genuinely missing.
eq "witness: base's TIP and head carry the SAME version (two-dot ⇒ 'unchanged')" "0.2.0" \
   "$(ver_at bump-base)"
eq "witness: …and head does too"                                   "0.2.0" "$(ver_at head-not-moved)"
eq "witness: …while the FORK POINT carries the older one"          "0.1.0" \
   "$(ver_at "$(g -C "$R" merge-base bump-base head-not-moved)")"

run bump-base head-not-moved
eq "the tool classifies it as a release PR and FAILS"  "1"     "$RC"
eq "…rather than exiting 0 as 'version unchanged'"     "false" "$(has 'version unchanged' "$OUT")"
eq "…naming the missing member"                        "true"  "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and counting the full declared set"               "true"  "$(has 'of 5 artifact member(s) failed' "$OUT")"

# ---------------------------------------------------------------------------
# Config / usage surface.
# ---------------------------------------------------------------------------
echo "== a config with no artifacts array asserts nothing and exits 0 =="
# Checked BEFORE the version legs: a repo that never opted in must not be refused by a
# fail-closed version read it has no reason to satisfy.
cat > "$R/no-artifacts.json" <<'JSON'
{ "version_file": "NO-SUCH-FILE", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+" }
JSON
run base-0.1.0 head-good --config no-artifacts.json
eq "rc 0"                        "0"    "$RC"
eq "…and says so"                "true" "$(has 'no artifacts declared — nothing to assert' "$OUT")"
# CONTROL — same repo, same range, a config that DOES declare a set must assert it, so the
# arm above is discriminating rather than vacuously green.
run base-0.1.0 head-good
eq "control: the real config DOES assert" "true" "$(has 'all 5 declared artifact member(s)' "$OUT")"

echo "== an EMPTY artifacts array is the same non-opt-in, not a vacuous pass =="
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": [] }' > "$R/empty-artifacts.json"
run base-0.1.0 head-good --config empty-artifacts.json
eq "rc 0"          "0"     "$RC"
eq "…and says so"  "true"  "$(has 'no artifacts declared' "$OUT")"
eq "…and claims no members passed" "false" "$(has 'declared artifact member(s) moved' "$OUT")"

echo "== a declared member that would expand to NOTHING is refused, never dropped =="
# Both shapes silently produce zero paths, so the member would be neither asserted nor
# counted — this tool's own defect class (a declared member no assertion ever reads) one
# layer up. Each is paired with the count the CORRECT config produces, so "refused" is
# distinguishable from "the run never got that far".
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "sboms/v{{version}}{}.json"] }' > "$R/empty-brace.json"
run base-0.1.0 head-good --config empty-brace.json
eq "an empty brace set → rc 2"       "2"     "$RC"
eq "…and names the offending path"   "true"  "$(has 'expands to no member' "$OUT")"
# The refusal must reach the SCRIPT's exit status, not just its stderr. `_expand_braces` is
# consumed through a process substitution, whose `exit` unwinds the subshell only — a `die`
# placed there printed this very message and then let the run finish rc 0 with the member
# dropped from both the assertions and the count. rc alone is the check that saw that.
eq "…rather than quietly finishing with the member dropped" "false" \
   "$(has 'artifact member(s) moved and agree' "$OUT")"

printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "   docs/CHANGELOG.md → [{{version}}] section"] }' > "$R/leading-space.json"
run base-0.1.0 head-good --config leading-space.json
eq "a leading-whitespace entry → rc 2" "2"    "$RC"
eq "…and echoes the entry"             "true" "$(has 'no leading path token' "$OUT")"

# CONTROL — the same two entries, well-formed, DO assert and count.
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "docs/CHANGELOG.md → [{{version}}] section"] }' > "$R/two-well-formed.json"
run base-0.1.0 head-good --config two-well-formed.json
eq "control: the well-formed pair passes"  "0"    "$RC"
eq "control: …and counts BOTH members"     "true" "$(has 'all 2 declared artifact member(s)' "$OUT")"

echo "== a declared set with no version_file is a CONFIG error, not a pass =="
printf '%s\n' '{ "artifacts": ["VERSION → {{version}}"] }' > "$R/no-version-file.json"
run base-0.1.0 head-good --config no-version-file.json
eq "rc 2"                    "2"    "$RC"
eq "…and names what is missing" "true" "$(has 'no version_file' "$OUT")"

echo "== value-taking flags reject an EMPTY value, and both refs are required =="
for f in --base --head --config; do
  rc=0; err="$("$BIN" "$f" "" 2>&1)" || rc=$?
  eq "$f \"\" → rc 2"         "2"    "$rc"
  eq "$f \"\" names the flag" "true" "$(has "$f requires a non-empty value" "$err")"
done
rc=0; err="$("$BIN" --base 2>&1)" || rc=$?
eq "trailing --base → rc 2"               "2"     "$rc"
eq "trailing --base does not leak set -u" "false" "$(has 'unbound variable' "$err")"
rc=0; err="$( (cd "$R" && "$BIN" --head head-good) 2>&1 )" || rc=$?
eq "a missing --base is refused"          "2"     "$rc"
eq "…by name"                             "true"  "$(has '--base <ref> is required' "$err")"
rc=0; err="$( (cd "$R" && "$BIN" --base base-0.1.0) 2>&1 )" || rc=$?
eq "a missing --head is refused"          "2"     "$rc"
eq "…by name"                             "true"  "$(has '--head <ref> is required' "$err")"
rc=0; err="$("$BIN" --nope 2>&1)" || rc=$?
eq "an unknown flag is refused"           "2"     "$rc"
eq "…by name"                             "true"  "$(has "unknown arg '--nope'" "$err")"

_summary "release-artifacts-selftest"
