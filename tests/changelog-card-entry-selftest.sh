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
# THAT SCOPE IS RIGHT AND ITS REMEDY WAS WRONG (card#8442). A branch cut BEFORE a release fold has
# its `[Unreleased]` entry carried UNDER the folded `## [X.Y.Z]` heading by the merge — cleanly,
# because step 4 is textually a pure insertion at the top of the old section's body and the
# branch's bullet is an insertion further down it. The region is not at fault: the entry really is
# outside it, and the card really is undocumented for the release it is about to be counted in. But
# the only thing this gate said was "missing", so an author filed a SECOND entry and the file
# shipped two wordings of one change — the `_stale_dupes` shape, minted by this gate's own advice.
# So when `_missing` names a card, `_missing_remedy` now asks WHERE the branch's own new lines
# landed and, when three legs establish that the heading they landed under was cut while this
# branch was open, names the MOVE instead. It is a DIAGNOSTIC ONLY — the verdict is identical in
# every shape, and a diagnosis that cannot be established prints the text this gate always printed.
# `_prefold_heading` carries the three legs and the residuals they buy.
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
# section scope; a second copy of the stop rule would be a second thing to get wrong. The reader
# count is deliberately NOT restated here — it was stale within one card of being written, and
# the callers are two screens away (card#7304 tracks consolidating what carves this concept).
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
# than a second carve of the same concept. "" on any revision whose region cannot be CARVED —
# the three arms are enumerated at `_added_bullets` below, which is the caller that decides what
# silence buys.
#
# ⛔ THE STOP-HEADER GATE IS NOT BELT-AND-BRACES, it is the arm that errs GREEN. `_region`'s
# ceiling is `index($0, "## [<version>]") == 1 { exit }` — a test that simply never fires on a
# revision carrying no such header, so the carve runs `[Unreleased]` → EOF and reports every
# frozen released section as in-region. The live leg refuses that state outright (the missing
# stop header is the load-bearing hard exit in the preconditions block); this function is handed
# ARBITRARY historical revisions and cannot refuse, so it gates on the same `_has_version_header`
# the precondition uses and drops the revision instead.
#
# The blob goes to a FILE, not a `<(printf …)` process substitution: `_has_version_header` and
# `_bullets` are two readers, and a builtin writer feeding an `awk` that `exit`s early is the
# SIGPIPE shape `_selftest-prelude.sh`'s `has_line` header documents at length.
_bullets_at() {
    local blob at="$TMP/bullets-at"
    blob="$(git -C "$1" show "$2:$3" 2>/dev/null)" || return 0
    printf '%s\n' "$blob" > "$at"
    if _has_version_header "$at" "$4"; then _bullets "$at" "$4"; fi
    rm -f "$at"
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
# emitted only where the parent revision PROVES the line stood in the region. THREE arms drop it,
# and they are not equivalent — the third is the one that would have erred GREEN:
#   * the path does not exist at that revision;
#   * the revision carries no `## [Unreleased]`, so `_region` yields an empty region;
#   * the revision carries `## [Unreleased]` but NOT the stop header `## [<version>]`, so
#     `_region`'s ceiling never fires and a carve would run to EOF, reporting every frozen
#     released section as in-region — which is card#7303's own defect, re-minted one layer down
#     on a surface that has no precondition to refuse it. `_bullets_at` gates that arm on
#     `_has_version_header` rather than trusting the carve, and the arm is fixtured below.
# Given those three, a dropped removal can only leave net HIGHER — this side can only
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
# THE REMEDY WHEN THE REGION FINDS NOTHING (card#8442) — a DIAGNOSTIC, not a verdict.
#
# `_region`'s bound is right and stays exactly where it is: everything below decides only WHICH
# SENTENCE prints beside a red `_missing` has already returned. No arm here can make the gate
# pass, which is why "the diagnosis could not be established" is not a failure — it prints the
# generic text, the only text this gate had before this card.
#
# WHAT IT EXISTS FOR. A branch cut BEFORE a release fold has its `[Unreleased]` entry carried
# UNDER the folded `## [X.Y.Z]` heading by the merge, at rc 0 and with no conflict for anyone to
# resolve. Step 4 of VERSIONING.md is textually a pure INSERTION — the new `## [X.Y.Z]` heading
# goes in at the TOP of the old section's body — and the branch's bullet is an insertion further
# down that same body, so git applies both and the bullet ends up below the new heading. The
# entry is then OUTSIDE the region, `_missing` names the card, and the only thing the author was
# told was that the entry is missing. Following that, they file a SECOND one and the file ships
# two wordings of one change — the `_stale_dupes` shape, minted by this gate's own remedy.
# Bridge card#8339 / DL-329 measured the same mechanism on its own copy (run 33544122079); this
# is the toolkit half, reported here rather than forked.
# ---------------------------------------------------------------------------

# _added_section_label <merged-changelog> <added-lines> <baseline-changelog> — the label of the
# FIRST RELEASED section of <merged-changelog> whose BODY carries a line the branch introduced.
#
# ⚠ THE LABEL IS NOT THE DIAGNOSIS, and treating it as one is the false-positive shape bridge
# #632 measured and repaired before this card was written. This function answers "where did the
# branch's own new lines land"; `_prefold_heading` below owns whether a FOLD is what put them
# there, and it is the only caller.
#
# A NEEDLE THE BASELINE ALREADY CARRIES IS DROPPED, and that subtraction is load-bearing rather
# than tidy: `docs/CHANGELOG.md` carries 67 `### Added` / `### Fixed` / `### Docs` heads today, so
# a branch opening one under `[Unreleased]` would otherwise match the identical head inside a
# released section and return a label with nothing behind it. A branch line that merely
# duplicates a standing one is dropped with them — no label rather than a wrong one.
#
# THE HEADER TEST IS `_region`'s, GENERALISED — not a second carve of it. Same `index($0, "## [")
# == 1` technique for the same two reasons: nothing to escape, and `[` never reaching a regex.
# `_region` asks whether a line IS one nominated header; this asks which header a line is UNDER.
# A header whose bracket never closes opens no released section while still being a BOUNDARY,
# which is the reading the plain carve already gives it.
#
# THE HEADER LINE IS NEVER A NEEDLE SITE (`next` before the membership test). A branch that adds
# the version heading ITSELF has not thereby filed anything under it — and that is precisely the
# shape leg 2 below refuses, so letting it match here would hand that leg a label to reject
# instead of never minting one.
_added_section_label() {
    awk -v addedf="$2" -v basef="$3" '
        FILENAME == basef  { known[$0] = 1; next }
        FILENAME == addedf {
            if ($0 ~ /[^[:space:]]/ && !($0 in known)) needle[$0] = 1
            next
        }
        index($0, "## [") == 1 {
            rest = substr($0, 5)
            close_at = index(rest, "]")
            label = (close_at > 1) ? substr(rest, 1, close_at - 1) : ""
            released = (label != "" && label != "Unreleased")
            next
        }
        released && ($0 in needle) { print label; exit }
    ' "$3" "$2" "$1"
}

# _branch_added_lines <repo> <path> <base> <head> — the lines the BRANCH adds to <path>, one per
# line. ONE owner, because there are two readers: `_prefold_heading` feeds them to the locator on
# the live path, and the fixtures below feed them to the locator in isolation. A second
# `git diff | awk` for the second reader would be free to answer a question the first one did not.
#
# `$base...$head` is the branch's OWN work — the diff from the merge-base, not from the base tip —
# so a line the BASE brought in while the branch was open is not among these.
#
# THE `+` SIDE ONLY, with git's DEFAULT indicator. Bridge's copy re-spells the OLD indicator
# because it reads the `-` side too, where a deleted line spelled `-- text` renders as `--- text`
# and is indistinguishable from the `--- a/path` header — skipping it would HIDE a deletion. Here
# the mirror collision (`++ text` rendering as `+++ text`) costs a NEEDLE, which DROPS a diagnosis
# rather than minting one, and that is the safe direction.
_branch_added_lines() {
    git -C "$1" diff --no-color "$3...$4" -- "$2" |
        awk '/^\+\+\+ /{next} /^\+/{print substr($0, 2)}'
}

# _prefold_heading <repo> <path> <base> <head> <merged-changelog> — the released label to NAME in
# the remedy, or nothing at rc 1 when the fold diagnosis is not established.
#
# THE FOLD IS ASSERTED, NOT INFERRED FROM THE LABEL. Bridge #632 R1 measured two shapes that make
# `_added_section_label` return a released label while the fold sentence is FALSE, and both are
# reachable here: a branch CORRECTING a line inside a section that already stood when it forked,
# and a branch that CUTS the section itself and files under it. So the predicate has three legs,
# and each of the two extra ones rejects one of those shapes:
#
#   LEG 2 — the label EXISTS on `$BASE`. Rejects the branch that cut the section: a PR that adds
#   `## [X.Y.Z]` and files under it would otherwise be told that X.Y.Z "was cut while this branch
#   was open" by somebody else.
#   LEG 3 — the label is ABSENT at `git merge-base $BASE $HEAD`. Rejects the stale-fix and the
#   deliberate-edit shapes: a section that already stood where this branch forked was not cut
#   while it was open, and telling an author to lift a SHIPPED line out of a release is worse
#   than telling them nothing.
#
# BOTH READS GO THROUGH `_has_version_header` — the section parser the live preconditions and
# `_bullets_at` already use. A second `grep '## \['` for either file would be two carvings of one
# boundary free to disagree, which is the defect class this repo keeps closing.
#
# ⛔ THE DISCLOSED RESIDUAL, and it is the price of spelling leg 3 as the MERGE-BASE: a genuinely
# pre-fold branch that has ALREADY merged the folded base makes that base its own merge-base, so
# the heading stands there, leg 3 goes false, and the author gets the generic text. Unhelpful,
# never confidently wrong — and fixtured below rather than argued. (Bridge's copy spells leg 3 at
# the branch's FORK POINT instead, which keeps the diagnosis across that merge at the cost of
# refusing every branch whose own oldest commit is itself a merge. That trade is bridge's; this
# card's spec pinned the merge-base spelling and this comment is where the difference is
# recorded.)
#
# ⛔ AN EMPTY `$BASE` OR `$HEAD` REFUSES rather than defaulting. `_pr_merge_refs` answers with
# NOTHING off a checkout that is not a pull_request merge ref, and `git diff "...$head"` off an
# empty base is a legal command with a different meaning — a diagnosis derived from it would be a
# confident claim about a range nobody asked for.
_prefold_heading() {
    local repo="$1" path="$2" base="$3" head="$4" merged="$5"
    local d="$TMP/prefold" label='' mb='' rc=0
    [[ -n "$base" && -n "$head" ]] || return 1
    rm -rf "$d"
    mkdir -p "$d"
    {
        _branch_added_lines "$repo" "$path" "$base" "$head" > "$d/added" &&
        git -C "$repo" show "$base:$path" > "$d/baseline" &&
        mb="$(git -C "$repo" merge-base "$base" "$head")" &&
        git -C "$repo" show "$mb:$path" > "$d/mergebase" &&
        # An EMPTY read of either revision is REFUSED, not read as "that revision had no
        # sections". It inverts the safe direction on both legs at once: leg 2 would find no
        # heading and drop a true diagnosis, and leg 3 — which is INVERTED — would find none and
        # SATISFY itself off a failed read, turning a tooling fault into a confident answer.
        [[ -s "$d/baseline" && -s "$d/mergebase" ]] &&
        label="$(_added_section_label "$merged" "$d/added" "$d/baseline")" &&
        [[ -n "$label" ]] &&
        _has_version_header "$d/baseline" "$label" &&
        ! _has_version_header "$d/mergebase" "$label"
    } || rc=$?
    rm -rf "$d"
    [[ "$rc" -eq 0 ]] || return 1
    printf '%s\n' "$label"
}

# _missing_remedy <repo> <path> <base> <head> <merged-changelog> — the text printed beside a red
# `_missing`. ONE spelling of both arms, in one function: a guard's remediation string is a doc
# surface, and a per-caller copy is two versions of one instruction free to drift.
#
# The `|| heading=''` collapses EVERY refusal above — an unestablished diagnosis and a tooling
# failure alike mean "this is not established", and the remedy for that is the one this gate
# always printed. Naming a fold nobody verified would send the author to edit a RELEASED section.
_missing_remedy() {
    local heading=''
    heading="$(_prefold_heading "$@")" || heading=''
    if [[ -n "$heading" ]]; then
        printf 'your entry landed under `[%s]` after the fold — move it back to `[Unreleased]`.\n' "$heading"
        printf 'v%s was cut while this branch was open. The fold renamed the `[Unreleased]` heading your\n' "$heading"
        printf 'entry sat under and opened a fresh one above it, so the merge left the entry inside a\n'
        printf 'RELEASED section, which now claims work that did not ship in it. Do NOT file a second\n'
        printf 'entry — move the one you already have.\n'
    else
        printf 'add a line-initial `- **card#NNNN**` bullet under `## [Unreleased]` in docs/CHANGELOG.md.\n'
    fi
}

# _pr_merge_refs <repo> — `<base> <head>` when HEAD is the pull_request MERGE COMMIT that
# `actions/checkout` leaves in the tree, and NOTHING otherwise.
#
# The diagnosis is about a MERGE — the entry moves only when the base's fold and the branch's
# bullet are combined — so it needs the merged file, and this gate already runs against exactly
# that: `refs/pull/N/merge`, whose first parent is the base tip and whose second is the branch.
#
# BOTH CONDITIONS ARE REQUIRED, and neither implies the other. `GITHUB_BASE_REF` is set only on a
# `pull_request` event, which is what makes that parent ORDER a documented fact rather than a
# guess about an arbitrary two-parent commit; the parent-count test is what keeps a checkout that
# is NOT a merge from being read as one on an event that does set the variable.
#
# ⛔ RESIDUAL: a local `bash tests/changelog-card-entry-selftest.sh` and the `push` runs on
# main/dev therefore establish NO diagnosis and print the generic remedy. The VERDICT is identical
# in all three, and the pull_request run is the one an author is looking at while the branch is
# still open and the move is still cheap.
_pr_merge_refs() {
    [[ -n "${GITHUB_BASE_REF:-}" ]] || return 0
    [[ "$(git -C "$1" rev-list --parents -n 1 HEAD 2>/dev/null | wc -w)" -eq 3 ]] || return 0
    printf '%s %s\n' "$(git -C "$1" rev-parse HEAD^1)" "$(git -C "$1" rev-parse HEAD^2)"
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

echo "== prove-it-can-fail: gating ADDS on presence closes the FALSE RED (card#7303) =="
# The other direction of the same defect, and the half of the predicate change nothing else here
# witnesses — `$MV` above stays green with adds gated or not, so it is the CONTROL, not the
# evidence. With adds counted whether or not they stand, a PR that rewords a prior card's bullet
# (+1/−1), files its own (+1) and backfills one UNDER the stop header (+1) reaches net 2 over two
# survivors and reds the legitimate two-PRs-on-one-card shape this leg exists to let through.
FRB="$TMP/false-red-backfill"
_newrepo "$FRB"
_prepend "$FRB/CHANGELOG.md" '- **card#7038** — the first PR on this card.'
g -C "$FRB" commit -qam 'fix(a): the first PR on this card (card#7038) (#265)'
sed -i 's/^- \*\*card#7038\*\* — the first PR on this card\.$/- **card#7038** — the first PR on this card, now cross-referenced./' \
    "$FRB/CHANGELOG.md"
_prepend "$FRB/CHANGELOG.md" '- **card#7038** — the second PR on the same card.'
printf -- '- **card#7038** — a backfilled note under the released version.\n' >> "$FRB/CHANGELOG.md"
g -C "$FRB" commit -qam 'test(a): the second PR, plus a backfill under the released header (card#7038) (#266)'
eq "#266 really files THREE adds (witness: ungated, its own net reaches the threshold)" "3" \
   "$(_added_bullets "$FRB" CHANGELOG.md 'HEAD~2..HEAD' "0.23.1" |
      awk -F'\t' '$1 == "266" && $2 == "+"' | { grep -c . || true; })"
eq "and exactly ONE in-region removal, which is all the net has to pull it back down" "1" \
   "$(_added_bullets "$FRB" CHANGELOG.md 'HEAD~2..HEAD' "0.23.1" |
      awk -F'\t' '$1 == "266" && $2 == "-"' | { grep -c . || true; })"
