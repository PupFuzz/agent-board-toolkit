# shellcheck shell=bash
# _ref-canon-cases.sh — THE shared fixture for the one-decorated-integer rule, and the reason
# the toolkit can carry that rule in two runtimes without them drifting apart (card#7587).
#
# ⛔ WHY A FIXTURE AND NOT A SHARED PREDICATE. The rule is kanban DL-251's — a correlation ref
# must name ONE integer, optionally decorated (`^\D*(\d+)\D*$`) — and it is expressed in TWO
# LANGUAGES in this toolkit, and cannot be expressed once:
#   * BASH, `_kbc_require_ref_int` in `bin/kbcard`, at the MINT site (card#7536): it refuses to
#     WRITE a value no reader can agree about.
#   * JQ, at every READ site, where refusing means the stored stamp correlates to NOTHING and
#     the tool leaves the card alone. The jq text exists TWICE — once as `KB_JQ_REF_CANON` in
#     `bin/_kb-board-lib.sh`, which every lib-sourcing reader prepends to its own filter
#     (card#7592; which readers those are is DERIVED by the census in the selftest named below,
#     never counted here), and once inline as the `def norm:` in `bin/promote-released-cards`
#     (card#7587), a vendored standalone that must not even source the lib and so cannot read
#     the constant.
#     ⚑ Those two jq texts are asserted BYTE-IDENTICAL by `tests/reader-ref-canon-selftest.sh`
#     — a copy that cannot be removed is pinned instead of tolerated.
# jq cannot call the bash predicate. A second expression of one rule is a drift risk, so what is
# shared is the TABLE: one list of values and one expected answer per value. Neither side owns
# it, so neither side can move without the other going red. TWO selftests consume it and the
# split is by SUBJECT, not by coverage: `tests/promote-ref-canon-selftest.sh` holds the
# standalone plus the mint site (including the `numlist` column, which only that bin has), and
# `tests/reader-ref-canon-selftest.sh` holds the shared lib constant and the bins that prepend
# it. Both run the whole table.
#
# ⚑ WHAT EACH SIDE IS HELD TO — they are not held to the same thing, and saying so is the point:
#   * CONTAINMENT, in one direction, is the invariant: every value the MINT site accepts must be
#     one the READER correlates. A stamp `kbcard` wrote that the release sweep then silently
#     skips is the defect that ordering exists to prevent, and it is asserted as such.
#   * ⚠ EQUALITY IS NOT THE INVARIANT, and this fixture's FIRST run said so. Card#7536 narrowed
#     the MINT site below the board's own rule — `--pr` now refuses a NEGATIVE value and `0`,
#     for reasons that belong to the write site (there is no PR 0, and a stored `-5` keeps its
#     sign while every reader drops it) — while this READER is pinned to the rule the board
#     itself applies and correlates both. So the mint site is strictly NARROWER, which is the
#     safe ordering. The divergent rows are TAGGED below, one reason each, and the selftest
#     asserts the divergence set is EXACTLY the tagged one: a new divergence that nobody named
#     reds, which is the anti-drift claim that survives the two sides ruling differently.
#   * the CANONICAL FORM is asserted on the jq side only. `kbcard` stores the operator spelling
#     verbatim (`#178` travels as `#178`); it is a predicate, not a normaliser, and has no
#     canonical form to compare. Asserting one there would be inventing a behaviour to test.
#
# ⚑ THE THIRD COLUMN IS A DIFFERENT RULE ON PURPOSE. `numlist` in `bin/promote-released-cards`
# normalises the SHIPPED side of the same comparison and SPLITS a multi-run value into one
# candidate ref per run, where `norm` refuses it outright. That divergence is deliberate (the
# reasoning is in the bin, above `numlist`), and it used to be an unstated one behind a comment
# claiming the two sides were "the same rule, kept in sync". It is pinned here so it stays a
# decision rather than becoming an accident: a change that makes the two sides agree, or makes
# them disagree somewhere new, reds this table.
#
# ROW FORMAT — `<value>|<norm>|<numlist>|<mint>`, `|` separated (no value contains one):
#   <value>    the stored / typed spelling. Passed through `printf %b`, so `\n` is an embedded
#              NEWLINE and `\t` a tab; no case carries a literal backslash.
#   <norm>     what the jq reader must answer. EMPTY means "not one integer" ⇒ correlates to
#              nothing ⇒ the card is left alone.
#   <numlist>  what the shipped-side normaliser must emit, space-separated, in order. EMPTY
#              means it emits nothing.
#   <mint>     what the bash mint predicate must answer — `accept`, or `refuse-<reason>`. A
#              `refuse-*` row whose <norm> is NON-EMPTY is a DECLARED divergence between the two
#              sides; the reason tag is the whole record of why, and an undeclared one reds.
#
# ⛔ ASCII-ONLY POPULATION, deliberately. `numlist` matches with the RANGE `[0-9]`, which a
# UTF-8 collation widens (measured: under en_US.UTF-8 `DL-4<U+0663>` yields the ref `4<U+0663>`,
# under C it yields `4`), so a non-ASCII row would make the third column depend on the ambient
# locale of whoever runs the suite. The two implementations this fixture exists to keep aligned
# both use a NEGATED ASCII set and are locale-invariant; the selftest asserts the non-ASCII
# cases against those two directly, outside this table, and `tests/locale-range-guard-selftest.sh`
# owns the range-widening class itself.
REF_CANON_CASES=(
  # --- ONE integer: accepted by the mint site, correlated by the reader. These are the
  # BEHAVIOUR-NEUTRALITY population — every one of them answered exactly this before the
  # card#7587 guard existed, which the selftest asserts against the pre-fix expression itself.
  '178|178|178|accept'
  '#178|178|178|accept'
  'PR-178|178|178|accept'
  'PR-085|85|85|accept'
  'DL-0253|253|253|accept'
  '093|93|93|accept'
  '(#12)|12|12|accept'
  '7587|7587|7587|accept'
  # ⚠ DECLARED DIVERGENCE — the reader correlates these, the mint site refuses them. `0` is one
  # integer under the rule the board applies, so the reader answers `0`; card#7536 refuses it at
  # the WRITE site because GitHub numbers PRs and issues from 1, so there is nothing to
  # correlate to. Harmless in the safe direction: no release ever ships a ref `0` for the
  # reader to match `0` against.
  '0|0|0|refuse-zero'
  '000|0|0|refuse-zero'
  '  42  |42|42|accept'
  # ⚠ DECLARED DIVERGENCE, and the OPEN one. The sign is not a second run, so `-5` satisfies the
  # rule the board itself applies and this reader correlates the card to PR **5** — a real but
  # different ref, which is this card#7587 defect one property over. Card#7536 closed it at the
  # MINT site only; closing it HERE means narrowing the reader BELOW the board's own rule, which
  # is a separate ruling nobody has made, so the reader is left at the rule it implements and
  # the divergence is declared instead of hidden. ⛔ A pre-existing `-5` stamp — written before
  # that mint guard, or by the board UI / any other writer — still correlates to PR 5 here.
  '-5|5|5|refuse-negative'

  # --- NOT one integer: refused at the mint site, correlated to NOTHING by the reader.
  # The first three are the measured defect — pre-fix the reader answered 15 / 20260823 / 1234
  # and PATCHed the card onto whichever real ref that named.
  '1.5||1 5|refuse-multirun'
  '2026-08-23||2026 8 23|refuse-multirun'
  'PR 12 of 34||12 34|refuse-multirun'
  '1,5||1 5|refuse-multirun'
  'PR 1 of 5||1 5|refuse-multirun'
  '1.0e20||1 0 20|refuse-multirun'
  'v0.9.2||0 9 2|refuse-multirun'
  # An embedded NEWLINE. It is the case a `\A…\z` anchor and a `^…$` one can answer differently
  # under Oniguruma line-anchor semantics — but ⚠ NOT on jq 1.7, where they are measured
  # identical, so this row pins the VALUE (it correlates to nothing) and NOT the anchor
  # spelling; an `^…$` mutant of the reader is green on this row here.
  '1\n5||1 5|refuse-multirun'
  # No digits at all, and the empty stamp. Both correlate to nothing; the empty row is also
  # what a card with no such payload key reaches the reader as.
  'TBD|||refuse-nodigits'
  '|||refuse-nodigits'
  'v|||refuse-nodigits'
)
