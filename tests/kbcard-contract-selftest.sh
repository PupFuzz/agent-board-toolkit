#!/usr/bin/env bash
# kbcard-contract-selftest.sh — the drift pin for those `kbcard` interface contracts that are
# stated on TWO reader-facing surfaces and were held together by nothing (card#9173).
#
# ⭐ THE POPULATION IS THE CONTRACTS TABLED BELOW, and it is named rather than implied: today
# `stages`' output contract, and `list`'s ROW PROJECTION. It is not "every kbcard verb" and this
# file does not pretend to derive one; the second member was added because the FIRST member's own
# defect shape was found live on it — README published `list`'s projection as a fixed, exhaustive
# TEN-key list while the verb emitted more (see that section's header; the live set is read off
# the projection at assert time and is pinned in no prose here). A third member belongs
# here rather than in a third file: the authority model, the extractor refusals and the control
# discipline below are the same for any two-surface contract, and a second file holding a second
# copy of them would be the divergent-implementation defect this repo files as canon #5.
#
# THE TWO SURFACES, AND WHY NEITHER CAN BE DELETED. Each contract is stated in `bin/kbcard`'s
# `Usage:` header — which IS the rendered help, printed by a bare `kbcard` — and again in its own
# `README.md` span. Canon #16 allows a restatement to be DELETED in favour of a
# pointer only where the consumer can FOLLOW the pointer, and here neither consumer can:
#   * the help block is read at a TERMINAL, by someone who may have no browser and no network,
#     so it cannot be replaced by "see README";
#   * the README section is read BEFORE the tool is installed — it is the vendor-facing
#     interface doc an adopting repo evaluates (README § Get started → docs/INSTALL.md §6b), and
#     README's own `list` section links INTO this section's anchor — so it cannot be replaced by
#     "run `kbcard --help`" on a box where `kbcard` is not on PATH.
# Both copies therefore stay, and the duplication is GUARDED. This file is that guard.
#
# THE DRIFT IS NOT HYPOTHETICAL. card#9171 added a stderr provenance line emitted on every
# successful call, updated the in-bin help and left README describing the pre-change output
# contract — caught in review on that PR, by a person. Nothing mechanical noticed, and the reason
# is worse than "no check compared them": `bin/kbcard` mentions `--help` ZERO times (it prints
# the block on a bare invocation), so `help-output-selftest.sh`'s derived scan cannot see it and
# it is in neither that file's CLIS nor its EXCLUDED — the exact escape its own header names, a
# bin dispatching help under some other spelling. `readme-bin-coverage-selftest.sh` asserts each
# bin owns a README ROW, not that any prose agrees with anything. Until this file, the ONLY
# assertion anywhere on kbcard's rendered help was a `has 'Usage:'` presence check in
# `kb-positional-guard-selftest.sh` — a contains-check, which passes while truncating everything
# after the match.
#
# ⭐ WHAT THIS FILE COMPARES, AND WHAT IT DELIBERATELY DOES NOT. It does NOT compare the two
# prose copies to each other. They are not verbatim twins — measured, not assumed: one is
# markdown with bold and in-document anchors, the other is 78-column plain text behind a `# `
# prefix — so no equality is available over them, and a comparison of two hand-maintained copies
# has no authority in it anyway: both can be identically wrong and pass.
#
# The authority here is the EXECUTABLE. Each fact below is OBSERVED by running the verb, and the
# observation decides what the two surfaces are then required to say: a needle is required
# PRESENT or required ABSENT according to a value read out of a live call, never according to a
# constant written here. So a behaviour change moves the requirement, and whichever surface was
# not updated reds — which is exactly the shape card#9171's drift had.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support:
#   * that for each fact in the table, BOTH surfaces carry a needle whose required polarity the
#     live verb chose. NOT that either surface's prose is accurate beyond that needle, complete,
#     or well-written; a surface can carry the needle inside a sentence that says the opposite.
#   * NOTHING about facts absent from the table. The table is a floor that grows with the
#     contract, not a derivation of the contract's full statement — English cannot be derived
#     from bash, and this file does not pretend otherwise.
#   * NOTHING about the two surfaces stating the SAME set of claims. It requires each tabled
#     fact on both; a claim only one surface makes is invisible here (see the bound below).
#   * NOTHING about any verb's help/README pair that is not TABLED here. The population is named
#     at the top of this file; a verb absent from it is guarded by nothing.
#
# ⛔ THE BOUND, STATED AS A PROPERTY AND NOT AS A LIST OF EXCEPTIONS. It was a list once, and the
# list was wrong twice over in one sentence: it named `sorted by name` as the single doc-side-only
# fact when two others were as weak, and it blamed a mechanism (`bash sorts ${!KB_STAGE_@}`) that
# the same mutation disproves — bash does hand back name order, and the mutant still emits ID
# order, because `unique_by(.id)` on the emit line sorts by its key before `sort_by(.name)` ever
# runs. A maintainer acting on that sentence would have looked at the env and found nothing.
#
# ⭐ THE PROPERTY, which is what to check instead: A FACT IS ONLY AS STRONG AS THE SPAN OF ITS
# OBSERVATION. `assert_fact`'s controls prove the NEEDLE is load-bearing; they say nothing about
# whether the OBSERVATION could have come out the other way. So for each fact ask: could this
# probe have produced the opposite value against some reachable code change? Where the answer
# turns on the FIXTURE rather than on the call, the probe carries an explicit WITNESS below
# asserting the fixture still discriminates — a witness reds when a later tidy-up flattens the
# fixture, which is the move that silently turns a live fact into a decoration.
#
# ⛔ HOW TO RUN THE MUTATION THAT ANSWERS THAT QUESTION — the interactive shape is UNSAFE on an
# agent seat. A mutate-measure-restore run by hand leaves the tree mutated whenever the measure
# step is cancelled mid-flight, and on an agent seat a context clear does exactly that: the
# in-flight call dies (rc 137) with the edit applied and the restore never reached, so the next
# thing to read `bin/kbcard` reads the MUTANT and every conclusion drawn from it is about code
# nobody shipped. It happened twice while this file was being written. The safe shape:
#   * put the mutation, the measurement AND the restore in one script, restore in a trap so it
#     runs on any exit path — never as a later step someone still has to reach;
#   * run that script DETACHED (`nohup … &`), so a cancelled foreground call cannot orphan it;
#   * afterwards assert the tree is clean — `git diff --quiet -- bin/kbcard` — rather than
#     trusting that the restore ran. A mutation you cannot prove you reverted is a mutation you
#     have to assume is still there.
#   * ⚠ AND COMMIT YOUR OWN EDITS TO THAT FILE FIRST. The restore is `git checkout -- <file>`,
#     which restores from the INDEX — so it silently DISCARDS any uncommitted legitimate edit to
#     the same file, and the clean-tree assertion above then reports CLEAN precisely BECAUSE your
#     work was reverted. Measured, in card#9173's own fifth round: a one-line comment fix to
#     `bin/kbcard` was made, verified present, wiped by a later mutation run's trap, and the
#     "tree clean" check confirmed the loss instead of catching it. A safety assertion that
#     passes because of the damage it was meant to detect is worse than no assertion.
#
# Beyond that span question: a rewrite of either surface that preserves every needle while
# changing the meaning around it passes; a needle present for an unrelated reason satisfies its
# fact; the two surfaces are not required to state the same SET of claims; and the ordinal fact
# is blunt in the ADD direction — growing an ordinal key makes fact `row keys` require
# `"ordinal"` while fact `ordinal` requires it absent, so the pair is guaranteed to red, loudly
# and for a confusing reason, which is the intended fail-closed outcome and not a diagnosis.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"

