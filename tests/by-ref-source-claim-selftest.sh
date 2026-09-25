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
#     It breaks at a new ITEM — a list bullet, an ordered item, a table row, a fence — because two
#     adjacent bullets are two claims, and merging them manufactures a co-occurrence neither one
#     makes. Blockquote `>` markers are stripped, not broken on: `docs/INSTALL.md` writes whole
#     paragraphs inside one.
#     ⛔ THIS SENTENCE WAS FALSE FOR MARKDOWN FOR A ROUND, IN BOTH DIRECTIONS, AND IT IS THE
#     CLASSIFIER — not the trigger — THAT DECIDES IT. The mode test is `#` only, and the
#     blockquote strip runs BEFORE it; the reasoning for both, and what each got wrong, is at the
#     awk itself rather than restated here. The controls at the bottom drive a `*` bullet pair, a
#     `**bold**`-leading continuation, and the `-`/unbolded twins that reported all along, so this
#     paragraph is measured on every run rather than believed.
#
#   * THE TRIGGER KEYS ON THE CLAIM'S NOUNS, NEVER ON ITS VERB — which is what lets it see a copy
#     worded in a way nobody has used yet. Any statement of this rule relates a URL — or a
#     `link`, since naming the thing is not the same as naming the field — to which repo
#     a CARD is attributed to; there is no smaller invariant, and none of the four wordings that
#     defeated the sweeps above ("falling back to", "detaching the card from its repo", "they set
#     its by-ref source", "from pr_url / issue_url / payload.repo") avoids the nouns both arms
#     between them require. What is claimed is coverage of those arms, never that no wording can
#     escape — see the residual bound below.
#     ⚑ BARE `source` IS NOT ENOUGH ON ITS OWN, and that is the lexical half of why the greps
#     failed: this tree spends the word on four unrelated things — the shell builtin, the
#     `.promote.source` config key, `source of truth`, and this field. So the first arm takes the
#     two spellings that are unambiguous here, `attribut*` and `by-ref` beside `source`.
#     ⚑ A SECOND ARM CARRIES `source` ANYWAY, because excluding it outright HAD a measured cost
#     (round 1, MINOR 5): *"whichever GitHub pr_url the card carries is what SETS ITS SOURCE, so
#     clearing that URL detaches the card from its repo"* is a full-strength instance in this
#     tree's own vocabulary and went green. The arm admits `source` when the passage also names a
#     derivation FIELD by name, which is what disambiguates it from the other three meanings —
#     measured on this tree, the arm costs 4 further dispositions where admitting bare `source`
#     beside any url/link would cost 48.
#     ⚑ THE RESIDUAL BOUND, WRITTEN DOWN AND PINNED BY A CONTROL: a claim that says `source` and
#     names NO field — "whichever link you paste sets its source" — is still outside the trigger.
#     That is the honest edge of this instrument, not an oversight; the control at the bottom
#     asserts it so the bound cannot quietly change without somebody noticing.
#
#   * THE DISCHARGE IS THE CONDITION ITSELF. A passage that names `payload.repo` has stated the
#     thing whose omission is the defect; a passage that does not has made the URL case sound
#     universal. That is one rule with no allow-list of blessed phrasings — and it is also the
#     shape every pointer in this tree already adopted, `bin/kbcard`'s being the model
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
# ⚑ NO APOSTROPHE ANYWHERE INSIDE THE awk PROGRAM BELOW — it is a single-quoted shell string, and
# one in a comment ends it. (The same constraint KB_JQ_REPO_FROM_GH_URL states for its own value.)
_bsc_passages() {
    awk -v REL="$2" '
    function flush() { if (buf != "") printf "%s\t%d\t%s\n", REL, start, buf; buf = ""; start = 0 }
    {
        line = $0
        # ORDER IS LOAD-BEARING, AND GETTING IT WRONG LOST FINDINGS IN BOTH DIRECTIONS (round 1,
        # MAJOR 1). The blockquote prefix is stripped FIRST, before the comment test, because a
        # bulleted line inside a blockquote is a new ITEM exactly as it is outside one — and the
        # first cut stripped it AFTER, so the same bullet broke a passage inside a quote and did
        # not outside it.
        sub(/^[ \t]*(>[ \t]*)+/, "", line)
        # ⛔ ONLY `#`. The first cut also treated a leading `*` as a C block-comment continuation
        # and ATE it — on the RAW line, before the item test could see it — so in markdown:
        #   MERGE: two adjacent `* ` bullets became ONE passage, and a neighbour bullet naming
        #          payload.repo then discharged the other one. Measured green where the same two
        #          lines as `- ` bullets red.
        #   SPLIT: a `**bold**`-leading continuation line flipped mode mid-paragraph and CUT the
        #          passage, so a claim spanning that break tripped nothing — which is miss 3, the
        #          defect this whole file exists to close, re-minted by its own classifier.
        # The arm guarded a state this tree cannot reach; re-derive rather than trust that:
        #   git ls-files | sed "s/.*\\.//" | sort | uniq -c | sort -rn   (sh, md, yml, py, txt)
        #   git ls-files | grep -cE "[.](c|h|js|ts|go|java|rs|css)$"       (0)
        # A `//` arm went with it for the same reason. Both are canon #6: not defending against a
        # state that cannot happen — and here the defence was the defect.
        if (match(line, /^[ \t]*#+[ \t]?/)) { mode = "c"; body = substr(line, RSTART + RLENGTH) }
        else                                 { mode = "p"; body = line }
        gsub(/^[ \t]+|[ \t]+$/, "", body)
        # A TABLE ROW IS ANCHORED AT BOTH ENDS. A bare leading-pipe test also fires on a jq
        # pipeline continuation line, which SPLIT the shipped derive_source into fragments and
        # hid the def from the leg that exempts it.
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
# <root>, with the carve-outs applied. They are argued at leg 3, which is the leg they were
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
# ⛔ `CLAUDE.md` IS CARVED AT ITS TABLE HEADER, NOT WHOLE-FILE (round 1, MINOR 6). It used to be
# the one carve-out with NO witness — no premise, no assertion, and a stated reason ("its release
# table is a copy of CHANGELOG highlights") that was true of the TABLE and not of the FILE, so any
# live prose added elsewhere in it disappeared silently. Measured: the whole-file carve suppressed
# exactly ONE reported line, the `v0.35.1` table row. It is now split like the other two and gets
# the same four premise assertions, so its frozen half is witnessed and its live head is IN.
CLAUDE_MD="$ROOT/CLAUDE.md"
# By SHAPE — the table's own header row — so no version and no line number is a fact kept here.
CLAUDE_CUT='^\| Version \| Date \|'
_carve "$CLAUDE_MD" "$CLAUDE_CUT" "$TMP/claude-live.md" "$TMP/claude-frozen.md"
BSC_HISTORY=()

# ⚑ THE FIELD SEPARATOR IS NOT `|`. `CLAUDE.md`'s cut pattern IS a pipe-delimited table row, and
# splitting on `|` shredded it into the wrong fields — caught by these very premises, which is the
# direction they exist for.
for pair in "docs/CHANGELOG.md~$CHANGELOG~$CHANGELOG_CUT~changelog" \
            "docs/UPGRADE.md~$UPGRADE~$UPGRADE_CUT~upgrade" \
            "CLAUDE.md~$CLAUDE_MD~$CLAUDE_CUT~claude"; do
    IFS='~' read -r cname cfile cpat ckey <<<"$pair"
    cutline="$(_headings "$cfile" "$cpat" | head -n 1 | cut -d: -f2-)"
    eq "$cname carries the heading it is split at" "true" \
       "$([ "$(_headings "$cfile" "$cpat" | grep -c . || true)" -ge 1 ] && echo true || echo false)"
    eq "premise: the $ckey LIVE head is non-empty"      "true" \
       "$([ -s "$TMP/$ckey-live.md" ] && echo true || echo false)"
    eq "…and stops before the first frozen entry"       "false" "$(_contains "$cutline" "$TMP/$ckey-live.md")"
    eq "…which IS in the frozen complement"             "true"  "$(_contains "$cutline" "$TMP/$ckey-frozen.md")"
done


# ⛔ THE FILE WALK KEEPS ITS OWN STDERR (round 1, MINOR 6). `grep -rIl ''` was written with
# `2>/dev/null`, so a file `grep` could not READ — or decided was binary and skipped under `-I` —
# left the population in silence, in the one leg whose whole claim is that it is fail-CLOSED over
# the repo. An unreadable file is not an absent file. The stderr is captured and asserted empty by
# the caller; `grep` exits 1 on "no file matched", which is a real state for an empty fixture tree
# and is not an error, so the rc is not what is judged here.
# ⚑ THE WALK'S STDERR GOES TO A FILE, NOT A VARIABLE. `_bsc_corpus` is always called inside a
# command substitution, i.e. in a SUBSHELL, so a variable it assigns never reaches the assertion —
# the first cut of this guard did exactly that and the premise below could not fail, which is the
# decoration canon #9 names. A file crosses the subshell boundary; a variable does not.
_bsc_corpus() { # <root> — every passage under <root>, carves applied
    local root="$1" f rel src
    grep -rIl '' "$root" --exclude-dir=.git 2>"$TMP/walk.err" >/dev/null || true
    while IFS= read -r f; do
        rel="${f#"$root"/}"
        case " ${BSC_HISTORY[*]} " in *" $rel "*) continue ;; esac
        src="$f"
        if [[ "$root" == "$ROOT" ]]; then
            case "$rel" in
                docs/UPGRADE.md)   src="$TMP/upgrade-live.md" ;;
                docs/CHANGELOG.md) src="$TMP/changelog-live.md" ;;
                CLAUDE.md)         src="$TMP/claude-live.md" ;;
            esac
        fi
        _bsc_passages "$src" "$rel"
    done < <(grep -rIl '' "$root" --exclude-dir=.git 2>/dev/null | LC_ALL=C sort)
}
ALL="$(_bsc_corpus "$ROOT")"
eq "premise: the corpus reached files and produced passages" "true" \
   "$([ -n "$ALL" ] && echo true || echo false)"
