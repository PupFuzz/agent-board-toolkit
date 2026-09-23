# shellcheck shell=bash
# _frozen-region-lib.sh — the ONE split of a doc into its LIVE region and its FROZEN,
# append-only per-version record, for the gates whose population is "what this repo currently
# CLAIMS" rather than "what it claimed at some version".
#
# Sourced after `_selftest-prelude.sh`, alongside it — `_contains` calls that file's `has`.
#
# WHY IT IS A LIB (card#9957). `lib-set-derivation-selftest.sh` wrote this split for
# `docs/UPGRADE.md` and `docs/CHANGELOG.md`, and `source-precedence-pin-selftest.sh` needs the
# same split over the same two files for a different class. Canon #5 says extract at the SECOND
# real caller, and a second hand-spelling of a carve would be especially perverse here: the card
# the second caller closes is about a rule restated with nothing holding the copies equal.
#
# The reasoning each function carries is the first caller's, moved rather than rewritten — the
# `⛔ THE CUT IS BY HEADING TEXT` note records a measured regression and belongs with the code.

# _headings <file> <ere> — the `<lineno>:<text>` lines of <file> whose text matches <ere>.
# The `|| true` is what makes "no heading matched" an ASSERTABLE state instead of a death: under
# `set -e` + `pipefail` grep's rc 1 kills the assignment at the call site. The guard this replaced
# — `[[ -n "$cut" ]] || { printf ... ; exit 1; }` — could never fire for exactly that reason.
_headings() { grep -nE "$2" "$1" || true; }

# _carve <file> <ere> <live-out> <frozen-out> — split <file> at its FIRST line matching <ere>:
# everything ABOVE that line is the LIVE region, that line and everything below is the FROZEN one.
# BOTH halves are written, because the frozen half is the witness that the cut landed on the
# heading the caller says it did.
#
# ⛔ THE CUT IS BY HEADING TEXT, NEVER BY A SECTION NUMBER. `docs/UPGRADE.md` was split on `^## 6\.`
# while one sentence beside it called the split "derived, not a line number" (the file mentioned
# the split three times; only that one made the claim): only the OFFSET was
# derived — the 6 was a hand-kept fact, i.e. this file's own subject, inside this file. Measured:
# inserting a new LIVE `## 6.` section carrying an enumeration line and renumbering the history to
# `## 7.` left the whole run rc 0 all-green while the live region silently SHRANK, because the only
# premise beside the cut asserted what the live region LACKS — a direction that can catch a too-WIDE
# cut and never a too-narrow one. Each caller now also asserts how many headings matched and that
# the matched one is in the frozen complement, which is the missing direction.
#
# No match at all ⇒ the whole file is LIVE and the frozen half is empty. Fail-CLOSED: leg 3 then
# scans everything (reporting more, never less) while the caller's count assertion reds.
_carve() {
    local file="$1" pat="$2" live="$3" frozen="$4" cut
    cut="$(_headings "$file" "$pat" | head -n 1 | cut -d: -f1)"
    if [[ -z "$cut" ]]; then
        cp "$file" "$live"; : > "$frozen"; return 0
    fi
    sed -n "1,$((cut - 1))p" "$file" > "$live"
    sed -n "$cut,\$p" "$file" > "$frozen"
}

# _contains <needle> <file> — `has` against a file's contents, with an EMPTY needle answering
# false. `has ""` matches anything, so a presence witness built from a heading that was never
# found would pass at exactly the moment the split it witnesses had failed.
_contains() { [[ -n "$1" ]] || { echo false; return 0; }; has "$1" "$(cat "$2")"; }