BIN="$HERE/../bin/kbcard"
README="$HERE/../README.md"
_need -x "$BIN"
_need -r "$README"

_mktmp_scratch --home
kb_stub_scrub_env
# The operator's own shell exports these, and the verb reads the ambient environment as well as
# the board env — an unscrubbed KB_STAGE_* would put a live board's ids into every observation.
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}

# ONE fixture serves the whole file, and it has to exist before the help is even captured:
# `main` resolves the board env BEFORE its no-arguments help path, so a bare `kbcard` on a box
# with no board env exits 2 with no help at all. The curl stand-in goes on PATH here rather than
# in the no-request section below so that EVERY process this file starts is answered by the stub
# — a call that escaped to the wire would otherwise depend on which section it came from.
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48' 'export KB_STAGE_SHIPPED_TO_DEV=51'
kb_stub_install
kb_stub_route() { printf '500\n{"message":"stages must not reach the wire"}'; }
export -f kb_stub_route

# shellcheck source=/dev/null
source "$BIN"   # main-guarded — defines cmd_stages/stage_name without running

# ═══════════════════════════ the two spans, extracted and REFUSED when empty ═════════════════
#
# Both extractions are SECTION-SCOPED, and both are terminated by the next sibling heading
# rather than run to end-of-file: an unterminated span would swallow the following verb's prose
# and satisfy needles this section never carried — an err-GREEN hole. A renamed heading makes an
# extraction EMPTY, which is refused by name rather than passed as a span with nothing in it
# (an empty span answers `false` to every present-needle fact, i.e. it reds — but it reds
# blaming the docs for a broken extractor). The controls below drive both directions.

# THE BLOCK-OPENING LINE of each surface, declared ONCE because two questions need the same
# string: a block STARTS on it, which is exactly why the block before it ENDS on it. The
# extractors below terminate on it and `_block_opens` counts it back inside the extracted span,
# so "where the span stops" and "the check that it stopped" cannot drift apart — they are one
# declaration read twice, not two statements to keep in step.
HELP_BLOCK_OPEN='^  kbcard [a-z]'
README_BLOCK_OPEN='^## '

# _help_span <rendered-help-text> <verb> — that verb's block of the RENDERED help. Rendered, not
# read out of the source file: what a terminal user sees is the thing under contract, and the
# renderer strips one leading `# `, so this also proves the block is reachable in the output.
# The START anchor is a PREFIX match, not the whole-line one `stages` alone could use: `list`'s
# verb line carries its flags, and an anchor that required a bare verb line would silently
# return an empty span for every verb that takes one.
_help_span() {
    awk -v verb="$2" -v open="$HELP_BLOCK_OPEN" '
        $0 ~ "^  kbcard " verb "([ \t]|$)" { inside = 1; print; next }
        inside && $0 ~ open                 { exit }
        inside                              { print }
    ' <<<"$1"
}

# _readme_span <path> — the `## `kbcard stages`` section of a README, to the next `## `.
_readme_span() {
    awk -v open="$README_BLOCK_OPEN" '
        /^## `kbcard stages`/ { inside = 1; print; next }
        inside && $0 ~ open   { exit }
        inside                { print }
    ' "$1"
}

