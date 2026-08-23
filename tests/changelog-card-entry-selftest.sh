#!/usr/bin/env bash
# changelog-card-entry-selftest.sh — assert that every card shipped since the last release tag
# owns a line-initial `- **card#NNNN**` entry in docs/CHANGELOG.md, and that no PR left a
# SUPERSEDED entry standing beside its replacement.
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
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest properties the assertions support. One:
# every `card#NNNN` appearing in a commit subject since the last release tag also appears at
# the head of some bullet in the sections ABOVE that tag's section. Two: no card in that region
# carries two line-initial bullets that a SINGLE PR put there and left standing. Neither says
# anything about whether a bullet's prose is accurate, current, or describes what shipped, and
# the second sees BULLETS only — a duplicated line inside a multi-line entry is outside its
# population. Never report a green run as "the CHANGELOG is correct"; it means "no shipped card
# is undocumented, and no PR left a stale copy of its own entry behind".
#
# WHY THE SECOND PROPERTY EXISTS (card#7227). A `merge=union` attribute on docs/CHANGELOG.md
# resolves the anchor collision every sibling PR creates by keeping both sides' lines, and on a
# REBASE that same rule re-adds a line the branch had already superseded, at rc 0 and in
# silence, so a branch that reworded its own entry ships both wordings. Presence — the first
# property — cannot see it: both copies are line-initial bullets for the card, so the
# obligation is discharged twice over and the gate stays green over a file that now says two
# different things about one change.
#
# THIS REPO DOES NOT CARRY THAT ATTRIBUTE, AND HAS NO `.gitattributes` AT ALL — 6cbf5e5 dropped
# it in the same card, its benefit measured and absent (GitHub's server-side merge does not apply
# a merge driver, so sibling PRs still go CONFLICTING). So a catch-up `git merge origin/dev` on
# this repo DOES conflict on this file and IS hand-edited; nothing here should be read as saying
# otherwise. The leg stays because the shape it catches — one PR leaving a superseded bullet
# beside its replacement — is reachable without union (a bad conflict resolution, a stray
# copy-paste), and because the attribute is one `.gitattributes` away from returning.
#
# THE SCAN IS SECTION-SCOPED AT BOTH ENDS, and each end is load-bearing in a different
# direction. Entries are read from the `## [Unreleased]` header down to the
# `## [<last release tag>]` header — i.e. `[Unreleased]` plus any version section cut after that
# tag, and nothing else.
#
# The CEILING errs GREEN without it: scanning down past the stop header would let an entry under
# `[0.20.0]` discharge a commit that landed after v0.23.1, a claim about the wrong release. It
# also keeps the release PR green — step 4 of VERSIONING.md retitles `[Unreleased]` as `[X.Y.Z]`
# while the newest tag is still the PREVIOUS version, so the just-renamed section is still above
# the stop header and every entry still counts.
#
# The FLOOR errs GREEN too, and did — for real, until card#7293. Without it the region began at
# LINE 1, so the H1, the format blurb and the `begins at [0.8.2]` note were all inside it: a
# bullet sitting in NO section discharged its card. The card#7227 entry landed at line 1, above
# the `# Changelog` H1, and this gate reported it as documented. The floor is the LITERAL
# `## [Unreleased]` — step 4 opens a fresh one above the section it renames, so a correct release
# PR still has it, and pinning to it is what makes a release PR that forgot the fresh header red
# on that PR rather than on everyone else's afterwards (`_region` below carries the timing
# argument in full).
#
# EMPTY IS A LEGITIMATE ANSWER HERE, AND THAT IS WHY THE MACHINERY IS FIXTURE-PROVEN. Right
# after a release both streams are genuinely empty (no commits since the tag; `[Unreleased]`
# emptied by step 4), so "non-empty" cannot be asserted against the live repo without a false
# red on the first PR of every cycle. The positive controls therefore run against FIXTURES
# carrying known members — including a fixture on which the gate must go GREEN, without which
# "always reports something" would satisfy the can-fail legs vacuously. The live repo is then
# trusted to answer "" honestly.
#
# THE WAY THIS COULD GO SILENTLY GREEN is a checkout that cannot see the history it needs, or a
# file whose section structure the region cannot find, so the preconditions below are refused
# BEFORE any assertion runs. The workflow gives this job `fetch-depth: 0` for that reason, which
# is also why it is its own job and not a `selftest` matrix entry in ci.yml (that job checks out
# at the default depth 1). Do not restate their number here — it was inherited wrong once
# already; count the `exit 1`s in that block.
#
# The load-bearing one is the MISSING STOP HEADER: with no `## [<last tag>]` section the scan
# runs from `[Unreleased]` to EOF and an entry under any past version discharges a commit that
# landed after the tag — that one errs GREEN, silently, and is the reason this block exists.
#
# The MISSING FLOOR precondition — no `## [Unreleased]` above the stop — is a DIAGNOSTIC, in the
# shallow guard's sense rather than the stop header's. It cannot err green: an empty region
# discharges nothing, so every obligation reds. But `_stale_dupes` asserts an ABSENCE over that
# same region, and an empty region answers "" for a reason that has nothing to do with the file
# being clean — which is precisely what this block exists to refuse. It also stops the run
# blaming N innocent cards for one missing header. On a release PR it is the arm that fires: a
# PR that renamed `[Unreleased]` without opening a fresh one reds HERE, on itself.
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
# KNOWN, ACCEPTED FRICTION, and the second one belongs to the uniqueness leg. A commit subject
# that cites a card it is not about ("supersedes card#1234") creates a real obligation for
# card#1234; and the uniqueness leg's PR grouping reads the `(#NNN)` token that squash-merge
# leaves in the subject, so two commits that reached `dev` WITHOUT one — a direct push, or a
# branch merged with a merge commit — share the unsquashed group and would be read as one PR.
# Neither errs green. The first is fixed by rewording
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

