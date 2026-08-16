#!/usr/bin/env bash
# fetch-board-cards-caller-claims-selftest.sh — a STATIC guard on what a CONSUMER of
# `fetch_board_cards` is allowed to CLAIM in its failure message.
#
# THE RULE IS NOT STATED HERE. It is stated once, at `fetch_board_cards`' header in
# `bin/_kb-board-lib.sh`, beside the rc contract it is derived from. This file owns the
# per-consumer DISPOSITIONS — which rcs reach which arm, and therefore which arms may
# name a cause — and asserts them. Neither restates the other.
#
# WHY IT EXISTS. Giving the paginator's rc 1 a third cause (card#6594) falsified five
# caller messages that had enumerated the old two. They were then corrected ONE SITE PER
# ROUND, for three rounds, each round's own report finding another — the sixth was
# board-card-start's arm, which round 1 had itself rewritten into the wrong shape. Every
# individual fix was correct, reviewed and green, which is exactly what made the miss
# comfortable. Nothing in the suite could see the class, so the class was rediscovered by
# reading instead of by CI. This test is that missing leg.
#
# WHY STATIC, AND WHY A REGISTRY. Which rcs reach a given arm is NOT statically derivable
# (a bare `||` catches all four, an `rc=$?` + case arm catches a subset, an `-eq 1` guard
# catches exactly one), so the arity is MEASURED — by driving each real bin as a process
# against a stubbed curl over all seven paginator outcomes — and recorded below. What IS
# derivable is the POPULATION: the invocation list is re-derived from the tree on every
# run and compared against the registry, so a new consumer, a new call inside an existing
# consumer, or a moved call REDS until it is ruled on. A registry that only listed sites
# would rot; one whose denominator is re-derived cannot.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$HERE/.."
LIB="$ROOT/bin/_kb-board-lib.sh"
_need -r "$LIB"

# ---------------------------------------------------------------------------
# The two predicates. NAMES_RC must see an EXPANDED rc (`rc=$…`), not a literal — a
# hardcoded number on an arm that catches four rcs is wrong three times out of four.
NAMES_RC='rc=\$'
# CAUSE vocabulary — WHY the read failed. Deliberately excludes the shared-OUTCOME words
# ("did not return a complete card list", "INCOMPLETE", "partial", "unavailable"): those
# hold for every non-zero rc, so they are true on a multi-rc arm and the rule permits
# them. "short read" IS a cause (it is rc 4 alone), so it is listed.
NAMES_CAUSE='no response|non-2xx|no card array|unreachable|page cap|PAGE_CAP|page-fetch|page fetch|short read|auth rejected|transport|token'

# HERESTRING rather than `printf | grep -q`: under `pipefail` a `grep -q` that matches exits
# before its writer finishes, and the writer's SIGPIPE can become the PIPELINE's status — so a
# MATCH reads as a non-match. Measured honestly: bash's printf BUILTIN does not die on SIGPIPE
# (rc 0 over a 5MB body), so the pipe form was not in fact leaking here — but the same shape
# with an external writer does (rc 141, `yes | head -c 50M | grep -q x`), and a classifier
# whose correctness rests on which writer bash happens to use is not one to leave standing.
is_rc()    { grep -qE "$NAMES_RC"    <<<"$1"; }
is_cause() { grep -qE "$NAMES_CAUSE" <<<"$1"; }

# ---------------------------------------------------------------------------
echo "== the predicates discriminate (controls — a check that cannot fail is a decoration) =="
# NEGATIVE CONTROL, pinned to the exact failure this guard exists to prevent: the wording
# bin/board-card-start carried until card#6594's class round. If this ever passes, the
# guard has stopped seeing the defect it was built for.
_BAD_HISTORICAL='board $board fetch failed (no response, a non-2xx status, or a 2xx carrying no card array)'
is_cause "$_BAD_HISTORICAL" && ok "the pre-fix board-card-start wording is seen as cause-naming" \
                            || bad "the pre-fix board-card-start wording was NOT flagged — the cause predicate is broken"
is_rc "$_BAD_HISTORICAL" && bad "the pre-fix wording must not read as rc-naming" \
                         || ok "the pre-fix board-card-start wording names no rc"