# _block_opens <span> <block-opening-regex> — how many block-OPENING lines the extracted span
# carries. A span whose terminator fired carries exactly ONE: its own. That is the BOUNDED leg
# for every surface here, and it is DERIVED — it counts the very pattern the extractor stops on,
# so no second constant exists to keep in step with the documents. `1` is not a per-site figure
# either: it is the same structural invariant at every call, and it is a PRECONDITION of the
# extractor rather than a house style — a block that grew a second opening line would have its
# span TRUNCATED at that line, which is a red worth having.
#
# ⛔ WHY NOT "the span does not contain <the next block's name>", which is what all three call
# sites below used to say: that names a NEIGHBOUR, and a neighbour is a hand-typed constant that
# goes stale in silence. One of the three was typed five blocks too far — `list`'s leg asserted
# the span stops before `kbcard show` when `list`'s actual neighbour is `kbcard stages` — so it
# could only fail on a FIVE-block overrun, and a ONE-block overrun shipped `all checks passed`
# at rc 0 (measured on the commit that introduced it, and again before this replacement).
# Counting openings reds on a one-block overrun, on every surface, and names nothing that would
# ever have to be told about a document again.
_block_opens() { command grep -cE -- "$2" <<<"$1" || true; }

# _require_span <what> <text> — the extractor refusal. It does NOT return: an empty span means the
# anchor moved, and every fact downstream would then measure the empty string. It reports through
# `bad` + `_summary` rather than a bare `printf`+`exit`, so a refusal prints the same
# `N check(s) FAILED` trailer every other failure here does — a run that dies on a different line
# shape reads as a harness crash rather than as this file saying no. `_summary` exits 1 on a
# non-zero `fails`, which is why nothing follows it.
_require_span() {
    [[ -n "$2" ]] && return 0
    bad "the $1 span came out EMPTY — its anchor moved; fix the extractor in $(basename "${BASH_SOURCE[0]}")"
    _summary "kbcard-contract-selftest"
}

echo "== the two surfaces are extractable, bounded, and refuse an empty span =="
HELP_TEXT="$("$BIN")"
HELP_SPAN="$(_help_span "$HELP_TEXT" stages)"
README_SPAN="$(_readme_span "$README")"
_require_span "rendered --help" "$HELP_SPAN"
_require_span "README" "$README_SPAN"

eq "the --help span starts at the verb line"  "  kbcard stages" "$(head -n1 <<<"$HELP_SPAN")"
eq "the README span starts at the heading"    "true" \
   "$(has '## `kbcard stages`' "$(head -n1 <<<"$README_SPAN")")"
# BOUNDED, both — the terminator fired, so neither span carries the NEXT block. Asked as a
# count of block-OPENING lines rather than as the absence of a named neighbour; see `_block_opens`.
eq "the --help \`stages\` span carries exactly ONE verb line — its own"       "1" \
   "$(_block_opens "$HELP_SPAN" "$HELP_BLOCK_OPEN")"
eq "the README \`stages\` span carries exactly ONE \`## \` heading — its own" "1" \
   "$(_block_opens "$README_SPAN" "$README_BLOCK_OPEN")"

# CONTROL — each extractor watched to go empty, and the refusal watched to fire, on the one
# mutation that breaks it. Without this the extractors are decorations: a pair that silently
# returned "" would let every fact below pass or fail for a reason that has nothing to do with
# the docs.
rc=0
( _require_span "x" "$(_help_span "$(sed 's/^  kbcard stages$/  kbcard stagez/' <<<"$HELP_TEXT")" stages)" ) \
    >/dev/null 2>&1 || rc=$?
eq "control: a renamed --help verb line empties the span AND is refused" "1" "$rc"
sed 's/^## `kbcard stages`.*/## `kbcard stagez` — renamed/' "$README" >"$TMP/readme-mut.md"
rc=0
( _require_span "x" "$(_readme_span "$TMP/readme-mut.md")" ) >/dev/null 2>&1 || rc=$?
eq "control: a renamed README heading empties the span AND is refused" "1" "$rc"

# ═══════════════════════════ normalization, and the fact assertion ══════════════════════════
#
# The two registers differ in ways that carry no meaning — markdown emphasis, the `# ` prefix,
# where a sentence happens to wrap, and CASE (the help block shouts what README bolds). A needle
# must survive all four or it would pin the typography instead of the claim, so both spans are
# folded the same way before any match. The fold is deliberately NARROW — a `*` goes because
# markdown bold is `**` and the shipped needles never turn on the one in `KB_STAGE_*`; every
# other punctuation mark a needle might contain stays, quotes, `>`, `&` and digits included,
# because a fold wide enough to make a needle always match is a check that cannot fail.
_norm() {
    printf '%s' "$1" | sed 's/^[[:space:]]*#\{0,1\}[[:space:]]*//' \
        | tr -d '`*' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'
}
HELP_N="$(_norm "$HELP_SPAN")"
README_N="$(_norm "$README_SPAN")"

