#!/usr/bin/env bash
# kbcard-stages-contract-selftest.sh — the drift pin for the `kbcard stages` interface contract,
# which is stated on TWO reader-facing surfaces and was held together by nothing (card#9173).
#
# THE TWO SURFACES, AND WHY NEITHER CAN BE DELETED. The contract is stated in `bin/kbcard`'s
# `Usage:` header — which IS the rendered help, printed by a bare `kbcard` — and again in
# `README.md` § `kbcard stages`. Canon #16 allows a restatement to be DELETED in favour of a
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
#   * NOTHING about any OTHER verb's help/README pair. The population of this file is `stages`.
#
# ⛔ THE BOUND, stated so a green run is not read as more than it is. A rewrite of either surface
# that preserves every needle while changing the meaning around it passes. A needle that appears
# in the span for an unrelated reason satisfies its fact. `sorted by name` is pinned to an
# observation the env expansion makes true incidentally (bash sorts `${!KB_STAGE_@}`), so that
# one fact's polarity cannot currently be flipped by a real code change — it is the doc-side
# half only, and `kbcard-selftest.sh` owns the behaviour-side leg. And the ordinal fact is blunt
# in the ADD direction: growing an ordinal key makes fact `row keys` require `"ordinal"` while
# fact `ordinal` requires it absent, so the pair is guaranteed to red — loudly and for a
# confusing reason, which is the intended fail-closed outcome, not a diagnosis.
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

# _help_span <rendered-help-text> — the `kbcard stages` block of the RENDERED help. Rendered, not
# read out of the source file: what a terminal user sees is the thing under contract, and the
# renderer strips one leading `# `, so this also proves the block is reachable in the output.
_help_span() {
    awk '
        /^  kbcard stages$/           { inside = 1; print; next }
        inside && /^  kbcard [a-z]/   { exit }
        inside                        { print }
    ' <<<"$1"
}

# _readme_span <path> — the `## `kbcard stages`` section of a README, to the next `## `.
_readme_span() {
    awk '
        /^## `kbcard stages`/ { inside = 1; print; next }
        inside && /^## /      { exit }
        inside                { print }
    ' "$1"
}

# _require_span <what> <text> — the extractor refusal. `exit 1`, not `return`: an empty span
# means the anchor moved, and every fact downstream would then measure the empty string.
_require_span() {
    [[ -n "$2" ]] && return 0
    printf 'selftest: the %s span came out EMPTY — its anchor moved; fix the extractor in %s\n' \
        "$1" "$(basename "${BASH_SOURCE[0]}")" >&2
    exit 1
}

echo "== the two surfaces are extractable, bounded, and refuse an empty span =="
HELP_TEXT="$("$BIN")"
HELP_SPAN="$(_help_span "$HELP_TEXT")"
README_SPAN="$(_readme_span "$README")"
_require_span "rendered --help" "$HELP_SPAN"
_require_span "README" "$README_SPAN"

eq "the --help span starts at the verb line"  "  kbcard stages" "$(head -n1 <<<"$HELP_SPAN")"
eq "the README span starts at the heading"    "true" \
   "$(has '## `kbcard stages`' "$(head -n1 <<<"$README_SPAN")")"
# BOUNDED, both — the terminator fired, so neither span carries the NEXT section's prose.
eq "the --help span stops before the next verb"   "false" "$(has 'kbcard search' "$HELP_SPAN")"
eq "the README span stops before the next section" "false" "$(has 'kbcard patch --assign' "$README_SPAN")"

# CONTROL — each extractor watched to go empty, and the refusal watched to fire, on the one
# mutation that breaks it. Without this the extractors are decorations: a pair that silently
# returned "" would let every fact below pass or fail for a reason that has nothing to do with
# the docs.
rc=0
( _require_span "x" "$(_help_span "$(sed 's/^  kbcard stages$/  kbcard stagez/' <<<"$HELP_TEXT")")" ) \
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
export KB_STAGE_BACKLOG=48 KB_STAGE_IN_PROGRESS=49 KB_STAGE_TESTING=77
ROWS="$(cmd_stages 2>/dev/null)"
eq "observation precondition: the verb emitted rows to observe" "3" "$(jq 'length' <<<"$ROWS")"

# FACT — THE ROW KEY SET. Derived per key: whatever keys the verb actually emits must be NAMED
# on both surfaces, so a key added to stdout cannot ship undocumented on either.
KEYS="$(jq -r '.[0] | keys[]' <<<"$ROWS")"
eq "observed: the row key set" "id name" "$(tr '\n' ' ' <<<"$KEYS" | sed 's/ $//')"
while read -r _k; do
    [[ -n "$_k" ]] || continue
    assert_fact "row key \"$_k\"" "\"$_k\"" true
done <<<"$KEYS"

# FACT — THE STDERR PROVENANCE LINE, on EVERY successful call. This is card#9171's own claim and
# the one the drift dropped: README described the pre-change output contract, so a consumer read
# the happy path as writing nothing to stderr.
ERR="$(cmd_stages 2>&1 >/dev/null)"
_writes_stderr="$([[ -n "$ERR" ]] && echo true || echo false)"
eq "observed: a successful call writes to stderr" "true" "$_writes_stderr"
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
# variable's own suffix.
_suffix_rule="$(jq -r '(.[] | select(.id == 77) | .name) == "testing"' <<<"$ROWS")"
eq "observed: a row's name is its KB_STAGE_* suffix, lowercased" "true" "$_suffix_rule"
assert_fact "the name derivation" "suffix, lowercased" "$_suffix_rule"

# FACT — NO ORDINAL. The absence is deliberate and documented as such, so the polarity is the
# absence: grow an ordinal key and the requirement flips to "do not say there is none".
_no_ordinal="$(jq -r 'map(has("ordinal") or has("position") or has("order")) | any | not' <<<"$ROWS")"
eq "observed: no row carries an ordinal/position/order key" "true" "$_no_ordinal"
assert_fact "the deliberate absence of an ordinal" "ordinal" "$_no_ordinal"

# FACT — ROW ORDER. Doc-side only; see the bound in the header.
_sorted="$(jq -r '. == (. | sort_by(.name))' <<<"$ROWS")"
eq "observed: rows come out sorted by name" "true" "$_sorted"
assert_fact "the row order" "sorted by name" "$_sorted"

# FACT — A VALUE THAT IS NOT A STAGE ID IS NAMED, NOT DROPPED, and `000` is that case on a real
# box: it is what `examples/kanban-board.env.example` ships as the not-yet-configured
# placeholder, which is why the placeholder itself is the needle.
export KB_STAGE_UNCONFIGURED=000
_ERR_000="$(cmd_stages 2>&1 >/dev/null)"
_names_000="$(has "KB_STAGE_UNCONFIGURED='000'" "$_ERR_000")"
eq "observed: the 000 placeholder is named on stderr" "true" "$_names_000"
eq "  …and is not listed as a row"                    "3" "$(cmd_stages 2>/dev/null | jq 'length')"
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

_summary "kbcard-stages-contract-selftest"