eq "premise: …and the walk read every file it was handed" "" "$(cat "$TMP/walk.err")"

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
# ⛔ THE HOME SET IS PINNED, AND ROUND 1's MAJOR 3 IS WHY. Deriving the homes from the markers
# alone checks only ONE direction — a marker removed from a statement. Deleting the marker AND the
# statement together was GREEN, home count 4 → 3 in silence, leaving `bin/kbcard`'s pointers citing
# a header that no longer states the rule, in a bin this file itself argues can read neither
# `docs/` nor `promote-released-cards`. A declaration checked in one direction is a declaration you
# can delete.
#
# THIS LIST IS A FLOOR AND ONLY THIS LEG READS IT, which is what makes hand-keeping it legitimate
# (the same terms `tests/lib-set-derivation-selftest.sh` leg 2 states for its own). It is asserted
# in BOTH directions below: every entry must resolve to a marked passage, and every marked passage
# must be an entry — so a home cannot be deleted, and a new one cannot be added unreviewed.
BSC_HOMES=(
    # The operator-facing full statement. `README.md` points here twice and `bin/_kb-board-lib.sh`
    # once, so deleting it dangles those pointers.
    "docs/INSTALL.md::derived exactly as the kanban server derives it"
    # The code-side statement, beside the def itself, for a copy vendored with no docs/.
    "bin/promote-released-cards::sourceFor field preference"
    # RENDERED to an operator, who cannot follow a pointer out of a log line.
    "bin/promote-released-cards::card has NO by-ref source"
    # kbcard's own, cited by its in-file pointers; vendored standalone, reads neither of the above.
    "bin/kbcard::THE DEFECT IT CLOSES"
)
HOMES="$(printf '%s\n' "$ALL" | grep -F "$MARKER" || true)"
eq "premise: at least one surface DECLARES itself a home" "true" \
   "$([ -n "$HOMES" ] && echo true || echo false)"
