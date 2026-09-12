#!/usr/bin/env bash
# single-row-projection-census.sh — a CENSUS INSTRUMENT, not a gate. It re-derives the population
# of one defect class across `tests/` and prints it. It asserts nothing about that population and
# is deliberately NOT named `*-selftest.sh`, so `ci-matrix-parity-selftest.sh`'s orphan gate
# (whose population IS `tests/*-selftest.sh`) does not claim it, `suite-home-containment`'s
# `*selftest*` glob does not run it, and it is wired into no workflow. Same shape, and for the
# same reason, as `readback-before-success-census.sh` and `hand-enumerated-population-census.sh`.
#
# THE DEFECT CLASS (card#9173). An assertion whose NAME claims a property of every row reads ONE
# row — `jq '.[0].foo'` — so the claim spans a population of one. A key emitted on some row but
# not the first, a value correct on the first carrier and wrong on the second, a shape that
# varies per row: each satisfies the probe and each is exactly what the assertion said could not
# happen. Four instances were fixed across card#9173's rounds and the fifth review found two more
# still standing, one of them inside the block the previous round had just rewritten — which is
# why the figure moved out of the prose and into this file.
#
# ⛔ WHY THIS IS A CENSUS AND NOT A GATE. The class is not mechanically decidable. Whether `.[0]`
# is a narrowing depends on what the assertion's NAME claims and on whether the fixture holds more
# than one candidate row — the first is English, the second needs the fixture evaluated. What IS
# mechanically decidable is the SHAPE of each site, which is what this file reports: it sorts the
# population into buckets that need no human judgement, and prints the remainder — the sites where
# a human still has to read the name against the fixture — rather than guessing at them. A gate
# over this population would need a suppression list, and a hand list that cannot red on a new
# member is card#6645's class, i.e. it would mint the defect one layer over.
#
# ⭐ WHY IT EXISTS AT ALL, given the instances are fixed. The population is not fixed: every new
# assertion in `tests/` is a new candidate, and a population re-derived only when somebody
# remembers to is a population nobody is measuring. This is the method by which a later pass
# RE-COMPUTES it — cheap enough to actually run — rather than a number in a PR body that was
# already wrong twice (a round published "60" and "64" for the same population, and classified 42
# sites as an idiom that only 16 of them used).
#
# ⛔ WHY EVERY SWEEP HERE USES `command grep`. In an interactive Claude Code shell `grep` is a
# shell FUNCTION that execs `ugrep --ignore-files`, which silently honours `.gitignore` and still
# exits 0 — a truncated sweep that looks exactly like a clean result.
#
# WHAT A RUN HERE CANNOT SEE, stated so a clean REMAINDER is not read as a clean audit:
#   * whether an assertion's NAME claims more than its probe observes — that is the defect, and
#     it is English; this file can only put the site in front of a reader.
#   * whether the fixture under a site holds more than one candidate row. A `.[0]` over a
#     genuinely single-row fixture is not a narrowing at all.
#   * a narrowing spelled some other way — `first(...)`, `head -1`, `| .[]` piped into a probe
#     that reads one value, an `eq` over a single id. The sweep is one spelling.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"

# The population is every shell file under tests/, minus THIS file — whose own sweep patterns
# contain the spelling being swept for, and would be reported as sites of themselves. That is one
# exclusion, derived from $BASH_SOURCE rather than written down, so it cannot go stale.
mapfile -t FILES < <(find "$HERE" -maxdepth 1 -type f -name '*.sh' ! -name "$SELF" | sort)

printf 'single-row-projection census — population: %s file(s) under tests/, excluding %s\n\n' \
    "${#FILES[@]}" "$SELF"

total=0; comment=0; narrowed=0; positional=0; keyset=0; remainder=0
REMAINDER_LINES=""; KEYSET_LINES=""

for f in "${FILES[@]}"; do
    rel="tests/$(basename "$f")"
    while IFS=: read -r ln text; do
        [[ -n "${ln:-}" ]] || continue
        total=$((total + 1))
        case "$text" in
            *'#'*) # a leading-# line is prose about the class, not a probe of it
                if [[ "$text" =~ ^[[:space:]]*# ]]; then comment=$((comment + 1)); continue; fi ;;
        esac
        if [[ "$text" == *'select('* ]];              then narrowed=$((narrowed + 1)); continue; fi
        if [[ "$text" == *'.[1]'* || "$text" == *'.[2]'* ]]; then positional=$((positional + 1)); continue; fi
        if [[ "$text" == *keys* ]]; then
            keyset=$((keyset + 1))
            KEYSET_LINES+="    $rel:$ln"$'\n'
            continue
        fi
        remainder=$((remainder + 1))
        REMAINDER_LINES+="    $rel:$ln"$'\n'
    done < <(command grep -n '\.\[0\]' "$f" || true)
done

printf 'sites carrying `.[0]`                                  %4d\n' "$total"
printf '  prose (a leading-# line, not a probe)                %4d\n' "$comment"
printf '  key-narrowed — a select() on the same line picks the\n'
printf '    row and `.[0]` unwraps the singleton it produced   %4d\n' "$narrowed"
printf '  positional — `.[1]`/`.[2]` on the same line, so the\n'
printf '    index is a tuple field, not a row choice           %4d\n' "$positional"
printf '  KEY SET read off one row (`.[0] | keys`) — the shape\n'
printf '    card#9173 fixed four times; expected to be 0       %4d\n' "$keyset"
printf '  remainder — a human must read the NAME against the\n'
printf '    fixture; this file does not rule on these          %4d\n' "$remainder"
printf '\n'

if [[ -n "$KEYSET_LINES" ]]; then
    printf 'KEY SET off one row — read each against its fixture:\n%s\n' "$KEYSET_LINES"
fi
if [[ -n "$REMAINDER_LINES" ]]; then
    printf 'REMAINDER — undisposed by this instrument, by design:\n%s\n' "$REMAINDER_LINES"
fi
printf 'This run says nothing about whether any remainder site is a defect. It reports where the\n'
printf 'spelling is, so the reading is over a derived population rather than a recalled one.\n'
