#!/usr/bin/env bash
# by-ref-source-claim-selftest.sh — nothing in this tree may say what decides a card's by-ref
# `source` and disagree with the one thing that decides it.
#
# THE RULE, which this file does not state a copy of: `derive_source` in
# `bin/promote-released-cards` returns from the `payload.repo` branch when that key is a string
# containing `/`, with NO fall-through, and only otherwise reads the URL fields. The board's own
# `sourceFor()` does the same. The full statements live at the surfaces whose
# `by-ref-source-rule` marker reads HOME, and leg 2 holds every one of them against that def.
#
# WHY THIS FILE EXISTS (card#9957). The rule was restated across the tree and several copies said
# only the URL half, so an operator reading one concludes that clearing or re-pointing `pr_url`
# moves (or cannot move) a card's source, and acts on the wrong direction. FOUR sweeps ran under
# card#9918 to find those copies and all four under-reported:
#
#   1. a phrase grep on `falling back to payload.repo`  — missed everything worded differently;
#   2. a wider phrase grep                              — missed `bin/kbcard`'s rendered help and
#                                                         the whole `tests/` tree;
#   3. a derived population over meaning-bearing predicates, every hit read and disposed — missed
#      `bin/adopt-to-dl`'s `_ata_issue_url` header, because the claim SPANS A LINE BREAK and the
#      predicate was line-scoped;
#   4. the grep published in `docs/CHANGELOG.md` to replace an enumeration — itself under-reported,
#      and it had been written into the canonical record AS IF IT WERE THE POPULATION.
#
# ⛔ SO A PHRASE GREP IS NOT THE INSTRUMENT, AND NEITHER IS A LINE. Both bounds are designed
# against, and both are exercised by a control at the bottom of this file:
#
#   * THE UNIT IS A PASSAGE, NEVER A LINE. `_bsc_passages` joins each maximal run of same-kind
#     non-blank lines into one record, so a claim split over three comment lines is one string.
#     It breaks at a new ITEM — a list bullet, an ordered item, a table row, a heading, a fence —
#     because two adjacent bullets are two claims, and merging them manufactures a co-occurrence
#     neither one makes. Blockquote `>` markers are stripped, not broken on: `docs/INSTALL.md`
#     writes whole paragraphs inside one.
#
#   * THE TRIGGER KEYS ON THE CLAIM'S NOUNS, NEVER ON ITS VERB — which is what lets it see a copy
#     worded in a way nobody has used yet. Any statement of this rule relates a URL — or a
#     `link`, since naming the thing is not the same as naming the field — to which repo
#     a CARD is attributed to; there is no smaller invariant, and none of the four wordings that
#     defeated the sweeps above ("falling back to", "detaching the card from its repo", "they set
#     its by-ref source", "from pr_url / issue_url / payload.repo") avoids all three nouns.
#     ⚑ `source` ALONE IS DELIBERATELY NOT IN THE TRIGGER, and that is the lexical half of why the
#     greps failed: this tree spends the word on four unrelated things — the shell builtin, the
#     `.promote.source` config key, `source of truth`, and this field. The trigger takes the two
#     spellings that are unambiguous here, `attribut*` and `by-ref` beside `source`.
#
#   * THE DISCHARGE IS THE CONDITION ITSELF. A passage that names `payload.repo` has stated the
#     thing whose omission is the defect; a passage that does not has made the URL case sound
#     universal. That is one rule with no allow-list of blessed phrasings — and it is also the
#     shape every pointer in this tree already adopted, `bin/kbcard`'s five being the model
#     ("unless the card's `payload.repo` outranks it (`_kbc_ref_pair_guard`'s header owns that
#     rule)"), so pointing and discharging are the same act.
#
# ⚑ BOUND, STATED SO IT IS NOT OVER-CITED: this covers the OMISSION class — a copy that states the
# URL case without the condition — which is every miss the four sweeps produced. It does NOT cover
# CONTRADICTION: a passage that names `payload.repo` and then says something false about it
# discharges here. Leg 2 is what closes that for the declared full statements, by holding their
# field ORDER against the executable def; a non-home passage carrying the condition is not held to
# anything, and the cheaper answer for one of those is to make it a pointer.
#
# ⛔ IT ASSERTS NOTHING ABOUT BEHAVIOUR, ON PURPOSE. `tests/promote-source-qualify-selftest.sh` § 5
# already drives the shipped `derive_source` over a corpus — `payload.repo` winning outright,
# winning when it DISQUALIFIES the card, a slashless value deriving nothing, and the URL order
# after it. A second corpus here would be a second answer to one question (canon #5). What was
# missing is the join between that corpus and the prose, which is leg 2.
#
# THE THREE LEGS:
#   1. THE EXECUTABLE ANSWER — the field order is EXTRACTED from the shipped `derive_source` on
#      every run, never written here, and the extractor is shown to discriminate.
#   2. EVERY DECLARED HOME AGREES WITH IT, BOTH DIRECTIONS — every HOME-marked
#      passage states the same five fields in the same order as the def, AND every passage
#      anywhere in the tree that states all five in that order carries the marker. One direction
#      alone is a declaration nothing checks; the other alone lets a home be deleted in silence.
#   3. NO PRECEDENCE CLAIM ANYWHERE IN THE TREE OMITS THE CONDITION — the whole repo, fail-closed,
#      minus the two carve-outs named at the leg.

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
PRC="$ROOT/bin/promote-released-cards"
_need -r "$PRC" "bin/promote-released-cards"
_mktmp_scratch