# _region <changelog> <version> — the scanned region: the file from its `## [Unreleased]` header
# down to the `## [<version>]` header (exclusive), the floor line included. ONE owner for the
# section scope now that three readers need it; a second copy of the stop rule would be a second
# thing to get wrong.
#
# THE FLOOR IS THE POINT, and it was absent until card#7293. The region's PURPOSE has always
# been "the sections recording unreleased work", but with no floor its PREDICATE was "anywhere
# above the stop header" — which swallows the H1, the format blurb and the `begins at [0.8.2]`
# note, i.e. every line of preamble. A `- **card#NNNN**` bullet parked in NO section therefore
# discharged its card's obligation, and one was: the card#7227 entry landed at line 1, above
# the `# Changelog` H1, and this gate reported 21 obligations / 21 discharged over it.
#
# THE FLOOR IS THE LITERAL `## [Unreleased]`, AND A RELEASE PR IS WHY — the opposite of what it
# looks like. Step 4 of VERSIONING.md retitles the accumulated `## [Unreleased]` block as
# `## [X.Y.Z]` *and opens a fresh, empty `## [Unreleased]` above it*, so on a correct release PR
# the file reads `## [Unreleased]` → `## [X.Y.Z]` → `## [<prev>]` (the stop) and the renamed
# section is INSIDE the region, discharging exactly as before. Measured over the tag history as
# it stood at v0.29.0, not assumed: of the 42 `v*` tags, 31 carry a `docs/CHANGELOG.md` and 29 of
# those have `## [Unreleased]` as their first section header; the two that do not (v0.23.0,
# v0.23.1) predate the rule. Re-derive rather than trusting those figures — they were a reason,
# not a constant.
#
# The generous spelling — floor at "whatever the first `## [` header is" — is what would go
# wrong, and it goes wrong at the worst moment. A release PR that forgets the fresh
# `## [Unreleased]` passes that floor (the renamed `## [X.Y.Z]` becomes the floor), merges, and
# is tagged — and from the tag onward that same renamed section IS the stop header, so the region
# is empty and the precondition below reds EVERY subsequent PR on `dev`, blaming whoever pushed
# next. The literal floor reds on the release PR itself, where the omission is, while the person
# who made it is looking at the check.
#
# WHEN THERE IS NO `## [Unreleased]` ABOVE THE STOP the region is EMPTY, which discharges nothing
# and therefore reds loudly rather than passing over an unscanned file. The live leg refuses on
# that state outright (precondition below) so the message names the real cause instead of listing
# every shipped card as undocumented.
#
# BOTH headers are matched as LITERAL prefixes, not regexes: the stop version is interpolated,
# and `0.23.1` as a regex also matches `0x23y1`. `index()` takes no pattern at all, so there is
# nothing to escape and no awk `-v` escape-processing to get wrong; the floor uses the same
# technique for the same reason, plus one of its own — `[` is a regex metacharacter, so the
# obvious `/^## \[Unreleased\]/` spelling is one dropped backslash away from a character class.
#
# ⛔ RESIDUAL, unchanged in kind by this card: neither end is fence-aware, so a line beginning
# `## [Unreleased]` (or the stop header) at column 1 inside a fenced code block would be taken as
# the real header — the ceiling has carried that exposure since it was written, and
# `docs/CHANGELOG.md` carries no fenced block at all today.
_region() {
    awk -v stop="## [$2]" '
        index($0, stop) == 1 { exit }
        !in_region && index($0, "## [Unreleased]") != 1 { next }
        { in_region = 1; print }
    ' "$1"
}

