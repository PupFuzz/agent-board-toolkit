#!/usr/bin/env bash
# changelog-card-entry-selftest.sh — the FIXTURES for `bin/changelog-gate`, the CHANGELOG
# `[Unreleased]` gate. This file sources the bin and drives its rule functions — and, from the
# "END TO END" section on, the bin itself — against throwaway repositories carrying known data.
# It runs NO live leg: the live judgement of this repository is `bin/changelog-gate`, run by the
# second step of `.github/workflows/changelog-card-entry.yml` through `./changelog-gate`
# (card#11698). The bin's header owns the rule; nothing here restates it.
#
# WHY THE MACHINERY IS FIXTURE-PROVEN. Right after a release both streams the gate compares are
# genuinely empty (no commits since the tag; `[Unreleased]` emptied by the fold), so "non-empty"
# cannot be asserted against a live repository without a false red on the first PR of every
# cycle. Every red the gate can give is therefore shown here on a fixture carrying a known member,
# beside a fixture on which the same code must go GREEN — without which "always reports
# something" would satisfy every can-fail leg vacuously.
#
# WHAT THE FIXTURES COVER, by the bin's legs:
#   * the token leg — leftmost-token obligations, the R2 bullet grammar (`BULLET_RE`, the lead,
#     every `card#N` in it), the region's floor and ceiling, the PR-title source, and "released"
#     decided by patch / PR identity (the cherry-pick release, card#11034);
#   * `changelog.exempt_paths` judged per landed unit, including the one shape where the PR run
#     and a merge-commit push run disagree — asserted as that divergence, not hidden;
#   * the remedy beside a red: the fold arm (card#8442), the carried-entry arm, the generic one;
#   * `_squash_ends`' admission of a PR delta and its refusal on release and back-merge PRs;
#   * end to end through the bin: the announce leg and its classification skip, the classifier's
#     refusal and its `::warning::` relay, the release-body size arm, where `changelog.*` is read
#     on each run kind (fork point, release cut, HEAD) and the refusals that read can hit, the
#     unknown-key warning and the `tag_format` refusal.
# ⛔ NO DUPLICATE SHAPE IS FIXTURED, because the bin reports none (card#11684 R8, D10).
#
# WHAT A GREEN RUN HERE PROVES — that each named function and each named run of the bin answers
# as asserted on these fixtures, under this host's git, awk and jq. Nothing about this
# repository's own CHANGELOG, which the workflow's second step judges.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$HERE/.."
GATE="$ROOT/bin/changelog-gate"
_need -x "$GATE"
_mktmp_scratch
# The bin's functions, verbatim: the fixtures test the code the live run executes, not a
# paraphrase of it. Its run guard keeps the live leg from firing when sourced.
# shellcheck source=bin/changelog-gate
source "$GATE"

# ---------------------------------------------------------------------------
# Fixtures FIRST — the machinery is proven against known data before the live repo's answer is
# trusted, because that answer is an assertion of absence and "" is what both a clean repo and
# a broken extractor return.
# ---------------------------------------------------------------------------
FIX="$TMP/fixture"
mkdir -p "$FIX"

