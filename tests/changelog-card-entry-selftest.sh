#!/usr/bin/env bash
# changelog-card-entry-selftest.sh — assert that every card shipped since the last release tag
# owns a line-initial `- **card#NNNN**` entry in docs/CHANGELOG.md.
#
# WHY THIS FILE EXISTS. `[Unreleased]` is where this repo records shipped work between
# releases, and 21 of the 24 cards merged to `dev` since v0.23.1 had an entry there. Nothing
# asserted it. Three did not, and the CHANGELOG is the *canonical* record — `CLAUDE.md`'s
# release table is explicitly a truncated snapshot of it (VERSIONING.md step 5), so an entry
# that never lands is not recoverable from a second copy later; the release PR that bundles
# the version section simply ships without it (card#5767).
#
# The three misses were not uniform, and the third is why the rule below is spelled the way it
# is:
#   * card#5371 (#198) and card#5671 (#209) — no mention anywhere in the file.
#   * card#5374 (#191) — no entry, and its ONLY mention is a *stale forward reference* inside
#     card#5359's entry: "card#5374 proposes the selftest that would have caught both
#     directions", written before #191 shipped it. A reader of a release cut from that file is
#     told the gate was proposed, not delivered. So "the file mentions the card" is NOT the
#     property worth gating — a mention can be prose that actively misinforms.
#
# This is the same defect shape this repo has already closed three times by building the
# tripwire instead of re-fixing instances — card#5355 (a selftest nothing runs), card#5389 (a
# hand-maintained `bin/` enumeration that under-covered), card#5374 itself (README's table vs
# `bin/`). Every one was "a list a human keeps in sync, with no check".
#
# THE RULE, and why line-initial. A card token in a commit subject obliges a bullet whose FIRST
# characters are `- **card#NNNN**`. That spelling is the entry *claiming to be about* that card.
# Bold-anywhere would be weaker in a way that matters here: `- **card#5766** — … supersedes
# **card#1234**` would then discharge card#1234's obligation with a clause about a different
# change. The cost is real and accepted — a PR that folds two cards owes two bullets, not one
# bullet naming both (`- **card#5370** (with **card#5372** folded in)` discharges only 5370).
# Two bullets is the more honest record anyway: both cards shipped.
#
# BOTH SIDES ARE DERIVED, neither is hand-listed — the property that makes this different from
# the convention it replaces. Obligations come from commit subjects (plus the PR title, below);
# discharges come from the file. There is no exempt-card list to maintain: a commit with no
# `card#` token (`chore(deps)`, `docs(orientation)` syncs) creates no obligation at all, which
# is the exemption, expressed as the absence of a trigger rather than as a second registry.
#
# WHY THE PR TITLE IS A SECOND OBLIGATION SOURCE. Under squash-merge the commit subject IS the
# PR title, so before merge the branch's own subjects may carry no token and the obligation
# would not exist yet — the gate would pass on the PR and fail on the push to `dev`
# AFTERWARDS, leaving a red integration branch and a merged omission. Reading `$PR_TITLE`
# (set from the pull_request event by .github/workflows/changelog-card-entry.yml) makes the
# check pre-merge, against the exact string that is about to become the subject. It is a plain
# env var, so a local run without it simply checks the merged history — the weaker of the two,
# never a different rule.
#
# THAT PRE-MERGE CLAIM IS ONLY TRUE IF THE JOB RE-RUNS WHEN THE TITLE CHANGES, which is why
# this gate has its OWN workflow rather than a job in ci.yml (card#6062): editing a PR title
# fires `edited`, never `synchronize`, so under ci.yml's event set the last run kept answering
# about the PRE-EDIT title — a token added by a title edit reached `dev` unchecked, exactly the
# merged-omission case above. The workflow subscribes `edited` for that reason.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that
# every `card#NNNN` appearing in a commit subject since the last release tag also appears at
# the head of some bullet in the sections ABOVE that tag's section. It proves nothing about
# whether the bullet's prose is accurate, current, or describes what shipped. Never report a
# green run as "the CHANGELOG is correct"; it means "no shipped card is undocumented".
#
# THE SCAN IS SECTION-SCOPED, and that is load-bearing in the err-GREEN direction. Entries are
# read from the top of the file down to the `## [<last release tag>]` header — i.e. from
# `[Unreleased]` plus any version section cut after that tag. Scanning the whole file would let
# an entry under `[0.20.0]` discharge a commit that landed after v0.23.1, which is a claim
# about the wrong release. Scoping also keeps the release PR green: step 4 of VERSIONING.md
# renames `[Unreleased]` to `[X.Y.Z]` while the newest tag is still the PREVIOUS version, so
# the just-renamed section is still above the stop header and every entry still counts.
#
# EMPTY IS A LEGITIMATE ANSWER HERE, AND THAT IS WHY THE MACHINERY IS FIXTURE-PROVEN. Right
# after a release both streams are genuinely empty (no commits since the tag; `[Unreleased]`
# emptied by step 4), so "non-empty" cannot be asserted against the live repo without a false
# red on the first PR of every cycle. The positive controls therefore run against FIXTURES
# carrying known members — including a fixture on which the gate must go GREEN, without which
# "always reports something" would satisfy the can-fail legs vacuously. The live repo is then
# trusted to answer "" honestly.
#
# THE WAY THIS COULD GO SILENTLY GREEN is a checkout that cannot see the history it needs, so
# the three preconditions below are refused BEFORE any assertion runs. The workflow gives this
# job `fetch-depth: 0` for that reason, which is also why it is its own job and not a
# `selftest` matrix entry in ci.yml (that job checks out at the default depth 1).
#
# The load-bearing one is the MISSING STOP HEADER: with no `## [<last tag>]` section the scan
# widens to the whole file and an entry under any past version discharges a commit that landed
# after the tag — that one errs GREEN, silently, and is the reason this block exists.
#
# The shallow guard is a DIAGNOSTIC, and saying so is the point — measured, not assumed. A
# shallow clone does not actually produce a wrong answer: either no `v*` tag is reachable from
# the truncated history and `git describe` fails (the tag guard catches it), or the tag IS
# reachable, in which case every commit between it and HEAD is present and the range is
# COMPLETE. What the shallow guard buys is an accurate message. Verified against a real
# `--depth 1` clone carrying all 36 tags after `fetch --tags`: `describe` still finds none, so
# without this guard that checkout is told "a checkout that fetched no tags lands here; fetch
# them" — advice that is simply false for the state it is describing, and sends the reader
# after the wrong fix. Do not read this guard as a second correctness catch; it is ordered
# first so the true diagnosis wins.
#
# THE `card#[0-9]+` SPELLING HERE IS DELIBERATELY HARDCODED, not read from `.release-pr.json`'s
# `card_token_regex` — even though that key now exists and carries the same string (card#5877).
# They are two copies on purpose, with different trust models: this is a GATE, and a gate whose
# obligation-detecting pattern comes from a PR-editable config file can be switched off by the
# same PR that needs switching off. The cost of the divergence is bounded and visible — the live
# leg prints its obligation and discharge COUNTS every run, so a spelling migration that emptied
# the obligation set would show as `0 obligation(s)` rather than pass quietly. Do not "consolidate"
# the two; if the repo's subject spelling changes, change this literal in the same PR.
#
# KNOWN, ACCEPTED FRICTION: a commit subject that cites a card it is not about ("supersedes
# card#1234") creates a real obligation for card#1234. This errs RED and is fixed by rewording
# the subject — which the repo already requires for an unrelated reason: a foreign `card#` token
# in a PR title hijacks the bridge's card correlation, so citing one is a defect on its own.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$HERE/.."
CHANGELOG="$ROOT/docs/CHANGELOG.md"
_need -r "$CHANGELOG"
_mktmp_scratch

