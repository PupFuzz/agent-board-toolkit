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
# derivable is the POPULATION, and BOTH halves of it are derived here: the consumer files
# and their invocation counts, AND the arms attached to those invocations. A registry
# whose members were merely listed would rot; every member below is compared against a
# fresh derivation on every run, so a new consumer, a new call inside an existing
# consumer, a new arm at an already-registered call, or a reworded arm REDS until it is
# ruled on.
#
# ⚠ WHAT THIS TEST DOES NOT SEE — stated because a guard that reads as total and is not
# is worse than a narrow one. Both bounds were chosen, not discovered:
#   - the arm derivation looks ARM_WINDOW code lines past a call. An arm further away
#     than that is invisible. Existing arms cannot silently drift out of the window —
#     the "every registered arm is in the DERIVED set" leg reds if one does — but a NEW
#     arm placed beyond it would pass.
#   - an arm is recognised by an emitter vocabulary (echo / printf / bcs_skip /
#     kb_bcs_log / an array append / a `>&2` redirect). An arm emitting through some
#     other helper would pass.
#   - COMMENTS are not covered at all. The wording rule binds a caller-side comment that
#     states which rcs reach an arm (the rule's third clause) and nothing here checks
#     one: prose beside an arm is checked by reading. The rule exists to make that
#     reading cheap, not to make it unnecessary.
#   - the population is bin/ and hooks/ — the shipped consumer surface. A consumer
#     elsewhere in the tree is out of the denominator by construction.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$HERE/.."
LIB="$ROOT/bin/_kb-board-lib.sh"
_need -r "$LIB"

# ---------------------------------------------------------------------------
# The message predicates. NAMES_RC must see an EXPANDED rc (`rc=$…`), not a literal — a
# hardcoded number on an arm that catches four rcs is wrong three times out of four.
NAMES_RC='rc=\$'
# CAUSE vocabulary — WHY the read failed. Deliberately excludes the shared-OUTCOME words
# ("did not return a complete card list", "INCOMPLETE", "partial", "unavailable"): those
# hold for every non-zero rc, so they are true on a multi-rc arm and the rule permits
# them. "short read" IS a cause (it is rc 4 alone), so it is listed.
#
# ⚠ THIS IS A SCREEN, NOT A CLASSIFIER. It is a deny-list, so a cause worded in terms it
# does not list passes it. That is survivable only because it is not the guarantee: every
# arm is ALSO pinned VERBATIM below and derived from the tree, so a novel cause word
# cannot enter without changing text this file reds on until a human rules on it. It was
# NOT inverted into a pure allow-list of permitted wordings, and the reason is concrete:
# these messages carry tool-specific POLICY prose ("refusing to mint from a partial scan",
# "aborting (no partial backfill)") which no closed vocabulary can enumerate without
# rejecting the next legitimate one. What IS closed, and is now asserted as an allow-list
# on its own leg, is the OUTCOME half — see NAMES_OUTCOME.
NAMES_CAUSE='no response|non-2xx|no card array|unreachable|page cap|PAGE_CAP|page-fetch|page fetch|short read|auth rejected|transport|token|timed out|timeout|refused|DNS|TLS|certificate|rate limit|HTTP [0-9]'
# OUTCOME vocabulary — WHAT happened, the half that IS closed: every phrasing a multi-rc
# arm may use to say the read was not whole. All four members are in the tree today, so
# this constrains the next arm rather than describing the current ones; a new arm reaching
# for a fifth phrasing reds until the phrasing is ruled on and added here.
NAMES_OUTCOME='did not return a complete card list|INCOMPLETE|unavailable|read failed'