# _bullets <changelog> <version> — the region's line-initial card bullets, VERBATIM and in file
# order. The uniqueness leg compares whole LINES, which is the one thing `_discharged` throws
# away.
_bullets() {
    _region "$1" "$2" | { grep -E '^- \*\*card#[0-9]+\*\*' || true; }
}

# _discharged <changelog> <version> — the card tokens carrying a line-initial bullet in the
# region. The head token is extracted BEFORE the id is, so a bullet whose prose cites a second
# card does not discharge it (the card#5374 shape, fixtured below).
_discharged() {
    _bullets "$1" "$2" |
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

# _bullets_at <repo> <rev> <path> <version> — the line-initial card bullets standing in the
# REGION of <path> as of <rev>, through the same `_region`/`_bullets` the live leg uses rather
# than a second carve of the same concept. "" when the path does not exist at that revision, and
# "" when the revision carries no `## [Unreleased]` above the stop header — both are "the region
# says nothing here", and the caller below is the one that decides what silence buys.
_bullets_at() {
    local blob
    blob="$(git -C "$1" show "$2:$3" 2>/dev/null)" || return 0
    _bullets <(printf '%s\n' "$blob") "$4"
}

# _added_bullets <repo> <path> <range> <version> — one TAB-separated `<pr>\t<+|->\t<bullet line>`
# record per line-initial card bullet a commit in <range> added to <path>, or removed from the
# unreleased REGION of <path>. Both signs are emitted; `_stale_dupes` owns what they mean.
#
# THE TWO SIGNS ARE SCOPED IN DIFFERENT PLACES, AND THAT IS THE POINT (card#7303). `_stale_dupes`
# states its scope as the region and both halves of its arithmetic have to honour it — but the
# evidence for the two signs lives in two different files. An ADD can be judged against the
# CHANGELOG as it stands: the bullet is either standing in the region now or it is not, which is
# the presence test `_stale_dupes` already runs, so its net half is gated on that same test and
# nothing is owed here. A REMOVAL cannot be judged that way at all — the line is GONE from the
# file, so the only witness to where it stood is the revision it was removed FROM. Hence the
# `<version>` argument and the parent-revision read below.
#
# ⛔ THE PATH-SCOPED VERSION ERRED GREEN, measured by construction rather than reasoned about:
# ONE commit adding two `card#4000` bullets to `[Unreleased]` while deleting two `card#4000`
# bullets from the frozen `## [0.23.1]` section leaves two duplicate wordings standing and was
# reported as NOTHING, because the path-scoped net was 2 − 2 = 0. The out-of-region removals are
# the entire difference — the same commit without them reds. A suppressed red is not a weaker
# check; on that axis it is a decoration. Both shapes are fixtured below, as a pair.
#
# THE BURDEN OF PROOF SITS ON THE SIDE THAT COULD SUPPRESS. A removal LOWERS net, so it is
# emitted only where the parent revision PROVES the line stood in the region; every unprovable
# case — the path absent there, or a revision whose region cannot be carved because it carries no
# `## [Unreleased]` — is dropped, which can only leave net HIGHER and therefore can only
# over-report. Adds need no such branch: they are emitted unconditionally and gated on presence
# downstream, so two surviving bullets always contribute net ≥ 2 by themselves.
#
# THE GROUP KEY IS THE PR NUMBER, and that is the whole trick. This repo squash-merges, so every
# commit that reached `dev` carries its PR number in the subject (`… (card#7038) (#265)`), and a
# commit that has not been squashed yet — the branch you are on — carries none. Grouping by it
# separates TWO PRs each documenting the same card, which is legitimate and is in this file
# twice today (card#6645 via #261/#262, card#7038 via #265/#266), from ONE PR leaving two
# bullets for one card, which is what a union merge mints. A whole-file "no id twice" rule — the
# obvious spelling, and the one to reach for first — reds this repo as it stands, on two entries
# that are correct.
#
# MERGE COMMITS CONTRIBUTE NOTHING, by `git log -p`'s default of not diffing them, and that is
# load-bearing rather than incidental: a branch that catches up with `git merge origin/dev` takes
# every sibling entry that landed meanwhile (by hand — this repo has no `.gitattributes`, so that
# merge conflicts on this file), and attributing all of them to the branch's own group would red
# a branch for entries it did not write.
_added_bullets() {
    local repo="$1" path="$2" range="$3" version="$4"
    local sha pr sign line memo_rev="" memo_bullets=""
    git -C "$repo" log -p --no-color --format='@@COMMIT@@ %H %s' "$range" -- "$path" | awk '
        /^@@COMMIT@@ / {
            sha = $2
            pr = "(unsquashed)"; s = $0
            while (match(s, /\(#[0-9]+\)/)) {
                pr = substr(s, RSTART + 2, RLENGTH - 3)
                s  = substr(s, RSTART + RLENGTH)
            }
            next
        }
        /^\+- \*\*card#[0-9]+\*\*/ { print sha "\t" pr "\t+\t" substr($0, 2); next }
        /^-- \*\*card#[0-9]+\*\*/  { print sha "\t" pr "\t-\t" substr($0, 2); next }
    ' | while IFS=$'\t' read -r sha pr sign line; do
        if [[ "$sign" == "-" ]]; then
            # One read per commit, not per record: `git log -p` emits a commit's records
            # together, so a single memo slot is all the caching this needs.
            if [[ "$memo_rev" != "$sha" ]]; then
                memo_rev="$sha"
                memo_bullets="$(_bullets_at "$repo" "$sha^" "$path" "$version")"
            fi
            [[ "$(has_line "$line" "$memo_bullets")" == true ]] || continue
        fi
        printf '%s\t%s\t%s\n' "$pr" "$sign" "$line"
    done
}

# _stale_dupes <records> <changelog> <version> — the card ids for which ONE PR left two or more
# bullets standing in the region. <records> is `_added_bullets`' output, whose REMOVALS are
# already region-scoped there (they have to be — see below); this function scopes the additions.
#
# TWO CONDITIONS, AND EACH REJECTS A REAL SHAPE THE OTHER ACCEPTS.
#
#   NET ≥ 2 — the PR's arithmetic, IN THE REGION AT BOTH ENDS (card#7303): bullets it added that
#   still STAND in the region, minus bullets it removed FROM the region. Editing somebody else's
#   entry is a remove plus an add and nets to zero, which is the only reason this leg can run on
#   the live history at all: #266 REWORDED #265's card#7038
#   bullet and added its own, so two of the three surviving card#7038 lines are its doing. Net
#   arithmetic reads that as one new entry. Counting raw additions reported it as a duplicate —
#   a false red on merged, correct history, seen before this rule was written and fixtured below.
#
#   TWO STILL PRESENT — the file's state: both copies are in the region right now. A branch that
#   corrects its own entry adds two wordings across two commits, which nets to two only when
#   `union` re-adds the superseded one during a rebase; if the branch simply reworded, the first
#   wording is gone and there is nothing for a reader to trip over.
#
# Requiring both means a red always corresponds to two lines a reader can see, which is what
# makes the failure actionable — and neither leg alone is sound: net-only reds a PR that
# legitimately split one card across two entries, presence-only reds #266.
#
# ⛔ UNTIL card#7303 THIS FUNCTION SAID "in the region" AND MEANT IT ON ONE HALF ONLY. `present`
# was region-scoped; the net arithmetic consumed `_added_bullets` whole, and that is scoped to the
# PATH. So a bullet a PR removed from a FROZEN released section — tidying a stray preamble bullet,
# correcting a shipped entry — subtracted from a net computed over the region's survivors, and two
# duplicate bullets standing in `[Unreleased]` reported NOTHING. It erred GREEN: a suppressed red,
# measured by construction (`_added_bullets` carries the reproduction) rather than argued.
#
# THE SCOPE WAS RIGHT AND THE PREDICATE WAS WRONG, so the predicate is what moved. The removal
# side is filtered where its evidence lives — in `_added_bullets`, against the parent revision,
# because a removed line is gone from the file and the file cannot answer for it. The addition
# side is filtered HERE, by letting an add count toward net only when the presence test has
# already found it standing in the region: it needs no history, it deletes the second copy of
# that test rather than adding one, and it makes net ≥ pres STRUCTURALLY — so the only thing that
# can pull a genuine duplicate back under the threshold is a genuine in-region removal.
#
# ⛔ RESIDUAL, deliberate and unchanged in kind: a PR that removes two in-region bullets for one
# card and files two of its own nets to zero and stays green. That is the replace-an-existing-entry
# case at multiplicity two — the same trade the net rule already makes at multiplicity one, and a
# card whose entry a PR must replace TWICE was carrying duplicates before that PR existed.
_stale_dupes() {
    local present pr sign line id
    present="$(_bullets "$2" "$3")"
    while IFS=$'\t' read -r pr sign line; do
        [[ -n "$line" ]] || continue
        id="${line#- \*\*}"; id="${id%%\**}"
        if [[ "$sign" == "-" ]]; then
            printf '%s\t%s\tnet\t-1\n' "$pr" "$id"
        elif [[ "$(has_line "$line" "$present")" == true ]]; then
            printf '%s\t%s\tnet\t1\n' "$pr" "$id"
            printf '%s\t%s\tpresent\t%s\n' "$pr" "$id" "$line"
        fi
    done < "$1" | awk -F'\t' '
        $3 == "net" { net[$1 FS $2] += $4; next }
        $3 == "present" {
            if (!(($1 FS $2 FS $4) in seen)) { seen[$1 FS $2 FS $4] = 1; pres[$1 FS $2]++ }
        }
        END {
            for (k in net)
                if (net[k] >= 2 && pres[k] >= 2) { split(k, a, FS); print a[2] }
        }
    ' | LC_ALL=C sort -u
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
# region discharges nothing, so every obligation reds — but `_stale_dupes` asserts an ABSENCE
# over this same region and would answer "" for a reason unrelated to the file being clean,
# which is why the live leg refuses on it (precondition below) rather than reporting alongside
# a pass.
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
# The uniqueness leg (card#7227). A `merge=union` attribute buys conflict-free sibling entries
# and pays for it with a silent both-sides-keep on the one shape that is not an append: a branch
# that REWORDS its own `[Unreleased]` entry and is then REBASED keeps the superseded wording too.
# Presence — everything above — cannot see that: both copies are line-initial bullets for the
# card, so the obligation is discharged twice over and the gate stays green over a file that now
# says two different things about one change. This repo has NO `.gitattributes` (6cbf5e5), so the
# fixtures below create the attribute in a throwaway repo of their own to exercise the mechanism;
# the leg guards the shape, which a hand-resolved conflict reaches without any attribute.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: a superseded bullet ONE PR left behind is REPORTED =="
# Six records over one unsquashed branch and two PRs. The branch's two are the corruption. #265
# and #266 are the shape this file really carries today, #266's included: it REWORDED #265's
# bullet and added its own, so it owns two of the surviving lines and must still not be named.
printf '%s\t%s\t%s\n' \
    '(unsquashed)' '+' '- **card#4000** — FIRST WORDING.' \
    '(unsquashed)' '+' '- **card#4000** — CORRECTED WORDING.' \
    '265'          '+' '- **card#7038** — one PR, one bullet.' \
    '266'          '-' '- **card#7038** — one PR, one bullet.' \
    '266'          '+' '- **card#7038** — one PR, one bullet, now cross-referenced.' \
    '266'          '+' '- **card#7038** — a second PR on the same card, its own bullet.' \
    > "$FIX/records"

cat > "$FIX/changelog-dupe.md" <<'EOF'
# Changelog

## [Unreleased]

- **card#9000** — a sibling entry that landed on dev while the branch was open.
- **card#4000** — FIRST WORDING.
- **card#4000** — CORRECTED WORDING.
- **card#7038** — one PR, one bullet, now cross-referenced.
- **card#7038** — a second PR on the same card, its own bullet.

## [0.23.1] - 2026-07-27

- **card#4000** — a released entry for the same card, below the stop header.
EOF
eq "the superseded copy is named, and ONLY it" \
   "card#4000" "$(_stale_dupes "$FIX/records" "$FIX/changelog-dupe.md" "0.23.1")"
# THE PAIRED WITNESS, and the reason this is not the obvious whole-file uniqueness rule:
# card#7038 has two bullets in the very same region, one of which #266 authored and the other of
# which #266 reworded, and it MUST NOT be reported. A rule that reds it reds this repo today.
eq "two PRs documenting one card are NOT reported (witness: the run saw both)" "" \
   "$(_stale_dupes "$FIX/records" "$FIX/changelog-dupe.md" "0.23.1" | grep -x 'card#7038' || true)"

echo "== prove-it-can-PASS: an ordinary reword reports nothing =="
# Same records — the branch still ADDED both wordings, one per commit, so its NET is still 2 —
# but only the corrected line survives in the file. This is the leg that isolates the presence
# condition: without it, every branch that ever fixed its own typo would red.
cat > "$FIX/changelog-reworded.md" <<'EOF'
# Changelog

## [Unreleased]

- **card#9000** — a sibling entry that landed on dev while the branch was open.
- **card#4000** — CORRECTED WORDING.
- **card#7038** — one PR, one bullet, now cross-referenced.
- **card#7038** — a second PR on the same card, its own bullet.

## [0.23.1] - 2026-07-27
EOF
eq "a reword whose superseded line is gone is not a duplicate" "" \
   "$(_stale_dupes "$FIX/records" "$FIX/changelog-reworded.md" "0.23.1")"
eq "the region scope holds: the released section's own card#4000 is not read as a survivor" \
   "" "$(_stale_dupes "$FIX/records" "$FIX/changelog-dupe.md" "0.23.1" | grep -x 'card#9000' || true)"

echo "== the derivation against the REAL mechanism: a union rebase, with its no-attribute control =="
# `_stale_dupes` above is proven over hand-written records. This proves the thing that mints
# them — `_added_bullets` reading a real history — and reproduces the measured defect end to end
# rather than restating it: two branch commits (add, then reword) rebased onto a `dev` that
# gained a sibling entry at the same anchor.
#
# THE CONTROL IS THE SAME FIXTURE WITHOUT THE ATTRIBUTE, and it is what makes this a measurement
# of `merge=union` rather than of git: without it the rebase STOPS for a human. If some future
# git conflicts under union too, the control still passes and this arm reds — the right way
# round.
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
# _mkrebase <dir> <union|plain> — build the branch/sibling collision, attempt the rebase, echo rc.
_mkrebase() {
    local d="$1"
    _newrepo "$d" "$2"
    g -C "$d" checkout -q -b feat
    _prepend "$d/CHANGELOG.md" '- **card#4000** — FIRST WORDING.'
    g -C "$d" commit -qam 'docs(changelog): the entry (card#4000)'
    sed -i 's/FIRST WORDING/CORRECTED WORDING/' "$d/CHANGELOG.md"
    g -C "$d" commit -qam 'docs(changelog): reword the entry (card#4000)'
    g -C "$d" checkout -q dev
    _prepend "$d/CHANGELOG.md" '- **card#9000** — a sibling PR filed at the same anchor.'
    g -C "$d" commit -qam 'fix(x): a sibling (card#9000) (#265)'
    g -C "$d" checkout -q feat
    local rc=0
    g -C "$d" rebase dev >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

RB="$TMP/rebase-union"
eq "with merge=union the rebase reports SUCCESS" "0" "$(_mkrebase "$RB" union)"
eq "and it silently kept the superseded wording" "true" \
   "$(has_line '- **card#4000** — FIRST WORDING.' "$(cat "$RB/CHANGELOG.md")")"
# The rebased reword commit records NO removal — union swallowed it — which is why the branch's
# NET is 2 rather than 1, and why net arithmetic can tell this apart from a plain reword at all.
eq "the derivation attributes both to the one unsquashed branch, and the sibling to its PR" \
   "(unsquashed)	+	- **card#4000** — CORRECTED WORDING.
(unsquashed)	+	- **card#4000** — FIRST WORDING.
265	+	- **card#9000** — a sibling PR filed at the same anchor." \
   "$(_added_bullets "$RB" CHANGELOG.md 'dev~1..HEAD' "0.23.1" | LC_ALL=C sort)"
eq "END TO END: the union-rebase duplicate is reported by the live code path" "card#4000" \
   "$(_stale_dupes <(_added_bullets "$RB" CHANGELOG.md 'dev~1..HEAD' "0.23.1") "$RB/CHANGELOG.md" "0.23.1")"
eq "and the sibling that arrived from dev is not (witness: it was seen)" "" \
   "$(_stale_dupes <(_added_bullets "$RB" CHANGELOG.md 'dev~1..HEAD' "0.23.1") "$RB/CHANGELOG.md" "0.23.1" \
      | grep -x 'card#9000' || true)"

RBC="$TMP/rebase-plain"
eq "CONTROL — without the attribute the same rebase STOPS for a human" "1" "$(_mkrebase "$RBC" plain)"
g -C "$RBC" rebase --abort >/dev/null 2>&1 || true

echo "== a PR that reworks an earlier PR's entry AND adds its own is not a duplicate =="
# The #266-over-#265 shape, on a real history rather than on records: it edits the standing
# card#7038 bullet and files its own beneath it, leaving two card#7038 lines in the file that it
# alone touched. This is the false red that net arithmetic removed — asserted, not argued.
MV="$TMP/reflow"
_newrepo "$MV"
_prepend "$MV/CHANGELOG.md" '- **card#7038** — the first PR on this card.'
g -C "$MV" commit -qam 'fix(a): first (card#7038) (#265)'
sed -i 's/^- \*\*card#7038\*\* — the first PR on this card\./- **card#7038** — the first PR on this card, now cross-referenced./' "$MV/CHANGELOG.md"
_prepend "$MV/CHANGELOG.md" '- **card#7038** — the second PR on the same card.'
g -C "$MV" commit -qam 'test(a): second (card#7038) (#266)'
eq "the edit is recorded with its removal, so #266 nets ONE new entry" \
   "265	+	- **card#7038** — the first PR on this card.
266	+	- **card#7038** — the first PR on this card, now cross-referenced.
266	+	- **card#7038** — the second PR on the same card.
266	-	- **card#7038** — the first PR on this card." \
   "$(_added_bullets "$MV" CHANGELOG.md 'HEAD~2..HEAD' "0.23.1" | LC_ALL=C sort)"
eq "so two surviving bullets from one PR are NOT reported when one replaced an existing entry" \
   "" "$(_stale_dupes <(_added_bullets "$MV" CHANGELOG.md 'HEAD~2..HEAD' "0.23.1") "$MV/CHANGELOG.md" "0.23.1")"

# ---------------------------------------------------------------------------
# BOTH ENDS OF THE NET ARITHMETIC ARE REGION-SCOPED (card#7303). `_added_bullets` is scoped to the
# PATH, and until this card `_stale_dupes` consumed it whole while stating its own scope as "in
# the region" — so a bullet removed from a FROZEN released section subtracted from a net computed
# over the region's survivors, and a real duplicate went unreported. It erred GREEN, which is the
# one direction a guard must not err, so what follows is the defect fixture and its MIRROR
# CONTROL: identical arithmetic (two adds, two removes, one PR), differing only in WHERE the two
# removed bullets stood. Without the control, "stop counting removals" would satisfy the fixture.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: an OUT-OF-region removal does not offset an in-region add =="
OOR="$TMP/removal-out-of-region"
_newrepo "$OOR"
printf -- '- **card#4000** — a released wording, frozen under the stop header.\n' >> "$OOR/CHANGELOG.md"
printf -- '- **card#4000** — a second released wording.\n' >> "$OOR/CHANGELOG.md"
g -C "$OOR" commit -qam 'docs(changelog): the released section (#264)'
g -C "$OOR" checkout -q -b feat
_prepend "$OOR/CHANGELOG.md" '- **card#4000** — FIRST WORDING.'
_prepend "$OOR/CHANGELOG.md" '- **card#4000** — CORRECTED WORDING.'
sed -i '/^- \*\*card#4000\*\* — a released wording, frozen under the stop header\.$/d
        /^- \*\*card#4000\*\* — a second released wording\.$/d' "$OOR/CHANGELOG.md"
g -C "$OOR" commit -qam 'docs(changelog): file the entry and tidy the released section (card#4000)'
# The two witnesses that make the assertion below about SCOPE rather than about an absent diff:
# the commit really does remove two card#4000 bullets, and two really do stand in the region.
eq "the branch commit really removes two card#4000 bullets (witness: the diff is not empty)" "2" \
   "$(g -C "$OOR" show HEAD -- CHANGELOG.md | { grep -c '^-- \*\*card#4000\*\*' || true; })"
eq "and two duplicate wordings stand in the region right now" \
   "- **card#4000** — CORRECTED WORDING.
- **card#4000** — FIRST WORDING." "$(_bullets "$OOR/CHANGELOG.md" "0.23.1")"
eq "the derivation keeps the in-region adds and drops the out-of-region removals" \
   "(unsquashed)	+	- **card#4000** — CORRECTED WORDING.
(unsquashed)	+	- **card#4000** — FIRST WORDING." \
   "$(_added_bullets "$OOR" CHANGELOG.md 'dev..feat' "0.23.1" | LC_ALL=C sort)"
eq "END TO END: the duplicate is REPORTED — a released-section tidy-up cannot suppress it" \
   "card#4000" \
   "$(_stale_dupes <(_added_bullets "$OOR" CHANGELOG.md 'dev..feat' "0.23.1") "$OOR/CHANGELOG.md" "0.23.1")"

echo "== CONTROL: the same arithmetic with IN-region removals still nets to zero =="
# Two adds, two removes, one PR — the only difference from the fixture above is that the removed
# bullets stood INSIDE the region, which is the replace-an-existing-entry case the net rule
# exists to let through. A fix that simply stopped counting removals reds here.
INR="$TMP/removal-in-region"
_newrepo "$INR"
_prepend "$INR/CHANGELOG.md" '- **card#4000** — a standing wording, inside the region.'
_prepend "$INR/CHANGELOG.md" '- **card#4000** — a second standing wording, inside the region.'
g -C "$INR" commit -qam 'docs(changelog): two standing entries (#264)'
g -C "$INR" checkout -q -b feat
_prepend "$INR/CHANGELOG.md" '- **card#4000** — FIRST WORDING.'
_prepend "$INR/CHANGELOG.md" '- **card#4000** — CORRECTED WORDING.'
sed -i '/standing wording, inside the region\.$/d' "$INR/CHANGELOG.md"
g -C "$INR" commit -qam 'docs(changelog): replace both standing entries (card#4000)'
eq "the in-region removals ARE recorded (witness: the filter drops removals by scope, not by sign)" \
   "2" "$(_added_bullets "$INR" CHANGELOG.md 'dev..feat' "0.23.1" | cut -f2 | { grep -c '^-' || true; })"
eq "so a PR that replaced two standing entries is NOT reported" "" \
   "$(_stale_dupes <(_added_bullets "$INR" CHANGELOG.md 'dev..feat' "0.23.1") "$INR/CHANGELOG.md" "0.23.1")"

echo "== the removal side reads the PARENT revision, and says nothing when it cannot =="
# `_bullets_at`'s own arms, unit-tested: a removal is counted only where the parent revision
# PROVES the line stood in the region, so every way of failing to prove it has to answer "" —
# and each "" needs a witness, or it is indistinguishable from a helper that always answers "".
eq "at a revision carrying the region, its bullets are read back (positive control)" \
   "- **card#4000** — CORRECTED WORDING.
- **card#4000** — FIRST WORDING." "$(_bullets_at "$OOR" feat CHANGELOG.md "0.23.1")"
eq "a path that does not exist at the revision is not an error, it is nothing" "" \
   "$(_bullets_at "$OOR" feat NOTHING-HERE.md "0.23.1")"
g -C "$OOR" checkout -q -b noheader
sed -i '/^## \[Unreleased\]$/d' "$OOR/CHANGELOG.md"
g -C "$OOR" commit -qam 'docs(changelog): a revision with no [Unreleased] header at all'
eq "a revision whose region cannot be carved answers with nothing …" "" \
   "$(_bullets_at "$OOR" noheader CHANGELOG.md "0.23.1")"
eq "… while that same revision still carries the bullets (witness: not an empty file)" "true" \
   "$(has_line '- **card#4000** — FIRST WORDING.' "$(g -C "$OOR" show noheader:CHANGELOG.md)")"
g -C "$OOR" checkout -q feat

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
    echo "          $LAST_TAG. Without it the scan runs to EOF, and an entry under any past" >&2
    echo "          version would discharge a commit that landed after the tag." >&2
    exit 1
fi
if [[ -z "$(_region "$CHANGELOG" "$LAST_VERSION")" ]]; then
    echo "selftest: docs/CHANGELOG.md has no '## [Unreleased]' header above '## [$LAST_VERSION]'," >&2
    echo "          so the scanned region is EMPTY. Every entry filed for an unreleased card is" >&2
    echo "          currently outside it. On a release PR this means step 4 of VERSIONING.md was" >&2
    echo "          half-done: retitling '## [Unreleased]' as '## [X.Y.Z]' must also open a" >&2
    echo "          fresh, empty '## [Unreleased]' above it. Add that header back." >&2
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

echo "== no PR left a superseded [Unreleased] entry standing beside its replacement =="
RECORDS="$TMP/added-live"
_added_bullets "$ROOT" docs/CHANGELOG.md "$LAST_TAG..HEAD" "$LAST_VERSION" > "$RECORDS"
printf '  ..   %s bullet(s) added, %s removed, across %s contributor(s) since %s\n' \
    "$(cut -f2 "$RECORDS" | grep -c '^+' || true)" \
    "$(cut -f2 "$RECORDS" | grep -c '^-' || true)" \
    "$(cut -f1 "$RECORDS" | LC_ALL=C sort -u | grep -c . || true)" "$LAST_TAG"
eq "no card carries two surviving bullets from one PR" "" \
   "$(_stale_dupes "$RECORDS" "$CHANGELOG" "$LAST_VERSION")"

_summary "changelog-card-entry-selftest"