eq "the backfilled bullet stands in the FILE but not in the REGION (witness: both, in that order)" \
   "true false" \
   "$(has_line '- **card#7038** — a backfilled note under the released version.' \
       "$(cat "$FRB/CHANGELOG.md")") $(has_line \
       '- **card#7038** — a backfilled note under the released version.' \
       "$(_bullets "$FRB/CHANGELOG.md" "0.23.1")")"
eq "so a PR that reworded one entry and filed its own is NOT reported for backfilling a third" \
   "" "$(_stale_dupes <(_added_bullets "$FRB" CHANGELOG.md 'HEAD~2..HEAD' "0.23.1") "$FRB/CHANGELOG.md" "0.23.1")"

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

echo "== a PARENT REVISION CARRYING NO STOP HEADER proves nothing either =="
# The third unprovable arm, and the one that errs GREEN if `_bullets_at` merely CARVES: with no
# `## [0.23.1]` at the parent, `_region`'s ceiling test never fires, the carve runs
# `[Unreleased]` → EOF, and bullets removed from a FROZEN released section read as in-region and
# subtract — card#7303's own defect, intact, one layer down. Not a paper shape: a branch that
# catches up across a release boundary has exactly this parent, and this repo creates those.
NST="$TMP/parent-no-stop-header"
_newrepo "$NST"
cat > "$NST/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.22.0] - 2026-06-01

