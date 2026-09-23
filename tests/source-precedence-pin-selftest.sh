#!/usr/bin/env bash
# source-precedence-pin-selftest.sh — the mechanical pin under one rule this repo restates in
# prose and nothing held equal to the code: **a card's by-ref `source` comes from
# `payload.repo` when that is a string containing `/`, and from a URL field only otherwise.**
#
# THE DEFECT CLASS (card#9957). The rule has ONE implementation on each side of the wire —
# `derive_source` in `bin/promote-released-cards`, and the board's own `sourceFor()` — and both
# return from the `payload.repo` branch with NO fall-through. Prose copies that state the URL
# half WITHOUT the condition tell an operator that clearing or re-pointing a URL moves (or
# cannot move) the card's source, which is false on every card carrying a `payload.repo`. The
# cost is not cosmetic: the reader either avoids a safe clear or performs an unsafe one.
#
# ⛔ WHY A PHRASE GREP IS NOT THE INSTRUMENT, and this is the card's central finding rather than
# a design preference. FOUR sweeps ran under card#9918, each with a different instrument, and
# each missed sites the next one found: a phrase grep on one wording; a wider phrase grep (which
# missed `bin/kbcard`s rendered help and the whole `tests/` tree); a derived population over
# meaning-bearing predicates, every hit read and disposed (which missed a claim that SPANS A
# LINE BREAK, because the predicate was line-scoped); and the published grep written to replace
# an enumeration, which itself under-reported while standing in the canonical record AS the
# population. Each copy phrases the rule differently — *"falling back to"*, *"detaching the card
# from its repo"*, *"they set its by-ref source"*, *"from pr_url / issue_url / payload.repo"* —
# so no instrument keyed on WORDING can close it.
#
# ⛔ SO THIS KEYS ON THE CLAIM, NOT ITS WORDING, and the two halves are the two NOUNS any such
# claim must name: a URL-bearing field, and the card's SOURCE or ATTRIBUTION. A unit naming both
# is making a claim about what sets a card's source, whatever verb it reaches for. That is a
# PROXY and it is bounded — see WHAT THIS CANNOT SEE — but it is a bound on the nouns rather
# than on the phrasing, which is the half that defeated all four sweeps.
#
# ⛔ AND THE UNIT IS THE PARAGRAPH, NEVER THE LINE. Miss 3 above is the whole reason: a claim
# split over two comment lines is invisible to every line-scoped predicate, and one such claim
# (`bin/adopt-to-dl`s `_ata_issue_url` header) survived a sweep that read and disposed every
# other hit. A unit here is a maximal run of consecutive COMMENT lines (shell) or of non-blank
# lines (markdown and python, where prose is not `#`-prefixed), flattened to one string before
# either predicate runs. Control (d) below drives exactly that arm over a fixture, beside a
# line-scoped reading of the same fixture that finds nothing.
#
# THE THREE OUTCOMES for a candidate unit, and only the third costs anything to keep:
#   STATES THE CONDITION  the unit names `payload.repo`, so it is not a half-statement.
#   POINTS AT A HOME      the unit names `docs/INSTALL.md` or `derive_source`. Those two ARE the
#                         full statements (card#9918 says so, and leg 1 checks that they still
#                         are) so a pointer at either cannot drift — that is the DELETE-and-point
#                         answer, and it is the cheaper one wherever a site is not rendered help.
#   DISPOSED              the unit names both nouns and makes no claim about the precedence —
#                         a repo-slug charset argument, a by-ref VERIFY diagnostic. Hand-kept,
#                         which is the honest price of line-scope carve-outs, and leg 4 reds on
#                         a disposition that has stopped suppressing exactly one unit, so it
#                         can neither rot nor silently widen to cover a claim nobody read.
#
# ⚠ WHAT THIS CANNOT SEE, stated so a green run is not read as a closed population:
#   B1  A CLAIM NAMING NEITHER NOUN. A copy that says "clearing the URL detaches the card from
#       its repo" with no field name and no `source`/`attribut` word is invisible. The nouns are
#       the predicate, and a predicate is the one thing a derived population can be wrong about.
#   B2  WHETHER A CLEARED UNIT IS RIGHT. Naming `payload.repo`, or pointing at a home, is
#       checkable; stating the precedence CORRECTLY is English. A unit that names the condition
#       and then gets it backwards passes here.
#   B3  THE FROZEN PER-VERSION RECORDS. `docs/CHANGELOG.md` from its first version heading down,
#       and `docs/UPGRADE.md` §6, are append-only records of what was true AT a version; they are
#       carved out by `_frozen-region-lib.sh` and not read. Leg 2s premises assert the cut landed
#       where it claims, in BOTH directions, so a cut that silently shrank the live region reds.
#   B4  ANY REPO BUT THIS ONE. The board's `sourceFor()` is the other end of this rule and lives
#       in `kanban-board`; nothing here can read it. Leg 1 checks this repos own implementation
#       and says so — a declaration whose check can only reach one end is exactly what it is.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=tests/_frozen-region-lib.sh
source "$HERE/_frozen-region-lib.sh"

