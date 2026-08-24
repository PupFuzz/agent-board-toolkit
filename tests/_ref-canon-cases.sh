# shellcheck shell=bash
# _ref-canon-cases.sh — THE shared fixture for the one-decorated-integer rule, and the reason
# the toolkit can carry that rule in two runtimes without them drifting apart (card#7587).
#
# ⛔ WHY A FIXTURE AND NOT A SHARED PREDICATE. The rule is kanban DL-251's — a correlation ref
# must name ONE integer, optionally decorated (`^\D*(\d+)\D*$`) — and it is expressed TWICE in
# this toolkit, in two languages, and cannot be expressed once:
#   * BASH, `_kbc_require_ref_int` in `bin/kbcard`, at the MINT site (card#7536): it refuses to
#     WRITE a value no reader can agree about.
#   * JQ, the `def norm:` inside `bin/promote-released-cards`, at a READ site (card#7587): it
#     refuses to CORRELATE one, so the release sweep leaves such a card alone instead of
#     PATCHing it onto an unrelated pull request.
# jq cannot call the bash predicate, and `promote-released-cards` is a vendored standalone that
# must not even source `_kb-board-lib.sh`. A second expression of one rule is a drift risk, so
# what is shared is the TABLE: one list of values and one expected answer per value, asserted
# against both implementations by `tests/promote-ref-canon-selftest.sh`. Neither side owns it,
# so neither side can move without the other going red.
#
# ⚑ WHAT EACH SIDE IS HELD TO — they are not held to the same thing, and saying so is the point:
#   * the ACCEPT SET is shared and asserted on both. A value the mint site refuses must be a
#     value the reader correlates to nothing, and vice versa. That equality is the whole
#     anti-drift claim.
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
# ROW FORMAT — `<value>|<norm>|<numlist>`, `|` separated (no value contains one):
#   <value>    the stored / typed spelling. Passed through `printf %b`, so `\n` is an embedded
#              NEWLINE and `\t` a tab; no case carries a literal backslash.
#   <norm>     what the jq reader must answer. EMPTY means "not one integer" ⇒ correlates to
#              nothing ⇒ and therefore also means the bash mint site must REFUSE this value.
#   <numlist>  what the shipped-side normaliser must emit, space-separated, in order. EMPTY
#              means it emits nothing.
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
  '178|178|178'
  '#178|178|178'
  'PR-178|178|178'
  'PR-085|85|85'
  'DL-0253|253|253'
  '093|93|93'
  '(#12)|12|12'
  '7587|7587|7587'
  '0|0|0'
  '000|0|0'
  '  42  |42|42'
  # ⚠ THE SIGN IS NOT A SECOND RUN, and this row is a KNOWN-OPEN shape rather than an
  # endorsement (card#7536 reported it and did not close it): `-5` satisfies the rule the
  # board itself applies, so both sides accept it and the reader then drops the sign with the
  # rest of the decoration and correlates the card to PR 5. Refusing it means refusing a value
  # that rule accepts, which is a separate ruling. Pinned so that ruling cannot land silently.
  '-5|5|5'

  # --- NOT one integer: refused at the mint site, correlated to NOTHING by the reader.
  # The first three are the measured defect — pre-fix the reader answered 15 / 20260823 / 1234
  # and PATCHed the card onto whichever real ref that named.
  '1.5||1 5'
  '2026-08-23||2026 8 23'
  'PR 12 of 34||12 34'
  '1,5||1 5'
  'PR 1 of 5||1 5'
  '1.0e20||1 0 20'
  'v0.9.2||0 9 2'
  # An embedded NEWLINE. It is the case a `\A…\z` anchor and a `^…$` one can answer differently
  # under Oniguruma line-anchor semantics — but ⚠ NOT on jq 1.7, where they are measured
  # identical, so this row pins the VALUE (it correlates to nothing) and NOT the anchor
  # spelling; an `^…$` mutant of the reader is green on this row here.
  '1\n5||1 5'
  # No digits at all, and the empty stamp. Both correlate to nothing; the empty row is also
  # what a card with no such payload key reaches the reader as.
  'TBD||'
  '||'
  'v||'
)
