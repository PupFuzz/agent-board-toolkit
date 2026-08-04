#!/usr/bin/env bash
# readme-bin-coverage-selftest.sh — assert README's "What's here" table lists exactly the
# public tools in bin/, and that bin/ holds exactly the tools it lists.
#
# WHY THIS FILE EXISTS. That table is the toolkit's ONLY enumeration of bin/, and until
# card#5374 nothing asserted it matched. `git grep -ln 'README.md' -- tests/ .github/`
# returned no hits: the inventory an adopter reads was maintained by diligence alone. It
# drifted in BOTH directions, measurably, and neither was found by a tool:
#   * PHANTOM  — a row for a tool that no longer exists. `board-transition-sync` survived 23
#                releases after v0.9.0 retired it (card#5359, #55/card#3649).
#   * OMISSION — a bin with no row. `agent-board-toolkit-runtime-check` shipped in v0.15.0,
#                documented in docs/INSTALL.md §2 and VERSIONING.md, and was never given a
#                row. Found by comparing the two sets BY HAND during card#5359 — a grep
#                cannot find an omission, because there is no term to grep for.
# card#5359 then made this table the SINGLE list (ADOPTION.md points at it instead of
# keeping a second copy), so a drifted table is now the whole inventory being wrong with no
# second copy left to contradict it.
#
# BOTH DIRECTIONS ARE EQUALLY LOAD-BEARING HERE. That is a real difference from
# ci-matrix-parity-selftest.sh, whose `dangling` leg only sharpens a failure CI already
# reports loudly — do not copy that file's "one leg is the reason this exists" framing into
# this one. Nothing else in the repo reports EITHER direction of this drift, and each has
# already shipped once.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support: that
# the two NAME SETS agree. It proves nothing whatsoever about whether a row's prose is
# accurate, current, or describes what the tool now does. A green run must never be reported
# as "README is verified correct"; it means "README lists every tool and invents none".
#
# TWO EXCLUSIONS, BOTH DELIBERATE AND BOTH STATED — neither is a side effect of a regex:
#   1. `_`-prefixed entries in bin/ are not tools: the private lib + the python helpers
#      (`_kb-board-lib.sh`, `_kbc-archive-lib.py`, `_kbc-archive-eligible.py`,
#      `_kbc-may-archive.py`) are implementation, deliberately undocumented as tools. The
#      rule is the NAME, applied to every directory entry — `__pycache__` is `_`-prefixed and
#      is a DIRECTORY, so this must not assume an entry is a file. The rule itself lives in
#      `_bin-set-lib.sh` (`_public_bin_names`) because runtime-check's TOOLS gate needs the
#      identical set; WHY it is right *here* is this paragraph and stays here.
#   2. Table rows not keyed by `bin/…` are out of scope — today exactly one,
#      `promote/action.yml`, a real row for a real artifact that simply does not live in
#      bin/. It is dropped by a NAMED partition step, not by a `^| \`bin/` pattern that would
#      silently swallow it, and the live out-of-scope set is PRINTED on every run so the
#      exclusion stays visible rather than becoming folklore.
#
# The extraction is scoped to the ONE section, not the whole file: a `bin/…` row appearing
# under some other heading would otherwise satisfy this check while the inventory table
# itself stayed incomplete — an err-GREEN hole. Section-scoping errs RED instead (rename the
# heading and the extraction goes empty, which the positive control below fails on).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_bin-set-lib.sh"

README="$HERE/../README.md"
BINDIR="$HERE/../bin"
_need -r "$README"
_mktmp_scratch