ROOT="$(cd "$HERE/.." && pwd)"
_need -r "$ROOT/bin/promote-released-cards"
_need -r "$ROOT/docs/INSTALL.md"
_mktmp_scratch

# ─────────────────────────── THE PREDICATES, STATED ───────────────────────────
#
# Matched case-insensitively against the flattened unit. `SPP_URL` is the URL-bearing half —
# the four payload/board fields `derive_source` reads, their `--flag` spellings, and the bare
# phrase `github url`, which is how the claim is worded where the field name is a shell
# variable (`tests/kbcard-selftest.sh` writes `$_uf`, so a field-name-only predicate misses it —
# measured, and it is two of the three instances that card#9957 carried forward by hand).
SPP_URL='pr_url|issue_url|pr-url|issue-url|html_url|external_link|github url|github[.]com'
# `SPP_SRC` is the ATTRIBUTION half, and it is deliberately NOT the bare word `source`: that
# word is also the `.promote.source` config key and the shell builtin, and including it took the
# candidate population from a readable list to one nobody would maintain — noise on this side
# buys nothing, because a claim about what sets a card's source reaches for one of these three.
SPP_SRC='by-ref|attribut|sourcefor'
# `SPP_CLEAR` — states the condition, or points at one of the two full statements.
SPP_CLEAR='payload[.]repo|install[.]md|derive_source'

# THE TWO FULL STATEMENTS. Named here because a pointer is only as good as what it points at,
# and leg 1 asserts each still carries the rule. They are the pair card#9918 declared.
SPP_HOME_DOC="docs/INSTALL.md"
SPP_HOME_CODE="bin/promote-released-cards"

# _spp_units <relpath> <file-to-read> — one line per CANDIDATE unit: `<relpath>:<start>-<end>`
# followed by a TAB and the flattened text. A unit is a maximal run of prose lines; a non-prose
# line is its own unit, so a one-line claim is still seen.
_spp_units() {
    local rel="$1" file="$2" md=0
    case "$rel" in *.md|*.py) md=1 ;; esac
    awk -v REL="$rel" -v urlre="$SPP_URL" -v srcre="$SPP_SRC" -v md="$md" '
    function flush(   t) {
        if (n == 0) { buf = ""; return }
        t = tolower(buf)
        if (t ~ urlre && t ~ srcre) printf "%s:%d-%d\t%s\n", REL, start, last, t
        buf = ""; n = 0
    }
    {
        if (md == 1) isprose = (length($0) > 0)
        else         isprose = ($0 ~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*#[[:space:]]*$/)
        # The comment marker and the indentation are stripped before the join, and runs of
        # space are collapsed, so a disposition needle is a clean quote of the prose rather than
        # a transcription of one file`s comment gutter.
        L = $0
        sub(/^[[:space:]]*#[[:space:]]?/, "", L)
        gsub(/[[:space:]]+/, " ", L)
        sub(/^ /, "", L); sub(/ $/, "", L)
        if (isprose) { if (n == 0) start = NR; last = NR; buf = (n == 0 ? L : buf " " L); n++ }
        else { flush(); buf = L; n = 1; start = NR; last = NR; flush() }
    }
    END { flush() }' "$file"
}

# _spp_scan_list <root> — `<relpath>\t<file to actually read>`, one per line. The two files
# carrying a frozen per-version record are read through their carved LIVE half; because that
# half is the HEAD of the file, its line numbers are the original ones and need no offset.
#
# The file population is DERIVED, not listed: every tracked-shaped file under `bin/`, `docs/`,
# `tests/` plus `README.md`. A new doc is scanned the day it lands, which is the property the
# hand-listed sweeps lacked.
_spp_scan_list() {
    local root="$1" f rel
    while IFS= read -r f; do
        rel="${f#"$root"/}"
        case "$rel" in
            docs/CHANGELOG.md) printf '%s\t%s\n' "$rel" "$TMP/spp-changelog-live.md" ;;
            docs/UPGRADE.md)   printf '%s\t%s\n' "$rel" "$TMP/spp-upgrade-live.md" ;;
            *)                 printf '%s\t%s\n' "$rel" "$f" ;;
        esac
    done < <(find "$root/bin" "$root/docs" "$root/tests" -maxdepth 1 -type f 2>/dev/null
             [ -f "$root/README.md" ] && printf '%s\n' "$root/README.md" || true)
}

