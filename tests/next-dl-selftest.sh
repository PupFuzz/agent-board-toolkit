#!/usr/bin/env bash
# next-dl-selftest.sh — deterministic, network-free unit checks for next-dl's
# highest-int-in-a-stream primitives `max_int` and `max_dl`.
#
# next-dl runs its main at top level (arg-parse on source), so it is never sourced
# whole — lift just the two one-liner functions out of it (the extract-and-exercise
# pattern promote-pagination-selftest uses on fetch_whole_board). max_int is the
# shared tail of BOTH offline max scans (the CLAUDE_DECISIONS.md `## DL-NNN` header
# scan and the board `dl_number` scan); it undercounted-silently would let next-dl
# re-mint a used DL, so its leading-zero-strip and its DL-only filter are pinned here.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
NDL="$HERE/../bin/next-dl"
_need -r "$NDL"

# Lift the two one-liner primitives (never meant to be sourced with the whole script).
ndl_src="$(grep -E '^(max_int|max_dl)\(\) \{' "$NDL")"
[[ "$(printf '%s\n' "$ndl_src" | wc -l)" -eq 2 ]] \
    || { echo "selftest: expected to lift max_int + max_dl from $NDL — did they get renamed?" >&2; exit 1; }
eval "$ndl_src"

echo "== max_int — highest integer in a stream, leading zeros stripped =="
eq "picks the true max"                     "90" "$(printf '7\n90\n3\n'      | max_int)"
eq "ignores leading zeros when comparing"   "90" "$(printf '007\n90\n003\n'  | max_int)"
# The zero-strip is a FORMAT contract, not just ordering: sort -n reads 007 as 7 either way,
# so these red only if the `sed 's/^0*//;s/^$/0/'` is dropped (the output keeps a padded form).
eq "strips leading zeros from the winner"   "7"  "$(printf '007\n003\n'      | max_int)"
eq "a bare zero survives the strip (^\$->0)" "0"  "$(printf '0\n'            | max_int)"
eq "empty stream → empty output"            ""   "$(printf ''                | max_int)"

echo "== max_dl — only DL-prefixed tokens (a bare number must NOT leak) =="
# The DL- filter is the whole point: fed a stream that mixes prose numbers with DL tokens,
# max_dl must count ONLY the DL tokens. Reds if the 'DL-' grep is weakened to plain digits.
eq "counts only DL tokens, ignores prose ints" "40" "$(printf 'see PR 999\nDL-40\nDL-7\n' | max_dl)"
eq "strips zeros via the shared max_int tail"  "7"  "$(printf 'DL-007\n'                  | max_dl)"
eq "no DL tokens → empty"                      ""   "$(printf 'nothing to see, 123\n'     | max_dl)"

_summary "next-dl-selftest"