# POSITIVE CONTROL: the shape the rule prescribes.
_GOOD='board $board did not return a complete card list (fetch rc=$rc)'
is_rc "$_GOOD"    && ok "the prescribed shape reads as rc-naming"    || bad "the prescribed shape did not read as rc-naming"
is_cause "$_GOOD" && bad "the prescribed shape must name no cause"   || ok "the prescribed shape names no cause"
# OUTCOME-WORD CONTROL: a shared outcome is permitted on a multi-rc arm. Without this the
# predicate would demand a rewrite of board-stats' already-conforming INCOMPLETE line.
_OUTCOME='card snapshot INCOMPLETE (fetch rc=$rc) — every stock count below is a floor, not a total'
is_cause "$_OUTCOME" && bad "a shared OUTCOME word must not be read as a cause" \
                     || ok "a shared OUTCOME word (INCOMPLETE) is not read as a cause"
# LITERAL-RC CONTROL: a hardcoded rc is not naming the rc this run took.
is_rc 'board read failed (fetch rc=1)' && bad "a hardcoded rc must not satisfy the rc predicate" \
                                       || ok "a hardcoded rc does not satisfy the rc predicate"

# ---------------------------------------------------------------------------
# THE REGISTRY — the derived table. One row per ARM, tab-separated:
#   <file>  <arity: one|many>  <message literal, as written in the file>
# `arity` is the count of paginator rcs MEASURED reaching that arm, driving each real bin
# as a process against a stubbed curl: rc 1 via all three of its causes (curl transport
# failure, HTTP 403, a 200 carrying `<html>502</html>`), rc 2 via a page-2 HTTP 500, rc 3
# via the page cap, rc 4 via meta.total exceeding the delivered rows.
#
#   bin/kbcard             list          rc 1,2,3,4  (bare `||`)
#   bin/kbcard             archive twin  rc 1,2,3,4  — `|| true`, NO arm and no claim
#   bin/board-snapshot                   rc 1,2      (`rc=$?`; 0/3/4 render instead)
#   bin/board-stats        case 3|4      rc 3,4
#   bin/board-stats        case *        rc 1,2
#   bin/next-dl            `-eq 1` arm   rc 1 ONLY   — the one arm allowed to name causes
#   bin/next-dl            fall-through  rc 2,3,4
#   bin/dl-a0-backfill…                  rc 1,2,3,4  (bare `||`)
#   bin/board-card-start                 rc 1,2,3,4  (bare `||`)
REGISTRY=$'bin/kbcard\tmany\tkbcard: board $KB_BOARD_ID did not return a complete card list (fetch rc=$frc)
bin/board-snapshot\tmany\t• ${label}: (board read failed — fetch rc=$rc)
bin/board-stats\tmany\tcard snapshot INCOMPLETE (fetch rc=$rc) — every stock count below is a floor, not a total
bin/board-stats\tmany\tcard snapshot unavailable (fetch rc=$rc) — this board\'s stock section is missing
bin/next-dl\tone\tnext-dl: board $board could not be read (no response, a non-2xx status, or a 2xx carrying no card array) — skipping board check
bin/next-dl\tmany\tnext-dl: board $board did not return a complete card list (fetch rc=$rc) — refusing to mint from a partial scan (could re-mint a used DL)
bin/dl-a0-backfill-triaged\tmany\t$KB_PROG: board $KB_BOARD_ID did not return a complete card list (fetch rc=$fetch_rc) — aborting (no partial backfill)
bin/board-card-start\tmany\tboard $board did not return a complete card list (fetch rc=$?)'

# The consumer FILES the registry accounts for. A file carrying an invocation but no arm
# (kbcard's archive twin check swallows every rc with `|| true` and claims nothing) is
# still a disposition and must be listed, or the denominator leg below cannot close.
REGISTERED_FILES=$'bin/board-card-start\nbin/board-snapshot\nbin/board-stats\nbin/dl-a0-backfill-triaged\nbin/kbcard\nbin/next-dl'
# Invocations per consumer file — so a NEW call added inside an already-registered bin
# (the way kbcard grew its second one) cannot slip in behind a satisfied file set.
REGISTERED_CALLS=$'bin/board-card-start\t1\nbin/board-snapshot\t1\nbin/board-stats\t1\nbin/dl-a0-backfill-triaged\t1\nbin/kbcard\t2\nbin/next-dl\t1'