# DIRECTION 1 — every declared home still EXISTS, still carries its marker, and is the passage the
# registry named. This is the leg a whole-home deletion reds.
for h in "${BSC_HOMES[@]}"; do
    hpath="${h%%::*}"; hanchor="${h#*::}"
    eq "registered home still exists and is marked: $hpath — $hanchor" "true" \
       "$(awk -F'\t' -v p="$hpath" -v a="$hanchor" -v m="$MARKER" \
             'BEGIN{f="false"} $1==p && index($3,a) && index($3,m){f="true"} END{print f}' <<<"$HOMES")"
done
# DIRECTION 2 — and no marked passage is missing from the registry, so a fifth home cannot be
# declared without the review this list exists to force.
UNREGISTERED="$(awk -F'\t' -v reg="$(printf '%s\n' "${BSC_HOMES[@]}")" '
    BEGIN { n = split(reg, R, "\n") }
    NF >= 3 {
        for (i = 1; i <= n; i++) {
            p = R[i]; sub(/::.*/, "", p); a = R[i]; sub(/^[^:]*::/, "", a)
            if ($1 == p && index($3, a)) next
        }
        printf "%s:%s\n", $1, $2
    }' <<<"$HOMES")"
eq "no marked home is missing from the registry" "" "$UNREGISTERED"
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
    "bin/_kb-board-lib.sh::WHY THIS IS A PRIMITIVE AND NOT A SHAPE TEST AT EACH CALLER::fee40a6f7730"
    "bin/promote-released-cards::THE SHAPE \`case\` ABOVE AND THIS CHARSET CHECK ARE ONE PAIR::065ec7d1f572"
    "tests/kb-board-lib-selftest.sh::A SHAPE TEST ALONE CANNOT DO THIS JOB::1fd3905c3c9b"

    # ── WHAT A TOOL STAMPS, not what the board then reads. Both describe the write; the rule for
    #    the read is stated 20 lines below each, at `_ata_pr_url` and `_ata_issue_url`, and both
    #    of those carry the condition.
    "README.md::pull-into-build adoption seam::1a88070060c7"
    "bin/adopt-to-dl::Usage: adopt-to-dl <card-id> --repo::3f252362e401"

    # ── ⚠ RENDERED FAILURE TEXT, REPORTED RATHER THAN FIXED (card#9957). Both messages list the
    #    causes of a failed by-ref VERIFY and neither names the one this rule creates: a card
    #    whose `payload.repo` names a repo other than `--repo` verifies against a source the
    #    stamp did not set. That is a real gap in what the operator is told — and changing what a
    #    tool tells an operator is an ask-first gate, so it is named here and on the card rather
    #    than taken unasked. The passages state no precedence either way, which is why they are
    #    disposed and not fixed in passing.
    #
    #    ⚠ RE-RULED at card#10241, against the text that is there now — which is the digest
    #    field's whole purpose, and the case its own header predicted ("the edit that closes that
    #    finding would have landed INSIDE a disposed passage"). Each passage now also carries an
    #    UNMEASURED arm, for a by-ref answer that could not be READ at all; that arm names no key
    #    and no precedence either, and the card#9957 gap above is untouched by it — an undecodable
    #    response and a card sourced to another repo are different causes, and only the first one
    #    is what that arm is about.
    "bin/adopt-to-dl::VERIFY FAILED — by-ref(system=dl::f07b741db3eb"
    "bin/adopt-to-dl::ISSUE VERIFY FAILED — by-ref(system=github_issue::392169920b00"

    # ── THE NULL CASE — "this card has NO source", which is not a claim about which key supplies
    #    one. The remedy each gives (stamp a `pr_url`) is correct under its own premise: a card
    #    with a `payload.repo` that is a string containing `/` is not in the population these
    #    lines describe.
    "bin/promote-released-cards::A card with NO derivable by-ref source cannot be attributed::a7139314fe13"
    "bin/release-pr-body::matched ONLY an unsourced card::d7ef1a8db8a4"
    "docs/INSTALL.md::Shipped refs whose card carries no by-ref source::a306030aea36"
    "tests/promote-source-qualify-selftest.sh::qualified: the foreign card is NAMED, by id::86591210a1ed"
    "tests/release-pr-body-selftest.sh::the coverage report MEASURED (qualified)::bdbe48bd011b"

    # ── ADMITTED BY ARM 2 (bare `source` beside a field name), and the same rulings as above one
    #    class over: what the tool STAMPS, and a fixture. The arm that reported them also found a
    #    real site four sweeps and this file's own round-1 predicate had all missed —
    #    `bin/adopt-to-dl`'s step-4 note — which is fixed rather than disposed.
    "bin/adopt-to-dl::Stamps an EXISTING plain product card::44563f1fb1b4"
    "tests/promote-source-qualify-selftest.sh::4c: nothing was promoted::7d9b8b1c2b79"

    # ── A DIFFERENT SUBJECT that happens to share the nouns: a custom FIELD definition narrowing
    #    under cards that carry a value for it.
    "bin/kbcard::even while a card references the dropped value::7ea4273e4d9f"

    # ── ASSERTIONS ABOUT A MESSAGE, not statements of the rule. `_c9918` asserts that a refusal
    #    states NO attribution consequence — the opposite of making one — and the prelude-shadow
    #    entry is a disposition table for another guard entirely.
    "tests/kbcard-selftest.sh::it states no consequence: no attribution::fd7177779bbd"
    "tests/prelude-shadow-selftest.sh::EXTRACTORS=(::003fa2a3c360"

    # ── THIS FILE ITSELF: its own prose about the trigger, the trigger, and its own control
    #    fixture. The fixture MUST be reportable — that is its job — and the other two cannot
    #    describe a predicate over these nouns without using them.
    "tests/by-ref-source-claim-selftest.sh::WHY THIS FILE EXISTS::3b392b49ed5d"
    "tests/by-ref-source-claim-selftest.sh::ARM 1 — a URL or link::43370a6a1fe8"
    "tests/by-ref-source-claim-selftest.sh::TWO CARVE-OUTS::01279241b6d0"
    "tests/by-ref-source-claim-selftest.sh::control: a claim SPLIT ACROSS LINES is reported::cfa933e61486"
)