# ---------------------------------------------------------------------------
# The rule, as three pure functions over files. Every assertion below — fixture and live —
# goes through these, so the fixtures test the code the live leg runs, not a paraphrase.
# ---------------------------------------------------------------------------

# _obliged <subjects-file> — the card tokens a set of commit subjects obliges, C-collated.
# Position-free: a token anywhere in the subject counts, because the subject spellings in this
# repo's history are not uniform ("… (card#5766) (#210)", "Close Stage D … (card#5566) (#206)").
_obliged() {
    { grep -oE 'card#[0-9]+' "$1" || true; } | LC_ALL=C sort -u
}

# _discharged <changelog> <version> — the card tokens carrying a line-initial bullet, read from
# the top of the file down to the `## [<version>]` header (exclusive).
#
# The stop header is matched as a LITERAL prefix, not a regex: the version is interpolated, and
# `0.23.1` as a regex also matches `0x23y1`. `index()` takes no pattern at all, so there is
# nothing to escape and no awk `-v` escape-processing to get wrong.
_discharged() {
    awk -v stop="## [$2]" 'index($0, stop) == 1 { exit } { print }' "$1" |
        { grep -oE '^- \*\*card#[0-9]+\*\*' || true; } |
        { grep -oE 'card#[0-9]+' || true; } | LC_ALL=C sort -u
}