# _spp_scan <root> — run the derivation over <root> ONCE and park the candidate units in
# `$TMP/spp-cand.txt`, which every reader below consumes. Caching is not an optimisation here:
# re-deriving per disposition ran the whole tree through awk once per entry, and a check nobody
# will wait for is a check that gets disabled. Every caller re-scans explicitly, so no reader
# can silently answer about a tree that has moved.
_spp_scan() {
    local root="$1" rel file
    : > "$TMP/spp-cand.txt"
    while IFS=$'\t' read -r rel file; do
        [ -r "$file" ] || continue
        _spp_units "$rel" "$file" >> "$TMP/spp-cand.txt"
    done < <(_spp_scan_list "$root" | LC_ALL=C sort)
}

# ⛔ THE DISPOSITIONS — a candidate unit that names both nouns and makes NO claim about what
# sets a card's source. Each is `<relpath>::<substring of the flattened, lowercased unit>`, and
# NEVER a line number: a number rots on the next edit above it and would red for the wrong
# reason. Leg 3 asserts every entry still matches a candidate, so an entry that has stopped
# suppressing anything reds instead of rotting — which is the whole difference between this list
# and the hand-kept lists card#9957 is about.
SPP_DISPOSED=(
    # The `<owner>/<name>` SLUG predicate: these argue about which spellings are a repo, on both
    # sides of the adoption comparison, and name a URL field and an attribution noun on the way
    # past without saying anything about which of them wins.
    "bin/_kb-board-lib.sh::the placeholder \`pr_url\` a card is stamped with"
    "bin/adopt-to-dl::the placeholder \`pr_url\` this tool stamps"
    "bin/adopt-to-dl::are both git-remote spellings of a repo"
    "bin/adopt-to-dl::so a spelling that is not a real repo correlates to nothing"
    "bin/promote-released-cards::it becomes the \`<owner>/<repo>\` of the pr_url"
    "tests/kb-board-lib-selftest.sh::interpolates it into the placeholder \`pr_url\` the card is stamped with"
    # The by-ref VERIFY diagnostics: they report that a verify did not return the card and name a
    # cause ("the source did not resolve") without claiming what sets it.
    "bin/adopt-to-dl::verify failed — by-ref(system=dl"
    "bin/adopt-to-dl::issue verify failed — by-ref(system=github_issue"
    # The adoption usage block: describes the co-stamped issue_url as source-qualified, which is a
    # statement about the URL this tool WRITES, not about precedence.
    "bin/adopt-to-dl::a source-qualified issue_url in the same atomic write"
    # The UNSOURCED-card branch: it prescribes stamping a URL for a card with NO derivable source,
    # which is the branch a card carrying the outranking key is never in.
    "bin/promote-released-cards::a card with no derivable by-ref source cannot be attributed under a qualified run"
    # The server-side `is_string` guard on a url field — about the SHAPE of a url value.
    "tests/promote-source-qualify-selftest.sh::a non-string url field derives nothing"
    # THIS FILE'S OWN FIXTURES. Two controls below are claim-shaped ON PURPOSE — they are what
    # proves the derivation discriminates — and a guard exempting itself WHOLESALE is how the next
    # real claim written here would go unread. Each is pinned to its own sentence instead, so
    # editing a control reds leg 4 rather than silently widening the carve-out.
    #
    # ⚠ Every needle above deliberately stops SHORT of naming both nouns. An entry that named
    # both would itself be a candidate unit of this file, and a disposition that disposes its own
    # entry reads as live while suppressing nothing real — measured, at a count of two.
    "tests/source-precedence-pin-selftest.sh::is what attributes the card to a repository."
    "tests/source-precedence-pin-selftest.sh::this tool stamps is what the board reads to"
)