# Four subjects, one per case: documented, prose-only, released-section-only, and no token.
cat > "$FIX/subjects" <<'EOF'
feat(kbcard): a documented change (card#9001) (#500)
test(x): the one whose only mention is prose (card#9002) (#501)
fix(y): the one documented under an already-released version (card#9003) (#502)
chore(deps): Bump actions/checkout from 7.0.0 to 7.0.1 (#503)
EOF

# card#9002 appears ONLY mid-bullet and BOLD — the card#5374 shape, sharpened. If the rule were
# "the file mentions the card", or even "a bold token appears in a bullet", this fixture would
# discharge it. Line-initial is the only spelling that does not.
cat > "$FIX/changelog.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#9001** — a real entry, and it also supersedes **card#9002** in passing.

## [0.23.1] - 2026-07-27

### Added
- **card#9003** — documented, but under a version that shipped before these commits.
EOF

echo "== positive control — the extractors see real data on a known fixture =="
# Named members, not counts: a count pins the check to today's fixture and rots when a case is
# added, while a member that must be present re-derives nothing.
eq "obligations are extracted, and the no-token subject contributes none" \
   "card#9001
card#9002
card#9003" "$(_obliged "$FIX/subjects")"
eq "discharges are extracted, scoped above the stop header" \
   "card#9001" "$(_discharged "$FIX/changelog.md" "0.23.1")"
eq "the fixture's stop header is found (scoping is real, not a no-op scan)" "true" \
   "$(_has_version_header "$FIX/changelog.md" "0.23.1" && echo true || echo false)"
# The FALSE arm, without which `_has_version_header` could be a function that always says yes
# and the live precondition guarding the only err-GREEN path would never be able to fire. It is
# checked here rather than only against a real checkout because CI runs this file, not that
# experiment. Two shapes: the header genuinely absent, and a version that merely APPEARS in the
# file without being a section header of its own.
grep -v '^## \[0\.23\.1\]' "$FIX/changelog.md" > "$FIX/changelog-noheader.md"
eq "a CHANGELOG with no stop header is REPORTED as missing it" "false" \
   "$(_has_version_header "$FIX/changelog-noheader.md" "0.23.1" && echo true || echo false)"
eq "a version named only in prose is not mistaken for its section header" "false" \
   "$(_has_version_header "$FIX/changelog.md" "0.9.0" && echo true || echo false)"
# And the consequence that precondition exists to prevent, shown rather than asserted about:
# with the stop header gone the scan reaches the released section, and card#9003's old entry
# silently discharges a commit that landed after the tag.
eq "without the stop header, a released-section entry wrongly discharges (errs GREEN)" \
   "card#9002" "$(_missing "$FIX/subjects" "$FIX/changelog-noheader.md" "0.23.1")"

echo "== prove-it-can-fail: an undocumented card is REPORTED =="
eq "the prose-only and released-section-only cards are named" \
   "card#9002
card#9003" "$(_missing "$FIX/subjects" "$FIX/changelog.md" "0.23.1")"
# The witness that the comparison ran against real data rather than an empty discharge set: the
# properly documented sibling must be ABSENT from the same output.
eq "the documented sibling is NOT named (witness: discharges were seen)" "" \
   "$(_missing "$FIX/subjects" "$FIX/changelog.md" "0.23.1" | grep -x 'card#9001' || true)"

echo "== prove-it-can-PASS: a complete CHANGELOG reports nothing =="
# Without this leg, a gate that reported every card unconditionally would satisfy every
# can-fail assertion above. Same subjects, same stop header — only the entries differ.
cat > "$FIX/changelog-complete.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#9001** — a real entry, and it also supersedes **card#9002** in passing.
- **card#9002** — now documented in its own right.

### Fixed
- **card#9003** — moved up into the unreleased section where it belongs.

## [0.23.1] - 2026-07-27

### Added
- **card#8000** — an older entry that must not be read as a discharge for anything above.
EOF
eq "a complete CHANGELOG discharges every obligation" "" \
   "$(_missing "$FIX/subjects" "$FIX/changelog-complete.md" "0.23.1")"

# ---------------------------------------------------------------------------
# The region's FLOOR (card#7293). The stop header is the ceiling; until this card there was no
# floor, so the region began at line 1 and the whole preamble — the H1, the format blurb, the
# `begins at [0.8.2]` note — was inside it. A bullet filed in NO section discharged its card,
# which is not a hypothetical: the card#7227 entry landed above the `# Changelog` H1 on `dev`
# and this gate reported 21 obligations / 21 discharged over it.
#
# FOUR FIXTURES, and exactly ONE of them separates the literal `## [Unreleased]` floor from the
# generous "first `## [` header" one: the release PR that renamed `[Unreleased]` without opening
# a fresh one. Every other fixture here passes under both spellings. Its sibling — the CORRECT
# step-4 shape, fresh header plus renamed section — is the control that says the literal floor
# costs a correct release PR nothing, without which "reject everything" would satisfy it.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: a bullet above the H1 is in NO section and discharges NOTHING =="
# Same file as the complete fixture, with card#9003's entry moved out of `### Fixed` and parked
# at line 1 — the exact shape that landed on `dev`. Its two siblings stay where they belong and
# are the CONTROL: this must red on the stray bullet only, not flood.
cat > "$FIX/changelog-preamble.md" <<'EOF'
- **card#9003** — an entry parked above the H1, in no section at all.

# Changelog

All notable changes are documented here.

## [Unreleased]

### Added
- **card#9001** — a real entry, and it also supersedes **card#9002** in passing.
- **card#9002** — now documented in its own right.

## [0.23.1] - 2026-07-27

### Added
- **card#8000** — an older entry that must not be read as a discharge for anything above.
EOF
eq "the preamble bullet is NOT a discharge — its card is reported missing" \
   "card#9003" "$(_missing "$FIX/subjects" "$FIX/changelog-preamble.md" "0.23.1")"
# CONTROL, in the same run and on the same file: the two correctly-filed bullets still
# discharge. Without this the assertion above is satisfied by a `_region` that emits nothing.
eq "the correctly-filed siblings still discharge (witness: the region is not empty)" \
   "card#9001
card#9002" "$(_discharged "$FIX/changelog-preamble.md" "0.23.1")"
# And the stray line is genuinely IN the file — otherwise the fixture proves nothing about the
# floor, only about a card with no entry anywhere.
eq "the stray bullet is present in the file, just not in the region" "true" \
   "$(has_line '- **card#9003** — an entry parked above the H1, in no section at all.' \
      "$(cat "$FIX/changelog-preamble.md")")"

echo "== a CORRECT release PR keeps discharging: the renamed section is inside the region =="
# The shape step 4 of VERSIONING.md actually prescribes — retitle the accumulated `[Unreleased]`
# block as `[X.Y.Z]` AND open a fresh, empty `[Unreleased]` above it — while the newest tag is
# still the PREVIOUS version. The region therefore runs `[Unreleased]` → `[0.24.0]` → stop, and
# every bullet in the renamed section still counts. This is the leg that says the literal floor
# costs a correct release PR nothing.
awk '/^## \[Unreleased\]$/ { print; print ""; print "## [0.24.0] - 2026-08-01"; next } 1' \
    "$FIX/changelog-complete.md" > "$FIX/changelog-release-correct.md"
eq "the fixture is the step-4 shape: fresh [Unreleased], then the renamed section" \
   "## [Unreleased]
## [0.24.0] - 2026-08-01
## [0.23.1] - 2026-07-27" \
   "$({ grep '^## \[' "$FIX/changelog-release-correct.md" || true; })"
eq "the region reaches into the renamed section (witness: the floor is not the stop)" "true" \
   "$(has_line '## [0.24.0] - 2026-08-01' "$(_region "$FIX/changelog-release-correct.md" "0.23.1")")"
eq "a correct release PR's renamed section still discharges every obligation" "" \
   "$(_missing "$FIX/subjects" "$FIX/changelog-release-correct.md" "0.23.1")"

echo "== a release PR that renamed [Unreleased] without opening a fresh one REDS, on itself =="
# The step-4 VIOLATION, and the only shape on which the literal floor and a generous "first
# `## [` header" floor disagree — so this assertion is what stands between the two designs.
# It models the pre-rule v0.23.x file shape (v0.23.0/v0.23.1 are the only two of the 42 tags
# whose CHANGELOG has no `## [Unreleased]`), which is also what a release PR that skipped half
# of step 4 would ship.
#
# It MUST red here, at the PR that made the omission. Under the generous floor it would go
# green, merge and be tagged — and the renamed section would then BE the stop header, emptying
# the region and reddening every subsequent PR on `dev` instead, blaming someone who did
# nothing wrong.
sed 's/^## \[Unreleased\]$/## [0.24.0] - 2026-08-01/' "$FIX/changelog-complete.md" \
    > "$FIX/changelog-released-pr.md"
eq "the fixture really has no [Unreleased] header left" "false" \
   "$(_has_version_header "$FIX/changelog-released-pr.md" "Unreleased" && echo true || echo false)"
eq "its region is EMPTY — the renamed section is NOT accepted as the floor" "" \
   "$(_region "$FIX/changelog-released-pr.md" "0.23.1")"
eq "so every obligation reds — nothing in this file discharges anything" \
   "card#9001
card#9002
card#9003" "$(_missing "$FIX/subjects" "$FIX/changelog-released-pr.md" "0.23.1")"

echo "== no [Unreleased] above the stop ⇒ an EMPTY region, not a silent whole-file scan =="
# The floor's failure mode with nothing above the stop at all. It cannot err green — an empty
# region discharges nothing, so every obligation reds — but it would blame every shipped card for
# one missing header, which is why the live run refuses on it outright and names the cause.
printf '# Changelog\n\nA preamble and nothing else.\n\n## [0.23.1] - 2026-07-27\n\n- **card#9001** — released.\n' \
    > "$FIX/changelog-nofloor.md"
eq "the region is empty when the stop header is the only section header" "" \
   "$(_region "$FIX/changelog-nofloor.md" "0.23.1")"
eq "so nothing is discharged, and the released entry below the stop is NOT reached" "" \
   "$(_discharged "$FIX/changelog-nofloor.md" "0.23.1")"

echo "== prove-it-can-fail: the PR-title obligation is real =="
# The pre-merge half. A branch whose own commit subjects carry no token still owes an entry for
# the card in the title it will be squashed under.
cp "$FIX/subjects" "$FIX/subjects-pr"
printf '%s\n' "refactor(z): a card that only the PR title names (card#9004)" >> "$FIX/subjects-pr"
eq "a card named only by the PR title is obliged" "true" \
   "$(has_line 'card#9004' "$(_missing "$FIX/subjects-pr" "$FIX/changelog-complete.md" "0.23.1")")"


# ---------------------------------------------------------------------------
# Repository scaffolding the fixtures below build on.
# ---------------------------------------------------------------------------
g() { git -c init.defaultBranch=dev -c user.name=t -c user.email=t@example.invalid \
          -c commit.gpgsign=false -c gc.auto=0 "$@"; }

# _prepend <changelog> <bullet> — put a bullet directly under `## [Unreleased]`, the one anchor
# every entry in this repo is filed at and therefore the one every PR collides on.
_prepend() {
    awk -v b="$2" '/^## \[Unreleased\]/ { print; print ""; print b; next } 1' "$1" > "$1.t"
    mv "$1.t" "$1"
}
# _newrepo <dir> [union] — an empty changelog on `dev`, with or without the attribute.
_newrepo() {
    mkdir -p "$1"
    g init -q "$1"
    printf '# Changelog\n\n## [Unreleased]\n\n## [0.23.1] - 2026-07-27\n' > "$1/CHANGELOG.md"
    if [[ "${2:-}" == union ]]; then printf 'CHANGELOG.md merge=union\n' > "$1/.gitattributes"
    else : > "$1/.gitattributes"; fi
    g -C "$1" add -A && g -C "$1" commit -qm 'base'
}

# ---------------------------------------------------------------------------
# THE PRE-FOLD REMEDY (card#8442). `_missing`'s VERDICT is settled above and no fixture here
# moves it — every one of them asserts a red and then asks which SENTENCE prints beside it.
#
# THE MECHANISM IS REPRODUCED, NOT DESCRIBED. Each shape below forks a real repo, folds a real
# release on one side, files a real entry on the other and lets GIT do the merge; the assertions
# then run `_missing_remedy` through `_pr_merge_refs`, i.e. the two calls the live leg makes.
# A hand-placed bullet under a released heading would satisfy the label leg while proving nothing
# about whether the merge puts one there.
#
# FOUR REPO SHAPES, and three of them are NEGATIVE — the label alone is true in all four and the
# fold sentence is true in exactly one. Without the three, "name the released heading" would pass
# every assertion here while telling a stale-fix author to lift a shipped line out of a release.
# ---------------------------------------------------------------------------

# _pf_newrepo <dir> — a repo on `dev` whose `[Unreleased]` has a BODY. The body is the point: the
# fold inserts its new heading at the TOP of that body and a branch files at the FOOT of it, so
# the two insertions are far enough apart for git to apply both. Filed at the very top instead
# they collide and the merge CONFLICTS — a different failure, and a loud one, because a human
# then resolves it. Measured both ways when this fixture was written.
_pf_newrepo() {
    mkdir -p "$1"
    g init -q "$1"
    cat > "$1/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#8901** — an entry that was already standing when this branch forked.
- **card#8902** — a second standing entry.
- **card#8903** — a third standing entry.

## [0.23.1] - 2026-07-27

### Added
- **card#8000** — an entry that shipped in 0.23.1.
EOF
    g -C "$1" add -A && g -C "$1" commit -qm 'docs(changelog): the file as it stands (#300)'
}
# _pf_fold <dir> <version> — step 4 of VERSIONING.md, textually: retitle the accumulated
# `## [Unreleased]` as `## [<version>]` and open a fresh empty one above it. As a DIFF that is a
# pure insertion of two lines below the `## [Unreleased]` header, which is why it merges.
_pf_fold() {
    awk -v v="## [$2] - 2026-08-01" '/^## \[Unreleased\]$/ { print; print ""; print v; next } 1' \
        "$1/CHANGELOG.md" > "$1/CHANGELOG.md.t"
    mv "$1/CHANGELOG.md.t" "$1/CHANGELOG.md"
}
# _pf_file_entry <dir> <bullet> — file a bullet at the FOOT of the `[Unreleased]` body.
_pf_file_entry() {
    awk -v b="$2" '/^- \*\*card#8903\*\*/ { print; print b; next } 1' \
        "$1/CHANGELOG.md" > "$1/CHANGELOG.md.t"
    mv "$1/CHANGELOG.md.t" "$1/CHANGELOG.md"
}
# _pf_prmerge <dir> <branch> — build what `actions/checkout` gives this gate on a pull_request:
# a MERGE COMMIT whose FIRST parent is the base tip and whose SECOND is the branch. Echoes git's
# own rc, so a fixture that silently stopped conflicting reds instead of passing on a stale tree.
_pf_prmerge() {
    local rc=0
    g -C "$1" checkout -q -b "pr-$2" dev
    g -C "$1" merge -q --no-ff --no-edit "$2" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}
# _pf_remedy <dir> <missing-cards> <stop-version> — the LIVE run's two calls, verbatim: derive
# the refs off the merge commit, then ask for the remedy. `GITHUB_BASE_REF` is what a pull_request
# run sets and what `_pr_merge_refs` requires; setting it here is the fixture standing in for that
# event. <stop-version> is a LITERAL, because the `_pf_*` fixtures mint no tag (`_pf_newrepo`
# commits, never tags): it models the tag on the fixture's release commit — `0.24.0` where the
# fold is committed as a release, `0.23.1` where the branch cuts `[0.24.0]` itself.
_pf_remedy() {
    local refs
    refs="$(GITHUB_BASE_REF=dev _pr_merge_refs "$1")"
    _missing_remedy "$1" CHANGELOG.md "${refs%% *}" "${refs##* }" "$1/CHANGELOG.md" "$2" "$3"
}
# _pf_heading <dir> <card> — the same derivation, stopping at the label the three legs establish.
_pf_heading() {
    local refs
    refs="$(GITHUB_BASE_REF=dev _pr_merge_refs "$1")"
    _prefold_heading "$1" CHANGELOG.md "${refs%% *}" "${refs##* }" "$1/CHANGELOG.md" "$2" || true
}
# _pf_label <dir> — `_added_section_label` alone, off the same merge commit. Every negative
# fixture asserts on this too: without it, "the generic text printed" is equally satisfied by a
# locator that found nothing, and the legs would be proving nothing.
_pf_label() {
    local d="$TMP/pf-label" base head
    rm -rf "$d"; mkdir -p "$d"
    base="$(g -C "$1" rev-parse HEAD^1)"
    head="$(g -C "$1" rev-parse HEAD^2)"
    _branch_added_lines "$1" CHANGELOG.md "$base" "$head" > "$d/added"
    g -C "$1" show "$base:CHANGELOG.md" > "$d/baseline"
    _added_section_label "$1/CHANGELOG.md" "$d/added" "$d/baseline"
    rm -rf "$d"
}

# Spelled out per card rather than built by a helper: an expectation formatted by the same rule the
# implementation uses would agree with it whatever that rule became.
PF_FOLD_9100='card#9100 — your entry landed under `[0.24.0]` after the fold; move it back to `[Unreleased]`.'
PF_GEN_9100='card#9100 — add a line-initial `- **card#9100**` bullet under `## [Unreleased]` in CHANGELOG.md.'
PF_GEN_9200='card#9200 — add a line-initial `- **card#9200**` bullet under `## [Unreleased]` in CHANGELOG.md.'
PF_CAR_8902='card#8902 — a bullet for it already stands under `## [0.24.0]`, below the scanned region. If a merge carried this card'"'"'s entry there after the fold, move the WHOLE entry — the bullet and every indented line under it — back under `## [Unreleased]`; otherwise add a new bullet under `## [Unreleased]` for the work that landed after v0.24.0. The gate cannot tell which; where `[0.24.0]` holds more than one entry for the card, judge each.'
PF_CAR_9100='card#9100 — a bullet for it already stands under `## [0.24.0]`, below the scanned region. If a merge carried this card'"'"'s entry there after the fold, move the WHOLE entry — the bullet and every indented line under it — back under `## [Unreleased]`; otherwise add a new bullet under `## [Unreleased]` for the work that landed after v0.24.0. The gate cannot tell which; where `[0.24.0]` holds more than one entry for the card, judge each.'
printf 'fix(x): the branch entry (card#9100)\n' > "$TMP/prefold-subjects"

echo "== prove-it-can-fail: a PRE-FOLD branch's entry is folded under [0.24.0] and NAMED =="
PFF="$TMP/prefold-fold"
_pf_newrepo "$PFF"
g -C "$PFF" checkout -q -b feat
_pf_file_entry "$PFF" '- **card#9100** — the entry, filed while [Unreleased] was still open.'
g -C "$PFF" commit -qam 'fix(x): the branch entry (card#9100)'
g -C "$PFF" checkout -q dev
_pf_fold "$PFF" 0.24.0
g -C "$PFF" commit -qam 'chore(release): v0.24.0 (#301)'
eq "the merge is CLEAN — git moved the entry, no human resolved anything" "0" \
   "$(_pf_prmerge "$PFF" feat)"
# The mechanism, shown rather than asserted about: the entry is still IN the file and is no
# longer in the region, which together are the whole defect.
eq "the entry survives the merge (witness: this is a MOVE, not a loss)" "true" \
   "$(has_line '- **card#9100** — the entry, filed while [Unreleased] was still open.' \
       "$(cat "$PFF/CHANGELOG.md")")"
eq "… under the FOLDED heading, outside the region" "0.24.0" "$(_pf_label "$PFF")"
eq "THE VERDICT IS UNCHANGED: the card is still reported missing its entry" "card#9100" \
   "$(_missing "$TMP/prefold-subjects" "$PFF/CHANGELOG.md" "0.24.0")"
eq "the three legs establish the fold and name the heading" "0.24.0" "$(_pf_heading "$PFF" card#9100)"
# ONE call, three assertions off the captured text: the leading line, the absence of the generic
# arm, and the instruction the card exists to deliver. `${x%%$'\n'*}` rather than `| head -1` —
# nothing in this file reaches for a pipeline it does not need.
PF_OUT="$(_pf_remedy "$PFF" card#9100 0.24.0)"
eq "so the remedy names the MOVE, not a second entry" "$PF_FOLD_9100" "${PF_OUT%%$'\n'*}"
eq "and it says so out loud (witness: the generic arm is NOT what printed for it)" "false" \
   "$(has_line "$PF_GEN_9100" "$PF_OUT")"
# The instruction this whole card exists to deliver, asserted as a LINE rather than left to the
# first line's summary: the remedy an author acted on before this change was "your entry is
# missing", and the file that came back had two.
eq "the remedy tells the author NOT to file a second entry" "true" \
   "$(has_line 'for a card named above as FOLDED — move the one it already has. The other lines above are' \
       "$PF_OUT")"

echo "== CONTROL: a STALE-FIX branch editing a section that already stood at its fork is NOT =="
# The first false positive bridge #632 R1 measured. The fold happened BEFORE this branch existed,
# so nothing was cut while it was open — and the remedy would tell the author to lift a line that
# genuinely SHIPPED in 0.24.0 out of the release. LEG 3 is the only thing that separates it from
# the fixture above: the label is identical, and asserted to be.
PFS="$TMP/prefold-stale-fix"
_pf_newrepo "$PFS"
_pf_fold "$PFS" 0.24.0
g -C "$PFS" commit -qam 'chore(release): v0.24.0 (#301)'
g -C "$PFS" checkout -q -b feat
sed -i 's/^- \*\*card#8902\*\* — a second standing entry\.$/- **card#8902** — a second standing entry, wording corrected./' \
    "$PFS/CHANGELOG.md"
g -C "$PFS" commit -qam 'docs(changelog): correct a shipped entry (card#8902)'
eq "the merge is clean here too" "0" "$(_pf_prmerge "$PFS" feat)"
eq "the LABEL is the same one the fold fixture returns (witness: leg 3 is what differs)" "0.24.0" \
   "$(_pf_label "$PFS")"
eq "but 0.24.0 already stood at the merge-base, so no fold is established" "" \
   "$(_pf_heading "$PFS" card#8902)"
# PREDICATE 6 (d): the shipped line stands under `[0.24.0]`, at or below the stop, so the remedy
# says where — with both options, because it cannot tell a shipped line from a carried one —
# and STILL never the MOVE verdict leg 3 refuses.
PF_STALE="$(_pf_remedy "$PFS" card#8902 0.24.0)"
eq "the remedy names where the shipped bullet stands, with both options" "$PF_CAR_8902" "$PF_STALE"
eq "… and it is never the MOVE text" "false" "$(has 'after the fold; move it back' "$PF_STALE")"

echo "== CONTROL: a branch that CUTS the section itself is not told somebody else cut it =="
# The second shape, and the only fixture LEG 2 decides: the release PR adds `## [0.24.0]` and
# files under it, so the heading is on no base anywhere — telling its author that 0.24.0 "was cut
# while this branch was open" would name them as the victim of their own commit.
PFC="$TMP/prefold-cuts-it"
_pf_newrepo "$PFC"
g -C "$PFC" checkout -q -b feat
_pf_fold "$PFC" 0.24.0
# Filed AFTER the fold, so the bullet lands inside the section this same branch just cut —
# appending it to the end of the file would put it under [0.23.1] and leg 3 would be what
# rejected it, leaving leg 2 unexercised. (It was written that way first, and the label came
# back 0.23.1.)
_pf_file_entry "$PFC" '- **card#9100** — a note the release PR files under the version it is cutting.'
g -C "$PFC" commit -qam 'chore(release): v0.24.0 (card#9100)'
eq "the merge is clean here too" "0" "$(_pf_prmerge "$PFC" feat)"
eq "the LABEL is again 0.24.0 (witness: leg 2 is what differs)" "0.24.0" "$(_pf_label "$PFC")"
eq "… and that heading stands on NO base — the branch brought it (witness for leg 2)" "false" \
   "$(g -C "$PFC" show 'HEAD^1:CHANGELOG.md' > "$TMP/pf-cuts-base" &&
      _has_version_header "$TMP/pf-cuts-base" 0.24.0 && echo true || echo false)"
eq "so no fold is established" "" "$(_pf_heading "$PFC" card#9100)"
eq "and the remedy is the generic one" "$PF_GEN_9100" "$(_pf_remedy "$PFC" card#9100 0.23.1)"

echo "== THE DISCLOSED RESIDUAL: a pre-fold branch that already MERGED the fold gets the carried-entry sentence =="
# Same defect as the first fixture — the entry really is stranded under [0.24.0] and really was
# put there by the fold — but this branch has since merged the folded base, which makes that base
# its own merge-base, so leg 3 cannot see that the heading arrived late and the MOVE verdict is
# not established. Spelling leg 3 at the merge-base buys this residual. The author still reads
# where the entry went and both options (predicate 6), never a confident MOVE: pinned here so a
# future author meets the trade instead of rediscovering it as a bug.
PFR="$TMP/prefold-residual"
_pf_newrepo "$PFR"
g -C "$PFR" checkout -q -b feat
_pf_file_entry "$PFR" '- **card#9100** — the entry, filed while [Unreleased] was still open.'
g -C "$PFR" commit -qam 'fix(x): the branch entry (card#9100)'
g -C "$PFR" checkout -q dev
_pf_fold "$PFR" 0.24.0
g -C "$PFR" commit -qam 'chore(release): v0.24.0 (#301)'
g -C "$PFR" checkout -q feat
g -C "$PFR" merge -q --no-ff --no-edit dev >/dev/null 2>&1
eq "the branch's own merge already stranded the entry under [0.24.0]" "true" \
   "$(has_line '- **card#9100** — the entry, filed while [Unreleased] was still open.' \
       "$(_region "$PFR/CHANGELOG.md" 0.23.1)")"
eq "the PR merge is clean" "0" "$(_pf_prmerge "$PFR" feat)"
eq "the LABEL still finds it (witness: the residual is leg 3's, not the locator's)" "0.24.0" \
   "$(_pf_label "$PFR")"
eq "the merge-base IS the folded base, so leg 3 goes false" "true" \
   "$(g -C "$PFR" show \
        "$(g -C "$PFR" merge-base 'HEAD^1' 'HEAD^2'):CHANGELOG.md" > "$TMP/pf-res-mb" &&
      _has_version_header "$TMP/pf-res-mb" 0.24.0 && echo true || echo false)"
eq "so the MOVE is not established, and the carried-entry sentence prints" "$PF_CAR_9100" \
   "$(_pf_remedy "$PFR" card#9100 0.24.0)"

echo "== TWO missing cards, ONE folded: each gets the arm that is TRUE OF IT =="
# The shape a verdict-wide sentence gets WRONG, and the reason the needles are scoped per card
# (card#8442 R1). `_missing` routinely names several cards; a fold is a property of ONE card's
# bullet. Before the scoping, one folded card put every other missing card under "do NOT file a
# second entry" — the exact wrong instruction for a card that has no entry to move, and following
# it leaves that card undocumented, which is the failure this whole gate exists to prevent.
PFM="$TMP/prefold-multi"
_pf_newrepo "$PFM"
g -C "$PFM" checkout -q -b feat
_pf_file_entry "$PFM" '- **card#9100** — the entry, filed while [Unreleased] was still open.'
g -C "$PFM" commit -qam 'fix(x): the branch entry (card#9100)'
# The second card ships with NO entry at all — an ordinary omission, riding the same branch.
printf 'a second change, documented nowhere\n' > "$PFM/other.txt"
g -C "$PFM" add other.txt && g -C "$PFM" commit -qm 'feat(y): a change with no entry (card#9200)'
g -C "$PFM" checkout -q dev
_pf_fold "$PFM" 0.24.0
g -C "$PFM" commit -qam 'chore(release): v0.24.0 (#301)'
eq "the merge is clean here too" "0" "$(_pf_prmerge "$PFM" feat)"
printf 'fix(x): the branch entry (card#9100)\nfeat(y): a change with no entry (card#9200)\n' \
    > "$TMP/prefold-subjects-multi"
PF_MULTI_MISSING="$(_missing "$TMP/prefold-subjects-multi" "$PFM/CHANGELOG.md" 0.24.0)"
eq "BOTH cards are reported missing — the verdict is unchanged for either" "card#9100
card#9200" "$PF_MULTI_MISSING"
# Only card#9100's bullet was folded; card#9200 never had one. The two arms must not be swapped
# and must not be merged.
eq "card#9100's own bullet is located under the fold" "0.24.0" \
   "$(_pf_heading "$PFM" card#9100)"
eq "card#9200 has no bullet the branch added, so nothing is established for it" "" \
   "$(_pf_heading "$PFM" card#9200)"
PF_MULTI="$(_pf_remedy "$PFM" "$PF_MULTI_MISSING" 0.24.0)"
eq "the folded card is told to MOVE its entry" "true" "$(has_line "$PF_FOLD_9100" "$PF_MULTI")"
eq "and the undocumented card is told to ADD one — not to withhold it" "true" \
   "$(has_line "$PF_GEN_9200" "$PF_MULTI")"
# The two witnesses that make the pair about SCOPING rather than about ordering: neither card
# receives the other's arm.
eq "the undocumented card does NOT get the fold sentence" "false" \
   "$(has_line "card#9200 — your entry landed under \`[0.24.0]\` after the fold; move it back to \`[Unreleased]\`." \
       "$PF_MULTI")"
eq "the folded card does NOT get the generic add" "false" "$(has_line "$PF_GEN_9100" "$PF_MULTI")"
eq "and the shared paragraph scopes itself to the cards named as folded" "true" \
   "$(has_line 'ordinary missing entries and do need a new bullet.' "$PF_MULTI")"

echo "== a checkout that is NOT a pull_request merge ref establishes nothing, by design =="
# The other residual, and the reason it is safe: a local run has no merge commit to read parents
# off, so it takes the generic arm — the text this gate printed before this card. Both halves of
# `_pr_merge_refs` are exercised, because either alone would let the other's shape through.
#
# ⛔ EACH ARM IS DRIVEN AGAINST THE OPPOSITE AMBIENT, and that is a CI red rather than a flourish.
# The negative cell first asserted "with GITHUB_BASE_REF unset" by simply CALLING the function and
# relying on the variable being absent — which is a property of the SHELL, not of the code. A
# GitHub runner exports `GITHUB_BASE_REF` to EVERY step of a `pull_request` job, so on the runner
# the cell's stated condition never held: it passed four local runs and went red on the real event
# (PR #325, run 33593043265, `expected '' got 'fa2558f… 724801b…'`). The premise a fixture relies
# on has to be one the fixture ESTABLISHES.
#
# So each arm now carries its own per-call assignment AND an exported ambient set to the OTHER
# value, inside the command substitution's own subshell — nothing leaks to the live leg below,
# which reads the runner's real `GITHUB_BASE_REF` and must keep seeing it. What the pair
# discriminates is the assignment, on one commit, with the environment pushing the other way.
#
# THE ISOLATION IS COMPLETE BECAUSE THE INPUT SET IS SMALL AND ENUMERATED, not because the two
# values were chosen well: `_pr_merge_refs` reads exactly `$GITHUB_BASE_REF` and the repository
# named by `$1`. It opens no event payload and consults no `GITHUB_REF` / `GITHUB_HEAD_REF` /
# `GITHUB_SHA` / `GITHUB_EVENT_PATH`, and `git -C "$1"` answers about the FIXTURE repo, never the
# runner's checkout. Grep the function before adding an input to it; a third one makes this pair
# under-isolated again.
eq "on the pull_request shape the refs ARE derived — the per-call value decides, not the ambient" \
   "$(g -C "$PFF" rev-parse HEAD^1) $(g -C "$PFF" rev-parse HEAD^2)" \
   "$(export GITHUB_BASE_REF=''; GITHUB_BASE_REF=dev _pr_merge_refs "$PFF")"
eq "with GITHUB_BASE_REF EMPTY nothing is derived from that same merge commit, under an EXPORTED one" \
   "" "$(export GITHUB_BASE_REF=dev; GITHUB_BASE_REF='' _pr_merge_refs "$PFF")"
g -C "$PFF" checkout -q feat
eq "and on a non-merge checkout, nothing is derived even on a pull_request event" "" \
   "$(export GITHUB_BASE_REF=dev; GITHUB_BASE_REF=dev _pr_merge_refs "$PFF")"
eq "so the remedy falls back to the generic text" "$PF_GEN_9100" "$(_pf_remedy "$PFF" card#9100 0.24.0)"
g -C "$PFF" checkout -q pr-feat

echo "== the locator subtracts what the BASELINE already carries, and still finds what it does not =="
# `docs/CHANGELOG.md` carries 67 `### Added` / `### Fixed` / `### Docs` heads, one per released
# section, so a branch that opens one under `[Unreleased]` matches every released section at once.
# Without the subtraction the locator returns a label off that collision and the two history legs
# are then asked to defend a heading nothing was ever filed under.
PFU="$TMP/prefold-unit"
mkdir -p "$PFU"
cat > "$PFU/merged.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#9100** — a new entry, correctly filed.

## [0.24.0] - 2026-08-01

### Added
- **card#8901** — an entry that shipped in 0.24.0.
EOF
cat > "$PFU/baseline.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.24.0] - 2026-08-01

### Added
- **card#8901** — an entry that shipped in 0.24.0.
EOF
printf '### Added\n- **card#9100** — a new entry, correctly filed.\n' > "$PFU/added"
eq "a '### Added' the baseline already carries is no needle, and the [Unreleased] bullet is skipped" \
   "" "$(_added_section_label "$PFU/merged.md" "$PFU/added" "$PFU/baseline.md")"
# CONTROL, on the same three inputs: one line the baseline does NOT carry, standing in the
# released section. Without it the assertion above is satisfied by a locator that never answers.
printf -- '- **card#9100** — the same entry, this time inside the released section.\n' >> "$PFU/added"
awk '/^- \*\*card#8901\*\*/ { print; print "- **card#9100** — the same entry, this time inside the released section."; next } 1' \
    "$PFU/merged.md" > "$PFU/merged-in-release.md"
eq "… while a line it does NOT carry, standing in that section, IS located (control)" "0.24.0" \
   "$(_added_section_label "$PFU/merged-in-release.md" "$PFU/added" "$PFU/baseline.md")"
# And the heading itself, which leg 2's shape depends on not matching: a branch that ADDS
# `## [0.24.0]` has filed nothing under it, so the header line is a boundary and never a site.
cat > "$PFU/baseline-prefold.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#8901** — an entry not yet released.
EOF
printf '## [0.24.0] - 2026-08-01\n' > "$PFU/added-heading-only"
eq "the version heading a branch adds is a BOUNDARY, never a line filed under itself" "" \
   "$(_added_section_label "$PFU/merged.md" "$PFU/added-heading-only" "$PFU/baseline-prefold.md")"

# ---------------------------------------------------------------------------
# THE SQUASH DELTA (card#10338). `exempt_paths` judges a PR's own tokens on the diff its squash
# will LAND, so the delta must be admitted exactly where the merge will be a squash — and refused
# on the PR classes this repo merges with a merge commit, whose commits land individually. The
# fixtures below drive `_squash_ends` through each shape. The fixture carries a sibling entry on
# `dev`, which proves the second end is the MERGE COMMIT (the tree that lands) and not the
# branch tip.
# ---------------------------------------------------------------------------

# _sq_file <dir> <heading> <bullet> — file a bullet at the TOP of <heading>'s body. `_prepend` has
# one anchor and these fixtures need two headings, which is the whole point of them.
_sq_file() {
    awk -v h="$2" -v b="$3" 'index($0, h) == 1 && !done { print; print b; done = 1; next } 1' \
        "$1/CHANGELOG.md" > "$1/CHANGELOG.md.t"
    mv "$1/CHANGELOG.md.t" "$1/CHANGELOG.md"
}
# _sq_newrepo <dir> — a repo on `dev` whose `[Unreleased]` carries two real `###` headings, each
# with a standing entry. `_newrepo`'s file has no headings at all, which is the one thing a
# same-heading-vs-split fixture cannot do without.
_sq_newrepo() {
    mkdir -p "$1"
    g init -q "$1"
    cat > "$1/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- **card#9000** — an entry standing on dev when this branch forked.

### Fixed
- **card#9001** — a second standing entry.

## [0.23.1] - 2026-07-27
EOF
    : > "$1/.gitattributes"
    g -C "$1" add -A && g -C "$1" commit -qm 'docs(changelog): the file as it stands (#264)'
    # The base commit IS the last release, and `_squash_ends`' UNRELEASED leg needs that floor to
    # be a real revision rather than a name these fixtures agree to pretend about.
    g -C "$1" tag -a v0.23.1 -m 'v0.23.1' -q 2>/dev/null || g -C "$1" tag v0.23.1
}

echo "== the squash ENDS are the base tip and the merge commit, on a branch that reworded its entry =="
SQ="$TMP/squash-parity"
_sq_newrepo "$SQ"
SQ_DEV0="$(g -C "$SQ" rev-parse dev)"
g -C "$SQ" checkout -q -b feat
_sq_file "$SQ" '### Added' '- **card#4000** — FIRST WORDING.'
_sq_file "$SQ" '### Added' '- **card#4000** — a second claim of the SAME kind.'
g -C "$SQ" commit -qam 'feat(x): the change, documented twice (card#4000)'
# The reword — routine, and the whole mechanism: a remove plus an add that no squash will record.
sed -i 's/FIRST WORDING/CORRECTED WORDING/' "$SQ/CHANGELOG.md"
g -C "$SQ" commit -qam 'docs(changelog): reword the first bullet (card#4000)'
g -C "$SQ" checkout -q dev
_sq_file "$SQ" '### Fixed' '- **card#9002** — a sibling PR, filed on dev while this branch was open.'
g -C "$SQ" commit -qam 'fix(y): a sibling (card#9002) (#265)'
eq "the PR merge is clean — git combined the two, no human resolved anything" "0" \
   "$(_pf_prmerge "$SQ" feat)"
SQ_ENDS="$(GITHUB_BASE_REF=dev _squash_ends "$SQ" v0.23.1)"
eq "the ends are the BASE TIP and the MERGE COMMIT — not the branch tip" \
   "$(g -C "$SQ" rev-parse dev) $(g -C "$SQ" rev-parse HEAD)" "$SQ_ENDS"
eq "… and the branch tip is a THIRD revision (witness: the distinction is not vacuous)" "false" \
   "$(has "$(g -C "$SQ" rev-parse feat)" "$SQ_ENDS")"

echo "== the branch's CATCH-UP MERGE: the squash delta is still admitted =="
# The one shape of the three a branch can take (split, reword, catch-up) that carries a merge
# commit of its own. The delta must still be admitted: the siblings the catch-up brought in stand
# at the squash BASE, so they are on both sides of the diff and cannot enter the unit.
SQC="$TMP/squash-parity-catchup"
_sq_newrepo "$SQC"
SQC_DEV0="$(g -C "$SQC" rev-parse dev)"
g -C "$SQC" checkout -q -b feat
_sq_file "$SQC" '### Added' '- **card#4000** — FIRST WORDING.'
g -C "$SQC" commit -qam 'feat(x): the entry (card#4000)'
g -C "$SQC" checkout -q dev
_sq_file "$SQC" '### Fixed' '- **card#9002** — a sibling PR, filed on dev while this branch was open.'
g -C "$SQC" commit -qam 'fix(y): a sibling (card#9002) (#265)'
# The catch-up itself, and then the reword plus a second same-heading bullet ON TOP of it.
g -C "$SQC" checkout -q feat && g -C "$SQC" merge -q --no-edit dev >/dev/null 2>&1
sed -i 's/FIRST WORDING/CORRECTED WORDING/' "$SQC/CHANGELOG.md"
_sq_file "$SQC" '### Added' '- **card#4000** — a second claim of the SAME kind.'
g -C "$SQC" commit -qam 'docs(changelog): reword and add (card#4000)'
eq "the branch really carries a merge commit from dev (witness: this is the catch-up shape)" "1" \
   "$(g -C "$SQC" rev-list --count --merges "$SQC_DEV0..feat")"
eq "the PR merge is clean here too" "0" "$(_pf_prmerge "$SQC" feat)"
SQC_ENDS="$(GITHUB_BASE_REF=dev _squash_ends "$SQC" v0.23.1)"
eq "the ends are the BASE TIP and the MERGE COMMIT here too — the catch-up does not refuse the delta" \
   "$(g -C "$SQC" rev-parse dev) $(g -C "$SQC" rev-parse HEAD)" "$SQC_ENDS"

# ---------------------------------------------------------------------------
# ⛔ THE DELTA IS REFUSED ON THE PR CLASSES THIS REPO DOES NOT SQUASH (card#10338 R1).
# `_pr_merge_refs`' two conditions are base-agnostic by design, and VERSIONING.md § Anti-patterns
# merge-commits both the release PR and the back-merge sync PR, whose commits therefore land — and
# are judged — one by one. TWO FIXTURES BECAUSE THERE ARE TWO LEGS AND NEITHER CATCHES THE OTHER'S
# CLASS; each carries the CROSS-WITNESS that the other leg would have let it through.
# ---------------------------------------------------------------------------
echo "== a RELEASE PR is refused the delta: its covered commits are squashed PRs of their own =="
SQREL="$TMP/squash-parity-release"
_sq_newrepo "$SQREL"
g -C "$SQREL" branch main
# Two squashed `dev` PRs on one card, then a release branch merged to MAIN with a merge commit.
_sq_file "$SQREL" '### Added' '- **card#7038** — the first PR on this card.'
g -C "$SQREL" commit -qam 'fix(a): first (card#7038) (#265)'
sed -i 's/^- \*\*card#7038\*\* — the first PR on this card\.$/- **card#7038** — the first PR on this card, now cross-referenced./' \
    "$SQREL/CHANGELOG.md"
_sq_file "$SQREL" '### Added' '- **card#7038** — the second PR on the same card.'
g -C "$SQREL" commit -qam 'test(a): second (card#7038) (#266)'
# The release PR: a disposable `release/v<version>` head off `dev`, merged to MAIN with a merge
# commit — VERSIONING.md rule 7 and § Anti-patterns, not an invention of this fixture.
g -C "$SQREL" checkout -q -b release/v0.24.0 dev
_pf_fold "$SQREL" 0.24.0
g -C "$SQREL" commit -qam 'chore(release): v0.24.0'
g -C "$SQREL" checkout -q -b pr-release main
eq "the release PR's merge is clean" "0" \
   "$(rc=0; g -C "$SQREL" merge -q --no-ff --no-edit release/v0.24.0 >/dev/null 2>&1 || rc=$?; echo "$rc")"
# THE GUARD — and the cross-witness that it is the UNSQUASHED leg doing the work here.
eq "the shipped derivation REFUSES the delta on this shape" "" \
   "$(GITHUB_BASE_REF=main _squash_ends "$SQREL" v0.23.1)"
eq "… because covered commits carry a (#N) of their own (the UNSQUASHED leg)" "2" \
   "$(g -C "$SQREL" log --format='%s' 'HEAD^1..HEAD' | { grep -cE '\(#[0-9]+\)' || true; })"
eq "… and NOT because they are released — every one is unreleased (the other leg is silent)" \
   "$(g -C "$SQREL" rev-list --count 'HEAD^1..HEAD')" \
   "$(_unreleased "$SQREL" v0.23.1 'HEAD^1..HEAD' | grep -c . || true)"

echo "== prove-it-can-fail: a BACK-MERGE sync PR is based on dev and is not squashed either =="
# The class no base-name test could reject — its base IS `dev`. What disqualifies it is that the
# commits the delta would cover came from `main` and are ALREADY RELEASED.
SQBM="$TMP/squash-parity-backmerge"
_sq_newrepo "$SQBM"
g -C "$SQBM" branch main
g -C "$SQBM" checkout -q -b release/v0.24.0 dev
_pf_fold "$SQBM" 0.24.0
g -C "$SQBM" commit -qam 'chore(release): v0.24.0'
g -C "$SQBM" checkout -q main
g -C "$SQBM" merge -q --no-ff --no-edit release/v0.24.0 >/dev/null 2>&1
g -C "$SQBM" tag -a v0.24.0 -m 'v0.24.0'
g -C "$SQBM" checkout -q -b sync/main-to-dev-post-v0.24.0 main
g -C "$SQBM" checkout -q -b pr-sync dev
eq "the back-merge PR's merge is clean" "0" \
   "$(rc=0; g -C "$SQBM" merge -q --no-ff --no-edit sync/main-to-dev-post-v0.24.0 >/dev/null 2>&1 || rc=$?; echo "$rc")"
eq "its base really is dev — a base-name test would admit it (witness for the OTHER leg)" "true" \
   "$(has_line "$(g -C "$SQBM" rev-parse dev)" "$(g -C "$SQBM" rev-parse 'HEAD^1')")"
# ⛔ THE FLOOR IS PINNED, NOT `describe`d, AND THE REASON IS A CI-ONLY RED THIS FIXTURE ALREADY
# TOOK. The live leg passes `LAST_TAG`, which on a real back-merge is the tag the merge brings back
# — the release is tagged before this PR is opened (VERSIONING.md steps 9–10) and every older tag is
# a whole release away. This fixture is four commits wide, so BOTH its tags are near HEAD and
# `git describe --abbrev=0` is choosing between them on commit ORDER: it answered `v0.24.0` on a
# laptop and `v0.23.1` on a runner, where the commits share a timestamp. That is a property of the
# fixture's size, not of the rule under test, so the rule is handed the floor it is about and the
# tag's position is asserted TOPOLOGICALLY, which no tie-break can move.
SQBM_TAG=v0.24.0
eq "the tag is reachable from the merge and NOT from dev — it is what this PR brings back" \
   "true false" \
   "$(g -C "$SQBM" merge-base --is-ancestor "$SQBM_TAG" HEAD && echo true || echo false) $(g -C "$SQBM" merge-base --is-ancestor "$SQBM_TAG" dev && echo true || echo false)"
eq "the shipped derivation REFUSES the delta here too" "" \
   "$(GITHUB_BASE_REF=dev _squash_ends "$SQBM" "$SQBM_TAG")"
eq "… because a covered commit is ALREADY RELEASED (the UNRELEASED leg: covered > unreleased)" \
   "true" \
   "$([[ "$(g -C "$SQBM" rev-list --count 'HEAD^1..HEAD')" -gt \
         "$(_unreleased "$SQBM" "$SQBM_TAG" 'HEAD^1..HEAD' | grep -c . || true)" ]] && echo true || echo false)"
eq "… and NOT because they carry a (#N) — none does (the other leg is silent)" "0" \
   "$(g -C "$SQBM" log --format='%s' 'HEAD^1..HEAD' | { grep -cE '\(#[0-9]+\)' || true; })"

# ---------------------------------------------------------------------------
# A RELEASE CUT BY CHERRY-PICK (card#11034). v0.41.0 was cut from v0.40.0 with four `dev` PRs
# picked onto it, so the tag reaches the COPIES and not dev's originals; once `dev` merged the tag
# the originals obliged bullets for cards that had already shipped. `_unreleased` owns the rule.
#
# One history carries every leg, so each is judged beside the others rather than alone:
#   dev:  A (#601, card#7001) · S (#602, card#7003) · B (#603, card#7002) ·
#         D1 = B's subject minus `(#603)`, no PR · D2 = M's subject exactly, no PR ·
#         F0 (#606, a follow-up on card#7001 merged BEFORE the sync)
#   main: A' (A's patch, REWORDED subject) · B' (B's subject, DRIFTED patch — S is not under it) ·
#         M (a direct push, no `(#N)`) · the fold, filing 7001/7002 under `## [0.24.0]` · tag v0.24.0
#   then dev merges v0.24.0, and adds F (#604, follow-up on card#7001) and N (#605, card#7009).
# A' is matched by PATCH alone and B' by SUBJECT alone, so each condition is witnessed without the
# other's help. The tag is passed, never `describe`d, for the SQBM fixture's tie-break reason.
# ---------------------------------------------------------------------------
CP="$TMP/cherry-pick-release"
_newrepo "$CP"
g -C "$CP" tag v0.23.1
g -C "$CP" branch main
printf 'one\ntwo\nthree\nfour\nfive\n' > "$CP/shared.txt"
g -C "$CP" add shared.txt && g -C "$CP" commit -qm 'chore: shared file'
g -C "$CP" checkout -q main && g -C "$CP" merge -q --ff-only dev && g -C "$CP" checkout -q dev
echo a > "$CP/a.txt"; g -C "$CP" add a.txt
g -C "$CP" commit -qm 'feat(a): one (closes card#7001) (#601)'
CP_A="$(g -C "$CP" rev-parse HEAD)"
sed -i 's/^two$/TWO/' "$CP/shared.txt"
g -C "$CP" commit -qam 'fix(s): left out of the release (card#7003) (#602)'
sed -i 's/^four$/FOUR/' "$CP/shared.txt"
g -C "$CP" commit -qam 'feat(b): drift (card#7002) (#603)'
CP_B="$(g -C "$CP" rev-parse HEAD)"
echo d1 > "$CP/d1.txt"; g -C "$CP" add d1.txt
g -C "$CP" commit -qm 'feat(b): drift (card#7002)'
echo d2 > "$CP/d2.txt"; g -C "$CP" add d2.txt
g -C "$CP" commit -qm 'chore(m): direct (card#7005)'
echo f0 > "$CP/f0.txt"; g -C "$CP" add f0.txt
g -C "$CP" commit -qm 'fix(a): follow-up before the sync (card#7001) (#606)'
g -C "$CP" checkout -q main
g -C "$CP" cherry-pick "$CP_A" >/dev/null
g -C "$CP" commit -q --amend -m 'feat(a): one, as released (card#7001)'
g -C "$CP" cherry-pick "$CP_B" >/dev/null
echo m > "$CP/m.txt"; g -C "$CP" add m.txt
g -C "$CP" commit -qm 'chore(m): direct (card#7005)'
_pf_fold "$CP" 0.24.0
_sq_file "$CP" '## [0.24.0]' '- **card#7002** — shipped by cherry-pick.'
_sq_file "$CP" '## [0.24.0]' '- **card#7001** — shipped by cherry-pick.'
g -C "$CP" commit -qam 'chore(release): v0.24.0'
g -C "$CP" tag v0.24.0
g -C "$CP" checkout -q dev
CP_PRESYNC="$(g -C "$CP" rev-parse HEAD)"

echo "== cherry-pick release: the two copies are what this fixture claims they are =="
_cp_pid() { g -C "$CP" show "$1" | g -C "$CP" patch-id --stable | cut -d' ' -f1; }
eq "(a) A' has A's PATCH and a different subject" "true false" \
   "$([[ "$(_cp_pid "$CP_A")" == "$(_cp_pid v0.24.0~3)" ]] && echo true || echo false) $([[ "$(g -C "$CP" log -1 --format=%s "$CP_A")" == "$(g -C "$CP" log -1 --format=%s v0.24.0~3)" ]] && echo true || echo false)"
eq "(b) B' has B's SUBJECT and a different patch — the context drifted, as on v0.41.0" "false true" \
   "$([[ "$(_cp_pid "$CP_B")" == "$(_cp_pid v0.24.0~2)" ]] && echo true || echo false) $([[ "$(g -C "$CP" log -1 --format=%s "$CP_B")" == "$(g -C "$CP" log -1 --format=%s v0.24.0~2)" ]] && echo true || echo false)"
eq "neither original is reachable from the tag — reachability calls both unreleased" "false false" \
   "$(g -C "$CP" merge-base --is-ancestor "$CP_A" v0.24.0 && echo true || echo false) $(g -C "$CP" merge-base --is-ancestor "$CP_B" v0.24.0 && echo true || echo false)"

echo "== (e) post-sync: dev has merged the cherry-picked tag, and new work lands on top =="
# An explicit message: git's default merge subject for a tag is version-dependent wording.
g -C "$CP" merge -q --no-ff -m 'Merge main into dev after v0.24.0 (back-merge sync)' v0.24.0 >/dev/null
echo f > "$CP/f.txt"; g -C "$CP" add f.txt
g -C "$CP" commit -qm 'fix(a): follow-up on a shipped card (card#7001) (#604)'
echo n > "$CP/n.txt"; g -C "$CP" add n.txt
g -C "$CP" commit -qm 'feat(n): new work (card#7009) (#605)'
eq "(e) the tag is an ancestor of HEAD — the shape a symmetric --cherry-pick range cannot see" "true" \
   "$(g -C "$CP" merge-base --is-ancestor v0.24.0 HEAD && echo true || echo false)"
CP_SUBJ="$TMP/cp-subjects"
_obligation_subjects "$CP" v0.24.0 > "$CP_SUBJ"
eq "(a)(b) exactly the commits with no copy in the tag are unreleased — A and B are not" \
   "Merge main into dev after v0.24.0 (back-merge sync)
chore(m): direct (card#7005)
feat(b): drift (card#7002)
feat(n): new work (card#7009) (#605)
fix(a): follow-up before the sync (card#7001) (#606)
fix(a): follow-up on a shipped card (card#7001) (#604)
fix(s): left out of the release (card#7003) (#602)" "$(LC_ALL=C sort "$CP_SUBJ")"
eq "(a) A, released by PATCH alone, obliges nothing" "false" \
   "$(has_line 'feat(a): one (closes card#7001) (#601)' "$(cat "$CP_SUBJ")")"
eq "(b) B, released by SUBJECT alone, obliges nothing" "false" \
   "$(has_line 'feat(b): drift (card#7002) (#603)' "$(cat "$CP_SUBJ")")"
eq "(d) an unsquashed commit equal to a released subject MINUS its (#N) stays obliged" "true" \
   "$(has_line 'feat(b): drift (card#7002)' "$(cat "$CP_SUBJ")")"
eq "(d) an unsquashed commit IDENTICAL to a released subject with no (#N) stays obliged" "true" \
   "$(has_line 'chore(m): direct (card#7005)' "$(cat "$CP_SUBJ")")"
eq "(c) a follow-up PR on a SHIPPED card, merged before the sync, stays obliged (new #N, new patch)" \
   "true" "$(has_line 'fix(a): follow-up before the sync (card#7001) (#606)' "$(cat "$CP_SUBJ")")"
eq "the commit S that the release left out stays obliged (the card#10868 shape)" "true" \
   "$(has_line 'fix(s): left out of the release (card#7003) (#602)' "$(cat "$CP_SUBJ")")"

echo "== (c)(e) the gate end to end: the follow-up and the new card RED without their bullets =="
# The fold filed 7001/7002 under `## [0.24.0]`, the stop header, so those bullets discharge nothing:
# a card that shipped and then took a follow-up owes a NEW `[Unreleased]` bullet for it.
# 7003, 7002 (via D1) and 7005 (via D2) get their bullets; 7001 (F) and 7009 (N) do not.
cp "$CP/CHANGELOG.md" "$TMP/cp-changelog.md"
_prepend "$TMP/cp-changelog.md" '- **card#7003** — left out of the release.'
_prepend "$TMP/cp-changelog.md" '- **card#7002** — the unsquashed follow-up.'
_prepend "$TMP/cp-changelog.md" '- **card#7005** — the dev-side direct commit.'
eq "(c)(e) the follow-up on a shipped card and the new card are the ones missing" \
   "card#7001
card#7009" "$(_missing "$CP_SUBJ" "$TMP/cp-changelog.md" 0.24.0)"
_prepend "$TMP/cp-changelog.md" '- **card#7001** — the follow-up.'
_prepend "$TMP/cp-changelog.md" '- **card#7009** — the new work.'
eq "CONTROL: with their bullets filed the same history is GREEN — the leg is not always-red" "" \
   "$(_missing "$CP_SUBJ" "$TMP/cp-changelog.md" 0.24.0)"

echo "== the same rule over a range, as _squash_ends reads it =="
eq "a back-merge range is still refused: its covered commits are reachable from the tag" "true" \
   "$([[ "$(g -C "$CP" rev-list --count "$CP_PRESYNC..HEAD")" -gt \
         "$(_unreleased "$CP" v0.24.0 "$CP_PRESYNC..HEAD" | grep -c . || true)" ]] && echo true || echo false)"
eq "and the pre-sync originals A and B count as released over an explicit range too (S, D1, D2, F0 left)" "4" \
   "$(_unreleased "$CP" v0.24.0 "v0.23.1..$CP_PRESYNC" | grep -c . || true)"

# ---------------------------------------------------------------------------
# THE BULLET GRAMMAR (card#11684 R2). One grammar, cut in one place (`_bullet_id`): a bullet is
# `- **` or `- ⚠ **` at column 1, its LEAD runs to the first `**`, and every `card#N` in the lead
# discharges. Each consumer of the lead gets its own loose-bullet fixture below — discharge, the
# fold diagnosis, the carried-entry arm — because a consumer that kept its own spelling of the old
# `- **card#N**` prefix would pass every other fixture and miss exactly this shape.
# ---------------------------------------------------------------------------
echo "== the lead: a ⚠ bullet, a multi-card lead, and prose that names a card discharge as ruled =="
cat > "$FIX/changelog-grammar.md" <<'EOF'
# Changelog

## [Unreleased]

### Changed
- ⚠ **BREAKING — a refusal that used to pass (card#9600)** — the warning-prefixed shape.
- **card#9700 / card#9701** (#880) — one lead naming two cards.
- **card#9702** — its prose mentions card#9703 and must not discharge it.
- **an unclosed lead naming card#9704
- not a bullet: **card#9705** sits behind a prefix the grammar does not take.

## [0.23.1] - 2026-07-27
EOF
eq "_bullet_id cuts each bullet's lead and lists its tokens" \
   "card#9600	- ⚠ **BREAKING — a refusal that used to pass (card#9600)** — the warning-prefixed shape.
card#9700 card#9701	- **card#9700 / card#9701** (#880) — one lead naming two cards.
card#9702	- **card#9702** — its prose mentions card#9703 and must not discharge it.
card#9704	- **an unclosed lead naming card#9704" \
   "$(_bullet_id < "$FIX/changelog-grammar.md")"
eq "every card a lead names is discharged — and only those" \
   "card#9600
card#9700
card#9701
card#9702
card#9704" "$(_discharged "$FIX/changelog-grammar.md" "0.23.1")"
printf '%s\n' 'fix(a): the ⚠ one (card#9600) (#881)' 'fix(b): a mention (card#9703) (#882)' \
    > "$FIX/subjects-grammar"
eq "so the ⚠ bullet discharges, and a card named only in prose stays missing" "card#9703" \
   "$(_missing "$FIX/subjects-grammar" "$FIX/changelog-grammar.md" "0.23.1")"

echo "== the obligation is the LEFTMOST token of a subject (card#11684 Q2) =="
printf '%s\n' 'fix(x): the change (card#9800) — supersedes card#9801 (#883)' \
    'docs(y): one token only (card#9802) (#884)' > "$FIX/subjects-leftmost"
eq "a two-token subject obliges its leftmost card only" "card#9800
card#9802" "$(_obliged "$FIX/subjects-leftmost")"

# ---------------------------------------------------------------------------
# THE MERGED-FILE REMEDY ARMS, OVER THE NEW GRAMMAR. Each reuses the `_pf_*` mechanism above — a
# real fold, a real merge — with a ⚠ bullet where the fixtures above file a plain one.
# ---------------------------------------------------------------------------
echo "== the FOLD arm finds a ⚠ bullet the branch filed before the fold =="
PFW="$TMP/prefold-warning-bullet"
_pf_newrepo "$PFW"
g -C "$PFW" checkout -q -b feat
_pf_file_entry "$PFW" '- ⚠ **BREAKING — filed while [Unreleased] was still open (card#9101)** — the entry.'
g -C "$PFW" commit -qam 'fix(x): a breaking change (card#9101)'
g -C "$PFW" checkout -q dev
_pf_fold "$PFW" 0.24.0
g -C "$PFW" commit -qam 'chore(release): v0.24.0 (#301)'
eq "the merge is clean" "0" "$(_pf_prmerge "$PFW" feat)"
eq "the three legs establish the fold for the ⚠ bullet" "0.24.0" "$(_pf_heading "$PFW" card#9101)"
PFW_OUT="$(_pf_remedy "$PFW" card#9101 0.24.0)"
eq "and the remedy names the MOVE" \
   'card#9101 — your entry landed under `[0.24.0]` after the fold; move it back to `[Unreleased]`.' \
   "${PFW_OUT%%$'\n'*}"

# _p6_file_entry <dir> <lines-file> — file a multi-line ENTRY (a bullet and its indented lines)
# at the foot of the `[Unreleased]` body, where `_pf_file_entry` files one line.
_p6_file_entry() {
    awk -v f="$2" '{ print } /^- \*\*card#8903\*\*/ { while ((getline l < f) > 0) print l }' \
        "$1/CHANGELOG.md" > "$1/CHANGELOG.md.t"
    mv "$1/CHANGELOG.md.t" "$1/CHANGELOG.md"
}
# _p6_sync <dir> <release-branch> — a back-merge sync PR's merge ref: `pr-sync` off `dev`, merging
# the release branch, which stands in for `main` after the release merged.
_p6_sync() {
    local rc=0
    g -C "$1" checkout -q -b pr-sync dev
    g -C "$1" merge -q --no-ff --no-edit "$2" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

echo "== predicate 6 (a): a sync merge CARRIES a multi-line entry under [0.24.0] — the #782 shape =="
P6A="$TMP/p6-carried-entry"
_pf_newrepo "$P6A"
g -C "$P6A" checkout -q -b release/v0.24.0
_pf_fold "$P6A" 0.24.0
g -C "$P6A" commit -qam 'chore(release): v0.24.0'
g -C "$P6A" checkout -q dev
printf '%s\n' '- **card#9300** — filed on dev after the release was cut.' \
    '  - the first indented line of the entry' '  - the second indented line of the entry' \
    > "$TMP/p6-entry"
_p6_file_entry "$P6A" "$TMP/p6-entry"
g -C "$P6A" commit -qam 'fix(x): the entry (card#9300) (#305)'
eq "the sync merge is clean" "0" "$(_p6_sync "$P6A" release/v0.24.0)"
eq "the merge carried the WHOLE entry under the release heading (witness)" "0.24.0" \
   "$(_added_section_label "$P6A/CHANGELOG.md" "$TMP/p6-entry" /dev/null)"
printf 'fix(x): the entry (card#9300) (#305)\nfix(z): never documented (card#9500) (#307)\n' \
    > "$TMP/p6-subjects"
P6A_MISSING="$(_missing "$TMP/p6-subjects" "$P6A/CHANGELOG.md" 0.24.0)"
eq "THE VERDICT IS RED: the carried entry is outside the region" "card#9300
card#9500" "$P6A_MISSING"
eq "the fold arm is NOT established — the sync branch did not ADD that bullet" "" \
   "$(_pf_heading "$P6A" card#9300)"
P6A_OUT="$(_pf_remedy "$P6A" "$P6A_MISSING" 0.24.0)"
P6A_9300="$(printf '%s\n' "$P6A_OUT" | { grep '^card#9300 ' || true; })"
eq "the sentence names [0.24.0]" "true" "$(has 'stands under `## [0.24.0]`, below the scanned region' "$P6A_9300")"
eq "… says WHOLE entry and every indented line" "true" \
   "$(has 'move the WHOLE entry — the bullet and every indented line under it — back under `## [Unreleased]`' "$P6A_9300")"
eq "… prints the other option too" "true" \
   "$(has 'otherwise add a new bullet under `## [Unreleased]` for the work that landed after v0.24.0' "$P6A_9300")"
eq "… and decides neither" "true" "$(has 'The gate cannot tell which' "$P6A_9300")"
echo "== predicate 6 (c) CONTROL: a card with no bullet anywhere gets the GENERIC sentence =="
eq "card#9500 gets the generic arm (the carried arm is keyed on a found bullet)" \
   'card#9500 — add a line-initial `- **card#9500**` bullet under `## [Unreleased]` in CHANGELOG.md.' \
   "$(printf '%s\n' "$P6A_OUT" | { grep '^card#9500 ' || true; })"

echo "== predicate 6 (b): [0.24.0] holds a SHIPPED bullet and a CARRIED entry for one card — the #808 shape =="
P6B="$TMP/p6-shipped-and-carried"
_pf_newrepo "$P6B"
_pf_file_entry "$P6B" '- **card#9400** — the DL-428 half, standing when the release is cut.'
g -C "$P6B" commit -qam 'fix(a): the first half (card#9400) (#304)'
g -C "$P6B" checkout -q -b release/v0.24.0
_pf_fold "$P6B" 0.24.0
g -C "$P6B" commit -qam 'chore(release): v0.24.0'
g -C "$P6B" tag v0.24.0
g -C "$P6B" checkout -q dev
printf '%s\n' '- **card#9400** — the DL-430 half, filed after the cut.' '  - its indented line' \
    > "$TMP/p6b-entry"
_p6_file_entry "$P6B" "$TMP/p6b-entry"
g -C "$P6B" commit -qam 'fix(a): the second half (card#9400) (#305)'
eq "the sync merge is clean" "0" "$(_p6_sync "$P6B" release/v0.24.0)"
eq "the first bullet stands at the v0.24.0 tag — it genuinely SHIPPED (witness)" "true" \
   "$(has_line '- **card#9400** — the DL-428 half, standing when the release is cut.' \
       "$(g -C "$P6B" show v0.24.0:CHANGELOG.md)")"
eq "and the carried one does not (witness: it was never released)" "false" \
   "$(has_line '- **card#9400** — the DL-430 half, filed after the cut.' \
       "$(g -C "$P6B" show v0.24.0:CHANGELOG.md)")"
eq "both stand under [0.24.0] in the merged file" "2" \
   "$(_region "$P6B/CHANGELOG.md" 0.23.1 | _lines_naming card#9400 | grep -c .)"
eq "THE VERDICT IS RED for the post-cut work" "card#9400" \
   "$(_missing <(printf 'fix(a): the second half (card#9400) (#305)\n') "$P6B/CHANGELOG.md" 0.24.0)"
P6B_OUT="$(_pf_remedy "$P6B" card#9400 0.24.0)"
eq "ONE sentence for the card — not one per bullet" "1" "$(printf '%s\n' "$P6B_OUT" | grep -c '^card#9400 ')"
eq "it names [0.24.0] and offers both options" "true true" \
   "$(has 'stands under `## [0.24.0]`' "$P6B_OUT") $(has 'otherwise add a new bullet' "$P6B_OUT")"
eq "and tells the author to judge each entry, since [0.24.0] holds more than one" "true" \
   "$(has 'where `[0.24.0]` holds more than one entry for the card, judge each' "$P6B_OUT")"

echo "== predicate 6 over the new grammar: a CARRIED ⚠ bullet is found too =="
P6W="$TMP/p6-carried-warning"
_pf_newrepo "$P6W"
g -C "$P6W" checkout -q -b release/v0.24.0
_pf_fold "$P6W" 0.24.0
g -C "$P6W" commit -qam 'chore(release): v0.24.0'
g -C "$P6W" checkout -q dev
_pf_file_entry "$P6W" '- ⚠ **BREAKING — filed on dev after the cut (card#9302)** — the entry.'
g -C "$P6W" commit -qam 'fix(x): breaking (card#9302) (#306)'
eq "the sync merge is clean" "0" "$(_p6_sync "$P6W" release/v0.24.0)"
eq "the carried ⚠ bullet's section is named" "0.24.0" \
   "$(_carried_heading "$P6W/CHANGELOG.md" 0.24.0 card#9302)"

# ---------------------------------------------------------------------------
# `changelog.exempt_paths`, JUDGED PER LANDED UNIT (card#11684 predicate 3). Obligations are
# re-derived from every unreleased subject on every run, so an exemption has to be a property of
# the UNIT that landed — the squash delta a PR run admits, or a commit's own first-parent diff —
# or the next run would forget it.
# ---------------------------------------------------------------------------

# _cg_repo <dir> [<changelog-object-json>] — a repository carrying what the BIN reads: `VERSION`,
# a `.release-pr.json` (with that `changelog` object, or none), `docs/CHANGELOG.md` with an empty
# `[Unreleased]` above `[0.23.1]`, tagged `v0.23.1`, on `dev` with `main` at the same commit.
_cg_repo() {
    local d="$1" cl="${2:-null}"
    mkdir -p "$d/docs"
    g init -q "$d"
    printf '0.23.1\n' > "$d/VERSION"
    jq -n --argjson cl "$cl" '{main_branch: "main", dev_branch: "dev", version_file: "VERSION",
        version_regex: "[0-9]+\\.[0-9]+\\.[0-9]+"} + (if $cl == null then {} else {changelog: $cl} end)' \
        > "$d/.release-pr.json"
    printf '# Changelog\n\n## [Unreleased]\n\n## [0.23.1] - 2026-07-27\n\n- **card#8000** — shipped in 0.23.1.\n' \
        > "$d/docs/CHANGELOG.md"
    g -C "$d" add -A && g -C "$d" commit -qm 'chore: the repository as released (#100)'
    g -C "$d" tag v0.23.1
    g -C "$d" branch main
}
# _cg_commit <dir> <path> <subject> — write a line into <path> (created if absent) and commit it.
_cg_commit() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" >> "$1/$2"
    g -C "$1" add -A && g -C "$1" commit -qm "$3"
}
# _cg_entry <dir> <bullet> <subject> — file a bullet under `[Unreleased]` and commit it.
_cg_entry() {
    _prepend "$1/docs/CHANGELOG.md" "$2"
    g -C "$1" commit -qam "$3"
}
# _cg_prmerge <dir> <base> <branch> — the merge ref `actions/checkout` leaves on a pull_request:
# FIRST parent the base tip, SECOND the branch. Echoes git's rc.
_cg_prmerge() {
    local rc=0
    g -C "$1" checkout -q -b "pr-${3//\//-}" "$2"
    g -C "$1" merge -q --no-ff --no-edit "$3" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}
# _cg_run <dir> <GITHUB_BASE_REF> [args…] — the bin itself, from <dir>, with the runner variable
# set to exactly what is passed ('' on a push run) — never inherited from this shell. Sets CG_RC
# and CG_OUT (stdout and stderr together, as a CI log shows them).
_cg_run() {
    local d="$1" gbr="$2"; shift 2
    CG_RC=0
    CG_OUT="$(cd "$d" && GITHUB_BASE_REF="$gbr" "$GATE" "$@" 2>&1)" || CG_RC=$?
}
# _cg_members <list…> — a members file for `_obligation_units`.
_cg_members() { printf '%s\n' "$@" > "$TMP/members"; echo "$TMP/members"; }
: > "$TMP/no-members"

echo "== exempt_paths: a docs-only tokened commit already on dev owes nothing, on the PR run and after =="
P3="$TMP/p3-docs-only"
_cg_repo "$P3" '{"exempt_paths": ["docs/", "tests/"]}'
_cg_commit "$P3" docs/guide.md 'docs: a guide (card#7200) (#101)'
g -C "$P3" checkout -q -b feat
_cg_commit "$P3" app/x.txt 'feat(x): an unrelated change (card#7201)'
_cg_entry "$P3" '- **card#7201** — an unrelated change.' 'docs(changelog): its entry (card#7201)'
eq "the PR merge is clean" "0" "$(_cg_prmerge "$P3" dev feat)"
P3_HEAD="$(g -C "$P3" rev-parse feat)"
P3_ENDS="$(cd "$P3" && GITHUB_BASE_REF=dev _squash_ends "$P3" v0.23.1)"
eq "the docs-only commit on dev is judged on its own diff, and is exempt" "card#7200	1" \
   "$( (cd "$P3" && _obligation_units "$P3" v0.23.1 "$(_cg_members docs/ tests/)" \
        "${P3_ENDS%% *}" "${P3_ENDS##* }" 'feat(x): an unrelated change (card#7201)') |
       awk -F'\t' '$1 == "card#7200" { print $1 "\t" $2 }')"
eq "CONTROL: with no exempt_paths the same commit OBLIGES (the members are what exempt it)" "card#7200" \
   "$( (cd "$P3" && _obligation_units "$P3" v0.23.1 "$TMP/no-members" "${P3_ENDS%% *}" "${P3_ENDS##* }" '') \
       > "$TMP/p3-units"; _missing <(_obliged_cards "$TMP/p3-units") "$P3/docs/CHANGELOG.md" 0.23.1)"
_cg_run "$P3" dev --base dev --head "$P3_HEAD" --title 'feat(x): an unrelated change (card#7201)'
eq "END TO END: the PR run is GREEN" "0" "$CG_RC"
eq "… and says one card was exempt" "true" "$(has '1 card(s) exempt by changelog.exempt_paths' "$CG_OUT")"
g -C "$P3" checkout -q dev
g -C "$P3" merge -q --squash feat >/dev/null 2>&1
g -C "$P3" commit -qm 'feat(x): an unrelated change (card#7201) (#102)'
_cg_run "$P3" ''
eq "END TO END: the push run after the squash is GREEN too" "0" "$CG_RC"

echo "== exempt_paths: a touch-then-revert branch, docs-only NET, is green on its PR run =="
P3R="$TMP/p3-touch-revert"
_cg_repo "$P3R" '{"exempt_paths": ["docs/"]}'
g -C "$P3R" checkout -q -b feat
mkdir -p "$P3R/app" && printf 'x\n' > "$P3R/app/x.txt"
printf 'a guide\n' > "$P3R/docs/guide.md"
g -C "$P3R" add -A && g -C "$P3R" commit -qm 'feat(x): try the change (card#7300)'
g -C "$P3R" rm -q app/x.txt && g -C "$P3R" commit -qm 'revert the app half (card#7300)'
eq "the PR merge is clean" "0" "$(_cg_prmerge "$P3R" dev feat)"
P3R_ENDS="$(cd "$P3R" && GITHUB_BASE_REF=dev _squash_ends "$P3R" v0.23.1)"
eq "the delta is admitted (witness: the PR run judges the squash unit)" "$(g -C "$P3R" rev-parse dev) $(g -C "$P3R" rev-parse HEAD)" "$P3R_ENDS"
eq "on the delta the token is EXEMPT — the squash lands docs only" "" \
   "$( (cd "$P3R" && _obligation_units "$P3R" v0.23.1 "$(_cg_members docs/)" "${P3R_ENDS%% *}" \
        "${P3R_ENDS##* }" '') > "$TMP/p3r-units"; _obliged_cards "$TMP/p3r-units")"
eq "CONTROL: judged per branch COMMIT the same token is obliged (the first commit touched app/)" "card#7300" \
   "$( (cd "$P3R" && _obligation_units "$P3R" v0.23.1 "$(_cg_members docs/)" '' '' '') > "$TMP/p3r-units"
       _obliged_cards "$TMP/p3r-units")"
_cg_run "$P3R" dev --base dev --head "$(g -C "$P3R" rev-parse feat)" --title 'docs: a guide (card#7300)'
eq "END TO END: the PR run is GREEN" "0" "$CG_RC"

echo "== THE NAMED DIVERGENCE: the same branch landed as a MERGE COMMIT reds the push run =="
g -C "$P3R" checkout -q dev
g -C "$P3R" merge -q --no-ff --no-edit feat >/dev/null 2>&1
_cg_run "$P3R" ''
eq "END TO END: the push run on dev is RED — each commit landed, and is judged, on its own" "1" "$CG_RC"
eq "… naming the token the PR run had passed" "true" "$(has 'card#7300 — add a line-initial' "$CG_OUT")"

# ---------------------------------------------------------------------------
# THE BIN END TO END. Every fixture below runs `bin/changelog-gate` itself, from inside a fixture
# repository, with `GITHUB_BASE_REF` set per call exactly as a runner sets it — so the classifier
# call, the config read and the exit code are the shipped ones.
# ---------------------------------------------------------------------------
echo "== the PR TITLE obliges on a PR run, through the bin's own unit derivation =="
TT="$TMP/title-obligation"
_cg_repo "$TT"
g -C "$TT" checkout -q -b feat
_cg_commit "$TT" app/t.txt 'feat: a change whose own commits carry no token'
eq "the PR merge is clean" "0" "$(_cg_prmerge "$TT" dev feat)"
_cg_run "$TT" dev --base dev --head "$(g -C "$TT" rev-parse feat)"
eq "CONTROL: without the title, nothing in this PR obliges a bullet" "0" "$CG_RC"
_cg_run "$TT" dev --base dev --head "$(g -C "$TT" rev-parse feat)" --title 'feat: a change (card#7202)'
eq "with it, the card the title names is obliged — RED, naming it" "1 true" \
   "$CG_RC $(has 'card#7202 — add a line-initial' "$CG_OUT")"

echo "== announce_paths: a tokenless PR touching a member must change [Unreleased] =="
AN="$TMP/announce"
_cg_repo "$AN" '{"announce_paths": ["app/"], "announce_exempt_branches": ["dependabot/"]}'
g -C "$AN" checkout -q -b chore-x
_cg_commit "$AN" app/x.txt 'chore: an app change with no card'
eq "the PR merge is clean" "0" "$(_cg_prmerge "$AN" dev chore-x)"
_cg_run "$AN" dev --base dev --head "$(g -C "$AN" rev-parse chore-x)" --title 'chore: an app change with no card' --head-ref chore-x
eq "a tokenless PR touching app/ with [Unreleased] unchanged is RED" "1" "$CG_RC"
eq "… on the announce leg" "true" "$(has 'touches a changelog.announce_paths member and leaves the [Unreleased] section' "$CG_OUT")"
_cg_run "$AN" dev --base dev --head "$(g -C "$AN" rev-parse chore-x)" --title 'chore: an app change with no card' --head-ref dependabot/npm/x
eq "the same PR from a dependabot/ branch is skipped" "0 true" \
   "$CG_RC $(has "skipped: head branch 'dependabot/npm/x' is under changelog.announce_exempt_branches" "$CG_OUT")"
g -C "$AN" checkout -q chore-x
_cg_entry "$AN" '- an app change with no card.' 'docs(changelog): announce it'
g -C "$AN" checkout -q dev && g -C "$AN" branch -q -D pr-chore-x
eq "the PR merge is clean" "0" "$(_cg_prmerge "$AN" dev chore-x)"
_cg_run "$AN" dev --base dev --head "$(g -C "$AN" rev-parse chore-x)" --title 'chore: an app change with no card' --head-ref chore-x
eq "with an [Unreleased] change the same PR is GREEN" "0 true" \
   "$CG_RC $(has 'no card token, and this PR changes the [Unreleased] section' "$CG_OUT")"

echo "== announce_paths: a RELEASE PR and a SYNC PR are skipped by classification (F2) =="
g -C "$AN" checkout -q dev
g -C "$AN" merge -q --squash chore-x >/dev/null 2>&1
g -C "$AN" commit -qm 'chore: an app change with no card (#103)'
g -C "$AN" update-ref refs/remotes/origin/dev dev
g -C "$AN" checkout -q -b release/v0.24.0 dev
printf '0.24.0\n' > "$AN/VERSION"
_pf_fold "$AN/docs" 0.24.0
g -C "$AN" commit -qam 'release: v0.24.0'
eq "the release PR's [Unreleased] section is unchanged at both ends (witness)" "true" \
   "$([[ "$(g -C "$AN" show main:docs/CHANGELOG.md > "$TMP/an-a"; _unreleased_section "$TMP/an-a")" == \
         "$(_unreleased_section "$AN/docs/CHANGELOG.md")" ]] && echo true || echo false)"
eq "… and its delta touches app/ (witness)" "true" \
   "$(has_line 'app/x.txt' "$(g -C "$AN" diff --name-only main release/v0.24.0)")"
eq "the release PR merge is clean" "0" "$(_cg_prmerge "$AN" main release/v0.24.0)"
_cg_run "$AN" main --base main --head "$(g -C "$AN" rev-parse release/v0.24.0)" --title 'release: v0.24.0' --head-ref release/v0.24.0
eq "the tokenless release PR is GREEN, skipped on the announce leg by classification" "0 true" \
   "$CG_RC $(has 'skipped: classified release 0.24.0' "$CG_OUT")"
g -C "$AN" checkout -q main
g -C "$AN" merge -q --no-ff --no-edit release/v0.24.0 >/dev/null 2>&1
g -C "$AN" tag v0.24.0
g -C "$AN" checkout -q -b sync/main-to-dev-post-v0.24.0 main
eq "the sync PR merge is clean" "0" "$(_cg_prmerge "$AN" dev sync/main-to-dev-post-v0.24.0)"
_cg_run "$AN" dev --base dev --head "$(g -C "$AN" rev-parse sync/main-to-dev-post-v0.24.0)" --title 'Sync main to dev after v0.24.0' --head-ref sync/main-to-dev-post-v0.24.0
eq "the sync PR into dev classifies release and is skipped too" "0 true" \
   "$CG_RC $(has 'skipped: classified release 0.24.0' "$CG_OUT")"

echo "== the classifier: a refusal is a refusal, and a ::warning:: before its verdict is relayed =="
_cg_run "$AN" dev --base dev --head "$(g -C "$AN" rev-parse sync/main-to-dev-post-v0.24.0)" --config nowhere.json
eq "release-artifacts-check refusing (rc 2) is rc 2 here, never a pass" "2 true" \
   "$CG_RC $(has 'could not classify' "$CG_OUT")"
eq "… with the classifier's own words relayed" "true" "$(has 'no nowhere.json in this repo' "$CG_OUT")"
WRN="$TMP/classifier-warning"
_cg_repo "$WRN" '{"exempt_paths": ["tests/"]}'
_cg_commit "$WRN" tests/a.txt 'test(a): tests only (card#7500) (#104)'
g -C "$WRN" update-ref refs/remotes/origin/dev dev
g -C "$WRN" checkout -q -b release/v0.24.0 dev
printf '0.23.1\n0.24.0\n' > "$WRN/VERSION"
_pf_fold "$WRN/docs" 0.24.0
g -C "$WRN" commit -qam 'release: v0.24.0'
eq "the release PR merge is clean" "0" "$(_cg_prmerge "$WRN" main release/v0.24.0)"
_cg_run "$WRN" main --base main --head "$(g -C "$WRN" rev-parse release/v0.24.0)" --title 'release: v0.24.0'
eq "a classifier ::warning:: printed BEFORE its verdict leaves the verdict read" "0 true" \
   "$CG_RC $(has "changelog.* read at $(g -C "$WRN" rev-parse dev) (release 0.24.0:" "$CG_OUT")"
eq "… and the warning itself reaches the log" "true" \
   "$(has '::warning::release-artifacts-check:' "$CG_OUT")"

echo "== the release-body size arm: bytes, the boundary, and the carve's two terminations =="
# _cg_section <file> <bytes> — a `## [0.24.0]` section of EXACTLY <bytes> bytes, as the carve
# measures it: the header line and one filler line.
_cg_section() {
    local hdr='## [0.24.0] - 2026-08-01'
    printf '%s\n' "$hdr" > "$1"
    head -c "$(( $2 - ${#hdr} - 2 ))" /dev/zero | tr '\0' x >> "$1"
    printf '\n' >> "$1"
}
_cg_section "$TMP/sec-125000" 125000
eq "the fixture section is 125 000 bytes on disk (witness)" "125000" "$(wc -c < "$TMP/sec-125000" | tr -d ' ')"
{ cat "$TMP/sec-125000"; printf '## [0.23.1] - 2026-07-27\n\n- **card#8000** — shipped.\n'; } > "$TMP/sec-header-terminated"
eq "a section ended by the next ## [ header measures its own bytes only" "125000" \
   "$(_section_bytes "$TMP/sec-header-terminated" 0.24.0)"
eq "the same section ended by EOF measures the same" "125000" "$(_section_bytes "$TMP/sec-125000" 0.24.0)"
eq "an absent section measures 0 (the arm tells absence apart by _has_version_header)" "0" \
   "$(_section_bytes "$TMP/sec-125000" 9.9.9)"
# _cg_size_pr <dir> <bytes> — a release PR into main whose [0.24.0] section is <bytes> bytes.
_cg_size_pr() {
    _cg_repo "$1" '{"release_body_limit_bytes": 125000}'
    g -C "$1" update-ref refs/remotes/origin/dev dev
    g -C "$1" checkout -q -b release/v0.24.0 dev
    printf '0.24.0\n' > "$1/VERSION"
    _cg_section "$TMP/sec-$2" "$2"
    { printf '# Changelog\n\n## [Unreleased]\n\n'; cat "$TMP/sec-$2"
      printf '## [0.23.1] - 2026-07-27\n\n- **card#8000** — shipped in 0.23.1.\n'; } > "$1/docs/CHANGELOG.md"
    g -C "$1" commit -qam 'release: v0.24.0'
    _cg_prmerge "$1" main release/v0.24.0 >/dev/null
    _cg_run "$1" main --base main --head "$(g -C "$1" rev-parse release/v0.24.0)" --title 'release: v0.24.0'
}
_cg_size_pr "$TMP/size-at" 125000
eq "a 125 000-byte section passes a 125 000-byte limit" "0 true" \
   "$CG_RC $(has 'is 125000 bytes, within 125000' "$CG_OUT")"
_cg_size_pr "$TMP/size-over" 125001
eq "a 125 001-byte section is RED" "1 true" \
   "$CG_RC $(has 'is 125001 bytes, over changelog.release_body_limit_bytes (125000)' "$CG_OUT")"

echo "== where changelog.* is read (predicate 5): the FIRST RELEASE AFTER ADOPTION =="
# `main`'s config carries no `changelog` key — it cannot, before the release that brings one —
# while `dev` adopted the gate with `exempt_paths: ["tests/"]` and then landed a tests-only
# tokened commit with no bullet. The release PR's fork point is on `main`.
P5="$TMP/p5-first-release"
_cg_repo "$P5"
jq '. + {changelog: {exempt_paths: ["tests/"]}}' "$P5/.release-pr.json" > "$P5/cfg.t" && mv "$P5/cfg.t" "$P5/.release-pr.json"
g -C "$P5" commit -qam 'ci: adopt the changelog gate (#110)'
_cg_commit "$P5" tests/a.txt 'test(x): tests only (card#7400) (#111)'
P5_DEVCUT="$(g -C "$P5" rev-parse dev)"
g -C "$P5" update-ref refs/remotes/origin/dev dev
g -C "$P5" checkout -q -b release/v0.24.0 dev
printf '0.24.0\n' > "$P5/VERSION"
_pf_fold "$P5/docs" 0.24.0
g -C "$P5" commit -qam 'release: v0.24.0'
P5_REL="$(g -C "$P5" rev-parse release/v0.24.0)"
eq "the release PR merge is clean" "0" "$(_cg_prmerge "$P5" main release/v0.24.0)"
P5_FORK="$(g -C "$P5" merge-base main "$P5_REL")"
eq "the fork point's config has NO changelog key (witness: the adoption is unreleased)" "null" \
   "$(g -C "$P5" show "$P5_FORK:.release-pr.json" | jq -c .changelog)"
_cg_run "$P5" main --base main --head "$P5_REL" --title 'release: v0.24.0'
eq "END TO END: the release PR is GREEN — dev's exempt_paths apply" "0" "$CG_RC"
eq "… read where the release was cut from dev" "true" \
   "$(has "changelog.* read at $P5_DEVCUT (release 0.24.0: where it was cut from refs/remotes/origin/dev)" "$CG_OUT")"
echo "== CONTROL: the same release judged with the FORK POINT's config is RED =="
g -C "$P5" show "$P5_FORK:.release-pr.json" | jq -r '.changelog.exempt_paths // [] | .[]' > "$TMP/p5-fork-members"
eq "the fork point exempts nothing (witness)" "" "$(cat "$TMP/p5-fork-members")"
eq "so the fork-point reading obliges card#7400, which has no bullet" "card#7400" \
   "$( (cd "$P5" && _obligation_units "$P5" v0.23.1 "$TMP/p5-fork-members" '' '' 'release: v0.24.0') \
       > "$TMP/p5-units"; _missing <(_obliged_cards "$TMP/p5-units") "$P5/docs/CHANGELOG.md" 0.23.1)"

echo "== CONTROL: a release branch cannot exempt its own release =="
P5S="$TMP/p5-self-exemption"
_cg_repo "$P5S" '{"exempt_paths": ["tests/"]}'
_cg_commit "$P5S" app/a.txt 'feat(a): an app change (card#7401) (#112)'
g -C "$P5S" update-ref refs/remotes/origin/dev dev
g -C "$P5S" checkout -q -b release/v0.24.0 dev
printf '0.24.0\n' > "$P5S/VERSION"
_pf_fold "$P5S/docs" 0.24.0
jq '.changelog.exempt_paths += ["app/"]' "$P5S/.release-pr.json" > "$P5S/cfg.t" && mv "$P5S/cfg.t" "$P5S/.release-pr.json"
g -C "$P5S" commit -qam 'release: v0.24.0'
eq "the release PR merge is clean" "0" "$(_cg_prmerge "$P5S" main release/v0.24.0)"
_cg_run "$P5S" main --base main --head "$(g -C "$P5S" rev-parse release/v0.24.0)" --title 'release: v0.24.0'
eq "the release branch's own widening is IGNORED — still RED" "1 true" \
   "$CG_RC $(has 'card#7401 — add a line-initial' "$CG_OUT")"
echo "== REFUSAL: no refs/remotes/origin/dev to find the release cut =="
g -C "$P5S" update-ref -d refs/remotes/origin/dev
_cg_run "$P5S" main --base main --head "$(g -C "$P5S" rev-parse release/v0.24.0)" --title 'release: v0.24.0'
eq "rc 2, naming the ref" "2 true" "$CG_RC $(has "'refs/remotes/origin/dev' does not resolve" "$CG_OUT")"

echo "== the config surface: an unknown changelog.* key warns; a non-default tag_format refuses =="
UK="$TMP/unknown-key"
_cg_repo "$UK" '{"exempt_paths": [], "bogus_key": true}'
_cg_run "$UK" ''
eq "an unknown key is a WARNING naming it and this pin, not a refusal" "0 true" \
   "$CG_RC $(has "::warning::changelog-gate: changelog.bogus_key ignored by this pin (v$ABTK_TOOL_VERSION)" "$CG_OUT")"
eq "… and a key this pin reads is not warned about (witness: the warning is per key)" "false" \
   "$(has 'changelog.exempt_paths ignored' "$CG_OUT")"

echo "== reading the config at a revision: present, ABSENT and UNREADABLE are three outcomes =="
CA="$TMP/config-at"
_cg_repo "$CA"
g -C "$CA" checkout -q -b no-config
g -C "$CA" rm -q .release-pr.json && g -C "$CA" commit -qm 'chore: a revision with no config'
eq "a revision carrying the config yields it" "dev" \
   "$(CG_ROOT="$CA" _config_at dev .release-pr.json | jq -r .dev_branch)"
eq "a revision with no config yields {} — the adoption PR's own fork point" "{} 0" \
   "$(rc=0; out="$(CG_ROOT="$CA" _config_at no-config .release-pr.json)" || rc=$?; echo "$out $rc")"
eq "a revision this clone cannot read is a FAILURE, never {}" "1" \
   "$(rc=0; CG_ROOT="$CA" _config_at 0123456789abcdef0123456789abcdef01234567 .release-pr.json >/dev/null 2>&1 || rc=$?; echo "$rc")"
TF="$TMP/tag-format"
_cg_repo "$TF"
jq '. + {tag_format: "v{{version}}"}' "$TF/.release-pr.json" > "$TF/cfg.t" && mv "$TF/cfg.t" "$TF/.release-pr.json"
g -C "$TF" commit -qam 'chore: spell the default tag_format out'
_cg_run "$TF" ''
eq "the DEFAULT tag_format, spelled out, runs" "0" "$CG_RC"
jq '.tag_format = "{{version}}"' "$TF/.release-pr.json" > "$TF/cfg.t" && mv "$TF/cfg.t" "$TF/.release-pr.json"
g -C "$TF" commit -qam 'chore: unprefixed tags'
_cg_run "$TF" ''
eq "any other tag_format is rc 2, naming the key" "2 true" \
   "$CG_RC $(has '`tag_format` "{{version}}" is not supported; this gate reads `v*` tags only' "$CG_OUT")"
MAL="$TMP/malformed-key"
_cg_repo "$MAL"
g -C "$MAL" checkout -q -b feat
jq '. + {changelog: {exempt_paths: "docs/"}}' "$MAL/.release-pr.json" > "$MAL/cfg.t" && mv "$MAL/cfg.t" "$MAL/.release-pr.json"
g -C "$MAL" commit -qam 'ci: a malformed key'
eq "the PR merge is clean" "0" "$(_cg_prmerge "$MAL" dev feat)"
_cg_run "$MAL" dev --base dev --head "$(g -C "$MAL" rev-parse feat)" --title 'ci: a malformed key'
eq "a PR writing a malformed changelog.* key is refused ON THAT PR (rc 2), naming it" "2 true" \
   "$CG_RC $(has 'changelog.exempt_paths must be an array of strings' "$CG_OUT")"

_summary "changelog-card-entry-selftest"