# _bsc_claims <passages> — the trigger, and its one implementation. Nouns only; see the header.
_bsc_claims() {
    awk -F'\t' '
    BEGIN { FLD = "pr_url|issue_url|html_url|external_link|payload[.]repo" }
    {
        t = tolower($3)
        # ARM 1 — a URL or link, and an attribution, in a passage about a card.
        a1 = (t ~ /url|link/) && (t ~ /attribut/ || (t ~ /by-ref/ && t ~ /source/))
        # ARM 2 — bare `source`, admitted only beside a derivation FIELD NAME, which is what
        # tells this meaning of the word apart from the other three this tree spends it on.
        a2 = (t ~ /source/) && (t ~ FLD)
        if ((t ~ /card/) && (a1 || a2)) print
    }' <<<"$1"
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

# ⛔ A DISPOSITION IS BOUND TO THE EXACT TEXT IT RULED ON — `<path>::<substring>::<digest>` — AND
# THAT THIRD FIELD IS THE WHOLE OF ROUND 1's MAJOR 2. A reported line is a PASSAGE, so a
# disposition matched on path+substring alone suppresses the whole passage, and a passage GROWS:
# measured, a brand-new undischarged operator-rendered claim inserted one line below the already
# disposed `VERIFY FAILED` message in `bin/adopt-to-dl` went green and did not move the claim
# count, while the same claim in a different passage of the SAME file reported. So the scope was
# never "the line" the PR body claimed — it was "whatever that passage grows into", unbounded.
#
# ⚠ AND IT IS REACHABLE BY THIS CARD'S OWN NEXT STEP: those two `VERIFY FAILED` messages are the
# ask-gated edit named in the dispositions below, so the edit that closes that finding would have
# landed INSIDE a disposed passage.
#
# The digest is over the passage TEXT, so any change to it re-reports and the ruling has to be
# re-made against what is there now — which is the same contract the liveness assertion already
# imposes in the other direction. A failure PRINTS the current digest, so re-ruling is a
# one-field edit and never a hunt.
#
# _bsc_digest — the first 12 hex of the sha256 of stdin. One owner; the recorded field and the
# measured value can only be produced the same way.
_bsc_digest() { sha256sum | cut -c1-12; }

# _bsc_disposes <dpath> <dsub> <line> — path prefix + substring. Deliberately NOT the digest: the
# two questions below need to find the passage a disposition is ABOUT even when its text has
# moved, so that the failure can say "this ruling is stale" instead of "this ruling is dead".
_bsc_disposes() { case "$3" in "$1: "*) case "$3" in *"$2"*) return 0 ;; esac ;; esac; return 1; }