# _spp_undisposed — every candidate unit that neither clears nor is fully disposed.
#
# ⛔ A DISPOSITION MUST COVER THE CLAIM, NOT MERELY OCCUR IN THE SAME PARAGRAPH, and that rule
# exists because the cheaper one was measured to fail. A unit here is a whole paragraph, so a
# needle matching anywhere in it suppressed the paragraph WHOLESALE: appending one new sentence
# that named a URL field and an attribution noun, to a paragraph some entry already disposed,
# left this file rc 0, all green. That is a hand list that cannot red on
# a new member, i.e. the exact defect card#9957 is about, rebuilt inside its own fix.
#
# So every matching needle is REMOVED from the unit and the REMAINDER is re-tested: a unit is
# disposed only once what is left of it no longer names both nouns. Several entries may cover
# one paragraph between them, which is why every match is stripped rather than the first.
_spp_is_claim() {
    local t; t="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
    [[ "$t" =~ $SPP_URL && "$t" =~ $SPP_SRC ]]
}

# _spp_witnesses <text> — the SENTENCES of <text> that name both nouns; the whole text when no
# single sentence does. A witness is one occurrence of the claim, and it is what a disposition
# has to cover. The whole-text fallback is deliberate and is the looser arm: where the nouns sit
# in different sentences there is nothing narrower to point at, and reporting the unit is better
# than reporting nothing. The delimiter is a period followed by a space and nothing cleverer —
# an abbreviation splits one sentence in two, which makes witnesses SMALLER and can only make a
# disposition harder to satisfy.
_spp_witnesses() {
    local text="$1" part any=0
    while [[ "$text" == *". "* ]]; do
        part="${text%%". "*}"; text="${text#*". "}"
        if _spp_is_claim "$part"; then printf '%s\n' "$part"; any=1; fi
    done
    if _spp_is_claim "$text"; then printf '%s\n' "$text"; any=1; fi
    [[ "$any" == 1 ]] || printf '%s\n' "$1"
}

_spp_undisposed() {
    local addr text rel w d drel dneedle covered all=1
    while IFS=$'\t' read -r addr text; do
        [[ "$text" =~ $SPP_CLEAR ]] && continue
        rel="${addr%%:*}"
        all=1
        while IFS= read -r w; do
            covered=0
            for d in "${SPP_DISPOSED[@]}"; do
                drel="${d%%::*}"; dneedle="${d#*::}"
                [[ "$drel" == "$rel" ]] || continue
                [[ "$w" == *"$dneedle"* ]] || continue
                covered=1; break
            done
            [[ "$covered" == 1 ]] || all=0
        done < <(_spp_witnesses "$text")
        [[ "$all" == 1 ]] || printf '%s\n' "$addr"
    done < "$TMP/spp-cand.txt"
    return 0
}