# _missing <subjects-file> <changelog> <version> — obliged but not discharged.
# `comm` validates input order in the AMBIENT locale, so it is pinned to C alongside both
# producers: en_US collation ignores punctuation in its primary pass and would judge two
# correctly C-sorted `card#NNNN` streams as unsorted.
_missing() {
    LC_ALL=C comm -23 <(_obliged "$1") <(_discharged "$2" "$3")
}

# _has_version_header <changelog> <version> — is there a `## [<version>]` section at all?
_has_version_header() {
    [[ -n "$(awk -v stop="## [$2]" 'index($0, stop) == 1 { print "y"; exit }' "$1")" ]]
}

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

echo "== prove-it-can-fail: the PR-title obligation is real =="
# The pre-merge half. A branch whose own commit subjects carry no token still owes an entry for
# the card in the title it will be squashed under.
cp "$FIX/subjects" "$FIX/subjects-pr"
printf '%s\n' "refactor(z): a card that only the PR title names (card#9004)" >> "$FIX/subjects-pr"
eq "a card named only by the PR title is obliged" "true" \
   "$(has_line 'card#9004' "$(_missing "$FIX/subjects-pr" "$FIX/changelog-complete.md" "0.23.1")")"

# ---------------------------------------------------------------------------
# Live preconditions. Each is a HARD exit, not an assertion: the live leg below asserts an
# ABSENCE, so anything that can make it answer "" for a reason unrelated to the repo being
# clean has to stop the run rather than be reported alongside a pass.
# ---------------------------------------------------------------------------
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "selftest: $ROOT is not a git work tree — the obligation set cannot be derived" >&2
    exit 1
}
if [[ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" != "false" ]]; then
    echo "selftest: shallow clone. The range would still be correct IF a tag were reachable," >&2
    echo "          but on a truncated history 'git describe' usually finds none — and the tag" >&2
    echo "          guard below would then blame missing tags you may already have. Check out" >&2
    echo "          with fetch-depth: 0." >&2
    exit 1
fi
LAST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || true)"
if [[ -z "$LAST_TAG" ]]; then
    echo "selftest: no v* tag is reachable from HEAD — no release baseline to measure from." >&2
    echo "          A checkout that fetched no tags lands here (the shallow case is caught" >&2
    echo "          above), as does a branch with no tagged ancestor. Fetch tags." >&2
    exit 1
fi
LAST_VERSION="${LAST_TAG#v}"
if ! _has_version_header "$CHANGELOG" "$LAST_VERSION"; then
    echo "selftest: docs/CHANGELOG.md has no '## [$LAST_VERSION]' section for the newest tag" >&2
    echo "          $LAST_TAG. Without it the scan silently covers the WHOLE file, and an entry" >&2
    echo "          under any past version would discharge a commit that landed after the tag." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# The live assertion.
# ---------------------------------------------------------------------------
SUBJECTS="$TMP/subjects-live"
git -C "$ROOT" log --format='%s' "$LAST_TAG..HEAD" > "$SUBJECTS"
if [[ -n "${PR_TITLE:-}" ]]; then
    printf '%s\n' "$PR_TITLE" >> "$SUBJECTS"
fi

echo "== every card shipped since $LAST_TAG owns a line-initial CHANGELOG entry =="
printf '  ..   baseline %s · %s commit subject(s)%s · %s obligation(s) · %s discharged\n' \
    "$LAST_TAG" "$(git -C "$ROOT" rev-list --count "$LAST_TAG..HEAD")" \
    "$([[ -n "${PR_TITLE:-}" ]] && echo " + PR title" || echo "")" \
    "$(_obliged "$SUBJECTS" | grep -c . || true)" \
    "$(_discharged "$CHANGELOG" "$LAST_VERSION" | grep -c . || true)"
eq "no card shipped since $LAST_TAG is missing its entry" "" \
   "$(_missing "$SUBJECTS" "$CHANGELOG" "$LAST_VERSION")"

_summary "changelog-card-entry-selftest"