# HERESTRING rather than `printf | grep -q`: under `pipefail` a `grep -q` that matches exits
# before its writer finishes, and the writer's SIGPIPE can become the PIPELINE's status — so a
# MATCH reads as a non-match. Measured honestly: bash's printf BUILTIN does not die on SIGPIPE
# (rc 0 with the match at byte 0 of a 5MB body, and of a 50MB one), so the pipe form was not in
# fact leaking here — but the same shape with an EXTERNAL writer does:
# `yes | head -c 50M | grep -q y` is rc 141, a match reported as a failure.
# ⚠ The command this line cited until card#6680 was `grep -q x`, and it is rc 1, NOT 141 —
# `yes` emits no `x`, so that grep never matches, never exits early, and drains all 50MB
# instead, leaving its own rc 1 as the rightmost non-zero status. It could not demonstrate the
# thing it was quoted for: the shape needs the reader to MATCH while the writer is still
# writing, which is the defect itself. Corrected to the command that was actually measured.
# A classifier whose correctness rests on which writer bash happens to use is not one to leave
# standing.
is_rc()      { grep -qE "$NAMES_RC"      <<<"$1"; }
is_cause()   { grep -qE "$NAMES_CAUSE"   <<<"$1"; }
is_outcome() { grep -qE "$NAMES_OUTCOME" <<<"$1"; }

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
is_rc "$_GOOD"      && ok "the prescribed shape reads as rc-naming"      || bad "the prescribed shape did not read as rc-naming"
is_cause "$_GOOD"   && bad "the prescribed shape must name no cause"     || ok "the prescribed shape names no cause"
is_outcome "$_GOOD" && ok "the prescribed shape names a ruled outcome"   || bad "the prescribed shape did not name a ruled outcome"
# OUTCOME-WORD CONTROL: a shared outcome is permitted on a multi-rc arm. Without this the
# predicate would demand a rewrite of board-stats' already-conforming INCOMPLETE line.
_OUTCOME='card snapshot INCOMPLETE (fetch rc=$rc) — every stock count below is a floor, not a total'
is_cause "$_OUTCOME" && bad "a shared OUTCOME word must not be read as a cause" \
                     || ok "a shared OUTCOME word (INCOMPLETE) is not read as a cause"