# assert_fact <label> <needle> <required-true|false> — the whole table's one assertion.
# <required> is a value OBSERVED from a live call at the call site, never a literal: that is what
# makes the CODE decide what the docs must say, rather than this file restating the contract as
# a third copy.
#
# Each fact carries its own CONTROL, on both surfaces, in the direction its polarity needs — a
# required-present needle is redacted out of a copy of the span and the answer must flip; a
# required-absent one is injected. A fact with no control proves only that the needle happened to
# be there, which every string is until something removes it.
assert_fact() {
    local label="$1" needle="$2" want="$3" other h r
    [[ "$want" == true || "$want" == false ]] || {
        printf 'selftest: %s got a non-boolean requirement %q — the observation did not resolve\n' \
            "$label" "$want" >&2
        exit 1
    }
    [[ "$want" == true ]] && other=false || other=true
    eq "$label: the rendered --help states it" "$want" "$(has "$needle" "$HELP_N")"
    eq "$label: README states it"              "$want" "$(has "$needle" "$README_N")"
    if [[ "$want" == true ]]; then
        h="${HELP_N//"$needle"/<redacted>}"; r="${README_N//"$needle"/<redacted>}"
    else
        h="$HELP_N $needle"; r="$README_N $needle"
    fi
    eq "  control: $label — a --help span with the needle flipped answers $other" "$other" "$(has "$needle" "$h")"
    eq "  control: $label — a README span with the needle flipped answers $other" "$other" "$(has "$needle" "$r")"
}

# ═══════════════════════════ the fact table ═════════════════════════════════════════════════

echo "== the contract, observed from the running verb and required on both surfaces =="
export KB_BOARD_ID=42
# ⛔ THE FIXTURE IS SHAPED BY WHAT THE OBSERVATIONS HAVE TO SPAN, not by what is tidy.
#   * KB_STAGE_ALPHA's id is the LARGEST while its name sorts FIRST, so the row-order probe can
#     answer NO. With ids ascending in name order it could not, and the `sorted by name` fact was
#     a decoration — `sort_by(.name)` deleted from `cmd_stages` left this file green.
#   * KB_STAGE_IN_PROGRESS is MULTI-TOKEN, so the name-derivation probe spans the whole claim
#     ("suffix, lowercased") and not just the lowercasing: a fold that also rewrote `_` would
#     make both surfaces false, and a single-token probe cannot see it.
export KB_BOARD_ID=42 KB_STAGE_BACKLOG=48 KB_STAGE_IN_PROGRESS=49 KB_STAGE_TESTING=77 KB_STAGE_ALPHA=90
ROWS="$(cmd_stages 2>/dev/null)"
eq "observation precondition: the verb emitted rows to observe" "4" "$(jq 'length' <<<"$ROWS")"

# FACT — THE ROW KEY SET. Derived per key: whatever keys the verb actually emits must be NAMED
# on both surfaces, so a key added to stdout cannot ship undocumented on either.
# ⭐ THE UNION OVER EVERY ROW, not `.[0] | keys`. Applying this file's own span question to its own
# facts — the review's finding was a CLASS, so the audit is owed here too (canon #7) — turned up
# this one: the surfaces claim the shape of EVERY row ("one {id, name} object per mapped stage,
# and no other key"), while reading row 0 alone spans a population of one. A key emitted on some
# rows and not the first is exactly the shape `list`'s consumers join on, and it escaped.
KEYS="$(jq -r '[.[] | keys] | add | unique | .[]' <<<"$ROWS")"
# ⚑ THE LITERAL IS DELIBERATE AND IS NOT `list`'s defect in a second dress (ruled in card#9173's
# sixth round, on the record rather than left to the next reviewer to re-find). `list`'s
# hand-typed copy was the AUTHORITY a comparison against the DOCUMENTS ran against, so both
# documents could agree with a stale literal while a new key shipped undocumented at rc 0. This
# one authorises nothing — the doc legs below derive from `$KEYS` — it only asserts the fixture
# produced the shape they derive FROM, so a key-set change reds HERE, naming its cause, rather
# than as a handful of confusing doc reds. Nor can it drift silently against
# `tests/kbcard-selftest.sh`'s pin of the same set: a behaviour change reds both, loudly.
eq "observed: the row key set" "id name" "$(tr '\n' ' ' <<<"$KEYS" | sed 's/ $//')"
while read -r _k; do
    [[ -n "$_k" ]] || continue
    assert_fact "row key \"$_k\"" "\"$_k\"" true
done <<<"$KEYS"

# FACT — THE STDERR PROVENANCE LINE, on EVERY successful call. This is card#9171's own claim and
# the one the drift dropped: README described the pre-change output contract, so a consumer read
# the happy path as writing nothing to stderr.
# ⭐ OBSERVED BY CONTENT, NOT BY NON-EMPTINESS. What both surfaces claim is that the LOCAL-ALIAS
# CAVEAT rides stderr on every success — not that stderr is non-empty. Replacing the declaration
# with any other line (`kbcard: stages: read complete.`) satisfies a `-n "$ERR"` probe while both
# surfaces go false, so that probe spanned deletion only and was half-live. The needle is the
# declaration's own words, the same ones `kbcard-selftest.sh` pins the message by — deliberately
# the same, because an observation narrower than the claim is the defect being closed here.
ERR="$(cmd_stages 2>&1 >/dev/null)"
_writes_stderr="$(has 'NAMES ARE LOCAL' "$ERR")"
eq "observed: a successful call puts the LOCAL-ALIAS DECLARATION on stderr" "true" "$_writes_stderr"
eq "  control: a non-empty stderr alone does NOT satisfy that probe" "false" \
   "$(has 'NAMES ARE LOCAL' 'kbcard: stages: read complete.')"