# ---------------------------------------------------------------------------
echo "== the population is RE-DERIVED, never recalled (denominator) =="
# The derivation, run fresh here: every invocation of the paginator outside its definition.
# `|| true`: a derivation that matches NOTHING must land on the assertions below (which red,
# loudly, including the >= 6 control) rather than abort the run under `set -e` with no verdict.
derived_calls="$( (cd "$ROOT" && grep -rc 'fetch_board_cards "' bin/ hooks/ 2>/dev/null \
                 | awk -F: '$2 > 0 && $1 != "bin/_kb-board-lib.sh" {print $1"\t"$2}' | sort) || true)"
eq "the derived per-consumer invocation counts equal the registry's" \
   "$(printf '%s' "$REGISTERED_CALLS" | sort)" "$derived_calls"
derived_files="$(printf '%s\n' "$derived_calls" | cut -f1 | sort -u)"
eq "the derived consumer FILE set equals the registry's" \
   "$(printf '%s' "$REGISTERED_FILES" | sort -u)" "$derived_files"
# Control: the derivation must be able to SEE a consumer — an empty derived set would
# satisfy nothing above by accident, but it would satisfy a future edit that broke grep.
[[ "$(printf '%s\n' "$derived_files" | wc -l)" -ge 6 ]] \
    && ok "the derivation actually found the consumers (>= 6 files)" \
    || bad "the derivation found almost nothing — the grep, not the tree, is what changed"

# ---------------------------------------------------------------------------
echo "== every registered arm is still in the tree, verbatim =="
# A reword that does not update this registry REDS. That is the point: the next wording
# change has to be RULED ON rather than merely made.
while IFS=$'\t' read -r file arity msg; do
    [[ -n "$file" ]] || continue
    eq "$file: the registered arm text is present [${msg:0:46}…]" "true" \
       "$(has "$msg" "$(cat "$ROOT/$file")")"
done <<< "$REGISTRY"

# ---------------------------------------------------------------------------
echo "== the rule: a MULTI-rc arm names the rc and NO cause =="
while IFS=$'\t' read -r file arity msg; do
    [[ "$arity" == "many" ]] || continue
    is_rc "$msg"    && ok "$file: names the rc [${msg:0:46}…]"     || bad "$file: a multi-rc arm must name the rc — '$msg'"
    is_cause "$msg" && bad "$file: a multi-rc arm must name NO cause — '$msg'" \
                    || ok "$file: names no cause [${msg:0:46}…]"
done <<< "$REGISTRY"

echo "== the rule: a SINGLE-rc arm may name that rc's causes — and names the contract's set =="
# next-dl's `[[ $rc -eq 1 ]]` arm is the only one gated to one rc, so it is the only one
# that may name causes. It must name ALL THREE the rc-1 contract lists: an arm naming two
# of three is the card#6594 defect itself, in its original form.
one_rc="$(printf '%s\n' "$REGISTRY" | awk -F'\t' '$2 == "one" {print $3}')"
eq "exactly one arm in the tree is rc-gated" "1" "$(printf '%s\n' "$one_rc" | grep -c .)"
for cause in 'no response' 'a non-2xx status' 'a 2xx carrying no card array'; do
    eq "the rc-1 arm names the contract cause '$cause'" "true" "$(has "$cause" "$one_rc")"
done

# ---------------------------------------------------------------------------
echo "== the rule has an owner, and the owner still states it =="
lib="$(cat "$LIB")"
eq "fetch_board_cards' header owns the wording rule"        "true" "$(has 'HOW A CALLER WORDS ITS FAILURE MESSAGE' "$lib")"
eq "…and states the multi-rc half explicitly"               "true" "$(has 'an arm reached by MORE THAN ONE rc names the rc' "$lib")"
eq "…and points at this test as the dispositions' owner"    "true" "$(has 'fetch-board-cards-caller-claims-selftest.sh' "$lib")"
# The rc contract the rule is derived from must still enumerate rc 4 — the rc a second,
# drifted copy of that contract had lost, and the one every bare `||` arm silently catches.
eq "the rc contract still enumerates rc 4 (SHORT READ)"     "true" "$(has '4  SHORT READ' "$lib")"
# ONE contract, not two: the compact duplicate that had drifted must not come back.
eq "there is no second copy of the rc contract in the header" "0" \
   "$(printf '%s\n' "$lib" | grep -c 'rc contract: 0 complete')"

# ---------------------------------------------------------------------------
_summary "fetch-board-cards-caller-claims-selftest"