# _spp_disposition_matches <entry> — how many UNCLEARED candidate units one disposition
# suppresses. Cleared units are excluded because a disposition does not exist for them: a unit
# naming `payload.repo` needs no carve-out, so counting it would let a needle that suppresses
# nothing real read as live.
_spp_disposition_matches() {
    local drel="${1%%::*}" dneedle="${1#*::}" addr text n=0
    while IFS=$'\t' read -r addr text; do
        [[ "${addr%%:*}" == "$drel" ]] || continue
        [[ "$text" =~ $SPP_CLEAR ]] && continue
        [[ "$(has "$dneedle" "$text")" == true ]] || continue
        n=$((n + 1))
    done < "$TMP/spp-cand.txt"
    printf '%d\n' "$n"
}

# ---------------------------------------------------------------------------
echo "== leg 1 — the two homes a pointer points at still STATE the rule =="
# ⛔ THIS IS THE DECLARE-AND-CHECK HALF, and without it the rest is decoration: every cleared
# unit above clears by naming `docs/INSTALL.md` or `derive_source`, so if either stopped stating
# the precedence this file would certify a tree full of pointers at nothing.
INSTALL_TXT="$(cat "$ROOT/$SPP_HOME_DOC")"
eq "$SPP_HOME_DOC states the payload.repo branch"        "true" "$(has 'payload.repo' "$INSTALL_TXT")"
eq "…and its CONDITION (a string containing a slash)"    "true" "$(has 'when it is a string containing' "$INSTALL_TXT")"
eq "…and the URL fallback it precedes"                   "true" "$(has 'else the first of' "$INSTALL_TXT")"

# The CODE half. `derive_source` is jq inside a shell heredoc, so it is read as text — but the
# property asserted is structural, not a wording: the `payload.repo` arm must come FIRST and must
# RETURN, i.e. the `else` of that test is where every URL is read. A `derive_source` that fell
# through to the URL list would make every pointer at it a pointer at a different rule.
DS_SRC="$(awk '/^  def derive_source:/ { f = 1 } f { print } f && /^      end;/ { exit }' "$ROOT/$SPP_HOME_CODE")"
eq "premise: derive_source was extracted from $SPP_HOME_CODE" "true" \
   "$([ -n "$DS_SRC" ] && echo true || echo false)"
DS_COND='if (($p.repo | type) == "string") and ($p.repo | test("/"))'
eq "derive_source tests payload.repo for a string containing a slash" "true" \
   "$(has "$DS_COND" "$DS_SRC")"
eq "…and the URL fields are read in its ELSE arm, not beside it"      "true" \
   "$(has 'else ( [ $p.pr_url, $p.issue_url, $p.html_url, $c.external_link ]' "$DS_SRC")"