assert_fact "the provenance line on success" "every successful call" "$_writes_stderr"

# FACT — THE MERGE HAZARD that provenance line creates. Observed by actually merging the streams
# and handing the result to jq: if stdout+stderr no longer parses as JSON, both surfaces owe the
# reader the `2>&1` warning. This is the consumer-visible half of card#9171 — the pipeline that
# dies at `jq: parse error` on line 1 — and it is the fact this guard first RED on: README
# carried it and the help block did not.
_merged="$(cmd_stages 2>&1 || true)"
_merged_parses="$(jq -e . >/dev/null 2>&1 <<<"$_merged" && echo true || echo false)"
eq "observed: stdout+stderr merged does NOT parse as JSON" "false" "$_merged_parses"
eq "  control: stdout ALONE does parse, so the leg above measures the merge and not the JSON" \
   "true" "$(jq -e . >/dev/null 2>&1 <<<"$ROWS" && echo true || echo false)"
assert_fact "the 2>&1 merge hazard" "2>&1" \
   "$([[ "$_merged_parses" == false ]] && echo true || echo false)"

# FACT — THE NAME HALF IS THE VARIABLE SUFFIX, LOWERCASED. `KB_STAGE_TESTING` is deliberately not
# one of the eight `--column` aliases, so a row named `testing` can only have come from the
# variable's own suffix. ⭐ BOTH SUFFIX SHAPES ARE OBSERVED, because the claim has two halves and
# a single-token probe spans only one: `stage_name`'s fold widened from `tr '[:upper:]'
# '[:lower:]'` to `tr '[:upper:]_' '[:lower:]-'` prints `shipped-to-dev`, which makes both
# surfaces false while a `testing`-only probe stays true.
_suffix_rule="$(jq -r '((.[] | select(.id == 77) | .name) == "testing")
                   and ((.[] | select(.id == 49) | .name) == "in_progress")' <<<"$ROWS")"
eq "observed: a row's name is its KB_STAGE_* suffix, lowercased — single- AND multi-token" \
   "true" "$_suffix_rule"
assert_fact "the name derivation" "suffix, lowercased" "$_suffix_rule"

# FACT — NO ORDINAL. The absence is deliberate and documented as such, so the polarity is the
# absence: grow an ordinal key and the requirement flips to "do not say there is none".
_no_ordinal="$(jq -r 'map(has("ordinal") or has("position") or has("order")) | any | not' <<<"$ROWS")"
eq "observed: no row carries an ordinal/position/order key" "true" "$_no_ordinal"
assert_fact "the deliberate absence of an ordinal" "ordinal" "$_no_ordinal"

# FACT — ROW ORDER. No longer doc-side only: the fixture's ids disagree with its names, so this
# probe can answer NO. The behaviour pin proper lives in `kbcard-selftest.sh` (one owner); what is
# owed HERE is only that the polarity is live, so the witness below asserts the FIXTURE's
# discriminating power rather than re-pinning the verb. It is computed over the name-sorted
# projection, so it stays true under the very mutation it exists to make visible.
_sorted="$(jq -r '. == (. | sort_by(.name))' <<<"$ROWS")"
eq "observed: rows come out sorted by name" "true" "$_sorted"
eq "  …over a fixture that can answer NO (its id order disagrees with its name order)" "false" \
   "$(jq -r '[.[].id] == ([.[].id] | sort)' <<<"$(jq -c 'sort_by(.name)' <<<"$ROWS")")"
assert_fact "the row order" "sorted by name" "$_sorted"

# FACT — A VALUE THAT IS NOT A STAGE ID IS NAMED, NOT DROPPED, and `000` is that case on a real
# box: it is what `examples/kanban-board.env.example` ships as the not-yet-configured
# placeholder, which is why the placeholder itself is the needle.
export KB_STAGE_UNCONFIGURED=000
_ERR_000="$(cmd_stages 2>&1 >/dev/null)"
_names_000="$(has "KB_STAGE_UNCONFIGURED='000'" "$_ERR_000")"
eq "observed: the 000 placeholder is named on stderr" "true" "$_names_000"
eq "  …and is not listed as a row"                    "4" "$(cmd_stages 2>/dev/null | jq 'length')"
assert_fact "the 000 placeholder" "000" "$_names_000"
unset KB_STAGE_UNCONFIGURED

# FACT — THE EMPTY-MAP REFUSAL, with the rc taken from the call rather than written down: change
# the refusal to rc 2 and the needle becomes `rc 2`, which neither surface carries.
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}
rc=0; _EMPTY_OUT="$(cmd_stages 2>/dev/null)" || rc=$?
eq "observed: a board env mapping NO stage prints nothing on stdout" "" "$_EMPTY_OUT"
eq "  …and the rc is not 0 (a refusal, not an empty array)" "false" "$([[ "$rc" == 0 ]] && echo true || echo false)"
assert_fact "the empty-map refusal" "rc $rc" true

