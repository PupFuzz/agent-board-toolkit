#!/usr/bin/env bash
# help-output-selftest.sh — deterministic, network-free checks that every CLI's `--help`
# prints its WHOLE header comment and nothing below it.
#
# WHY THIS FILE EXISTS. Both release movers printed their header with a FIXED line range
# (`sed -n '2,20p'`). A fixed range is silently wrong in both directions: it truncates once
# the header outgrows it, and it leaks code once the header shrinks. promote-released-cards'
# header reached 43 lines while the range still said 20, so `--help` stopped at line 20 and
# never reached `Usage:` at line 35 — the single block a `--help` user most needs. Nothing
# caught it because nothing asserted the output at all (card#5145, roundtable #161 item 2).
#
# The assertion is deliberately an EQUALITY on the line count, not a range or a
# contains-check. A "prints at least N lines" or "contains Usage:" assertion passes while
# truncating everything after the match — that is exactly the class of assertion that let
# this survive. Comparing against the file's own contiguous-leading-comment count means the
# check re-derives the expected length from the file on every run, so it cannot go stale as
# the header grows.
#
# The LEAK direction is not hypothetical: agent-board-toolkit-runtime-check, missed by that
# card's sibling audit, carried `sed -n '2,30p'` over a 28-line header and printed
# `set -euo pipefail` as its last --help line (card#5334).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

# The CLIs whose --help prints a leading comment header.
CLIS=(promote-released-cards release-pr-body agent-board-toolkit-runtime-check)

# header_lines <file>: the count of contiguous comment lines after the shebang — the
# authoritative expected length, re-derived from the file itself.
header_lines() { awk 'NR>1 { if (substr($0,1,1) == "#") c++; else exit } END { print c+0 }' "$1"; }

for cli in "${CLIS[@]}"; do
    bin="$HERE/../bin/$cli"
    _need -x "$bin"

    echo "== $cli --help =="
    out="$("$bin" --help)"
    got="$(printf '%s\n' "$out" | wc -l)"
    want="$(header_lines "$bin")"

    eq "$cli: --help prints the ENTIRE header (line-count equality)" "$want" "$got"
    eq "$cli: --help reaches the Usage: block"      "true"  "$(case "$out" in *"Usage:"*) echo true ;; *) echo false ;; esac)"
    # Everything below the header is implementation, not user-facing help. `set -euo
    # pipefail` is the first line after every header, so it is the canary for over-printing.
    eq "$cli: --help does not leak code past the header" "false" \
       "$(case "$out" in *"set -euo pipefail"*) echo true ;; *) echo false ;; esac)"
    # -h is the documented alias; assert it is the same output, not merely non-empty.
    eq "$cli: -h is identical to --help"            "true"  "$([ "$("$bin" -h)" = "$out" ] && echo true || echo false)"
done

_summary "help-output-selftest"