# _table_rows <readme> — every first-column code-span key of the "What's here" table,
# C-collated. The header row (`| Tool | Role |`) and the `|---|---|` separator carry no
# code span and are skipped by the same pattern that selects the keys.
_table_rows() {
    awk -v heading="## What's here" '
        { line = $0; sub(/[[:space:]]+$/, "", line) }
        line == heading { inside = 1; next }
        inside && /^## / { exit }
        inside && /^\|[[:space:]]*`[^`]+`[[:space:]]*\|/ {
            key = $0
            sub(/^\|[[:space:]]*`/, "", key)
            sub(/`.*$/, "", key)
            print key
        }
    ' "$1" | LC_ALL=C sort
}

# _bin_rows <readme> — exclusion 2 applied: the table keys under bin/, prefix stripped.
# This is the set compared against disk. `sed -n …p` both filters and strips in one step;
# a key like `bin/a/b` survives as `a/b`, matches no basename, and reads as a phantom (red).
_bin_rows() { _table_rows "$1" | sed -n 's|^bin/||p' | LC_ALL=C sort; }

# _nonbin_rows <readme> — the complement: table keys that name something outside bin/.
# Never compared; printed, so exclusion 2 is observable on every run.
_nonbin_rows() { _table_rows "$1" | grep -v '^bin/' || true; }

# The required set is `_public_bin_names` from `_bin-set-lib.sh` — exclusion 1 above IS that
# rule, and runtime-check's TOOLS gate compares against the same one. Two properties of it are
# load-bearing HERE specifically, so they are restated where they are relied on: a `_`-prefixed
# DIRECTORY is excluded by the name rule rather than by a file-type filter (so a non-`_`
# directory in bin/ still enters the set and reads as undocumented), and the set is not
# filtered to executables (a tool that lost its +x bit must not drop out of the required set
# and take this check green on a README that no longer documents it).
#
# `comm` validates its inputs' order in the AMBIENT locale, so it is pinned to C alongside
# both producers, not merely for tidiness: en_US.UTF-8 ignores punctuation in its primary
# collation pass and orders `-`-bearing names differently from codepoint order, which makes
# comm report "not in sorted order" and emit an unreliable diff.
undocumented() { LC_ALL=C comm -23 <(_public_bin_names "$2") <(_bin_rows "$1"); }
phantom()      { LC_ALL=C comm -13 <(_public_bin_names "$2") <(_bin_rows "$1"); }

# ---------------------------------------------------------------------------
# Positive control FIRST. Every live assertion below is an assertion of ABSENCE ("no
# undocumented tools"), and an empty answer is indistinguishable from an extraction that
# returned nothing at all — a heading rename, a table reformat, or a bad glob would make
# every absence check pass. Prove both streams carry real data before trusting any emptiness.
# ---------------------------------------------------------------------------
echo "== positive control — both streams are non-empty and carry a known member =="
rows="$(_table_rows "$README")"
bins="$(_public_bin_names "$BINDIR")"
eq "README table extraction is non-empty" "false" "$([ -z "$rows" ] && echo true || echo false)"
eq "bin/ enumeration is non-empty"        "false" "$([ -z "$bins" ] && echo true || echo false)"
# A named member, not a count: a count pins the check to a past value and goes stale as the
# toolkit grows, whereas a member that must be present re-derives nothing and cannot rot.
eq "README table extraction contains a known row key" "true" \
   "$(printf '%s\n' "$rows" | grep -qx 'bin/kbcard' && echo true || echo false)"
eq "bin/ enumeration contains a known tool" "true" \
   "$(printf '%s\n' "$bins" | grep -qx 'kbcard' && echo true || echo false)"

# Exclusion 1, asserted on the live tree: the absence claim is paired with its presence
# witness, and the witness is OBSERVED present first — otherwise "not in the public set"
# would also pass for a file that simply isn't there.
eq "witness: bin/_kb-board-lib.sh is present on disk" "true" \
   "$([ -e "$BINDIR/_kb-board-lib.sh" ] && echo true || echo false)"
eq "…and is excluded from the public set" "" \
   "$(printf '%s\n' "$bins" | grep -x '_kb-board-lib.sh' || true)"

# ---------------------------------------------------------------------------
# The live assertions.
# ---------------------------------------------------------------------------
echo "== README's What's here table and bin/ hold the same tool set =="
eq "every bin/ tool has a README row (add one to § What's here for any name below)" "" \
   "$(undocumented "$README" "$BINDIR")"
eq "every bin/ README row has a tool (drop the row for any name below)" "" \
   "$(phantom "$README" "$BINDIR")"

echo "== rows deliberately OUT OF SCOPE — real rows that name something outside bin/ =="
_nonbin_rows "$README" | sed 's/^/   /'

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL. Each leg is pointed at a fixture carrying the exact defect it claims to
# catch. Without this, a check that answers "" for structural reasons reads identically to
# one that answered "" because the repo is clean — an empty diff is a measurement that never
# happened until it has been shown able to be non-empty.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: a bin/ tool with no README row is REPORTED =="
mkdir -p "$TMP/bin-omit"
# One documented tool + one README has never heard of. The documented file is the presence
# witness: it must NOT appear in the output, which is what shows the comparison ran against
# real README data rather than against an empty set.
touch "$TMP/bin-omit/kbcard" "$TMP/bin-omit/ghost-tool"
eq "an undocumented tool is named" "ghost-tool" "$(undocumented "$README" "$TMP/bin-omit")"
eq "the DOCUMENTED sibling is not named (witness: the comparison saw README)" "" \
   "$(undocumented "$README" "$TMP/bin-omit" | grep -x 'kbcard' || true)"

echo "== prove-it-can-fail: a README row with no bin/ tool is REPORTED =="
# Injected as a literal table row into a copy of the real README — a regenerated table would
# assert this against the fixture's own formatting rather than against the file maintainers
# actually edit.
awk '{ print }
     /^\| `bin\/kbcard` \|/ { print "| `bin/phantom-tool` | injected by readme-bin-coverage-selftest |" }' \
    "$README" > "$TMP/README-phantom.md"
eq "the fixture actually injected the phantom row" "true" \
   "$(grep -q '^| `bin/phantom-tool` |' "$TMP/README-phantom.md" && echo true || echo false)"
eq "a phantom row is named" "phantom-tool" "$(phantom "$TMP/README-phantom.md" "$BINDIR")"
eq "the omission leg stays clean on that fixture (the two legs are independent)" "" \
   "$(undocumented "$TMP/README-phantom.md" "$BINDIR")"

echo "== prove-it-can-fail: exclusion 1 covers a DIRECTORY, and only by its name =="
# `__pycache__` is gitignored, so it is absent from a fresh CI checkout and present on a
# maintainer's host — asserting against the live tree would prove different things in the two
# places. A fixture makes the directory case deterministic in both.
mkdir -p "$TMP/bin-dir/__pycache__" "$TMP/bin-dir/realdir"
touch "$TMP/bin-dir/kbcard"
eq "witness: the fixture's _-prefixed entry is a directory, and is present" "true" \
   "$([ -d "$TMP/bin-dir/__pycache__" ] && echo true || echo false)"
# `realdir` is in the expected output on purpose: a non-`_` directory is NOT silently
# dropped. It enters the required set and reads as undocumented (red), forcing an explicit
# decision — the alternative, a -type f filter, would make it vanish with no signal.
eq "a _-prefixed directory is excluded; a non-_ directory is not" "$(printf 'kbcard\nrealdir')" \
   "$(_public_bin_names "$TMP/bin-dir")"

echo "== prove-it-can-fail: exclusion 2 drops a non-bin/ row, and keeps the bin/ ones =="
# A standalone fixture, not the live README: this proves the PARTITION's behaviour, so it
# stays honest if `promote/action.yml` is ever the row that changes.
cat > "$TMP/README-nonbin.md" <<'MD'
# fixture

## What's here

| Tool | Role |
|---|---|
| `bin/kbcard` | a row inside bin/ |
| `promote/action.yml` | a real row that names something outside bin/ |

## Next section

| `bin/out-of-section` | must not be seen — this table is under another heading |
MD
eq "witness: the extractor DOES see the non-bin/ row" "true" \
   "$(_table_rows "$TMP/README-nonbin.md" | grep -qx 'promote/action.yml' && echo true || echo false)"
eq "…and the compared set excludes it" "kbcard" "$(_bin_rows "$TMP/README-nonbin.md")"
eq "the out-of-scope row is reported, not silently dropped" "promote/action.yml" \
   "$(_nonbin_rows "$TMP/README-nonbin.md")"
eq "a row under a LATER heading is not seen (section scoping)" "" \
   "$(_table_rows "$TMP/README-nonbin.md" | grep -x 'bin/out-of-section' || true)"

_summary "readme-bin-coverage-selftest"