# ═══════════════════════ the no-request claim, through the real bin ═════════════════════════
#
# The headline claim of both ⚠ paragraphs — that this read issues no request — is a property of
# the PROCESS, not of a sourced function, so it is observed with a curl stand-in on PATH that
# would log any call and answer 500 to it.
echo "== no request is issued — observed through the bin, against a stub that would log one =="
# The ambient KB_STAGE_* this shell still carries would be read by the child too; the board env
# is the surface under observation here, so clear them and let the fixture file supply the map.
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}
kb_stub_reset
rc=0; _OUT="$("$BIN" stages 2>/dev/null)" || rc=$?
_reqs="$(kb_stub_total)"
eq "observed: the verb succeeds through the bin" "0" "$rc"
eq "observed: requests issued"                   "0" "$_reqs"
# CONTROL — the stub COUNTS. A verb that does reach the wire is logged, so `0` above is a
# measurement rather than a stub that was never wired up.
kb_stub_reset
"$BIN" show --task 1 >/dev/null 2>&1 || true
eq "control: a verb that DOES call the API is logged by the same stub" "false" \
   "$([[ "$(kb_stub_total)" == 0 ]] && echo true || echo false)"
assert_fact "the no-request claim" "no request is issued" \
   "$([[ "$_reqs" == 0 ]] && echo true || echo false)"
unset -f kb_stub_route

# ═══════════ `list`'s ROW PROJECTION — one authority, and no copy of it in this file ═════════
#
# ⛔ WHY THIS FACT IS NOT A ROW IN THE TABLE ABOVE, i.e. why per-key `assert_fact` calls would be
# a check that cannot fail. The stages row-key fact can go needle-per-key because its keys are
# quoted JSON on both surfaces (`"id"`), and a quoted needle is specific. `list`'s projection is
# published as PROSE — `id`, `name`, `swimlane_id`, `assigned_user_id`, … — and `_norm` strips the
# backticks, so a bare `id` needle matches inside `swimlane_id`, `external_id` AND
# `assigned_user_id`: every key would read as "present" on any surface that named any key at all.
#
# ⭐ SO THE INSTRUMENT IS AN ORDERED SEQUENCE COMPARISON, AND THE AUTHORITY IS THE EXECUTABLE.
# The emitted key order is read out of a LIVE projection at assert time; both prose copies are
# PARSED rather than restated here, and each must equal that sequence exactly. Nothing in this
# file — and, since card#9173's fifth round, nothing in `tests/kbcard-selftest.sh` either — types
# the key set, so there is no further copy left to drift: a key added to the projection reds both
# document legs until both documents name it, in the position the projection emits it.
#
# ⛔ THE DEFECT THIS WAS WRITTEN FOR WAS ALREADY LIVE, on the surface a reader meets FIRST.
# README published the projection as a **fixed** exhaustive list of TEN keys while the verb
# emitted TWELVE: `assigned_user_id` and `assignee` arrived with card#9169 and reached neither the
# prose nor any guard. The in-bin help WAS correct, and README's own § `kbcard patch --assign`
# said the opposite of its § `list` in the same file — so the wrong half was the half a consumer
# hits first, and what it told them was that the projection cannot answer "is this card already
# being worked", which is the exact question those two keys were added to answer.
#
# ⚠ ONE FAIL-CLOSED EDGE, NAMED SO IT IS NOT DIAGNOSED AS A BUG IN THIS FILE. If the rows ever
# carry DIFFERENT key sequences, the sequence leg below reds first and says so plainly, and the
# two document legs then red too — comparing against the concatenation of the distinct sequences,
# which is a confusing message for a correct refusal. That is the same intended shape as the
# ordinal fact above: the FIRST red names the cause, and nothing is permitted to pass.
#
# ORDER IS PART OF THE COMPARISON, deliberately, and it is the one coverage the widening round
# dropped: the pre-widening unit assertion compared `keys_unsorted` against an ordered literal and
# so pinned order too, while its replacement (`| keys | unique`) sorted both sides. Both documents
# publish the list in emission order, so requiring the sequence restores that pin — and restores
# it DERIVED, which a literal in a test file could never be.
echo "== \`list\`'s row projection — the emitted key sequence, and the two prose copies of it =="

# ── the two published copies, the ONE occurrence each is read at, and the parse ──────────────
#
# Each surface states the projection as a comma-separated run between two markers written in its
# own register. What is required of that, in order, each leg carrying its own refusal:
#   * the marker occurs EXACTLY ONCE          — `_require_unique_marker`
#   * the parse selects THAT occurrence       — `_projection_keys`, anchored rather than greedy
#   * what comes out are key NAMES            — `_require_keylist`
# The last one alone is not enough, and that gap is what card#9173's sixth round is: a marker
# that MOVED leaves a parse returning a whole sentence, which is loud; a marker that was COPIED
# leaves a parse returning a real-looking key list read off the wrong copy, which is silent.
HELP_MARKER=' projecting '
HELP_TAIL=' per card'
README_MARKER='row projection — '
README_TAIL=' —'

# _one_line <text> — the surface flattened to one line, runs of whitespace squeezed. The COUNT
# and the PARSE both read this, deliberately the same bytes: a count taken over text the parse
# does not read certifies nothing about what the parse selected.
_one_line() { tr '\n' ' ' <<<"$1" | tr -s ' ' | sed 's/^ *//; s/ *$//'; }