- **card#4000** — a released wording, frozen.
- **card#4000** — a second released wording.
EOF
g -C "$NST" commit -qam 'docs(changelog): the file as it stood before 0.23.1 was cut (#264)'
g -C "$NST" checkout -q -b feat
_prepend "$NST/CHANGELOG.md" '- **card#4000** — FIRST WORDING.'
_prepend "$NST/CHANGELOG.md" '- **card#4000** — CORRECTED WORDING.'
sed -i '/^- \*\*card#4000\*\* — a released wording, frozen\.$/d
        /^- \*\*card#4000\*\* — a second released wording\.$/d' "$NST/CHANGELOG.md"
awk '/^## \[0\.22\.0\]/ { print "## [0.23.1] - 2026-07-27"; print "" } 1' \
    "$NST/CHANGELOG.md" > "$NST/CHANGELOG.md.t" && mv "$NST/CHANGELOG.md.t" "$NST/CHANGELOG.md"
g -C "$NST" commit -qam 'docs(changelog): catch up across the release and tidy the released section (card#4000)'
eq "the parent revision carries the FLOOR …" "true" \
   "$(has_line '## [Unreleased]' "$(g -C "$NST" show 'feat^:CHANGELOG.md')")"
eq "… and not the STOP HEADER, which is what makes this the third arm and not the second" "false" \
   "$(has '## [0.23.1]' "$(g -C "$NST" show 'feat^:CHANGELOG.md')")"