# THE MARKER IS COMPOSED, not typed, so that THIS file never holds the literal string it greps the
# tree for and cannot report its own prose as a declared home.
#
# ⚑ AND THAT CUTS BOTH WAYS FOR EVERY OTHER SURFACE: the marker is a DECLARATION, so a doc that
# QUOTES it verbatim has declared itself a home and is then held to the field order. Measured on
# this very change — the `docs/CHANGELOG.md` entry describing this guard quoted the literal and
# reported as a home stating no fields at all. Write the marker's KEY and its VALUE separately
# when describing the mechanism; spell it whole only where you mean it.
MARKER_KEY='by-ref-source-rule'
MARKER="$MARKER_KEY: ""HOME"

# ---------------------------------------------------------------------------
# _bsc_passages <file> <relpath> — one record per PASSAGE: `<relpath>\t<startline>\t<text>`.
# The unit is argued in this file's header; this is its one implementation, and both the tree
# scan and every fixture go through it, so a control cannot be measuring a different unit.
_bsc_passages() {
    awk -v REL="$2" '
    function flush() { if (buf != "") printf "%s\t%d\t%s\n", REL, start, buf; buf = ""; start = 0 }
    {
        line = $0
        if (match(line, /^[ \t]*(#+|\/\/+|\*)[ \t]?/)) { mode = "c"; body = substr(line, RSTART + RLENGTH) }
        else                                          { mode = "p"; body = line }
        sub(/^[ \t]*(>[ \t]*)+/, "", body)
        gsub(/^[ \t]+|[ \t]+$/, "", body)
        # A TABLE ROW IS ANCHORED AT BOTH ENDS. A bare leading-pipe test also fires on a jq
        # pipeline continuation line, which SPLIT the shipped derive_source into fragments and
        # hid the def from the leg that exempts it. No apostrophes here: awk program, single quotes.
        isitem = (body ~ /^([-*+][ \t]|[0-9]+[.)][ \t]|```|~~~)/ || body ~ /^\|.*\|[ \t]*$/)
        if (body == "" || mode != prevmode || isitem) flush()
        prevmode = mode
        if (body == "") next
        if (buf == "") { start = FNR; buf = body } else { buf = buf " " body }
    }
    END { flush() }' "$1"
}

# BSC_ORDER_PROG — THE ONE OWNER of "what field order does this text state", as an awk function so
# that the two callers below (one text on stdin; one pass over thousands of passage records) share
# a single implementation instead of two spellings that can drift. It is asked of the shipped jq
# and of every prose statement alike, so neither is compared against a differently-derived reading
# of the other.
#
# Each name is matched through the prefixes its two worlds spell it with — `payload.` / `$p.` /
# `$c.` / bare — and `repo` ONLY with a prefix, because bare `repo` is a common English noun in
# these very sentences ("the repo this release ships"). The leading boundary excludes `_`, so
# `_ata_pr_url` (a function NAME) is not read as the field.
#
# ⚑ ONE PASS, NOT ONE PROCESS PER RECORD. The first cut called a shell function per passage and
# spawned ~18,000 awks over this tree; the leg did not finish. A guard nobody can afford to run is
# not a guard, so the record loop lives inside awk.
BSC_ORDER_PROG='
function bsc_order(buf,   nm, re, pos, n, i, best, bp, res) {
    n = split("repo pr_url issue_url html_url external_link", nm, " ")
    re["repo"]          = "(payload|[$]p)[.]repo([^A-Za-z0-9_]|$)"
    re["pr_url"]        = "(^|[^A-Za-z0-9_-])(payload[.]|[$]p[.])?pr_url"
    re["issue_url"]     = "(^|[^A-Za-z0-9_-])(payload[.]|[$]p[.])?issue_url"
    re["html_url"]      = "(^|[^A-Za-z0-9_-])(payload[.]|[$]p[.])?html_url"
    re["external_link"] = "(^|[^A-Za-z0-9_-])([$]c[.])?external_link"
    for (i = 1; i <= n; i++) pos[nm[i]] = (match(buf, re[nm[i]]) ? RSTART : 0)
    res = ""
    for (;;) {
        best = ""; bp = 0
        for (i = 1; i <= n; i++)
            if (pos[nm[i]] > 0 && (bp == 0 || pos[nm[i]] < bp)) { bp = pos[nm[i]]; best = nm[i] }
        if (best == "") break
        res = res (res == "" ? "" : " ") best
        pos[best] = 0
    }
    return res
}'

# _bsc_field_order — the order stated by whatever text arrives on stdin.
_bsc_field_order() {
    awk "$BSC_ORDER_PROG"'
    { buf = buf $0 " " }
    END { if (bsc_order(buf) != "") print bsc_order(buf) }'
}

# ---------------------------------------------------------------------------
echo "== leg 1 — the executable answer, extracted rather than written down =="
# `derive_source` IS the answer this repo ships; every surface below is compared against it and
# nothing is compared against a constant in this file. The extraction is by SHAPE (the def's own
# name, to its terminating `end;`), so no line number is a fact kept here.
# Anchored at BOTH ends. `/def derive_source:/` unanchored would also open the range on a COMMENT
# naming the def, and a range whose terminator never matched would run to EOF and hand leg 2 the
# whole file as if it were the def — which reads repo-first and would pass.
DS_SRC="$(sed -n '/^ *def derive_source:$/,/^ *end;$/p' "$PRC")"
eq "the shipped derive_source def is extractable" "true" \
   "$([ -n "$DS_SRC" ] && echo true || echo false)"
eq "…and the extraction TERMINATED at the def's own end, not at EOF" "true" \
   "$([[ "${DS_SRC##*$'\n'}" =~ ^[[:space:]]*end\;$ ]] && echo true || echo false)"
CODE_ORDER="$(printf '%s\n' "$DS_SRC" | _bsc_field_order)"
echo "     (derived from bin/promote-released-cards: $CODE_ORDER)"
# THE PREMISE THAT KEEPS LEG 2 FROM PASSING VACUOUSLY. An extractor that had stopped matching
# would make every home "agree" with an empty string. The `5` is a deliberate PIN on the def, not a
# figure copied from a document: a key added to or dropped from `derive_source` reds HERE, where
# somebody has to look at every declared statement, rather than silently shrinking what leg 2
# compares. It is the one number in this file, and it is about the code beside it.
eq "…and it names all five derivation fields" "5" \
   "$(printf '%s' "$CODE_ORDER" | wc -w | tr -d ' ')"
eq "…with the repo key FIRST (the no-fall-through branch)" "repo" "${CODE_ORDER%% *}"
# The condition itself is in the def, not only in its ordering: a string test and a `/` test.
eq "…and the def gates that branch on a STRING containing /" "true|true" \
   "$(has '"string"' "$DS_SRC")|$(has 'test("/")' "$DS_SRC")"

# CONTROL — the extractor DISCRIMINATES. A def with two fields transposed must produce a different
# order, or leg 2 is comparing two constants. Both directions: a mutant reads differently, and the
# unmutated text still reads as itself.
DS_SWAP="$(printf '%s\n' "$DS_SRC" | sed 's/\$p\.pr_url, \$p\.issue_url/$p.issue_url, $p.pr_url/')"
eq "control: the mutation actually changed the def" "false" \
   "$([ "$DS_SWAP" = "$DS_SRC" ] && echo true || echo false)"
eq "control: …and the extractor reports the swapped order" "repo issue_url pr_url html_url external_link" \
   "$(printf '%s\n' "$DS_SWAP" | _bsc_field_order)"
eq "control: a text naming ONE field reports only that one" "pr_url" \
   "$(printf 'the card carries a payload.pr_url\n' | _bsc_field_order)"
eq "control: a text naming none reports nothing"            "" \
   "$(printf 'nothing about any of this\n' | _bsc_field_order)"
eq "control: a bare English 'repo' is NOT the payload key"  "" \
   "$(printf 'the repo this release ships\n' | _bsc_field_order)"
eq "control: a function NAME ending in pr_url is not the field" "" \
   "$(printf 'call _ata_pr_url with the slug\n' | _bsc_field_order)"

# ---------------------------------------------------------------------------
# THE CORPUS, built ONCE and read by both legs below — every passage of every text file under
# <root>, with the two carve-outs applied. They are argued at leg 3, which is the leg they were
# minted for; leg 2 shares them for the same reason (a released entry's at-that-version copy is
# not a live restatement, and rewriting one rewrites the record).
#
# The two history files are read through their LIVE heads, and ONLY under the real $ROOT, so a
# fixture tree that happened to carry either path is read as itself rather than silently answered
# from the repo's own live head.
CHANGELOG="$ROOT/docs/CHANGELOG.md"
UPGRADE="$ROOT/docs/UPGRADE.md"
# Matched by SHAPE, so no version number is a fact this file keeps.
CHANGELOG_CUT='^## \[[0-9]'
UPGRADE_CUT='^### v[0-9]'
_carve "$CHANGELOG" "$CHANGELOG_CUT" "$TMP/changelog-live.md" "$TMP/changelog-frozen.md"
_carve "$UPGRADE"   "$UPGRADE_CUT"   "$TMP/upgrade-live.md"   "$TMP/upgrade-frozen.md"
for pair in "docs/CHANGELOG.md|$CHANGELOG|$CHANGELOG_CUT|changelog" "docs/UPGRADE.md|$UPGRADE|$UPGRADE_CUT|upgrade"; do
    IFS='|' read -r cname cfile cpat ckey <<<"$pair"
    cutline="$(_headings "$cfile" "$cpat" | head -n 1 | cut -d: -f2-)"
    eq "$cname carries a versioned heading to split at" "true" \
       "$([ "$(_headings "$cfile" "$cpat" | grep -c . || true)" -ge 1 ] && echo true || echo false)"
    eq "premise: the $ckey LIVE head is non-empty"      "true" \
       "$([ -s "$TMP/$ckey-live.md" ] && echo true || echo false)"
    eq "…and stops before the first frozen entry"       "false" "$(_contains "$cutline" "$TMP/$ckey-live.md")"
    eq "…which IS in the frozen complement"             "true"  "$(_contains "$cutline" "$TMP/$ckey-frozen.md")"
done

BSC_HISTORY=("CLAUDE.md")

_bsc_corpus() { # <root> — every passage under <root>, carves applied
    local root="$1" f rel src
    while IFS= read -r f; do
        rel="${f#"$root"/}"
        case " ${BSC_HISTORY[*]} " in *" $rel "*) continue ;; esac
        src="$f"
        if [[ "$root" == "$ROOT" ]]; then
            case "$rel" in
                docs/UPGRADE.md)   src="$TMP/upgrade-live.md" ;;
                docs/CHANGELOG.md) src="$TMP/changelog-live.md" ;;
            esac
        fi
        _bsc_passages "$src" "$rel"
    done < <(grep -rIl '' "$root" --exclude-dir=.git 2>/dev/null | LC_ALL=C sort)
}
ALL="$(_bsc_corpus "$ROOT")"
eq "premise: the corpus reached files and produced passages" "true" \
   "$([ -n "$ALL" ] && echo true || echo false)"

echo "== leg 2 — every declared HOME states the rule, and every full statement is a HOME =="
# THE HOME SET IS DERIVED FROM THE MARKERS, never listed here: mark a fifth surface and it is held
# to the def on the next run with no edit to this file. The ones that exist as this lands are
# several for a reason the tree already rules on for `KB_JQ_REPO_FROM_GH_URL` — `bin/kbcard` and
# `bin/promote-released-cards` are each vendored STANDALONE, beside neither `docs/` nor each other,
# so neither can point at a home it cannot read, and one of them RENDERS its copy to an operator
# who cannot follow a pointer at all. What was missing was never fewer copies; it was anything
# holding them level. This leg is that.
#
# ⚑ WHAT A HOME IS HELD TO IS THE FIELD ORDER, AND ONLY THAT. No leg here reads a home for a
# PHRASE. The order is wording-independent and is exactly what a reordering of the def would
# falsify; a phrase test would be the fifth phrase grep in a card whose whole finding is that
# phrase greps do not close this population. That the condition is PRESENT at all is leg 3's
# question, asked of every passage including these; that it is TRUE is pinned behaviourally by
# tests/promote-source-qualify-selftest.sh § 5.
HOMES="$(printf '%s\n' "$ALL" | grep -F "$MARKER" || true)"
eq "premise: at least one surface DECLARES itself a home" "true" \
   "$([ -n "$HOMES" ] && echo true || echo false)"
while IFS=$'\t' read -r hrel hline htext; do
    [[ -n "$hrel" ]] || continue
    eq "home states the def's own field order: $hrel:$hline" "$CODE_ORDER" \
       "$(printf '%s\n' "$htext" | _bsc_field_order)"
done <<<"$HOMES"

# THE REVERSE DIRECTION, which is what stops a home being deleted in silence: any passage ANYWHERE
# that states all five fields in the def's order IS a statement of this rule, and an unmarked one
# is an unpinned copy — exactly what this card exists to end. A declaration checked in one
# direction only is a declaration nothing can falsify.
#
# THE DEF ITSELF IS NOT A RESTATEMENT OF ITSELF and is excluded by identity (it carries
# `def derive_source:`), not by path: it is the reference every other surface is compared against.
_bsc_full_statements() { # <passages> — records whose field order equals the def's
    awk -F'\t' -v want="$CODE_ORDER" "$BSC_ORDER_PROG"'
    NF >= 3 && $3 !~ /def derive_source:/ && bsc_order($3) == want' <<<"$1"
}
FULL="$(_bsc_full_statements "$ALL")"
eq "premise: the tree carries at least one full statement to hold" "true" \
   "$([ -n "$FULL" ] && echo true || echo false)"
UNMARKED="$(printf '%s\n' "$FULL" | grep -vF "$MARKER" | awk -F'\t' 'NF{printf "%s:%s\n", $1, $2}' || true)"
eq "no UNMARKED full statement of the rule anywhere in the tree" "" "$UNMARKED"

# ---------------------------------------------------------------------------
echo "== leg 3 — no precedence claim in the tree omits the payload.repo condition =="
# THE POPULATION IS THE WHOLE REPO and is re-derived on every run. It is a PROHIBITION, so it is
# fail-CLOSED: a file nobody thought about is IN and reports; only a named, reasoned carve-out is
# out. A prohibition scoped to a path list answers about the list.
#
# TWO CARVE-OUTS:
#   (a) VERSION-SPECIFIC FROZEN HISTORY, cut at the heading where it begins. `docs/CHANGELOG.md`
#       and `docs/UPGRADE.md` are append-only records of what was true AT a version; a statement
#       there cannot rot, and editing one rewrites a released record. The LIVE head above the cut
#       stays IN — `[Unreleased]` is where the release in flight is written, and a claim landing
#       there is as live as any other. `CLAUDE.md` is carved whole: its release table is a copy of
#       CHANGELOG highlights that the release process regenerates.
#   (b) DISPOSED PASSAGES, each by `<path>::<substring>` with its reason, and each ASSERTED to
#       still suppress something. The trigger cannot tell a precedence claim from prose that
#       happens to name a URL, a card and an attribution in one breath; the residue is real and is
#       ruled on here rather than by narrowing the trigger, because every narrowing that would
#       remove one of these also removes a wording nobody has used yet.
BSC_DISPOSED=(
    # ⛔ EVERY ENTRY BELOW IS A RULING THAT THE PASSAGE MAKES NO PRECEDENCE CLAIM — never that it
    # is inconvenient. The trigger reports any passage holding all three of its nouns, and this
    # tree spends those nouns constantly for reasons that have nothing to do with which
    # key wins; narrowing the trigger until these stopped reporting would also remove the
    # wordings nobody has used yet, which is the whole point of the trigger. Each is asserted
    # LIVE below, so a disposition that has stopped matching reds instead of rotting.

    # ── the by-ref QUERY, not the derived field. `source=` here is a request parameter; these
    #    passages are about `kb_is_repo_slug`, the accept predicate for the `<owner>/<name>` that
    #    goes INTO that parameter, and rule on nothing about where a card's source comes from.
    "bin/_kb-board-lib.sh::WHY THIS IS A PRIMITIVE AND NOT A SHAPE TEST AT EACH CALLER"
    "bin/promote-released-cards::THE SHAPE \`case\` ABOVE AND THIS CHARSET CHECK ARE ONE PAIR"
    "tests/kb-board-lib-selftest.sh::A SHAPE TEST ALONE CANNOT DO THIS JOB"

    # ── WHAT A TOOL STAMPS, not what the board then reads. Both describe the write; the rule for
    #    the read is stated 20 lines below each, at `_ata_pr_url` and `_ata_issue_url`, and both
    #    of those carry the condition.
    "README.md::pull-into-build adoption seam"
    "bin/adopt-to-dl::Usage: adopt-to-dl <card-id> --repo"

    # ── ⚠ RENDERED FAILURE TEXT, REPORTED RATHER THAN FIXED (card#9957). Both messages list the
    #    causes of a failed by-ref VERIFY and neither names the one this rule creates: a card
    #    whose `payload.repo` names a repo other than `--repo` verifies against a source the
    #    stamp did not set. That is a real gap in what the operator is told — and changing what a
    #    tool tells an operator is an ask-first gate, so it is named here and on the card rather
    #    than taken unasked. The passages state no precedence either way, which is why they are
    #    disposed and not fixed in passing.
    "bin/adopt-to-dl::VERIFY FAILED — by-ref(system=dl"
    "bin/adopt-to-dl::ISSUE VERIFY FAILED — by-ref(system=github_issue"

    # ── THE NULL CASE — "this card has NO source", which is not a claim about which key supplies
    #    one. The remedy each gives (stamp a `pr_url`) is correct under its own premise: a card
    #    with a `payload.repo` that is a string containing `/` is not in the population these
    #    lines describe.
    "bin/promote-released-cards::A card with NO derivable by-ref source cannot be attributed"
    "bin/release-pr-body::matched ONLY an unsourced card"
    "docs/INSTALL.md::Shipped refs whose card carries no by-ref source"
    "tests/promote-source-qualify-selftest.sh::qualified: the foreign card is NAMED, by id"
    "tests/release-pr-body-selftest.sh::the coverage report MEASURED (qualified)"

    # ── A DIFFERENT SUBJECT that happens to share the nouns: a custom FIELD definition narrowing
    #    under cards that carry a value for it.
    "bin/kbcard::even while a card references the dropped value"

    # ── ASSERTIONS ABOUT A MESSAGE, not statements of the rule. `_c9918` asserts that a refusal
    #    states NO attribution consequence — the opposite of making one — and the prelude-shadow
    #    entry is a disposition table for another guard entirely.
    "tests/kbcard-selftest.sh::it states no consequence: no attribution"
    "tests/prelude-shadow-selftest.sh::EXTRACTORS=("

    # ── THIS FILE ITSELF: its own prose about the trigger, the trigger, and its own control
    #    fixture. The fixture MUST be reportable — that is its job — and the other two cannot
    #    describe a predicate over these nouns without using them.
    "tests/by-ref-source-claim-selftest.sh::TWO CARVE-OUTS"
    "tests/by-ref-source-claim-selftest.sh::t ~ /url|link/"
    "tests/by-ref-source-claim-selftest.sh::control: a claim SPLIT ACROSS LINES is reported"
)

# _bsc_claims <passages> — the trigger, and its one implementation. Nouns only; see the header.
_bsc_claims() {
    awk -F'\t' '
    { t = tolower($3) }
    t ~ /url|link/ && t ~ /card/ && (t ~ /attribut/ || (t ~ /by-ref/ && t ~ /source/))' <<<"$1"
}
# _bsc_undischarged <claims> — claims that do not name the condition.
_bsc_undischarged() { awk -F'\t' 'tolower($3) !~ /payload[.]repo/' <<<"$1"; }

# _bsc_scan <root> — every undischarged claim under <root>, as `<relpath>: <startline>: <text>`.
# It reads `_bsc_corpus`, so the carve-outs above apply to this leg and to leg 2 identically and
# there is one walk of the tree, not two.
_bsc_scan() {
    _bsc_undischarged "$(_bsc_claims "$(_bsc_corpus "$1")")" \
        | awk -F'\t' 'NF{printf "%s: %d: %s\n", $1, $2, $3}'
}

# _bsc_disposes <dpath> <dsub> <line> — THE disposition predicate, one owner, asked by both
# questions below: "is this reported line disposed?" and "does this disposition suppress anything?"
_bsc_disposes() { case "$3" in "$1: "*) case "$3" in *"$2"*) return 0 ;; esac ;; esac; return 1; }

_bsc_undisposed() {
    local raw="$1" d line keep
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        keep=true
        for d in ${BSC_DISPOSED[@]+"${BSC_DISPOSED[@]}"}; do
            if _bsc_disposes "${d%%::*}" "${d#*::}" "$line"; then keep=false; fi
        done
        $keep && printf '%s\n' "$line"
    done <<<"$raw"
}

# NO PIPELINE, deliberately: a `grep -q` fed from an external writer turns a MATCH into a reported
# non-match under `pipefail` when the reader exits first. Same class, same prescription as
# tests/lib-set-derivation-selftest.sh's own liveness loop.
_bsc_disposition_live() { # <dpath> <dsub>
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if _bsc_disposes "$1" "$2" "$line"; then printf 'true\n'; return 0; fi
    done <<<"$BSC_RAW"
    printf 'false\n'
}

BSC_RAW="$(_bsc_scan "$ROOT")"
# THE DENOMINATOR, PRINTED RATHER THAN RECORDED. Every figure below is re-derived on this run and
# is a measurement, not a fact this file keeps; nothing asserts on them, and no document restates
# them. `bash tests/by-ref-source-claim-selftest.sh` IS the answer to "how many sites are there",
# which is the question the fourth sweep answered with a number and got wrong.
printf '     (population: %s passages · %s precedence claims · %s of them not naming the condition · %s disposed)\n' \
    "$(printf '%s\n' "$ALL" | grep -c . || true)" \
    "$(_bsc_claims "$ALL" | grep -c . || true)" \
    "$(printf '%s\n' "$BSC_RAW" | grep -c . || true)" \
    "${#BSC_DISPOSED[@]}"
eq "premise: the scan reached files and reported something" "true" \
   "$([ -n "$BSC_RAW" ] && echo true || echo false)"
# EVERY DISPOSITION IS STILL LIVE. One that has stopped matching is an inherited ruling about a
# line nobody can point to, and it must be re-derived rather than carried.
for d in ${BSC_DISPOSED[@]+"${BSC_DISPOSED[@]}"}; do
    dpath="${d%%::*}"; dsub="${d#*::}"
    eq "disposition suppresses a live line: $dpath — $dsub" "true" "$(_bsc_disposition_live "$dpath" "$dsub")"
done
eq "no undisposed precedence claim anywhere in the repo" "" "$(_bsc_undisposed "$BSC_RAW")"

# ---------------------------------------------------------------------------
echo "== controls — the legs above are measurements, not absences of scanning =="
# THE FIXTURE IS A MINIATURE TREE, because the property is about a POPULATION and a single-file
# probe cannot see it: a file nobody named must report, and a disposition must suppress its own
# line and nothing else.
#
# THE FIXTURE TEXT IS COMPOSED, NOT TYPED — `$AV` carries the attribution verb, so no line of THIS
# file holds a whole trigger and the fixtures are not reported by the leg they exercise.
AV='attributes'
mkdir -p "$TMP/fix/docs"

printf 'The card url is read and it %s the card to the repo it names.\n' "$AV" \
    > "$TMP/fix/docs/A-SURFACE-NOBODY-NAMED.md"

FIX_RAW="$(_bsc_scan "$TMP/fix")"
eq "control: a surface NOBODY NAMED is reported" "true" \
   "$(has 'docs/A-SURFACE-NOBODY-NAMED.md' "$FIX_RAW")"

# ⛔ THE LINE-BREAK CONTROL — miss 3's regression, and the one a line-scoped predicate cannot pass.
# NO SINGLE LINE of this fixture carries the whole trigger: the URL is on line 1, the attribution
# on line 2. A line-unit scan reports nothing here; the passage unit reports it.
cat > "$TMP/fix/docs/SPLIT-CLAIM.md" <<FIXTURE
The stamped pr_url's owner/repo segment is what the board reads, and it then
$AV the card to that repo for every release that ships its number.
FIXTURE

eq "control: a claim SPLIT ACROSS LINES is reported" "true" "$(has 'docs/SPLIT-CLAIM.md' "$(_bsc_scan "$TMP/fix")")"
eq "control: …and no single LINE of it would have matched" "" \
   "$(grep -icE 'url.*card.*attribut|attribut.*url.*card' "$TMP/fix/docs/SPLIT-CLAIM.md" | grep -v '^0$' || true)"

# …and the SAME claim carrying the condition is NOT reported, so the leg is not simply reporting
# everything that mentions a URL.
cat > "$TMP/fix/docs/DISCHARGED.md" <<FIXTURE
The stamped pr_url's owner/repo segment is what the board reads, and it then
$AV the card to that repo — unless a payload.repo outranks it.
FIXTURE

eq "control: the same claim WITH the condition is not reported" "false" \
   "$(has 'docs/DISCHARGED.md' "$(_bsc_scan "$TMP/fix")")"

# NEW WORDING: a sentence using none of the four phrasings that defeated the sweeps, and no field
# name at all, is still reported — which is the property the whole trigger design is for.
cat > "$TMP/fix/docs/NEVER-WORDED-THIS-WAY.md" <<FIXTURE
Whichever GitHub link the operator last pasted decides, once and for all, which
repository the card is $AV to; nothing else on it is consulted.
FIXTURE

eq "control: a wording nobody has used is still reported" "true" \
   "$(has 'docs/NEVER-WORDED-THIS-WAY.md' "$(_bsc_scan "$TMP/fix")")"

# THE DISPOSITION MECHANISM, on the fixture tree: it suppresses its own line and nothing else in
# the same file.
FIX2="$(_bsc_scan "$TMP/fix")"
BSC_RAW_SAVE="$BSC_RAW"; BSC_RAW="$FIX2"
BSC_DISPOSED_SAVE=("${BSC_DISPOSED[@]+"${BSC_DISPOSED[@]}"}")
BSC_DISPOSED=("docs/SPLIT-CLAIM.md::every release that ships its number")
eq "control: a disposition suppresses its own line"        "false" \
   "$(has 'docs/SPLIT-CLAIM.md' "$(_bsc_undisposed "$FIX2")")"
eq "control: …and nothing else in the tree"                "true" \
   "$(has 'docs/NEVER-WORDED-THIS-WAY.md' "$(_bsc_undisposed "$FIX2")")"
eq "control: …and a live disposition reports itself live"  "true" \
   "$(_bsc_disposition_live 'docs/SPLIT-CLAIM.md' 'every release that ships its number')"
eq "control: …while a disposition matching nothing is DEAD" "false" \
   "$(_bsc_disposition_live 'docs/SPLIT-CLAIM.md' 'a substring no line carries')"
BSC_DISPOSED=("${BSC_DISPOSED_SAVE[@]+"${BSC_DISPOSED_SAVE[@]}"}")
BSC_RAW="$BSC_RAW_SAVE"

# LEG 2'S CONTROL — an unmarked full statement reports, and a marked one does not.
PF='payload.'   # composed, so THIS file does not itself state all five in the def's order
cat > "$TMP/fix/docs/UNPINNED-COPY.md" <<FIXTURE
The source comes from ${PF}repo when it is a string containing a slash, else from
${PF}pr_url, ${PF}issue_url, ${PF}html_url and finally external_link.
FIXTURE

FIXALL="$(_bsc_corpus "$TMP/fix")"
eq "control: an UNMARKED full statement is reported" "true" \
   "$(has 'docs/UNPINNED-COPY.md' "$(_bsc_full_statements "$FIXALL" | grep -vF "$MARKER" || true)")"
printf '<!-- %s -->\n' "$MARKER" >> "$TMP/fix/docs/UNPINNED-COPY.md"
eq "control: …and marking it discharges leg 2's reverse direction" "false" \
   "$(has 'docs/UNPINNED-COPY.md' "$(_bsc_full_statements "$(_bsc_corpus "$TMP/fix")" | grep -vF "$MARKER" || true)")"
# …but a MARKED home whose order disagrees with the def is caught by the forward direction.
eq "control: a home stating the WRONG order does not equal the def" "false" \
   "$([ "$(printf 'payload.pr_url first, then payload.repo, payload.issue_url, payload.html_url, external_link\n' | _bsc_field_order)" = "$CODE_ORDER" ] && echo true || echo false)"

_summary by-ref-source-claim-selftest