# _require_unique_marker <what> <text> <marker> — the marker occurs EXACTLY ONCE in <text>.
#
# ⛔ OCCURRENCES, NOT LINES, and that distinction IS the check rather than a detail of it.
# `grep -c` counts MATCHING LINES, and README publishes the whole projection inside ONE ~2 kB
# bullet on a single line — so a second copy planted in that line is `grep -c` 1, and the
# assertion built on it reported `ok` while the claim it was NAMED for ("in exactly ONE place")
# was false. That is this file's own recurring defect shape: the NAME spanned places, the
# PREDICATE spanned lines. The controls below pin both numbers over the same bytes, so this
# paragraph cannot go stale without a red.
#
# ⛔ AND IT RUNS BEFORE THE PARSE, not as a tidy-up after it. A second copy does not BREAK the
# parse — it makes the parse pick one silently, and the guard then certifies that one while the
# other copy publishes whatever it likes. A false green is strictly worse than a red here,
# because the surface a reader meets first is the one left unguarded.
_require_unique_marker() {
    local n
    n="$({ command grep -oF -- "$3" <<<"$2" || true; } | wc -l | tr -d '[:space:]')"
    [[ "$n" == 1 ]] && return 0
    bad "the $1 marker '$3' occurs $n time(s), not exactly once — the key list needs ONE published copy or this guard certifies whichever copy it happened to parse; fix the SURFACE, not $(basename "${BASH_SOURCE[0]}")"
    _summary "kbcard-contract-selftest"
}