eq "so that revision proves nothing about where a removed line stood …" "" \
   "$(_bullets_at "$NST" 'feat^' CHANGELOG.md "0.23.1")"
eq "… while still carrying the released bullets an unbounded carve would have returned (witness)" \
   "true" "$(has_line '- **card#4000** — a released wording, frozen.' \
       "$(g -C "$NST" show 'feat^:CHANGELOG.md')")"
eq "the branch commit really removes two card#4000 bullets (witness: the diff is not empty)" "2" \
   "$(g -C "$NST" show HEAD -- CHANGELOG.md | { grep -c '^-- \*\*card#4000\*\*' || true; })"
eq "the derivation keeps the in-region adds and drops both unprovable removals" \
   "(unsquashed)	+	- **card#4000** — CORRECTED WORDING.
(unsquashed)	+	- **card#4000** — FIRST WORDING." \
   "$(_added_bullets "$NST" CHANGELOG.md 'dev..feat' "0.23.1" | LC_ALL=C sort)"
eq "END TO END: the duplicate is REPORTED — a parent predating the stop header cannot suppress it" \
   "card#4000" \
   "$(_stale_dupes <(_added_bullets "$NST" CHANGELOG.md 'dev..feat' "0.23.1") "$NST/CHANGELOG.md" "0.23.1")"

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
g -C "$OOR" checkout -q -b nostop dev
sed -i '/^## \[0\.23\.1\]/d' "$OOR/CHANGELOG.md"
g -C "$OOR" commit -qam 'docs(changelog): a revision predating the stop header section'
eq "a revision with the floor but NO stop header answers with nothing too …" "" \
   "$(_bullets_at "$OOR" nostop CHANGELOG.md "0.23.1")"