# ALLOW-LIST CONTROL: a message that names a NOVEL cause and no ruled outcome — the exact
# hole the deny-list alone leaves open — must fail the outcome leg. This is what makes the
# two halves complementary rather than one screen stated twice.
_NOVEL='board $board timed out or was refused by the server (fetch rc=$rc)'
is_outcome "$_NOVEL" && bad "a novel-cause message must not satisfy the outcome allow-list" \
                     || ok "a novel-cause message fails the outcome allow-list"
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
#   bin/kbcard             search        rc 1,2,3,4,5 (bare `||`; measured by
#                                        tests/kbcard-selftest.sh, which drives all FIVE
#                                        through the verb — rc 5 is the search term's own
#                                        encode refusal and is reachable at no other call,
#                                        since it fires only when a query was passed)
#   bin/kbcard             archive twin  rc 1,2,3,4  — `|| true`, NO arm and no claim
#   bin/kbcard             field census  rc 1,2,3,4  (`rc=$?` + `-ne 0`; measured by
#                                        tests/kbcard-field-selftest.sh, which drives all
#                                        four rcs through the census and asserts rc 1 on
#                                        each, against a complete-read positive control)
#   bin/board-snapshot                   rc 1,2      (`rc=$?`; 0/3/4 render instead)
#   bin/board-stats        case 3|4      rc 3,4
#   bin/board-stats        case *        rc 1,2
#   bin/next-dl            `-eq 1` arm   rc 1 ONLY   — the one arm allowed to name causes
#   bin/next-dl            fall-through  rc 2,3,4
#   bin/dl-a0-backfill…                  rc 1,2,3,4  (bare `||`)
#   bin/board-card-start                 rc 1,2,3,4  (bare `||`)
REGISTRY=$'bin/kbcard\tmany\tkbcard: board $KB_BOARD_ID did not return a complete card list (fetch rc=$frc)
bin/kbcard\tmany\tkbcard: board $KB_BOARD_ID did not return a complete card list for this search (fetch rc=$frc) — refusing to present a partial match set as a whole one
bin/kbcard\tmany\tkbcard: board $KB_BOARD_ID did not return a complete card list (fetch rc=$rc) — refusing to act on a truncated denominator
bin/board-snapshot\tmany\t• ${label}: (board read failed — fetch rc=$rc)
bin/board-stats\tmany\tcard snapshot INCOMPLETE (fetch rc=$rc) — every stock count below is a floor, not a total
bin/board-stats\tmany\tcard snapshot unavailable (fetch rc=$rc) — this board\'s stock section is missing
bin/next-dl\tone\tnext-dl: board $board could not be read at all (no response, a non-2xx status, or a 2xx carrying no card array) — refusing to mint from the local scan alone (would drop this board\'s DL floor and could re-mint a used DL)
bin/next-dl\tmany\tnext-dl: board $board did not return a complete card list (fetch rc=$rc) — refusing to mint from a partial scan (could re-mint a used DL)
bin/dl-a0-backfill-triaged\tmany\t$KB_PROG: board $KB_BOARD_ID did not return a complete card list (fetch rc=$fetch_rc) — aborting (no partial backfill)
bin/board-card-start\tmany\tboard $board did not return a complete card list (fetch rc=$?)'

# The consumer FILES the registry accounts for. A file carrying an invocation but no arm
# (kbcard's archive twin check swallows every rc with `|| true` and claims nothing) is
# still a disposition and must be listed, or the denominator leg below cannot close.
REGISTERED_FILES=$'bin/board-card-start\nbin/board-snapshot\nbin/board-stats\nbin/dl-a0-backfill-triaged\nbin/kbcard\nbin/next-dl'
# Invocations per consumer file — so a NEW call added inside an already-registered bin
# (the way kbcard grew its second one) cannot slip in behind a satisfied file set.
REGISTERED_CALLS=$'bin/board-card-start\t1\nbin/board-snapshot\t1\nbin/board-stats\t1\nbin/dl-a0-backfill-triaged\t1\nbin/kbcard\t4\nbin/next-dl\t1'
# EMITTING lines the derivation finds in an arm window that are NOT paginator arms, each
# ruled on here rather than filtered out by a cleverer predicate — the exemption is the
# ruling, and a new one cannot appear without reding this file first. Tab-separated
# <file> <line text, leading whitespace stripped>.
#   bin/kbcard — `list`'s own stdout render of the projected board, three code lines
#   past the arm it shares a window with. Not a failure arm and makes no claim.
#   bin/kbcard — the field census's own jq PROJECTION failure, in the window after the
#   same call. It fires on a read the paginator returned rc 0 for, so it is not a
#   paginator arm at all and names no rc and no cause of one; what it claims is what
#   happened — this bin's own filter over a complete board did not produce a census.
#   bin/kbcard — `search`'s two ZERO-RESULT lines, in the window after its call. Both fire
#   on a read the paginator returned rc 0 for, and each is a statement about the match set
#   that COMPLETE read returned: nothing matched, or the query's matches were all removed by
#   the client-side filter flags. Neither names an rc or a cause, and neither could be
#   reached by a failed read — the arm above exits 1 first.
EXEMPT_EMITS=$'bin/kbcard\tprintf \'%s\\n\' "$out"\nbin/kbcard\techo "kbcard: board $KB_BOARD_ID read could not be projected for key \'$key\'" >&2\nbin/kbcard\techo "kbcard: no card on board $KB_BOARD_ID matched this search"\nbin/kbcard\techo "kbcard: the query matched $total card(s) on board $KB_BOARD_ID, none of which passed the filter flags"'

# ---------------------------------------------------------------------------
# THE DERIVATION — one primitive answering both questions, re-run here, never recalled.
#
# A CALL is the identifier `fetch_board_cards` on a line that is not a whole-line comment,
# in any regular file under bin/ or hooks/ other than the lib that defines it. The
# predicate is a WORD BOUNDARY, not the old `fetch_board_cards "`: the quote belonged to
# the calling CONVENTION, not to the call, so `fetch_board_cards $api $token $board` — a
# real, shellcheck-clean way to write it — was invisible to the old derivation. Only
# WHOLE-LINE comments are stripped, so a trailing `… # … fetch_board_cards …` reads as a
# call and REDS. That asymmetry is deliberate: this derivation may over-report, which
# costs a ruling, and must never under-report, which costs nothing and says nothing.
CALL_RE='(^|[^[:alnum:]_])fetch_board_cards([^[:alnum:]_]|$)'
# An ARM is an EMITTING line on the call line itself, or within ARM_WINDOW *code* lines
# after it (comments and blanks do not consume the window, so commenting an arm cannot
# push its sibling out of it). The window is a stated bound, sized from the tree: the
# furthest real arm from its call is board-stats' second `case` branch at 8 code lines.
ARM_WINDOW=10
# The emitter vocabulary. `>&2` is in it so an arm using a helper this list does not name
# is still seen whenever it redirects for itself; `<name>+=(` catches board-stats' shape,
# which accumulates its messages into an array instead of printing them.
EMIT_RE='(^|[^[:alnum:]_])(echo|printf|bcs_skip|kb_bcs_log)([^[:alnum:]_]|$)|[[:alnum:]_]+[+]=[(]|>&2'
EMIT_RE_NOPRINTF='(^|[^[:alnum:]_])(echo|bcs_skip|kb_bcs_log)([^[:alnum:]_]|$)|[[:alnum:]_]+[+]=[(]|>&2'

# _derive <file> — one TSV record per derived item, on stdout:
#   CALL <line>
#   ARM  <line> <line text, leading whitespace stripped>
_derive() {
    local f="$1" i j c s t
    local -a L=()
    mapfile -t L < "$f"
    for ((i = 0; i < ${#L[@]}; i++)); do
        s="${L[$i]}"
        [[ "$s" =~ ^[[:space:]]*# ]] && continue
        [[ "$s" =~ $CALL_RE ]] || continue
        printf 'CALL\t%d\n' "$((i + 1))"
        c=0
        # The scan STARTS ON THE CALL LINE, which does not consume the window: the arm
        # this whole class is named for — `cards="$(fetch_board_cards …)" || <claim>` —
        # lives there, and a scan starting one line later cannot see it.
        for ((j = i; j < ${#L[@]} && c < ARM_WINDOW; j++)); do
            t="${L[$j]}"
            if [[ "$j" -gt "$i" ]]; then
                [[ "$t" =~ ^[[:space:]]*# ]] && continue
                [[ "$t" =~ ^[[:space:]]*$ ]] && continue
                c=$((c + 1))
            fi
            [[ "$t" =~ $EMIT_RE ]] || continue
            # A printf whose output is PIPED or captured is a data writer, not a message.
            # Narrow on purpose: it only fires when the line's ONLY emitter evidence is a
            # piped printf, so `echo … | tee` or `printf … >&2 | …` stay arms.
            if [[ "$t" == *"|"* ]] && [[ "$t" =~ (^|[^[:alnum:]_])printf([^[:alnum:]_]|$) ]] \
               && ! [[ "$t" =~ $EMIT_RE_NOPRINTF ]]; then
                continue
            fi
            printf 'ARM\t%d\t%s\n' "$((j + 1))" "${t#"${t%%[![:space:]]*}"}"
        done
    done
}

derived_calls=""      # <file>\t<count>
derived_arms=""       # <file>\t<line>\t<text>
while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    [[ "$rel" == "bin/_kb-board-lib.sh" ]] && continue
    recs="$(_derive "$f")"
    n="$(grep -c $'^CALL\t' <<<"$recs" || true)"
    [[ "${n:-0}" -gt 0 ]] || continue
    derived_calls+="$rel"$'\t'"$n"$'\n'
    while IFS=$'\t' read -r kind line text; do
        [[ "$kind" == "ARM" ]] || continue
        derived_arms+="$rel"$'\t'"$line"$'\t'"$text"$'\n'
    done <<< "$recs"
done < <(find "$ROOT/bin" "$ROOT/hooks" -type f ! -path '*__pycache__*' | sort)
derived_calls="$(printf '%s' "$derived_calls" | sort)"
derived_arms="$(printf '%s' "$derived_arms")"

# ---------------------------------------------------------------------------
echo "== the population is RE-DERIVED, never recalled (denominator: calls) =="
eq "the derived per-consumer invocation counts equal the registry's" \
   "$(printf '%s' "$REGISTERED_CALLS" | sort)" "$derived_calls"
derived_files="$(printf '%s\n' "$derived_calls" | cut -f1 | sort -u)"
eq "the derived consumer FILE set equals the registry's" \
   "$(printf '%s' "$REGISTERED_FILES" | sort -u)" "$derived_files"
# Control: the derivation must be able to SEE a consumer — an empty derived set would
# satisfy nothing above by accident, but it would satisfy a future edit that broke it.
[[ "$(printf '%s\n' "$derived_files" | grep -c .)" -ge 6 ]] \
    && ok "the derivation actually found the consumers (>= 6 files)" \
    || bad "the derivation found almost nothing — the predicate, not the tree, is what changed"
# Control: the call predicate must see a call written WITHOUT the quote the old one
# required, which is how an unquoted new consumer passed a green suite.
_UNQUOTED='cards=$(fetch_board_cards $api $token $board) || echo "board $board unreachable"'
[[ "$_UNQUOTED" =~ $CALL_RE ]] \
    && ok "an UNQUOTED invocation satisfies the call predicate" \
    || bad "the call predicate still answers about the quoting, not about the call"

# ---------------------------------------------------------------------------
echo "== the population is RE-DERIVED, never recalled (denominator: arms) =="
# Every derived emitting line in an arm window is either a REGISTERED arm or an EXPLICIT
# exemption. This is the leg that makes the arm count derived rather than listed: a new
# cause-naming arm added at an ALREADY-registered invocation — which moves no file and no
# call count — lands here with nothing to match and REDS.
arm_total=0
while IFS=$'\t' read -r file line text; do
    [[ -n "$file" ]] || continue
    arm_total=$((arm_total + 1))
    hit=no
    while IFS=$'\t' read -r rfile rarity rmsg; do
        [[ "$rfile" == "$file" ]] || continue
        [[ -n "$rmsg" ]] || continue
        case "$text" in *"$rmsg"*) hit=registered; break ;; esac
    done <<< "$REGISTRY"
    if [[ "$hit" == no ]]; then
        while IFS=$'\t' read -r efile etext; do
            [[ "$efile" == "$file" && "$etext" == "$text" ]] && { hit=exempt; break; }
        done <<< "$EXEMPT_EMITS"
    fi
    [[ "$hit" != no ]] \
        && ok "$file:$line accounted for ($hit) [${text:0:46}…]" \
        || bad "$file:$line emits inside a fetch_board_cards arm window and is in neither the registry nor the exemptions — rule on it: '$text'"
done <<< "$derived_arms"
# Control: the arm derivation must actually be finding arms.
[[ "$arm_total" -ge 8 ]] \
    && ok "the arm derivation found the tree's arms ($arm_total >= 8)" \
    || bad "the arm derivation found $arm_total emitting lines — the predicate, not the tree, is what changed"
# The converse, which is what keeps ARM_WINDOW honest: a registered arm that is no longer
# INSIDE the derived window is a derivation that has quietly stopped covering it.
while IFS=$'\t' read -r file arity msg; do
    [[ -n "$file" ]] || continue
    found=false
    while IFS=$'\t' read -r dfile dline dtext; do
        [[ "$dfile" == "$file" ]] || continue
        case "$dtext" in *"$msg"*) found=true; break ;; esac
    done <<< "$derived_arms"
    eq "$file: the registered arm is INSIDE the derived window [${msg:0:46}…]" "true" "$found"
done <<< "$REGISTRY"

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
    is_outcome "$msg" && ok "$file: says WHAT happened in a ruled phrasing [${msg:0:46}…]" \
                      || bad "$file: a multi-rc arm must name a ruled OUTCOME phrasing — '$msg'"
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
# The clause that extends the rule from messages to caller-side COMMENTS. Nothing here
# enforces it — comments are outside this test's population, stated at the top — so the
# assertion is that the rule still SAYS it, which is what makes the reading cheap.
eq "…and binds a caller-side COMMENT that states an arm's rc set" "true" \
   "$(has 'THE SAME CONSTRAINT BINDS A CALLER-SIDE COMMENT' "$lib")"
eq "…and points at this test as the dispositions' owner"    "true" "$(has 'fetch-board-cards-caller-claims-selftest.sh' "$lib")"
# The rc contract the rule is derived from must still enumerate rc 4 — the rc a second,
# drifted copy of that contract had lost, and the one every bare `||` arm silently catches.
eq "the rc contract still enumerates rc 4 (SHORT READ)"     "true" "$(has '4  SHORT READ' "$lib")"
# ONE contract, not two. Two legs, because neither alone is the property:
#   (a) STRUCTURAL — each rc is stated on exactly one contract line, so a second copy of
#       the list cannot be added beside the first;
#   (b) the historical LITERAL, kept as a negative control pinned to the copy that
#       actually drifted (only it named rc 4, and the two had already diverged).
# Honest bound: a re-minted contract worded as PROSE, on lines that do not take the
# contract's shape, satisfies both. (a) closes the shape that recurred; it is not a
# guarantee that no paraphrase exists.
rc_contract_lines() { grep -cE '^#   [0-4]  ' <<<"$1"; }
eq "the rc contract is stated on exactly 5 lines, one per rc" "5" "$(rc_contract_lines "$lib")"
for n in 0 1 2 3 4; do
    eq "rc $n is stated on exactly one contract line" "1" "$(grep -cE "^#   $n  " <<<"$lib")"
done
# Control: the counter must be able to SEE a duplicate contract — otherwise "5" above is
# a number the predicate would print over any header at all.
eq "the contract counter sees a duplicated contract (control)" "10" \
   "$(rc_contract_lines "$lib"$'\n'"$lib")"
eq "there is no second copy of the rc contract in the header" "0" \
   "$(grep -c 'rc contract: 0 complete' <<<"$lib" || true)"

# ---------------------------------------------------------------------------
_summary "fetch-board-cards-caller-claims-selftest"