# _projection_keys <one-line-text> <marker> <tail> — the comma-separated run between the two
# markers, one key per line. ONE parse for BOTH surfaces: the pair this replaced differed only
# in its two marker strings, and that second divergent copy is how the help side came to ship
# with no uniqueness leg at all while the README side carried one that was false.
#
# ⛔ `index`/`substr` ON THE FIRST OCCURRENCE — never `sed 's/.*<marker> //'`. sed's `.*` is
# leftmost-LONGEST, so that spelling silently selects the LAST occurrence: measured, a stale
# copy placed ABOVE the live one was invisible while the same copy placed BELOW it red. `index`
# is also LITERAL, so a marker carrying a regex metacharacter cannot quietly match elsewhere.
_projection_keys() {
    awk -v m="$2" -v t="$3" '
        { i = index($0, m); if (!i) next
          s = substr($0, i + length(m))
          j = index(s, t); if (j) s = substr(s, 1, j - 1)
          print s }' <<<"$1" \
        | tr -d '`' | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d'
}
# _joined <newline-list> — the same list on ONE line. The per-line form is what the token regex
# and the drop-a-key control need; the joined form is what the FAILURE MESSAGE needs, and a red
# nobody can read is a red nobody acts on.
_joined() { tr '\n' ' ' <<<"$1" | sed 's/ *$//'; }

# _require_keylist <what> <newline-list> — the parse refusal. ONE arm, reached two ways: a list
# that came out EMPTY, and a list carrying something that is not a key name. They print the same
# message; what differs is the upstream failure driving each.
#
# ⛔ `-n "$2"` CANNOT CHANGE THE OUTCOME FOR ANY INPUT, and is kept deliberately rather than
# deleted as dead. `<<<` feeds grep one EMPTY LINE for an empty list, and that line is itself an
# offender, so the offenders half already refuses empty — measured over empty / valid / invalid
# input, no value of `$2` makes the two spellings differ. Deleting the conjunct would leave the
# empty case riding on that here-string newline: swap `<<<"$2"` for a pipe and `grep -cv`
# answers 0 offenders on empty input, i.e. the guard would PASS an empty key list (measured).
# It stays as the explicit statement of the predicate, so an input-shape change cannot silently
# open the guard — NOT because the two halves are separately reachable. They are not.
_require_keylist() {
    local offenders
    offenders="$(command grep -cvE '^[a-z_][a-z0-9_]*$' <<<"$2" || true)"
    [[ -n "$2" && "$offenders" == 0 ]] && return 0
    bad "the $1 key list did not parse as key names — its marker moved; fix the extractor in $(basename "${BASH_SOURCE[0]}")"
    _summary "kbcard-contract-selftest"
}

# THE AUTHORITY. The projection is a pure function of its stdin, so it is driven directly; the
# curl stand-in installed at the top of this file stays on PATH as a backstop either way.
_PCARDS='[{"id":1,"name":"a","workflow_stage_id":48,"payload":{"dl_number":"DL-0007"}},
          {"id":2,"name":"b","workflow_stage_id":48,"payload":{}}]'
_PROJ="$(printf '%s' "$_PCARDS" | _kbc_list_project '' '' '' '')"
eq "observation precondition: the projection emitted more than one row to observe" "true" \
   "$([[ "$(jq 'length' <<<"$_PROJ")" -gt 1 ]] && echo true || echo false)"
# ⭐ NO `.[0]`. One derivation answers both questions at once — how many DISTINCT key sequences
# the rows carry (which must be exactly one, or "the order the projection emits" names nothing),
# and what that sequence is. Reading row 0 alone would span a population of one, which is the
# defect this card exists to close and which recurred inside the block that closed it.
eq "every row emits the SAME key sequence (so 'the order' names something)" "1" \
   "$(jq '[.[] | keys_unsorted] | unique | length' <<<"$_PROJ")"
EMITTED="$(jq -r '[.[] | keys_unsorted] | unique | add | .[]' <<<"$_PROJ")"

LIST_SPAN="$(_help_span "$HELP_TEXT" list)"
_require_span "rendered --help \`list\`" "$LIST_SPAN"
eq "the --help \`list\` span carries exactly ONE verb line — its own" "1" \
   "$(_block_opens "$LIST_SPAN" "$HELP_BLOCK_OPEN")"
HELP_LINE="$(_one_line "$LIST_SPAN")"
_require_unique_marker "rendered --help \`list\`" "$HELP_LINE" "$HELP_MARKER"
HELP_KEYS="$(_projection_keys "$HELP_LINE" "$HELP_MARKER" "$HELP_TAIL")"
_require_keylist "rendered --help \`list\`" "$HELP_KEYS"

# README publishes it in a BULLET rather than a `## ` section, so the anchor is the bullet's own
# words — and EVERY line carrying them is collected, never the first. Two different second
# copies have to reach the uniqueness leg and each is hidden by a different shortcut: a copy on
# ANOTHER line is hidden by `head -1`, and a copy WITHIN this one line is hidden by counting
# lines. Flattening first is what makes one count cover both.
README_BULLET="$(command grep -F -- "$README_MARKER" "$README" || true)"
_require_span "README \`list\` projection bullet" "$README_BULLET"
README_LINE="$(_one_line "$README_BULLET")"
_require_unique_marker "README \`list\` projection bullet" "$README_LINE" "$README_MARKER"
README_KEYS="$(_projection_keys "$README_LINE" "$README_MARKER" "$README_TAIL")"
_require_keylist "README \`list\` projection bullet" "$README_KEYS"

eq "the rendered --help publishes EXACTLY the emitted key sequence, in order" \
   "$(_joined "$EMITTED")" "$(_joined "$HELP_KEYS")"
eq "README publishes EXACTLY the emitted key sequence, in order" \
   "$(_joined "$EMITTED")" "$(_joined "$README_KEYS")"

# CONTROLS — one per way the legs above could pass for no reason, and the list is the block
# below rather than a number here. For the parse: garbage in, nothing in, and an equality that
# is not load-bearing. For the copy those could not see: a SECOND marker on each surface, plus
# the line-vs-occurrence discriminator that says WHY `grep -c` was the wrong instrument for it.
# Every one is watched to fire — a refusal nobody has seen fire is the decoration this round
# exists to stop shipping.
rc=0
( _require_keylist "x" "$(_projection_keys "$(_one_line "$(sed 's/ projecting / projectng /g' <<<"$LIST_SPAN")")" "$HELP_MARKER" "$HELP_TAIL")" ) \
    >/dev/null 2>&1 || rc=$?
eq "control: a moved --help marker is REFUSED, not parsed into a plausible wrong list" "1" "$rc"
rc=0
( _require_keylist "x" "$(_projection_keys "$(_one_line "$(sed 's/row projection — /row projektion — /g' <<<"$README_BULLET")")" "$README_MARKER" "$README_TAIL")" ) \
    >/dev/null 2>&1 || rc=$?
eq "control: a moved README marker is REFUSED the same way" "1" "$rc"
# …and the OTHER CAUSE that reaches that same one refusal, which the anchored parse would
# otherwise retire silently: a moved HEAD marker now yields NOTHING (awk skips the line) rather
# than a sentence, so driving `_require_keylist` on NOT-KEY-NAMES needs a mutation that leaves
# the head marker alone and moves the TAIL, running the parse on past the key list. Both causes
# land on the same arm and the same message — see `_require_keylist`'s own note.
rc=0
( _require_keylist "x" "$(_projection_keys "$HELP_LINE" "$HELP_MARKER" ' per crad')" ) \
    >/dev/null 2>&1 || rc=$?
eq "control: a moved --help TAIL marker runs the parse past the list and is REFUSED as not-key-names" "1" "$rc"
eq "control: a published list missing ONE key no longer matches the emitted sequence" "false" \
   "$([[ "$(_joined "$(command grep -v '^assignee$' <<<"$README_KEYS")")" == "$(_joined "$EMITTED")" ]] && echo true || echo false)"

# A SECOND COPY, planted the way each surface would really acquire one. The help plant is a
# stale sentence ABOVE the live one — the placement the old greedy parse skipped in silence —
# and the README plant is inside the bullet's SINGLE line, the placement a line count cannot
# see. Both are measured here rather than asserted in prose.
_HELP_TWO="$(printf '%s\n%s' "    Before card#9169 this was a JSON array projecting id, name, stage per card." "$LIST_SPAN")"
rc=0
( _require_unique_marker "x" "$(_one_line "$_HELP_TWO")" "$HELP_MARKER" ) >/dev/null 2>&1 || rc=$?
eq "control: a SECOND projecting-sentence in the --help \`list\` block is REFUSED — even placed ABOVE the live one" "1" "$rc"
_README_TWO="$(sed 's/$/ (Before card#9169 the row projection — id, name, stage — was shorter.)/' <<<"$README_BULLET")"
rc=0
( _require_unique_marker "x" "$(_one_line "$_README_TWO")" "$README_MARKER" ) >/dev/null 2>&1 || rc=$?
eq "control: a SECOND copy INSIDE README's single bullet line is REFUSED" "1" "$rc"
eq "control: …and \`grep -c\` answers 1 over those very bytes — the line count that reported ok" "1" \
   "$(command grep -cF -- "$README_MARKER" <<<"$_README_TWO")"
eq "control: …while the OCCURRENCE count over the same bytes answers 2 — the discriminator" "2" \
   "$({ command grep -oF -- "$README_MARKER" <<<"$_README_TWO" || true; } | wc -l | tr -d '[:space:]')"

_summary "kbcard-contract-selftest"