# _bsc_disposed_digest <dpath> <dsub> — the digest of the passage this disposition matches now,
# or the empty string when it matches none.
_bsc_disposed_digest() {
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if _bsc_disposes "$1" "$2" "$line"; then printf '%s' "${line#*: *: }" | _bsc_digest; return 0; fi
    done <<<"$BSC_RAW"
    printf ''
}

# A disposition suppresses a reported passage ONLY while that passage still hashes to what was
# ruled on. A passage that has changed falls straight back into the undisposed set.
_bsc_undisposed() {
    local raw="$1" d line keep dpath dsub ddig
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        keep=true
        for d in ${BSC_DISPOSED[@]+"${BSC_DISPOSED[@]}"}; do
            dpath="${d%%::*}"; ddig="${d##*::}"; dsub="${d#*::}"; dsub="${dsub%::*}"
            if _bsc_disposes "$dpath" "$dsub" "$line"; then
                [[ "$(printf '%s' "${line#*: *: }" | _bsc_digest)" == "$ddig" ]] && keep=false
            fi
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
    dpath="${d%%::*}"; ddig="${d##*::}"; dsub="${d#*::}"; dsub="${dsub%::*}"
    eq "disposition suppresses a live passage: $dpath — $dsub" "true" "$(_bsc_disposition_live "$dpath" "$dsub")"
    # …AND that passage is still the text the ruling was made about. A changed passage reds here
    # with the digest to paste back, after the ruling has been re-made against what it says now.
    eq "…and that passage is unchanged since it was ruled on: $dpath" "$ddig" "$(_bsc_disposed_digest "$dpath" "$dsub")"
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

# ⛔ THE MARKDOWN-CLASSIFIER CONTROLS (round 1, MAJOR 1). Both directions the first cut lost, each
# beside the one-character-different text that already reported — which is what makes them
# measurements of the classifier rather than of the trigger.
#
# MERGE: two adjacent `* ` bullets, the second naming payload.repo. Under the first cut the `*`
# was eaten as a comment marker, the two became ONE passage, and the neighbour discharged the
# claim. The `- ` pair beside it reported throughout, so the difference is the bullet character.
mkdir -p "$TMP/fix2/docs"
{ printf -- '* The stamped pr_url is what %s the card to a repo, for every release.\n' "$AV"
  printf -- '* Separately, payload.repo is a key some boards set.\n'; } > "$TMP/fix2/docs/STAR-BULLETS.md"
{ printf -- '- The stamped pr_url is what %s the card to a repo, for every release.\n' "$AV"
  printf -- '- Separately, payload.repo is a key some boards set.\n'; } > "$TMP/fix2/docs/DASH-BULLETS.md"

# SPLIT: a `**bold**`-leading continuation line. Under the first cut this flipped mode mid-
# paragraph and CUT the passage, so the claim tripped nothing — miss 3 re-minted by the very
# classifier built to close it. The unbolded sentence beside it reported throughout.
{ printf 'Whichever GitHub link was stamped last is the one the board reads, and it is\n'
  printf -- '**what decides** which repository the card is %s to from then on.\n' "$AV"; } > "$TMP/fix2/docs/BOLD-SPLIT.md"
{ printf 'Whichever GitHub link was stamped last is the one the board reads, and it is\n'
  printf -- 'what decides which repository the card is %s to from then on.\n' "$AV"; } > "$TMP/fix2/docs/PLAIN-SPLIT.md"

# …and the same `*` bullets INSIDE a blockquote, which reported even under the first cut because
# the `>` strip happened to run first there. It is the control that pinned the cause, so it stays.
{ printf -- '> * The stamped pr_url is what %s the card to a repo, for every release.\n' "$AV"
  printf -- '> * Separately, payload.repo is a key some boards set.\n'; } > "$TMP/fix2/docs/QUOTED-STAR.md"

FIX2TREE="$(_bsc_scan "$TMP/fix2")"
for fx in STAR-BULLETS DASH-BULLETS BOLD-SPLIT PLAIN-SPLIT QUOTED-STAR; do
    eq "control: markdown classifier reports docs/$fx.md" "true" "$(has "docs/$fx.md" "$FIX2TREE")"
done

# ⚑ THE STATED RESIDUAL BOUND OF THE TRIGGER, PINNED SO IT CANNOT MOVE UNNOTICED (round 1,
# MINOR 5). Arm 2 admits bare `source` only beside a derivation FIELD NAME. A claim that says
# `source` and names no field is therefore OUTSIDE this instrument — this asserts that edge is
# where the header says it is, and reds if it ever moves in either direction.
# The field name is COMPOSED, so this file does not itself hold a claim naming one (the same
# reason `$AV` carries the attribution verb in the fixtures above).
FLDN='pr_url'

printf 'Whichever link you paste last on the card sets its source from then on.\n' \
    > "$TMP/fix2/docs/RESIDUAL-NO-FIELD.md"
printf 'Whichever %s you paste last on the card sets its source from then on.\n' "$FLDN" \
    > "$TMP/fix2/docs/RESIDUAL-WITH-FIELD.md"
FIX2TREE="$(_bsc_scan "$TMP/fix2")"
eq "control: arm 2 reports a 'sets its source' claim that NAMES a field" "true" \
   "$(has 'docs/RESIDUAL-WITH-FIELD.md' "$FIX2TREE")"
eq "control: …and the stated bound holds — the same claim naming NONE is out of reach" "false" \
   "$(has 'docs/RESIDUAL-NO-FIELD.md' "$FIX2TREE")"

# THE DISPOSITION MECHANISM, on the fixture tree. FOUR directions, and the fourth is the one
# round 1 found missing: the first cut only ever exercised a claim in a DIFFERENT FILE, which is
# not the direction that loses findings. A disposition suppresses a PASSAGE, so the direction that
# loses findings is a new claim arriving INSIDE one — and that is now a control.
FIX2="$(_bsc_scan "$TMP/fix")"
BSC_RAW_SAVE="$BSC_RAW"; BSC_RAW="$FIX2"
BSC_DISPOSED_SAVE=("${BSC_DISPOSED[@]+"${BSC_DISPOSED[@]}"}")
SPLIT_SUB='every release that ships its number'
SPLIT_DIG="$(printf '%s' "$(printf '%s\n' "$FIX2" | sed -n "s/^docs\/SPLIT-CLAIM.md: [0-9]*: //p")" | _bsc_digest)"
BSC_DISPOSED=("docs/SPLIT-CLAIM.md::$SPLIT_SUB::$SPLIT_DIG")
eq "control: a disposition suppresses its own passage"     "false" \
   "$(has 'docs/SPLIT-CLAIM.md' "$(_bsc_undisposed "$FIX2")")"
eq "control: …and nothing else in the tree"                "true" \
   "$(has 'docs/NEVER-WORDED-THIS-WAY.md' "$(_bsc_undisposed "$FIX2")")"
eq "control: …and a live disposition reports itself live"  "true" \
   "$(_bsc_disposition_live 'docs/SPLIT-CLAIM.md' "$SPLIT_SUB")"
eq "control: …while a disposition matching nothing is DEAD" "false" \
   "$(_bsc_disposition_live 'docs/SPLIT-CLAIM.md' 'a substring no line carries')"
# ⛔ THE FOURTH DIRECTION (round 1, MAJOR 2). A NEW claim appended into the disposed passage —
# no blank line, so it joins that passage rather than starting one — must NOT inherit the ruling.
# The disposition still MATCHES (same path, same substring); what stops it suppressing is that the
# passage no longer hashes to what was ruled on.
printf 'A new sentence: the link last pasted is what %s the card to its repo.\n' "$AV" \
    >> "$TMP/fix/docs/SPLIT-CLAIM.md"
FIX3="$(_bsc_scan "$TMP/fix")"
eq "control: a claim appended INTO a disposed passage is NOT suppressed" "true" \
   "$(has 'docs/SPLIT-CLAIM.md' "$(_bsc_undisposed "$FIX3")")"
# …and the stale ruling says so by NAME rather than by going quiet: the disposition still matches
# a passage, and it is the digest leg that reds.
BSC_RAW="$FIX3"
eq "control: …the disposition still MATCHES a passage"     "true" \
   "$(_bsc_disposition_live 'docs/SPLIT-CLAIM.md' "$SPLIT_SUB")"
eq "control: …but its digest no longer does"               "false" \
   "$([ "$(_bsc_disposed_digest 'docs/SPLIT-CLAIM.md' "$SPLIT_SUB")" = "$SPLIT_DIG" ] && echo true || echo false)"
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