# The control for that pair: the same extraction with the slash test dropped must FAIL the
# first assertion, or that assertion is reading something no edit could remove.
eq "control: a derive_source without the slash condition is NOT accepted" "false" \
   "$(has "$DS_COND" "${DS_SRC//and (\$p.repo | test(\"\/\"))/}")"

# ---------------------------------------------------------------------------
echo "== leg 2 — the frozen per-version records are carved out, and the cut is witnessed =="
# Both directions, because a premise asserting only what the LIVE region LACKS can catch a cut
# that is too WIDE and never one that silently SHRANK (the regression `_frozen-region-lib.sh`
# records). Each cut is located by its heading TEXT, so neither a line number nor a section
# NUMBER is a fact this file keeps.
CHANGELOG="$ROOT/docs/CHANGELOG.md"
CHANGELOG_CUT='^## \[[0-9]'
_carve "$CHANGELOG" "$CHANGELOG_CUT" "$TMP/spp-changelog-live.md" "$TMP/spp-changelog-frozen.md"
CHANGELOG_CUT_LINE="$(_headings "$CHANGELOG" "$CHANGELOG_CUT" | head -n 1 | cut -d: -f2-)"
eq "premise: the CHANGELOG live region is non-empty"  "true"  \
   "$([ -s "$TMP/spp-changelog-live.md" ] && echo true || echo false)"
eq "…and stops before the first version section"      "false" "$(_contains "$CHANGELOG_CUT_LINE" "$TMP/spp-changelog-live.md")"
eq "…which IS in the frozen complement"               "true"  "$(_contains "$CHANGELOG_CUT_LINE" "$TMP/spp-changelog-frozen.md")"
eq "…and [Unreleased] is INSIDE the live region"      "true"  "$(_contains '## [Unreleased]' "$TMP/spp-changelog-live.md")"

UPGRADE="$ROOT/docs/UPGRADE.md"
UPGRADE_CUT='^## [0-9]+\. Version-specific upgrade actions'
_carve "$UPGRADE" "$UPGRADE_CUT" "$TMP/spp-upgrade-live.md" "$TMP/spp-upgrade-frozen.md"
UPGRADE_CUT_LINE="$(_headings "$UPGRADE" "$UPGRADE_CUT" | head -n 1 | cut -d: -f2-)"
eq "docs/UPGRADE.md carries exactly ONE version-specific-history heading" "1" \
   "$(_headings "$UPGRADE" "$UPGRADE_CUT" | grep -c . || true)"
eq "premise: the UPGRADE.md live region is non-empty"  "true"  \
   "$([ -s "$TMP/spp-upgrade-live.md" ] && echo true || echo false)"
eq "…and stops before the version-specific record"     "false" "$(_contains "$UPGRADE_CUT_LINE" "$TMP/spp-upgrade-live.md")"
eq "…which IS in the frozen complement"                "true"  "$(_contains "$UPGRADE_CUT_LINE" "$TMP/spp-upgrade-frozen.md")"

# ---------------------------------------------------------------------------
echo "== leg 3 — every live claim about a card's source names the condition or a home =="
# THE DENOMINATOR IS PRINTED, not asserted: a figure here would be a restatement of what the
# tree holds and would red on the next paragraph added. What is asserted is that it is non-empty
# (a predicate matching nothing would pass this leg vacuously) and that nothing survives.
_spp_scan "$ROOT"
SPP_N="$(grep -c . < "$TMP/spp-cand.txt" || true)"
echo "   candidate units (a URL-bearing field AND an attribution noun in one paragraph): $SPP_N"
eq "premise: the claim predicate selects SOMETHING"   "true" "$([ "$SPP_N" -gt 0 ] && echo true || echo false)"
UNDISPOSED="$(_spp_undisposed)"
[[ -z "$UNDISPOSED" ]] \
    && ok "no undisposed claim about what sets a card's by-ref source" \
    || bad "these units claim what sets a card's by-ref source without naming payload.repo, without pointing at $SPP_HOME_DOC or derive_source, and without a disposition — state the condition, point at a home, or dispose it here:
$(printf '     %s\n' $UNDISPOSED)"

# ---------------------------------------------------------------------------
echo "== leg 4 — the REVERSE direction: no disposition suppresses nothing =="
# A disposition that has stopped matching is the failure mode of every hand-kept list this card
# is about: the text moved, the carve-out stayed, and the next claim written in that file is
# suppressed by an entry nobody re-read. This is the arm that a `declared ⇒ real` check lacks.
for _d in "${SPP_DISPOSED[@]}"; do
    eq "disposition suppresses exactly ONE unit: $_d" "1" "$(_spp_disposition_matches "$_d")"
done

# ---------------------------------------------------------------------------
echo "== controls — driven over fixture trees, both directions =="
# ⛔ EVERY CONTROL BUILDS ITS OWN ROOT, and that is the one place a fixture is right here: leg 3
# and leg 4 already run against the REAL tree, so these exist to show the derivation DISCRIMINATES
# rather than to re-measure the repo. A control that minted its own sample and then asserted only
# over that sample would prove the sample; these assert a difference between two fixtures that
# differ in exactly one clause.
_spp_fixture_root() {
    local r="$TMP/$1"
    rm -rf "$r"; mkdir -p "$r/bin" "$r/docs" "$r/tests"
    : > "$r/docs/CHANGELOG.md"; : > "$r/docs/UPGRADE.md"
    printf '%s\n' "$r"
}

# (a) AN UNDECLARED SITE, added where nothing declares it — the direction a one-way check misses.
R="$(_spp_fixture_root undeclared)"
cat > "$R/bin/newtool" <<'FIXTURE'
#!/usr/bin/env bash
# Writing pr_url is what attributes the card to a repository.
echo hi
FIXTURE
_carve "$R/docs/CHANGELOG.md" "$CHANGELOG_CUT" "$TMP/spp-changelog-live.md" "$TMP/spp-changelog-frozen.md"
_carve "$R/docs/UPGRADE.md"   "$UPGRADE_CUT"   "$TMP/spp-upgrade-live.md"   "$TMP/spp-upgrade-frozen.md"
eq "control: an UNDECLARED new site stating the URL half is REPORTED" "bin/newtool:1-2" "$(_spp_scan "$R"; _spp_undisposed)"

# (b) the same sentence WITH the condition — the clearing direction, so (a) is not passing
#     because the predicate reports everything.
cat > "$R/bin/newtool" <<'FIXTURE'
#!/usr/bin/env bash
# Writing pr_url is what attributes the card to a repository, unless a payload.repo outranks it.
echo hi
FIXTURE
eq "control: …and naming payload.repo clears it"                      ""                "$(_spp_scan "$R"; _spp_undisposed)"

# (c) a POINTER at the home clears it too — the DELETE-and-point answer, exercised.
cat > "$R/bin/newtool" <<'FIXTURE'
#!/usr/bin/env bash
# Writing pr_url is what attributes the card to a repository (docs/INSTALL.md §4 owns the rule).
echo hi
FIXTURE
eq "control: …and so does a pointer at docs/INSTALL.md"               ""                "$(_spp_scan "$R"; _spp_undisposed)"

# (d) ⛔ THE LINE-BREAK ARM — miss 3 of the four sweeps, reproduced. The two nouns sit on
#     DIFFERENT lines of one comment block, which every line-scoped predicate answers clean on.
R="$(_spp_fixture_root split)"
cat > "$R/bin/splittool" <<'FIXTURE'
#!/usr/bin/env bash
# The placeholder pr_url this tool stamps is what the board reads to
# decide which repository the card is attributed to.
echo hi
FIXTURE
_carve "$R/docs/CHANGELOG.md" "$CHANGELOG_CUT" "$TMP/spp-changelog-live.md" "$TMP/spp-changelog-frozen.md"
_carve "$R/docs/UPGRADE.md"   "$UPGRADE_CUT"   "$TMP/spp-upgrade-live.md"   "$TMP/spp-upgrade-frozen.md"
eq "control: a claim SPLIT ACROSS TWO LINES is still reported"        "bin/splittool:1-3" "$(_spp_scan "$R"; _spp_undisposed)"
# …and the line-scoped reading of the same fixture finds nothing, which is what makes the
# assertion above a measurement of the paragraph unit rather than of the fixture.
eq "control: …and the line-scoped reading of it finds NOTHING"        "0" \
   "$(command grep -icE "($SPP_URL).*($SPP_SRC)|($SPP_SRC).*($SPP_URL)" "$R/bin/splittool" || true)"

# (e) a markdown paragraph, where the unit is a non-blank run rather than a comment block.
R="$(_spp_fixture_root md)"
cat > "$R/docs/NOTE.md" <<'FIXTURE'
# Notes

Clearing the issue_url is how you stop the board
attributing the card to that repo.
FIXTURE
_carve "$R/docs/CHANGELOG.md" "$CHANGELOG_CUT" "$TMP/spp-changelog-live.md" "$TMP/spp-changelog-frozen.md"
_carve "$R/docs/UPGRADE.md"   "$UPGRADE_CUT"   "$TMP/spp-upgrade-live.md"   "$TMP/spp-upgrade-frozen.md"
eq "control: a markdown paragraph making the claim is reported"       "docs/NOTE.md:3-4"  "$(_spp_scan "$R"; _spp_undisposed)"

# (f) the DISPOSITION direction: an entry naming a needle no unit carries must be reported as
#     suppressing nothing — leg 4's own control, over the real tree.
eq "control: a disposition matching nothing counts ZERO" "0" \
   "$(_spp_disposition_matches "bin/adopt-to-dl::no unit has ever said this")"

_summary source-precedence-pin-selftest