eq "… and its \"\" is the GATE, not an empty region: it carries the floor AND the frozen bullets" \
   "true true" \
   "$(has_line '## [Unreleased]' "$(g -C "$OOR" show nostop:CHANGELOG.md)") $(has_line \
       '- **card#4000** — a released wording, frozen under the stop header.' \
       "$(g -C "$OOR" show nostop:CHANGELOG.md)")"
g -C "$OOR" checkout -q feat

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
# _pf_remedy <dir> — the LIVE LEG's two calls, verbatim: derive the refs off the merge commit,
# then ask for the remedy. `GITHUB_BASE_REF` is what a pull_request run sets and what
# `_pr_merge_refs` requires; setting it here is the fixture standing in for that event.
_pf_remedy() {
    local refs
    refs="$(GITHUB_BASE_REF=dev _pr_merge_refs "$1")"
    _missing_remedy "$1" CHANGELOG.md "${refs%% *}" "${refs##* }" "$1/CHANGELOG.md"
}
# _pf_heading <dir> — the same derivation, stopping at the label the three legs establish.
_pf_heading() {
    local refs
    refs="$(GITHUB_BASE_REF=dev _pr_merge_refs "$1")"
    _prefold_heading "$1" CHANGELOG.md "${refs%% *}" "${refs##* }" "$1/CHANGELOG.md" || true
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

PF_FOLD_LINE='your entry landed under `[0.24.0]` after the fold — move it back to `[Unreleased]`.'
PF_GENERIC='add a line-initial `- **card#NNNN**` bullet under `## [Unreleased]` in docs/CHANGELOG.md.'
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
eq "the three legs establish the fold and name the heading" "0.24.0" "$(_pf_heading "$PFF")"
# ONE call, three assertions off the captured text: the leading line, the absence of the generic
# arm, and the instruction the card exists to deliver. `${x%%$'\n'*}` rather than `| head -1` —
# nothing in this file reaches for a pipeline it does not need.
PF_OUT="$(_pf_remedy "$PFF")"
eq "so the remedy names the MOVE, not a second entry" "$PF_FOLD_LINE" "${PF_OUT%%$'\n'*}"
eq "and it says so out loud (witness: the generic text is NOT what printed)" "false" \
   "$(has_line "$PF_GENERIC" "$PF_OUT")"
# The instruction this whole card exists to deliver, asserted as a LINE rather than left to the
# first line's summary: the remedy an author acted on before this change was "your entry is
# missing", and the file that came back had two.
eq "the remedy tells the author NOT to file a second entry" "true" \
   "$(has_line 'entry — move the one you already have.' "$PF_OUT")"

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
eq "but 0.24.0 already stood at the merge-base, so no fold is established" "" "$(_pf_heading "$PFS")"
eq "and the remedy is the generic one" "$PF_GENERIC" "$(_pf_remedy "$PFS")"

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
eq "so no fold is established" "" "$(_pf_heading "$PFC")"
eq "and the remedy is the generic one" "$PF_GENERIC" "$(_pf_remedy "$PFC")"

echo "== THE DISCLOSED RESIDUAL: a pre-fold branch that already MERGED the fold drops to generic =="
# Same defect as the first fixture — the entry really is stranded under [0.24.0] and really was
# put there by the fold — but this branch has since merged the folded base, which makes that base
# its own merge-base, so leg 3 cannot see that the heading arrived late. Spelling leg 3 at the
# merge-base buys this residual; it errs toward saying nothing, which is the safe direction, and
# it is pinned here so a future author meets the trade instead of rediscovering it as a bug.
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
eq "so the diagnosis is not established, and the generic remedy prints" "$PF_GENERIC" \
   "$(_pf_remedy "$PFR")"

echo "== a checkout that is NOT a pull_request merge ref establishes nothing, by design =="
# The other residual, and the reason it is safe: a local run has no merge commit to read parents
# off, so it takes the generic arm — the text this gate printed before this card. Both halves of
# `_pr_merge_refs` are exercised, because either alone would let the other's shape through.
eq "on the pull_request shape the refs ARE derived (positive control)" \
   "$(g -C "$PFF" rev-parse HEAD^1) $(g -C "$PFF" rev-parse HEAD^2)" \
   "$(GITHUB_BASE_REF=dev _pr_merge_refs "$PFF")"
eq "with GITHUB_BASE_REF unset, nothing is derived from the same merge commit" "" \
   "$(_pr_merge_refs "$PFF")"
g -C "$PFF" checkout -q feat
eq "and on a non-merge checkout, nothing is derived even on a pull_request event" "" \
   "$(GITHUB_BASE_REF=dev _pr_merge_refs "$PFF")"
eq "so the remedy falls back to the generic text" "$PF_GENERIC" "$(_pf_remedy "$PFF")"
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
MISSING="$(_missing "$SUBJECTS" "$CHANGELOG" "$LAST_VERSION")"
eq "no card shipped since $LAST_TAG is missing its entry" "" "$MISSING"
if [[ -n "$MISSING" ]]; then
    # THE REMEDY, BESIDE THE RED IT BELONGS TO (card#8442). The verdict is already fixed one line
    # up; this only chooses the SENTENCE. `_pr_merge_refs` answers with nothing off any checkout
    # that is not a pull_request merge ref, and `_missing_remedy` takes the generic arm on that —
    # so a local run prints exactly what this gate printed before this card.
    PR_REFS="$(_pr_merge_refs "$ROOT")"
    while IFS= read -r REMEDY_LINE; do
        printf '  ..   %s\n' "$REMEDY_LINE" >&2
    done <<< "$(_missing_remedy "$ROOT" docs/CHANGELOG.md \
        "${PR_REFS%% *}" "${PR_REFS##* }" "$CHANGELOG")"
fi

echo "== no PR left a superseded [Unreleased] entry standing beside its replacement =="
RECORDS="$TMP/added-live"
_added_bullets "$ROOT" docs/CHANGELOG.md "$LAST_TAG..HEAD" "$LAST_VERSION" > "$RECORDS"
# ⚠ THE LABELS ARE NARROWER THAN THEY LOOK, AND SAY SO (card#7303). Removals are region-scoped
# in `_added_bullets`, so the second figure counts removals FROM THE REGION, not from the file;
# and the third counts PRs that left a surviving RECORD, so a PR whose only contribution to this
# file was an out-of-region removal is not among them. A counter whose label is wider than its
# predicate is the defect this card exists to fix — this one is cited as evidence, so it gets the
# same rule.
printf '  ..   %s bullet(s) added · %s removed from the region · %s PR(s) with a record, since %s\n' \
    "$(cut -f2 "$RECORDS" | grep -c '^+' || true)" \
    "$(cut -f2 "$RECORDS" | grep -c '^-' || true)" \
    "$(cut -f1 "$RECORDS" | LC_ALL=C sort -u | grep -c . || true)" "$LAST_TAG"
eq "no card carries two surviving bullets from one PR" "" \
   "$(_stale_dupes "$RECORDS" "$CHANGELOG" "$LAST_VERSION")"

_summary "changelog-card-entry-selftest"
